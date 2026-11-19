"use strict";
const markerBounds = require("./marker-bounds");
const assert = require("node:assert/strict"), fs = require("node:fs"), path = require("node:path"), vm = require("node:vm");
const root = path.resolve(__dirname, "../..");
const source = fs.readFileSync(path.join(root, "tools/probes/Probe-MarkerRestore.jsx"), "utf8");
const host = fs.readFileSync(path.join(root, "extension/jsx/host.jsx"), "utf8");
const parser = {};
vm.runInNewContext(process.binding("natives")["internal/deps/acorn/acorn/dist/acorn"], { exports: parser, module: { exports: parser } });
parser.parse(source, { ecmaVersion: 3 });
const TICKS = 254016000000, TAG = "[PremiereVoiceSync:marker-restore:v1]", SCOPE = "probe-tagged-only";
const args = ['project"1', "media-1", TAG, SCOPE];

function fixture(useHost = false, fault = "") {
    let id = 0, tagWrites = 0;
    const items = [], events = [];
    function marker(seconds, comments = "", name = "") {
        const bounds = markerBounds({}, seconds, seconds, id % 2 === 0);
        let color = 0, rangeWrites = 0;
        const m = { guid: "m" + id++, type: "Comment",
            get comments() { return comments; },
            set comments(v) {
                events.push(["comments", m.guid]);
                if (fault === "tag" && ++tagWrites === 2) throw Error("tag write failed");
                comments = v;
            },
            get name() { return name; },
            set name(v) { events.push(["name", m.guid]); name = v; },
            get start() { return bounds.start; },
            set start(v) { events.push(["start", m.guid]); bounds.start = v; },
            get end() { return bounds.end; },
            set end(v) {
                events.push(["end", m.guid]);
                if (fault === "end" && comments.endsWith("move-range") && ++rangeWrites === 3) v += 1 / TICKS;
                bounds.end = v;
            },
            getColorByIndex() { return color; },
            setColorByIndex(v) { events.push(["color", m.guid]); color = v; }
        };
        items.push(m);
        return m;
    }
    const manual = marker(12, 'manual "note"\n\t\u2028', "manual");
    marker(48, TAG + "-different-tag", "similar");
    const collection = { getFirstMarker: () => items[0], getNextMarker: m => items[items.indexOf(m) + 1],
        createMarker(seconds) {
            events.push(["create"]);
            return fault === "existing" ? manual : marker(seconds);
        },
        deleteMarker(m) {
            assert.equal(m.comments.split("\n")[0], TAG);
            events.push(["delete", m.guid]);
            if (fault !== "delete-noop") items.splice(items.indexOf(m), 1);
        }
    };
    const item = { type: 1, nodeId: args[1], name: "media", isSequence: () => false, getMarkers: () => collection };
    const sequenceItem = { type: 1, nodeId: "sequence", isSequence: () => true, getMarkers() { throw Error("Sequence markers accessed"); } };
    const children = [item, sequenceItem]; children.numItems = children.length;
    const project = { documentID: args[0], rootItem: { children } };
    for (const field of ["save", "saveAs", "undo", "sequences"]) {
        Object.defineProperty(project, field, { get() { throw Error("Forbidden access: " + field); } });
    }
    let activeReads = 0;
    const time = (seconds, ticks) => Object.freeze({ seconds, ticks: String(ticks) });
    const clip = Object.freeze({ nodeId: "c1", start: time(1 + 0.5 / TICKS, TICKS), end: time(2, 2 * TICKS),
        inPoint: time(0.5, TICKS / 2), outPoint: time(1.5, 1.5 * TICKS), getSpeed: () => 125 });
    const clips = { 0: clip, 1: {...clip, nodeId:"c2", getSpeed: () => 0.8}, numItems: 2 };
    Object.defineProperty(project, "activeSequence", { get() {
        activeReads++;
        return { sequenceID: "seq", timebase: TICKS / 30, audioTracks: { 0: { clips }, numTracks: 1 } };
    } });
    const context = vm.createContext({ $: {}, app: { project } });
    if (useHost) vm.runInContext(host, context);
    else context.JSON = undefined;
    vm.runInContext(source, context);
    assert.equal(activeReads, 0);
    assert.deepEqual(events, []);
    const api = context.$._PVSMarkerRestoreProbe;
    const call = (method, ...values) => JSON.parse(api[method](...values));
    const snapshot = () => items.map(m => [m.guid, m.start.seconds, m.end, m.name, m.comments, m.type, m.getColorByIndex()]);
    return { call, events, items, marker, snapshot, get activeReads() { return activeReads; } };
}

