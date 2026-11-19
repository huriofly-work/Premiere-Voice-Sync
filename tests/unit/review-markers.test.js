"use strict";
const markerBounds=require("./marker-bounds");
const assert = require("assert"), fs = require("fs"), path = require("path"), vm = require("vm");
const root = path.join(__dirname, "../..");
const main = fs.readFileSync(path.join(root, "extension/js/main.js"), "utf8");
const start = main.indexOf("  function buildReviewMarkers("), end = main.indexOf("  function logReviewMarkers(", start);
assert(start > 0 && end > start);
const ui = vm.createContext({ fixedAlgorithm: { confidence: 0.55 } });
vm.runInContext(main.slice(start, end), ui);
const build = (report, plan) => JSON.parse(JSON.stringify(ui.buildReviewMarkers(report, plan)));
// Issue #28: exercise panel-to-host comments, with short Caption notes.
{
  const context = vm.createContext({ $: { _PVS: {} } });
  vm.runInContext(fs.readFileSync(path.join(root, "extension/jsx/host.jsx"), "utf8"), context);
  const tag = "[PremiereVoiceSync:caption:captions]", failures = [];
  function comments(issues) {
    const values = [];
    const markers = { getFirstMarker: () => values[0] || null, getNextMarker: m => values[values.indexOf(m) + 1] || null,
      deleteMarker: m => values.splice(values.indexOf(m), 1), createMarker: seconds => {
        const m=markerBounds({ name: "", comments: "",  setColorByIndex(c) { this.color = c; }, getColorByIndex() { return this.color; } }, seconds);
        values.push(m); return m;
      } };
    const clip={start:{seconds:0},end:{seconds:30},inPoint:{seconds:0},outPoint:{seconds:30},getSpeed:()=>1,projectItem:{nodeId:"voice",getMarkers:()=>markers}};
    const stats = context.$._PVS._applyCaptionMarkers({ timebase: 254016000000 / 30, sequenceID:"s" }, issues, [{ start: 0, end: 30 }], null,[clip]);
    assert.equal(stats.reviewMarkerFailureCount, 0);
    assert.equal(values.length, 1);
    return values[0].comments;
  }
  function test(name, fn) { try { fn(); console.log("SHORT_MARKER_PASS: " + name); } catch (e) { failures.push(name + ": " + e.message); } }
  const block = { cueIndex: 3, cueIndices: [8], captionCells: [{ Text: "ASR variant", ReferenceCueIndices: [] }] };
  const captions = [{ Index: 4, SourceCueIndex: 3, Start: 1, End: 2, ManualCaptionCellIndex: 0, CaptionTimingQuality: "estimated" },
    { Index: 5, SourceCueIndex: 3, Start: 2, End: 3, CaptionTimingQuality: "dtw", IndependentSpeechEdges: true }];
  test("manual timing and text merge on final Cue", () => {
    const note = comments(build({ autoEditManualReviewBlocks: [block] }, { captions }));
    assert.equal(note, "Cue 4: chữ khác SRT, timing ước lượng – nghe lại\n" + tag);
    assert(!/Đoạn phân tích|\[\d.*s\]/.test(note));
  });
  test("final caption range Cue 20–24", () => {
    const p = { captions: Array.from({ length: 5 }, (_, i) => ({ Index: 20 + i, SourceCueIndex: 3, Start: 1 + i, End: 2 + i })) };
    assert.equal(comments(build({ autoEditManualReviewBlocks: [{ cueIndex: 3, cueIndices: [8] }] }, p)), "Cue 20–24: timing ước lượng – kiểm mép\n" + tag);
  });
  test("uncovered issue has no cue label", () => {
    assert.equal(comments(build({ captionTimingEstimatedRanges: [{ start: 7, end: 8 }] }, null)), "Timing ước lượng – kiểm tra\n" + tag);
  });
  test("duplicate comments collapse despite different bounds", () => {
    assert.equal(comments([{ start: 1, end: 2, captionIndex: 4, reason: "chữ khác SRT – nghe lại" },
      { start: 1.001, end: 3, captionIndex: 4, reason: "chữ khác SRT – nghe lại" }]), "Cue 4: chữ khác SRT – nghe lại\n" + tag);
  });
  test("caption-only uses final caption indices", () => {
    assert.equal(comments(build({ reviewCueRanges: [{ Index: 3, Start: 1, End: 2 }],
      reviewCaptionRanges: [{ Index: 9, SourceCueIndex: 3, Start: 1, End: 2 }], captionTimingReviewCues: [3] }, null)),
    "Cue 9: timing chưa xác minh – kiểm mép\n" + tag);
  });
  test("uncovered issue ignores internal block number", () => {
    assert.equal(comments([{ start: 7, end: 8, cueIndex: 99, reason: "hở hình 3 frame – kiểm tra" }]), "Hở hình 3 frame – kiểm tra\n" + tag);
  });
  test("duplicate still collapses after merge", () => {
    const issues = build({ autoEditManualReviewBlocks: [block] }, { captions });
    assert.equal(comments(issues.concat(issues)), "Cue 4: chữ khác SRT, timing ước lượng – nghe lại\n" + tag);
  });
  test("long notes stay separate without losing reasons", () => {
    const reasons = ["SRT chưa khớp, dùng chữ máy nghe – kiểm tra", "chữ máy nghe (ngoài SRT) – kiểm tra"];
    assert.equal(comments(reasons.map(reason => ({ start: 1, end: 2, captionIndex: 4, reason }))),
      reasons.map(reason => "Cue 4: " + reason).join("\n") + "\n" + tag);
  });
  test("short notes retain both different actions", () => {
    assert.equal(comments(["timing ước lượng – kiểm tra", "timing ước lượng – kiểm mép"].map(reason => ({ start: 1, end: 2, captionIndex: 4, reason }))),
      "Cue 4: timing ước lượng – kiểm tra, kiểm mép\n" + tag);
  });
  test("confidence keeps existing precision", () => {
    for (const confidence of [0.4, 0.526]) {
      assert.equal(build({ cues: [{ Index: 3, Start: 1, End: 2, Confidence: confidence }] }, null)[0].reason,
        "căn lời kém tin cậy (" + confidence + ") – nghe lại");
    }
  });
  test("essential engine reasons stay short", () => {
    for (const [reason, detail] of [["Giữ chữ SRT; chỉ khác cách viết cấp độ La Mã/chữ số", "La Mã/số"],
      ["Giữ nhãn chữ cái SRT đã khớp giữa hai câu lân cận", "nhãn chữ cái"]]) {
      assert.equal(build({ referenceReviewCues: [{ start: 1, end: 2, reason }] }, null)[0].reason, "chữ SRT khác voice (" + detail + ") – nghe lại");
    }
  });
  assert.deepEqual(failures, [], "SHORT_MARKER_REGRESSION_FAILED\n" + failures.join("\n"));
}
const partialReason = "Giữ chữ SRT khớp phần lớn; nhận diện thiếu/khác một vài từ, cần kiểm tra chữ và timing";
const partialMarkers = build({ referenceReviewCues: [{ start: 1, end: 2, cueIndex: 2, reason: partialReason }],
  referenceSupplementRanges: [{ start: 3, end: 4, referenceCueIndices: [5] }, { start: 6, end: 7, referenceCueIndices: [] }] }, null);
