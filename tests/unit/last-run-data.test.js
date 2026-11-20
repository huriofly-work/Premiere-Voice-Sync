"use strict";
const assert = require("assert"), fs = require("fs"), path = require("path"), os = require("os"), vm = require("vm");
const security = require("../../extension/js/security.js");
const source = fs.readFileSync(path.join(__dirname, "../../extension/js/main.js"), "utf8");
const toolVersion = /ExtensionBundleVersion="([^"]+)"/.exec(fs.readFileSync(path.join(__dirname, "../../extension/CSXS/manifest.xml"), "utf8"))[1];
const root = fs.mkdtempSync(path.join(os.tmpdir(), "PVS-LastRun-"));
const tests = [];
function test(name, run) { tests.push({ name, run }); }
function fixture(options = {}) {
  const home = fs.mkdtempSync(path.join(root, "case-")), jobs = path.join(home, "Jobs"), controls = {}, logs = [], storage = new Map();
  const external = path.join(home, "user.wav"); fs.writeFileSync(external, "USER MEDIA");
  const faultFs = Object.create(fs);
  faultFs.unlinkSync = function (file) {
    if (options.trimFailure && file.endsWith(".wav")) throw Error("TRIM_DENIED");
    return fs.unlinkSync(file);
  };
  const context = {
    require: n => ({ fs: faultFs, path, child_process: {} }[n]),
    window: { PvsEditInput:require("../../extension/js/edit-input.js"), PvsSecurity: security },
    document: { getElementById: id => controls[id] || (controls[id] = {}), addEventListener() {} },
    localStorage: { getItem: k => storage.get(k) || null, setItem: (k, v) => storage.set(k, v), removeItem: k => storage.delete(k) },
    process: { env: {} }, fixture: { home, options, logs, sequence: require("./edit-input.test.js")({ voices: [{ ...require("./edit-input.test.js")().voices[0], path: external }] }) }, console
  };
  vm.runInNewContext(source.replace('  document.addEventListener("DOMContentLoaded", wire);', `
    applicationDataRoot = function () { return fixture.home; };
    extensionRoot = function () { return fixture.home; };
    setWorkflowBusy = function (busy) { state.workflowBusy = busy; };
    confirmWorkflowNotice = async function () { return true; };
    readSettings = function () { return settingDefaults; };
    readVoiceLanguage = function () { return "vi"; };
    readCaptionSettings = function () { return { maxCaptionCharacters: 42, language: "vi" }; };
    readSequenceScan= async function () { return fixture.sequence; };
    state.captionPlan = { key: "fixture", input: {}, ranges: [{ start: 0, end: 10 }] };
    var captionState = { ok: true, count: 0, bins: 0, inPoint: 0, outPoint: 10 };
    scanCaptionRange = async function () { return { projectId: "project", sequenceId: "seq", snapshot: "base", frameRate: 30, plan: state.captionPlan, captionState: captionState }; };
    findWavePreset = function () { return "fixture.epr"; };
    createWorkflowMetrics = function () { return { begin: function () {}, end: function () {}, finish: function () {}, reviewPlan: function () {} }; };
    log = function (message, level) { fixture.logs.push({ message: message, level: level }); };
    status = renderBackend = logCaptionTiming = function () {};
    exportCaptionAudio = async function () { return { ok: true, restored: true }; };
    evalHost = async function (expression) {
      if (expression.includes("restorePendingCaptionAudioExport")) return { ok: false, restored: false, error: "RESTORE_FAILED" };
      if (expression.includes("scanCaptionRange")) return captionState;
      return { ok: true, captionCreated: true, captionCueCount: 1 };
    };
    executeStagedPlan = async function () { return { ok: true, executorVersion: 25 }; };
    runPowerShell = async function (script, args) {
      var folder = runContext.outputFolder;
      var nested = path.join(folder, "analysis"); fs.mkdirSync(nested, { recursive: true });
      ["timeline-0.wav", "recognition-000.wav", "analysis/retry-timing-1.wav", "analysis/converted.pcm"].forEach(function (name) { fs.writeFileSync(path.join(folder, name), "AUDIO"); });
      ["notes.txt", "captions.srt", "plan.json", "engine.log", "native-progress.jsonl"].forEach(function (name) { fs.writeFileSync(path.join(folder, name), "DIAGNOSTIC"); });
      if (fixture.options.journal) fs.writeFileSync(path.join(folder, "job.json.audio-recovery.json"), "RECOVERY");
      if (fixture.options.failed) throw new Error("ENGINE_FAILED");
      if (fixture.options.cancelled) throw stoppedError();
      var plan = { ok: true, schemaVersion: 8, sequenceId: "seq", summary: { captionCueCount: 1 } };
      var reports = {
        "alignment-result.json": {}, "sentence-edit-plan.json": plan,
        "dtw-trial-report.json": { ok: true, revision: "dtw-additive-v1", canApply: false, addedCutCount: 0 },
        "speed-merge-report.json": { ok: true, revision: "adjacent-speed-v2", canApply: false, coverageVerified: true, voiceUnchanged: true, captionsUnchanged: true, durationChangedFrames: 0, newPauses: 0, summary: { mergeCount: 0 }, planPath: path.join(folder, "speed-merge-trial", "sentence-edit-plan.json") },
        "caption-result.json": { ok: true, workflow: "caption-only", schemaVersion: 1, captionCueCount: 1, language: "vi" }
      };
      Object.keys(reports).forEach(function (name) { fs.writeFileSync(path.join(folder, name), JSON.stringify(reports[name])); });
      fs.mkdirSync(path.join(folder, "speed-merge-trial"), { recursive: true });
      fs.writeFileSync(path.join(folder, "speed-merge-trial", "sentence-edit-plan.json"), JSON.stringify(Object.assign({}, plan, { speedMergeTrial: "adjacent-speed-v2", visualSegments: [] })));
    };
    state.targetSrt = path.join(fixture.home, "reference.srt"); fs.writeFileSync(state.targetSrt, "REFERENCE");
    window.api = { edit: runSync, captions: runCaptions, cleanup: cleanupStaleJobs, prune: function (root, workflow, current) { cleanupPreviousJobs(root, workflow, current); }, active: function (folder) { runContext = folder ? { outputFolder: folder } : null; } };
  `), context);
  function job(name, workflow, finishedAt = "2026-01-01T00:00:00.000Z", outcome = "success") {
    const folder = path.join(jobs, name); fs.mkdirSync(folder, { recursive: true });
    if (workflow) fs.writeFileSync(path.join(folder, "last-run.json"), JSON.stringify({ workflow, outcome, finishedAt, toolVersion }));
    fs.writeFileSync(path.join(folder, "keep.txt"), "KEEP"); return folder;
  }
  return { api: context.window.api, jobs, home, logs, external, job, options };
}
function folders(f) { return fs.readdirSync(f.jobs).map(n => path.join(f.jobs, n)); }
function old(folder) { fs.utimesSync(folder, new Date(0), new Date(0)); }
for (const workflow of ["edit", "captions"]) for (const outcome of ["success", "failed", "cancelled"]) {
  test(workflow + ":" + outcome + ":retained-and-trimmed", async () => {
    const f = fixture({ failed: outcome === "failed", cancelled: outcome === "cancelled" });
    await f.api[workflow]();
    const kept = folders(f); assert.equal(kept.length, 1, "last job must remain");
    const record = JSON.parse(fs.readFileSync(path.join(kept[0], "last-run.json"), "utf8"));
    assert.deepEqual(Object.keys(record).sort(), ["finishedAt", "outcome", "toolVersion", "workflow"]);
    assert.equal(record.workflow, workflow); assert.equal(record.outcome, outcome, JSON.stringify(f.logs)); assert.equal(record.toolVersion, toolVersion);
    assert(Number.isFinite(Date.parse(record.finishedAt)));
    for (const name of ["timeline-0.wav", "recognition-000.wav", "analysis/retry-timing-1.wav", "analysis/converted.pcm"]) assert(!fs.existsSync(path.join(kept[0], name)), name);
    for (const name of ["job.json", "notes.txt", "captions.srt", "plan.json", "engine.log", "native-progress.jsonl"]) assert(fs.existsSync(path.join(kept[0], name)), name);
    assert.equal(fs.readFileSync(f.external, "utf8"), "USER MEDIA");
    assert(f.logs.some(l => l.level === "muted" && l.message.includes(kept[0])));
  });
}
for (const workflow of ["edit", "captions"]) test(workflow + ":replace-only-same-workflow", async () => {
  const f = fixture(), prefix = workflow === "edit" ? "Job_" : "Job_Subtitle_", other = workflow === "edit" ? "captions" : "edit";
  const previous = [f.job(prefix + "old1", workflow), f.job(prefix + "old2", workflow)];
  const latestFailure = f.job(prefix + "failed", workflow, "2026-02-01T00:00:00Z", "failed");
  previous.push(f.job(prefix + "older_failure", workflow, "2026-01-01T00:00:00Z", "failed"));
  const untouched = f.job(other === "edit" ? "Job_Other" : "Job_Subtitle_Other", other);
  await f.api[workflow]();
  previous.forEach(p => assert(!fs.existsSync(p), "previous kept job must be removed"));
  assert(fs.existsSync(untouched), "other workflow must remain");
  assert.equal(folders(f).length, 3);
  old(latestFailure);
  f.api.cleanup();
  assert(fs.existsSync(path.join(latestFailure, "keep.txt")), "retain failed diagnostics after a newer success");
});
test("recovery-journal-protected-at-start-and-finish", async () => {
  const f = fixture({ journal: true, failed: true }), previous = f.job("Job_Subtitle_pending", "captions");
  fs.writeFileSync(path.join(previous, "job.json.audio-recovery.json"), "PENDING");
  await f.api.captions();
  assert(fs.existsSync(previous));
  const current = folders(f).find(p => p !== previous); assert(current, "failed job must remain");
  assert(fs.existsSync(path.join(current, "job.json.audio-recovery.json")));
  assert(fs.existsSync(path.join(current, "timeline-0.wav")), "pending journal keeps all recovery files");
  assert.equal(JSON.parse(fs.readFileSync(path.join(current, "last-run.json"))).outcome, "failed");
});
test("stale-cleanup-protects-latest-marked-per-workflow-and-active", () => {
  const f = fixture(), keep = [f.job("Job_latest", "edit", "2026-02-01T00:00:00Z"), f.job("Job_Subtitle_latest", "captions", "2026-02-01T00:00:00Z")];
  const remove = [f.job("Job_old", "edit"), f.job("Job_Subtitle_old", "captions"), f.job("Job_unmarked")];
  const pending = f.job("Job_pending"); fs.writeFileSync(path.join(pending, "job.json.audio-recovery.json"), "PENDING");
  const active = f.job("Job_active"), recent = f.job("Job_recent"), unrelated = f.job("unrelated");
  [...keep, ...remove, pending, active, unrelated].forEach(old); f.api.active(active);
  assert.equal(f.api.cleanup(), remove.length);
  [...keep, pending, active, recent, unrelated].forEach(p => assert(fs.existsSync(p), p));
  remove.forEach(p => assert(!fs.existsSync(p), p));
  assert(fs.existsSync(path.join(pending, "job.json.audio-recovery.json")));
});
test("active-job-never-pruned-at-new-run", async () => {
  const f = fixture(), active = f.job("Job_active", "edit"), current = f.job("Job_current", "edit"); f.api.active(active);
  f.api.prune(f.jobs, "edit", current);
  assert(fs.existsSync(active)); assert(fs.existsSync(current));
});
test("trim-failure-warns-without-changing-outcome", async () => {
  const f = fixture({ trimFailure: true }); await f.api.captions();
  const kept = folders(f); assert.equal(kept.length, 1);
  assert.equal(JSON.parse(fs.readFileSync(path.join(kept[0], "last-run.json"))).outcome, "success");
  assert(f.logs.some(l => l.level === "warn"));
});
test("junction-refused-for-trim-prune-and-stale-delete", async () => {
  const f = fixture(), outside = path.join(f.home, "outside"); fs.mkdirSync(outside); fs.writeFileSync(path.join(outside, "keep.wav"), "SENTINEL");
  const linked = f.job("Job_linked", "edit"), link = path.join(linked, "audio");
  fs.symlinkSync(outside, link, process.platform === "win32" ? "junction" : "dir");
  try {
    await f.api.edit(); assert(fs.existsSync(linked), "pruning must refuse nested junction");
    old(linked); assert.throws(() => f.api.cleanup(), /SECURITY_LINKED_PATH/);
    const captions = fixture();
    // Native export/engine are mocked; introduce a link during engine output creation.
    const write = fs.writeFileSync; let trimLink;
    fs.writeFileSync = function (file) {
      if (String(file).endsWith("caption-result.json") && String(file).startsWith(captions.jobs)) {
        trimLink = path.join(path.dirname(file), "linked-audio"); if (!fs.existsSync(trimLink)) fs.symlinkSync(outside, trimLink, process.platform === "win32" ? "junction" : "dir");
      }
      return write.apply(fs, arguments);
    };
    try { await captions.api.captions(); assert(trimLink && fs.existsSync(trimLink)); assert(captions.logs.some(l => l.level === "warn")); }
    finally { fs.writeFileSync = write; if (trimLink) fs.unlinkSync(trimLink); }
    assert.equal(fs.readFileSync(path.join(outside, "keep.wav"), "utf8"), "SENTINEL");
  } finally { fs.unlinkSync(link); }
});
(async () => {
  let passed = 0;
  for (const t of tests) { try { await t.run(); passed++; } catch (e) { console.error("LAST_RUN_DATA_FAIL:" + t.name + ":" + e.message); } }
  console.log("LAST_RUN_DATA_RESULT:passed=" + passed + ";failed=" + (tests.length - passed) + ";total=" + tests.length);
  if (passed !== tests.length) process.exitCode = 1;
})().finally(() => security.removeOwnedTree(fs, path, root, os.tmpdir()));
