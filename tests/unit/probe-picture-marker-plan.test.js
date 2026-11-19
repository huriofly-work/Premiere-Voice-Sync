"use strict";
const assert = require("node:assert/strict"), fs = require("node:fs"), vm = require("node:vm"), path = require("node:path");
const { scriptFor } = require("../../tools/probes/run-probe");
const markerBounds = require("./marker-bounds");
const read = file => fs.readFileSync(path.join(__dirname, "../..", file), "utf8").replace(/\r\n/g, "\n");
const source = read("tools/probes/Probe-PictureMarkerPlan.jsx"), host = read("extension/jsx/host.jsx");
const parser = {};
vm.runInNewContext(process.binding("natives")["internal/deps/acorn/acorn/dist/acorn"], { exports: parser, module: { exports: parser } });
parser.parse(source, { ecmaVersion: 3 });

// Match the actual source bodies so drift in even an unexercised branch fails.
function body(code, start, end) {
    const offset = code.indexOf(start);
    assert(offset >= 0, start);
    const limit = code.indexOf(end, offset + start.length);
    assert(limit >= 0, end);
    return code.slice(offset + start.length, limit).split("\n").map(line => line.trim()).join("\n").trim();
}
for (const [start, end] of [
    ["function inScope(", "function group(collection"],
    ["function available(", "function same(a, b)"],
    ["function isOwnedClipMarker(", "function prepareClipMarkerGroup"]
]) {
    const probeEnd = { "function group(collection": "function available(", "function same(a, b)": "function speedFactor",
        "function prepareClipMarkerGroup": "function hasName" }[end];
    assert.equal(body(source, start, probeEnd), body(host, start, end), start);
}
for (const name of ["speedFactor", "clipMarkerMapping"]) {
    assert.equal(body(source, "function " + name + "(", "\n    }\n"),
        body(host, "$._PVS._" + name + " = function (", "\n};").replace("$._PVS._speedFactor(item)", "speedFactor(item)"), name);
}
const pictureNames = [...body(host, "Name: mergedVisualGroup ?", ",\n").matchAll(/"([^"]+)"/g)].map(match => match[1]);
assert.deepEqual(JSON.parse("[" + body(source, "var PICTURE_NAMES = [", "];") + "]"), pictureNames);

