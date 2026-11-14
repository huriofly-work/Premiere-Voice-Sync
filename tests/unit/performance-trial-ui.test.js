"use strict";
const assert=require("assert"),fs=require("fs"),vm=require("vm"),path=require("path").win32,crypto=require("crypto");
const source=fs.readFileSync(require("path").join(__dirname,"../../extension/js/main.js"),"utf8");
async function scenario(options={}){
  const calls=[],rows=[],warnings=[],controls={workflowNotice:{hidden:true}},base="stable-source\r\n",hash=crypto.createHash("sha256").update(base.replace(/\r\n/g,"\n")).digest("hex");
  let request=0;
  const fakeFs={readFileSync(){return base;},mkdirSync(){},writeFileSync(p,text,opt){if(options.logCreateError)throw Error("DISK_FULL");assert.strictEqual(opt.flag,"wx");rows.push(JSON.parse(text));},appendFileSync(p,text){if(options.logWriteError)throw Error("DISK_FULL");rows.push(JSON.parse(text));}};
  const context={require:n=>({fs:fakeFs,path,child_process:{},crypto}[n]),window:{PvsSecurity:{assertNoLinks(){}},setTimeout(cb,delay){calls.push(["yield",delay]);setTimeout(cb,0);}},document:{getElementById:id=>controls[id]||(controls[id]={}),addEventListener(){}},localStorage:{getItem(){return null;}},process:{env:{}},console,fixture:{calls}};
  const inject=`
    applicationDataRoot=function(){return "C:\\\\local";}; extensionRoot=function(){return "C:\\\\panel";};
    ensureHostLoaded=async function(){};status=function(){};log=function(message,level){if(level==="warn")fixture.warnings.push(message);};
    window.testApi={execute:executeStagedPlan,choose:choosePerformanceCheckpoint};
  `;
  context.fixture.warnings=warnings;
  vm.runInNewContext(source.replace('  document.addEventListener("DOMContentLoaded", wire);',inject),context);
  context.window.__adobe_cep__={evalScript(expression,callback){
    calls.push(["host",expression]);
    if(expression.includes("diagnosticInfo")){callback(JSON.stringify({ok:true,revision:"staged-edit-v3",baseHash:options.badHash?"wrong":hash}));return;}
    if(expression.includes("beginDiagnosticEdit")){callback(JSON.stringify(options.active?{ok:false,error:"DIAGNOSTIC_SESSION_ACTIVE"}:{ok:true,nextCall:0,nextStage:"Hình"}));return;}
    if(expression.includes("abortDiagnosticEdit")){callback(JSON.stringify({ok:false,done:true,timings:[]}));return;}
    if(expression.includes("advanceDiagnosticEdit")){
      if(options.evalError){callback("EvalScript error.");return;}
      callback(JSON.stringify(request++===0?{ok:true,done:false,nextCall:1,nextStage:"Voice",stage:"Hình",stageIndex:1,stageCount:2,milliseconds:4,checkpoint:options.pause?"Hình":""}:{ok:true,done:true,result:{ok:true,private:"SECRET_MEDIA_NAME_AND_PATH"},timings:[{stage:"Voice",milliseconds:5,complete:true}]}));return;
    }
    throw Error("Unexpected host call");
  }};
  const promise=context.window.testApi.execute("C:\\secret\\voice.mp3",!!options.pause,!!options.fast,undefined,undefined,!!options.noDelay);
  if(options.pause){
    for(let i=0;i<100&&controls.workflowNotice.hidden!==false;i++)await new Promise(r=>setTimeout(r,1));
    assert.strictEqual(controls.workflowNotice.hidden,false);
    assert.strictEqual(controls.acceptWorkflowNotice.textContent,"Play bình thường — Tiếp tục");
    assert.strictEqual(calls.filter(c=>c[0]==="host"&&c[1].includes("advanceDiagnosticEdit")).length,1,"Checkpoint cannot resume without user observation.");
    // Drive actual checkpoint button handler via the injected API.
    context.window.testApi.choose(!options.stop);
  }
  let result,error;try{result=await promise;}catch(e){error=e.message;}
  assert(!JSON.stringify(rows).includes("SECRET_MEDIA_NAME_AND_PATH"));assert(!JSON.stringify(rows).includes("voice.mp3"));assert(!JSON.stringify(rows).includes("C:\\\\secret"));
  assert(!calls.some(c=>c[0]==="host"&&c[1].includes("executePlan(")));
  if(!options.badHash)assert.strictEqual(controls.workflowNotice.hidden,true);
  return {calls,rows,result,error,warnings};
}
(async()=>{
  let r=await scenario();assert(r.result.ok);assert.strictEqual(r.calls.filter(c=>c[0]==="yield").length,2);assert(r.calls.filter(c=>c[0]==="yield").every(c=>c[1]===150));assert.deepStrictEqual(r.rows.filter(r=>r.type==="request").map(r=>r.stage),["Hình","Voice"]);
  r=await scenario({pause:true});assert(r.result.ok);assert(r.rows.some(r=>r.type==="user-observation"&&r.previewHealthy===true));
  r=await scenario({fast:true});assert(r.result.ok);assert(r.calls.filter(c=>c[0]==="yield").every(c=>c[1]===20));assert(r.calls.some(c=>c[0]==="host"&&c[1].includes('"fast")')));assert.strictEqual(r.rows[0].profile,"fast");assert.strictEqual(r.rows[0].yieldMilliseconds,20);
  r=await scenario({fast:true,noDelay:true});assert(r.result.ok);assert.strictEqual(r.calls.filter(c=>c[0]==="yield").length,0,"No-delay keeps no artificial sleep, with bounded native batches.");assert(r.calls.some(c=>c[0]==="host"&&c[1].includes('"no-delay")')));assert.strictEqual(r.rows[0].profile,"no-delay");assert.strictEqual(r.rows[0].yieldMilliseconds,0);assert.strictEqual(r.rows[0].batchLimitsDisabled,false);assert.strictEqual(r.rows[0].nativeSpeedPairsPerBatch,4);assert.strictEqual(r.rows[0].captionCleanupDelayMilliseconds,0);
  r=await scenario({pause:true,stop:true});assert(r.error.includes("Timeline mới dựng một phần"));assert.strictEqual(r.calls.filter(c=>c[0]==="host"&&c[1].includes("advanceDiagnosticEdit")).length,1);assert.strictEqual(r.calls.filter(c=>c[0]==="host"&&c[1].includes("abortDiagnosticEdit")).length,1);
  r=await scenario({evalError:true});assert(r.error);assert.strictEqual(r.calls.filter(c=>c[0]==="host"&&c[1].includes("advanceDiagnosticEdit")).length,1);assert.strictEqual(r.calls.filter(c=>c[0]==="host"&&c[1].includes("abortDiagnosticEdit")).length,1);
  r=await scenario({active:true});assert(r.error.includes("ACTIVE"));assert(!r.calls.some(c=>c[0]==="host"&&c[1].includes("abortDiagnosticEdit")));
  r=await scenario({badHash:true});assert(r.error.includes("không khớp"));assert.strictEqual(r.rows.length,0);assert.strictEqual(r.calls.filter(c=>c[0]==="host").length,1);
  for(const fault of ["logCreateError","logWriteError"]){
    r=await scenario({[fault]:true,noDelay:true,fast:true});assert(r.result&&r.result.ok,"Optional trace failure must not abort editing: "+r.error);
    assert.strictEqual(r.warnings.length,1);assert(!r.calls.some(c=>c[0]==="host"&&c[1].includes("abortDiagnosticEdit")));
  }
  console.log("PERFORMANCE_TRIAL_UI_MOCK_OK:separate-host-calls;event-loop-yield;checkpoint-continue-and-stop;no-retry;hash-guard;no-other-session-abort;private-data-not-in-profile");
})().catch(e=>{console.error(e);process.exitCode=1;});
