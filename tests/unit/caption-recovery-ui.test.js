"use strict";
const assert=require("assert"),fs=require("fs"),path=require("path").win32,vm=require("vm");
const source=fs.readFileSync(require("path").join(__dirname,"../../extension/js/main.js"),"utf8");
const root="C:\\fixture",jobs=path.join(root,"Jobs"),first=path.join(jobs,"Job_First"),second=path.join(jobs,"Job_Second"),old=path.join(jobs,"Job_Stale"),journal=folder=>path.join(folder,"job.json.audio-recovery.json");
const entries=new Set([jobs,first,second,old,journal(first),journal(second)]),removed=[],calls=[],storage=new Map(),controls={};
const fakeFs={existsSync:p=>entries.has(p),readdirSync:p=>p===jobs?[...entries].filter(n=>path.dirname(n)===jobs).map(n=>path.basename(n)):[],lstatSync:()=>({isDirectory:()=>true,isSymbolicLink:()=>false,mtime:new Date(0)})};
const context={require:n=>({fs:fakeFs,path,child_process:{}}[n]),window:{PvsSecurity:{assertNoLinks(){}}},document:{getElementById:id=>controls[id]||(controls[id]={setAttribute(){}}),addEventListener(){}},localStorage:{getItem:k=>storage.get(k)||null,setItem:(k,v)=>storage.set(k,v),removeItem:k=>storage.delete(k)},fixture:{root,removed,calls,entries}};
vm.runInNewContext(source.replace('  document.addEventListener("DOMContentLoaded", wire);',`
  applicationDataRoot=()=>fixture.root;removeTreeSafe=p=>{if(fs.existsSync(path.join(p,"job.json.audio-recovery.json")))throw Error("DELETED_PENDING_JOURNAL");fixture.removed.push(p);fixture.entries.delete(p);};status=log=()=>{};
  confirmWorkflowNotice=async()=>true;scanCaptionRange=async()=>({sequenceId:"seq",snapshot:"base"});
  evalHost=async expression=>{fixture.calls.push(expression);const start=expression.indexOf("(")+1,p=JSON.parse(expression.slice(start,-1));fixture.entries.delete(p);return {ok:true,restored:true};};
  window.api={cleanup:cleanupStaleJobs,check:checkIncidentInputs,recovery:()=>recoveryContext,captions:runCaptions};
`),context);
(async()=>{
  assert.equal(context.window.api.cleanup(),1);assert.deepEqual(removed,[old]);assert.equal(context.window.api.recovery().audioRecoveryPath,journal(first));assert(entries.has(journal(first))&&entries.has(journal(second)));
  assert.equal(JSON.parse(storage.get("pvs.recovery.v1")).audioRecoveryPath,journal(first));
  await context.window.api.captions();assert(!calls.length,"orphan journal must block new work before host or engine");
  await context.window.api.check();assert.equal(context.window.api.recovery().audioRecoveryPath,journal(second),"recovering one journal must not unlock other pending recovery");
  await context.window.api.check();assert.equal(context.window.api.recovery(),null);assert.equal(calls.length,2);assert(!storage.has("pvs.recovery.v1"));
  assert(calls.every(c=>c.includes("restorePendingCaptionAudioExport")));assert(removed.includes(first)&&removed.includes(second),"old job is eligible for cleanup only after its journal has been restored and removed");
  console.log("CAPTION_RECOVERY_UI_OK:orphan-discovery;no-stale-delete;durable-pointer;run-lock;recovery-path-passed;multiple-journals-serialized");
})().catch(error=>{console.error(error);process.exitCode=1;});
