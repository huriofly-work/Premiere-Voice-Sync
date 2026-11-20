"use strict";
const assert=require("assert"),fs=require("fs"),path=require("path").win32,vm=require("vm");
const source=fs.readFileSync(require("path").join(__dirname,"../../extension/js/main.js"),"utf8");
const root="C:\\fixture",jobs=path.join(root,"Jobs"),first=path.join(jobs,"Job_First"),second=path.join(jobs,"Job_Second"),live=path.join(jobs,"Job_Live"),linked=path.join(jobs,"Job_Linked"),old=path.join(jobs,"Job_Stale"),journal=folder=>path.join(folder,"job.json.audio-recovery.json");
const entries=new Set([jobs,first,second,live,linked,old,journal(first),journal(second),journal(live),journal(linked)]),removed=[],calls=[],logs=[],storage=new Map(),controls={};
storage.set("pvs.recovery.v1",JSON.stringify({workflow:"captions",audioRecoveryPath:journal(root)}));
const fakeFs={existsSync:p=>entries.has(p),readdirSync:p=>p===jobs?[...entries].filter(n=>path.dirname(n)===jobs).map(n=>path.basename(n)):[],lstatSync:()=>({isDirectory:()=>true,isSymbolicLink:()=>false,mtime:new Date(0)})};
const context={require:n=>({fs:fakeFs,path,child_process:{}}[n]),window:{PvsSecurity:{assertNoLinks(_fs,_path,p){if(p===journal(linked))throw Error("SECURITY_LINKED_PATH");}}},document:{getElementById:id=>controls[id]||(controls[id]={setAttribute(){}}),addEventListener(){}},localStorage:{getItem:k=>storage.get(k)||null,setItem:(k,v)=>storage.set(k,v),removeItem:k=>storage.delete(k)},fixture:{root,removed,calls,entries,logs,liveJournal:journal(live)}};
vm.runInNewContext(source.replace('  document.addEventListener("DOMContentLoaded", wire);',`
  applicationDataRoot=()=>fixture.root;removeTreeSafe=p=>{if(fs.existsSync(path.join(p,"job.json.audio-recovery.json")))throw Error("DELETED_PENDING_JOURNAL");fixture.removed.push(p);fixture.entries.delete(p);};status=()=>{};log=(message,tone)=>fixture.logs.push([message,tone]);
  confirmWorkflowNotice=async()=>{throw Error("UNEXPECTED_RECOVERY_CONFIRMATION");};
  evalHost=async expression=>{
    const start=expression.indexOf("(")+1,p=JSON.parse(expression.slice(start,-1));
    fixture.calls.push(p);
    if(fixture.entries.delete(fixture.liveJournal))return {ok:false,done:true,restored:true};
    fixture.entries.delete(p);
    return {ok:true,restored:true};
  };
  window.api={cleanup:cleanupStaleJobs,start:()=>recoverPendingRuns(true),current:()=>currentNotice};
`),context);
(async()=>{
  const api=context.window.api;
  assert.equal(api.cleanup(),1);assert.deepEqual(removed,[old]);
  assert(entries.has(journal(first))&&entries.has(journal(second))&&entries.has(journal(linked)));
  await api.start();
  assert.deepEqual(calls,[journal(second),journal(second),journal(first)],"Startup must attempt every eligible journal, even if the first call closes a different live export");
  assert([first,second,live].every(folder=>removed.includes(folder)),"Old jobs are eligible for cleanup after the host removes their journals");
  assert(entries.has(journal(linked))&&!removed.includes(linked),"A linked journal must never be passed to the host or deleted");
  assert(logs.some(([message,tone])=>tone==="warn"&&message.includes("SECURITY_LINKED_PATH")));
  assert(api.current().tone==="warn"&&!api.current().choice);
  assert(!storage.has("pvs.recovery.v1"),"Audio paths are discovered on disk");
  console.log("CAPTION_RECOVERY_UI_OK:startup;multiple-journals;cleanup-after-restore;linked-journal-refused;warning-only");
})().catch(error=>{console.error(error);process.exitCode=1;});
