"use strict";
const assert = require("node:assert/strict"), fs = require("node:fs"), path = require("node:path"), vm = require("node:vm");
const root = path.resolve(__dirname, "../..");
const source = fs.readFileSync(path.join(root, "tools/probes/Probe-StaleTrackItem.jsx"), "utf8");
const parser = {};
vm.runInNewContext(process.binding("natives")["internal/deps/acorn/acorn/dist/acorn"], { exports: parser, module: { exports: parser } });
parser.parse(source, { ecmaVersion: 3 });
const { scriptFor } = require(path.join(root, "tools/probes/run-probe.js"));

// Each host call can hand out new TrackItem wrappers. With stale=true a wrapper
// from an earlier call keeps its timing fields but loses projectItem, the model
// that reproduces the 2.20.93-2.20.95 pre-commit traces.
function world(stale) {
    let epoch = 0;
    const writes = [];
    const time = ticks => ({ ticks: String(ticks), seconds: ticks / 254016000000 });
    const voice = { nodeId: "000f4241", treePath: "\\Voice\\voice.wav", name: "voice.wav", getMarkers() { throw Error("Probe must not read markers"); } };
    const bases = [0, 1].map(i => ({ nodeId: "track-item-" + i, name: "voice.wav", start: time(i * 100), end: time(i * 100 + 90),
        inPoint: time(i * 50), outPoint: time(i * 50 + 99), projectItem: voice, getSpeed() { return 1.1; } }));
    const wrappers = new Map();
    function wrapper(base) {
        const key = base.nodeId + "@" + epoch;
        if (!wrappers.has(key)) {
            const born = epoch;
            wrappers.set(key, new Proxy(base, {
                get(target, name) { return stale && name === "projectItem" && born !== epoch ? undefined : target[name]; },
                set(target, name) { writes.push(String(name)); return true; }
            }));
        }
        return stale ? wrappers.get(key) : base;
    }
    const clips = { get numItems() { return bases.length; } };
    bases.forEach((base, i) => Object.defineProperty(clips, i, { get() { return wrapper(base); } }));
    const sequence = { sequenceID: "seq-1", audioTracks: { numTracks: 2, 0: { clips: { numItems: 0 } }, 1: { clips } } };
    Object.defineProperty(sequence, "markers", { get() { throw Error("Sequence markers must never be accessed"); } });
    const project = { documentID: "doc-1", activeSequence: sequence, save() { throw Error("MUST_NOT_SAVE"); } };
    const context = vm.createContext({ app: { project }, $: { _PVS: {} } });
    vm.runInContext(source, context);
    const api = context.$._PVSStaleTrackItemProbe;
    // Every probe command is its own evalScript call.
    const call = (name, ...args) => { epoch++; return JSON.parse(api[name](...args)); };
    return { call, writes, project, sequence };
}

for (const stale of [false, true]) {
    const w = world(stale);
    assert.equal(w.call("compare").ok, false, "compare requires capture");
    const captured = w.call("capture", 1);
    assert.equal(captured.ok, true);
    assert.equal(captured.clipCount, 2);
    for (const row of captured.clips) {
        assert.equal(row.fresh.projectKey, "node:000f4241");
        assert.deepEqual(row.sameCallHeldDiff, []);
        assert.deepEqual(row.sameCallRefetchDiff, []);
        assert.equal(row.fresh.speed.value, "1.1");
    }
    const compared = w.call("compare");
    assert.equal(compared.ok, true, JSON.stringify(compared));
    assert.equal(compared.keyMismatches, stale ? 2 : 0);
    for (const row of compared.clips) {
        assert.equal(row.freshFound, true);
        assert.equal(row.sameObject, !stale);
        assert.equal(row.keyMatchesFresh, !stale);
        assert.equal(row.held.projectKey, stale ? "" : "node:000f4241");
        assert.equal(row.held.projectItem.kind, stale ? "undefined" : "object");
        assert.equal(row.held.projectItemNodeId.kind, stale ? "error" : "string");
        assert.equal(row.held.inPointTicks.kind, "string", "Timing fields stay readable on the held wrapper");
        assert.deepEqual(row.heldVsFreshDiff, stale ? ["projectItem", "projectItemNodeId", "projectItemTreePath", "projectItemGetMarkers", "projectKey"] : []);
        assert.deepEqual(row.keptProjectItemNodeId, { kind: "string", value: "000f4241" }, "A ProjectItem kept from call A stays usable");
        assert.equal(row.keptProjectItemGetMarkers.value, "function");
    }
    assert.deepEqual(w.call("release"), { ok: true, step: "release", released: true });
    assert.equal(w.call("compare").ok, false, "release forgets the capture");
    assert.deepEqual(w.writes, [], "Probe never writes native properties");

    // Guards: wrong track, changed sequence.
    assert.match(w.call("capture", 0).error, /no clips/);
    assert.match(w.call("capture", 5).error, /out of range/);
    assert.match(w.call("capture", 1.5).error, /out of range/);
    assert.equal(w.call("capture", 1).ok, true);
    w.project.activeSequence = Object.assign({}, w.sequence, { sequenceID: "seq-2" });
    assert.match(w.call("compare").error, /changed since capture/);
}

assert.equal(scriptFor(["stale-capture", "1"]), "$._PVSStaleTrackItemProbe.capture(1)");
assert.equal(scriptFor(["stale-compare"]), "$._PVSStaleTrackItemProbe.compare()");
assert.equal(scriptFor(["stale-release"]), "$._PVSStaleTrackItemProbe.release()");
for (const bad of [["stale-capture"], ["stale-capture", "-1"], ["stale-capture", "1.5"], ["stale-capture", "1", "2"], ["stale-compare", "x"], ["stale-release", "x"]]) {
    assert.throws(() => scriptFor(bad), /Usage/, bad.join(" "));
}
console.log("STALE_TRACKITEM_PROBE_OK");
