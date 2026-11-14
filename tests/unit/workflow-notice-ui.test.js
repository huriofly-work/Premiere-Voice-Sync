"use strict";
const assert=require("assert"),fs=require("fs"),vm=require("vm"),path=require("path");
const source=fs.readFileSync(path.join(__dirname,"../../extension/js/main.js"),"utf8");
const html=fs.readFileSync(path.join(__dirname,"../../extension/index.html"),"utf8");
const css=fs.readFileSync(path.join(__dirname,"../../extension/css/styles.css"),"utf8");
function fixture(options={}){
  const calls=[],controls={workflowNotice:{hidden:true},subtitleMaxCharacters:{value:"42"},captionLanguage:{value:"vi"},captionVoiceTrack:{value:"1"}};
  if(options.wire)for(const match of html.matchAll(/id="([^"]+)"/g))if(!controls[match[1]])controls[match[1]]={};
  function element(id){
    if(options.wire&&!controls[id])throw Error("MISSING_HTML_CONTROL:"+id);
    if(!controls[id])controls[id]={};
    if(!controls[id].addEventListener)controls[id].addEventListener=function(event,handler){this.handlers=this.handlers||{};this.handlers[event]=handler;};
    return controls[id];
  }
  const forbidden=()=>{throw Error("NATIVE_WINDOW_OR_FOCUS_FORBIDDEN");};
  const result={ok:true,workflow:"caption-only",schemaVersion:1,recognitionBackend:"cpu",recognitionBackendLabel:"CPU",language:"vi",captionCueCount:2,usedReferenceSrt:!!options.reference};
  if(options.preserveTimeline)Object.assign(result,{preserveTimeline:true,captionCueCount:0,recognitionReviewTasks:[{chapter:0,start:0,end:10}]});
  if(options.supplement){result.referenceSupplementRanges=[{sourceIndex:0,start:4,end:7,referenceCueIndices:[3],captionCueCount:1},{sourceIndex:0,start:8,end:10,referenceCueIndices:[],captionCueCount:1}];}
  if(options.emptySupplement)result.referenceSupplementEmptyRanges=[{sourceIndex:0,start:4,end:7}];
  if(options.numberDifference){result.referenceNumberReviewCues=[{cueIndex:1,expected:"9 phẩy 46 nghìn tỷ",recognized:"9 46 000 tỷ"}];result.referenceReviewCues=[{cueIndex:1,start:1,end:2,reason:"Giữ chữ SRT khớp phần lớn; nhận diện thiếu/khác một vài từ, cần kiểm tra chữ và timing"}];}
  const fakeFs={existsSync:()=>!!options.diagnostic,mkdirSync(){},writeFileSync(p,text,opt){if(options.writeFailure)throw Error("WRITE_FAILED");calls.push(["write",p,text,opt]);},readFileSync:()=>JSON.stringify(result)};
  const context={require:n=>({fs:fakeFs,path:path.win32,child_process:{}}[n]),window:{PvsSecurity:{assertNoLinks(){},redactLog(text,values){calls.push(["redact",text,values]);return "REDACTED";}},cep:{fs:{showOpenDialog(){calls.push("picker");if(options.pickerFailure)throw Error("PICKER_FAILED");return options.pickerCancel?{err:0,data:[]}:{err:0,data:["C:\\support"]};}}},confirm:forbidden,alert:forbidden,focus:forbidden,blur:forbidden,open:forbidden},setTimeout:function(fn){calls.push("export-yield");fn();},document:{getElementById:element,addEventListener(){}},localStorage:{getItem:()=>null,setItem(){}},process:{env:{}},fixture:{calls,options},console};
  const inject=`
    applicationDataRoot=function(){return "C:\\\\local";};extensionRoot=function(){return "C:\\\\panel";};
    state.captionPlan={key:"fixture",input:{sourceMode:"tracks",scopeMode:"whole",trackIndices:[1]},ranges:[{start:0,end:10}]};
    scanCaptionRange=async function(){if(fixture.options.rangeFailure)throw Error("RANGE_FAILED");if(fixture.options.planChanged)state.captionPlan.key="changed";if(fixture.options.sourceEmpty){state.captionPlan=null;state.captionPlanError=inputError("Nguồn audio trống.","captionVoiceTrack");}return {projectId:"project",sequenceId:"seq",snapshot:"snapshot",frameRate:30,plan:state.captionPlan,applicationFolder:"C:\\\\Premiere"};};
    findWavePreset=function(){return "preset.epr";};inspectSrt=function(){fixture.calls.push("reference");return {cueCount:2};};
    scanSequence=async function(){if(fixture.options.diagnosticFailure)throw Error("SEQUENCE_FAILED");return {voices:[{path:"voice.mp3",start:0,end:10}],v1LooksNested:true,frameRate:30};};
    diagnosticStatus=function(){};readSettings=function(){return settingDefaults;};
    createWorkflowMetrics=function(workflow){fixture.calls.push(["metrics-start",workflow]);return {begin:s=>fixture.calls.push(["metrics-begin",s]),end:(r,o)=>fixture.calls.push(["metrics-end",o||"success"]),reviewPlan:r=>fixture.calls.push(["review-plan",r.reviewMarkers.length]),finish:o=>fixture.calls.push(["metrics-finish",o])};};
    runPowerShell=async function(){fixture.calls.push("engine");if(fixture.options.engineFailure)throw Error("ENGINE_FAILED");};
    evalHost=async function(expression){fixture.calls.push(expression);if(expression.includes("s.captionTracks"))return {ok:true,count:fixture.options.noCaptionApi?null:0,bins:0,inPoint:0,outPoint:10};if(expression.includes("beginCaptionAudioExport"))return {ok:true,done:false,nextCall:0,rangeCount:1};if(expression.includes("advanceCaptionAudioExport"))return fixture.options.exportFailure?{ok:false,done:true,restored:true,error:"Error: -1",exportFailurePhase:"native-export"}:{ok:true,done:true,restored:true};return {ok:!fixture.options.applyFailure,error:"APPLY_FAILED",captionCreated:true,captionCueCount:2};};
    removeTreeSafe=function(target,root){if(fixture.options.cleanupFailure)throw Error("CLEANUP_FAILED");fixture.calls.push("cleanup");fixture.calls.push(["remove",target,root]);};status=log=logCaptionTiming=renderBackend=function(){};
    if(fixture.options.reference)state.captionSrt="reference.srt";
    if(fixture.options.diagnostic)state.targetSrt="reference.srt";
    if(fixture.options.wire){cleanupStaleJobs=function(){return 0;};detectBackend=async function(){return {};};detectSrt=async function(){};}
    window.testApi={show:showWorkflowNotice,confirm:confirmWorkflowNotice,choose:chooseWorkflowNotice,close:closeWorkflowNotice,busy:setWorkflowBusy,captions:runCaptions,diagnose:runDiagnostics,clear:clearWhisperCache,export:exportSafeLog,getBusy:function(){return state.workflowBusy;}};
    if(fixture.options.wire)wire();
  `;
  vm.runInNewContext(source.replace('  document.addEventListener("DOMContentLoaded", wire);',inject),context);
  return {api:context.window.testApi,controls,calls};
}
(async()=>{
  const f=fixture(),payload="<img src=x onerror=alert(1)>\n"+"long notice ".repeat(1000);
  for(const id of ["workflowNoticeTitle","workflowNoticeMessage"])Object.defineProperty(f.controls[id]||(f.controls[id]={}),"innerHTML",{set(){throw Error("UNSAFE_HTML");}});
  f.api.show("<b>title</b>",payload,"ok");
  assert.strictEqual(f.controls.workflowNotice.hidden,false);
  assert.strictEqual(f.controls.workflowNoticeMessage.textContent,payload);
  assert.strictEqual(f.controls.workflowNoticeTitle.textContent,"<b>title</b>");
  f.api.show("Second","Replacement","invalid-css-token");
  assert.strictEqual(f.controls.workflowNoticeMessage.textContent,"Replacement");
  assert.strictEqual(f.controls.workflowNoticeCard.className,"workflow-notice-card ok");
  f.api.close();assert.strictEqual(f.controls.workflowNotice.hidden,true);assert.strictEqual(f.api.getBusy(),false);
  f.api.show("Notice","Result","warn");f.api.busy(true);
  assert.strictEqual(f.controls.workflowNotice.hidden,true);assert.strictEqual(f.controls.runSync.disabled,true);
  f.api.show("Done","Result","ok");f.api.busy(false);
  assert.strictEqual(f.controls.workflowNotice.hidden,false);assert.strictEqual(f.controls.runSync.disabled,false);
  assert.strictEqual(f.calls.length,0,"Notice show/close/busy cannot call host or engine.");
  const w=fixture({wire:true});
  assert.strictEqual(typeof w.controls.runSync.handlers.click,"function");
  assert.strictEqual(typeof w.controls.runCaptions.handlers.click,"function");
  assert.strictEqual(typeof w.controls.captionSourceMode.handlers.change,"function");
  assert.strictEqual(typeof w.controls.captionScopeMode.handlers.change,"function");
  const wiredChoice=w.api.confirm("Choice","Message");w.controls.acceptWorkflowNotice.handlers.click();assert.strictEqual(await wiredChoice,true);
  const wiredCancel=w.api.confirm("Choice","Message");w.controls.closeWorkflowNotice.handlers.click();assert.strictEqual(await wiredCancel,false);
  w.controls.resetSettings.handlers.click();assert(w.controls.workflowNotice.hidden);assert.strictEqual(w.controls.settingsFeedback.textContent,"Đã khôi phục thiết lập mặc định.");
  let settled=false;
  const approval=f.api.confirm("Confirm","Wait for user","Do it","Cancel").then(value=>{settled=true;return value;});
  await Promise.resolve();assert(!settled,"A DOM confirmation must wait, never auto-approve.");
  assert.strictEqual(f.controls.acceptWorkflowNotice.hidden,false);
  assert.strictEqual(f.controls.closeWorkflowNotice.textContent,"Cancel");
  f.api.show("Replacement","Queued until choice","ok");
  assert.strictEqual(f.controls.workflowNoticeTitle.textContent,"Confirm","A later notice must not replace pending approval.");
  await assert.rejects(f.api.confirm("Second","No"),/chờ trả lời/);
  f.api.choose(true);f.api.choose(false);assert.strictEqual(await approval,true,"Duplicate clicks must settle once.");
  const canceled=f.api.confirm("Confirm","Cancel by close");f.api.close();assert.strictEqual(await canceled,false);
  f.api.show("Done","Result","ok");assert.strictEqual(f.controls.acceptWorkflowNotice.hidden,true);
  assert.strictEqual(f.controls.closeWorkflowNotice.textContent,"Đóng thông báo");
  for(const options of [{cancel:true},{},{cleanupFailure:true}]){
    const c=fixture(options),running=c.api.clear();
    assert(c.api.getBusy());assert.strictEqual(c.controls.runSync.disabled,true);assert(!c.calls.includes("cleanup"));
    await c.api.clear();await c.api.captions();c.api.export();assert.strictEqual(c.calls.length,0,"Other actions cannot start while cache confirmation is pending.");
    c.api.choose(!options.cancel);await running;assert(!c.api.getBusy());
    if(options.cancel){assert.strictEqual(c.calls.length,0);assert(c.controls.workflowNotice.hidden);}
    else if(options.cleanupFailure){assert(c.controls.workflowNotice.hidden);assert(c.controls.supportFeedback.className.includes("error"));}
    else{assert(c.calls.includes("cleanup"));assert.deepStrictEqual(Array.from(c.calls.find(x=>Array.isArray(x)&&x[0]==="remove")),["remove","C:\\local\\Cache\\Whisper","C:\\local"]);assert(c.controls.workflowNotice.hidden);assert.strictEqual(c.controls.supportFeedback.textContent,"Đã xóa cache nhận diện.");}
  }
  for(const options of [{},{writeFailure:true},{pickerFailure:true},{pickerCancel:true}]){
    const e=fixture(options);e.api.export();
    if(options.pickerCancel){assert.strictEqual(e.controls.workflowNotice.hidden,true);assert.strictEqual(e.calls.length,1);}
    else{assert(e.controls.workflowNotice.hidden);assert.strictEqual(e.controls.supportFeedback.className,"hint"+(options.writeFailure||options.pickerFailure?" error":""));}
    if(!options.writeFailure&&!options.pickerFailure&&!options.pickerCancel){const write=e.calls.find(x=>Array.isArray(x)&&x[0]==="write");assert.strictEqual(write[2],"REDACTED");assert.strictEqual(write[3].flag,"wx");assert(write[1].startsWith("C:\\support\\PremiereVoiceSync-Support-"));}
  }
  for(const options of [{},{reference:true},{reference:true,numberDifference:true},{reference:true,supplement:true},{reference:true,emptySupplement:true},{noCaptionApi:true,reference:true},{rangeFailure:true},{exportFailure:true},{engineFailure:true},{applyFailure:true}]){
    const s=fixture(options);await s.api.captions();
    assert.strictEqual(s.controls.workflowNotice.hidden,false);
    assert.strictEqual(s.api.getBusy(),false);
    const failed=options.rangeFailure||options.exportFailure||options.engineFailure||options.applyFailure;
    assert.strictEqual(s.controls.workflowNoticeCard.className,"workflow-notice-card "+(failed?"error":options.supplement||options.emptySupplement?"warn":"ok"));
    if(!options.rangeFailure)assert(s.calls.includes("cleanup"),"DOM notice must not delay finally cleanup.");
    if(options.exportFailure){assert(!s.calls.includes("engine"));assert(!s.calls.some(x=>typeof x==="string"&&x.includes("applyCaptionOnly")));assert(s.controls.workflowNoticeTechnical.textContent.includes("native-export"));assert(s.calls.includes("cleanup"));}
    if(options.reference)assert(s.calls.includes("reference"));
    if(options.numberDifference){assert(s.calls.some(x=>Array.isArray(x)&&x[0]==="review-plan"&&x[1]===0));assert(!s.controls.workflowNoticeMessage.textContent.includes("cue SRT cần nghe lại"));const saved=JSON.parse(s.calls.find(x=>Array.isArray(x)&&x[0]==="write"&&x[1].endsWith("caption-result.json"))[2]);assert.equal(saved.referenceNumberReviewCues.length,1,"Keep number diagnostics in the saved report.");}
    if(options.supplement){assert(s.controls.workflowNoticeTechnical.textContent.includes("bổ sung 2 vùng"));assert(s.controls.workflowNoticeTechnical.textContent.includes("lời nói ngoài SRT"));assert(!s.controls.workflowNoticeMessage.textContent.includes("Đã bỏ qua"));}
    if(options.emptySupplement)assert(s.controls.workflowNoticeTechnical.textContent.includes("không nhận diện được lời nói"));
    if(options.applyFailure){assert(s.controls.workflowNoticeTechnical.textContent.includes("Caption Track có thể đã được thêm"));assert(s.controls.runCaptions.disabled,"Unknown import result requires recovery verification.");}
    if(!options.rangeFailure){
      assert.strictEqual(s.calls.find(x=>Array.isArray(x)&&x[0]==="metrics-start")[1],"caption-only");
      assert.strictEqual(s.calls.find(x=>Array.isArray(x)&&x[0]==="metrics-finish")[1],failed?"failed":"success");
      if(!failed)assert.deepStrictEqual(s.calls.filter(x=>Array.isArray(x)&&x[0]==="metrics-begin").map(x=>x[1]),["preflight","audio-export","caption-alignment","caption-import","cleanup"]);
      const job=JSON.parse(s.calls.find(x=>Array.isArray(x)&&x[0]==="write")[2]);assert.deepStrictEqual(job.audioInput.trackIndices,[1],"job must carry selected track set to host");assert.strictEqual(job.audioInputKey,"fixture");
    }
  }
  const preservedCaption=fixture({preserveTimeline:true});await preservedCaption.api.captions();
  assert(!preservedCaption.calls.some(x=>typeof x==="string"&&x.includes("applyCaptionOnly")),"No usable recognition must not import a fake or empty caption track.");
  assert.strictEqual(preservedCaption.controls.workflowNoticeCard.className,"workflow-notice-card warn");
  assert(preservedCaption.controls.workflowNoticeTitle.textContent.includes("cần tạo phụ đề thủ công"));
  assert(preservedCaption.controls.workflowNoticeReview.textContent.includes("00:00:10.000"));
  assert(preservedCaption.calls.some(x=>Array.isArray(x)&&x[0]==="metrics-finish"&&x[1]==="success"));
  for(const options of [{sourceEmpty:true},{planChanged:true}]){
    const s=fixture(options);await s.api.captions();assert(!s.calls.includes("engine"));assert(!s.calls.some(x=>Array.isArray(x)&&x[0]==="write"));assert(!s.calls.some(x=>typeof x==="string"&&x.includes("beginCaptionAudioExport")));
  }
  for(const diagnosticFailure of [false,true]){
    const d=fixture({diagnostic:true,diagnosticFailure});await d.api.diagnose();
    if(diagnosticFailure)assert.strictEqual(d.controls.workflowNoticeCard.className,"workflow-notice-card error");else{assert(d.controls.workflowNotice.hidden);assert(d.controls.supportFeedback.textContent.includes("Đã kiểm tra đầu vào"));}
    assert(!d.api.getBusy());assert(!d.calls.some(x=>Array.isArray(x)&&["write","remove"].includes(x[0])));
  }
  for(const id of ["workflowNotice","workflowNoticeCard","workflowNoticeTitle","workflowNoticeMessage","closeWorkflowNotice","acceptWorkflowNotice"])assert.strictEqual((html.match(new RegExp('id="'+id+'"','g'))||[]).length,1);
  assert(source.includes('byId("closeWorkflowNotice").addEventListener("click", closeWorkflowNotice)'));
  assert(/\.workflow-notice-card p\s*\{[^}]*overflow-y:\s*auto/.test(css));
  assert(!/\b(?:window\.)?(?:alert|confirm|prompt)\s*\(/.test(source),"No native notifications anywhere in the panel.");
  assert(!/performanceCheckpoint|performanceContinue|performanceStop/.test(html),"Checkpoints share the one notice box.");
  assert(!/performanceTrialSection|runPerformanceTrial|runFastPerformanceTrial|pausePerformanceTrial/.test(html),"Completed experiment controls must be removed, not merely hidden.");
  const wire=source.slice(source.indexOf("function wire()"));
  assert(!/runPerformanceTrial|runFastPerformanceTrial|pausePerformanceTrial/.test(wire),"No handlers for removed experimental controls.");
  assert(/\.workflow-notice-actions\s*\{[^}]*flex-wrap:\s*wrap/.test(css));
  assert(/id="acceptWorkflowNotice" class="button primary"/.test(html),"Confirmation needs an explicit primary background, not browser defaults.");
  function luminance(hex){const rgb=hex.match(/[0-9a-f]{2}/gi).map(x=>parseInt(x,16)/255).map(x=>x<=0.04045?x/12.92:((x+0.055)/1.055)**2.4);return rgb[0]*0.2126+rgb[1]*0.7152+rgb[2]*0.0722;}
  for(const suffix of ["",":hover",":active"]){
    for(const prefix of [".button.primary",".workflow-notice-actions .button.primary"]){
      const selector=prefix+suffix;
      const declaration=css.slice(css.indexOf(selector+" {"),css.indexOf("}",css.indexOf(selector+" {")));
      const bg=/background:\s*(#[0-9a-f]{6})/i.exec(declaration),fg=/color:\s*(#[0-9a-f]{6})/i.exec(declaration);
      assert(bg&&fg,"Explicit colors required for "+selector);
      const a=luminance(bg[1]),b=luminance(fg[1]),ratio=(Math.max(a,b)+0.05)/(Math.min(a,b)+0.05);
      assert(ratio>=4.5,"Insufficient text contrast: "+selector+" "+ratio);
      console.log("PRIMARY_BUTTON_CONTRAST:"+selector+"="+ratio.toFixed(2)+":1");
    }
  }
  console.log("WORKFLOW_NOTICE_UI_OK:prioritized-notices;explicit-confirm-cancel;busy-guards;cache-scope;redacted-log-export;checkpoint-shared;literal-text;caption-outcomes;cleanup-not-blocked");
})().catch(e=>{console.error(e);process.exitCode=1;});