assert.equal(partialMarkers.length, 2);
assert(partialMarkers.every(m => m.reason === "chữ máy nghe (ngoài SRT) – kiểm tra"));
assert(!partialMarkers.some(m => m.reason.includes("cue SRT 5")), "Candidate SRT indices are not a localized content diagnosis.");
assert(!partialMarkers.some(m => m.reason.includes("ngoài phần SRT đã xác minh")));
const retainedWithTiming = { referenceReviewCues: [{ start: 1, end: 2, cueIndex: 2, reason: partialReason }],
  captionTimingEstimatedRanges: [{ start: 1, end: 2, reason: "unverified" }] };
assert.equal(build(retainedWithTiming, null).length, 1, "Retained SRT must not hide an independent timing warning.");
assert.equal(retainedWithTiming.referenceReviewCues.length, 1, "Keep diagnostic data in the report/log.");
assert.equal(build({ referenceReviewCues: [{ start: 1, end: 2, reason: "asr-spelling-variant" }] }, null)[0].reason, "chữ SRT khác voice – nghe lại");
const plan = { captions: [
  { Index: 1, SourceCueIndex: 7, Start: 1, End: 2, Text: "Không có số." }, { Index: 2, SourceCueIndex: 7, Start: 2, End: 3, Text: "Năm 1979." },
  { Index: 3, SourceCueIndex: 8, Start: 5, End: 6, Text: "Lời tiếp theo." }
], segments: [
  { Kind: "retime", Chapter: 0, OriginalVoiceStart: 10, OriginalVoiceEnd: 12, NewVoiceStart: 1 },
  { Kind: "retime", Chapter: 0, OriginalVoiceStart: 14, OriginalVoiceEnd: 16, NewVoiceStart: 5 }
], captionMappingReviewCues: [8] };
const report = { cues: [{ Index: 7, Confidence: 0.4 }, { Index: 8, Confidence: 1 }],
  numericCaptionReviewCues: [7], captionTimingReviewCues: [8], acousticEditReviewCues: [8], wordTimingRecoveredCues: [7],
  captionTimingEstimatedRanges: [{ sourceIndex: 0, start: 11, end: 15, reason: "estimated" }] };
