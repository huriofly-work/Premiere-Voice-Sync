"use strict";
const assert = require("assert"), fs = require("fs"), path = require("path"), vm = require("vm");
const root = path.join(__dirname, "../..");
const main = fs.readFileSync(path.join(root, "extension/js/main.js"), "utf8");
const start = main.indexOf("  function buildReviewMarkers("), end = main.indexOf("  function logReviewMarkers(", start);
assert(start > 0 && end > start);
const ui = vm.createContext({ fixedAlgorithm: { confidence: 0.55 } });
vm.runInContext(main.slice(start, end), ui);
const build = (report, plan) => JSON.parse(JSON.stringify(ui.buildReviewMarkers(report, plan)));
const partialReason = "Giữ chữ SRT khớp phần lớn; nhận diện thiếu/khác một vài từ, cần kiểm tra chữ và timing";
const partialMarkers = build({ referenceReviewCues: [{ start: 1, end: 2, cueIndex: 2, reason: partialReason }],
  referenceSupplementRanges: [{ start: 3, end: 4, referenceCueIndices: [5] }, { start: 6, end: 7, referenceCueIndices: [] }] }, null);
assert.equal(partialMarkers.length, 2);
assert(partialMarkers.every(m => m.reason.includes("Đã thêm chữ tự nhận diện")));
assert(!partialMarkers.some(m => m.reason.includes("cue SRT 5")), "Candidate SRT indices are not a localized content diagnosis.");
assert(!partialMarkers.some(m => m.reason.includes("ngoài phần SRT đã xác minh")));
const retainedWithTiming = { referenceReviewCues: [{ start: 1, end: 2, cueIndex: 2, reason: partialReason }],
  captionTimingEstimatedRanges: [{ start: 1, end: 2, reason: "unverified" }] };
