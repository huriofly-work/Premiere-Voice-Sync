"use strict";
const assert=require("assert"), fs=require("fs"), path=require("path"), cp=require("child_process");
const root=path.resolve(__dirname,"../.."), sandbox=fs.mkdtempSync(path.join(root,".tmp-cancel-process-"));
const ps=path.join(process.env.SystemRoot,"System32/WindowsPowerShell/v1.0/powershell.exe");
const literal=s=>"'"+s.replace(/'/g,"''")+"'";
const sleep=ms=>new Promise(r=>setTimeout(r,ms));
const children=[];
function run(file,args=[]){
  const child=cp.execFile(ps,["-NoProfile","-ExecutionPolicy","Bypass","-File",file,...args],{windowsHide:true},(error,stdout,stderr)=>child.done({error,stdout,stderr}));
  child.result=new Promise(r=>{child.done=r;}); children.push(child); return child;
}
async function until(fn){for(let i=0;i<200;i++){if(fn())return;await sleep(50);}throw Error("FIXTURE_TIMEOUT");}
(async()=>{
  const engine=path.join(sandbox,"Máy thử ' riêng"), lib=path.join(engine,"lib"); fs.mkdirSync(lib,{recursive:true});
  for(const [src,dest] of [["extension/engine/run-workflow.ps1","run-workflow.ps1"],["extension/engine/lib/Security.ps1","lib/Security.ps1"]])fs.copyFileSync(path.join(root,src),path.join(engine,dest));
  const fixture=String.raw`param([string]$JobPath,[string]$PlanPath,[switch]$ValidateOnly)
$ErrorActionPreference='Stop'
$job=Get-Content -LiteralPath $JobPath -Raw -Encoding UTF8 | ConvertFrom-Json
if($job.mode -eq 'normal') { [Console]::WriteLine(('SUCCESS:'+ $PlanPath + ':' + $ValidateOnly)); exit 0 }
if($job.mode -eq 'fail') { [Console]::Error.WriteLine('FIXTURE_ENGINE_FAILURE'); exit 7 }
$descendantCommand='[IO.File]::WriteAllText(' + "'" + $job.ready.Replace("'","''") + "'" + ',[string]$PID); Start-Sleep -Seconds 60'
$encoded=[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($descendantCommand))
$info=New-Object Diagnostics.ProcessStartInfo
$info.FileName=Join-Path $PSHOME 'powershell.exe'; $info.Arguments='-NoProfile -EncodedCommand '+$encoded
$info.UseShellExecute=$false; $info.CreateNoWindow=$true
$descendant=[Diagnostics.Process]::Start($info)
[IO.File]::WriteAllText($job.parent,[string]$PID)
Start-Sleep -Seconds 60
`;
  fs.writeFileSync(path.join(engine,"run-alignment.ps1"),"\ufeff"+fixture,"utf8");
  const wrapper=path.join(engine,"run-workflow.ps1");
  function request(name,mode,script="run-alignment.ps1"){
    const folder=path.join(sandbox,name);fs.mkdirSync(folder);
    const job=path.join(folder,"job.json"), req=path.join(folder,"request.json");
    fs.writeFileSync(job,JSON.stringify({mode,ready:path.join(folder,"grandchild.txt"),parent:path.join(folder,"parent.txt")}));
    fs.writeFileSync(req,JSON.stringify({script,args:["-JobPath",job,"-PlanPath","Đường ' dẫn $() & giữ nguyên","-ValidateOnly"]}));
    return {folder,req};
  }
  let f=request("normal","normal"),r=await run(wrapper,["-RequestPath",f.req]).result;
  assert.ifError(r.error);assert(r.stdout.includes("SUCCESS:Đường ' dẫn $() & giữ nguyên:True"),JSON.stringify(r));
  f=request("fail","fail");r=await run(wrapper,["-RequestPath",f.req]).result;assert.equal(r.error.code,7,JSON.stringify(r));assert(r.stderr.includes("FIXTURE_ENGINE_FAILURE"));
  f=request("rejected","normal","..\\outside.ps1");r=await run(wrapper,["-RequestPath",f.req]).result;assert(r.error);assert(r.stderr.includes("WORKFLOW_SCRIPT_NOT_ALLOWED"));
  f=request("early","normal");fs.writeFileSync(f.req+".cancel","stop");r=await run(wrapper,["-RequestPath",f.req]).result;assert.equal(r.error.code,1223);assert(!r.stdout.includes("SUCCESS"));
  // An unrelated process must survive cancellation of the owned job.
  const otherFile=path.join(sandbox,"unrelated.ps1");fs.writeFileSync(otherFile,"Start-Sleep -Seconds 60");const other=run(otherFile);
  f=request("cancel-tree","tree");const running=run(wrapper,["-RequestPath",f.req]);
  await until(()=>fs.existsSync(path.join(f.folder,"grandchild.txt"))&&fs.existsSync(path.join(f.folder,"parent.txt")));
  const pids=["parent.txt","grandchild.txt"].map(n=>Number(fs.readFileSync(path.join(f.folder,n),"utf8")));
  const before=Date.now();fs.writeFileSync(f.req+".cancel","stop");r=await running.result;
  assert.equal(r.error.code,1223,JSON.stringify(r));assert(Date.now()-before<10000);
  for(const pid of pids)assert.throws(()=>process.kill(pid,0),"Owned descendant must exit before wrapper callback");
  assert.doesNotThrow(()=>process.kill(other.pid,0),"Unrelated process must survive");other.kill();await other.result;
  console.log("WORKFLOW_PROCESS_OK:real-Windows-job;gated-start;cancel-before-start;owned-descendants-drained;unrelated-survives;Unicode-arguments;exit-status");
})().catch(e=>{console.error(e);process.exitCode=1;}).finally(async()=>{
  for(const child of children)if(child.exitCode===null)child.kill();
  await Promise.all(children.map(c=>c.result));
  fs.rmSync(sandbox,{recursive:true,force:true});
});
