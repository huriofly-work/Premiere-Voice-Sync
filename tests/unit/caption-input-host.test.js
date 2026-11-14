"use strict";
const assert=require("assert"),fs=require("fs"),path=require("path"),vm=require("vm");
const modelSource=fs.readFileSync(path.join(__dirname,"../../extension/js/caption-input.js"),"utf8"),hostSource=fs.readFileSync(path.join(__dirname,"../../extension/jsx/host.jsx"),"utf8");
function fixture(options={}){
  const files={"wave.epr":"preset"},writes=[],renders=[];let selection=[],turn=0,mutationTurn=-1,fail=null;
  const time=v=>({seconds:v,ticks:String(v*254016000000)});
  function clip(id,start,end,disabled=false){let value=disabled;const c={nodeId:id,name:id,mediaType:"Audio",projectItem:{nodeId:"source-"+id},start:time(start),end:time(end),inPoint:time(0),outPoint:time(end-start),getSpeed:()=>1};Object.defineProperty(c,"disabled",{get(){if(options.unreadable===id)return undefined;return value;},set(v){writes.push(["disabled",id,v]);mutationTurn=turn;if(fail)fail("clip",id,v);if(options.ignoreDisable!==id)value=v;}});return c;}
  const a=clip("original",0,40),b=clip("chosen",10,20),other=clip("unselected-overlap",12,16),off=clip("disabled",10,20,true),c=clip("other-track",10,20);
  function track(id,clips,muted){clips.numItems=clips.length;const t={id,name:id,clips,muted,isMuted(){return t.muted;},setMute(v){writes.push(["mute",id,v]);mutationTurn=turn;if(fail)fail("mute",id,!!v);t.muted=!!v;}};return t;}
  const audio=[track("A1",[a],false),track("A2",[b,other,off],true),track("A3",[c],false)];audio.numTracks=3;
  const video=[];video.numTracks=0;
  const seq={sequenceID:"seq",name:"fixture",timebase:254016000000/(options.fps||30),audioTracks:audio,videoTracks:video,inPoint:-400000,outPoint:-400000,getSelection:()=>selection,getInPoint(){return this.inPoint;},getOutPoint(){return this.outPoint;},setInPoint(v){mutationTurn=turn;this.inPoint=v;},setOutPoint(v){mutationTurn=turn;this.outPoint=v;},exportAsMediaDirect(p){assert(turn>mutationTurn,"export runs after setup returns");const record=audio.flatMap(t=>t.muted?[]:t.clips.filter(c=>!c.disabled&&c.start.seconds<seq.outPoint&&c.end.seconds>seq.inPoint).map(c=>c.nodeId));renders.push(record);if(options.nativeFailure)throw Error("NATIVE_FAILED");files[p]="w".repeat(100);return true;}};
  function File(p){this.fsName=p;this.encoding="";Object.defineProperty(this,"exists",{get:()=>Object.hasOwn(files,p)});Object.defineProperty(this,"length",{get:()=>files[p]?.length||0});this.open=mode=>{if(mode==="w"){if(options.journalWriteFail)return false;files[p]="";}return true;};this.close=()=>true;this.read=()=>files[p];this.write=text=>{files[p]=text;return true;};this.remove=()=>{delete files[p];return true;};}
  const project={documentID:"project",activeSequence:seq};
  const context={$:{_PVS:{}},File,Folder:{startup:{fsName:"fixture"}},app:{project}};
  if(options.crossRuntime)context.JSON={parse:JSON.parse,stringify:value=>JSON.stringify(value,(key,value)=>typeof value==="number"?Number(value.toPrecision(15)):value)};
  vm.createContext(context);vm.runInContext(modelSource,context);vm.runInContext(hostSource,context);
  const api=context.$._PVS,model=options.crossRuntime?require("../../extension/js/caption-input.js"):context.PvsCaptionInput,read=()=>JSON.parse(api.scanCaptionRange());
  function call(name,...args){turn++;return JSON.parse(api[name](...args));}
  function job(config){const scan=read();assert(scan.ok);const plan=model.resolve(scan,config);const job={workflow:"caption-only",projectId:scan.projectId,sequenceId:scan.sequenceId,snapshot:scan.snapshot,audioInput:plan.input,audioInputKey:plan.key,sources:plan.ranges.map((r,i)=>({...r,path:"audio-"+i+".wav"}))};files["job.json"]=JSON.stringify(job);return job;}
  function run(){let r=call("beginCaptionAudioExport","job.json","wave.epr","token");while(r.ok&&!r.done)r=call("advanceCaptionAudioExport","token",r.nextCall);return r;}
  return {api,model,seq,project,files,writes,renders,read,job,run,call,select:clips=>selection=clips,clips:{a,b,other,off,c},fault:fn=>fail=fn};
}
for(const mode of ["mix","tracks","clips"]){
  const f=fixture();f.select([f.clips.b]);const before=f.read().snapshot;
  const config=mode==="tracks"?{sourceMode:mode,trackIndices:[1,2],topology:f.model.topology(f.read())}:{sourceMode:mode};
  f.job(config);const r=f.run();assert(r.ok,r.error);assert.equal(f.read().snapshot,before);assert(!f.files["job.json.audio-recovery.json"]);assert.equal(f.seq.inPoint,-400000);assert.equal(f.seq.outPoint,-400000);
  assert.deepEqual(f.renders,mode==="mix"?[["original","other-track"]]:mode==="tracks"?[["chosen","unselected-overlap","other-track"]]:[["chosen"]]);
  if(mode==="mix")assert(!f.writes.length,"mix never changes mute/disabled");
}
{
  const f=fixture();f.select([f.clips.b,f.clips.c]);f.job({sourceMode:"clips"});f.select([f.clips.a]);assert(f.run().ok);assert.deepEqual(f.renders,[["chosen","other-track"]],"later selection cannot change frozen clip input");
}
for(const options of [{ignoreDisable:"unselected-overlap"},{nativeFailure:true},{journalWriteFail:true},{unreadable:"unselected-overlap"}]){
  const f=fixture(options);f.select([f.clips.b]);const before=f.read().snapshot;
  if(options.unreadable){assert.throws(()=>f.job({sourceMode:"clips"}),/enable/);continue;}
  f.job({sourceMode:"clips"});const r=f.run();assert(!r.ok);assert.equal(f.read().snapshot,before,r.error);assert(!f.files["job.json.audio-recovery.json"]);
  if(!options.nativeFailure)assert(!f.renders.length,"preflight/isolation failure cannot render");
}
{
  const f=fixture();f.select([f.clips.b]);const before=f.read().snapshot;f.job({sourceMode:"clips"});
  const r=f.call("beginCaptionAudioExport","job.json","wave.epr","token");assert(r.ok);assert(f.files["job.json.audio-recovery.json"]);assert(f.clips.other.disabled);
  f.api._captionAudioExport=null;const recovered=f.call("restorePendingCaptionAudioExport","job.json.audio-recovery.json");assert(recovered.ok,recovered.error);assert.equal(f.read().snapshot,before);assert(!f.files["job.json.audio-recovery.json"]);
}
{
  const f=fixture();f.select([f.clips.b]);f.job({sourceMode:"clips"});assert(f.call("beginCaptionAudioExport","job.json","wave.epr","token").ok);f.api._captionAudioExport=null;f.project.documentID="different";const count=f.writes.length;const r=f.call("restorePendingCaptionAudioExport","job.json.audio-recovery.json");assert(!r.ok);assert.equal(f.writes.length,count);assert(f.files["job.json.audio-recovery.json"]);
}
{
  const f=fixture({nativeFailure:true});f.select([f.clips.b]);const before=f.read().snapshot;f.job({sourceMode:"clips"});f.fault((kind,id,value)=>{if(kind==="clip"&&id==="unselected-overlap"&&!value)throw Error("RESTORE_FAILED");});const r=f.run();assert(!r.ok&&!r.restored);assert(r.error.includes("NATIVE_FAILED")&&r.error.includes("RESTORE_FAILED"));assert(f.files["job.json.audio-recovery.json"]);assert.equal(f.seq.inPoint,-400000);assert.equal(f.seq.outPoint,-400000);assert.deepEqual(f.seq.audioTracks.map(t=>t.muted),[false,true,false]);f.fault(null);assert(f.call("restorePendingCaptionAudioExport","job.json.audio-recovery.json").ok);assert.equal(f.read().snapshot,before);
}
{
  const f=fixture();f.select([f.clips.b]);const before=f.read().snapshot;f.job({sourceMode:"clips"});assert(f.call("beginCaptionAudioExport","job.json","wave.epr","token").ok);const r=f.call("abortCaptionAudioExport","token");assert(r.restored);assert.equal(f.read().snapshot,before);assert(!f.renders.length);
}
for(const change of [f=>f.project.documentID="other",f=>f.clips.b.end.seconds=21,f=>f.seq.audioTracks[1].id="changed"]){const f=fixture();f.select([f.clips.b]);f.job({sourceMode:"clips"});change(f);assert(!f.run().ok);assert(!f.writes.length);assert(!f.renders.length);}
{
  const f=fixture();f.select([f.clips.b]);f.job({sourceMode:"tracks",scopeMode:"selection"});f.select([f.clips.a]);assert(f.run().ok);assert.deepEqual(f.renders,[["chosen","unselected-overlap"]],"selection time is frozen just like clip identity");
}
{
  const f=fixture();f.select([f.clips.b]);f.job({sourceMode:"clips"});assert(f.call("beginCaptionAudioExport","job.json","wave.epr","token").ok);f.api._captionAudioExport=null;const record=JSON.parse(f.files["job.json.audio-recovery.json"]);record.clips={};f.files["job.json.audio-recovery.json"]=JSON.stringify(record);const count=f.writes.length;assert(!f.call("restorePendingCaptionAudioExport","job.json.audio-recovery.json").ok);assert.equal(f.writes.length,count,"malformed recovery record must not write state");
}
for(const fps of [30,30000/1001,24000/1001])for(const sourceMode of ["mix","tracks","clips"]){
  const f=fixture({fps,crossRuntime:true});f.clips.a.end.seconds=40+1/fps;f.select([f.clips.b]);f.job({sourceMode});const before=f.read().snapshot;const result=f.run();
  assert(result.ok,"separate CEP/host number serialization: "+fps+"/"+sourceMode+": "+result.error);
  assert.equal(f.read().snapshot,before);
}
for(const mutate of [job=>{job.sources[0].end+=1/30;},job=>{const key=JSON.parse(job.audioInputKey);key.input.trackIndices=[0];job.audioInputKey=JSON.stringify(key);}]){
  const f=fixture({crossRuntime:true});const job=f.job({sourceMode:"tracks"});mutate(job);f.files["job.json"]=JSON.stringify(job);
  assert(!f.run().ok);assert(!f.writes.length);assert(!f.renders.length);
}
console.log("CAPTION_INPUT_HOST_OK:real-resolver-job-host;mix-no-mutation;multi-track-mix;exact-clip-isolation;disabled-preserved;selection-frozen;staged-export;fail-closed;durable-recovery;identity-guard;partial-restoration;cancel;cross-runtime-numbers");
