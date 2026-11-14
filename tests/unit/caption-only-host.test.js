"use strict";
const assert = require("assert");
const fs = require("fs");
const path = require("path");
const vm = require("vm");
const source = fs.readFileSync(path.join(__dirname, "../../extension/jsx/host.jsx"), "utf8");
function time(seconds) { return {seconds, ticks:String(seconds*254016000000)}; }
function clip(id,start,end,type) { return {nodeId:id,name:id,mediaType:type,start:time(start),end:time(end),inPoint:time(0),outPoint:time(end-start),getSpeed:()=>1}; }
let muteFault=null;
const muteCalls=[];
function track(clips,muted=false) { clips.numItems=clips.length; const value={clips,muted,isMuted:()=>value.muted,setMute(v){muteCalls.push([value,v]);if(muteFault&&muteFault(value,v)===false)return;value.muted=!!v;}};return value; }
const videos=[track([clip("v0",10,12,"Video"),clip("v1",20,22,"Video")])]; videos.numTracks=1;
const audios=[track([clip("a0",10,12,"Audio")]),track([clip("voice",10,22,"Audio")],true),track([clip("music",0,22,"Audio")],true)]; audios.numTracks=3;
const files={}; const exported=[];
let selected=[videos[0].clips[0],audios[0].clips[0],videos[0].clips[1]];
let inPoint=-400000,outPoint=-400000,failExport=false,importCount=0,captionCount=0;
const seq={sequenceID:"seq1",name:"Independent",timebase:254016000000/30,videoTracks:videos,audioTracks:audios,getSelection:()=>selected,getInPoint:()=>String(inPoint),getOutPoint:()=>String(outPoint),setInPoint:v=>{assert.equal(typeof v,"number");inPoint=v;},setOutPoint:v=>{assert.equal(typeof v,"number");outPoint=v;},exportAsMediaDirect:(p,preset,mode)=>{assert.deepEqual(audios.map(t=>t.muted),[true,false,true],"Only chosen voice may be audible during every export");if(failExport===true||failExport===p)throw Error("Mock export failed");files[p]={text:"",length:1000};exported.push([inPoint,outPoint,mode]);},createCaptionTrack:()=>{captionCount++;return true;}};
const children=[]; children.numItems=0;
const root={nodeId:"root",children,createBin:()=>{const items=[];items.numItems=0;const bin={nodeId:"temp",children:items,deleteBin:()=>{children.splice(children.indexOf(bin),1);children.numItems=children.length;return null;}};children.push(bin);children.numItems=children.length;return bin;}};
function File(p) { this.fsName=p;this.encoding="";Object.defineProperty(this,"exists",{get:()=>!!files[p]});Object.defineProperty(this,"length",{get:()=>files[p]?files[p].length:0});this.open=()=>true;this.close=()=>{};this.read=()=>files[p].text; }
const hostClock={now:100000};class HostDate extends Date {constructor(value){super(value===undefined?hostClock.now:value);}}
const context={Date:HostDate,$:{_PVS:{},sleep:()=>{}},File,Folder:{startup:{fsName:"C:/Premiere"}},Sequence:{CAPTION_FORMAT_SUBTITLE:0},ProjectItemType:{BIN:2},app:{project:{activeSequence:seq,rootItem:root,importFiles:(paths,skip,bin)=>{importCount++;bin.children.push({nodeId:"srt",getMediaPath:()=>paths[0]});bin.children.numItems=1;return true;}},encoder:{ENCODE_IN_TO_OUT:1}}};
vm.createContext(context);vm.runInContext(source,context);
const api=context.$._PVS;const parse=raw=>JSON.parse(raw);
let tokenCount=0,hostTurn=0,mutationTurn=-1;
const originalSetIn=seq.setInPoint,originalSetOut=seq.setOutPoint;
seq.setInPoint=v=>{mutationTurn=hostTurn;originalSetIn(v);};seq.setOutPoint=v=>{mutationTurn=hostTurn;originalSetOut(v);};
const mockNative=seq.exportAsMediaDirect;seq.exportAsMediaDirect=(...args)=>{assert(hostTurn>mutationTurn,"Native export must run in a later host call than In/Out mutation");return mockNative(...args);};
function hostCall(method,...args){hostTurn++;return parse(api[method](...args));}
function exportAudio(){const token="test-"+(++tokenCount);let r=hostCall("beginCaptionAudioExport","job.json","wave.epr",token);while(r.ok&&!r.done)r=hostCall("advanceCaptionAudioExport",token,r.nextCall);return JSON.stringify(r);}
let range=parse(api.scanCaptionRange());assert(range.ok);assert.equal(range.ranges.length,2);assert.equal(range.ranges[0].start,10);assert.equal(range.ranges[1].start,20);
assert.deepEqual(range.audioTracks.map(t=>[t.index,t.clipCount]),[[0,1],[1,1],[2,1]]);
selected=[];range=parse(api.scanCaptionRange());assert(range.ok);assert.equal(range.ranges.length,1);assert.equal(range.ranges[0].start,0);assert.equal(range.ranges[0].end,22);
const snapshot=range.snapshot;
const job={workflow:"caption-only",sequenceId:"seq1",snapshot,voiceTrackIndex:1,sources:[{start:10,end:12,path:"a.wav"},{start:20,end:22,path:"b.wav"}]};
files["job.json"]={text:JSON.stringify(job),length:10};files["wave.epr"]={length:10};
let result=parse(exportAudio());assert(result.ok);assert.deepEqual(exported,[[10,12,1],[20,22,1]]);assert.equal(inPoint,-400000);assert.equal(outPoint,-400000);assert.equal(api._captionOnlySnapshot(seq),snapshot);
assert.deepEqual(audios.map(t=>t.muted),[false,true,true]);assert.equal(result.voiceTrackIndex,1);
job.sources=[{start:10,end:12,path:"failed.wav"}];files["job.json"].text=JSON.stringify(job);inPoint=3;outPoint=7;failExport=true;
result=parse(exportAudio());assert(!result.ok);assert.equal(inPoint,3);assert.equal(outPoint,7);failExport=false;
files["captions.srt"]={length:10};files["result.json"]={text:JSON.stringify({ok:true,workflow:"caption-only",schemaVersion:1,sequenceId:"seq1",snapshot,captionSrtPath:"captions.srt",captionCueCount:5}),length:10};
result=parse(api.applyCaptionOnly("result.json"));assert(result.ok);assert.equal(captionCount,1);assert.equal(children.length,0);assert.equal(api._captionOnlySnapshot(seq),snapshot);
videos[0].clips[0].end=time(13);result=parse(api.applyCaptionOnly("result.json"));assert(!result.ok);assert.equal(importCount,1);assert.equal(captionCount,1);
videos[0].clips[0].end=time(12);seq.createCaptionTrack=()=>false;result=parse(api.applyCaptionOnly("result.json"));assert(!result.ok);assert(!result.captionCreated);assert.equal(children.length,0);assert.equal(api._captionOnlySnapshot(seq),snapshot);
function writeJob(overrides={}){const value=Object.assign({},job,{snapshot:api._captionOnlySnapshot(seq),sources:[{start:10,end:12,path:"case-"+Object.keys(files).length+".wav"}]},overrides);files["job.json"].text=JSON.stringify(value);return value;}
for(const voiceTrackIndex of [undefined,null,"1",-1,0.5,3]){
  writeJob({voiceTrackIndex});const count=muteCalls.length;result=parse(exportAudio());assert(!result.ok);assert.equal(muteCalls.length,count);
}
writeJob({sources:[{start:30,end:40,path:"outside.wav"}]});result=parse(exportAudio());assert(!result.ok);assert(result.error.includes("không có clip"));
const setMute=audios[2].setMute;delete audios[2].setMute;writeJob();let count=muteCalls.length;result=parse(exportAudio());assert(!result.ok);assert.equal(muteCalls.length,count);audios[2].setMute=setMute;
writeJob();muteFault=(t,v)=>t===audios[0]&&v===1?false:undefined;count=exported.length;result=parse(exportAudio());assert(!result.ok);assert.equal(exported.length,count);assert.deepEqual(audios.map(t=>t.muted),[false,true,true]);muteFault=null;
// A later setup failure still restores an earlier changed track.
audios[2].muted=false;writeJob();muteFault=(t,v)=>{if(t===audios[2]&&v===1)throw Error("SETUP_FAILED");};result=parse(exportAudio());assert(!result.ok);assert(result.error.includes("SETUP_FAILED"));assert.deepEqual(audios.map(t=>t.muted),[false,true,false]);muteFault=null;audios[2].muted=true;
// Export may fail after one of several disjoint ranges has already succeeded.
writeJob({sources:[{start:10,end:12,path:"first-ok.wav"},{start:20,end:22,path:"second-fail.wav"}]});failExport="second-fail.wav";result=parse(exportAudio());assert(!result.ok);assert(files["first-ok.wav"]);assert.deepEqual(audios.map(t=>t.muted),[false,true,true]);assert.equal(inPoint,3);assert.equal(outPoint,7);failExport=false;
// Restoration errors remain visible, retain the export error, and do not skip other tracks or In/Out.
writeJob();failExport=true;muteFault=(t,v)=>t===audios[0]&&v===0?false:undefined;result=parse(exportAudio());assert(!result.ok);assert(result.error.includes("Mock export failed"));assert(result.error.includes("mute track A1"));assert.deepEqual(audios.map(t=>t.muted),[true,true,true]);assert.equal(inPoint,3);assert.equal(outPoint,7);muteFault=null;failExport=false;audios[0].muted=false;
const setIn=seq.setInPoint;seq.setInPoint=v=>{if(v===3)throw Error("RESTORE_IN_FAILED");setIn(v);};writeJob();result=parse(exportAudio());assert(!result.ok);assert(result.error.includes("RESTORE_IN_FAILED"));assert.equal(outPoint,7);assert.deepEqual(audios.map(t=>t.muted),[false,true,true]);seq.setInPoint=setIn;inPoint=3;
writeJob({snapshot:"stale"});count=muteCalls.length;result=parse(exportAudio());assert(!result.ok);assert.equal(muteCalls.length,count);
// A transient read failure after unmuting voice must not prevent writing its saved mute state back.
const isMuted=audios[1].isMuted;let readFailed=false;audios[1].isMuted=()=>{if(!audios[1].muted&&!readFailed){readFailed=true;throw Error("MUTE_READ_FAILED");}return isMuted();};writeJob();result=parse(exportAudio());assert(!result.ok);assert(result.error.includes("MUTE_READ_FAILED"));assert.deepEqual(audios.map(t=>t.muted),[false,true,true]);audios[1].isMuted=isMuted;
console.log("CAPTION_ONLY_HOST_OK:selection,whole-sequence,voice-isolation,mixed-mute-restore,partial-setup-failure,second-range-failure,restore-failure,invalid-track,caption-cleanup,stale-timeline");
// Native failure can leave a large, incomplete WAV. It must never reach ASR.
const nativeExport=seq.exportAsMediaDirect;
for(const failure of [false,-1,"Error: -1","Export failed","Canceled"]){
  seq.exportAsMediaDirect=(p,preset,mode)=>{nativeExport(p,preset,mode);return failure;};
  const j=writeJob();result=parse(exportAudio());
  assert(files[j.sources[0].path].length>44);assert(!result.ok);assert.equal(result.exportFailurePhase,"native-export");
  assert(result.error.includes(String(failure)));assert.deepEqual(audios.map(t=>t.muted),[false,true,true]);assert.equal(inPoint,3);assert.equal(outPoint,7);
}
seq.exportAsMediaDirect=nativeExport;
for(const success of [true,0,"",undefined]){
  seq.exportAsMediaDirect=(p,preset,mode)=>{nativeExport(p,preset,mode);return success;};writeJob();result=parse(exportAudio());assert(result.ok);
}
seq.exportAsMediaDirect=nativeExport;
// Native export must not depend on optional AME constants.
delete context.app.encoder.ENCODE_IN_TO_OUT;writeJob();result=parse(exportAudio());assert(result.ok);assert.equal(exported.at(-1)[2],1);
// A rejected In/Out update must not accidentally export the whole sequence.
seq.setInPoint=v=>{if(v!==10)setIn(v);};writeJob();count=exported.length;result=parse(exportAudio());assert(!result.ok);assert.equal(result.exportFailurePhase,"range-setup");assert.equal(exported.length,count);assert.equal(inPoint,3);assert.equal(outPoint,7);seq.setInPoint=setIn;
for(const sources of [[{start:0,end:Infinity,path:"bad.wav"}],[{start:0,end:2,path:"ok.wav"},{start:2,end:1,path:"bad.wav"}]]){
  writeJob({sources});count=muteCalls.length;result=parse(exportAudio());assert(!result.ok);assert.equal(result.exportFailurePhase,"preflight");assert.equal(muteCalls.length,count);
}
console.log("CAPTION_EXPORT_GUARDS_OK:native-failure-with-partial-WAV,restore,explicit-In-Out-mode,rejected-range,all-ranges-preflight");
// Preparation must never start native encoding; other sessions/call numbers
// must not be able to repeat it or restore someone else's temporary state.
writeJob({sources:[{start:10,end:12,path:"split-first.wav"},{start:20,end:22,path:"split-second.wav"}]});
count=exported.length;result=hostCall("beginCaptionAudioExport","job.json","wave.epr","split");assert(result.ok);assert.equal(exported.length,count);assert.equal(inPoint,10);assert.deepEqual(audios.map(t=>t.muted),[true,false,true]);
result=hostCall("beginCaptionAudioExport","job.json","wave.epr","other");assert(!result.ok);assert.equal(api._captionAudioExport.token,"split");
result=hostCall("advanceCaptionAudioExport","other",0);assert(!result.ok);assert.equal(exported.length,count);
result=hostCall("abortCaptionAudioExport","other");assert(!result.found);assert.equal(api._captionAudioExport.token,"split");
result=hostCall("advanceCaptionAudioExport","split",0);assert(result.ok&&!result.done);assert.equal(exported.length,count+1);assert.equal(inPoint,20);
result=hostCall("advanceCaptionAudioExport","split",0);assert(!result.ok);assert.equal(exported.length,count+1);
result=hostCall("advanceCaptionAudioExport","split",1);assert(result.ok&&result.done);assert.equal(exported.length,count+2);assert.equal(inPoint,3);assert.equal(outPoint,7);assert.equal(api._captionAudioExport,null);
for(const change of [()=>{inPoint=9;},()=>{videos[0].clips[0].end=time(13);},()=>{context.app.project.activeSequence=null;}]){
  writeJob();result=hostCall("beginCaptionAudioExport","job.json","wave.epr","changed");assert(result.ok);count=exported.length;change();result=hostCall("advanceCaptionAudioExport","changed",0);assert(!result.ok&&result.done);assert(result.restored);assert.equal(result.exportFailurePhase,"between-calls");assert.equal(exported.length,count);assert.equal(inPoint,3);assert.equal(outPoint,7);assert.deepEqual(audios.map(t=>t.muted),[false,true,true]);videos[0].clips[0].end=time(12);context.app.project.activeSequence=seq;
}
writeJob();hostCall("beginCaptionAudioExport","job.json","wave.epr","abort");count=exported.length;result=hostCall("abortCaptionAudioExport","abort");assert(result.restored);assert.equal(exported.length,count);assert.equal(api._captionAudioExport,null);assert.equal(inPoint,3);assert.equal(outPoint,7);
writeJob();hostCall("beginCaptionAudioExport","job.json","wave.epr","old-panel");count=exported.length;result=hostCall("restorePendingCaptionAudioExport");assert(result.restored);assert.equal(exported.length,count);assert.equal(inPoint,3);assert.equal(outPoint,7);assert.equal(api._captionAudioExport,null);result=hostCall("restorePendingCaptionAudioExport");assert(result.ok&&!result.found);
console.log("CAPTION_EXPORT_SESSION_OK:no-native-in-prepare,later-host-turn,one-range-per-call,duplicate-and-owner-guards,timeline-and-In-Out-guard,abort-restores");
writeJob();const timedNative=seq.exportAsMediaDirect;seq.exportAsMediaDirect=(...args)=>{hostClock.now+=8000;return timedNative(...args);};result=parse(exportAudio());assert(result.ok);assert.equal(result.audioExportTiming.nativeMilliseconds,8000);assert.equal(result.audioExportTiming.hostMilliseconds,8000);assert.equal(result.audioExportTiming.finalizeMilliseconds,0);
writeJob();failExport=true;result=parse(exportAudio());assert(!result.ok);assert.equal(result.audioExportTiming.nativeMilliseconds,8000,"Thrown native errors must retain measured time");failExport=false;seq.exportAsMediaDirect=timedNative;
console.log("CAPTION_EXPORT_TIMING_OK:native-clock,host-clock,finalize-clock,throw-preserves-timing");
const reviewValues=[];
seq.markers={getFirstMarker:()=>reviewValues[0]||null,getNextMarker:m=>reviewValues[reviewValues.indexOf(m)+1]||null,deleteMarker:m=>reviewValues.splice(reviewValues.indexOf(m),1),createMarker:seconds=>{const m={start:{seconds},setColorByIndex:c=>{m.color=c;},getColorByIndex:()=>m.color};reviewValues.push(m);return m;}};
seq.createCaptionTrack=()=>true;
const reviewResult={ok:true,workflow:"caption-only",schemaVersion:1,sequenceId:"seq1",snapshot:api._captionOnlySnapshot(seq),captionSrtPath:"captions.srt",captionCueCount:5,reviewMarkers:[{start:10,end:11,reason:"number review"}],reviewMarkerRanges:[{start:10,end:12}]};
files["result.json"].text=JSON.stringify(reviewResult);
result=parse(api.applyCaptionOnly("result.json"));assert(result.ok);assert(result.captionCreated);assert.equal(result.reviewMarkerCount,1);assert.equal(reviewValues[0].start.seconds,10);assert(reviewValues[0].comments.includes("number review"));assert.equal(api._captionOnlySnapshot(seq),reviewResult.snapshot);
const panel=fs.readFileSync(path.join(__dirname,"../../extension/js/main.js"),"utf8"),projection=panel.slice(panel.indexOf("  function projectHostInput("),panel.indexOf("  function writeHostInput("));
const compactResult=vm.runInNewContext(projection+'projectHostInput(input,"captions");',{input:reviewResult});
const fullImport=result;reviewValues.length=0;files["result.json"].text=JSON.stringify(compactResult);
result=parse(api.applyCaptionOnly("result.json"));assert.deepStrictEqual(result,fullImport,"Caption snapshot, import, cleanup and markers are identical with compact input.");
delete seq.markers;result=parse(api.applyCaptionOnly("result.json"));assert(!result.ok);assert(result.captionCreated);assert.equal(result.reviewMarkerFailureCount,1);assert.equal(children.length,0);
console.log("CAPTION_REVIEW_MARKERS_OK:timeline-offset,media-preserved,cleanup,marker-failure-preserves-captionCreated");
