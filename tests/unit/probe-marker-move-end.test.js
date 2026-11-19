"use strict";
const assert = require("node:assert/strict"), fs = require("node:fs"), vm = require("node:vm"), path = require("node:path");
const markerBounds = require("./marker-bounds");
const { scriptFor } = require("../../tools/probes/run-probe");
const source = fs.readFileSync(path.join(__dirname, "../../tools/probes/Probe-MarkerMoveEnd.jsx"), "utf8");
const parser = {};
vm.runInNewContext(process.binding("natives")["internal/deps/acorn/acorn/dist/acorn"], { exports: parser, module: { exports: parser } });
parser.parse(source, { ecmaVersion: 3 });
const TICKS = 254016000000, FRAME = TICKS / 25, TAG = "[PremiereVoiceSync:marker-move-end:v1]";
const MEDIA_SCOPE = "probe-tagged-only", NEST_SCOPE = "probe-tagged-nest";
const nestArgs = ["doc", "nest", TAG, NEST_SCOPE], mediaArgs = ["doc", "media", TAG, MEDIA_SCOPE];

function fixture(fault = "") {
    const events = [], markers = [], time = seconds => ({ seconds, ticks: String(Math.round(seconds * TICKS)) });
    const onGrid = seconds => Math.round(seconds * TICKS / FRAME) * FRAME / TICKS;
    let nextId = 0, tagWrites = 0;
    function marker(seconds, comments = "", name = "") {
        const bounds = markerBounds({}, seconds, seconds, true);
        const guid = "marker-" + nextId++;
        const row = { guid, type: "Comment", getColorByIndex: () => 1,
            get name() { return name; },
            set name(value) { events.push(["name", guid]); name = value; },
            get comments() { return comments; },
            set comments(value) {
                events.push(["comments", guid]);
                if (fault === "tag" && ++tagWrites === 2) throw Error("Tag failed");
                comments = value;
            },
            get start() { return time(bounds.start.seconds); },
            set start(value) {
                events.push(["start", guid]);
                const end = bounds.end.seconds;
                bounds.start = onGrid(value);
                if (fault === "stationary-end") bounds.end = end;
            },
            get end() { return time(bounds.end.seconds); },
            set end(value) { events.push(["end", guid]); bounds.end = onGrid(value); }
        };
        markers.push(row);
        return row;
    }
    const manual = marker(4, "manual", "manual");
    marker(44, TAG + "-different-tag", "near tag");
    const collection = { getFirstMarker: () => markers[0], getNextMarker: m => markers[markers.indexOf(m) + 1],
        createMarker(seconds) {
            events.push(["create"]);
            return fault === "existing" ? manual : marker(onGrid(seconds));
        },
        deleteMarker(m) {
            assert.equal(m.comments.split("\n")[0], TAG);
            events.push(["delete", m.guid]);
            if (fault !== "delete-noop") markers.splice(markers.indexOf(m), 1);
        }
    };
    const media = { type: 1, nodeId: "media", name: "Media", isSequence: () => false, getMarkers: () => collection };
    const nest = { type: 2, nodeId: "nest", name: "Nest", isSequence: () => true, getMarkers: () => collection };
    const children = [media, nest]; children.numItems = children.length;
    const sequences = [{ projectItem: nest, timebase: String(fault === "no-timebase" ? "" : FRAME) }];
    sequences.numSequences = sequences.length;
    const project = { documentID: "doc", rootItem: { children }, sequences };
    for (const key of ["activeSequence", "save", "saveAs", "undo"]) {
        Object.defineProperty(project, key, { get() { throw Error("Forbidden access: " + key); } });
    }
    const context = vm.createContext({ $: {}, JSON: undefined, app: { project } });
    vm.runInContext(source, context);
    const call = (method, ...args) => JSON.parse(context.$._PVSMarkerMoveEndProbe[method](...args));
    const snapshot = () => markers.map(m => [m.guid, m.start.ticks, m.end.ticks, m.name, m.comments, m.type, m.getColorByIndex()]);
    return { call, marker, snapshot, events };
}

