"use strict";
const assert=require("assert"),fs=require("fs"),path=require("path"),vm=require("vm"),crypto=require("crypto");
const policy=require("../../extension/js/notification-policy");
const source=fs.readFileSync(path.resolve(__dirname,"../../extension/js/main.js"),"utf8");
function fixture(options={}) {
  const elements={},helper=[],native=[],settings=new Map(),focuses=[],opened=[];let focused=!options.background,bridgeOptions;
  settings.set("pvs.focusOnIncident", options.focusOff ? "false" : "true");
  if(options.soundOff)settings.set("pvs.notificationSound","false");
  if(options.externalOff)settings.set("pvs.externalNotifications","false");
  function makeElement(id) {
    const node={attrs:{},children:[],handlers:{},className:"hint",hidden:false,setAttribute(name,value){this.attrs[name]=value;},focus(){focuses.push(id);},appendChild(child){this.children.push(child);},addEventListener(type,handler){this.handlers[type]=handler;}};let text="original hint";
    Object.defineProperty(node,"textContent",{get(){return text;},set(value){text=String(value);this.children=[];}});return node;
  }
  const element=id=>elements[id]||(elements[id]=makeElement(id));
  const bridge={publish:(item,toast)=>native.push({type:"publish",item,toast}),clear:item=>native.push({type:"clear",item}),observe:(item,visible)=>native.push({type:"observe",item,visible}),hideToast:()=>native.push({type:"hide-toast"}),stop(){}};
  const context={require:name=>({fs:{},path:path.win32,crypto,child_process:{spawn(){},execFile(file,args,opts,callback){helper.push({file,args,opts,callback});}}}[name]),
    window:{PvsSecurity:{assertNoLinks(){}},PvsNotificationPolicy:policy,PvsNativeNotifications:{create(options){bridgeOptions=options;return bridge;}},__adobe_cep__:{requestOpenExtension(){opened.push("panel");} }},
    process:{pid:123,env:{SystemRoot:"C:\\Windows"}},document:{getElementById:element,createElement:()=>makeElement("dynamic"),addEventListener(){},hasFocus:()=>focused,visibilityState:"visible"},
    localStorage:{getItem:key=>settings.get(key)||null,setItem:(key,value)=>settings.set(key,value)},console};
  vm.runInNewContext(source.replace('  document.addEventListener("DOMContentLoaded", wire);',`
    extensionRoot=function(){return 'C:\\\\panel';};status=log=function(){};
    state.captionPlan={key:'fixture',input:{sourceMode:'tracks',trackIndices:[1]},ranges:[{start:0,end:10}]};scanSequence=async function(){return {sequenceId:'fixture',voices:[]};};scanCaptionRange=async function(){return {sequenceId:'fixture',snapshot:'baseline',plan:state.captionPlan};};captionTrackCount=async function(){return JSON.stringify({count:0,bins:0,inPoint:0,outPoint:10});};
    window.test={show:showWorkflowNotice,close:closeWorkflowNotice,begin:beginRun,fail:reportRunFailure,unexpected:reportUnexpectedError,current:function(){return currentNotice;},context:function(){return runContext;},warning:runWarning,finish:finishRunNotice,readSettings:readSettings,display:displayNotice,setSound:setNotificationSoundPreference,setExternal:setExternalNotificationPreference,edit:runSync,captions:runCaptions,observe:observeCurrentNotice};
  `),context);
  return {api:context.window.test,elements,helper,native,focuses,opened,element,focus:value=>{focused=value;},bridgeOptions:()=>bridgeOptions};
}
const foreground=fixture();foreground.api.show("Failure","Explanation","error");assert.equal(foreground.native.length,0);assert(foreground.api.current().seen);assert.equal(foreground.helper.length,0);
const background=fixture({background:true});const item=background.api.show("Failure","Explanation","error");assert.equal(background.helper.length,0);assert.equal(background.native[0].toast,true);
background.api.show("Failure","Explanation","error");assert.equal(background.native.length,1);assert.equal(background.api.current().count,2);
background.bridgeOptions().onOpen({...item});assert.equal(background.opened.length,0);background.bridgeOptions().onOpen(item);assert.equal(background.opened.length,1);assert.equal(background.api.current(),item);
background.focus(true);background.api.observe();assert(item.seen);assert(background.native.some(x=>x.type==="hide-toast"));assert.equal(background.api.current(),item,"Read does not close the result");
background.bridgeOptions().onOpen(item);assert.equal(background.opened.length,1,"Read toast cannot reopen");
const off=fixture({background:true,externalOff:true});off.api.show("Failure","Explanation","error");assert.equal(off.native.length,0);assert.equal(off.helper.length,0);
const routine=fixture({background:true});routine.api.show("Warning","Recovered","warn");assert.equal(routine.native.length,0);
for(const workflow of ["edit","captions"])for(const review of [false,true]){
 const done=fixture({background:true});done.api.begin(workflow);if(review)done.api.warning("Check result",true);done.api.finish("Done","Result");
 assert.equal(done.native.filter(x=>x.type==="publish").length,1);assert.equal(done.native[0].toast,true);assert.equal(done.helper.length,0);assert.equal(done.api.current().workflow,workflow);assert.equal(done.elements.workflowProgress.hidden,true);
 done.api.display(done.api.current(),true);assert.equal(done.native.filter(x=>x.type==="publish").length,1);
 done.focus(true);done.api.observe();assert(done.api.current().seen);assert.equal(done.api.current().tone,review?"warn":"ok");
}
const nativeRead=fixture({background:true});nativeRead.api.show("Done","Result","ok");nativeRead.bridgeOptions().onObserved(nativeRead.api.current());assert(nativeRead.api.current().seen,"Native observation handles timeline focus with panel visible");
const hidden=fixture({background:true});hidden.api.show("Done","Result","ok");hidden.elements.workflowNotice.hidden=true;hidden.bridgeOptions().onObserved(hidden.api.current());assert(!hidden.api.current().seen,"Old native observation cannot mark a now-hidden card read");
const stale=fixture({background:true});const old=stale.api.show("Done","Result","ok");stale.api.close();stale.bridgeOptions().onOpen(old);assert.equal(stale.opened.length,0);
const offscreen=fixture();offscreen.element("workflowNotice").getBoundingClientRect=()=>({width:300,height:100,top:-200,bottom:-100});offscreen.api.show("Done","Result","ok");assert(!offscreen.api.current().seen);assert.equal(offscreen.native[0].toast,true,"Offscreen result is not treated as read just because panel has keyboard focus");
const decision=fixture({background:true});decision.api.show("Decision","Mutates data","warn",{choice:true});assert.equal(decision.native[0].toast,true,"A real decision awaiting in background needs one reminder");assert.equal(decision.elements.workflowNotice.attrs["aria-modal"],"false");
const validation=fixture();validation.api.begin("edit");validation.api.fail(Error("SRT_INVALID"),"Invalid input");assert.strictEqual(validation.elements.srtHint.className,"hint input-error");assert.strictEqual(validation.elements.srtHint.textContent,"Chọn file SRT đúng nội dung và ngôn ngữ lời nói.");
assert.strictEqual(validation.elements.workflowNotice.hidden,true,"Field validation cannot also display a popup");assert.strictEqual(validation.helper.length,0);assert.strictEqual(validation.native.length,0);assert(validation.focuses.includes("srtCandidates"));
validation.api.display(validation.api.current(),true);assert.strictEqual(validation.elements.workflowNotice.hidden,false);assert.strictEqual(validation.elements.workflowNotice.attrs["aria-modal"],"false","History opens a nonblocking explanation");
const banner=fixture();banner.api.show("Failure","Explanation","error",{impact:"unchanged"});assert.strictEqual(banner.elements.workflowNotice.attrs.role,"region");assert(!banner.focuses.includes("closeWorkflowNotice"));
const partial=fixture();partial.api.begin("edit");partial.api.context().impact="changed";partial.api.fail(Error("SRT_IMPORT_FAILED"),"Partial failure");assert.strictEqual(partial.elements.workflowNotice.attrs.role,"alert");assert(!partial.focuses.includes("closeWorkflowNotice"),"An error must not trap keyboard focus like an approval");
const fatal=fixture();fatal.api.begin("edit");fatal.api.context().fatal=true;fatal.api.fail(Error("UI_FAILURE"),"Unexpected");assert.strictEqual(fatal.elements.workflowNotice.attrs.role,"alert");
const globalFailure=fixture();globalFailure.api.unexpected(Error("GLOBAL_UI_FAILURE"));assert.strictEqual(globalFailure.elements.workflowNotice.attrs.role,"alert","Unexpected UI failure must remain prominent outside a running workflow");
const numbers=fixture();numbers.api.begin("edit");for(const [id,value] of Object.entries({minSpeed:"",maxSpeed:130,minDialogueGap:1,voiceGroupGap:2,maxCaptionCharacters:42}))numbers.element(id).value=value;
let invalidNumber;try{numbers.api.readSettings();}catch(error){invalidNumber=error;}assert.strictEqual(invalidNumber.pvsInputField,"minSpeed");numbers.api.fail(invalidNumber,"Invalid parameter");assert.strictEqual(numbers.elements.workflowNotice.hidden,true);assert.strictEqual(numbers.elements.minSpeed.attrs["aria-invalid"],"true");assert.strictEqual(numbers.elements.editSettings.open,true);assert(numbers.elements.minSpeedError.textContent.includes("chưa có giá trị"));
for(const impact of ["unchanged","changed"]) {
  const history=fixture();history.api.show("Earlier warning","Old","warn");history.api.close();history.api.begin("edit");history.api.context().impact=impact;history.api.fail(Error(impact==="unchanged"?"SRT_INVALID":"PARTIAL_EDIT"),"Current failure");
  const earlier=history.elements.noticeHistoryList.children.find(button=>button.textContent.includes("Earlier warning"));assert(earlier);earlier.handlers.click();
  assert.strictEqual(history.elements.workflowNoticeTitle.textContent,impact==="unchanged"?"Earlier warning":"Current failure","Field errors must not trap the user in an invisible dialog; active critical review stays protected");
}
const pending=fixture({background:true});pending.api.show("Failure","Explanation","error");pending.api.setExternal(false);assert.equal(pending.native.at(-1).type,"hide-toast");assert(!pending.api.current().seen);
assert.equal(pending.bridgeOptions().soundEnabled(),false,"Master opt-out also disables audio");assert.equal(pending.elements.notificationSound.disabled,true);
const sound=fixture({background:true});sound.api.show("Done","Result","ok");assert.equal(sound.bridgeOptions().soundEnabled(),true);sound.api.setSound(false);assert.equal(sound.bridgeOptions().soundEnabled(),false);assert.equal(sound.native.filter(x=>x.type==="publish").length,1,"Changing sound must not resend an existing notification");
const soundOff=fixture({background:true,soundOff:true});soundOff.api.show("Done","Result","ok");assert.equal(soundOff.bridgeOptions().soundEnabled(),false);assert.equal(soundOff.native[0].toast,true,"Mute audio retains the single visible notification");
(async()=>{
  for(const mode of ["numeric","srt","captions"]) {
    const workflow=fixture();for(const [id,value] of Object.entries({minSpeed:mode==="numeric"?"":70,maxSpeed:130,minDialogueGap:1,voiceGroupGap:2,maxCaptionCharacters:42,subtitleMaxCharacters:"invalid"}))workflow.element(id).value=value;
    if(mode==="captions")await workflow.api.captions();else await workflow.api.edit();
    const expectedField=mode==="numeric"?"minSpeed":mode==="srt"?"srtCandidates":"subtitleMaxCharacters";
    assert.strictEqual(workflow.api.current().fieldId,expectedField,"Real workflow catch must preserve field annotation");assert.strictEqual(workflow.elements.workflowNotice.hidden,true);assert.strictEqual(workflow.element(expectedField).disabled,false);assert(workflow.focuses.includes(expectedField));assert.strictEqual(workflow.native.length,0);assert.strictEqual(workflow.helper.length,0);
  }
  console.log("NOTIFICATION_DELIVERY_OK:policy-drives-renderer;field-no-popup;real-workflow-validation;numeric-input;nonblocking-failure;critical-dialog;warning-completion;single-panel-target;foreground-defer;opt-out;stale-actions");
})().catch(error=>{console.error(error);process.exitCode=1;});
