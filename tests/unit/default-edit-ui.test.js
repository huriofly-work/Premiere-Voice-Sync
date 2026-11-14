"use strict";
const assert=require("assert"),vm=require("vm"),fs=require("fs"),path=require("path").win32;
const source=fs.readFileSync(require("path").join(__dirname,"../../extension/js/main.js"),"utf8");
async function scenario(options={}){
  const calls=[],alerts=[],controls={pausePerformanceTrial:{checked:true}};let folder="",scans=0;
  const base={ok:true,schemaVersion:8,sequenceId:"seq",summary:{punctuationSentenceCount:2,captionCueCount:2}};
  const dtw=Object.assign({},base,{editBoundaryTrial:"dtw-additive-v1"});
  const merged=Object.assign({},options.noCuts?base:dtw,{speedMergeTrial:"adjacent-speed-v2",visualSegments:[],speedMergeSummary:{visualGroupsAfter:1}});
  const report=Object.assign({ok:true,revision:"dtw-additive-v1",canApply:!options.noCuts,addedCutCount:options.noCuts?0:1,coverageVerified:true,existingCutsPreserved:true,durationChangedFrames:0,newPauses:0,boundaries:[]},options.report||{});
  const merge=Object.assign({ok:true,revision:"adjacent-speed-v2",canApply:!options.noMerge,coverageVerified:true,voiceUnchanged:true,captionsUnchanged:true,durationChangedFrames:0,newPauses:0,summary:{mergeCount:options.noMerge?0:1,visualGroupsBefore:2,visualGroupsAfter:options.noMerge?2:1,warningsBefore:1,warningsAfter:0}},options.mergeReport||{});
  const fakeFs={existsSync:p=>p.endsWith(".srt"),mkdirSync:p=>{folder=p;},writeFileSync(p,t){if(p.endsWith("job.json"))calls.push(["job",JSON.parse(t)]);if(p.endsWith("timeline-executor.json"))calls.push(["executor-input",p,JSON.parse(t)]);},readFileSync(p){
    if(p.endsWith("alignment-result.json"))return JSON.stringify(Object.assign({recognitionBackend:"cpu",recognitionBackendLabel:"CPU"}, options.preserveTimeline?{preserveTimeline:true,recognitionReviewTasks:[{chapter:0,start:1,end:4}]}:{}));
    if(p.endsWith("dtw-trial-report.json"))return JSON.stringify(Object.assign({},report,{planPath:options.badPath?"C:\\outside\\plan.json":path.join(folder,"dtw-trial","sentence-edit-plan.json")}));
    if(p.endsWith("speed-merge-report.json"))return JSON.stringify(Object.assign({},merge,{planPath:path.join(folder,"speed-merge-trial","sentence-edit-plan.json")}));
    if(p.endsWith("sentence-edit-plan.json"))return JSON.stringify(p.includes("speed-merge-trial")?merged:p.includes("dtw-trial")?dtw:base);
    throw Error("Unexpected read");
  }};
  const context={require:n=>({fs:fakeFs,path,child_process:{}}[n]),window:{PvsSecurity:{assertNoLinks(){}},confirm(){throw Error("NATIVE_CONFIRM_FORBIDDEN");},alert:t=>alerts.push(t)},document:{getElementById:id=>controls[id]||(controls[id]={}),addEventListener(){}},localStorage:{getItem(){return null;},setItem(){}},process:{env:{}},console,fixture:{calls}};
  const inject=`
    applicationDataRoot=function(){return "C:\\\\fixture";};extensionRoot=function(){return "C:\\\\extension";};
    scanSequence=async function(){fixture.calls.push(["scan"]);return {name:"fixture",projectId:${!!options.staleProject} && fixture.calls.filter(c=>c[0]==="scan").length>1?"other-project":"project",sequenceId:${JSON.stringify(options.stale)} && fixture.calls.filter(c=>c[0]==="scan").length>1?"changed":"seq",voices:[{start:0,end:4,speedPercent:110,inPoint:0}]};};
    applySettings(Object.assign({},settingDefaults,${JSON.stringify(options.settings||{})}));
    if(${!!options.commaGap})byId("minDialogueGap").value="0,5";
    setWorkflowBusy=function(b){state.workflowBusy=b;};
    createWorkflowMetrics=function(workflow){fixture.calls.push(["metrics-start",workflow]);return {begin:s=>fixture.calls.push(["metrics-begin",s]),end:(r,o)=>fixture.calls.push(["metrics-end",o||"success"]),finish:o=>fixture.calls.push(["metrics-finish",o])};};
    runPowerShell=async function(file,args){fixture.calls.push(["script",file,args]);if(${!!options.invalidInput} && args.includes("-ValidateOnly"))throw Error("TRIAL_VOICE_MEDIA_IN_NONZERO");};
    executeStagedPlan=async function(p,pause,fast,workflow,metrics,noDelay){fixture.calls.push(["staged",p,pause,fast,workflow,noDelay]);return {ok:true,executorVersion:25,clearedClipMarkerCount:1,mergeClipMarkerCount:1};};
    evalHost=async function(){throw Error("DIRECT_SINGLE_CALL_EXECUTOR_FORBIDDEN");};
    removeTreeSafe=function(){fixture.calls.push(["cleanup"]);};status=log=renderBackend=function(){};
    state.targetSrt="C:\\\\fixture.srt";window.testApi={runSync,runPerformanceTrial,runFastPerformanceTrial,choose:chooseWorkflowNotice,pending:function(){return !!state.noticeChoice;},busy:function(){return state.workflowBusy;}};
  `;
  vm.runInNewContext(source.replace('  document.addEventListener("DOMContentLoaded", wire);',inject),context);
  const running=context.window.testApi[options.kind||"runSync"]();
  for(let i=0;i<10&&!context.window.testApi.pending();i++)await Promise.resolve();
  assert(context.window.testApi.pending(),"Start requires explicit in-panel approval.");
  assert(context.window.testApi.busy());assert(!calls.some(c=>["job","script","staged"].includes(c[0])));
  calls.push(["confirm",controls.workflowNoticeMessage.textContent]);
  await context.window.testApi.runSync();assert.strictEqual(calls.filter(c=>c[0]==="scan").length,1,"Duplicate start is blocked while confirming.");
  context.window.testApi.choose(options.cancel!==true);
  await running;assert(!context.window.testApi.busy());
  if(options.cancel)assert(!calls.some(c=>["job","script","staged","cleanup"].includes(c[0])));
  assert.strictEqual(alerts.length,0,"Workflow results must not open a native alert.");return {calls,alerts,controls};
}
(async()=>{
  const preserved=await scenario({preserveTimeline:true});
  assert(!preserved.calls.some(c=>c[0]==="staged"),"Unproven source mapping must never call the editing executor.");
  assert(!preserved.calls.some(c=>c[0]==="script"&&/build-sentence|build-dtw-trial.*(?!ValidateOnly)|build-speed-merge.*(?!ValidateOnly)/.test(c[1])&&!c[2].includes("-ValidateOnly")),"Whole-template preservation must not create an edit plan.");
  assert(preserved.calls.some(c=>c[0]==="metrics-finish"&&c[1]==="success"),"Recognition uncertainty finishes with review, not a failed workflow.");
  assert.strictEqual(preserved.controls.workflowNoticeCard.className,"workflow-notice-card warn");
  assert(preserved.controls.workflowNoticeTechnical.textContent.includes("00:00:01.000"),"The review includes the preserved voice range.");
  const fresh=await scenario({});assert.equal(fresh.calls.find(c=>c[0]==="job")[1].algorithm.minNoDialogueGapSeconds,0.5,"Fresh/default settings must reach the job as 0.5s.");
  const custom=await scenario({settings:{minDialogueGap:1.5}});assert.equal(custom.calls.find(c=>c[0]==="job")[1].algorithm.minNoDialogueGapSeconds,1.5,"A saved/custom threshold must override the default.");
  for(const stored of [null,{maxSpeed:130},{minDialogueGap:1,maxSpeed:130},{minDialogueGap:2,maxSpeed:130}]){
    const storage=new Map();if(stored)storage.set("pvs.algorithm",JSON.stringify(stored));
    const context={require:n=>({fs:{},path,child_process:{}}[n]),window:{},document:{addEventListener(){}},localStorage:{getItem:k=>storage.get(k)||null,setItem:(k,v)=>storage.set(k,v),removeItem:k=>storage.delete(k)}};
    vm.runInNewContext(source.replace('  document.addEventListener("DOMContentLoaded", wire);','window.settingsTest={load:loadSettings};'),context);
    assert.equal(context.window.settingsTest.load().minDialogueGap,stored&&stored.minDialogueGap!==undefined?stored.minDialogueGap:0.5,"Missing values inherit the new default; saved values are preserved.");
  }
  for(const commaGap of [false,true]){
    const r=await scenario({commaGap,settings:{minSpeed:60,maxSpeed:180,minDialogueGap:0.5,voiceGroupGap:3.5,maxCaptionCharacters:40}}),job=r.calls.find(c=>c[0]==="job")[1];
    assert.equal(job.algorithm.minNoDialogueGapSeconds,0.5);assert.equal(job.speedWarningMinPercent,60);assert.equal(job.speedWarningMaxPercent,180);
    assert.equal(job.algorithm.voiceGroupGapSeconds,3.5);assert.equal(job.algorithm.maxCaptionCharacters,40);
  }
  for(const options of [{},{noCuts:true},{noMerge:true},{noCuts:true,noMerge:true}]){
    const r=await scenario(options),job=r.calls.find(c=>c[0]==="job")[1],execution=r.calls.find(c=>c[0]==="staged");
    assert.strictEqual(job.workflow,"one-click-dtw-direct");assert.strictEqual(job.editBoundaryTrial,"dtw-additive-v1");assert.strictEqual(job.speedMergeTrial,"adjacent-speed-v2");
    assert.strictEqual(r.calls.filter(c=>c[0]==="confirm").length,1);assert.strictEqual(r.calls.filter(c=>c[0]==="staged").length,1);
    assert(r.calls.find(c=>c[0]==="confirm")[1].includes("dựng lại hình và audio theo voice"));
    assert(!r.calls.find(c=>c[0]==="confirm")[1].includes("DTW"),"Approval explains the consequence without algorithm details");
    assert(!r.calls.find(c=>c[0]==="confirm")[1].includes("Không dùng điểm cắt DTW"));
    assert(execution[1].endsWith("timeline-executor.json"));
    const packet=r.calls.find(c=>c[0]==="executor-input");assert.equal(packet[1],execution[1]);assert.equal(packet[2].speedMergeTrial,"adjacent-speed-v2");assert.equal(!!packet[2].editBoundaryTrial,!options.noCuts);
    assert.strictEqual(execution[2],false);assert.strictEqual(execution[3],true);assert.strictEqual(execution[4],"auto-edit-dtw-merge");
    assert.strictEqual(execution[5],true);assert(!r.calls.find(c=>c[0]==="confirm")[1].includes("BẢN THỬ KHÔNG DELAY"));
    const scripts=r.calls.filter(c=>c[0]==="script");assert(scripts[0][1].includes("build-dtw-trial-plan")&&scripts[0][2].includes("-ValidateOnly"));assert(scripts[1][1].includes("build-speed-merge")&&scripts[1][2].includes("-ValidateOnly"));
    const mergeCall=scripts.find(c=>c[1].includes("build-speed-merge")&&!c[2].includes("-ValidateOnly"));assert(mergeCall[2].includes("-PlanPath"));assert.strictEqual(mergeCall[2][3].includes("dtw-trial"),!options.noCuts);
    assert.strictEqual(r.calls.filter(c=>c[0]==="scan").length,2);assert(r.calls.some(c=>c[0]==="cleanup"));
    assert.strictEqual(r.controls.workflowNotice.hidden,false);
    assert(r.controls.workflowNoticeTitle.textContent.includes("Đã dựng xong"));
    assert.strictEqual(r.calls.find(c=>c[0]==="metrics-start")[1],"auto-edit");
    assert.deepStrictEqual(r.calls.filter(c=>c[0]==="metrics-begin").map(c=>c[1]),["preflight","alignment","sentence-plan","dtw-plan","speed-merge","template-check","timeline","cleanup"]);
    assert.strictEqual(r.calls.find(c=>c[0]==="metrics-finish")[1],"success");
  }
  for(const report of [{coverageVerified:false},{existingCutsPreserved:false},{durationChangedFrames:1},{newPauses:1},{revision:"wrong"},{addedCutCount:NaN},{addedCutCount:-1}]){
    const r=await scenario({report});assert(!r.calls.some(c=>c[0]==="staged"));assert(r.calls.some(c=>c[0]==="cleanup"));
    assert.strictEqual(r.calls.find(c=>c[0]==="metrics-finish")[1],"failed");
    assert.strictEqual(r.controls.workflowNoticeCard.className,"workflow-notice-card error");
  }
  for(const mergeReport of [{voiceUnchanged:false},{captionsUnchanged:false},{coverageVerified:false},{durationChangedFrames:1},{newPauses:1},{revision:"wrong"},{canApply:false}]){
    const r=await scenario({mergeReport});assert(!r.calls.some(c=>c[0]==="staged"));assert(r.calls.some(c=>c[0]==="cleanup"));
  }
  for(const options of [{stale:true},{badPath:true},{invalidInput:true},{cancel:true}]){
    const r=await scenario(options);assert(!r.calls.some(c=>c[0]==="staged"));
    if(options.invalidInput)assert(!r.calls.some(c=>c[0]==="script"&&c[1].includes("run-alignment")));
  }
  for(const kind of ["runPerformanceTrial","runFastPerformanceTrial"]){
    const r=await scenario({kind}),job=r.calls.find(c=>c[0]==="job")[1],execution=r.calls.find(c=>c[0]==="staged");
    assert(!job.editBoundaryTrial&&!job.speedMergeTrial);assert.strictEqual(execution[2],kind==="runPerformanceTrial");assert.strictEqual(execution[3],kind==="runFastPerformanceTrial");
    assert.strictEqual(execution[5],false);
  }
  for(const kind of ["runSync","runPerformanceTrial","runFastPerformanceTrial"]){
    const r=await scenario({kind,staleProject:true});assert(!r.calls.some(c=>c[0]==="staged"),"Project-only change must block all edit/diagnostic executors even when sequence and geometry match");
  }
  assert(!/allowDtwTrial|allowSpeedMerge|runDtwTrial/.test(source));
  assert(!/noDelayAutoEditTrial|noDelayTrial|BẢN THỬ KHÔNG DELAY/.test(source),"Accepted scheduling is the default, not a trial toggle.");
  console.log("DEFAULT_EDIT_UI_OK:DTW-merge-fast-default;one-confirmation;safe-no-op-continues;both-preflights-before-ASR;baseline-diagnostics;stale-path-report-guards;cleanup");
})().catch(e=>{console.error(e);process.exitCode=1;});