assert.equal(build(retainedWithTiming, null).length, 1, "Retained SRT must not hide an independent timing warning.");
assert.equal(retainedWithTiming.referenceReviewCues.length, 1, "Keep diagnostic data in the report/log.");
assert(build({ referenceReviewCues: [{ start: 1, end: 2, reason: "asr-spelling-variant" }] }, null)[0].reason.includes("asr-spelling-variant"));
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
assert(recoveryMarkers.every(m => m.reason.includes("Đã phục hồi chữ SRT")));
const manualMarkers = build({ autoEditManualReviewBlocks: [{cueIndex:7,cueIndices:[7,8,9]}] }, Object.assign({}, plan, {captionMappingReviewCues:[]}));
assert.deepEqual(manualMarkers.map(m => [m.start,m.end,m.cueIndex]), [[1,3,7]], "A block-level timing review must not expand into one marker per split caption.");
assert(manualMarkers.every(m => m.reason.includes("7, 8, 9") && m.reason.includes("ước lượng")));
assert(main.includes('manualSummary.pendingReferenceCues'), "Completion separates unmatched text from estimated block timing.");
const denseCaptions=Array.from({length:400},(_,i)=>({Index:i+1,SourceCueIndex:7,Start:10+i/10,End:10+(i+1)/10,Text:"Chữ đã giữ.",ManualCaptionCellIndex:i<390?0:1}));
const denseBlock={cueIndex:7,cueIndices:[7,8],pendingReferenceCueIndices:[8],retainedReferenceCueIndices:[7],captionCells:[{Text:"Chữ SRT đã giữ.",ReferenceCueIndices:[7]},{Text:"Chữ tự nhận diện cần rà.",ReferenceCueIndices:[]}]};
const denseReport={cues:[{Index:7,Confidence:0,ManualEditBlock:true}],captionTimingReviewCues:[7],autoEditManualReviewBlocks:[denseBlock]};
const densePlan={captions:denseCaptions,segments:[],captionMappingReviewCues:[],manualReviewBlocks:[denseBlock]};
const denseMarkers=build(denseReport,densePlan);
assert.deepEqual(denseMarkers.map(m=>[m.start,m.end]),[[10,50],[49,50]],"Four hundred display captions produce one timing region and one localized unmatched-text region.");
assert(!denseMarkers.some(m=>m.reason.includes("Độ tin cậy")||m.reason.includes("Chưa xác minh mốc DTW")),"Synthetic Confidence=0/no-DTW permissions must not become recognition diagnoses.");
assert(denseMarkers[1].reason.includes("391–400")&&!denseMarkers[1].reason.includes("Chữ SRT đã giữ"),"Review only the raw-ASR cell, without flagging retained SRT text.");
assert.deepEqual(JSON.parse(JSON.stringify(ui.manualReviewSummary(densePlan))),{timingBlocks:1,pendingReferenceCues:1});
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
assert(build({},gapPlan)[0].reason.includes("chưa có điểm cắt voice an toàn"));
assert.throws(()=>build({},Object.assign({},gapPlan,{visualSegments:[]})),/khoảng không lời/);
assert.equal(mapped.length, 9);
assert.deepEqual(mapped.filter(m => m.reason.includes("estimated")).map(m => [m.start, m.end]), [[2,3],[5,6]], "Map each retained voice interval; exclude removed silence.");
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
assert(outro[0].reason.includes("665")&&outro[0].reason.includes("Xin cảm ơn"));assert(!outro[0].reason.includes("288"));
assert.equal(outro[1].start,1119.5);assert.equal(outro[1].captionIndex,666);assert(outro[1].reason.includes("hội viên"));
const longAsr=build({reviewCueRanges:[{Index:1,RecognitionSupplement:true}],reviewCaptionRanges:Array.from({length:49},(_,i)=>({Index:i+1,SourceCueIndex:1,Start:i,End:i+1,Text:i===48?"Bộ náo ở câu cuối.":"Lời nhận diện "+i})),referenceSupplementRanges:[{start:0,end:49}]},null);
assert.equal(longAsr.length,49);assert.equal(longAsr[48].start,48);assert(longAsr[48].reason.includes("Bộ náo ở câu cuối."),"Every ASR caption has its own full text and exact marker bounds, including beyond 220 characters.");
assert(main.includes("Không giữ được câu nào từ SRT đã chọn"));
assert(!main.includes('" · dùng nội dung SRT."'),"Selecting an SRT does not mean its text was retained.");
const numberContent=build({referenceNumberReviewCues:[{cueIndex:5,expected:"9 phẩy 46 nghìn tỷ",recognized:"9 46 000 tỷ"}],reviewCaptionRanges:[{Index:9,SourceCueIndex:5,Start:14,End:15,Text:"Khoảng cách đó vào khoảng"},{Index:10,SourceCueIndex:5,Start:15,End:18,Text:"9 phẩy 46 nghìn tỷ kilomet."}]},null);
assert.deepEqual(numberContent,[],"Identified SRT numbers do not require a content comparison marker.");
assert.deepEqual(build({referenceNumberReviewCues:[{cueIndex:99,expected:"13,8",recognized:"13,9"}]},Object.assign({},plan,{captionMappingReviewCues:[]})),[],"Numeric diagnostics do not require caption mapping or block either workflow.");
assert.equal(build({referenceNumberReviewCues:[{cueIndex:5}],captionTimingEstimatedRanges:[{start:15,end:18,reason:"estimated"}]},null).length,1,"Keep independently detected estimated timing warnings.");

