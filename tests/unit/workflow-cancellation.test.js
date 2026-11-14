"use strict";
const assert=require("assert"),fs=require("fs"),path=require("path").win32,vm=require("vm"),crypto=require("crypto");
const source=fs.readFileSync(require("path").join(__dirname,"../../extension/js/main.js"),"utf8");
const policy=require("../../extension/js/notification-policy.js");
const sourceHash=crypto.createHash("sha256").update("host").digest("hex");
function fixture(options={}){
  const calls=[],files={},controls={captionVoiceTrack:{value:"1"},subtitleMaxCharacters:{value:"42"},captionLanguage:{value:"vi"}};
  let api, advances=0, engineCallback=null, resumeCallback=null;
  const sequence={name:"fixture",sequenceId:"seq",voices:[{start:0,end:4,speedPercent:100,inPoint:0}]};
  const plan={ok:true,schemaVersion:8,sequenceId:"seq",summary:{punctuationSentenceCount:2,captionCueCount:2},speedMergeTrial:"adjacent-speed-v2",visualSegments:[]};
  function stopAt(key){if(options.onPoint)options.onPoint(key,api);if(options.stopAt===key){api.stop();api.stop();assert(api.busy(),"Stop cannot unlock an outstanding call");assert(controls.stopWorkflow.disabled);assert(controls.stopWorkflow.textContent.includes("Đang yêu cầu"));}}
  const fakeFs={existsSync:p=>p.endsWith(".srt"),mkdirSync(){},writeFileSync(p,text){files[p]=text;calls.push(["write",p]);},appendFileSync(){},readFileSync(p){
    if(files[p])return files[p];if(p.endsWith("host.jsx"))return "host";
    if(p.endsWith("alignment-result.json"))return JSON.stringify({recognitionBackend:"cpu",recognitionBackendLabel:"CPU"});
    if(p.endsWith("dtw-trial-report.json"))return JSON.stringify({ok:true,revision:"dtw-additive-v1",addedCutCount:0,canApply:false});
    if(p.endsWith("speed-merge-report.json"))return JSON.stringify({ok:true,revision:"adjacent-speed-v2",coverageVerified:true,voiceUnchanged:true,captionsUnchanged:true,durationChangedFrames:0,newPauses:0,summary:{mergeCount:0},canApply:false,planPath:path.join(api.context().outputFolder,"speed-merge-trial/sentence-edit-plan.json")});
    if(p.endsWith("sentence-edit-plan.json"))return JSON.stringify(plan);
    if(p.endsWith("caption-result.json"))return JSON.stringify({ok:true,workflow:"caption-only",schemaVersion:1,recognitionBackend:"cpu",recognitionBackendLabel:"CPU",language:"vi",captionCueCount:2});
    throw Error("UNEXPECTED_READ:"+p);
  }};
  const childProcess={execFile(file,args,opts,callback){
    assert(opts.windowsHide);assert(args.includes("-RequestPath"),"Workflow engine must use owned wrapper");
    const request=JSON.parse(files[args.at(-1)]);calls.push(["engine",request.script]);
    stopAt(request.script);
    const finish=()=>callback(options.engineError?Object.assign(Error("ENGINE_FAILED"),{code:1}):api.context().cancelRequested?Object.assign(Error("stopped"),{code:1223}):null,"","ENGINE_FAILED");
    if(options.holdEngine)engineCallback=finish;else Promise.resolve().then(finish);
    return {};
  }};
  const context={require:n=>({fs:fakeFs,path,child_process:childProcess,crypto}[n]),window:{PvsSecurity:{assertNoLinks(){}},PvsNotificationPolicy:policy},document:{getElementById:id=>controls[id]||(controls[id]={}),addEventListener(){},hasFocus:()=>true},localStorage:{getItem:()=>null,setItem(){},removeItem(){}},process:{env:{SystemRoot:"C:\\Windows"}},fixture:{calls,sequence,options,stopAt},setTimeout:(fn)=>{stopAt("export-yield");Promise.resolve().then(fn);}};
  context.window.setTimeout=(fn)=>Promise.resolve().then(fn);
  context.window.__adobe_cep__={evalScript(expression,callback){
    calls.push(["host",expression]);let result;
    if(expression.includes("workflowPauseState"))result=options.pauseReadFailure?{ok:false,error:"PAUSE_READ_FAILED"}:{ok:true,state:JSON.stringify([options.snapshotVersion||0])};
    else if(expression.includes("s.captionTracks"))result={ok:true,count:0,bins:0,inPoint:0,outPoint:10};
    else if(expression.includes("diagnosticInfo"))result={ok:true,revision:"staged-edit-v3",baseHash:sourceHash};
    else if(expression.includes("beginDiagnosticEdit")){stopAt("edit-begin");result={ok:true,nextCall:0,nextStage:"video"};}
    else if(expression.includes("advanceDiagnosticEdit")){advances++;stopAt("edit-advance-"+advances);result=advances===1?{ok:true,done:false,nextCall:1,nextStage:"voice",stage:"video",timelineMutated:true}:{ok:true,done:true,result:{ok:true,executorVersion:25,timelineMutated:true}};}
    else if(expression.includes("abortDiagnosticEdit"))result={ok:false,done:true,result:{timelineMutated:advances>0}};
    else if(expression.includes("beginCaptionAudioExport")){stopAt("export-begin");result={ok:true,done:false,nextCall:0,rangeCount:2};}
    else if(expression.includes("advanceCaptionAudioExport")){advances++;stopAt("export-advance-"+advances);result={ok:true,done:advances===2,nextCall:advances,restored:advances===2};}
    else if(expression.includes("abortCaptionAudioExport"))result=options.restoreError?{ok:false,done:true,restored:false,exportFailurePhase:"restore",error:"RESTORE_FAILED"}:{ok:false,done:true,restored:true};
    else if(expression.includes("applyCaptionOnly")){stopAt("caption-import");result={ok:true,captionCreated:true,captionCueCount:2};}
    else throw Error("UNEXPECTED_HOST:"+expression);
    if(expression.includes("workflowPauseState")&&options.holdResumeRead&&api.context().resuming)resumeCallback=()=>callback(JSON.stringify(result));
    else Promise.resolve().then(()=>callback(JSON.stringify(result)));
  }};
  const inject=`
    applicationDataRoot=()=>"C:\\\\fixture";extensionRoot=()=>"C:\\\\panel";ensureHostLoaded=async()=>{};
    scanSequence=async()=>{fixture.stopAt("scan");return fixture.sequence;};
    state.captionPlan={key:"fixture",input:{sourceMode:"tracks",scopeMode:"whole",trackIndices:[1]},ranges:[{start:0,end:4},{start:5,end:9}]};
    scanCaptionRange=async()=>{fixture.stopAt("scan");return {projectId:"project",sequenceId:"seq",snapshot:"base",frameRate:30,plan:state.captionPlan};};
    readSettings=()=>settingDefaults;findWavePreset=()=>"preset.epr";
    createWorkflowMetrics=()=>({begin:s=>fixture.calls.push(["stage",s]),end:(r,o)=>fixture.calls.push(["stage-end",o]),finish:o=>fixture.calls.push(["finish",o]),linkTimeline(){},reviewPlan:r=>fixture.calls.push(["review-plan",r.reviewMarkers.length])});
    removeTreeSafe=()=>{if(hostPending||enginePending)throw Error("CLEANUP_WHILE_PENDING");fixture.calls.push(["cleanup"]);};
    status=log=renderBackend=logCaptionTiming=()=>{};
    state.targetSrt="input.srt";
    window.api={edit:runSync,captions:runCaptions,stop:requestWorkflowStop,pause:requestWorkflowPause,fatal:reportUnexpectedError,choose:chooseWorkflowNotice,pending:()=>!!state.noticeChoice,busy:()=>state.workflowBusy,context:()=>runContext,recovery:()=>recoveryContext};
  `;
  vm.runInNewContext(source.replace('  document.addEventListener("DOMContentLoaded", wire);',inject),context);api=context.window.api;
  return {api,calls,controls,files,release:()=>engineCallback(),releaseResume:()=>resumeCallback()};
}
async function settle(f,running){
  for(let i=0;i<100;i++){if(f.api.pending()){f.api.choose(true);break;}if(!f.api.busy())break;await Promise.resolve();}
  await running;
  assert(!f.api.busy());assert(f.controls.stopWorkflow.hidden);
}
if(require.main===module)(async()=>{
  for(const mode of ["edit","captions"]){
    const points=mode==="edit"?["scan","build-dtw-trial-plan.ps1","run-alignment.ps1","build-sentence-plan.ps1","build-speed-merge-trial-plan.ps1","edit-begin","edit-advance-1","edit-advance-2"]:["scan","export-begin","export-yield","export-advance-1","export-advance-2","run-captions.ps1","caption-import"];
    for(const stopAt of points){
      const f=fixture({stopAt});await settle(f,f.api[mode]());
      assert.equal(f.controls.workflowNoticeTitle.textContent,"Đã dừng tác vụ",mode+":"+stopAt);
      assert(!f.calls.some(c=>c[0]==="finish"&&c[1]==="success"));
      const changed=stopAt.startsWith("edit-advance")||stopAt==="caption-import";
      assert.equal(!!f.api.recovery(),changed,mode+":"+stopAt+":recovery");
      if(changed)assert(f.controls.runSync.disabled&&f.controls.runCaptions.disabled);
      else assert(f.controls.workflowNoticeMessage.textContent.includes("Timeline chưa bị thay đổi"));
      const hosts=f.calls.filter(c=>c[0]==="host").map(c=>c[1]);
      if(["edit-begin","edit-advance-1"].includes(stopAt))assert.equal(hosts.filter(c=>c.includes("abortDiagnosticEdit")).length,1);
      if(["export-begin","export-yield","export-advance-1"].includes(stopAt))assert.equal(hosts.filter(c=>c.includes("abortCaptionAudioExport")).length,1);
      if(stopAt.startsWith("export"))assert(!f.calls.some(c=>c[0]==="engine"));
      assert(!hosts.some(c=>/\.save\(|\.undo\(/i.test(c)));
    }
  }
  const f=fixture({stopAt:"run-captions.ps1",holdEngine:true}),running=f.api.captions();
  for(let i=0;i<100&&!f.calls.some(c=>c[0]==="engine");i++)await Promise.resolve();
  assert(f.api.busy());assert(!f.calls.some(c=>c[0]==="cleanup"));
  assert(Object.keys(f.files).some(n=>n.endsWith(".cancel")));
  await f.api.edit();assert(f.api.busy(),"Duplicate start stays blocked");f.release();await settle(f,running);
  for(const options of [{stopAt:"export-advance-1",restoreError:true},{stopAt:"run-captions.ps1",engineError:true}]){
    const f=fixture(options);await settle(f,f.api.captions());assert(f.controls.workflowNoticeTitle.textContent.includes("Không hoàn tất"));assert(!f.controls.workflowNoticeTitle.textContent.includes("Đã dừng tác vụ"));
    if(options.restoreError)assert(f.api.recovery());
  }
  const quiet=policy.route({kind:"cancelled",impact:"changed"},{background:true});assert.equal(quiet.toast,"banner-and-center");assert.equal(quiet.attention,"none");assert.equal(policy.route({kind:"cancelled",observed:true},{background:true}).toast,"none");
  console.log("WORKFLOW_CANCELLATION_OK:both-workflows;preflight;engine;export-restoration;staged-abort;final-native-call;pending-lock;repeat-stop;recovery;error-precedence;quiet-cancel");
})().catch(e=>{console.error(e);process.exitCode=1;});
module.exports={fixture,settle};
