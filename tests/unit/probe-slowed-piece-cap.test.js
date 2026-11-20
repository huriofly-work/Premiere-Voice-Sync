"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");
const { scriptFor } = require("../../tools/probes/run-probe");

const probePath = path.resolve(__dirname, "../../tools/probes/Probe-SlowedPieceCap.jsx");
const source = fs.readFileSync(probePath, "utf8");
const parser = {};
vm.runInNewContext(process.binding("natives")["internal/deps/acorn/acorn/dist/acorn"], { exports: parser, module: { exports: parser } });
parser.parse(source, { ecmaVersion: 3 });
const command = ["slowcap-auto"];
const timebase = 10160640000;
const time = frames => ({ ticks: String(Math.round(frames * timebase)) });

function fixture({ duration = 1125, audioIn = 79, cappedTracks = ["V1", "A1"], loadError = false,
    rippleBypassesCap = false, rippleMovesMarker = false, outExtendsEnd = false, rejectOut = false,
    linkedMove = false, refuseMove = false, refuseRazor = false, unlinkedRazor = false } = {}) {
    const events = [], loads = [], sourceItem = { nodeId: "nest" };
    const mediaFrames = 79 + duration;
    const fromTimecode = tc => tc.split(":").map(Number).reduce((frames, n, i) => frames * (i === 3 ? 25 : 60) + n);
    const tracks = { V1: [], A1: [] };
    for (const clips of Object.values(tracks)) {
        Object.defineProperty(clips, "numItems", { get() { return this.length; } });
    }
    const id = (label, start) => label + ":" + start;
    const marker = { guid: "marker", start: time(10), end: time(10) };
    let links = null;
    function makeClip(label, start, end, inFrame) {
        let timelineEnd = time(end), outPoint = time(inFrame + end - start);
        const item = {
            nodeId: id(label, start), name: 'Nest "A"', projectItem: sourceItem,
            start: time(start), inPoint: time(inFrame),
            speed: 1, reversed: false,
            getSpeed() { return this.speed; },
            isSpeedReversed() { return this.reversed; },
            getLinkedItems() { return links || [{ nodeId: id("A1", start) }]; },
            get outPoint() { return outPoint; },
            set outPoint(value) {
                events.push(["out", label, start, value.ticks]);
                if (rejectOut) throw Error("Out refused");
                outPoint = value;
                if (outExtendsEnd) timelineEnd = { ticks: String(Number(this.start.ticks) + Number(value.ticks) - Number(this.inPoint.ticks)) };
            },
            get end() { return timelineEnd; },
            set end(value) {
                events.push(["end", label, start, value.ticks]);
                timelineEnd = value;
            },
            translate(delta) {
                this.start = { ticks: String(Number(this.start.ticks) + delta) };
                timelineEnd = { ticks: String(Number(timelineEnd.ticks) + delta) };
            },
            move(delta) {
                events.push(["move", label, start, delta.ticks]);
                if (refuseMove) return;
                this.translate(Number(delta.ticks));
                if (linkedMove && label === "V1") tracks.A1.find(clip => clip.nodeId === id("A1", start)).translate(Number(delta.ticks));
            },
            remove(...args) {
                events.push(["remove", label, start, ...args]);
                const clips = tracks[label];
                clips.splice(clips.indexOf(this), 1);
            },
            setSpeed(...args) {
                events.push(["speed", label, start, ...args]);
                const [factor, tc, , , ripple] = args;
                const requested = fromTimecode(tc);
                const remaining = mediaFrames - inFrame;
                const capped = cappedTracks.includes(label) && !(ripple && rippleBypassesCap);
                const actual = capped ? Math.min(requested, remaining) : requested;
                this.speed = factor;
                this.inPoint = time(inFrame / factor);
                outPoint = time(inFrame / factor + actual);
                timelineEnd = { ticks: String(Number(this.start.ticks) + actual * timebase) };
                if (ripple && rippleMovesMarker) marker.start = marker.end = time(11);
                return true;
            }
        };
        return item;
    }
    tracks.V1.push(makeClip("V1", 0, duration, 79));
    tracks.A1.push(makeClip("A1", 0, duration, audioIn));
    const sequence = {
        name: "PVS Probe - speed cap", sequenceID: "active", timebase: String(timebase),
        getSelection() { throw Error("The auto probe must not read selection."); },
        videoTracks: Object.assign([{ clips: tracks.V1 }], { numTracks: 1 }),
        audioTracks: Object.assign([{ clips: tracks.A1 }], { numTracks: 1 }),
        markers: { getFirstMarker: () => marker, getNextMarker: () => null }
    };
    const nest = { projectItem: sourceItem, sequenceID: "source", zeroPoint: time(1000).ticks, end: time(1000 + mediaFrames).ticks };
    const project = { documentID: "project", activeSequence: sequence, sequences: Object.assign([nest], { numSequences: 1 }) };
    function qeTrack(label) {
        const clips = tracks[label];
        return {
            get numItems() { return clips.length + 1; },
            getItemAt(i) {
                if (i === 0) return { type: "Empty" };
                const clip = clips[i - 1];
                return { type: "Clip", start: clip.start, end: clip.end, in: clip.inPoint,
                    setSpeed: clip.setSpeed.bind(clip) };
            },
            razor(...args) {
                assert.equal(label, "V1");
                events.push(["razor", ...args]);
                if (refuseRazor) return false;
                const split = fromTimecode(args[0]);
                for (const [kind, items] of Object.entries(tracks)) {
                    if (unlinkedRazor && kind === "A1") continue;
                    const index = items.findIndex(item => Number(item.start.ticks) < split * timebase && Number(item.end.ticks) > split * timebase);
                    assert.notEqual(index, -1);
                    const { start, end, inPoint } = items[index];
                    const first = Number(start.ticks) / timebase;
                    const last = Number(end.ticks) / timebase;
                    const inFrame = Number(inPoint.ticks) / timebase;
                    items.splice(index, 1, makeClip(kind, first, split, inFrame), makeClip(kind, split, last, inFrame + split - first));
                }
                return true;
            }
        };
    }
    const context = vm.createContext({
        $: { evalFile(file) {
            assert.equal(file.encoding, "UTF-8");
            assert.equal(path.normalize(file.filename), probePath);
            loads.push(file.filename);
            if (loadError) throw Object.assign(Error("Illegal reserved word"), { line: 42 });
            vm.runInContext(source, context);
        } },
        File: function (filename) { this.filename = filename; },
        JSON: undefined,
        app: { project, enableQE() { events.push(["enableQE"]); } },
        qe: { project: { getActiveSequence: () => ({
            getVideoTrackAt(index) { assert.equal(index, 0); return qeTrack("V1"); },
            getAudioTrackAt(index) { assert.equal(index, 0); return qeTrack("A1"); }
        }) } },
        Time: function () { this.ticks = "0"; }
    });
    return {
        project, sequence, nest, tracks, events, loads,
        setLinks(items) { links = items; },
        evaluate: script => vm.runInContext(script, context),
        call(expected) { return JSON.parse(this.evaluate(scriptFor(command, expected))); },
        reread(report) { return JSON.parse(this.evaluate(`$._PVSSlowedPieceCapProbe.reread(${JSON.stringify(report)})`)); }
    };
}

