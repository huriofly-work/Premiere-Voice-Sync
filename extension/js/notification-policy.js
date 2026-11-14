(function(root,factory){var api=factory();if(typeof module==="object"&&module.exports)module.exports=api;if(root)root.PvsNotificationPolicy=api;}(typeof window!=="undefined"?window:null,function(){
"use strict";
function route(event,environment){
  var kinds=["validation","progress","recovered","warning","failure","approval","completed","stalled","cancelled"];
  if(!event||kinds.indexOf(event.kind)<0)throw Error("UNKNOWN_NOTIFICATION_EVENT");
  var env=Object.assign({background:false,fieldAvailable:true,externalEnabled:true,toastCapability:"available",dnd:false},environment||{});
  if(["available","disabled","unavailable"].indexOf(env.toastCapability)<0)throw Error("INVALID_CAPABILITY");
  var result={surface:"status",persistent:false,pauseWorkflow:false,toast:"none",attention:"none",sound:false,action:"none",retry:false,reviewVisibility:"now"};
  if(event.handled||event.expired||event.duplicate)return Object.assign(result,{surface:"none"});
  if(event.kind==="validation")return Object.assign(result,{surface:env.fieldAvailable?"field":"banner",persistent:true});
  if(["progress","recovered","stalled"].indexOf(event.kind)>=0)return result;
  if(event.kind==="warning")return Object.assign(result,{surface:"banner",persistent:true});
  if(event.kind==="approval"||event.kind==="failure"){
    result.surface=event.kind==="approval"?"panel-choice":event.fatal||["changed","unknown"].indexOf(event.impact)>=0?"panel-alert":"banner";
    result.persistent=true;result.pauseWorkflow=true;
    result.retry=event.kind==="failure"&&event.impact==="unchanged"&&event.retryVerifiedSafe===true;
  }else result.surface="result-card";
  if(!event.observed&&env.background&&env.externalEnabled&&env.toastCapability==="available"){
    result.toast=env.dnd?"notification-center-only":"banner-and-center";result.action="open-current-incident";
    result.reviewVisibility="after-user-open-or-foreground";
    result.sound=env.soundEnabled===true&&!env.dnd;
  }
  return result;
}
function resolveOpenAction(request,current){
  if(!request||request.action!=="open-current-incident"||!current||current.handled||current.expired||request.sessionId!==current.sessionId||request.runId!==current.runId||request.incidentId!==current.incidentId)return "ignore";
  return "open-review";
}
return {route:route,resolveOpenAction:resolveOpenAction};
}));
