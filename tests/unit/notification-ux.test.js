"use strict";
// Real notification model/renderer with in-memory DOM and data only. No native host.
const assert=require("assert"),fs=require("fs"),path=require("path"),vm=require("vm");
const policy=require("../../extension/js/notification-policy");
const source=fs.readFileSync(path.join(__dirname,"../../extension/js/main.js"),"utf8");
function fixture(storedFocus=null,storedSound=null) {
  const controls={},native=[],storage=new Map();
  if(storedSound!==null)storage.set("pvs.notificationSound",storedSound);
  if(storedFocus!==null)storage.set("pvs.focusOnIncident",storedFocus);
  function element(id){return controls[id]||(controls[id]={textContent:"",hidden:true,className:"",attrs:{},setAttribute(k,v){this.attrs[k]=v;},focus(){this.focused=true;},addEventListener(){}});}
  const context={require:name=>({fs:{},path:path.win32,child_process:{execFile(){native.push("focus");}}}[name]),window:{PvsSecurity:{},PvsNotificationPolicy:policy},
    document:{getElementById:element,addEventListener(){},hasFocus:()=>true},console:{error(){}},process:{env:{}},
    localStorage:{getItem:key=>storage.get(key)||null,setItem:(key,value)=>storage.set(key,value),removeItem:key=>storage.delete(key)}};
  vm.runInNewContext(source.replace('  document.addEventListener("DOMContentLoaded", wire);',`
    window.api={begin:beginRun,log:log,warning:runWarning,markers:logReviewMarkers,finish:finishRunNotice,fail:reportRunFailure,close:closeWorkflowNotice,busy:setWorkflowBusy,
      history:function(){return noticeHistory;},current:function(){return currentNotice;},context:function(){return runContext;},external:function(){return externalPreference;},sound:function(){return soundPreference;},setSound:setNotificationSoundPreference,end:function(){runContext=null;setWorkflowBusy(false);}};
  `),context);
  return {api:context.window.api,controls,native,storage};
}
for(const stored of [null,"true","false"])assert.equal(fixture(stored).api.external(),true,"Retired focus preference cannot change external permission");
for(const [stored,expected] of [[null,true],["true",true],["false",false]])assert.equal(fixture(null,stored).api.sound(),expected,"Sound defaults on and preserves explicit opt-out");
const soundSettings=fixture();soundSettings.api.setSound(false);assert.equal(soundSettings.storage.get("pvs.notificationSound"),"false");assert.equal(soundSettings.api.sound(),false);
const routine=fixture();routine.api.begin("edit");
routine.api.log("DTW_DIAGNOSTIC warning with PRIVATE_TRANSCRIPT", "warn");
routine.api.warning("CPU recovered successfully");routine.api.warning("Cleanup file only");
routine.api.context().startedAt=Date.now()-600000;
routine.api.finish("Edit","Detailed technical metrics");
assert.equal(routine.api.current().tone,"ok");assert.equal(routine.api.history().length,0);
assert.equal(routine.native.length,0);assert.equal(routine.controls.workflowNotice.attrs["aria-modal"],"false");
assert(!routine.controls.workflowNoticeMessage.textContent.includes("DTW"));
assert(routine.controls.workflowNoticeTechnical.textContent.includes("CPU recovered"));
assert(routine.controls.closeWorkflowNotice.hidden,"A successful result requires no dismissal");
assert.equal(policy.route({kind:"completed",durationMilliseconds:600000},{background:true,foregroundEnabled:false}).toast,"banner-and-center");

const review=fixture();review.api.begin("captions");review.api.context().resultHeadline="Đã tạo 120 phụ đề.";
const markers=[{start:4,end:5,captionIndex:3,reason:"Chữ tự nhận diện: cần kiểm tra chữ"},
  {start:4,end:5,captionIndex:3,reason:"Cần nghe lại thời gian"},
  {start:4.5,end:6,reason:"Vùng âm thanh chưa xác minh"},{start:9,end:10,captionIndex:8,reason:"Kiểm tra chữ"}];
review.api.markers({reviewMarkerCount:0,reviewMarkerFailureCount:4},markers);
review.api.finish("Captions","Technical source cue 102, frame 1234");
assert.equal(review.api.current().tone,"warn");assert(review.api.current().reviewRequired);
assert.equal(review.api.current().reviewItems.length,3,"Same final bounds merge reasons, without widening the original marker positions");
assert(review.controls.workflowNoticeMessage.textContent.includes("2 vùng"),"Overlapping warning ranges are counted once");
assert(review.controls.workflowNoticeMessage.textContent.includes("chưa có marker"),"Missing markers must be explicit in the main message");
assert(review.controls.workflowNoticeReview.textContent.includes("Phụ đề 3 · 00:00:04.000–00:00:05.000"));
assert(review.controls.workflowNoticeReview.textContent.includes("Cần nghe lại thời gian"));
assert(review.controls.workflowNoticeActionsNeeded.textContent.includes("Chưa tạo đủ marker"));
assert(!review.controls.noticeReviewIssues.hidden);assert.equal(review.api.history().length,1);
assert.equal(policy.route({kind:"completed",reviewRequired:true},{background:true,foregroundEnabled:false}).toast,"banner-and-center");
assert(!Array.from(review.storage.values()).join(" ").includes("Chữ tự nhận diện"),"History cannot persist speech or raw diagnostics");

const blue=fixture();blue.api.begin("edit");blue.api.markers({mergeClipMarkerCount:5,reviewMarkerCount:0},[],{visualSegments:[{NewStart:0,NewEnd:3,SpeedOutsideWarningRange:false}]});blue.api.finish("Edit","Merged visuals");
assert.equal(blue.api.current().tone,"ok");assert.equal(blue.api.current().reviewItems.length,0,"Informational blue merge markers are not review problems");
const speed=fixture();speed.api.begin("edit");speed.api.markers({speedWarningSentenceCount:1},[],{visualSegments:[{NewStart:2,NewEnd:4,SpeedOutsideWarningRange:true}]});
speed.api.warning("Check speed",true,"SPEED");speed.api.finish("Edit","Details");assert.equal(speed.api.current().reviewItems.length,1);

const failed=fixture();failed.api.begin("captions");failed.api.context().impact="unknown";failed.api.fail(Error("RAW_PRIVATE_PATH C:\\private\\audio.wav"),"Chưa tạo được phụ đề");
assert.equal(failed.controls.workflowNotice.attrs.role,"alert");assert.equal(failed.controls.workflowNotice.attrs["aria-modal"],"false");
assert(!failed.controls.workflowNoticeMessage.textContent.includes("RAW_PRIVATE_PATH"));assert(!failed.controls.status.textContent.includes("RAW_PRIVATE_PATH"));
failed.api.close();failed.api.end();assert(failed.controls.runCaptions.disabled);assert(!failed.controls.recoveryNotice.hidden,"Closing an error does not approve a retry");

const input=fixture();input.api.begin("edit");input.api.fail(Error("SRT_INVALID C:\\private\\file.srt"),"Invalid input");
assert(input.controls.workflowNotice.hidden);assert.equal(input.api.history().length,0);assert(!input.controls.srtHint.textContent.includes("SRT_INVALID"));
console.log("NOTIFICATION_UX_OK:quiet-recovery;no-routine-history;explicit-focus-migration;foreground-success-local;background-success-notified;deduplicated-final-ranges;marker-failure-fallback;blue-markers-informational;raw-errors-hidden;recovery-lock-preserved");
