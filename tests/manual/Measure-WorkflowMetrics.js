"use strict";
// Filesystem-only microbenchmark; does not load Premiere, media, model or cache.
const fs = require("fs"), path = require("path"), os = require("os"), vm = require("vm"), assert = require("assert");
const source = fs.readFileSync(path.join(__dirname, "../../extension/js/main.js"), "utf8");
const root = fs.mkdtempSync(path.join(os.tmpdir(), "pvs-log-cost-"));
assert(path.resolve(root).startsWith(path.resolve(os.tmpdir()) + path.sep));
assert(path.basename(root).startsWith("pvs-log-cost-"));
const security = require("../../extension/js/security.js");
const warnings = [];
const context = { require, window: { PvsSecurity: security }, document: { addEventListener() {} }, localStorage: { getItem() { return null; } }, process, console, fixture: { root, warnings } };
vm.runInNewContext(source.replace('  document.addEventListener("DOMContentLoaded", wire);', `
  applicationDataRoot=function(){return fixture.root;};
  log=function(message, level){if(level==="warn")fixture.warnings.push(message);};
  window.metricsApi=createWorkflowMetrics;
`), context);
try {
  const samples = [];
  for (let i = 0; i < 30; i++) {
    const started = process.hrtime.bigint(), recorder = context.window.metricsApi("auto-edit");
    for (const stage of ["preflight", "alignment", "sentence-plan", "dtw-plan", "speed-merge", "template-check", "timeline", "cleanup"]) {
      recorder.begin(stage);
      recorder.end({ recognitionBackend: "cuda", audioCache: { enabled: true, whisperHits: 4, whisperMisses: 0, quietHits: 1, quietMisses: 0, invalidEntries: 0, writeFailures: 0 } });
    }
    recorder.linkTimeline("Performance_20261008_103030_1791430230437_8540722cd83f311376d86898.jsonl");
    recorder.finish("success");
    samples.push(Number(process.hrtime.bigint() - started) / 1e6);
  }
  assert.strictEqual(warnings.length, 0);
  const files = fs.readdirSync(path.join(root, "Logs"));
  assert.strictEqual(files.length, 30);
  for (const name of files) assert.strictEqual(fs.readFileSync(path.join(root, "Logs", name), "utf8").trim().split("\n").length, 19);
  samples.sort((a, b) => a - b);
  console.log(JSON.stringify({ scope: "filesystem-only-not-Premiere", iterations: samples.length, eventsPerRun: 19, minMilliseconds: samples[0], medianMilliseconds: samples[15], maxMilliseconds: samples.at(-1), averageMilliseconds: samples.reduce((a, b) => a + b, 0) / samples.length }));
} finally { fs.rmSync(root, { recursive: true, force: true }); }