const TICKS = 254016000000, OUTER = TICKS / 30, NEST = TICKS / 25;
const time = (seconds, ticks = Math.round(seconds * TICKS)) => Object.freeze({ seconds, ticks: String(ticks) });
const readOnly = (value, writes) => new Proxy(Object.freeze(value), {
    get(target, key) {
        if (["createMarker", "deleteMarker", "setColorByIndex", "save", "undo"].includes(key)) {
            writes.push(key);
            throw Error("Unexpected write API: " + key);
        }
        return target[key];
    },
    set(target, field) {
        writes.push(field);
        throw Error("Unexpected write: " + field);
    }
});
const frozenCollection = (values, writes) => readOnly({
    getFirstMarker: () => values[0],
    getNextMarker: marker => values[values.indexOf(marker) + 1]
}, writes);
function fixture(useHost, missingNest = false) {
    const writes = [], tag = "[PremiereVoiceSync:owned-marker:v1]";
    const marker = (name, guid, start, end) => readOnly({
        name, guid, start: time(start), end: time(end), comments: "private fixture\n" + tag,
        type: "Comment", getColorByIndex: () => 1
    }, writes);
    const markers = [
        marker(pictureNames[0], "keep", 2, 2),
        marker(pictureNames[1], "move", 2 + 0.6 / 30, 2 + 0.6 / 30),
        marker(pictureNames[2], "end", 2, 2 + 1 / 30),
        marker(pictureNames[0], "snap", 2 + 0.4 / 30, 2 + 0.4 / 30)
    ];
    const other = marker("VOICE SYNC - Can kiem tra", "private-review", 3, 3);
    // Outside every clip range on the track: a leftover candidate.
    const stray = marker(pictureNames[2], "stray", 10, 10);
    const owners = markers.map((m, i) => Object.freeze({
        nodeId: "owner-" + i, isSequence: () => i === 0,
        getMarkers: () => frozenCollection(i === 0 ? [m, other, stray] : [m], writes)
    }));
    const clips = owners.map((projectItem, index) => Object.freeze({
        name: 'clip "' + index, start: time(10), end: time(12), inPoint: time(1), outPoint: time(3),
        projectItem, getSpeed: () => index === 0 ? 100 : 1
    }));
    // Shared owner on another cut, where this picture marker is out of scope.
    clips.push(Object.freeze({ ...clips[0], name: "shared", start: time(20), end: time(21), inPoint: time(4), outPoint: time(5) }));
    clips.numItems = clips.length;
    const active = Object.freeze({ sequenceID: "outer", timebase: String(OUTER), videoTracks: { 0: { clips }, numTracks: 1 } });
    const sequences = [active, { projectItem: owners[0], sequenceID: "nest", timebase: String(NEST) }];
    sequences.numSequences = sequences.length;
    const project = { documentID: "project", get sequences() { if (missingNest) throw Error("unavailable"); return sequences; } };
    let activeReads = 0;
    Object.defineProperty(project, "activeSequence", { get() { activeReads++; return active; } });
    const context = vm.createContext({ $: {}, app: { project: readOnly(project, writes) } });
    if (useHost) vm.runInContext(host, context);
    else context.JSON = undefined;
    vm.runInContext(source, context);
    assert.equal(activeReads, 0);
    const run = index => JSON.parse(context.$._PVSPictureMarkerPlanProbe.read(index));
    assert.equal(run(1).ok, false);
    assert.equal(run("0").ok, false);
    const result = run(0);
    assert.equal(result.ok, true, JSON.stringify(result));
    assert.deepEqual(writes, []);
    assert(!JSON.stringify(result).includes("private"));
    return result;
}
const replicated = fixture(false), nativeHelpers = fixture(true);
assert.equal(replicated.markerToolsSource, "replicated");
assert.equal(nativeHelpers.markerToolsSource, "host");
assert.equal(nativeHelpers.mappingSource, "host");
assert.deepEqual({ ...nativeHelpers, markerToolsSource: "replicated", mappingSource: "replicated" }, replicated);
assert.equal(replicated.sequenceId, "outer");
assert.equal(replicated.documentId, "project");
assert.equal(replicated.timebase, String(OUTER));
assert.equal(replicated.fps, 30);
assert.equal(replicated.trackIndex, 0);
assert.equal(replicated.clipCount, 5);
const [nest] = replicated.clips;
assert.equal(nest.index, 0);
assert.equal(nest.name, 'clip "0');
assert.equal(nest.projectItemNodeId, "owner-0");
assert.equal(nest.isSequence, true);
assert.deepEqual(nest.nest, { sequenceId: "nest", timebase: String(NEST), fps: 25 });
assert.deepEqual(nest.speed, { raw: 100, factor: 1 });
assert.deepEqual(nest.start, time(10));
assert.deepEqual(nest.end, time(12));
assert.deepEqual(nest.inPoint, time(1));
assert.deepEqual(nest.outPoint, time(3));
assert.equal(nest.otherOwnedMarkers, 1);
assert.equal(nest.middleOutputFrame, 330);
assert.equal(nest.middleTimelineSeconds, 11);
const [keep, move, endWrite, snap] = replicated.clips.slice(0, 4).map(clip => clip.pictureMarkers[0]);
assert.deepEqual([keep, move, endWrite, snap].map(row => row.predictedAction), ["keep", "move", "endWrite", "keep"]);
// The shared nest marker lies outside the second cut, so it is reported once.
assert.deepEqual(replicated.clips[4].pictureMarkers, []);
assert.equal(replicated.unmatchedPictureMarkers.length, 1);
assert.equal(replicated.unmatchedPictureMarkers[0].owner, "node:owner-0");
assert.deepEqual(replicated.unmatchedPictureMarkers[0].start, time(10));
assert.deepEqual(keep.start, time(2));
assert.deepEqual(keep.end, time(2));
assert.equal(keep.isPoint, true);
assert.equal(keep.timelineSeconds, 11);
assert.equal(keep.distanceToMiddleFrames, 0);
assert.equal(keep.insideClipRange, true);
assert.equal(keep.nestGridDeltaTicks, 0);
assert.equal(keep.outerGridDeltaTicks, 0);
assert.equal(move.nestGridDeltaTicks, null);
assert.equal(move.outerGridDeltaTicks, Math.round(-0.4 * OUTER));
assert.equal(keep.desiredSourceSeconds, 2);
assert.equal(keep.nearMatch, true);
assert.deepEqual(keep.verify, { startInRange: true, endInRange: true, inRange: true, endNearStart: true, withinHalfFrame: true, passed: true });
assert.equal(move.nearMatch, false);
assert.equal(move.verify.withinHalfFrame, false);
assert.equal(move.commitNearMatch, false);
assert.equal(endWrite.isPoint, false);
assert.equal(endWrite.verify.endNearStart, false);
assert.equal(snap.nearMatch, false);
assert.equal(snap.verify.withinHalfFrame, true);
assert.equal(snap.snappedToStoredPosition, true);
const { maxAbsDelta, ...counts } = replicated.summary;
assert.deepEqual(counts, { keep: 2, move: 1, endWrite: 1, unclassified: 0, outsideClip: 3, sequenceOwners: 1, otherOwnedMarkers: 1, unmatchedPictureMarkers: 1 });
assert(Math.abs(maxAbsDelta.sourceSeconds - 0.6 / 30) < 1e-12);
assert(Math.abs(maxAbsDelta.middleFrames - 0.6) < 1e-9);
assert.equal(fixture(false, true).clips[0].pictureMarkers[0].nestGridDeltaTicks, null);

