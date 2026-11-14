"use strict";
// Real compiled helper, inherited pipes and lifecycle; no UI, toast or Premiere interaction.
const assert=require("assert"),cp=require("child_process"),path=require("path");
const executable=path.resolve(__dirname,"../../extension/native/PvsNotifications.exe");
async function run() {
  const session="c".repeat(32),child=cp.spawn(executable,["--pipe",String(process.pid),session],{windowsHide:true,stdio:["pipe","pipe","pipe"]});
  const messages=[];let buffer="";
  child.stdout.setEncoding("utf8");child.stdout.on("data",chunk=>{buffer+=chunk;let index;while((index=buffer.indexOf("\n"))>=0){messages.push(JSON.parse(buffer.slice(0,index)));buffer=buffer.slice(index+1);}});
  const exited=new Promise((resolve,reject)=>{child.on("error",reject);child.on("exit",code=>resolve(code));});
  async function until(predicate) {const end=Date.now()+10000;while(!predicate()){if(Date.now()>end)throw Error("IPC_TIMEOUT:"+JSON.stringify(messages));await new Promise(resolve=>setTimeout(resolve,25));}}
  const send=data=>child.stdin.write(JSON.stringify(Object.assign({sessionId:session},data))+"\n");
  try {
    await until(()=>messages.some(x=>x.type==="ready"));
    send({type:"incident",incidentId:"i-1",runId:"r-1",kind:"completed",workflow:"captions",panelVisible:false,hasWarnings:false,playSound:false,toast:false});
    await until(()=>messages.some(x=>x.type==="state"&&x.incidentId==="i-1"));
    send({type:"incident",incidentId:"i-2",runId:"r-2",kind:"failure",workflow:"edit",panelVisible:false,hasWarnings:false,playSound:false,toast:false});
    await until(()=>messages.some(x=>x.type==="state"&&x.incidentId==="i-2"));
    send({type:"clear",incidentId:"i-1",runId:"r-1"});
    send({type:"clear",incidentId:"i-2",runId:"r-2"});
    await until(()=>messages.some(x=>x.type==="state"&&x.toast==="cleared"));
    assert.strictEqual(messages.filter(x=>x.type==="state"&&x.toast==="cleared").length,1);
    assert(messages.every(x=>x.sessionId===session));child.stdin.end();
    assert.strictEqual(await exited,0);
  }finally{if(child.exitCode===null)child.kill();}
  const wrong=cp.spawnSync(executable,["--pipe","1",session],{windowsHide:true,timeout:10000});assert.strictEqual(wrong.status,3);
  console.log("NATIVE_NOTIFICATION_IPC_OK:real-binary;parent-binding;ready;run-replacement;stale-clear-rejected;EOF-exit;no-visible-UI");
}
run().catch(error=>{console.error(error);process.exitCode=1;});
