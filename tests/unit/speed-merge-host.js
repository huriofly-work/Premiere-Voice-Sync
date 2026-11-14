"use strict";
const assert = require("assert"), fs = require("fs"), path = require("path"), vm = require("vm");
const source = fs.readFileSync(path.join(__dirname, "../../extension/jsx/host.jsx"), "utf8");
let appRead = 0;
const context = { $: { _PVS: {} }, app: { get project() { appRead++; throw Error("Must validate before touching Premiere"); } } };
vm.runInNewContext(source, context);
const api = context.$._PVS;
function fixture() {
  function segment(index, kind, sourceStart, sourceEnd, start, end) {
    return { Kind: kind, SourceStartFrame: sourceStart, SourceEndFrame: sourceEnd, NewStartFrame: start, NewEndFrame: end,
      SourceStart: sourceStart / 30, SourceEnd: sourceEnd / 30, NewStart: start / 30, NewEnd: end / 30,
      SourceDurationFrames: sourceEnd - sourceStart, OutputDurationFrames: end - start,
      OriginalVoiceStartFrame: start, OriginalVoiceEndFrame: end,
      VisualDurationFrames: end - start, EffectiveSourceDurationFrames: sourceEnd - sourceStart,
      AppliedSpeedPercent: 100 * (sourceEnd - sourceStart) / (end - start), Chapter: index, BorrowFrames: 0, TrimTailFrames: 0 };
  }
  const segments = [segment(0, "retime", 0, 40, 0, 100), segment(1, "retime", 40, 140, 100, 200), segment(1, "gap", 140, 170, 200, 230)];
  const visual = Object.assign({}, segments[0], { SourceEndFrame: 140, SourceEnd: 140 / 30, NewEndFrame: 200, NewEnd: 200 / 30,
    SourceDurationFrames: 140, EffectiveSourceDurationFrames: 140, OutputDurationFrames: 200, VisualDurationFrames: 200,
    AppliedSpeedPercent: 70, MemberSegmentIndices: [0, 1] });
  return { schemaVersion: 8, speedMergeTrial: "adjacent-speed-v2", segments, visualSegments: [visual, Object.assign({}, segments[2], { MemberSegmentIndices: [2] })], frameRate: 30, mainVideoSourceEndFrame: 170, plannedMainVideoEndFrame: 230 };
}
let plan = fixture();
const snapshot = JSON.stringify(plan.segments);
assert.strictEqual(api._speedMergeVisualPlans(plan), plan.visualSegments);
assert.strictEqual(JSON.stringify(plan.segments), snapshot); // A2 remains the original three plans.
const stable = { segments: plan.segments };
assert.strictEqual(api._speedMergeVisualPlans(stable), stable.segments);
for (const mutate of [
  p => p.speedMergeTrial = "wrong",
  p => p.visualSegments[0].MemberSegmentIndices = [0, 0],
  p => p.visualSegments[0].MemberSegmentIndices = [0, 1, 2],
  p => p.speedMergeTrial = "adjacent-speed-v1",
  p => p.visualSegments[0].AppliedSpeedPercent = 71,
  p => p.visualSegments[0].SourceEndFrame--,
  p => p.visualSegments[0].BorrowFrames = 1,
  p => p.visualSegments[1].NewEndFrame++,
  p => p.segments[1].Kind = "gap",
  p => p.segments[1].OriginalVoiceStartFrame++,
  p => p.visualSegments.pop(),
  p => p.visualSegments[0].NewStart = NaN
]) {
  plan = fixture(); mutate(plan);
  assert.throws(() => api._speedMergeVisualPlans(plan));
  api._readJsonFile = () => plan;
  const result = JSON.parse(api.executePlan("fixture.json"));
  assert.strictEqual(result.ok, false);
  assert.strictEqual(result.timelineMutated, false);
  assert.strictEqual(appRead, 0);
}
assert(source.includes("var sourcePlan = visualPlans[ps];"));
assert(source.includes("var speechPlan = plan.segments[spi];"));
assert(source.includes("speechIndexByPlanSegment[String(spi)] = speechPlans.length;"));
assert(source.includes("Number(sourceSegments[speedPieceIndex]._PlanSegmentIndex) === Number(speedMarkerSpec.SegmentIndex)"));
console.log("SPEED_MERGE_HOST_OK:stable-bypass;cross-chapter;voice-separate;marker-index-spaces;reject-before-Premiere-mutation");