const mapped = build(report, plan);
const recoveryMarkers = build({ autoEditReferenceRecoveredCueIndices: [7] }, Object.assign({}, plan, { captionMappingReviewCues: [] }));
assert.deepEqual(recoveryMarkers.map(m => [m.start, m.end, m.cueIndex]), [[1, 2, 7], [2, 3, 7]], "Recovered Auto edit SRT reviews follow every final split caption.");
assert(recoveryMarkers.every(m => m.reason === "đã khôi phục chữ SRT – nghe lại"));
const manualMarkers = build({ autoEditManualReviewBlocks: [{cueIndex:7,cueIndices:[7,8,9]}] }, Object.assign({}, plan, {captionMappingReviewCues:[]}));
assert.deepEqual(manualMarkers.map(m => [m.start,m.end,m.cueIndex]), [[1,3,7]], "A block-level timing review must not expand into one marker per split caption.");
assert(manualMarkers.every(m => m.reason === "timing ước lượng – kiểm mép"));
assert.deepEqual(manualMarkers[0].captionIndices, [1, 2]);
assert(main.includes('manualSummary.pendingReferenceCues'), "Completion separates unmatched text from estimated block timing.");
const denseCaptions=Array.from({length:400},(_,i)=>({Index:i+1,SourceCueIndex:7,Start:10+i/10,End:10+(i+1)/10,Text:"Chữ đã giữ.",ManualCaptionCellIndex:i<390?0:1}));
const denseBlock={cueIndex:7,cueIndices:[7,8],pendingReferenceCueIndices:[8],retainedReferenceCueIndices:[7],captionCells:[{Text:"Chữ SRT đã giữ.",ReferenceCueIndices:[7]},{Text:"Chữ tự nhận diện cần rà.",ReferenceCueIndices:[]}]};
const denseReport={cues:[{Index:7,Confidence:0,ManualEditBlock:true}],captionTimingReviewCues:[7],autoEditManualReviewBlocks:[denseBlock]};
const densePlan={captions:denseCaptions,segments:[],captionMappingReviewCues:[],manualReviewBlocks:[denseBlock]};
const denseMarkers=build(denseReport,densePlan);
assert.deepEqual(denseMarkers.map(m=>[m.start,m.end]),[[10,50],[49,50]],"Four hundred display captions produce one timing region and one localized unmatched-text region.");
assert(!denseMarkers.some(m=>m.reason.includes("kém tin cậy")||m.reason.includes("timing chưa xác minh")),"Synthetic Confidence=0/no-DTW permissions must not become recognition diagnoses.");
assert.equal(denseMarkers[1].reason, "chữ khác SRT – nghe lại");
assert.deepEqual(denseMarkers[1].captionIndices, Array.from({length:10},(_,i)=>391+i), "Review only the raw-ASR cell, without flagging retained SRT text.");
assert.deepEqual(JSON.parse(JSON.stringify(ui.manualReviewSummary(densePlan))),{timingBlocks:1,pendingReferenceCues:1});
const nearPlan=JSON.parse(JSON.stringify(densePlan));
nearPlan.manualReviewBlocks[0].captionCells[1]={Text:"Chữ SRT được phục hồi.",ReferenceCueIndices:[8],RecognitionOriginalText:"Chữ ASR cũ.",ReferenceTextRecovery:"near-match-one-word"};
nearPlan.manualReviewBlocks[0].pendingReferenceCueIndices=[];
nearPlan.manualReviewBlocks[0].retainedReferenceCueIndices=[7,8];
const nearMarkers=build(Object.assign({},denseReport,{autoEditManualReviewBlocks:nearPlan.manualReviewBlocks}),nearPlan);
assert.equal(nearMarkers.length,1,"Near-match recovery removes only text mismatch review.");
assert(!nearMarkers.some(m=>m.reason.includes("chữ khác SRT")));
assert(nearMarkers[0].reason.includes("ước lượng"),"Estimated timing review survives text recovery.");
const timedPlan=JSON.parse(JSON.stringify(densePlan));
timedPlan.captions.forEach(c=>{c.CaptionTimingQuality="dtw";c.IndependentSpeechEdges=true;});
assert.deepEqual(build(denseReport,timedPlan).map(m=>[m.start,m.end]),[[49,50]],"Automatic DTW resolution removes timing review while preserving unresolved wording.");
assert.deepEqual(JSON.parse(JSON.stringify(ui.manualReviewSummary(timedPlan))),{timingBlocks:0,pendingReferenceCues:1});
timedPlan.captions.slice(100,110).forEach(c=>{c.CaptionTimingQuality="estimated";c.IndependentSpeechEdges=false;});
assert.deepEqual(build(denseReport,timedPlan).map(m=>[m.start,m.end]),[[20,21],[49,50]],"Only the contiguous unresolved timing portion is marked.");
assert.equal(build({cues:[{Index:7,Confidence:.2}]},{captions:denseCaptions.slice(0,2)}).length,2,"Real low-confidence nonmanual captions retain their independent warnings.");
assert.throws(()=>build(denseReport,Object.assign({},densePlan,{captions:denseCaptions.slice(0,390)})),/phần chữ nhận diện/);
const gapPlan={frameRate:30,sourceGapReviewRanges:[{leftCue:11,rightCue:12,sourceStartFrame:60,sourceEndFrame:90}],visualSegments:[{SourceStartFrame:0,SourceEndFrame:120,NewStartFrame:0,NewEndFrame:90}]};
assert.deepEqual(build({},gapPlan).map(m=>[m.start,m.end]),[[1.5,2.25]],"Unsplit source gap markers follow final V1 speed, independently of voice/caption mapping.");
assert.equal(build({},gapPlan)[0].reason, "chưa tách khoảng lặng SRT 11–12 – cắt tay");
assert.throws(()=>build({},Object.assign({},gapPlan,{visualSegments:[]})),/khoảng không lời/);
assert.equal(mapped.length, 9);
assert.deepEqual(mapped.filter(m => m.reason === "timing ước lượng – kiểm tra").map(m => [m.start, m.end]), [[2,3],[5,6]], "Map each retained voice interval; exclude removed silence.");
assert(mapped.filter(m => m.cueIndex === 7).every(m => m.start < 3), "Use final caption coordinates after DTW/merge.");
assert.deepEqual(build({ numericCaptionReviewCues: [99] }, Object.assign({},plan,{captionMappingReviewCues:[]})), [], "Numeric refinement failures are diagnostic only.");
assert.throws(() => build({ captionTimingEstimatedRanges: [{start:null,end:15}] }, plan), /marker/);
assert.throws(() => build({ referenceReviewCues: [{start:null,end:2,reason:"bad"}] }), /marker/);
const standalone = build({ reviewCueRanges: [{Index:1,Start:20,End:21,Confidence:1},{Index:2,Start:40,End:41,Confidence:1}],
  reviewCaptionRanges:[{Index:4,SourceCueIndex:2,Start:40,End:41,Text:"Có 98 phần trăm."}],
  numericCaptionReviewCues:[2], captionOverlapReviewCues:[1], referenceReviewCues:[{start:20,end:21,reason:"variant",cueIndex:1}],
  referenceFallbackRanges:[{start:40,end:42}], referenceSupplementRanges:[{start:21,end:22}], referenceSupplementEmptyRanges:[{start:41,end:42}]
}, null);
assert.equal(standalone.length,5); assert(!standalone.some(m=>m.reason.includes("Chưa xác minh timing của số")));
const editedJoin={editedReferenceRanges:[{status:"omitted",chapter:0,start:11,end:15,cueIndices:[2,3]}]};
const joinPlan=Object.assign({},plan,{captionMappingReviewCues:[]});
assert.deepEqual(build(editedJoin,joinPlan).map(m=>[m.start,m.end]),[[2,3],[5,6]],"Omission review uses retained output voice ranges.");
assert.deepEqual(build(editedJoin,null).map(m=>[m.start,m.end]),[[11,15]],"Subtitle-only review stays on the existing timeline.");

