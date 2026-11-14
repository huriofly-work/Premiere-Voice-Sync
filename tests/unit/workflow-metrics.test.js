"use strict";
const assert = require("assert"), fs = require("fs"), os = require("os"), path = require("path"), vm = require("vm"), crypto = require("crypto");
const source = fs.readFileSync(path.join(__dirname, "../../extension/js/main.js"), "utf8");
const sandbox = fs.mkdtempSync(path.join(os.tmpdir(), "pvs-metrics-test-"));
assert(path.resolve(sandbox).startsWith(path.resolve(os.tmpdir()) + path.sep));
function fixture(name, options = {}) {
  const data = path.join(sandbox, name), messages = [], clock = { now: Date.now() };
  fs.mkdirSync(data, { recursive: true });
  const io = Object.create(fs);
  if (options.createFailure) io.writeFileSync = () => { throw Error("PRIVATE_PATH_AND_ERROR"); };
  if (options.appendFailure) io.appendFileSync = () => { throw Error("PRIVATE_PATH_AND_ERROR"); };
  class ClockDate extends Date {
    constructor(value) { super(value === undefined ? clock.now : value); }
    static now() { return clock.now; }
  }
  const context = {
    require: n => ({ fs: io, path, child_process: {}, crypto }[n]),
    window: { PvsSecurity: { assertNoLinks(f, p, target) {
      if (!path.resolve(target).startsWith(path.resolve(data) + path.sep) && path.resolve(target) !== path.resolve(data)) throw Error("OUTSIDE_LOG_ROOT");
      if (options.linkFailure) throw Error("LINK_REJECTED_PRIVATE_PATH");
    } } },
    document: { addEventListener() {} }, localStorage: { getItem() { return null; } },
    process: { env: {} }, Date: ClockDate, console, fixture: { data, messages }
  };
  vm.runInNewContext(source.replace('  document.addEventListener("DOMContentLoaded", wire);', `
    applicationDataRoot=function(){return fixture.data;};
    log=function(message, level){fixture.messages.push([message,level]);};
    window.metricsApi=createWorkflowMetrics;
  `), context);
  return { create: context.window.metricsApi, data, messages, clock };
}
function read(f) {
  const files = fs.readdirSync(path.join(f.data, "Logs")).filter(n => /^Workflow_/.test(n));
  assert.strictEqual(files.length, 1);
  const text = fs.readFileSync(path.join(f.data, "Logs", files[0]), "utf8");
  return { text, events: text.trim().split(/\n/).map(JSON.parse) };
}
try {
  const f = fixture("success"), m = f.create("auto-edit");
  m.begin("alignment"); f.clock.now += 123;
  m.end({ recognitionBackend: "cuda", recognitionBackendLabel: "PRIVATE_GPU", gpuFallbackUsed: false,
    audioCache: { enabled: true, whisperHits: 4, whisperMisses: 2, quietHits: 3, quietMisses: 1, invalidEntries: 0, writeFailures: 0, transcript: "PRIVATE_SPEECH" },
    captionTimingMode: "dtw-word-boundary-v1", captionTimingRetryRanges: [{ path: "PRIVATE_MEDIA" }], captionTimingEstimatedRanges: [{ text: "PRIVATE_SPEECH" }], captionTimingAcousticBoundaryCount: 7,
    captionCueCount: 12, name: "PRIVATE_SEQUENCE", path: "F:\\PRIVATE_MEDIA.mp3", error: "PRIVATE_ERROR", words: ["PRIVATE_SPEECH"] });
  m.linkTimeline("Performance_20261008_103030_1791430230437_8540722cd83f311376d86898.jsonl");
  m.linkTimeline("C:\\PRIVATE_MEDIA.mp3");
  m.reviewPlan({ referenceQuietRanges: [{ text: "PRIVATE_SPEECH" }], recognitionRejectedRanges: [{ path: "PRIVATE_MEDIA" }],
    reviewMarkers: [{ start: 1, end: 2, cueIndex: 3, reason: "PRIVATE_SPEECH", path: "PRIVATE_MEDIA" }, { start: NaN, end: 5 }] });
  m.begin("caption-import"); f.clock.now += 77; m.end({ captionCueCount: 12 }); m.finish("success");
  const r = read(f), alignment = r.events.find(e => e.type === "stage-end" && e.stage === "alignment");
  const review = r.events.find(e => e.type === "review-plan");
  assert.equal(review.counts.referenceQuietRanges, 1); assert.equal(review.counts.recognitionRejectedRanges, 1);
  assert.equal(review.plannedIssueCount, 2); assert.equal(review.ranges.length, 1);
  assert.equal(review.ranges[0].cueIndex, 3); assert(!/PRIVATE|NaN/.test(JSON.stringify(review)));
  assert.strictEqual(r.events[0].toolVersion,fs.readFileSync(path.join(__dirname,"../../VERSION"),"utf8").trim());
  assert.strictEqual(alignment.milliseconds, 123); assert.strictEqual(alignment.recognitionBackend, "cuda");
  assert.deepStrictEqual(alignment.captionTiming, { mode: "dtw-word-boundary-v1", retryRangeCount: 1, estimatedRangeCount: 1, acousticBoundaryCount: 7 });
  assert.deepStrictEqual(alignment.audioCache, { enabled: true, whisperHits: 4, whisperMisses: 2, quietHits: 3, quietMisses: 1, invalidEntries: 0, writeFailures: 0 });
  assert(!/PRIVATE/.test(r.text)); assert.strictEqual(r.events.filter(e => e.type === "timeline-trace").length, 1);
  assert.strictEqual(r.events.at(-1).processingMilliseconds, 200); assert.strictEqual(r.events.at(-1).outcome, "success");
  m.notification("route","try-foreground-once",{background:true,foregroundEnabled:true,externalEnabled:true,path:"PRIVATE"});
  m.notification("attention","taskbar-flashed");m.notification("native","submitted");
  m.notification("PRIVATE","submitted");m.notification("native","PRIVATE_ERROR");
  const notices=read(f);assert.equal(notices.events.filter(e=>e.type==="notification").length,3);assert(!/PRIVATE/.test(notices.text));
  assert.equal(notices.events.at(-3).foregroundEnabled,true);assert.equal(notices.events.at(-1).value,"submitted");
  const interrupted = fixture("interrupted"), im = interrupted.create("caption-only"); im.begin("caption-import");
  const ie = read(interrupted).events; assert.strictEqual(ie.at(-1).stage, "caption-import"); assert(!ie.some(e => e.type === "finish"));
  const failed = fixture("failed"), fm = failed.create("caption-only"); fm.begin("caption-alignment"); failed.clock.now += 40; fm.end(null, "failed"); fm.begin("cleanup"); fm.end(); fm.finish("failed");
  const fe = read(failed).events; assert.strictEqual(fe.find(e => e.type === "stage-end").outcome, "failed"); assert.strictEqual(fe.at(-1).outcome, "failed");
  const bad = fixture("bad-values"), bm = bad.create("caption-only"); bm.begin("PRIVATE_STAGE"); bm.begin("alignment");
  const cancelled=fixture("cancelled"),cm=cancelled.create("caption-only");cm.begin("caption-alignment");cm.end(null,"cancelled");cm.begin("cleanup");cm.end();cm.finish("cancelled");
  const ce=read(cancelled).events;assert.equal(ce.find(e=>e.type==="stage-end").outcome,"cancelled");assert.equal(ce.at(-1).outcome,"cancelled");
  const paused=fixture("paused"),pm=paused.create("auto-edit");pm.begin("timeline");paused.clock.now+=20;pm.pause(true);pm.pause(true);paused.clock.now+=500;pm.pause(false);pm.pause(false);paused.clock.now+=30;pm.end();pm.finish("success");
  const pe=read(paused).events;assert.equal(pe.filter(e=>e.type==="pause-start").length,1);assert.equal(pe.find(e=>e.type==="pause-end").milliseconds,500);assert.equal(pe.find(e=>e.type==="stage-end").milliseconds,50);assert.equal(pe.at(-1).processingMilliseconds,50);assert.equal(pe.at(-1).pausedMilliseconds,500);
  bm.end({ recognitionBackend: "PRIVATE_BACKEND", audioCache: { enabled: true, whisperHits: "PRIVATE", whisperMisses: NaN, quietHits: -1, quietMisses: Infinity }, captionCueCount: "PRIVATE" }); bm.finish("success");
  assert(!/PRIVATE|NaN|Infinity/.test(read(bad).text));
  const exportFailure=fixture("export-failure"), ef=exportFailure.create("caption-only");
  ef.begin("audio-export");ef.end({exportFailurePhase:"native-export",error:"PRIVATE_MEDIA_PATH"},"failed");
  ef.begin("audio-export");ef.end({exportFailurePhase:"PRIVATE_TEXT"},"failed");ef.finish("failed");
  const ee=read(exportFailure);assert.equal(ee.events[2].exportFailurePhase,"native-export");assert(!ee.text.includes("PRIVATE"));assert(!("exportFailurePhase" in ee.events[4]));
  const settingsRun=fixture("effective-settings"),sm=settingsRun.create("auto-edit");sm.begin("sentence-plan");
  sm.end({minNoDialogueGapSeconds:0.5,speedWarningMinPercent:70,speedWarningMaxPercent:130,settings:{voiceGroupGapSeconds:2,maxCaptionCharacters:42,path:"PRIVATE"}});
  assert.deepEqual(read(settingsRun).events.find(e=>e.type==="stage-end").effectiveSettings,{minNoDialogueGapSeconds:0.5,speedWarningMinPercent:70,speedWarningMaxPercent:130,voiceGroupGapSeconds:2,maxCaptionCharacters:42});
  assert(!read(settingsRun).text.includes("PRIVATE"),"Only numeric consumed settings persist after temporary jobs are removed.");
  const detailed=fixture("export-timings"),dm=detailed.create("caption-only");
  dm.audioExport("render","start",0);assert.equal(read(detailed).events.length,1,"Only record during the audio-export stage");
  dm.begin("audio-export");dm.audioExport("prepare","start");dm.audioExport("prepare","end",undefined,147000,{ok:true,audioExportTiming:{hostMilliseconds:12,path:"PRIVATE_PATH"}});
  dm.audioExport("yield","end",0,100);dm.audioExport("render","start",0);dm.audioExport("render","end",0,8010,{ok:true,audioExportTiming:{hostMilliseconds:8005,nativeMilliseconds:8000,finalizeMilliseconds:5,error:"PRIVATE"}});
  dm.audioExport("PRIVATE","end",0,1);dm.audioExport("render","PRIVATE",0,1);dm.audioExport("render","end",NaN,Infinity,{ok:false,audioExportTiming:{hostMilliseconds:-1,nativeMilliseconds:NaN,finalizeMilliseconds:"PRIVATE"}});dm.finish("success");
  const de=read(detailed),render=de.events.find(e=>e.type==="audio-export-end"&&e.nativeMilliseconds===8000);
  assert.equal(render.milliseconds,8010);assert.equal(render.hostMilliseconds,8005);assert.equal(render.finalizeMilliseconds,5);assert.equal(render.rangeIndex,0);assert.equal(render.outcome,"success");assert(!/PRIVATE|NaN|Infinity/.test(de.text));
  for (const opt of [{ createFailure: true }, { appendFailure: true }, { linkFailure: true }]) {
    const e = fixture(Object.keys(opt)[0], opt), em = e.create("auto-edit");
    assert.doesNotThrow(() => { em.begin("timeline"); em.end(); em.finish("success"); });
    assert.strictEqual(e.messages.filter(x => x[1] === "warn").length, 1);
    assert(!e.messages.some(x => /PRIVATE/.test(x[0])));
  }
  const retained = fixture("retention"), root = path.join(retained.data, "Logs"); fs.mkdirSync(root);
  const own = i => "Workflow_20260901_010000_1791430230437_" + i.toString(16).padStart(24, "0") + ".jsonl";
  for (let i = 0; i < 102; i++) { const p = path.join(root, own(i)); fs.writeFileSync(p, "{}"); fs.utimesSync(p, new Date(retained.clock.now - 2 * 86400000), new Date(retained.clock.now - 2 * 86400000 - i)); }
  const expired = path.join(root, own(102)); fs.writeFileSync(expired, "{}"); fs.utimesSync(expired, new Date(retained.clock.now - 31 * 86400000), new Date(retained.clock.now - 31 * 86400000));
  for (const n of ["Failure_keep.log", "Performance_keep.jsonl", "Workflow_my_personal_file.jsonl"]) fs.writeFileSync(path.join(root, n), "KEEP");
  fs.mkdirSync(path.join(root, own(103)));
  retained.create("auto-edit");
  assert.strictEqual(fs.readdirSync(root).filter(n => /^Workflow_\d/.test(n) && fs.statSync(path.join(root, n)).isFile()).length, 100);
  assert(!fs.existsSync(expired)); assert(fs.statSync(path.join(root, own(103))).isDirectory());
  assert.strictEqual(fs.readFileSync(path.join(root, "Workflow_my_personal_file.jsonl"), "utf8"), "KEEP");
  console.log("WORKFLOW_METRICS_OK:persisted-stages;cache-counts;privacy-allowlist;crash-evidence;failure-isolation;owned-retention");
} finally { fs.rmSync(sandbox, { recursive: true, force: true }); }
