"use strict";
const assert=require("assert"),fs=require("fs"),path=require("path"),vm=require("vm");
const source=fs.readFileSync(path.join(__dirname,"../../extension/jsx/host.jsx"),"utf8");
const block=source.slice(source.indexOf('$._PVS._captionOnlySnapshot ='),source.indexOf('$._PVS.scanCaptionRange ='));
function fixture(){
  const clip={nodeId:"clip",disabled:false,projectItem:{nodeId:"source"},start:{ticks:"0"},end:{ticks:"100"},inPoint:{ticks:"0"},outPoint:{ticks:"100"},speed:1,getSpeed(){return this.speed;}};
  const clips=[clip];clips.numItems=1;
  const track={clips,muted:false,isMuted(){return this.muted;}};
  const video=[track];video.numTracks=1;const audio=[];audio.numTracks=0;
  const children=[{nodeId:"bin",name:"Fixture"}];children.numItems=1;
  const sequence={sequenceID:"seq",timebase:30,videoTracks:video,audioTracks:audio,captionTracks:{numTracks:1},inPoint:"0",outPoint:"100",getInPoint(){return this.inPoint;},getOutPoint(){return this.outPoint;}};
  const project={documentID:"doc",path:"fixture.prproj",activeSequence:sequence,rootItem:{children}};
  const context={$:{_PVS:{_result:JSON.stringify}},app:{project}};vm.runInNewContext(block,context);
  return {read:()=>JSON.parse(context.$._PVS.workflowPauseState()),clip,track,sequence,project,children};
}
const changes=[f=>f.project.documentID="other",f=>f.project.path="other.prproj",f=>f.sequence.sequenceID="other",f=>f.sequence.timebase=24,f=>f.sequence.inPoint="1",f=>f.sequence.outPoint="101",f=>f.clip.start.ticks="1",f=>f.clip.end.ticks="101",f=>f.clip.inPoint.ticks="1",f=>f.clip.outPoint.ticks="101",f=>f.clip.speed=1.1,f=>f.clip.nodeId="other",f=>f.clip.projectItem.nodeId="other",f=>f.track.muted=true,f=>f.sequence.captionTracks.numTracks=2,f=>f.children[0].name="Changed",f=>f.sequence.audioTracks.numTracks=1];
for(const change of changes){const f=fixture(),before=f.read();assert(before.ok);change(f);const after=f.read();assert(!after.ok||after.state!==before.state,"Relevant native change must invalidate resume");}
const f=fixture(),before=f.read();f.sequence.playhead=999;f.sequence.selection=["other"];assert.equal(f.read().state,before.state,"Playback/selection do not change captured edit input");
const disabled=fixture(),enabled=disabled.read();disabled.clip.disabled=true;assert.notEqual(disabled.read().state,enabled.state,"Clip enable changes must invalidate resume");
for(const value of [null,undefined,"",NaN,Infinity]){const f=fixture();f.sequence.inPoint=value;assert(!f.read().ok);}
const missing=fixture();missing.project.activeSequence=null;assert(!missing.read().ok);
const noCaptionApi=fixture();delete noCaptionApi.sequence.captionTracks;assert(noCaptionApi.read().ok,"Missing caption API is recorded as unavailable");
console.log("WORKFLOW_PAUSE_HOST_OK:real-helper;project-sequence;source-id;all-clip-edges;speed;mute;In-Out;caption-count;bins;read-errors;playhead-selection-excluded");