// Regression: internal analysis cue 2 spans 20 seconds. The number is in its
// last short caption, never at the beginning of that analysis cue.
const longCueReport={reviewCueRanges:[{Index:2,ReferenceCueIndex:9,Start:5.09,End:25.348,Confidence:1}],numericCaptionReviewCues:[2],reviewCaptionRanges:[
  {Index:3,SourceCueIndex:2,Start:5.09,End:7,Text:"Đoạn này không có số."},
  {Index:4,SourceCueIndex:2,Start:7,End:9,Text:"Vẫn đang nói chuyện."},
  {Index:12,SourceCueIndex:2,Start:23.1,End:25.348,Text:"Khoảng 98 phần trăm người."}
]};
assert.deepEqual(build(longCueReport,null),[],"Do not mark numeric timing in either workflow.");
assert.deepEqual(build({numericCaptionReviewCues:[2],reviewCaptionRanges:[{Index:1,SourceCueIndex:2,Start:1,End:2,Text:"Không có số."}]},null),[]);
const outro=build({reviewCueRanges:[{Index:3,RecognitionSupplement:true}],reviewCaptionRanges:[{Index:665,SourceCueIndex:3,Start:1117.5,End:1119.5,Text:"Xin cảm ơn các Nhà Khám Phá."},{Index:666,SourceCueIndex:3,Start:1119.5,End:1121,Text:"Đã tham gia hội viên của kênh."}],referenceSupplementRanges:[{start:1116.6,end:1137.5,referenceCueIndices:[288,289,290,292,293,294,295,296]}]},null);
assert.equal(outro.length,2);assert.equal(outro[0].start,1117.5);assert.equal(outro[0].end,1119.5);assert.equal(outro[0].captionIndex,665);
assert.equal(outro[0].reason, "chữ máy nghe (ngoài SRT) – kiểm tra");assert.deepEqual(outro[0].captionIndices,[665]);
assert.equal(outro[1].start,1119.5);assert.equal(outro[1].captionIndex,666);assert.deepEqual(outro[1].captionIndices,[666]);
const longAsr=build({reviewCueRanges:[{Index:1,RecognitionSupplement:true}],reviewCaptionRanges:Array.from({length:49},(_,i)=>({Index:i+1,SourceCueIndex:1,Start:i,End:i+1,Text:i===48?"Bộ náo ở câu cuối.":"Lời nhận diện "+i})),referenceSupplementRanges:[{start:0,end:49}]},null);
assert.equal(longAsr.length,49);assert.equal(longAsr[48].start,48);assert.deepEqual(longAsr[48].captionIndices,[49],"Every ASR caption still has its own label and exact marker bounds, including the last caption.");
assert.equal(longAsr[48].reason,"chữ máy nghe (ngoài SRT) – kiểm tra");
assert(main.includes("Không giữ được câu nào từ SRT đã chọn"));
assert(!main.includes('" · dùng nội dung SRT."'),"Selecting an SRT does not mean its text was retained.");
const numberContent=build({referenceNumberReviewCues:[{cueIndex:5,expected:"9 phẩy 46 nghìn tỷ",recognized:"9 46 000 tỷ"}],reviewCaptionRanges:[{Index:9,SourceCueIndex:5,Start:14,End:15,Text:"Khoảng cách đó vào khoảng"},{Index:10,SourceCueIndex:5,Start:15,End:18,Text:"9 phẩy 46 nghìn tỷ kilomet."}]},null);
assert.deepEqual(numberContent,[],"Identified SRT numbers do not require a content comparison marker.");
assert.deepEqual(build({referenceNumberReviewCues:[{cueIndex:99,expected:"13,8",recognized:"13,9"}]},Object.assign({},plan,{captionMappingReviewCues:[]})),[],"Numeric diagnostics do not require caption mapping or block either workflow.");
assert.equal(build({referenceNumberReviewCues:[{cueIndex:5}],captionTimingEstimatedRanges:[{start:15,end:18,reason:"estimated"}]},null).length,1,"Keep independently detected estimated timing warnings.");