// Exercise commit only on mutable mocks, separate from the probe's read-only fixture.
const hostContext = vm.createContext({ $: {} });
vm.runInContext(host, hostContext);
const tools = hostContext.$._PVS._markerTools;
const mapping = { speed: 1, source: t => t - 9, timeline: m => m + 9 };
for (const detail of [keep, move, endWrite, snap]) {
    const marker = markerBounds({ name: detail.name, comments: "same", guid: detail.guid,
        getColorByIndex: () => 1 }, detail.start.seconds, detail.end.seconds, true);
    const collection = { getFirstMarker: () => marker, getNextMarker: () => null,
        createMarker() { throw Error("Unexpected create"); }, deleteMarker() { throw Error("Unexpected delete"); } };
    const group = tools.group(collection, [{ start: 1, end: 3 }], () => true, 0.25 / 30, true);
    const spec = tools.point(group, 10, 12, 30, mapping);
    Object.assign(spec, { name: marker.name, comments: marker.comments, color: 1 });
    tools.add(group, spec);
    const result = tools.commit(group);
    assert.deepEqual(Array.from(result.failures), []);
    const { moves, endWrites } = result.timings;
    assert.equal(moves ? "move" : endWrites ? "endWrite" : "keep", detail.predictedAction);
}

assert.equal(scriptFor(["picture-plan", "0"]), "$._PVSPictureMarkerPlanProbe.read(0)");
for (const args of [[], ["-1"], ["0.2"], ["9007199254740992"], ["0", "1"]]) {
    assert.throws(() => scriptFor(["picture-plan", ...args]), /Usage: picture-plan/);
}
console.log("PICTURE_MARKER_PLAN_PROBE_OK: ES3, host parity, keep/move/endWrite, snap, shared owner, read-only");
