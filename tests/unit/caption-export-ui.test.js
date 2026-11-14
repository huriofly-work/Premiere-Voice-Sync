"use strict";
const assert=require("assert"),fs=require("fs"),path=require("path"),vm=require("vm");
const source=fs.readFileSync(path.join(__dirname,"../../extension/js/main.js"),"utf8");
function fixture(options={}){
  const calls=[],timings=[];let pending=false;
  const context={require:n=>({fs:{},path:path.win32,child_process:{}}[n]),window:{PvsSecurity:{}},document:{addEventListener(){}},localStorage:{getItem:()=>null},fixture:{
    host:async expression=>{
      assert(!pending,"No overlapping native/cleanup calls");pending=true;calls.push(expression);
      try{
        if(expression.includes("beginCaptionAudioExport")){
          if(options.beginTransportFailure)throw Error("BEGIN_TRANSPORT");
          return options.preflightFailure?{ok:false,done:true,error:"PREFLIGHT"}:{ok:true,done:false,nextCall:0,rangeCount:2};
        }
        if(expression.includes("advanceCaptionAudioExport")){
          assert.equal(calls.at(-2),"yield:100","A separate event-loop turn must precede every native export");
          if(options.advanceTransportFailure)throw Error("ADVANCE_TRANSPORT");
          if(options.nativeFailure)return {ok:false,done:true,error:"NATIVE",restored:true};
          if(expression.endsWith(",0)"))return {ok:true,done:false,nextCall:options.badOrder?0:1};
          return {ok:true,done:true,restored:true};
        }
        assert(expression.includes("abortCaptionAudioExport"));
        return options.restoreFailure?{ok:false,done:true,restored:false,error:"RESTORE",exportFailurePhase:"restore"}:{ok:false,done:true,restored:true,error:"ABORT"};
      }finally{pending=false;}
    }
  },setTimeout:(fn,ms)=>{assert(!pending);calls.push("yield:"+ms);Promise.resolve().then(fn);}};
  vm.runInNewContext(source.replace('  document.addEventListener("DOMContentLoaded", wire);',`evalHost=fixture.host;window.exportAudio=exportCaptionAudio;`),context);
  return {run:()=>context.window.exportAudio("job.json","wave.epr",2,{audioExport(...args){timings.push(args);if(options.metricsFailure)throw Error("LOG_FAILED");}}),calls,timings};
}
(async()=>{
  const good=fixture(),result=await good.run();assert(result.ok&&result.done);assert.equal(good.calls.length,5);assert(!good.calls.some(x=>x.includes("abort")));
  assert.deepEqual(good.timings.map(t=>t.slice(0,2)),[["prepare","start"],["prepare","end"],["yield","start"],["yield","end"],["render","start"],["render","end"],["yield","start"],["yield","end"],["render","start"],["render","end"]]);
  assert((await fixture({metricsFailure:true}).run()).ok,"Diagnostic failures must not change workflow outcome");
  for(const options of [{preflightFailure:true},{nativeFailure:true}]){const f=fixture(options),r=await f.run();assert(!r.ok);assert(!f.calls.some(x=>x.includes("abort")),"A host-completed restoration must not be repeated");}
  for(const options of [{beginTransportFailure:true},{advanceTransportFailure:true},{badOrder:true},{advanceTransportFailure:true,restoreFailure:true}]){
    const f=fixture(options);await assert.rejects(f.run(),options.restoreFailure?/ADVANCE_TRANSPORT[\s\S]*RESTORE/:options.beginTransportFailure?/BEGIN_TRANSPORT/:options.badOrder?/Sai thứ tự/:/ADVANCE_TRANSPORT/);
    assert.equal(f.calls.filter(x=>x.includes("abortCaptionAudioExport")).length,1);
  }
  console.log("CAPTION_EXPORT_UI_OK:separate-host-calls,yield-before-every-export,bounded-call-order,no-retry,abort-on-transport-error,restore-error-retains-cause");
})().catch(e=>{console.error(e);process.exitCode=1;});
