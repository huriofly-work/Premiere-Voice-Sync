"use strict";
const assert = require("node:assert/strict"), fs = require("node:fs"), path = require("node:path"), vm = require("node:vm");
const root = path.resolve(__dirname, "../..");
const source = fs.readFileSync(path.join(root, "tools/probes/Probe-VoiceClipMarkers.jsx"), "utf8");
const parser = {};
vm.runInNewContext(process.binding("natives")["internal/deps/acorn/acorn/dist/acorn"], { exports: parser, module: { exports: parser } });
parser.parse(source, { ecmaVersion: 3 });
const tag = "[PremiereVoiceSync:probe:v1]";
const collection = (rows, countName) => Object.assign(rows, { [countName]: rows.length });
const time = seconds => ({ seconds });

// Run with native JSON, missing JSON and a broken JSON implementation.
for (const json of [JSON, undefined, { stringify() { throw Error("no JSON"); } }]) {
    let creates = 0, deletes = 0, falseDelete = false;
    const marker = (start, comments) => ({ guid: `m${start}`, start: time(start), end: time(start), name: "manual", comments, type: "Comment" });
    const manual = marker(11, 'manual "note"\n\\\t\u0001\u2028'), almost = marker(13, "[PremiereVoiceSync:probe:v10]");
    const rows = [manual, almost];
    const markers = {
        getFirstMarker() { return rows[0]; }, getNextMarker(m) { return rows[rows.indexOf(m) + 1]; },
        createMarker(start) { creates++; const m = marker(start, ""); m.name = ""; rows.push(m); return m; },
        deleteMarker(m) { assert(m.comments.includes(tag)); deletes++; if (!falseDelete) rows.splice(rows.indexOf(m), 1); }
    };
    const item = { name: "voice", nodeId: "media-1", treePath: "\\project\\voice", getMarkers() { return markers; } };
    const clip = (start, inPoint, outPoint, speed, pi = item) => ({ name: "voice", nodeId: `c${start}`, start: time(start), end: time(start + (outPoint - inPoint) / speed), inPoint: time(inPoint), outPoint: time(outPoint), projectItem: pi, getSpeed() { return speed; }, isSpeedReversed() { return false; } });
    const a2 = clip(30, 10, 20, 2), repeated = clip(50, 8, 18, 0.5, { ...item });
    const outside = clip(1, 14, 18, 1);
    const seq = { name: "Probe \"sequence\"\n", sequenceID: "seq-1", timebase: 254016000000 / 30,
        audioTracks: collection([{ clips: collection([repeated], "numItems") }, { clips: collection([a2], "numItems") }], "numTracks"),
        videoTracks: collection([{ clips: collection([outside], "numItems") }], "numTracks") };
    Object.defineProperty(seq, "markers", { get() { throw Error("Sequence markers must never be accessed"); } });
    const context = { app: { project: { activeSequence: seq } }, $: { _PVS: { sentinel: true } }, JSON: json };
    vm.runInNewContext(source, context);
    assert.equal(creates + deletes, 0, "Loading is read-only");
    const api = context.$._PVSProbe, call = (name, ...args) => JSON.parse(api[name](...args));
    const listed = call("list");
    assert.equal(listed.ok, true); assert.equal(listed.trackIndex, 1); assert.equal(listed.sequence.frameRate, 30);
    assert.equal(listed.sequence.name, seq.name); assert.equal(listed.clips[0].markerCount, 2);
    assert.equal(listed.clips[0].probeMarkerCount, 0); assert.equal(listed.clips[0].projectItem.getMarkers, true);
    assert.equal(listed.clips[0].speed.factor, 2); assert.equal(creates + deletes, 0);
    for (const offset of [-1, 10, 11, NaN, Infinity, "2", undefined]) assert.equal(call("create", 1, 0, offset).ok, false);
    assert.equal(call("create", 1, 0, 1).ok, false, "Never reuse occupied manual marker");
    assert.equal(creates, 0, "Validation rejects before mutation");
    const created = call("create", 1, 0, 2);
    assert.equal(created.ok, true); assert.equal(creates, 1); assert.equal(created.requestedSourceTime, 12);
    assert.equal(created.marker.start, 12); assert.equal(created.marker.end, 12); assert.equal(created.sourceTimeDelta, 0);
    assert.equal(created.marker.name, "PVS PROBE"); assert.equal(created.marker.comments, "probe clip marker\n" + tag);
    assert.equal(created.marker.type, "Comment");
    let read = call("read", 1, 0); assert.equal(read.markers.length, 1);
    const uses = read.markers[0].trackItems;
    assert.equal(uses.length, 3); assert.equal(uses[0].insideSourceRange, false);
    assert.equal(uses[1].expectedTimelineTime, 58); assert.equal(uses[2].expectedTimelineTime, 31);
    a2.start.seconds += 5;
    assert.equal(call("read", 1, 0).markers[0].trackItems[2].expectedTimelineTime, 36);
    a2.inPoint.seconds = 13;
    assert.equal(call("read", 1, 0).markers[0].trackItems[2].insideSourceRange, false);
    a2.getSpeed = () => 200;
    assert.equal(call("read", 1, 0).markers[0].trackItems[2].speed.factor, 2);
    a2.getSpeed = () => { throw Error("unknown"); };
    assert.equal(call("read", 1, 0).markers[0].trackItems[2].expectedTimelineTime, null);
    a2.getSpeed = () => 2; a2.isSpeedReversed = () => true;
    assert.equal(call("read", 1, 0).markers[0].trackItems[2].expectedTimelineTime, null);
    assert.equal(creates + deletes, 1, "list/read never mutate");
    falseDelete = true;
    assert.equal(call("remove", 1, 0).ok, false, "Readback detects native false-success deletion");
    falseDelete = false;
    const removed = call("remove", 1, 0);
    assert.equal(removed.ok, true); assert.equal(removed.remaining, 0); assert.equal(removed.totalMarkerCount, 2);
    assert.deepEqual(rows, [manual, almost]); assert.equal(call("remove", 1, 0).attempted, 0);
    assert.equal(context.$._PVS.sentinel, true);
    assert.equal(call("list", -1).ok, false); assert.equal(call("read", 1, 99).ok, false);
    context.app.project.activeSequence = null;
    for (const method of ["list", "create", "read", "remove"]) assert.equal(call(method, 1, 0, 2).ok, false);
}

