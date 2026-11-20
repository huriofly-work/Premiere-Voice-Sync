"use strict";
const assert=require("assert"),fs=require("fs"),path=require("path").win32,vm=require("vm"),crypto=require("crypto");
const source=fs.readFileSync(require("path").join(__dirname,"../../extension/js/main.js"),"utf8");
const policy=require("../../extension/js/notification-policy.js");
const sourceHash=crypto.createHash("sha256").update("host").digest("hex");
const recoverySuffix=".audio-recovery.json";
function fixture(options={}){
  const calls=[],files={},controls={runSync:{disabled:false},runCaptions:{disabled:false},captionVoiceTrack:{value:"1"},subtitleMaxCharacters:{value:"42"},captionLanguage:{value:"vi"}};
  let api, advances=0, engineCallback=null, resumeCallback=null, journal;
  const directories=new Set(),pendingJournals=options.pendingJournals||new Set();
  const sequence=require("./edit-input.test.js")();
  const plan={ok:true,schemaVersion:8,sequenceId:"seq",summary:{punctuationSentenceCount:2,captionCueCount:2},speedMergeTrial:"adjacent-speed-v2",visualSegments:[],reviewMarkers:[]};
  function stopAt(key){if(options.onPoint)options.onPoint(key,api);if(options.stopAt===key){api.stop();api.stop();assert(api.busy(),"Stop cannot unlock an outstanding call");assert(controls.stopWorkflow.disabled);assert(controls.stopWorkflow.textContent.includes("Đang yêu cầu"));}}
  const fakeFs={existsSync:p=>p.endsWith(".srt")||p==="voice.mp3"||directories.has(p)||pendingJournals.has(p),
    mkdirSync(p){for(let folder=p;folder!==path.dirname(folder);folder=path.dirname(folder))directories.add(folder);},
    readdirSync(p){return [...new Set([...directories,...pendingJournals].map(item=>path.dirname(item)===p?path.basename(item):null).filter(Boolean))];},
    lstatSync:p=>({isDirectory:()=>directories.has(p),isSymbolicLink:()=>false,mtime:new Date()}),
    writeFileSync(p,text){files[p]=text;calls.push(["write",p]);},appendFileSync(){},readFileSync(p){
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
  const context={require:n=>({fs:fakeFs,path,child_process:childProcess,crypto}[n]),window:{PvsEditInput:require("../../extension/js/edit-input.js"),PvsSecurity:{assertNoLinks(){}},PvsNotificationPolicy:policy},document:{getElementById:id=>controls[id]||(controls[id]={}),addEventListener(){},hasFocus:()=>true},localStorage:{getItem:()=>null,setItem(){},removeItem(){}},process:{env:{SystemRoot:"C:\\Windows"}},fixture:{calls,sequence,options,stopAt},setTimeout:(fn)=>{stopAt("export-yield");Promise.resolve().then(fn);}};
  const storage=options.storage||new Map();
  context.localStorage={getItem:key=>storage.get(key)||null,setItem:(key,v)=>storage.set(key,v),removeItem:key=>storage.delete(key)};
  context.window.setTimeout=(fn)=>Promise.resolve().then(fn);
  context.window.__adobe_cep__={evalScript(expression,callback){
    calls.push(["host",expression]);let result;
    if(expression.includes("workflowPauseState"))result=options.pauseReadFailure?{ok:false,error:"PAUSE_READ_FAILED"}:{ok:true,state:JSON.stringify([options.snapshotVersion||0])};
    else if(expression.includes("s.captionTracks"))result={ok:true,count:0,bins:0,inPoint:0,outPoint:10};
    else if(expression.includes("diagnosticInfo"))result={ok:true,revision:"staged-edit-v3",baseHash:sourceHash};
    else if(expression.includes("beginDiagnosticEdit")){advances=0;stopAt("edit-begin");result={ok:true,nextCall:0,nextStage:"video"};}
    else if(expression.includes("advanceDiagnosticEdit")){
      advances++;stopAt("edit-advance-"+advances);
      if(options.advanceError)result={ok:false,error:"Original advance error"};
      else if(advances===1)result={ok:true,done:false,nextCall:1,nextStage:"voice",stage:"video",timelineMutated:true};
      else result={ok:true,done:true,result:options.editResult||{ok:true,executorVersion:25,timelineMutated:true}};
    }
    else if(expression.includes("acceptDiagnosticEdit")){stopAt("edit-accept");result={ok:true};}
    else if(expression.includes("abortDiagnosticEdit") && options.closeError)throw Error("Secondary close error");
    else if(expression.includes("abortDiagnosticEdit") && options.lostSession)result={ok:false,error:"DIAGNOSTIC_SESSION_NOT_FOUND"};
    else if(expression.includes("abortDiagnosticEdit"))result={ok:false,done:true,result:{timelineMutated:advances>0}};
    else if(expression.includes("beginCaptionAudioExport")){
      advances=0;
      journal=JSON.parse(expression.slice(expression.indexOf("(")+1).split(",")[0])+recoverySuffix;
      pendingJournals.add(journal);stopAt("export-begin");result={ok:true,done:false,nextCall:0,rangeCount:2};
    }
    else if(expression.includes("advanceCaptionAudioExport")){
      advances++;stopAt("export-advance-"+advances);
      if(options.exportError) result={ok:false,done:true,restored:false,exportFailurePhase:"restore",error:"EXPORT_FAILED"};
      else {
        if(advances===2)pendingJournals.delete(journal);
        result={ok:true,done:advances===2,nextCall:advances,restored:advances===2};
      }
    }
    else if(expression.includes("abortCaptionAudioExport")){
      if(!options.restoreError)pendingJournals.delete(journal);
      result=options.restoreError?{ok:false,done:true,restored:false,exportFailurePhase:"restore",error:"RESTORE_FAILED"}:{ok:false,done:true,restored:true};
    }
    else if(expression.includes("restorePendingCaptionAudioExport")){
      const target=JSON.parse(expression.slice(expression.indexOf("(")+1,-1));
      if(!options.retryError)pendingJournals.delete(target);
      result=options.retryError?{ok:false,restored:false,error:"RETRY_FAILED"}:{ok:true,restored:true};
    }
    else if(expression.includes("applyCaptionOnly")){stopAt("caption-import");result={ok:true,captionCreated:true,captionCueCount:2};}
    else throw Error("UNEXPECTED_HOST:"+expression);
    if(expression.includes("workflowPauseState")&&options.holdResumeRead&&api.context().resuming)resumeCallback=()=>callback(JSON.stringify(result));
    else Promise.resolve().then(()=>callback(JSON.stringify(result)));
  }};
  const inject=`
    applicationDataRoot=()=>"C:\\\\fixture";extensionRoot=()=>"C:\\\\panel";ensureHostLoaded=async()=>{};
    readSequenceScan=async()=>{fixture.calls.push(["scan-edit",fixture.sequence.sequenceId]);fixture.stopAt("scan");return fixture.sequence;};
    state.captionPlan={key:"fixture",input:{sourceMode:"tracks",scopeMode:"whole",trackIndices:[1]},ranges:[{start:0,end:4},{start:5,end:9}]};
    scanCaptionRange=async()=>{fixture.calls.push(["scan-captions",fixture.sequence.sequenceId]);fixture.stopAt("scan");return {projectId:"project",sequenceId:fixture.sequence.sequenceId,snapshot:"base",frameRate:30,plan:state.captionPlan};};
    readSettings=()=>settingDefaults;findWavePreset=()=>"preset.epr";
    createWorkflowMetrics=()=>({begin:s=>fixture.calls.push(["stage",s]),end:(r,o)=>fixture.calls.push(["stage-end",o]),finish:o=>fixture.calls.push(["finish",o]),linkTimeline(){},reviewPlan:r=>fixture.calls.push(["review-plan",r.reviewMarkers.length])});
    removeTreeSafe=()=>{if(hostPending||enginePending)throw Error("CLEANUP_WHILE_PENDING");fixture.calls.push(["cleanup"]);};
    retainLastRun=removeTreeSafe;
    status=renderBackend=logCaptionTiming=()=>{};
    log=message=>fixture.calls.push(["log",message]);
    state.targetSrt="input.srt";
    window.api={reload:()=>recoverPendingRuns(true),edit:runSync,captions:runCaptions,stop:requestWorkflowStop,pause:requestWorkflowPause,fatal:reportUnexpectedError,choose:chooseWorkflowNotice,pending:()=>!!state.noticeChoice,busy:()=>state.workflowBusy,context:()=>runContext,history:()=>noticeHistory};
  `;
  vm.runInNewContext(source.replace('  document.addEventListener("DOMContentLoaded", wire);',inject),context);api=context.window.api;
  for(const pending of pendingJournals)fakeFs.mkdirSync(path.dirname(pending));
  return {api,calls,controls,files,sequence,pendingJournals,release:()=>engineCallback(),releaseResume:()=>resumeCallback()};
}
async function settle(f,running){
  for(let i=0;i<100;i++){if(f.api.pending()){f.api.choose(true);break;}if(!f.api.busy())break;await Promise.resolve();}
  await running;
  assert(!f.api.busy());assert(f.controls.stopWorkflow.hidden);
}
const editRegressions = {
  async "postcheck-error-first"() {
    const f=fixture({editResult:{ok:false,executorVersion:25,timelineMutated:true,error:"Original host error",settings:{validationToleranceFrames:1},markerFailureCount:1,markerFailures:["Marker write failed"]}});
    await settle(f,f.api.edit());
    assert.match(f.controls.workflowNoticeTechnical.textContent,/^Original host error; .*1 lỗi gắn marker Video, Voice hoặc Caption: Marker write failed/);
    assert.match(f.controls.workflowNoticeMessage.textContent,/Timeline được giữ đến bước đã thực hiện..*trước bước Gắn marker/);
  },
  async "closing-error-secondary"() {
    const f=fixture({advanceError:true,closeError:true});
    await settle(f,f.api.edit());
    assert.match(f.controls.workflowNoticeTechnical.textContent,/^Original advance error; Secondary close error/);
    assert(!f.controls.runSync.disabled&&!f.controls.runCaptions.disabled,"A failed close must allow later runs");
  },
  async "late-stop-accepts-success"() {
    for(const stopAt of ["edit-advance-2","edit-accept"]){
      const storage=new Map(),f=fixture({stopAt,storage});
      await settle(f,f.api.edit());
      assert.equal(f.controls.workflowNoticeTitle.textContent,"Đã dựng xong.",stopAt);
      assert(f.calls.some(c=>c[0]==="finish"&&c[1]==="success"));
      const hosts=f.calls.filter(c=>c[0]==="host").map(c=>c[1]);
      assert.equal(hosts.filter(c=>c.includes("acceptDiagnosticEdit")).length,1);
      assert(!hosts.some(c=>c.includes("abortDiagnosticEdit")));
      assert(!storage.has("pvs.recovery.v1"));
      assert.equal(f.calls.filter(c=>c[0]==="log"&&c[1]==="Yêu cầu Dừng đến sau khi dựng xong, giữ kết quả.").length,1);
    }
  },
  async "caption-export-failure-recovers-automatically"() {
    for(const retryError of [false,true]){
      const f=fixture({exportError:true,retryError});
      await settle(f,f.api.captions());
      const restores=f.calls.filter(c=>c[0]==="host"&&c[1].includes("restorePendingCaptionAudioExport"));
      assert.equal(restores.length,1,"Failed export must retry the on-disk journal automatically");
      assert(!f.api.pending()&&!f.controls.runSync.disabled&&!f.controls.runCaptions.disabled);
      assert.equal(f.pendingJournals.size,retryError?1:0);
      assert(f.controls.workflowNoticeTitle.textContent.includes("Không hoàn tất"));
      if(retryError){
        assert(f.controls.workflowNoticeMessage.textContent.includes("Chưa khôi phục được mute"));
        assert(f.calls.some(c=>c[0]==="log"&&c[1].includes("RETRY_FAILED")));
        const reloaded=fixture({pendingJournals:f.pendingJournals});
        await reloaded.api.reload();
        assert.equal(reloaded.calls.filter(c=>c[0]==="host"&&c[1]===restores[0][1]).length,1);
        assert.equal(f.pendingJournals.size,0);
      }else assert(f.controls.workflowNoticeMessage.textContent.includes("đã được tự động khôi phục"));
    }
  },
  async "pending-audio-retried-before-either-workflow"() {
    const journal=path.join("C:\\fixture","Jobs","Job_Subtitle_pending","job.json.audio-recovery.json");
    for(const mode of ["edit","captions"]){
      const f=fixture({pendingJournals:new Set([journal]),retryError:true});
      const startup=f.api.reload();
      const running=f.api[mode]();
      await startup;
      await settle(f,running);
      const attempts=()=>f.calls.filter(c=>c[0]==="host"&&c[1].includes("restorePendingCaptionAudioExport")).length;
      assert.equal(attempts(),1,"An immediate run shares the startup recovery attempt");
      f.calls.length=0;
      await settle(f,f.api[mode]());
      assert.equal(attempts(),1,"A later run retries a journal that still exists");
      assert(f.calls.findIndex(c=>c[0]==="host"&&c[1].includes("restorePendingCaptionAudioExport"))<
        f.calls.findIndex(c=>c[0]==="scan-"+mode),"Recovery runs before input is scanned");
      assert(f.pendingJournals.has(journal));
      assert(!f.controls.runSync.disabled&&!f.controls.runCaptions.disabled);
    }
  }
};
if(require.main===module)(async()=>{
  let failures=0;
  for(const [name,test] of Object.entries(editRegressions)){
    try { await test(); console.log("PASS "+name); }
    catch(error){failures++;console.error("FAIL "+name,error);}
  }
  if(failures||process.argv.includes("--edit-regressions")){
    process.exitCode=failures?1:0;
    return;
  }
  for(const mode of ["edit","captions"]){
    const points=mode==="edit"?["scan","build-dtw-trial-plan.ps1","run-alignment.ps1","build-sentence-plan.ps1","build-speed-merge-trial-plan.ps1","edit-begin","edit-advance-1"]:["scan","export-begin","export-yield","export-advance-1","export-advance-2","run-captions.ps1","caption-import"];
    for(const stopAt of points){
      const f=fixture({stopAt});await settle(f,f.api[mode]());
      assert.equal(f.controls.workflowNoticeTitle.textContent,"Đã dừng tác vụ",mode+":"+stopAt);
      assert(!f.calls.some(c=>c[0]==="finish"&&c[1]==="success"));
      const changed=stopAt.startsWith("edit-advance")||stopAt==="caption-import";
      assert(!f.controls.runSync.disabled&&!f.controls.runCaptions.disabled,mode+":"+stopAt);
      if(!changed)assert(f.controls.workflowNoticeMessage.textContent.includes("Timeline chưa bị thay đổi"));
      if(stopAt==="edit-advance-1")assert.match(f.controls.workflowNoticeMessage.textContent,/Timeline được giữ đến bước đã thực hiện..*trước bước Gắn marker/);
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
    assert(!f.controls.runSync.disabled&&!f.controls.runCaptions.disabled);
  }
  for(const options of [{},{lostSession:true},{closeError:true}]) {
    const storage=new Map(),key="pvs.recovery.v1";
    let saved;
    const active=fixture({storage,onPoint(point){if(point==="edit-advance-1")saved=storage.get(key);}});
    await settle(active,active.api.edit());
    assert(JSON.parse(saved).editSession && !storage.has(key));
    storage.set(key,saved);
    const reloaded=fixture({storage,...options});
    await reloaded.api.reload();
    assert.equal(reloaded.calls.filter(c=>c[0]==="host"&&c[1].includes("abortDiagnosticEdit")&&c[1].includes(JSON.parse(saved).editSession)).length,1);
    assert(!reloaded.api.pending()&&!reloaded.controls.runSync.disabled&&!reloaded.controls.runCaptions.disabled);
    assert.equal(storage.has(key),!!options.closeError);
    if(options.closeError)assert(reloaded.api.history().some(n=>n.tone==="warn"&&n.details.includes("Secondary close error")));
  }
  for(const options of [{stopAt:"edit-advance-1"},{advanceError:true},{advanceError:true,closeError:true}]) {
    const f=fixture(options);
    await settle(f,f.api.edit());
    assert(!f.controls.runSync.disabled&&!f.controls.runCaptions.disabled);
    f.sequence.sequenceId="another-sequence";
    f.sequence.name="Other template";
    options.advanceError=options.closeError=false;
    await settle(f,f.api.captions());
    assert(f.calls.some(c=>c[0]==="scan-captions"&&c[1]==="another-sequence"));
    assert.equal(f.controls.workflowNoticeTitle.textContent,"Đã tạo 2 phụ đề.","No recovery approval should interrupt the next caption run");
    const next=f.api.edit();
    for(let i=0;i<100&&!f.api.pending()&&f.api.busy();i++)await Promise.resolve();
    assert.equal(f.controls.workflowNoticeTitle.textContent,"Dựng sequence “Other template”?","Only the normal approval should be requested");
    f.api.choose(false);
    await next;
  }
  const quiet=policy.route({kind:"cancelled",impact:"changed"},{background:true});assert.equal(quiet.toast,"banner-and-center");assert.equal(quiet.attention,"none");assert.equal(policy.route({kind:"cancelled",observed:true},{background:true}).toast,"none");
  console.log("WORKFLOW_CANCELLATION_OK:both-workflows;preflight;engine;export-restoration;staged-abort;final-native-call;pending-lock;repeat-stop;recovery;error-precedence;quiet-cancel");
})().catch(e=>{console.error(e);process.exitCode=1;});
module.exports={fixture,settle};