const host = vm.createContext({ $:{_PVS:{}} });
vm.runInContext(fs.readFileSync(path.join(root,"extension/jsx/host.jsx"),"utf8"),host);
const apply = host.$._PVS._applyCaptionMarkers;
let stats=apply({timebase:254016000000/30},[{start:1,end:2,reason:"number",captionIndex:12},
  {start:1,end:2,reason:"DTW",severity:"error"}],[{start:0,end:4}],null,[]);
assert.equal(stats.unattachedMarkerCount,2);
assert.equal(stats.reviewMarkerFailureCount,0);
assert.equal(stats.unattachedMarkers[0].cueLabel,"Cue 12");
assert.equal(stats.unattachedMarkers[0].kind,"VOICE SYNC - Caption");
stats=apply({timebase:254016000000/30},[{start:9,end:10,reason:"outside"}],[{start:0,end:4}],null,[]);
assert.equal(stats.reviewMarkerFailureCount,1);
assert(main.includes("plan.reviewMarkers = buildReviewMarkers(alignment, plan)"));
assert(main.includes("result.reviewMarkers = buildReviewMarkers(result, null)"));
{
  const messages=[],scope={log:m=>messages.push(m),runWarning(){}};
  vm.runInNewContext(main.slice(main.indexOf("  function logReviewMarkers("),main.indexOf("  function logReviewMarkers(")+main.slice(main.indexOf("  function logReviewMarkers(")).indexOf("\n  function ",10)),scope);
  scope.logReviewMarkers({captionMarkerCount:2,unattachedMarkerCount:1},[],null);
  assert(messages[0].includes("Caption 2"));
}
console.log("REVIEW_MARKERS_OK:final-timeline-mapping,split-cues,retained-voice-ranges,all-review-types,ownership,scope,rerun,manual-collisions,write-position-color-failures");