for (const [mutate, error] of [
    [f => { f.project.activeSequence = null; }, /disposable sequence/],
    [f => { f.sequence.name = "Original PVS Probe"; }, /disposable sequence/],
    [f => f.tracks.V1.push({}), /each contain exactly one clip/],
    [f => f.tracks.A1.push({}), /each contain exactly one clip/],
    [f => { f.tracks.A1.pop(); }, /each contain exactly one clip/],
    [f => f.setLinks([]), /linked only to the matching A1/],
    [f => f.setLinks([{ nodeId: "A1:0" }, { nodeId: "A2:0" }]), /linked only to the matching A1/],
    [f => { f.nest.projectItem = { nodeId: "other" }; }, /must contain a nested sequence/],
    [f => { f.tracks.V1[0].start = time(1); }, /start at frame 0/],
    [f => { f.tracks.A1[0].speed = 0.5; }, /forward at 100%/],
    [f => { f.tracks.V1[0].reversed = true; }, /forward at 100%/],
    [f => { f.sequence.timebase = "0"; }, /Invalid frame rate/]
]) {
    const f = fixture();
    mutate(f);
    const actual = f.call();
    assert.equal(actual.ok, false);
    assert.match(actual.error, error);
    assert.deepEqual(f.events, []);
}
for (const mutate of [
    f => { f.sequence.sequenceID = "other"; },
    f => { f.project.documentID = "other"; },
    f => { f.nest.end = time(2300).ticks; },
    f => {
        f.tracks.A1[0].inPoint = time(78);
        Object.defineProperty(f.tracks.A1[0], "outPoint", { value: time(1203) });
    }
]) {
    const f = fixture(), preview = f.call();
    mutate(f);
    assert.match(f.call(preview.expected).error, /changed after preview/);
    assert.deepEqual(f.events, []);
}
{
    const f = fixture({ duration: 99 });
    assert.match(f.call().error, /at least one second/);
    assert.deepEqual(f.events, []);
}
{
    const f = fixture();
    f.sequence.videoTracks.push({ clips: Object.assign([{ nodeId: "late", start: time(3000), end: time(3100) }], { numItems: 1 }) });
    f.sequence.videoTracks.numTracks++;
    // A clip on another track that ends after the nest pushes C past it, so the ripple moves nothing.
    const preview = f.call();
    assert.equal(preview.ok, true, preview.error);
    assert(preview.plannedChange.variants[2].startFrame > 3100, "C must start after the last clip on every track");
    assert.deepEqual(f.events, []);
}
{
    const f = fixture({ duration: 100, linkedMove: true });
    const preview = f.call();
    assert.deepEqual(preview.plannedChange.razor.map(cut => cut.frame), [25, 50, 75]);
    const report = f.call(preview.expected);
    assert.equal(report.ok, true);
    assert.equal(report.variants[0].video.before.startFrame, 0);
    assert.deepEqual(report.setup.movesCompleted.map(move => move.track), ["V1", "V1"]);
}
{
    const f = fixture({ audioIn: 75 });
    const preview = f.call(), plans = preview.plannedChange.variants;
    assert.deepEqual(f.events, []);
    assert.deepEqual(plans.map(p => [p.id, p.cutStartFrame, p.startFrame, p.video.targetFrames, p.audio.targetFrames]), [
        ["A", 125, 125, 1056, 1060], ["B", 375, 1210, 806, 810], ["C", 625, 2045, 556, 560]
    ]);
    const immediate = f.call(preview.expected);
    assert.equal(immediate.ok, true, immediate.error);
    assert.deepEqual(immediate.setup.cutsCompleted, [125, 375, 625, 875]);
    assert.deepEqual(immediate.setup.removalsCompleted.map(({ track, startFrame }) => [track, startFrame]), [["V1", 875], ["A1", 875]]);
    assert.deepEqual(immediate.setup.movesCompleted.map(({ variant, track }) => [variant, track]),
        [["C", "V1"], ["C", "A1"], ["B", "V1"], ["B", "A1"]]);
    const [a, b, c] = immediate.variants;
    const mutations = f.events.filter(([op]) => ["speed", "out", "end"].includes(op));
    assert.deepEqual(mutations.map(event => event.slice(0, 3)), [
        ["speed", "V1", 125], ["speed", "A1", 125], ["end", "V1", 125], ["end", "A1", 125],
        ["speed", "V1", 375], ["speed", "A1", 375], ["out", "V1", 375], ["end", "V1", 375],
        ["out", "A1", 375], ["end", "A1", 375], ["speed", "V1", 625], ["speed", "A1", 625]
    ]);
    for (let i = 0; i < plans.length; i++) {
        const plan = plans[i], variant = immediate.variants[i];
        assert.equal(variant.startFrame, plan.startFrame);
        for (const [kind, label] of [["video", "V1"], ["audio", "A1"]]) {
            const entry = variant[kind], request = plan[kind];
            assert.deepEqual(mutations.find(([op, track, start]) => op === "speed" && track === label && start === plan.cutStartFrame),
                ["speed", label, plan.cutStartFrame, 250 / request.targetFrames, request.durationTimecode, false, false, plan.id === "C"]);
            assert.equal(entry.afterSetSpeed.durationFrames, request.remainingMediaFrames);
            assert.equal(entry.afterSetSpeed.sourceSpanFrames < 250, true);
            assert.equal(entry.immediate.speed, 250 / request.targetFrames);
            assert.equal(entry.capRuleHeld, true);
            assert.equal(entry.later, null);
        }
    }
    const [aEnd, bOut, bEnd] = [mutations[2], mutations[6], mutations[7]];
    assert.equal(aEnd[3], plans[0].video.endTicks);
    assert.equal(bOut[3], String(Number(b.video.afterSetSpeed.inTicks) + 806 * timebase));
    assert.equal(bEnd[3], plans[1].video.endTicks);
    assert.equal(a.video.immediate.outTicks, a.video.afterSetSpeed.outTicks);
    assert.equal(b.video.immediate.sourceSpanFrames, 250);
    assert.equal(c.video.immediate.durationFrames, 500);
    assert.match(f.call().error, /each contain exactly one clip/);

    const mutationCount = f.events.length;
    const freshClips = f.tracks.V1.map(item => ({ ...item }));
    freshClips.numItems = freshClips.length;
    const freshA = freshClips.find(item => item.nodeId === a.video.before.nodeId);
    freshA.outPoint = { ticks: String(Number(freshA.inPoint.ticks) + 1056 * timebase) };
    f.project.activeSequence = { ...f.sequence, videoTracks: Object.assign([{ clips: freshClips }], { numTracks: 1 }) };
    const report = f.reread(immediate);
    assert.equal(report.ok, true);
    assert.equal(f.events.length, mutationCount);
    assert.equal(report.variants[0].video.inOutChanged, true);
    assert.equal(report.variants[0].audio.inOutChanged, false);
    assert.equal(report.variants[0].video.later.sourceSpanFrames, 250);
    assert.deepEqual(report.variants[0].video.qeLater, {
        start: time(125).ticks, end: time(1181).ticks, inPoint: a.video.immediate.inTicks, outPoint: null
    });
    assert.equal(report.variants[0].video.qeInOutChanged, null);
    assert.deepEqual(report.variants.map(v => v.summary), [
        { reachedTarget: true, sourceSpanPreservedImmediate: false, sourceSpanPreservedLater: false, anythingElseMoved: false },
        { reachedTarget: true, sourceSpanPreservedImmediate: true, sourceSpanPreservedLater: true, anythingElseMoved: false },
        { reachedTarget: false, sourceSpanPreservedImmediate: false, sourceSpanPreservedLater: false, anythingElseMoved: false }
    ]);
    assert.deepEqual(report.timelineChangesBetweenCalls, []);
    f.project.activeSequence.sequenceID = "other";
    assert.match(f.reread(immediate).error, /changed before the later read/);
}
for (const [options, check] of [
    [{ cappedTracks: [] }, (f, report) => {
        assert.equal(f.events.some(([op]) => ["out", "end"].includes(op)), false);
        assert.equal(report.variants.every(v => v.summary.reachedTarget && v.summary.sourceSpanPreservedLater), true);
    }],
    [{ outExtendsEnd: true }, (f, report) => {
        assert.equal(f.events.some(([op, , start]) => op === "end" && start === 375), false);
        assert.equal(report.variants[1].summary.reachedTarget, true);
    }],
    [{ rippleBypassesCap: true, rippleMovesMarker: true }, (f, report) => {
        const c = report.variants[2];
        assert.deepEqual(c.summary, { reachedTarget: true, sourceSpanPreservedImmediate: true,
            sourceSpanPreservedLater: true, anythingElseMoved: true });
        assert.equal(c.otherTimelineChanges[0].after.nodeId, "marker");
    }],
    [{ rejectOut: true }, (f, report) => {
        assert.equal(report.ok, false);
        assert.match(report.variants[1].video.errors[0], /outPoint: Out refused/);
        assert.equal(report.variants[1].summary.sourceSpanPreservedLater, false);
        assert.ok(report.variants[2].video.later);
    }]
]) {
    const f = fixture(options), immediate = f.call(f.call().expected);
    assert.equal(immediate.ok, true, immediate.error);
    check(f, f.reread(immediate));
}