const host = vm.createContext({ $:{_PVS:{}} });
vm.runInContext(fs.readFileSync(path.join(root,"extension/jsx/host.jsx"),"utf8"),host);
const apply = host.$._PVS._applyReviewMarkers;
const tag = w => "[PremiereVoiceSync:review-marker:v1:"+w+"]";
function fixture(initial=[]) {
  const values=initial.slice(); let colorFault=false, positionFault=false, creationFault=false;
  const markers={getFirstMarker:()=>values[0]||null,getNextMarker:m=>values[values.indexOf(m)+1]||null,
    deleteMarker:m=>values.splice(values.indexOf(m),1),createMarker(seconds){
      if(creationFault)throw Error("CREATE_FAILED");
      const marker={name:"",comments:"",start:{seconds:seconds+(positionFault?1:0)},setColorByIndex(c){if(colorFault)throw Error("COLOR_FAILED");this.color=c;},getColorByIndex(){return this.color;}};
      values.push(marker);return marker;
    }};
  return {seq:{timebase:254016000000/30,markers},values,set colorFault(v){colorFault=v;},set positionFault(v){positionFault=v;},set creationFault(v){creationFault=v;}};
}
const owned=(seconds,w="captions")=>({name:"VOICE SYNC - Can kiem tra",comments:"old\n"+tag(w),start:{seconds}});
const manual={name:"VOICE SYNC - Can kiem tra",comments:"my note",start:{seconds:1}}, other=owned(1.5,"edit"), outside=owned(8);
let f=fixture([manual,other,outside,owned(2)]);
let stats=apply(f.seq,[{start:1,end:3,reason:"number",cueIndex:2,captionIndex:12,referenceCueIndex:9},{start:1,end:2,reason:"DTW",severity:"error"}], [{start:1,end:4}],"captions");
assert.equal(stats.reviewMarkerCount,1);assert.equal(stats.reviewMarkerFailureCount,0);
assert(f.values.includes(manual)&&f.values.includes(other)&&f.values.includes(outside));
assert.equal(manual.comments,"my note");
let warning=f.values.find(m=>m!==outside&&m.comments.includes(tag("captions")));
assert(Math.abs(warning.start.seconds-(1+1/30))<1e-8);assert(warning.comments.includes("number")&&warning.comments.includes("DTW"));assert.equal(warning.color,1);
assert(warning.comments.startsWith("Caption 12 (SRT 9): number"));assert(!warning.comments.includes("Cue 2:"));
stats=apply(f.seq,[{start:1,end:3,reason:"number"}], [{start:1,end:4}],"captions");assert.equal(stats.reviewMarkerCount,1);assert.equal(f.values.length,4,"Reruns upsert and do not duplicate.");
stats=apply(f.seq,[],[{start:1,end:4}],"captions");assert.equal(stats.reviewMarkerFailureCount,0);assert.deepEqual(f.values,[manual,other,outside]);
f=fixture();stats=apply(f.seq,[{start:1,end:2,reason:"first"},{start:1+1/30,end:2,reason:"second"}], [{start:0,end:3}],"edit");assert.equal(stats.reviewMarkerCount,2);assert.equal(f.values.length,2);
f=fixture([manual]);stats=apply(f.seq,[{start:1,end:1+1/30,reason:"blocked"}],[{start:1,end:2}],"captions");assert.equal(stats.reviewMarkerFailureCount,1);assert.equal(manual.comments,"my note");
f=fixture([owned(2)]);f.creationFault=true;stats=apply(f.seq,[{start:1,end:2,reason:"failure"}],[{start:0,end:4}],"captions");assert.equal(stats.reviewMarkerFailureCount,1);assert.equal(f.values.length,1,"Incomplete replacement preserves old warnings.");
f=fixture();f.positionFault=true;stats=apply(f.seq,[{start:1,end:2,reason:"position"}],[{start:0,end:4}],"captions");assert.equal(stats.reviewMarkerFailureCount,1);assert.equal(f.values.length,0);
f=fixture();f.colorFault=true;stats=apply(f.seq,[{start:1,end:2,reason:"color"}],[{start:0,end:4}],"edit");assert.equal(stats.reviewMarkerCount,1);assert.equal(stats.reviewMarkerColorFailureCount,1);assert.equal(stats.reviewMarkerFailureCount,0);
f=fixture([owned(2)]);stats=apply(f.seq,[{start:9,end:10,reason:"outside"}],[{start:0,end:4}],"captions");assert.equal(stats.reviewMarkerFailureCount,1);assert.equal(f.values.length,1);
stats=apply({timebase:254016000000/30},[{start:1,end:2,reason:"api"}],[{start:0,end:4}],"edit");assert.equal(stats.reviewMarkerFailureCount,1);
assert(main.includes("plan.reviewMarkers = buildReviewMarkers(alignment, plan)"));
assert(main.includes("result.reviewMarkers = buildReviewMarkers(result, null)"));
const preservedManual={name:"My review",comments:"User marker",start:{seconds:3}},preservedOther=owned(4,"captions"),preservedOutside=owned(90,"edit");
f=fixture(Array.from({length:620},(_,i)=>owned(i/10,"edit")).concat([preservedManual,preservedOther,preservedOutside]));
stats=apply(f.seq,denseMarkers,[{start:0,end:70}],"edit");
assert.equal(stats.reviewMarkerCount,2);assert.equal(stats.reviewMarkerFailureCount,0);
assert(f.values.includes(preservedManual)&&f.values.includes(preservedOther)&&f.values.includes(preservedOutside),"Replacing dense owned markers preserves manual, other-workflow, and out-of-scope markers.");
assert.equal(f.values.length,5,"Six hundred twenty obsolete owned warnings are reconciled to two meaningful review intervals.");
console.log("REVIEW_MARKERS_OK:final-timeline-mapping,split-cues,retained-voice-ranges,all-review-types,ownership,scope,rerun,manual-collisions,write-position-color-failures");
