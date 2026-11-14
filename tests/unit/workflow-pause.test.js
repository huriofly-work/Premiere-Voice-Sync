"use strict";
const assert=require("assert"),{fixture,settle}=require("./workflow-cancellation.test.js");
const drain=async(n=100)=>{for(let i=0;i<n;i++)await Promise.resolve();};
async function paused(mode,point,extras={}){
  let requested=false;
  const options={...extras,onPoint(key,api){
    if(!requested&&key===point){requested=true;api.pause();api.pause();assert(api.context().pauseRequested);}
  }};
  const f=fixture(options),running=f.api[mode]();
  for(let i=0;i<250;i++){
    if(f.api.pending())f.api.choose(true);
    if(f.api.context()?.paused)break;
    await Promise.resolve();
  }
  assert(requested,mode+":"+point+":request");
  if(!extras.pauseReadFailure){
    assert(f.api.context()?.paused,mode+":"+point+":must pause");
    const count=f.calls.length;await drain();assert.equal(f.calls.length,count,"No engine/native work while paused");
    assert(f.api.busy());assert(!f.controls.stopWorkflow.disabled);assert(!f.controls.pauseWorkflow.disabled);
    assert.equal(f.controls.pauseWorkflow.textContent,"Tiếp tục");
    assert(!Object.keys(f.files).some(n=>n.endsWith(".cancel")),"Pause never cancels an engine");
    await f.api.edit();await f.api.captions();assert(f.api.busy());
  }
  return {f,running,options};
}
(async()=>{
  for(const mode of ["edit","captions"]){
    const points=mode==="edit"?["scan","build-dtw-trial-plan.ps1","run-alignment.ps1","build-sentence-plan.ps1","build-speed-merge-trial-plan.ps1","edit-begin","edit-advance-1"]:["scan","export-begin","export-yield","export-advance-1","export-advance-2","run-captions.ps1"];
    for(const point of points){
      const {f,running}=await paused(mode,point);
      if(point.startsWith("export")){
        assert.equal(f.calls.filter(c=>c[0]==="host"&&c[1].includes("advanceCaptionAudioExport")).length,2,"Export completes/restores all regions before pause");
        assert(!f.calls.some(c=>c[0]==="engine"),"No ASR before resume");
      }
      const engineBefore=f.calls.filter(c=>c[0]==="engine").length;
      f.api.pause();f.api.pause();await settle(f,running);
      assert(f.calls.some(c=>c[0]==="finish"&&c[1]==="success"),mode+":"+point+":resume succeeds");
      assert.equal(f.calls.filter(c=>c[0]==="host"&&c[1].includes("workflowPauseState")).length,2);
      assert(!f.controls.workflowNoticeTitle.textContent.includes("Không hoàn tất"));
      if(point==="run-captions.ps1")assert.equal(f.calls.filter(c=>c[0]==="engine").length,engineBefore,"Resume does not rerun completed ASR");
    }
  }
  for(const [mode,point] of [["edit","edit-advance-1"],["captions","run-captions.ps1"]]){
    let r=await paused(mode,point);r.f.api.stop();r.f.api.stop();await settle(r.f,r.running);
    assert.equal(r.f.controls.workflowNoticeTitle.textContent,"Đã dừng tác vụ");
    assert.equal(!!r.f.api.recovery(),mode==="edit");
    r=await paused(mode,point);r.options.snapshotVersion=1;r.f.api.pause();await settle(r.f,r.running);
    assert(r.f.controls.workflowNoticeTitle.textContent.includes("Không hoàn tất"));assert(r.f.api.recovery());
    assert(!r.f.calls.some(c=>c[0]==="host"&&c[1].includes("applyCaptionOnly")));
    if(mode==="edit")assert.equal(r.f.calls.filter(c=>c[0]==="host"&&c[1].includes("advanceDiagnosticEdit")).length,1,"Changed timeline cannot receive next stage");
    r=await paused(mode,point);r.f.api.fatal(Error("FATAL_PAUSED"));await settle(r.f,r.running);
    assert(r.f.controls.workflowNoticeTitle.textContent.includes("Không hoàn tất")||r.f.controls.workflowNoticeTitle.textContent.includes("lỗi"));
    r=await paused(mode,point);r.options.pauseReadFailure=true;r.f.api.pause();await settle(r.f,r.running);assert(r.f.api.recovery(),"Unreadable resume state keeps recovery locked");
  }
  const broken=await paused("captions","run-captions.ps1",{pauseReadFailure:true});await settle(broken.f,broken.running);
  assert(broken.f.controls.workflowNoticeTitle.textContent.includes("Không hoàn tất"));
  for(const [mode,point] of [["edit","edit-advance-2"],["captions","caption-import"]]){const f=fixture({onPoint(key,api){if(key===point)api.pause();}});await settle(f,f.api[mode]());assert(f.calls.some(c=>c[0]==="finish"&&c[1]==="success"),"Final native completion must not leave an orphan pause");}
  const pending=fixture({holdEngine:true,onPoint(key,api){if(key==="run-captions.ps1")api.pause();}}),running=pending.api.captions();await drain(200);
  assert(pending.api.context().pauseRequested&&!pending.api.context().paused,"Running ASR is not falsely reported paused");assert(pending.controls.pauseWorkflow.disabled);pending.api.stop();assert(pending.api.busy());pending.release();await settle(pending,running);assert.equal(pending.controls.workflowNoticeTitle.textContent,"Đã dừng tác vụ");
  const verifying=await paused("edit","edit-advance-1",{holdResumeRead:true});verifying.f.api.pause();await drain();assert(verifying.f.api.context().resuming);verifying.f.api.stop();assert(verifying.f.api.busy());verifying.f.releaseResume();await settle(verifying.f,verifying.running);assert.equal(verifying.f.controls.workflowNoticeTitle.textContent,"Đã dừng tác vụ");
  console.log("WORKFLOW_PAUSE_OK:both-modes;safe-boundaries;no-ASR-rerun;no-work-while-paused;resume-state-guard;stop-paused;fatal-release;repeat-click;export-restored-first");
})().catch(e=>{console.error(e);process.exitCode=1;});