for (const [options, error] of [
    [{ refuseRazor: true }, /Linked razor failed/],
    [{ unlinkedRazor: true }, /planned number of pieces/],
    [{ refuseMove: true }, /placement changed the planned span/]
]) {
    const f = fixture(options), report = f.call(f.call().expected);
    assert.equal(report.ok, false);
    assert.match(report.error, error);
    assert.equal(f.events.some(([op]) => ["speed", "out", "end"].includes(op)), false);
}

assert.throws(() => scriptFor([...command, "250"]), /Usage: slowcap-auto/);
assert.match(fixture({ loadError: true }).call().error, /Probe load failed: .*Illegal reserved word.*line 42/);

async function checkBridge({ valid = true, changeBeforeLater = false }) {
    const f = fixture(), output = [], calls = [], module = { exports: {} }, process = {};
    if (!valid) f.sequence.name = "Original";
    class MockSocket {
        constructor() {
            this.events = {};
            queueMicrotask(() => this.events.open());
        }
        addEventListener(name, handler) { this.events[name] = handler; }
        send(packet) {
            const { expression } = JSON.parse(packet).params;
            const window = { __adobe_cep__: { evalScript(script, callback) {
                calls.push(script);
                if (script.includes(".run(")) {
                    assert.deepEqual(f.events, []);
                    assert.equal(f.loads.length, 1);
                    assert.equal(output.length, 1);
                    assert.equal(output[0].channel, "stderr");
                    assert.equal(output[0].json.plannedChange.variants[2].video.targetFrames, 556);
                }
                if (script.includes(".reread(")) {
                    assert.equal(f.events.filter(([op]) => op === "speed").length, 6);
                    if (changeBeforeLater) f.project.activeSequence = null;
                }
                callback(f.evaluate(script));
            } } };
            vm.runInNewContext(expression, { window }).then(value => {
                this.events.message({ data: JSON.stringify({ id: 1, result: { result: { value } } }) });
            }).catch(() => this.events.error());
        }
        close() {}
    }
    const panel = { type: "page", title: "Premiere Voice Sync", url: "file:///panel/index.html", webSocketDebuggerUrl: "ws://localhost:8099/panel" };
    const bridgePath = require.resolve("../../tools/probes/run-probe");
    vm.runInNewContext(fs.readFileSync(bridgePath, "utf8"), {
        module, require, __dirname: path.dirname(bridgePath), process, URL, AbortSignal, setTimeout, clearTimeout, WebSocket: MockSocket,
        fetch: async () => ({ ok: true, json: async () => [panel] }),
        console: {
            error: value => output.push(value.startsWith("{") ?
                { channel: "stderr", json: JSON.parse(value) } : { channel: "summary", value }),
            log: value => output.push({ channel: "stdout", json: JSON.parse(value) })
        }
    });
    await module.exports.main(command);
    assert.deepEqual(output.map(line => line.channel), valid ? ["stderr", "summary", "summary", "summary", "stdout"] : ["stdout"]);
    const report = output.at(-1).json;
    assert.equal(report.ok, valid && !changeBeforeLater);
    assert.equal(calls.length, valid ? 3 : 1);
    assert.match(calls[0], /\.preview\(/);
    if (valid) {
        assert.match(output[1].value, /^A @ frame 125 \{"reachedTarget":true,/);
        assert.match(output[2].value, /^B @ frame 1206 /);
        assert.match(output[3].value, /^C @ frame 2037 /);
        assert.match(calls[1], /\.run\(/);
        assert.match(calls[2], /\.reread\(/);
        assert.equal(report.variants[0].video.immediate.durationFrames, 1056);
        if (changeBeforeLater) {
            assert.match(report.laterReadError, /changed before the later read/);
            assert.equal(report.variants[0].video.later, null);
            assert.equal(process.exitCode, 1);
        } else {
            assert.equal(report.variants[0].video.later.durationFrames, 1056);
        }
    } else {
        assert.match(report.error, /disposable sequence/);
        assert.equal(process.exitCode, 1);
        assert.deepEqual(f.events, []);
    }
}

Promise.all([checkBridge({}), checkBridge({ valid: false }), checkBridge({ changeBeforeLater: true })]).then(() => {
    console.log("SLOWED_PIECE_CAP_PROBE_MOCK_OK:ES3;guards;prewrite preview;linked layout;A/B/C calls;fresh readback");
}).catch(error => { console.error(error); process.exitCode = 1; });
