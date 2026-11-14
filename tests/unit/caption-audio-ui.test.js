"use strict";
const assert=require("assert"),fs=require("fs"),path=require("path"),vm=require("vm");
const model=require("../../extension/js/caption-input.js");
const source=fs.readFileSync(path.join(__dirname,"../../extension/js/main.js"),"utf8");
const controls={};
function element(){return {value:"",children:[],textContent:"",handlers:{},set innerHTML(v){this.children=[];},appendChild(child){this.children.push(child);},addEventListener(name,fn){this.handlers[name]=fn;},setAttribute(){},querySelectorAll(){return this.children.flatMap(label=>label.children.filter(child=>child.type==="checkbox"));}};}
let range;
const context={require:n=>({fs:{},path:path.win32,child_process:{}}[n]),window:{PvsSecurity:{},PvsCaptionInput:model},localStorage:{getItem:()=>null},document:{getElementById:id=>controls[id]||(controls[id]=element()),createElement:element,addEventListener(){}},fixture:{read:()=>range}};
vm.runInNewContext(source.replace('  document.addEventListener("DOMContentLoaded", wire);',`evalHost=async function(){return fixture.read();};window.api={scan:scanCaptionRange,state:state,busy:setWorkflowBusy,tracks:setCaptionTracks,mode:function(sourceMode,scopeMode){if(sourceMode)state.captionConfig.sourceMode=sourceMode;if(scopeMode)state.captionConfig.scopeMode=scopeMode;renderCaptionVoiceTracks(state.captionRange);}};`),context);
const api=context.window.api, copy=value=>JSON.parse(JSON.stringify(value));
function input(id,counts){return {ok:true,inputVersion:1,projectId:"p",sequenceId:id,name:"Sequence",frameRate:30,sequenceEnd:10,selectionRanges:[{start:2,end:4}],selectedAudio:[],inOut:{start:1,end:8,valid:true},audioTracks:counts.map((count,index)=>({index,key:"id:"+index,clipCount:count,name:"Track "+(index+1),muted:false,clips:Array.from({length:count},(_,n)=>({nodeId:index+":"+n,start:0,end:10,disabled:false}))})),snapshot:"original"};}
(async()=>{
  range=input("one",[1,1,1]);await api.scan();assert.deepEqual(copy(api.state.captionPlan.trackIndices),[1]);assert(controls.captionSummary.textContent.includes("Theo thời gian clip"));
  api.tracks([2]);assert(controls.captionSummary.textContent.includes("A3"));await api.scan();assert.deepEqual(copy(api.state.captionPlan.trackIndices),[2]);
  range=input("one",[1,1,0]);await api.scan();assert(!api.state.captionPlan);assert.deepEqual(copy(api.state.captionConfig.trackIndices),[2],"never replace explicit empty track with A2");
  range=input("one",[1,1]);await api.scan();assert(!api.state.captionPlan);assert(api.state.captionPlanError.message.includes("thay đổi"));
  range=input("other",[1,0,1]);await api.scan();assert.deepEqual(copy(api.state.captionPlan.trackIndices),[0]);
  range=input("third",[0,0,1]);await api.scan();assert.deepEqual(copy(api.state.captionPlan.trackIndices),[2]);
  api.tracks([2]);range=input("other",[1,0,1]);await api.scan();assert.equal(api.state.captionConfig.trackIndices,null);
  api.tracks([0,2]);assert.deepEqual(copy(api.state.captionPlan.trackIndices),[0,2]);
  api.tracks([]);await api.scan();assert(!api.state.captionPlan);assert.deepEqual(copy(api.state.captionConfig.trackIndices),[],"unchecked-all stays empty");
  api.tracks([2]);api.mode("mix","selection");assert(controls.captionVoiceTrack.disabled);assert(!controls.captionScopeMode.disabled);assert.deepEqual(copy(api.state.captionPlan.ranges),[{start:2,end:4}]);
  range.selectedAudio=[{trackIndex:2,nodeId:"2:0"}];await api.scan();api.mode("clips");assert(controls.captionScopeMode.disabled);assert.equal(controls.captionScopeMode.value,"clips");assert.deepEqual(copy(api.state.captionPlan.trackIndices),[2]);
  api.mode("tracks");assert(!controls.captionVoiceTrack.disabled);assert.equal(controls.captionScopeMode.value,"selection");assert.deepEqual(copy(api.state.captionConfig.trackIndices),[2]);
  api.busy(true);for(const id of ["captionSourceMode","captionScopeMode","captionVoiceTrack"])assert(controls[id].disabled);api.busy(false);assert(!controls.captionVoiceTrack.disabled);
  range=input("all-empty",[0,0,0]);await api.scan();assert(!api.state.captionPlan);range=input("all-empty",[0,1,0]);await api.scan();assert.deepEqual(copy(api.state.captionPlan.trackIndices),[1]);
  range.audioTracks[1].clips[0].start=5;api.mode(null,"selection");assert(!api.state.captionPlan,"default must overlap scope");
  range=input("one",[1,1,1]);await api.scan();api.tracks([0,2]);const boxes=controls.captionTrackList.querySelectorAll("input");boxes[0].checked=false;boxes[0].handlers.change.call(boxes[0]);assert.deepEqual(copy(api.state.captionConfig.trackIndices),[2]);
  range=input("auto-clips",[1,1,1]);range.selectedAudio=[{trackIndex:2,nodeId:"2:0"}];await api.scan();
  assert.equal(api.state.captionConfig.sourceMode,"auto");assert.equal(api.state.captionPlan.input.sourceMode,"clips");
  assert.deepEqual(copy(api.state.captionPlan.trackIndices),[2],'selected audio overrides A2 in automatic mode');
  assert(controls.captionTrackPicker.hidden && controls.captionScopeControl.hidden);
  range.selectedAudio=[{trackIndex:0,nodeId:"0:0"}];await api.scan();assert.deepEqual(copy(api.state.captionPlan.trackIndices),[0],'refresh uses current selection');
  api.tracks([1]);range.selectedAudio=[{trackIndex:2,nodeId:"2:0"}];await api.scan();assert.deepEqual(copy(api.state.captionPlan.trackIndices),[1],'manual source is never overwritten by new selection');
  api.mode("auto");range.audioTracks[2].clips[0].disabled=true;await api.scan();assert(!api.state.captionPlan,'disabled-only selection must not fall back to unrelated audio');
  range.selectedAudio=[];range.selectionRanges=[];await api.scan();assert.equal(api.state.captionPlan.input.scopeMode,"whole");assert.deepEqual(copy(api.state.captionPlan.trackIndices),[1]);
  range.selectedAudio=[{trackIndex:2,nodeId:"gone"}];await api.scan();assert(!api.state.captionPlan,'unverified selection must fail closed');
  console.log("CAPTION_AUDIO_UI_OK:three-sources;explicit-scopes;multi-track-checkbox;A2-fallback;manual-empty-retained;unchecked-all;topology-guard;per-sequence;busy;summary");
})().catch(e=>{console.error(e);process.exitCode=1;});