{
    const f = fixture(), before = f.snapshot();
    assert.deepEqual(f.call("list").items, [{ nodeId: "media", name: "Media" }]);
    assert.deepEqual(f.call("list", NEST_SCOPE).items, [{ nodeId: "nest", name: "Nest", isSequence: true }]);
    assert.equal(f.call("list", "other").ok, false);
    for (const args of [["doc", "nest", TAG, MEDIA_SCOPE], ["doc", "media", TAG, NEST_SCOPE],
        ["other", ...nestArgs.slice(1)], ["doc", "nest", TAG + "x", NEST_SCOPE]]) {
        assert.equal(f.call("run", ...args).ok, false);
        assert.equal(f.call("cleanup", ...args).ok, false);
    }
    f.marker(25, TAG + "\nleftover");
    assert.match(f.call("run", ...nestArgs).error, /already exist/);
    assert.deepEqual(f.events, []);
    assert.deepEqual(f.call("cleanup", ...nestArgs), { ok: true, attempted: 1, errors: [], verified: true });
    assert.deepEqual(f.snapshot(), before);
}
for (const fault of ["", "stationary-end"]) {
    const f = fixture(fault), before = f.snapshot(), result = f.call("run", ...nestArgs);
    assert.equal(result.ok, true, JSON.stringify(result));
    assert.equal(result.isSequence, true);
    assert.equal(result.timebase, String(FRAME));
    assert.equal(result.fps, 25);
    assert.deepEqual(result.cases.map(c => c.steps[0].offsetFrames), [0.37, 1.37, 1]);
    for (const [i, c] of result.cases.entries()) {
        const [step] = c.steps;
        assert.equal(c.initial.startTicks, c.initial.endTicks);
        assert.equal(c.initial.startGridDeltaTicks, 0);
        assert.equal(step.field, "start");
        assert.equal(step.requestedTicks, Number(c.initial.startTicks) + Math.round(step.offsetFrames * FRAME));
        assert.equal(step.requestedGridDeltaTicks, i === 2 ? 0 : Math.round(0.37 * FRAME));
        assert.equal(step.startGridDeltaTicks, 0);
        assert.equal(step.endGridDeltaTicks, 0);
        assert.equal(step.start, Number(step.startTicks) / TICKS);
        assert.equal(step.end, Number(step.endTicks) / TICKS);
        assert.equal(step.endTicks, fault ? c.initial.endTicks : step.startTicks);
        assert.equal(step.error, null);
        assert.equal(step.readError, null);
    }
    assert.equal(result.cases[1].steps[0].startTicks, String(Number(result.cases[1].initial.startTicks) + FRAME));
    assert.deepEqual(result.cleanup, { attempted: 3, errors: [], verified: true });
    assert.deepEqual(f.snapshot(), before);
}
for (const fault of ["tag", "existing", "delete-noop", "no-timebase"]) {
    const f = fixture(fault), before = f.snapshot(), result = f.call("run", ...nestArgs);
    assert.equal(result.ok, false);
    if (fault === "tag") {
        assert.equal(result.cleanup.verified, false);
        assert.equal(result.cleanup.attempted, 1);
        assert.equal(f.snapshot().length, before.length + 1);
        assert.equal(f.snapshot().at(-1)[4], "");
        assert.equal(f.call("cleanup", ...nestArgs).attempted, 0);
    } else if (fault === "delete-noop") {
        assert.equal(result.cleanup.verified, false);
        assert.equal(result.cleanup.attempted, 3);
    } else {
        assert.deepEqual(f.snapshot(), before);
        assert.deepEqual(f.events, fault === "existing" ? [["create"]] : []);
    }
}
{
    const f = fixture(), before = f.snapshot(), result = f.call("run", ...mediaArgs);
    assert.equal(result.ok, true, JSON.stringify(result));
    assert.equal(result.cases.length, 10);
    assert.equal(result.cases[0].id, "new-default");
    assert(result.cleanup.verified);
    assert.deepEqual(f.snapshot(), before);
}
assert.equal(scriptFor(["move-list", NEST_SCOPE]), '$._PVSMarkerMoveEndProbe.list("probe-tagged-nest")');
assert.throws(() => scriptFor(["move-list", "other"]), /Usage/);
console.log("MARKER_MOVE_END_PROBE_OK: 10 media cases, 3 nest cases, scope and cleanup faults");
