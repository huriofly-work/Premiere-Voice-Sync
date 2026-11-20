"use strict";
const assert = require("assert");
const fs = require("fs");
const path = require("path");
const vm = require("vm");
const { execFileSync } = require("child_process");
const root = path.resolve(__dirname, "../..");

function scanFixture(overrides = {}) {
  return Object.assign({
    ok: true, name: "Template", projectId: "project", sequenceId: "seq", frameRate: 30,
    mainVideoPieceCount: 1, v1LooksNested: true, captionTrackCount: null,
    mainVideoClip: { name: "Nest", start: 0, end: 10, inPoint: 0, speedPercent: 100, isSpeedReversed: false, timeRemap: "none" },
    linkedAudio: [{ name: "Nest", start: 0, end: 10 }], linkedTrackIndex: 0,
    voices: [{ name: "Voice", path: "voice.mp3", start: 0, end: 10, inPoint: 0, speedPercent: 110, isSpeedReversed: false, timeRemap: "none" }]
  }, overrides);
}
module.exports = scanFixture;

if (require.main === module) {
  const failures = [];
  function test(name, body) {
    try { body(); } catch (error) { failures.push(name); console.error(name, error); }
  }
  test("Host scan returns facts and shares marker time mapping", () => {
    const time = seconds => ({ seconds });
    const clip = (name, end, components, reversed) => ({
      name, components, nodeId: name, start: time(0), end: time(end), duration: time(end),
      inPoint: time(0), outPoint: time(end), getSpeed: () => 1,
      projectItem: { getMediaPath: () => name, getMarkers() {} },
      isSpeedReversed: () => !!reversed
    });
    const component = (...properties) => [{ matchName: "Time Remapping", properties: Object.assign(properties, { numItems: properties.length }) }];
    const track = (...clips) => ({ clips: Object.assign(clips, { numItems: clips.length }) });
    const video = clip("Nest", 10, component({ isTimeVarying: () => false }));
    const audio = clip("Nest", 10);
    const voices = [
      clip("plain", 2), clip("reverse", 2, [], true), clip("varying", 2, component({ isTimeVarying: () => true })),
      clip("unreadable", 2, component({})), clip("static", 2, video.components)
    ];
    video.getLinkedItems = () => [Object.assign(audio, { mediaType: "Audio" })];
    const seq = { timebase: 8467200000, videoTracks: Object.assign([track(video)], { numTracks: 1 }),
      audioTracks: Object.assign([track(audio), track(...voices)], { numTracks: 2 }) };
    const context = { $: {}, app: { project: { activeSequence: seq } }, Folder: { startup: { fsName: "/premiere" } } };
    vm.runInNewContext(fs.readFileSync(path.join(root, "extension/jsx/host.jsx"), "utf8"), context);
    const host = context.$._PVS;
    const scan = () => JSON.parse(host.scanSequence());
    const facts = scan();
    assert.strictEqual(facts.captionTrackCount, null);
    assert.strictEqual(facts.mainVideoClip.timeRemap, "static");
    assert.deepStrictEqual(facts.voices.map(v => [v.isSpeedReversed, v.timeRemap]), [
      [false, "none"], [true, "none"], [false, "varying"], [false, "unknown"], [false, "static"]
    ]);
    assert.strictEqual(facts.linkedTrackIndex, 0);
    assert.deepStrictEqual(facts.linkedAudio.map(a => [a.start, a.end]), [[0, 10]]);
    audio.end = time(9);
    assert.strictEqual(scan().linkedTrackIndex, -1);
    seq.captionTracks = { numTracks: 2 };
    assert.strictEqual(scan().captionTrackCount, 2);
    assert.strictEqual(host._clipMarkerMapping(video, true).source(1), 1);
    assert.strictEqual(host._clipMarkerMapping(voices[0], false).timeline(1), 1);
    for (const voice of voices.slice(1)) assert.strictEqual(host._clipMarkerMapping(voice, false), null);
    seq.videoTracks = { numTracks: 0, get 0() { throw Error("V1 does not exist"); } };
    seq.audioTracks = { numTracks: 1, get 1() { throw Error("A2 does not exist"); } };
    assert.strictEqual(scan().mainVideoClip, null);
    assert.deepStrictEqual(scan().voices, []);
    context.app.project.activeSequence = null;
    assert.strictEqual(scan().hasSequence, false);
  });

  test("Template eligibility reports exact reasons", () => {
    const { validateEditInput } = require("../../extension/js/edit-input.js");
    const check = (scan, ...codes) => {
      const result = validateEditInput(scan, { voiceGroupGap: 2 }, p => p === "voice.mp3");
      assert.strictEqual(result.ok, codes.length === 0);
      assert.deepStrictEqual(result.reasons.map(r => r.code).sort(), codes.sort());
      for (const reason of result.reasons) assert.match(reason.message, /[À-ỹ]/);
    };
    const main = patch => scanFixture({ mainVideoClip: { ...scanFixture().mainVideoClip, ...patch } });
    const voice = patch => ({ ...scanFixture().voices[0], ...patch });
    check(scanFixture());
    check(scanFixture({ captionTrackCount: 1 }));
    check(main({ timeRemap: "static" }));
    check(scanFixture({ hasSequence: false }), "NO_SEQUENCE");
    check(scanFixture({ mainVideoClip: null }), "NO_V1");
    check(scanFixture({ linkedAudio: [], linkedTrackIndex: -1 }), "V1_NOT_LINKED");
    check(scanFixture({ linkedTrackIndex: -1 }), "LINKED_AUDIO_MISALIGNED");
    check(scanFixture({ mainVideoPieceCount: 2 }), "ALREADY_CUT");
    check(scanFixture({ voices: [] }), "NO_A2_VOICE");
    check(main({ start: 1 }), "V1_MOVED");
    check(main({ inPoint: 1 }), "V1_HEAD_TRIMMED");
    check(main({ speedPercent: 125 }), "V1_SPEED");
    check(main({ isSpeedReversed: true }), "V1_REVERSED");
    for (const timeRemap of ["varying", "unknown"]) check(main({ timeRemap }), "V1_TIME_REMAP");
    check(scanFixture({ voices: [voice({ inPoint: 1 })] }), "VOICE_HEAD_TRIMMED");
    check(scanFixture({ voices: [voice({ isSpeedReversed: true, inPoint: 1 })] }), "VOICE_REVERSED");
    for (const timeRemap of ["static", "varying", "unknown"]) {
      check(scanFixture({ voices: [voice({ timeRemap })] }), "VOICE_TIME_REMAP");
    }
    for (const speedPercent of [0, 0.5, null, Infinity]) check(scanFixture({ voices: [voice({ speedPercent })] }), "VOICE_SPEED_INVALID");
    check(scanFixture({ voices: [voice({ path: "" })] }), "VOICE_FILE_MISSING");
    check(scanFixture({ voices: [voice({ start: 1 }), voice({ end: 2 })] }), "VOICES_OVERLAP");
    // Touching clips with tick-rounding jitter are not an overlap; a full frame is.
    check(scanFixture({ voices: [voice({ start: 0, end: 4.000000001 }), voice({ start: 4, end: 8 })] }));
    check(scanFixture({ voices: [voice({ start: 0, end: 4 + 1 / 30 }), voice({ start: 4, end: 8 })] }), "VOICES_OVERLAP");
    check(scanFixture({ frameRate: 241 }), "FRAME_RATE_INVALID");
    check(scanFixture({ frameRate: null }), "FRAME_RATE_INVALID");
    check(scanFixture({ voices: [voice({}), voice({ start: 13, end: 15, path: "", isSpeedReversed: true })] }));
    check(scanFixture({ mainVideoPieceCount: 2, frameRate: 0, voices: [voice({ path: "missing.mp3", inPoint: 1 })] }),
      "ALREADY_CUT", "FRAME_RATE_INVALID", "VOICE_FILE_MISSING", "VOICE_HEAD_TRIMMED");
  });

  test("Panel grouping matches the executed PowerShell grouping block", () => {
    const { mainVoiceGroup } = require("../../extension/js/edit-input.js");
    const a = { id: "a", start: 0, end: 2 }, b = { id: "b", start: 4, end: 6 }, c = { id: "c", start: 8.001, end: 10 };
    const fixtures = [{ voices: [a,b,c], gap: 2 }, { voices: [c,b,a], gap: 2 }, { voices: [c,b,a], gap: 3 }];
    const alignment = fs.readFileSync(path.join(root, "extension/engine/run-alignment.ps1"), "utf8");
    const grouping = alignment.match(/^\$allVoiceClips = [\s\S]+?^\$voiceClips = \$voiceList\.ToArray\(\)/m)[0];
    const script = `$ErrorActionPreference='Stop'
      $cases=ConvertFrom-Json '${JSON.stringify(fixtures)}'
      foreach($case in $cases) {
        $job=[pscustomobject]@{sequence=$case}
        $voiceGroupGapSeconds=$case.gap
        ${grouping}
        [Console]::WriteLine(($voiceClips.id -join ','))
      }`;
    const engine = execFileSync("powershell.exe", ["-NoProfile", "-EncodedCommand", Buffer.from(script, "utf16le").toString("base64")],
      { encoding: "utf8", stdio: ["ignore", "pipe", "pipe"] }).trim().split(/\r?\n/);
    const panel = fixtures.map(f => mainVoiceGroup(f.voices, f.gap).map(v => v.id).join(","));
    assert.deepStrictEqual(panel, ["a,b", "a,b", "a,b,c"]);
    assert.deepStrictEqual(panel, engine);
  });
  if (failures.length) process.exitCode = 1;
  else console.log("EDIT_INPUT_OK:host-facts;marker-parity;all-reasons;alignment-grouping");
}