const writeLogs = [];
for (const useHost of [false, true]) {
    const f = fixture(useHost), before = f.snapshot();
    const listed = f.call("list");
    assert.deepEqual(listed.items, [{ nodeId: args[1], name: "media" }]);
    assert.equal(listed.documentId, args[0]);
    assert.equal(listed.tag, TAG);
    const projection = f.call("projection", 0);
    assert.equal(projection.ok, true);
    assert.equal(projection.fps, 30);
    assert.equal(projection.timebase, String(TICKS / 30));
    assert.equal(projection.sequenceId, "seq");
    assert.equal(projection.speedSource, useHost ? "host" : "replicated");
    assert.equal(projection.clipCount, 2);
    assert.deepEqual(projection.clips.map(clip => clip.speed), [1.25, 0.8]);
    const delta = (1 + 0.5 / TICKS - 1) * TICKS;
    assert.deepEqual(projection.clips[0].start, { seconds: 1 + 0.5 / TICKS, ticks: String(TICKS), tickSeconds: 1, frame: 30,
        frameSeconds: 1, deltaVsTicks: delta, deltaVsRoundedFrameTicks: delta });
    assert.equal(projection.clips[0].end.frame, 60);
    assert.equal(projection.clips[0].inPoint.frame, 15);
    assert.equal(projection.clips[0].outPoint.frame, 45);
    assert.equal(f.call("projection", 1).ok, false);
    assert.deepEqual(f.events, []);
    const activeReads = f.activeReads, result = f.call("run", ...args);
    assert.equal(result.ok, true, JSON.stringify(result));
    assert.equal(result.markerToolsSource, useHost ? "host" : "replicated");
    assert.deepEqual(result.cases.map(c => c.id), ["move-point", "move-range", "recreate", "color"]);
    assert.equal(result.cases[0].requestedSeconds, 1234 / 29.97);
    for (const c of result.cases) {
        assert.deepEqual(c.differences, []);
        assert.equal(c.fingerprintMatches, true);
        assert.equal(c.prior.guid === c.actual.guid, c.id !== "recreate");
    }
    const range = result.cases[1], recreated = result.cases[2], color = result.cases[3];
    assert.notEqual(range.modified.end - range.modified.seconds, range.prior.end - range.prior.seconds);
    assert.notEqual(color.modified.color, color.prior.color);
    assert.deepEqual(f.events.filter(([, guid]) => guid === range.prior.guid).map(([name]) => name),
        ["comments", "name", "end", "color", "start", "end", "start", "end", "delete"]);
    assert.deepEqual(f.events.filter(([, guid]) => guid === recreated.actual.guid).map(([name]) => name),
        ["end", "name", "comments", "color", "delete"]);
    assert.equal(result.cleanup.verified, true);
    assert.equal(result.cleanup.attempted, 4);
    assert.deepEqual(f.snapshot(), before);
    assert.equal(f.activeReads, activeReads, "Marker commands must never access clips or sequences.");
    writeLogs.push(f.events);
}
assert.deepEqual(writeLogs[0], writeLogs[1], "Standalone and real host restore have the same mock write order.");

for (const useHost of [false, true]) {
    const f = fixture(useHost, "end"), before = f.snapshot(), result = f.call("run", ...args);
    assert.equal(result.ok, false);
    assert.equal(result.cases.length, 4);
    const range = result.cases[1];
    assert.equal(range.fingerprintMatches, false);
    const { actual, prior, differences } = range;
    assert.deepEqual(differences, [{ field: "end", actual: actual.end, prior: prior.end, deltaTicks: (actual.end - prior.end) * TICKS }]);
    assert(differences[0].deltaTicks > 0);
    assert(result.cleanup.verified);
    assert.deepEqual(f.snapshot(), before);
}
{
    const f = fixture(), before = f.snapshot();
    for (const values of [["other", ...args.slice(1)], [args[0], "sequence", TAG, SCOPE],
        [args[0], args[1], TAG + "x", SCOPE], [args[0], args[1], TAG, "other"]]) {
        assert.equal(f.call("run", ...values).ok, false);
        assert.equal(f.call("cleanup", ...values).ok, false);
    }
    f.marker(10, TAG + "\nleftover");
    assert.match(f.call("run", ...args).error, /already exist/);
    assert.deepEqual(f.events, []);
    assert.equal(f.call("cleanup", ...args).attempted, 1);
    assert.equal(f.call("cleanup", ...args).attempted, 0);
    assert.deepEqual(f.snapshot(), before);
}
for (const fault of ["tag", "existing", "delete-noop"]) {
    const f = fixture(false, fault), before = f.snapshot(), result = f.call("run", ...args);
    assert.equal(result.ok, false);
    assert.equal(result.cleanup.verified, fault === "existing");
    assert.deepEqual(f.snapshot().slice(0, before.length), before, fault);
    if (fault === "tag") {
        assert.equal(f.items.length, before.length + 1, "An untagged addition remains for inspection.");
        assert.equal(f.items.at(-1).comments, "");
    }
}

const { scriptFor } = require("../../tools/probes/run-probe.js");
assert.match(scriptFor(["load", path.join(root, "tools/probes/Probe-MarkerRestore.jsx")]), /\$\.evalFile/);
assert.equal(scriptFor(["restore-list"]), "$._PVSMarkerRestoreProbe.list()");
assert.equal(scriptFor(["restore-projection", "1"]), "$._PVSMarkerRestoreProbe.projection(1)");
assert.throws(() => scriptFor(["restore-projection", "-1"]));
for (const method of ["run", "cleanup"]) {
    assert.equal(scriptFor(["restore-" + method, ...args]), "$._PVSMarkerRestoreProbe." + method + "(" + args.map(JSON.stringify).join(",") + ")");
    assert.throws(() => scriptFor(["restore-" + method, ...args.slice(1)]));
}
console.log("PROBE_MARKER_RESTORE_OK:ES3;read-only-projection;host-and-standalone;exact-readback;tag-only-cleanup;no-native-proof");