// Exercise the debugger bridge entirely in a VM: no socket, CEP or Premiere access.
async function bridgeTest() {
    const runner = path.join(root, "tools/probes/run-probe.js"), exported = { exports: {} }, output = [];
    let packet, panelExpression, reply = '{"ok":true,"mock":true}', pages, sawURL;
    class MockSocket {
        constructor() { this.events = {}; queueMicrotask(() => this.events.open()); }
        addEventListener(name, fn) { this.events[name] = fn; }
        send(text) {
            packet = JSON.parse(text); panelExpression = packet.params.expression;
            queueMicrotask(() => this.events.message({ data: JSON.stringify({ id: 1, result: { result: { value: reply } } }) }));
        }
        close() {}
    }
    const sandbox = { module: exported, require, process: { exitCode: 0 }, WebSocket: MockSocket, URL, AbortSignal, setTimeout, clearTimeout,
        console: { log(text) { output.push(text); } }, fetch: async url => { sawURL = url; return { ok: true, json: async () => pages }; } };
    vm.runInNewContext(fs.readFileSync(runner, "utf8"), sandbox);
    const { isPanel, scriptFor, main } = exported.exports;
    const panel = { type: "page", title: "Premiere Voice Sync", url: "file:///panel/index.html", webSocketDebuggerUrl: "ws://localhost:8099/devtools/page/1" };
    assert(isPanel(panel)); assert(!isPanel({ ...panel, title: "Other panel" }));
    assert(!isPanel({ ...panel, type: "worker" }));
    assert(isPanel({ ...panel, title: "com.premierevoicesync.local.panel", url: "file:///x.html" }));
    assert.throws(() => scriptFor(["call", "create", "1", "0", "2);app.project.save()"]), /finite numbers/);
    assert.throws(() => scriptFor(["call", "save"]), /Usage/);
    assert.throws(() => scriptFor(["load", "relative.jsx"]), /absolute/);
    assert(scriptFor(["load", path.join(root, "tools/probes/Probe-VoiceClipMarkers.jsx")]).includes("$.evalFile(file)"));
    pages = [ { ...panel, title: "Other panel" }, panel ];
    await main(["call", "read", "1", "0"]);
    assert.equal(sawURL, "http://localhost:8099/json"); assert.equal(packet.method, "Runtime.evaluate");
    assert.equal(packet.params.awaitPromise, true); assert.equal(packet.params.returnByValue, true);
    let passedScript;
    await vm.runInNewContext(panelExpression, { window: { __adobe_cep__: { evalScript(script, callback) { passedScript = script; callback("ok"); } } } });
    assert.equal(passedScript, "$._PVSProbe.read(1,0)"); assert.equal(JSON.parse(output[0]).mock, true);
    reply = "EvalScript error.";
    await assert.rejects(main(["8099", "call", "list", "1"]), /EvalScript error/);
    pages = [panel, panel]; await assert.rejects(main(["call", "list"]), /Multiple/);
    pages = []; await assert.rejects(main(["call", "list"]), /No Premiere Voice Sync/);
}
bridgeTest().then(() => console.log("PROBE_VOICE_CLIP_MARKERS_OK:ES3;JSON-fallback;read-only;source-offset;speed;shared-items;tag-only-delete;CDP-mock"))
    .catch(error => { console.error(error); process.exitCode = 1; });
