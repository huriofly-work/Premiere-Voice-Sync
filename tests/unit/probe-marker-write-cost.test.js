"use strict";
const markerBounds=require("./marker-bounds");
const assert = require("node:assert/strict"), fs = require("node:fs"), path = require("node:path"), vm = require("node:vm");
const root = path.resolve(__dirname, "../.."), file = path.join(root, "tools/probes/Probe-MarkerWriteCost.jsx");
const source = fs.readFileSync(file, "utf8"), parser = {};
vm.runInNewContext(process.binding("natives")["internal/deps/acorn/acorn/dist/acorn"], { exports: parser, module: { exports: parser } });
parser.parse(source, { ecmaVersion: 3 });
const TAG = "[PremiereVoiceSync:marker-write-cost:v1]", SCOPE = "throwaway-project";
function fixture(mode = "both", fault = null) {
    let clock = 0, id = 0, faultUsed = false, writes = 0;
    const values = [], events = [], costs = { createMarker: 2, name: 3, comments: 5, end: 7, setColorByIndex: 11, getColorByIndex: 13, deleteMarker: 17 };
    function operation(key) { clock += costs[key]; events.push(key); if (key !== "getColorByIndex") writes++; }
    function fail(key) { if (fault === key && !faultUsed) { faultUsed = true; throw Error(key); } }
    function marker(start, comments = "", name = "") {
        const bounds = markerBounds({}, start, start, true);
        let color = 0;
        const m = { guid: "m" + id++, type: "Comment", get name() { return name; }, set name(v) { operation("name"); name = v; fail("name"); },
            get comments() { return comments; }, set comments(v) { operation("comments"); comments = v; fail("comments"); },
            get start() { return bounds.start; }, set start(v) {
                const kind = typeof v === "number" ? "seconds" : "Time";
                if (mode === "ignore") return;
                if (mode === "throw" || (!["both", "throw-after"].includes(mode) && mode !== kind)) throw Error("read-only " + kind);
                bounds.start = v;
                if (mode === "throw-after") throw Error("mutated then threw");
            },
            get end() { return bounds.end; }, set end(v) { operation("end"); if (fault !== "end-noop") bounds.end = v; fail("end"); },
            getColorByIndex() { operation("getColorByIndex"); return color; },
            setColorByIndex(v) { operation("setColorByIndex"); color = v; fail("setColorByIndex"); } };
        values.push(m); return m;
    }
    const manual = marker(1, 'manual "note"\n\\\t\u0001\u2028', "manual"), almost = marker(9, TAG + "0");
    const collection = { getFirstMarker() { clock += 19; return values[0]; }, getNextMarker(m) { clock += 23; return values[values.indexOf(m) + 1]; },
        createMarker(s) {
            operation("createMarker"); if (fault === "existing") return manual;
            const m = marker(s); fail("createMarker"); return m;
        },
        deleteMarker(m) {
            assert.equal(m.comments.split("\n")[0], TAG, "Only tagged markers may be deleted");
            operation("deleteMarker");
            if (fault === "delete-noop" || (fault === "delete-once" && !faultUsed)) { faultUsed = true; return; }
            values.splice(values.indexOf(m), 1); fail("deleteMarker");
        } };
    const item = { type: 1, nodeId: "media-1", name: "throwaway", isSequence: () => false, getMarkers: () => collection };
    const sequence = { type: 1, nodeId: "seq-1", isSequence: () => true, getMarkers() { throw Error("Sequence markers accessed"); } };
    const children = [item, sequence]; children.numItems = children.length;
    const project = { documentID: "project-1", name: "throwaway", rootItem: { type: 2, children } };
    for (const name of ["activeSequence", "sequences", "save", "saveAs", "undo"]) Object.defineProperty(project, name, { get() { throw Error("Forbidden access: " + name); } });
    const context = { app: { project }, $: { sentinel: true }, Date: function () { this.getTime = () => clock; }, Time: function () { this.seconds = 0; }, JSON: undefined };
    vm.runInNewContext(source, context);
    assert.equal(writes, 0, "Loading must not mutate");
    const api = context.$._PVSMarkerWriteCostProbe, call = (method, ...args) => JSON.parse(api[method](...args));
    const run = (...n) => call("run", "project-1", "media-1", TAG, SCOPE, ...n);
    const snapshot = () => values.map(m => [m.guid, m.start.seconds, m.end.seconds, m.name, m.comments, m.type, m.getColorByIndex()]);
    return { values, marker, manual, almost, call, run, snapshot, costs, project, item, events, get writes() { return writes; } };
}
for (const count of [undefined, 1, 10, 100]) {
    const f = fixture(), before = f.snapshot(), n = count === undefined ? 10 : count;
    const listed = f.call("list");
    assert.equal(listed.ok, true); assert.equal(listed.documentId, "project-1"); assert.equal(listed.items.length, 1); assert.equal(f.writes, 0);
    const result = count === undefined ? f.run() : f.run(count);
    assert.equal(result.ok, true, JSON.stringify(result)); assert.equal(result.count, n);
    for (const [key, cost] of Object.entries(f.costs)) {
        const m = result.metrics[key]; assert.equal(m.count, n, key); assert.equal(m.totalMs, n * cost, key); assert.equal(m.averageMs, cost, key);
    }
    assert.equal(result.metrics.collectionRead.count, 1);
    assert.equal(result.metrics.collectionRead.totalMs, 19 + (n + 2) * (23 + 13));
    assert.deepEqual(result.moves.map(m => m.accepted), [true, true]);
    assert.equal(result.moves[0].requested - result.moves[0].before, 0.25);
    assert.equal(result.moves[1].requested - result.moves[1].before, 0.25);
    assert.equal(result.deletionVerified, true); assert.equal(result.cleanup.verified, true); assert.equal(result.cleanup.attempted, 0);
    assert.deepEqual(f.snapshot(), before, "Every original field and identity survives");
}
for (const mode of ["Time", "seconds", "ignore", "throw", "throw-after"]) {
    const f = fixture(mode), r = f.run(2);
    assert.equal(r.ok, true); assert.equal(r.cleanup.verified, true);
    assert.deepEqual(r.moves.map(m => m.accepted), mode === "ignore" || mode === "throw" ? [false, false] : mode === "Time" ? [true, false] : mode === "seconds" ? [false, true] : [true, true]);
    if (mode === "throw-after") assert(r.moves.every(m => m.assignmentError && m.accepted));
    if (mode === "throw") assert(r.moves.every(m => m.assignmentError.includes("read-only")));
}
for (const count of [0, -1, 101, 1.1, "10", NaN, Infinity, null]) {
    const f = fixture(); assert.equal(f.run(count).ok, false); assert.equal(f.writes, 0);
}
for (const args of [[], ["project-1", "media-1"], ["project-1", "media-1", TAG, "real-project"], ["other", "media-1", TAG, SCOPE], ["project-1", "seq-1", TAG, SCOPE], ["project-1", "media-1", TAG + "x", SCOPE]]) {
    const f = fixture(); assert.equal(f.call("run", ...args).ok, false); assert.equal(f.call("cleanup", ...args).ok, false); assert.equal(f.writes, 0);
}
for (const fault of ["comments", "name", "end", "end-noop", "setColorByIndex", "deleteMarker", "delete-once", "delete-noop", "createMarker", "existing"]) {
    const f = fixture("both", fault), before = f.snapshot(), r = f.run(3);
    const unrecoverable = ["delete-noop", "createMarker"].includes(fault);
    assert.equal(r.cleanup.verified, !unrecoverable, fault);
    assert.equal(r.ok, false, fault);
    if (fault === "delete-once") { assert.equal(r.deletionVerified, false); assert.equal(r.cleanup.attempted, 1); }
    if (!unrecoverable) assert.deepEqual(f.snapshot(), before, fault);
    else assert(r.cleanup.errors.length > 0);
    if (fault === "createMarker") assert.equal(f.values.length, 3, "An untagged addition is reported and retained");
}
{
    const f = fixture(), before = f.snapshot();
    f.marker(20, TAG + "\nstale", "stale probe");
    assert.equal(f.run().ok, false); assert.equal(f.writes, 0, "Refuse a dirty probe scope");
    const cleaned = f.call("cleanup", "project-1", "media-1", TAG, SCOPE);
    assert.equal(cleaned.ok, true); assert.equal(cleaned.cleanup.attempted, 1); assert.deepEqual(f.snapshot(), before);
    assert.equal(f.call("cleanup", "project-1", "media-1", TAG, SCOPE).cleanup.attempted, 0);
}
{
    const f = fixture(); f.item.children = { numItems: 1, 0: f.item };
    assert.equal(f.call("list").ok, false); assert.equal(f.writes, 0, "Bound recursive project traversal");
}
const { scriptFor } = require(path.join(root, "tools/probes/run-probe.js"));
assert.equal(scriptFor(["cost-list"]), "$._PVSMarkerWriteCostProbe.list()");
assert.equal(scriptFor(["move-list"]), "$._PVSMarkerMoveEndProbe.list()");
const moveArgs = ['project"1', "media-1", "[PremiereVoiceSync:marker-move-end:v1]", "probe-tagged-only"];
for (const method of ["run", "cleanup"]) {
    const command = "move-" + method;
    assert.equal(scriptFor([command, ...moveArgs]), "$._PVSMarkerMoveEndProbe." + method + "(" + moveArgs.map(JSON.stringify).join(",") + ")");
    assert.throws(() => scriptFor([command, ...moveArgs.slice(1)]));
    assert.throws(() => scriptFor([command, ...moveArgs, "extra"]));
}
assert.throws(() => scriptFor(["move-list", "extra"]));
const args = ["project-1", "media-1", TAG, SCOPE];
assert.equal(scriptFor(["cost-run", ...args]), `$._PVSMarkerWriteCostProbe.run(${args.map(JSON.stringify).join(",")})`);
assert.equal(scriptFor(["cost-run", ...args, "10"]), `$._PVSMarkerWriteCostProbe.run(${args.map(JSON.stringify).join(",")},10)`);
assert.equal(scriptFor(["cost-cleanup", ...args]), `$._PVSMarkerWriteCostProbe.cleanup(${args.map(JSON.stringify).join(",")})`);
for (const command of [["cost-list", "extra"], ["cost-run"], ["cost-cleanup", ...args, "10"], ["cost-run", ...args, "101"], ["cost-run", ...args, "1);save()"]]) assert.throws(() => scriptFor(command));
assert(scriptFor(["cost-run", 'x";save()', "media-1", TAG, SCOPE]).includes('"x\\\";save()"'), "Identifiers are serialized literals");
console.log("PROBE_MARKER_WRITE_COST_OK:ES3;arithmetic;limits;scope;start-Time-and-seconds;false-success;tag-only-cleanup;pre-state-verification;no-native-proof");
