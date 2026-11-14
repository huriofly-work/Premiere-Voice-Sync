"use strict";
const assert = require("assert"), fs = require("fs"), path = require("path"), vm = require("vm");
const root = path.join(__dirname, "../..");
const host = fs.readFileSync(path.join(root,"extension/jsx/host.jsx"),"utf8");
const diagnostic = fs.readFileSync(path.join(root,"extension/jsx/diagnostic-executor.jsx"),"utf8");
const { output } = require("../../tools/Build-DiagnosticExecutor.js");
assert.strictEqual(diagnostic,output().text,"Generated source must match stable executor exactly.");
const TPF = 8467200000;
function collection(items) { Object.defineProperty(items,"numItems",{get(){return this.length;}}); return items; }
function tracks(items) { Object.defineProperty(items,"numTracks",{get(){return this.length;}}); return items; }
function time(frame) { return { ticks:String(frame*TPF),seconds:frame/30 }; }
function fixture(count=65, noCaption=false, withGaps=false, voiceSpeed=1, merged=false, oldMarkers=false, trace=false) {
  let nextId=0;
  const actions=[],nativeRows=[];let qeReads=0;
  function markers(){
    const values=[];
    return {items:values,getFirstMarker(){return values[0]||null;},getNextMarker(m){return values[values.indexOf(m)+1]||null;},deleteMarker(m){values.splice(values.indexOf(m),1);actions.push(["deleteMarker"]);},createMarker(seconds){const m={start:{seconds},setColorByIndex(c){this.colorIndex=c;actions.push(["markerColor",c]);},getColorByIndex(){return this.colorIndex;}};values.push(m);actions.push(["marker",seconds]);return m;}};
  }
  const nested={nodeId:"nested",getMarkers:markers,clearInPoint(){actions.push(["clearIn"]);},clearOutPoint(){actions.push(["clearOut"]);}};
  const voice={nodeId:"voice",getMarkers:markers};
  nested.getMarkers=(()=>{const m=markers();return ()=>m;})();
  voice.getMarkers=(()=>{const m=markers();return ()=>m;})();
  if(oldMarkers){
    for(const item of [nested,voice])item.getMarkers().items.push(
      {name:"VOICE SYNC - Kiem tra toc do",comments:"Sentence cues 1-1: actual speed=140.000%, warning range=70-130%",start:{seconds:1}},
      {name:"VOICE SYNC - Kiem tra toc do",comments:"My manual note",start:{seconds:2}},
      {name:"VOICE SYNC - Da gop hinh",comments:"old merge\n[PremiereVoiceSync:owned-marker:v1]",start:{seconds:count*120/30+100}}
    );
  }
  const seq={sequenceID:"seq",timebase:TPF,markers:markers(),videoTracks:tracks([{clips:collection([])}]),audioTracks:tracks([{clips:collection([])},{clips:collection([])}])};
  function clip(name,track,start,end,sourceIn,sourceOut,projectItem){
    const item={name,nodeId:"clip"+(nextId++),start:time(start),end:time(end),inPoint:time(sourceIn),outPoint:time(sourceOut),projectItem,speed:1,
      getSpeed(){return this.speed;},getLinkedItems(){if(projectItem!==nested)return [];return seq.audioTracks[0].clips.filter(c=>c.projectItem===nested&&c.inPoint.ticks===this.inPoint.ticks&&c.outPoint.ticks===this.outPoint.ticks);},
      move(delta){actions.push(["move",this.nodeId,delta.ticks]);const frames=Number(delta.ticks)/TPF;this.start=time(Number(this.start.ticks)/TPF+frames);this.end=time(Number(this.end.ticks)/TPF+frames);},
      remove(ripple,align){assert.strictEqual(ripple,false);assert.strictEqual(align,false);actions.push(["remove",this.nodeId]);track.clips.splice(track.clips.indexOf(this),1);this.deleted=true;}
    };const id=item.nodeId;Object.defineProperty(item,"nodeId",{get(){if(this.deleted)throw Error("REMOVED_PROXY_MUST_NOT_BE_READ");return id;}});track.clips.push(item);return item;
  }
  const segments=[];let outputFrame=0,voiceFrame=0;
  for(let i=0;i<count;i++){
    const duration=i%3===0?100:i%3===1?150:120;
    segments.push({Kind:"retime",SourceDuration:4,SourceStart:i*4,SourceEnd:(i+1)*4,SourceStartFrame:i*120,SourceEndFrame:(i+1)*120,NewStart:outputFrame/30,NewEnd:(outputFrame+duration)/30,NewStartFrame:outputFrame,VisualDurationFrames:duration,OutputDurationFrames:duration,AppliedSpeedPercent:120/duration*100,OriginalVoiceStartFrame:voiceFrame,OriginalVoiceEndFrame:voiceFrame+duration,NewVoiceStartFrame:outputFrame,FirstTargetCue:i+1,LastTargetCue:i+1});
    outputFrame+=duration;voiceFrame+=duration+(withGaps && i<count-1 ? 6 : 0);
  }
  clip("Nest",seq.videoTracks[0],0,count*120,0,count*120,nested);
  clip("Nest",seq.audioTracks[0],0,count*120,0,count*120,nested);
  const originalVoice=clip("Voice",seq.audioTracks[1],0,voiceFrame,0,voiceFrame*voiceSpeed,voice);originalVoice.speed=voiceSpeed;
  // Preserved tail moves first and must remain identical across both paths.
  clip("End screen",seq.videoTracks[0],count*120,count*120+60,0,60,{nodeId:"end"});
  clip("Adjustment",Object.assign(seq.videoTracks[1]={clips:collection([])}),count*120,count*120+60,0,60,{nodeId:"adjustment"});
  function razor(track,frame){
    const item=track.clips.find(c=>Number(c.start.ticks)/TPF<frame&&Number(c.end.ticks)/TPF>frame);
    if(!item)return;
    const oldEnd=Number(item.end.ticks)/TPF,oldOut=Number(item.outPoint.ticks)/TPF;
    const sourceCut=Number(item.inPoint.ticks)/TPF+(frame-Number(item.start.ticks)/TPF)*item.speed;
    const other=clip(item.name,track,frame,oldEnd,sourceCut,oldOut,item.projectItem);other.speed=item.speed;
    item.end=time(frame);item.outPoint=time(sourceCut);track.clips.sort((a,b)=>Number(a.start.ticks)-Number(b.start.ticks));
  }
  function tcFrames(tc){const v=tc.split(":").map(Number);return ((v[0]*3600+v[1]*60+v[2])*30)+v[3];}
  function qeTrack(track,isVideo){return {get numItems(){return track.clips.length;},getItemAt(i){qeReads++;const c=track.clips[i];return {type:"Clip",get start(){return c.start;},setSpeed(factor,duration){if(seq.failSpeed)throw Error("NATIVE_SPEED_FAILED");actions.push(["speed",c.nodeId,factor,duration]);c.speed=factor;c.end=time(Number(c.start.ticks)/TPF+tcFrames(duration));return true;}};},razor(tc,linked){actions.push(["razor",isVideo?"V":"A",tc,linked]);const frame=tcFrames(tc);razor(track,frame);if(linked)razor(seq.audioTracks[0],frame);return true;}};}
  const rootItem={children:collection([]),nodeId:"root",createBin(){actions.push(["createBin"]);const bin={nodeId:"bin",children:collection([]),deleteBin(){actions.push(["deleteBin"]);rootItem.children.splice(rootItem.children.indexOf(bin),1);return true;}};rootItem.children.push(bin);return bin;}};
  seq.createCaptionTrack=function(){actions.push(["captionTrack"]);return true;};
  const project={activeSequence:seq,rootItem,openSequence(){actions.push(["openSequence"]);},importFiles(paths,a,bin){actions.push(["importCaption"]);bin.children.push({nodeId:"srt",getMediaPath(){return paths[0];}});return true;},save(){throw Error("MUST_NOT_SAVE");}};
  const plan={schemaVersion:8,sequenceId:"seq",frameRate:30,mainVideoSourceEnd:count*4,plannedMainVideoEnd:outputFrame/30,plannedMainVideoEndFrame:outputFrame,voiceTrackIndex:1,voiceClips:[{name:"Voice",end:voiceFrame/30}],linkedAudio:[{name:"Nest"}],segments,captionSrtPath:"fixture.srt",captions:segments.map(()=>({})),summary:{captionCueCount:count},speedWarningMinPercent:90,speedWarningMaxPercent:110,markers:[]};
  if(oldMarkers)plan.markers.push({Owner:"A2",SegmentIndex:0,Name:"VOICE SYNC - Kiem tra can voice",Comments:"Sentence cues 1-1 needs review",ColorIndex:1});
  if(merged){
    assert(!withGaps);
    plan.mainVideoSourceEndFrame=count*120;plan.speedMergeTrial="adjacent-speed-v2";plan.editBoundaryTrial="dtw-additive-v1";
    segments.forEach(s=>s.NewEndFrame=Math.round(s.NewEnd*30));
    plan.visualSegments=[];
    for(let i=0;i<count;i+=2){
      const first=segments[i],last=segments[Math.min(i+1,count-1)],sourceFrames=last.SourceEndFrame-first.SourceStartFrame,outFrames=last.NewEndFrame-first.NewStartFrame;
      plan.visualSegments.push(Object.assign({},first,{MemberSegmentIndices:i+1<count?[i,i+1]:[i],SourceEnd:last.SourceEnd,SourceEndFrame:last.SourceEndFrame,SourceDuration:sourceFrames/30,SourceDurationFrames:sourceFrames,EffectiveSourceDurationFrames:sourceFrames,NewEnd:last.NewEnd,NewEndFrame:last.NewEndFrame,VisualDurationFrames:outFrames,OutputDurationFrames:outFrames,AppliedSpeedPercent:100*sourceFrames/outFrames,LastTargetCue:last.LastTargetCue}));
    }
  }
  if(trace)plan.nativeProgressPath=trace==="external"?"/outside/native-progress.jsonl":"/fixture/native-progress.jsonl";
  const context=vm.createContext({$: {_PVS:{}},Sequence:{CAPTION_FORMAT_SUBTITLE:0},app:{project,enableQE(){actions.push(["enableQE"]);}},qe:{project:{getActiveSequence(){return {getVideoTrackAt(i){return qeTrack(seq.videoTracks[i],true);},getAudioTrackAt(i){return qeTrack(seq.audioTracks[i],false);}};}}},Time:function(){this.ticks="0";},File:function(file){this.exists=!noCaption;this.name=String(file).split("/").pop();this.parent={fsName:String(file).includes("/")?String(file).slice(0,String(file).lastIndexOf("/")):"/fixture"};this.open=()=>trace!=="denied";this.write=text=>nativeRows.push(JSON.parse(text));this.close=()=>{};}});
  vm.runInContext(host,context);vm.runInContext(diagnostic,context);
  vm.runInContext("$._PVS._readJsonFile=function(){return "+JSON.stringify(plan)+";};",context);
  context.$._PVS._findItemByMediaPath=(bin,p)=>bin.children.find(c=>c.getMediaPath()===p);
  return {context,actions,seq,plan,nested,voice,nativeRows,api:context.$._PVS,get qeReads(){return qeReads;}};
}
for(const profile of ["baseline","fast","no-delay"])for(const count of [1,6,65,130])for(const voiceSpeed of [0.9,1,1.1]){
  const stable=fixture(count,false,false,voiceSpeed,true,true),trial=fixture(count,false,false,voiceSpeed,true,true);
  const stableReport=JSON.parse(stable.api.executePlan("fixture")),result=finishTrial(trial,profile);
  assert(stableReport.ok,JSON.stringify(stableReport));assert(result.report.ok,JSON.stringify(result.report));
  assert.deepStrictEqual(result.report,stableReport);assert.deepStrictEqual(trial.actions,stable.actions);
  assert.strictEqual(result.report.clearedClipMarkerCount,2);
  assert.strictEqual(result.report.mergeClipMarkerCount,Math.floor(count/2));
  const markers=trial.nested.getMarkers().items;
  assert(markers.some(m=>m.comments==="My manual note"));
  assert(!markers.some(m=>m.start.seconds===1));
  assert(markers.some(m=>m.comments.startsWith("old merge")),"Out-of-scope source marker preserved.");
  for(const visual of trial.plan.visualSegments.filter(v=>v.MemberSegmentIndices.length===2)){
    const found=markers.filter(m=>m.start.seconds>visual.SourceStart&&m.start.seconds<visual.SourceEnd&&m.comments.includes("merged adjacent source segments"));
    assert.strictEqual(found.length,1,"Every merged group owns exactly one marker, even within thresholds.");
    assert(found[0].comments.includes("[PremiereVoiceSync:owned-marker:v1]"));
    assert.strictEqual(found[0].colorIndex,visual.AppliedSpeedPercent<90?3:visual.AppliedSpeedPercent>110?1:6);
  }
  assert.strictEqual(trial.voice.getMarkers().items.find(m=>m.name==="VOICE SYNC - Kiem tra can voice").colorIndex,4);
  assert.strictEqual(result.report.clipMarkerColorFailureCount,0);
  if(count===6)assert.strictEqual(result.report.speedWarningSentenceCount,1,"Merged markers are not all speed warnings.");
}
const colored=fixture(6,false,false,1,false,true),coloredResult=finishTrial(colored,"fast");
assert(coloredResult.report.ok);
assert(colored.nested.getMarkers().items.some(m=>m.colorIndex===1),"Fast speed uses red.");
assert(colored.nested.getMarkers().items.some(m=>m.colorIndex===3),"Slow speed uses orange.");
const failedColor=fixture(6,false,false,1,true,true);
const bank=failedColor.nested.getMarkers(),create=bank.createMarker;
bank.createMarker=function(seconds){const m=create.call(this,seconds);m.setColorByIndex=function(){throw Error("NATIVE_COLOR_FAILED");};return m;};
const colorReport=finishTrial(failedColor,"fast").report;
assert(colorReport.ok,"Cosmetic color failure must not invalidate an otherwise correct timeline.");
assert.strictEqual(colorReport.clipMarkerColorFailureCount,3);assert.strictEqual(colorReport.mergeClipMarkerCount,3);
function finishTrial(f,profile){
  const api=f.api;let r=JSON.parse(api.beginDiagnosticEdit("fixture","token",profile));assert(r.ok);
  const checkpoints=[];let calls=0;
  do {r=JSON.parse(api.advanceDiagnosticEdit("token",r.nextCall));calls++;if(r.checkpoint)checkpoints.push(r.checkpoint);assert(calls<500); }while(!r.done);
  assert.strictEqual(JSON.parse(api.diagnosticInfo()).active,false);
  return {report:r.result,checkpoints,calls,timings:r.timings};
}
for(const profile of [undefined,"baseline","fast","no-delay"])for(const [count,gaps,voiceSpeed] of [[1,false,1],[6,false,1],[65,false,1],[65,true,1],[65,true,1.1],[65,true,0.9],[130,true,1.1]]){
  const stable=fixture(count,false,gaps,voiceSpeed),trial=fixture(count,false,gaps,voiceSpeed);
  const stableReport=JSON.parse(stable.api.executePlan("fixture"));
  const result=finishTrial(trial,profile);
  assert(stableReport.ok,JSON.stringify(stableReport));assert(result.report.ok,JSON.stringify(result.report));
  assert.deepStrictEqual(result.report,stableReport,"Scheduling must preserve full postcheck report.");
  assert.deepStrictEqual(trial.actions,stable.actions,"Every native editing call must stay identical and in order.");
  assert.deepStrictEqual(result.checkpoints,["Hình V1–A1","Voice A2","Marker","Caption"]);
  if(count>=65)assert(result.timings.some(t=>!t.complete),"Every profile, including no-delay, bounds native batches.");
  for(const timing of result.timings)for(const field of ["checkMs","rebindMs","workMs","snapshotMs","qeLookupMs","qeQueries","qeHits","qeBuilds","qeFallbacks","qeCacheReuses","qeCountChanges","qeCandidateMisses","qeInvalidLayouts","qeItemReads","qeEarlyHits","qeNearestScans"])assert(timing[field]>=0,field);
  if((profile==="fast" || profile==="no-delay") && count>=65)assert(trial.qeReads<stable.qeReads,"Fast exact-start lookup must reduce native QE reads without changing edits.");
  if(profile==="fast" || profile==="no-delay"){
    assert.strictEqual(result.timings.reduce((sum,t)=>sum+t.qeBuilds,0),0,"Count changes must not trigger full QE index builds.");
    assert.strictEqual(result.timings.reduce((sum,t)=>sum+t.qeItemReads,0),trial.qeReads,"Native QE reads must be measurable.");
    assert.strictEqual(result.timings.reduce((sum,t)=>sum+t.qeEarlyHits,0),result.timings.reduce((sum,t)=>sum+t.qeQueries,0),"Exact-start fixtures must use fresh first-exact lookup.");
    assert(result.timings.every(t=>t.snapshotDetailReads>=0));
    assert(result.timings.some(t=>t.snapshotStrategy==="incremental-speed"));
    assert(result.timings.some(t=>t.snapshotStrategy==="read-only"));
    assert(result.timings.filter(t=>t.stage.includes("Cắt")||t.stage.includes("Dồn")||t.stage.includes("caption")||t.stage.includes("hậu kiểm")).every(t=>t.snapshotStrategy==="full"),"Structural, move, caption and audit stages must keep full post-scan.");
  }
}
for(const profile of ["baseline","fast","no-delay"]){
  for(const mutate of [f=>f.seq.videoTracks[0].clips[0].end=time(9999),f=>f.seq.videoTracks[0].clips[0].inPoint=time(1),f=>f.seq.audioTracks[1].clips[0].speed=1.1]){
    const guarded=fixture();guarded.api.beginDiagnosticEdit("fixture","token",profile);
    mutate(guarded);const result=JSON.parse(guarded.api.advanceDiagnosticEdit("token",0));
    assert.strictEqual(result.result.error,"DIAGNOSTIC_TIMELINE_CHANGED_BETWEEN_BATCHES");assert.strictEqual(guarded.actions.length,0);
  }
}
const invalid=fixture();assert.strictEqual(JSON.parse(invalid.api.beginDiagnosticEdit("fixture","token","invalid")).error,"DIAGNOSTIC_PROFILE_INVALID");assert.strictEqual(invalid.actions.length,0);
for(const profile of ["fast","no-delay"]){
  const stalled=fixture(1),root=stalled.context.app.project.rootItem,create=root.createBin;let sleeps=0;
  stalled.context.$.sleep=function(ms){assert.strictEqual(ms,50);sleeps++;};
  root.createBin=function(){const bin=create.call(root);bin.deleteBin=function(){return true;};return bin;};
  const report=finishTrial(stalled,profile).report;
  assert(!report.ok,"No-delay must still report a temporary caption bin that could not be removed.");
  assert(report.error.includes("Temporary caption cleanup failed"));
  assert.strictEqual(sleeps,profile==="no-delay"?0:5,"Only the trial bypasses caption cleanup waits.");
}
// Corrupt an untouched clip AFTER an incremental speed batch: the next full
// before-batch guard still stops before another editing call is made.
for(const field of ["inPoint","speed"]){
  const guarded=fixture(130);let r=JSON.parse(guarded.api.beginDiagnosticEdit("fixture","token","fast"));
  do{r=JSON.parse(guarded.api.advanceDiagnosticEdit("token",r.nextCall));assert(r.ok&&!r.done);}while(r.stage!=="Tăng speed V1–A1");
  const voice=guarded.seq.audioTracks[1].clips[0];if(field==="inPoint")voice.inPoint=time(1);else voice.speed=1.1;
  const prior=guarded.actions.length;r=JSON.parse(guarded.api.advanceDiagnosticEdit("token",r.nextCall));assert.strictEqual(r.result.error,"DIAGNOSTIC_TIMELINE_CHANGED_BETWEEN_BATCHES");assert.strictEqual(guarded.actions.length,prior);
}
let f=fixture();
assert(JSON.parse(f.api.beginDiagnosticEdit("fixture","token")).ok);
assert.strictEqual(JSON.parse(f.api.beginDiagnosticEdit("fixture","second")).error,"DIAGNOSTIC_SESSION_ACTIVE");
assert.strictEqual(JSON.parse(f.api.advanceDiagnosticEdit("wrong",0)).error,"DIAGNOSTIC_SESSION_NOT_FOUND");
assert.strictEqual(JSON.parse(f.api.advanceDiagnosticEdit("token",1)).error,"DIAGNOSTIC_CALL_ORDER");assert.strictEqual(f.actions.length,0);
let response=JSON.parse(f.api.advanceDiagnosticEdit("token",0));assert(response.ok);
const before=f.actions.length;
assert.strictEqual(JSON.parse(f.api.advanceDiagnosticEdit("token",0)).error,"DIAGNOSTIC_CALL_ORDER");assert.strictEqual(f.actions.length,before);
f.seq.videoTracks[0].clips[0].end=time(9999);
response=JSON.parse(f.api.advanceDiagnosticEdit("token",1));assert(response.done);assert.strictEqual(response.result.error,"DIAGNOSTIC_TIMELINE_CHANGED_BETWEEN_BATCHES");assert.strictEqual(f.actions.length,before);
f=fixture();f.api.beginDiagnosticEdit("fixture","token");f.seq.sequenceID="other";
response=JSON.parse(f.api.advanceDiagnosticEdit("token",0));assert.strictEqual(response.result.error,"DIAGNOSTIC_SEQUENCE_CHANGED");assert.strictEqual(f.actions.length,0);
f=fixture();f.api.beginDiagnosticEdit("fixture","token");response=JSON.parse(f.api.abortDiagnosticEdit("token"));assert.strictEqual(response.result.timelineMutated,false);assert.strictEqual(f.actions.length,0);assert.strictEqual(JSON.parse(f.api.diagnosticInfo()).active,false);
f=fixture();response=JSON.parse(f.api.beginDiagnosticEdit("fixture","token"));do{response=JSON.parse(f.api.advanceDiagnosticEdit("token",response.nextCall));}while(!response.timelineMutated&&!response.done);assert(response.timelineMutated);const partialActions=f.actions.length;
response=JSON.parse(f.api.abortDiagnosticEdit("token"));assert.strictEqual(response.result.timelineMutated,true);assert.strictEqual(f.actions.length,partialActions);
f=fixture(6,true);const failed=finishTrial(f);assert.strictEqual(failed.report.ok,false);assert.strictEqual(failed.report.captionCreated,false);
assert(!/save\(|clearHistory\(|app\.undo|executeCommand/.test(diagnostic));
for(const profile of ["baseline","fast","no-delay"]){
  const stable=fixture(6),staged=fixture(6);
  for(const value of [stable,staged]){
    value.plan.reviewMarkers=[{start:0,end:1,reason:"caption DTW review"}];
    vm.runInContext("$._PVS._readJsonFile=function(){return "+JSON.stringify(value.plan)+";};",value.context);
  }
  const report=JSON.parse(stable.api.executePlan("fixture")),trial=finishTrial(staged,profile);
  assert(report.ok,JSON.stringify(report));assert.equal(report.reviewMarkerCount,1);assert.equal(report.sequenceMarkerCount,1);
  assert.deepStrictEqual(trial.report,report);assert.deepStrictEqual(staged.actions,stable.actions);
  assert(staged.seq.markers.items[0].comments.includes("caption DTW review"));
}
f=fixture(6);f.plan.reviewMarkers=[{start:0,end:1,reason:"review"}];delete f.seq.markers;
vm.runInContext("$._PVS._readJsonFile=function(){return "+JSON.stringify(f.plan)+";};",f.context);
const markerFailure=finishTrial(f,"no-delay").report;assert(!markerFailure.ok);assert(markerFailure.captionCreated);assert.equal(markerFailure.reviewMarkerFailureCount,1);
f=fixture(1);f.seq.videoTracks[0].clips[0].getLinkedItems=()=>[];
const badLink=JSON.parse(f.api.executePlan("fixture"));assert(!badLink.ok);assert.equal(badLink.linkMismatchCount,1);assert.equal(badLink.reviewMarkerCount,1);assert(f.seq.markers.items[0].comments.includes("link could not be verified"));assert.equal(f.seq.markers.items[0].colorIndex,1);
for(const profile of ["baseline","fast","no-delay"]){
  f=fixture(1);f.seq.failSpeed=true;
  const nativeFailure=finishTrial(f,profile).report;
  assert(!nativeFailure.ok);assert.equal(nativeFailure.error,"NATIVE_SPEED_FAILED");assert.equal(nativeFailure.reviewMarkerCount,1);assert.equal(f.seq.markers.items[0].start.seconds,0);assert.equal(f.seq.markers.items[0].colorIndex,1);assert(f.seq.markers.items[0].comments.includes("partially built"));
}
function editedFixture(oneVoiceGroup=false, outside=false) {
  const f=fixture(3),p=f.plan;
  p.mainVideoClip={start:0,end:28};p.mainVideoSourceEndFrame=360;
  p.segments.forEach(s=>s.NewEndFrame=Math.round(s.NewEnd*30));
  const pairs=f.seq.videoTracks[0].clips.concat(f.seq.audioTracks[0].clips).filter(c=>c.name==="Nest");
  pairs.forEach(c=>{c.end=time(840);c.outPoint=time(840);});
  pairs.forEach(c=>{for(const key of ["name","projectItem"]){const value=c[key];Object.defineProperty(c,key,{get(){if(this.deleted)throw Error("DELETED_MAIN_PROXY_READ:"+key);return value;}});}});
  for(const t of f.seq.videoTracks)for(const c of t.clips)if(c.name!=="Nest"){c.start=time(840);c.end=time(900);}
  const kept=outside?[[120,240,0,120],[360,480,120,240],[600,720,240,360]]:[[0,120,0,120],[360,480,120,240],[720,840,240,360]];
  const omitted=outside?[[0,120],[240,360],[480,600],[720,840]]:[[120,360],[480,720]];
  p.editedSourceMap={revision:"srt-omissions-v1",physicalStartFrame:0,physicalEndFrame:840,planStartFrame:0,planEndFrame:360,
    kept:kept.map(([a,b,c,d])=>({SourceStartFrame:a,SourceEndFrame:b,PlanStartFrame:c,PlanEndFrame:d})),
    omissions:omitted.map(([a,b],i)=>({SourceStartFrame:a,SourceEndFrame:b,CueIndices:[i+2],Reason:"join-rerecognized-with-retained-anchors"}))};
  if(oneVoiceGroup){
    const total=p.plannedMainVideoEndFrame;
    p.segments=[Object.assign({},p.segments[0],{SourceEnd:12,SourceEndFrame:360,SourceDuration:12,SourceDurationFrames:360,
      EffectiveSourceDurationFrames:360,NewEnd:total/30,NewEndFrame:total,OutputDurationFrames:total,VisualDurationFrames:total,
      AppliedSpeedPercent:360/total*100,OriginalVoiceEndFrame:total,LastTargetCue:7})];
  }
  vm.runInContext("$._PVS._readJsonFile=function(){return "+JSON.stringify(p)+";};",f.context);
  return f;
}
for(const oneGroup of [false,true])for(const outside of [false,true])for(const profile of ["baseline","fast","no-delay"]){
  const stable=editedFixture(oneGroup,outside),staged=editedFixture(oneGroup,outside);
  const direct=JSON.parse(stable.api.executePlan("fixture")),actual=finishTrial(staged,profile).report;
  assert(direct.ok,JSON.stringify(direct));assert(actual.ok,JSON.stringify(actual));
  assert.deepStrictEqual(actual,direct);assert.deepStrictEqual(staged.actions,stable.actions);
  assert.strictEqual(staged.actions.filter(a=>a[0]==="remove").length,outside?8:4,"Only the omitted V1/A1 pairs are removed.");
  const kept=staged.seq.videoTracks[0].clips.filter(c=>c.name==="Nest");
  assert.deepStrictEqual(kept.map(c=>Number(c.inPoint.ticks)/TPF),outside?[120,360,600]:[0,360,720]);
  assert.strictEqual(staged.seq.audioTracks[1].clips.length,oneGroup?1:3,"Picture omissions must not force new voice cuts.");
  assert.strictEqual(staged.seq.audioTracks[1].clips.reduce((n,c)=>n+Number(c.outPoint.ticks)-Number(c.inPoint.ticks),0),staged.plan.plannedMainVideoEndFrame*TPF);
}
for(const mutate of [p=>p.editedSourceMap.omissions[0].Reason="guess",p=>p.editedSourceMap.kept[1].SourceStartFrame++,p=>p.editedSourceMap.kept[1].PlanStartFrame++,p=>p.editedSourceMap.physicalEndFrame++,p=>p.editedSourceMap.omissions.pop()]){
  f=editedFixture();mutate(f.plan);vm.runInContext("$._PVS._readJsonFile=function(){return "+JSON.stringify(f.plan)+";};",f.context);
  const rejected=JSON.parse(f.api.executePlan("fixture"));assert(!rejected.ok);assert(!rejected.timelineMutated);assert.strictEqual(f.actions.length,0);
}
// Cancel immediately before the first deletion batch: the prior razors remain
// reviewable; cancellation must never proceed to removal, save or undo.
f=editedFixture();response=JSON.parse(f.api.beginDiagnosticEdit("fixture","token","baseline"));
do{response=JSON.parse(f.api.advanceDiagnosticEdit("token",response.nextCall));}while(!response.done && !response.nextStage.startsWith("Bỏ hình"));
assert(!response.done);const beforeCancel=f.actions.length;
JSON.parse(f.api.abortDiagnosticEdit("token"));assert.strictEqual(f.actions.length,beforeCancel);assert(!f.actions.some(a=>a[0]==="remove"));
for(const failAudio of [false,true]){
  f=editedFixture();response=JSON.parse(f.api.beginDiagnosticEdit("fixture","token","fast"));
  do{response=JSON.parse(f.api.advanceDiagnosticEdit("token",response.nextCall));}while(!response.done && !response.nextStage.startsWith("Bỏ hình"));
  const track=failAudio?f.seq.audioTracks[0]:f.seq.videoTracks[0];
  const removed=track.clips.find(c=>Number(c.start.ticks)/TPF===480);
  removed.remove=function(){throw Error("NATIVE_OMISSION_REMOVE_FAILED");};
  response=JSON.parse(f.api.advanceDiagnosticEdit("token",response.nextCall));
  assert(response.done);assert(!response.result.ok);assert(response.result.timelineMutated);
  assert.strictEqual(response.result.error,"NATIVE_OMISSION_REMOVE_FAILED");assert.strictEqual(response.result.reviewMarkerCount,1);
  assert(!f.actions.some(a=>a[0]==="speed"),"A failed removal must stop later editing");
}
console.log("EDITED_EXECUTOR_MOCK_OK:multi-cut;head,tail;linked-pair-removal;voice-preserved;all-profiles;bad-map-before-mutation;cancel-before-removal");
// Picture-only SRT cue cuts must not create cuts or lost frames on A2.
function cueFixture(count=6,withGaps=false){
  const f=fixture(count,false,withGaps,1,false,false),p=f.plan;
  p.pictureCueRevision="srt-cue-picture-v1";p.pictureCueBoundaries=[];p.pictureSegments=[];
  p.segments.forEach((s,i)=>{
    s.Chapter=0;s.NewEndFrame=Math.round(s.NewEnd*30);
    s.NewVoiceEndFrame=s.NewEndFrame;
    s.SourceDurationFrames=s.SourceEndFrame-s.SourceStartFrame;
    s.EffectiveSourceDurationFrames=s.SourceDurationFrames;
    s.OutputDuration=s.OutputDurationFrames/30;
    const middle=s.NewStartFrame+Math.floor(s.OutputDurationFrames*.4),sourceMiddle=s.SourceStartFrame+60;
    p.pictureCueBoundaries.push({ParentSegmentIndex:i,SourceFrame:sourceMiddle,OutputFrame:middle,VoiceFrame:s.OriginalVoiceStartFrame+middle-s.NewStartFrame,Chapter:0,LeftCue:2*i+1,RightCue:2*i+2});
    for(const [a,b,c,d] of [[s.SourceStartFrame,sourceMiddle,s.NewStartFrame,middle],[sourceMiddle,s.SourceEndFrame,middle,s.NewEndFrame]]){
      p.pictureSegments.push(Object.assign({},s,{ParentSegmentIndex:i,SourceStartFrame:a,SourceEndFrame:b,NewStartFrame:c,NewEndFrame:d,SourceStart:a/30,SourceEnd:b/30,NewStart:c/30,NewEnd:d/30,SourceDuration:(b-a)/30,SourceDurationFrames:b-a,EffectiveSourceDurationFrames:b-a,OutputDuration:(d-c)/30,OutputDurationFrames:d-c,VisualDurationFrames:d-c,AppliedSpeedPercent:(b-a)/(d-c)*100}));
    }
  });
  vm.runInContext("$._PVS._readJsonFile=function(){return "+JSON.stringify(p)+";};",f.context);
  return f;
}
for(const profile of ["baseline","fast","no-delay"])for(const count of [1,6,65])for(const gaps of [false,true]){
  const direct=cueFixture(count,gaps),staged=cueFixture(count,gaps);
  const a=JSON.parse(direct.api.executePlan("fixture")),b=finishTrial(staged,profile).report;
  assert(a.ok,JSON.stringify(a));assert(b.ok,JSON.stringify(b));assert.deepStrictEqual(a,b);assert.deepStrictEqual(direct.actions,staged.actions);
  assert.strictEqual(b.pictureCueCount,count*2);
  assert.strictEqual(staged.seq.videoTracks[0].clips.filter(c=>c.name==="Nest").length,count*2);
  assert.strictEqual(staged.seq.audioTracks[0].clips.length,count*2);
  assert.strictEqual(staged.seq.audioTracks[1].clips.length,count,"Continuous voice is not split at picture-only cue boundaries.");
  assert.strictEqual(staged.seq.audioTracks[1].clips.reduce((n,c)=>n+Number(c.outPoint.ticks)-Number(c.inPoint.ticks),0),staged.plan.plannedMainVideoEndFrame*TPF);
  assert.strictEqual(staged.nested.getMarkers().items.length,0,"Successful exact per-cue retime needs no speed review marker.");
  assert.strictEqual(staged.voice.getMarkers().items.length,0);
}
for(const mutate of [p=>p.pictureCueRevision="unknown",p=>p.pictureSegments[0].SourceEndFrame++,p=>p.pictureSegments[0].NewEndFrame++,p=>p.pictureSegments[0].AppliedSpeedPercent++,p=>p.pictureSegments[0].NewEnd+=.1,p=>p.pictureCueBoundaries[0].VoiceFrame++,p=>p.pictureCueBoundaries[0].Chapter++,p=>p.pictureCueBoundaries[0].RightCue++,p=>p.pictureCueBoundaries.pop(),p=>p.pictureSegments.pop(),p=>p.editedSourceMap={}]){
  for(const staged of [false,true]){
    const f=cueFixture();mutate(f.plan);vm.runInContext("$._PVS._readJsonFile=function(){return "+JSON.stringify(f.plan)+";};",f.context);
    const rejected=staged?finishTrial(f,"fast").report:JSON.parse(f.api.executePlan("fixture"));
    assert(!rejected.ok);assert(!rejected.timelineMutated);assert.strictEqual(f.actions.length,0);
  }
}
{
  const api=cueFixture().api,plan={pictureCueRevision:"srt-cue-picture-v1"};
  assert(!api._shouldMarkSpeed(plan,150,150,150,true,false));
  assert(api._shouldMarkSpeed(plan,100,101,100,false,false));
  assert(api._shouldMarkSpeed(plan,100,null,100,false,false));
  assert(api._shouldMarkSpeed({},150,150,150,true,false),"Legacy speed warning policy remains intact.");
}
console.log("CUE_PICTURE_EXECUTOR_OK:per-cue-v1-a1;continuous-a2;all-profiles;exact-parity;native-speed-errors-still-marked;invalid-plan-before-mutation");
// Compact input is the same native plan with offline evidence kept in Node.
const panelSource=fs.readFileSync(path.join(root,"extension/js/main.js"),"utf8");
const projectSource=panelSource.slice(panelSource.indexOf("  function projectHostInput("),panelSource.indexOf("  function writeHostInput("));
function projected(f){const compact=vm.runInNewContext(projectSource+'projectHostInput(input,"edit");',{input:f.plan});vm.runInContext("$._PVS._readJsonFile=function(){return "+JSON.stringify(compact)+";};",f.context);return f;}
for(const make of [()=>fixture(65,false,true),()=>fixture(6,false,false,1,true),()=>cueFixture(6),()=>editedFixture(true,true)]){
  const full=make(),compact=make(),staged=make();
  for(const f of [full,compact,staged]){f.plan.acousticEditBoundaryProofs=[{WordTimings:[{Text:"private",Exact:true}]}];}
  const expected=JSON.parse(full.api.executePlan("fixture")),actual=JSON.parse(projected(compact).api.executePlan("fixture")),batch=finishTrial(projected(staged),"no-delay").report;
  assert(expected.ok,JSON.stringify(expected));assert.deepStrictEqual(actual,expected);assert.deepStrictEqual(batch,expected);
  assert.deepStrictEqual(compact.actions,full.actions);assert.deepStrictEqual(staged.actions,full.actions);
}
for(const profile of ["baseline","fast","no-delay"]){
  const f=fixture(65);let r=JSON.parse(f.api.beginDiagnosticEdit("fixture","sparse-speed",profile));
  do {
    const previous=f.actions.filter(a=>a[0]==="speed").length;
    r=JSON.parse(f.api.advanceDiagnosticEdit("sparse-speed",r.nextCall));
    const added=f.actions.filter(a=>a[0]==="speed").length-previous;
    assert(added<=8,"Skipped entries cannot consume or enlarge the four linked-pair work allowance.");
  }while(!r.done);
  assert(r.result.ok);
  const speedBatches=r.timings.filter(t=>t.stage==="Tăng speed V1–A1"||t.stage==="Giảm speed V1–A1");
  assert(speedBatches.length<Math.ceil(65/4)*2,"Opposite-speed/unchanged entries must not force four-entry empty batches.");
}
{
  const f=fixture(65);let r=JSON.parse(f.api.beginDiagnosticEdit("fixture","bounded","no-delay"));
  while(!r.done&&r.nextStage!=="Tăng speed V1–A1")r=JSON.parse(f.api.advanceDiagnosticEdit("bounded",r.nextCall));
  assert(!r.done);r=JSON.parse(f.api.advanceDiagnosticEdit("bounded",r.nextCall));
  assert(!r.done&&r.nextStage==="Tăng speed V1–A1","No-delay must return control within a long speed loop.");
  assert(f.actions.filter(a=>a[0]==="speed").length<=8,"At most four linked pairs in one native call.");
  const count=f.actions.length;JSON.parse(f.api.abortDiagnosticEdit("bounded"));assert.equal(f.actions.length,count,"Cancel at a pair boundary adds no native editing.");
}
for(const mode of [true,"denied","external"]){
 const direct=fixture(6,false,false,1,false,false,mode),staged=fixture(6,false,false,1,false,false,mode);
 const a=JSON.parse(direct.api.executePlan("fixture")),b=finishTrial(staged,"no-delay").report;
 assert(a.ok&&b.ok);assert.deepStrictEqual(a,b);assert.deepStrictEqual(staged.actions,direct.actions);
 if(mode===true){
  const trim=r=>r.filter(row=>row.operation!=="snapshot").map(({operation,phase})=>({operation,phase}));assert.deepStrictEqual(trim(direct.nativeRows),trim(staged.nativeRows));
  for(const rows of [direct.nativeRows,staged.nativeRows])rows.forEach((r,i)=>assert.equal(r.serial,i+1));
  assert(staged.nativeRows.some(r=>r.operation==="snapshot"),"Staged state reads also expose entered/completed progress.");
  assert(direct.nativeRows.some(r=>r.operation==="set-speed"&&r.phase==="before"));assert(direct.nativeRows.some(r=>r.operation==="set-speed"&&r.phase==="after"));
 }else assert.equal(direct.nativeRows.length,0,"Unavailable/outside-job trace must not write or abort editing.");
}
{
 const f=fixture(6,false,false,1,false,false,true);f.seq.failSpeed=true;const r=finishTrial(f,"no-delay").report;
 assert(!r.ok);const last=f.nativeRows[f.nativeRows.length-1];assert.equal(last.operation,"set-speed");assert.equal(last.phase,"before","Failed native call leaves its last entered operation visible.");
}
{
 const f=fixture(6,false,false,1,false,false,true);const r=JSON.parse(f.api.executePlan("timeline-executor.json"));assert(r.ok);
 assert.equal(f.nativeRows[0].operation,"read-plan");assert.equal(f.nativeRows[0].phase,"before");assert.equal(f.nativeRows[1].phase,"after");
}
console.log("BOUNDED_NATIVE_EXECUTOR_OK:full-compact-call-and-report-parity;no-delay-four-pair-cap;cancel-between-pairs;native-progress;trace-failure-and-external-path-safe");
// Marker lifecycle on the actual executor, including no-delay safe boundaries.
function sourceMarkerState(f,item){return item.getMarkers().items.map(m=>[m.start.seconds,m.name,m.comments]);}
for(const profile of ["baseline","fast","no-delay"]){
  f=fixture(6,false,false,1,false,true);const oldNested=sourceMarkerState(f,f.nested),oldVoice=sourceMarkerState(f,f.voice);
  f.seq.failSpeed=true;const failed=finishTrial(f,profile).report;assert(!failed.ok);
  assert.deepStrictEqual(sourceMarkerState(f,f.nested),oldNested);assert.deepStrictEqual(sourceMarkerState(f,f.voice),oldVoice,"Native failure before marker commit preserves old warnings.");
  assert(!f.actions.some(a=>a[0]==="deleteMarker"));

  f=fixture(6,false,false,1,false,true);const beforeVoice=sourceMarkerState(f,f.voice),beforeNested=sourceMarkerState(f,f.nested);
  response=JSON.parse(f.api.beginDiagnosticEdit("fixture","token",profile));
  do{response=JSON.parse(f.api.advanceDiagnosticEdit("token",response.nextCall));assert(!response.done);}while(response.nextStage!=="Cập nhật marker nguồn");
  assert.deepStrictEqual(sourceMarkerState(f,f.nested),beforeNested);assert.deepStrictEqual(sourceMarkerState(f,f.voice),beforeVoice);
  response=JSON.parse(f.api.advanceDiagnosticEdit("token",response.nextCall));assert(!response.done);assert.equal(response.nextStage,"Cập nhật marker nguồn");
  assert.notDeepStrictEqual(sourceMarkerState(f,f.nested),beforeNested);assert.deepStrictEqual(sourceMarkerState(f,f.voice),beforeVoice);
  const committed=sourceMarkerState(f,f.nested),actions=f.actions.length;
  JSON.parse(f.api.abortDiagnosticEdit("token"));assert.equal(f.actions.length,actions);assert.deepStrictEqual(sourceMarkerState(f,f.nested),committed);assert.deepStrictEqual(sourceMarkerState(f,f.voice),beforeVoice);

  // A user modification between preparation and commit is not overwritten.
  f=fixture(6,false,false,1,false,true);response=JSON.parse(f.api.beginDiagnosticEdit("fixture","token",profile));
  do{response=JSON.parse(f.api.advanceDiagnosticEdit("token",response.nextCall));assert(!response.done);}while(response.nextStage!=="Cập nhật marker nguồn");
  f.nested.getMarkers().items[0].comments="user changed while paused";
  const manualState=sourceMarkerState(f,f.nested);
  while(!response.done)response=JSON.parse(f.api.advanceDiagnosticEdit("token",response.nextCall));
  assert(!response.result.ok);assert(response.result.clipMarkerFailures.some(x=>x.includes("changed since preparation")));assert.deepStrictEqual(sourceMarkerState(f,f.nested),manualState);
}
console.log("MARKER_EXECUTOR_LIFECYCLE_OK:all-profiles;native-failure-preserves-old;plan-without-write;cancel-between-owners;marker-change-guard");
console.log("DIAGNOSTIC_EXECUTOR_MOCK_OK:exact-native-call-parity;exact-report-parity;bounded-batches;four-checkpoints;duplicate-call-guard;timeline-and-sequence-guard;abort-no-new-edit;no-save-or-Undo-clear;generated-source-current;review-markers-all-profiles;marker-failure-reports-partial-result");
