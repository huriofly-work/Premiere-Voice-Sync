"use strict";
const assert = require("assert"), fs = require("fs"), path = require("path"), vm = require("vm");
const source = fs.readFileSync(path.join(__dirname, "../../extension/jsx/host.jsx"), "utf8");
const executorStart = source.indexOf("$._PVS.executePlan = function");
const cleanupEnd = source.indexOf("\n    report.cleanupError = cleanupError;", executorStart);
const marker = "\n    } finally {";
const cleanupStart = source.lastIndexOf(marker, cleanupEnd);
assert(executorStart >= 0 && cleanupStart > executorStart && cleanupEnd > cleanupStart);
const cleanup = source.slice(cleanupStart + marker.length, cleanupEnd).replace(/\n    }\s*$/, "");

function runCleanup(original, active, failOpen, failRead) {
  const calls = [], reads = [];
  const project = {
    get activeSequence() { reads.push("active"); if (failRead) throw Error("read failed"); return active; },
    openSequence(id) { calls.push(id); if (failOpen) throw Error("open failed"); return true; }
  };
  const error = vm.runInNewContext("(function () { var cleanupError = ''; " + cleanup + "; return cleanupError; })()", { original, app: { project } });
  return { error, calls, reads };
}
let result = runCleanup({ sequenceID: "same" }, { sequenceID: "same" });
assert.deepStrictEqual(result.calls, []);
assert.strictEqual(result.error, "");
assert.deepStrictEqual(runCleanup({ sequenceID: 42 }, { sequenceID: "42" }).calls, []);
assert.deepStrictEqual(runCleanup({ sequenceID: "original" }, { sequenceID: "other" }).calls, ["original"]);
assert.deepStrictEqual(runCleanup({ sequenceID: "original" }, null).calls, ["original"]);
result = runCleanup(null, null, true, true);
assert.deepStrictEqual(result.calls, []);
assert.deepStrictEqual(result.reads, []);
assert.strictEqual(result.error, "");
assert.strictEqual(runCleanup({ sequenceID: "original" }, null, true).error, "open original: open failed; ");
assert.strictEqual(runCleanup({ sequenceID: "original" }, null, false, true).error, "open original: read failed; ");

// Actual executor preflight failures must not reactivate an unchanged sequence.
// No QE, tracks, import, save or timeline mutation exists in this mock.
function preflight(activeAtEnd, failOpen) {
  const calls = []; let reads = 0;
  const project = {
    get activeSequence() { return ++reads === 1 ? { sequenceID: "original" } : activeAtEnd; },
    openSequence(id) { calls.push(id); if (failOpen) throw Error("restore failed"); }
  };
  const context = { $: { _PVS: {} }, app: { project } };
  vm.runInNewContext(source, context);
  context.$._PVS._readJsonFile = () => ({ schemaVersion: 8, sequenceId: "wrong", segments: [] });
  const report = JSON.parse(context.$._PVS.executePlan("mock-plan.json"));
  assert.strictEqual(report.ok, false);
  assert.strictEqual(report.timelineMutated, false);
  assert.strictEqual(report.error, "Active sequence ID does not match direct plan.");
  return { calls, report };
}
assert.deepStrictEqual(preflight({ sequenceID: "original" }).calls, []);
assert.deepStrictEqual(preflight({ sequenceID: "other" }).calls, ["original"]);
assert.deepStrictEqual(preflight(null).calls, ["original"]);
assert.strictEqual(preflight(null, true).report.cleanupError, "open original: restore failed; ");
console.log("HOST_SEQUENCE_RESTORE_OK:same-ID-no-open;different-ID-restore;missing-active-restore;no-original-no-read;cleanup-errors;executor-preflight");
