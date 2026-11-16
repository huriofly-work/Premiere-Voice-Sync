"use strict";
const assert = require("assert"), fs = require("fs"), path = require("path"), vm = require("vm");
const root = path.join(__dirname, "../..");
const host = fs.readFileSync(path.join(root,"extension/jsx/host.jsx"),"utf8");
const diagnostic = fs.readFileSync(path.join(root,"extension/jsx/diagnostic-executor.jsx"),"utf8");
let fixtureExecutor = diagnostic;
const { output } = require("../../tools/Build-DiagnosticExecutor.js");
assert.strictEqual(diagnostic,output().text,"Generated source must match stable executor exactly.");
const TPF = 8467200000;
// Run explicitly before the legacy assertions to capture the pre-fix failure.
{
  const f=fixture(1),clip=f.seq.videoTracks[0].clips[0];
  // Extract the real production planner, without running timeline mutations.
  const begin=host.indexOf("    function readSpeedPercent(item)"),end=host.indexOf("    try {\n        noteNative(\"before\", \"read-plan\")",begin);
  vm.runInContext(host.slice(begin,end),f.context);
  clip.start=time(300);clip.end=time(360);clip.inPoint=time(600);clip.outPoint=time(660);clip.speed=1.45;
  f.context.item=clip;
  vm.runInContext('var groups={};prepareClipMarkerGroup({Item:item,Ranges:[{start:29,end:31.9}]},groups,30);planOwnedClipMarker(item,{Name:"VOICE SYNC - Kiem tra toc do",Comments:"145%",ColorIndex:1},30,groups);var committed=$._PVS._markerTools.commit(groups[projectItemKey(item)]);',f.context);
  assert.equal(f.context.committed.count,1,"145% marker must land inside real source range");
  const m=f.nested.getMarkers().items[0];assert(Math.abs(m.start.seconds-29)<1e-7);assert(Math.abs(Number(m.end)-31.9)<1e-7);
  console.log("SPEED_REAL_SOURCE_RANGE_OK:145%");if(process.argv.includes("--voice-marker-regression"))process.exit(0);
}
function collection(items) { Object.defineProperty(items,"numItems",{get(){return this.length;}}); return items; }
function tracks(items) { Object.defineProperty(items,"numTracks",{get(){return this.length;}}); return items; }
function time(frame) { return { ticks:String(frame*TPF),seconds:frame/30 }; }
function fixture(count=65, noCaption=false, withGaps=false, voiceSpeed=1, merged=false, oldMarkers=false, trace=false, observe=false) {
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
  const originalVoice=clip("Voice",seq.audioTracks[1],0,voiceFrame,0,voiceFrame,voice);originalVoice.speed=voiceSpeed;
  // Preserved tail moves first and must remain identical across both paths.
  clip("End screen",seq.videoTracks[0],count*120,count*120+60,0,60,{nodeId:"end"});
  clip("Adjustment",Object.assign(seq.videoTracks[1]={clips:collection([])}),count*120,count*120+60,0,60,{nodeId:"adjustment"});
  function razor(track,frame){
    const item=track.clips.find(c=>Number(c.start.ticks)/TPF<frame&&Number(c.end.ticks)/TPF>frame);
    if(!item)return;
    const oldEnd=Number(item.end.ticks)/TPF,oldOut=Number(item.outPoint.ticks)/TPF;
    const sourceCut=Number(item.inPoint.ticks)/TPF+(frame-Number(item.start.ticks)/TPF);
    const other=clip(item.name,track,frame,oldEnd,sourceCut,oldOut,item.projectItem);other.speed=item.speed;
    item.end=time(frame);item.outPoint=time(sourceCut);track.clips.sort((a,b)=>Number(a.start.ticks)-Number(b.start.ticks));
  }
  function tcFrames(tc){const v=tc.split(":").map(Number);return ((v[0]*3600+v[1]*60+v[2])*30)+v[3];}
  function qeTrack(track,isVideo){return {get numItems(){return track.clips.length;},getItemAt(i){qeReads++;const c=track.clips[i];return {type:"Clip",get start(){return c.start;},setSpeed(factor,duration){if(seq.failSpeed)throw Error("NATIVE_SPEED_FAILED");actions.push(["speed",c.nodeId,factor,duration]);const oldSpeed=c.speed;c.inPoint=time(Number(c.inPoint.ticks)/TPF*oldSpeed/factor);c.outPoint=time(Number(c.outPoint.ticks)/TPF*oldSpeed/factor);c.speed=factor;c.end=time(Number(c.start.ticks)/TPF+tcFrames(duration));return true;}};},razor(tc,linked){actions.push(["razor",isVideo?"V":"A",tc,linked]);const frame=tcFrames(tc);razor(track,frame);if(linked)razor(seq.audioTracks[0],frame);return true;}};}
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
  // Observe native surfaces without adding property reads to their expressions.
  const nativeCalls=[],nativeMutations=[],methodNames=new WeakMap(),proxies=new WeakMap(),rawByProxy=new WeakMap(),ids=new WeakMap();let nextNativeId=0;
  const mutationMethods=new Set(["move","remove","setSpeed","razor","createMarker","deleteMarker","setColorByIndex","createCaptionTrack","importFiles","createBin","deleteBin","clearInPoint","clearOutPoint","openSequence"]);
  function mutationValue(value){
    value=rawByProxy.get(value)||value;
    if(Array.isArray(value))return value.map(mutationValue);
    if(value&&typeof value==="object"){
      if("nodeId" in value)return {nodeId:value.nodeId};
      if("ticks" in value)return {ticks:value.ticks};
      if("seconds" in value)return {seconds:value.seconds};
      if("start" in value)return {start:mutationValue(value.start),name:value.name,comments:value.comments};
    }
    return describe(value);
  }
  function describe(value){
    if(value!==null&&(typeof value==="object"||typeof value==="function")){
      if(!ids.has(value))ids.set(value,++nextNativeId);
      return {ref:ids.get(value)};
    }
    return typeof value==="string"?value.replace(/PVS_TEMP_CAPTION_\d+/g,"PVS_TEMP_CAPTION_TIME"):value;
  }
  function native(value){
    if(!observe||value===null||(typeof value!=="object"&&typeof value!=="function"))return value;
    if(proxies.has(value))return proxies.get(value);
    const id=describe(value).ref;
    const proxy=new Proxy(value,{
      get(target,key){nativeCalls.push(["get",id,String(key)]);const value=Reflect.get(target,key,target);if(typeof value==="function")methodNames.set(value,String(key));return native(value);},
      set(target,key,value){nativeCalls.push(["set",id,String(key),describe(value)]);nativeMutations.push(["set",target.nodeId||null,String(key),mutationValue(value)]);return Reflect.set(target,key,rawByProxy.get(value)||value,target);},
      apply(target,receiver,args){nativeCalls.push(["call",id,args.map(describe)]);const name=methodNames.get(target);if(mutationMethods.has(name))nativeMutations.push(["call",name,args.map(mutationValue)]);return native(Reflect.apply(target,rawByProxy.get(receiver)||receiver,args.map(v=>rawByProxy.get(v)||v)));}
    });
    proxies.set(value,proxy);rawByProxy.set(proxy,value);ids.set(proxy,id);return proxy;
  }
  const context=vm.createContext({$: {_PVS:{}},Sequence:{CAPTION_FORMAT_SUBTITLE:0},app:native({project,enableQE(){actions.push(["enableQE"]);}}),qe:native({project:{getActiveSequence(){return {getVideoTrackAt(i){return qeTrack(seq.videoTracks[i],true);},getAudioTrackAt(i){return qeTrack(seq.audioTracks[i],false);}};}}}),Time:function(){this.ticks="0";},File:function(file){this.exists=!noCaption;this.name=String(file).split("/").pop();this.parent={fsName:String(file).includes("/")?String(file).slice(0,String(file).lastIndexOf("/")):"/fixture"};this.open=()=>trace!=="denied";this.write=text=>nativeRows.push(JSON.parse(text));this.close=()=>{};}});
  vm.runInContext(host,context);vm.runInContext(fixtureExecutor,context);
  vm.runInContext("$._PVS._readJsonFile=function(){return "+JSON.stringify(plan)+";};",context);
  context.$._PVS._findItemByMediaPath=(bin,p)=>bin.children.find(c=>c.getMediaPath()===p);
  return {context,actions,seq,plan,nested,voice,nativeRows,nativeCalls,nativeMutations,api:context.$._PVS,get qeReads(){return qeReads;}};
}
function nativeDigests(executor){
  const digests={},previous=fixtureExecutor;fixtureExecutor=executor;
  try{
    for(const gaps of [false,true])for(const profile of ["direct","baseline","fast","no-delay"]){
      const f=fixture(6,false,gaps,1,!gaps,true,false,true);
      const result=profile==="direct"?JSON.parse(f.api.executePlan("fixture")):finishTrial(f,profile).report;
      assert(result.ok,JSON.stringify(result));
      digests[profile+":"+gaps]={rows:f.nativeCalls.length,sha256:require("crypto").createHash("sha256").update(JSON.stringify(f.nativeCalls)).digest("hex")};
    }
  }finally{fixtureExecutor=previous;}
  return digests;
}
// Trace counters must add no native reads, writes or calls. Compare against the
// same executor generated without counters in this Node runtime: proxy traps
// also see engine-internal reads (for example during sort), so frozen hashes
// differ between Node versions.
const measuredDigests=nativeDigests(diagnostic),unmeasuredDigests=nativeDigests(output({measure:false}).text);
assert.deepStrictEqual(measuredDigests,unmeasuredDigests);
assert.notStrictEqual(output({measure:false}).text,diagnostic,"unmeasured build must differ from the measured executor");
if(process.argv.includes("--timeline-native-digests")){console.log(JSON.stringify(measuredDigests));process.exit(0);}
// Ignore read-only guards/lookups, but retain every observed native property
// write and mutating call with its arguments, alongside clip-specific actions.
for(const [count,gaps,voiceSpeed,merged] of [[6,false,1,true],[65,false,1,false],[65,true,1.1,false],[130,true,0.9,false]]){
  const baseline=fixture(count,false,gaps,voiceSpeed,merged,true,false,true),noDelay=fixture(count,false,gaps,voiceSpeed,merged,true,false,true);
  const expected=finishTrial(baseline,"baseline"),actual=finishTrial(noDelay,"no-delay");
  assert(expected.report.ok&&actual.report.ok);
  assert.deepStrictEqual(JSON.parse(JSON.stringify(noDelay.nativeMutations)),JSON.parse(JSON.stringify(baseline.nativeMutations)),"No-delay native set/call mutations and arguments must equal baseline in order.");
  assert(noDelay.nativeMutations.some(row=>row[0]==="set")&&noDelay.nativeMutations.some(row=>row[0]==="call"));
  assert.deepStrictEqual(noDelay.actions,baseline.actions);
  assert.deepStrictEqual(actual.report,expected.report);
  const stages=actual.timings.filter(t=>t.stage!=="Cập nhật marker nguồn");
  assert(stages.every(t=>t.complete),"No-delay must complete every loop stage in one host call, except marker owners.");
  for(const label of ["Đọc marker nguồn","Cắt V1–A1 linked","Bỏ hình–A1 theo SRT đã lược","Tăng speed V1–A1","Dồn vị trí V1–A1","Giảm speed V1–A1","Đối chiếu mép V1–A1","Cắt voice A2","Bỏ lát khoảng lặng A2","Dồn voice A2","Chuẩn bị marker voice","Chuẩn bị marker tốc độ"])assert.equal(stages.filter(t=>t.stage===label).length,1,label);
}
console.log("NO_DELAY_STAGE_PARITY_OK:one-call-per-loop;native-set-call-mutations-equal-baseline;marker-owner-boundary-preserved");
// Freeze time to isolate iteration caps, then advance it beyond every budget
// to prove that only baseline/fast yield on elapsed time.
for(const profile of ["baseline","fast","no-delay"])for(const clock of ["frozen","elapsed"]){
  const f=fixture(130);vm.runInContext('var clockTicks=0;Date.prototype.getTime=function(){return '+(clock==="frozen"?'0':'(clockTicks+=1000)')+';};',f.context);
  let r=JSON.parse(f.api.beginDiagnosticEdit("fixture","clock",profile));const cuts=[];
  while(!r.done){const before=f.actions.length,stage=r.nextStage;r=JSON.parse(f.api.advanceDiagnosticEdit("clock",r.nextCall));if(stage==="Cắt V1–A1 linked")cuts.push(f.actions.slice(before).filter(a=>a[0]==="razor").length);}
  assert(r.result.ok);
  if(profile==="no-delay"){
    assert.deepStrictEqual(cuts,[129]);
    assert(r.timings.filter(t=>t.stage!=="Cập nhật marker nguồn").every(t=>t.complete));
  }else{
    const limit=clock==="elapsed"?1:profile==="fast"?100:20;
    assert.equal(Math.max(...cuts),limit,profile+":"+clock);
    assert(cuts.length>1);
  }
}
for(const profile of ["baseline","fast","no-delay"]){
  const f=fixture(6),r=finishTrial(f,profile);
  assert(r.report.ok);
  const prepared=r.timings.filter(t=>t.stage.startsWith("Chuẩn bị")||t.stage==="Kiểm tra đầu vào và chuẩn bị");
  for(const t of prepared){
    assert(t.detail,"Prepare details: "+t.stage);
    for(const field of ["clipEnumerationPasses","clipEnumerationItems","clipEnumerationMs","clipItems","clipCollectionReads","clipCountReads","nameReads","startSecondsReads","endSecondsReads","ticksReads","propertyReadMs","sortCalls","sortMs","comparatorCalls"])assert(t.detail[field]>=0,field);
  }
  const input=r.timings[0].detail;
  assert(input.clipEnumerationPasses>0&&input.clipEnumerationItems>0&&input.nameReads>0);
  const cut=r.timings.find(t=>t.stage==="Chuẩn bị sau Cắt V1–A1 linked").detail;
  assert.equal(cut.clipEnumerationPasses,2);assert.equal(cut.clipEnumerationItems,13);
  assert.equal(cut.clipItems,13);assert.equal(cut.clipCountReads,15);
  assert.equal(cut.nameReads,20);assert.equal(cut.sortCalls,2);
  assert(cut.comparatorCalls>0);
  assert.equal(cut.startSecondsReads,12+2*cut.comparatorCalls,"Keep both native start reads on every comparison");
  const voice=r.timings.find(t=>t.stage==="Chuẩn bị sau Cắt voice A2").detail;
  assert.equal(voice.clipEnumerationPasses,1);assert.equal(voice.clipEnumerationItems,6);assert.equal(voice.nameReads,6);
  for(const label of ["Chuẩn bị sau Cập nhật marker nguồn","Chuẩn bị hậu kiểm"])assert(r.timings.some(t=>t.stage===label&&t.detail.ticksReads>0),label);
  const markers=r.timings.filter(t=>t.stage==="Cập nhật marker nguồn");
  assert.equal(markers.reduce((n,t)=>n+t.detail.ownerGroups,0),2);
  assert(markers.every(t=>t.detail.ownerGroups===1&&t.detail.ownerGroupsTotal===2&&t.detail.markersPerGroup.length===1));
  assert.equal(markers.reduce((n,t)=>n+t.detail.markersPerGroup[0],0),4);
  for(const t of markers){
    const m=t.detail.markerCommit;assert.equal(m.readPasses,3);
    assert.equal(m.collectionAfter,m.collectionBefore+m.creates-m.deletes);
    assert.equal(m.creates,t.detail.markersPerGroup[0]);
    assert.equal(m.nameWrites,m.creates);assert.equal(m.commentsWrites,m.creates);assert.equal(m.endWrites,m.creates);
    assert.equal(m.colorWrites,m.creates);assert.equal(m.colorReads,3*m.creates);
    for(const field of ["createMs","nameWriteMs","commentsWriteMs","endWriteMs","colorWriteMs","colorReadMs","deleteMs"])assert(m[field]>=0,field);
    assert(m.readMs>=0&&m.verificationMs>=0&&m.commitMs>=m.readMs&&m.commitMs>=m.verificationMs);
  }
  if(process.argv.includes("--timeline-example")&&profile==="fast")console.log(JSON.stringify({type:"finish",ok:true,timings:r.timings}));
}
{
  const f=fixture(1);let reads=0;
  Object.defineProperty(f.seq.videoTracks[0].clips[0],"name",{get(){reads++;throw Error("NATIVE_NAME_READ_FAILED");}});
  const r=finishTrial(f,"fast"),t=r.timings[r.timings.length-1];
  assert(!r.report.ok);assert(r.report.error.includes("NATIVE_NAME_READ_FAILED"));
  assert.equal(reads,1);assert(t.failed);assert.equal(t.detail.nameReads,2);
  assert(t.detail.propertyReadMs>=0,"Keep partial counters when a native read throws");
}
// #1/#8: unreadable mapping and failed source read-back keep visible warnings.
{
  const failures=[];let passed=0;
  for(const profile of ["stable","baseline","fast","no-delay"])for(const mode of ["speed-unreadable","voice-unreadable","nest-readback","voice-readback"]){try{
    const f=fixture(1);
    Object.assign(f.plan.segments[0],{SourceDurationFrames:120,EffectiveSourceDurationFrames:120,NewEndFrame:100});
    f.plan.pictureCueRevision="srt-cue-picture-v1";f.plan.pictureSegments=f.plan.segments.map(s=>Object.assign({},s,{ParentSegmentIndex:0}));f.plan.pictureCueBoundaries=[];f.plan.mainVideoSourceEndFrame=120;
    if(mode==="speed-unreadable")f.seq.videoTracks[0].clips[0].getSpeed=()=>null;
    if(mode==="voice-unreadable" || mode==="voice-readback"){
      if(mode==="voice-unreadable")f.seq.audioTracks[1].clips[0].getSpeed=()=>null;
      f.plan.markers=[{Owner:"A2",SegmentIndex:0,Name:"VOICE SYNC - Kiem tra can voice",Comments:"listen",ColorIndex:4}];
    }
    if(mode==="nest-readback"){
      f.nested.isSequence=()=>true;
      const bank=f.nested.getMarkers(),create=bank.createMarker;
      bank.createMarker=seconds=>{const m=create(seconds);m.start.seconds+=100;return m;};
    }
    if(mode==="voice-readback"){
      const bank=f.voice.getMarkers(),create=bank.createMarker;
      bank.createMarker=seconds=>{const m=create(seconds);m.start.seconds+=100;return m;};
    }
    vm.runInContext("$._PVS._readJsonFile=function(){return "+JSON.stringify(f.plan)+";};",f.context);
    const result=profile==="stable"?JSON.parse(f.api.executePlan("fixture")):finishTrial(f,profile).report;
    assert.equal(result.clipMarkerFailureCount,0,JSON.stringify(result.clipMarkerFailures || result.error));
    assert(result.ok,JSON.stringify(result));
    assert.equal(result.ownedMarkerSequenceFallbackCount,1,"#1 "+mode+" fallback counted");
    const marker=f.seq.markers.items.find(m=>m.name===(mode.indexOf("voice-")===0?"VOICE SYNC - Kiem tra can voice":"VOICE SYNC - Kiem tra toc do"));
    assert(marker,"Warning must survive on ruler");assert.equal(marker.start.seconds,0);assert.equal(Number(marker.end),100/30);
    assert.equal(result.sequenceMarkerCount,result.reviewMarkerSequenceFallbackCount+1);assert.equal(result.clipMarkerCount,result.markerCount-result.sequenceMarkerCount);
    assert.equal(result.ownedMarkerSequenceFallbacks.length,1);assert(result.ownedMarkerSequenceFallbacks[0].reason);
    passed++;
  }catch(e){failures.push(profile+" "+mode+": "+e.message);}}
  try{
    for(const file of ["docs/USER_GUIDE.md","docs/REGRESSION_MEMORY.md"]){const text=fs.readFileSync(path.join(root,file),"utf8");assert(/V1 nest[^\n]*Native Premiere pending/i.test(text),"#8 native visibility caveat in "+file);}
    passed++;
  }catch(e){failures.push(e.message);}
  console.log("PR37_EXECUTOR_FALLBACK_CASES:passed="+passed+";failed="+failures.length);
  if(failures.length)throw Error(failures.join("\n"));
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
    const found=markers.filter(m=>m.start.seconds>=visual.SourceStart-1e-6&&m.start.seconds<visual.SourceEnd-1e-6&&/đã gộp hình/i.test(m.comments));
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
  if(count>=65&&profile!=="no-delay")assert(result.timings.some(t=>!t.complete&&t.stage!=="Cập nhật marker nguồn"),"Baseline/fast retain bounded native batches.");
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
    value.plan.reviewMarkers=[{start:0,end:1,reason:"timing chưa xác minh – kiểm mép"}];
    vm.runInContext("$._PVS._readJsonFile=function(){return "+JSON.stringify(value.plan)+";};",value.context);
  }
  const report=JSON.parse(stable.api.executePlan("fixture")),trial=finishTrial(staged,profile);
  assert(report.ok,JSON.stringify(report));assert.equal(report.reviewMarkerCount,1);assert.equal(report.sequenceMarkerCount,0);
  assert.deepStrictEqual(trial.report,report);assert.deepStrictEqual(staged.actions,stable.actions);
  assert(staged.voice.getMarkers().items[0].comments.startsWith("Timing chưa xác minh – kiểm mép\n"));
}
f=fixture(6);f.plan.reviewMarkers=[{start:0,end:1,reason:"review"}];delete f.seq.markers;f.voice.isSequence=()=>true;
vm.runInContext("$._PVS._readJsonFile=function(){return "+JSON.stringify(f.plan)+";};",f.context);
const markerFailure=finishTrial(f,"no-delay").report;assert(!markerFailure.ok);assert(markerFailure.captionCreated);assert.equal(markerFailure.reviewMarkerFailureCount,1);
f=fixture(1);f.seq.videoTracks[0].clips[0].getLinkedItems=()=>[];
const badLink=JSON.parse(f.api.executePlan("fixture"));assert(!badLink.ok);assert.equal(badLink.linkMismatchCount,1);assert.equal(badLink.reviewMarkerCount,1);assert(f.voice.getMarkers().items[0].comments.startsWith("Chưa xác minh liên kết V1/A1 – kiểm tra\n"));assert.equal(f.voice.getMarkers().items[0].colorIndex,1);
for(const profile of ["baseline","fast","no-delay"]){
  f=fixture(1);f.seq.failSpeed=true;
  const nativeFailure=finishTrial(f,profile).report;
  assert(!nativeFailure.ok);assert.equal(nativeFailure.error,"NATIVE_SPEED_FAILED");assert.equal(nativeFailure.reviewMarkerCount,1);assert.equal(f.seq.markers.items[0].start.seconds,0);assert.equal(f.seq.markers.items[0].colorIndex,1);assert(f.seq.markers.items[0].comments.includes("Đổi speed lỗi (V1 0) – kiểm tra trước khi thử lại"));
  assert(!f.seq.markers.items[0].comments.includes("NATIVE_SPEED_FAILED"), "Raw native errors remain in the report, not the short marker.");
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
  assert.deepStrictEqual(kept.map(c=>Math.round(Number(c.inPoint.ticks)/TPF*c.speed)),outside?[120,360,600]:[0,360,720]);
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
  const outside=staged.plan.pictureSegments.filter(s=>s.AppliedSpeedPercent<90-.01||s.AppliedSpeedPercent>110+.01);
  assert.strictEqual(staged.nested.getMarkers().items.length,outside.length,"Exact per-cue retime outside the warning band still needs markers.");
  assert.strictEqual(b.speedWarningSentenceCount,outside.length);
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
  assert(api._shouldMarkSpeed(plan,150,150,150,true,false),"Issue #30: exact 150% per-cue retime must get a warning marker.");
  assert(api._shouldMarkSpeed(plan,60,60,60,true,false));
  assert(!api._shouldMarkSpeed(plan,100,100,100,false,false));
  assert(!api._shouldMarkSpeed(plan,100,100,100,false,true),"Merging alone does not change the v1 policy.");
  assert(api._shouldMarkSpeed(plan,100,101,100,false,false));
  assert(api._shouldMarkSpeed(plan,100,100,101,false,false));
  assert(api._shouldMarkSpeed(plan,100,null,100,false,false));
  assert(api._shouldMarkSpeed(plan,100,100,null,false,false));
  assert(api._shouldMarkSpeed({},150,150,150,true,false),"Legacy speed warning policy remains intact.");
  assert(api._shouldMarkSpeed({},100,100,100,false,true));
  assert(!api._shouldMarkSpeed({},100,null,101,false,false));
}
console.log("CUE_PICTURE_EXECUTOR_OK:per-cue-v1-a1;continuous-a2;all-profiles;exact-parity;native-speed-errors-still-marked;invalid-plan-before-mutation");
// Compact input is the same native plan with offline evidence kept in Node.
const panelSource=fs.readFileSync(path.join(root,"extension/js/main.js"),"utf8");
const projectSource=panelSource.slice(panelSource.indexOf("  function projectHostInput("),panelSource.indexOf("  function writeHostInput("));
function projected(f){const compact=vm.runInNewContext(projectSource+'projectHostInput(input,"edit");',{input:f.plan});vm.runInContext("$._PVS._readJsonFile=function(){return "+JSON.stringify(compact)+";};",f.context);return f;}
// Issue #30: final caption labels, range policy and counts agree in full/compact
// input, both in the stable executor and every generated scheduling profile.
let speedRangeCases=0;
for(const compact of [false,true])for(const profile of ["stable","baseline","fast","no-delay"])for(const [percent,color] of [[150,1],[60,3],[100,null]]){
  const f=fixture(1),p=f.plan,s=p.segments[0],frames=12000/percent;
  Object.assign(s,{SourceDurationFrames:120,EffectiveSourceDurationFrames:120,NewEnd:frames/30,NewEndFrame:frames,NewVoiceEndFrame:frames,OriginalVoiceEndFrame:frames,OutputDuration:frames/30,OutputDurationFrames:frames,VisualDurationFrames:frames,AppliedSpeedPercent:percent});
  Object.assign(p,{pictureCueRevision:"srt-cue-picture-v1",pictureCueBoundaries:[],pictureSegments:[Object.assign({},s,{ParentSegmentIndex:0})],mainVideoSourceEndFrame:120,plannedMainVideoEnd:frames/30,plannedMainVideoEndFrame:frames,speedWarningMinPercent:70,speedWarningMaxPercent:130,
    captions:[{Index:11,Start:-1,End:0},{Index:13,Start:frames/60,End:frames/30},{Index:12,Start:0,End:frames/60},{Index:14,Start:frames/30,End:frames/30+1}],summary:{captionCueCount:4,speedWarningCount:color===null?0:1}});
  p.voiceClips[0].end=frames/30;
  f.seq.audioTracks[1].clips[0].end=time(frames);f.seq.audioTracks[1].clips[0].outPoint=time(frames);
  if(compact)projected(f);else vm.runInContext("$._PVS._readJsonFile=function(){return "+JSON.stringify(p)+";};",f.context);
  const result=profile==="stable"?JSON.parse(f.api.executePlan("fixture")):finishTrial(f,profile).report;
  assert(result.ok,JSON.stringify(result));
  const markers=f.nested.getMarkers().items;
  assert.equal(markers.length,color===null?0:1);assert.equal(result.speedWarningSentenceCount,markers.length);assert.equal(result.plannedSpeedWarningSentenceCount,markers.length);
  if(color!==null){
    assert.equal(markers[0].name,"VOICE SYNC - Kiem tra toc do");assert.equal(markers[0].colorIndex,color);
    assert.equal(markers[0].comments,"Cue 12–13: tốc độ hình "+percent+"% (ngưỡng 70–130%) – kiểm tra\n[PremiereVoiceSync:owned-marker:v1]");
    assert(markers[0].start.seconds>=0&&markers[0].start.seconds<4,"Marker stays inside the same V1 source range.");
    assert.equal(f.voice.getMarkers().items.length,0);
  }
  speedRangeCases++;
}
{
  const api=cueFixture().api,p={captions:[{Index:12,Start:0,End:1}],speedWarningMinPercent:70,speedWarningMaxPercent:130},s={NewStart:0,NewEnd:1,FirstTargetCue:999,LastTargetCue:999};
  assert.equal(api._speedMarkerComment(p,s,118,120,120,false,false),"Cue 12: speed thực 120% ≠ kế hoạch 118% – kiểm tra");
  assert.equal(api._speedMarkerComment(p,s,118,118,120,false,false),"Cue 12: speed A1 thực 120% ≠ kế hoạch 118% – kiểm tra");
  assert.equal(api._speedMarkerComment(p,s,118,null,118,false,false),"Cue 12: không đọc được speed V1 – kiểm tra phát");
  assert.equal(api._speedMarkerComment(p,s,118,118,null,false,false),"Cue 12: không đọc được speed A1 – kiểm tra phát");
  assert.equal(api._speedMarkerComment(p,s,118,null,null,false,false),"Cue 12: không đọc được speed V1/A1 – kiểm tra phát");
  assert.equal(api._speedMarkerComment(p,s,100,100,100,false,true),"Cue 12: đã gộp hình – xem hình");
  p.captions=[];
  assert.equal(api._speedMarkerComment(p,s,145,145,145,true,false),"Tốc độ hình 145% (ngưỡng 70–130%) – kiểm tra");
  p.captions=[{Index:24,Start:0,End:1},{Index:20,Start:0,End:1},{Index:20,Start:0,End:1}];
  assert.equal(api._speedMarkerComment(p,s,60,60,60,true,true),"Cue 20, 24: đã gộp hình; tốc độ hình 60% (ngưỡng 70–130%) – kiểm tra");
}
console.log("SPEED_RANGE_MARKERS_OK:executor-cases="+speedRangeCases+";short-comments=8;final-caption-indices;ownership;red-orange;legacy-policy-preserved");
// Real compact input must retain the caption geometry used by native reviews.
for (const compact of [false, true]) for (const profile of ["stable", "baseline", "fast", "no-delay"]) {
  const f = fixture(1);
  f.plan.captions = [{Index:20,Start:0,End:1,Text:"private narration"},{Index:21,Start:1,End:2,Text:"private narration"}];
  f.seq.videoTracks[0].clips[0].getLinkedItems = () => [];
  if (compact) {
    const input = vm.runInNewContext(projectSource+'projectHostInput(input,"edit");',{input:f.plan});
    assert(!JSON.stringify(input).includes("private narration"));
    projected(f);
  } else vm.runInContext("$._PVS._readJsonFile=function(){return "+JSON.stringify(f.plan)+";};",f.context);
  const result = profile === "stable" ? JSON.parse(f.api.executePlan("fixture")) : finishTrial(f,profile).report;
  assert.equal(result.reviewMarkerFailureCount, 0);
  assert.equal(f.voice.getMarkers().items[0].comments, "Cue 20–21: chưa xác minh liên kết V1/A1 – kiểm tra\n[PremiereVoiceSync:review-marker:v2:edit:seq]");
}
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
    if(profile!=="no-delay")assert(added<=8,"Skipped entries cannot consume or enlarge the four linked-pair work allowance.");
  }while(!r.done);
  assert(r.result.ok);
  const speedBatches=r.timings.filter(t=>t.stage==="Tăng speed V1–A1"||t.stage==="Giảm speed V1–A1");
  if(profile==="no-delay")assert.equal(speedBatches.length,2,"Each speed stage must run once without a pair cap.");
  assert(speedBatches.length<Math.ceil(65/4)*2,"Opposite-speed/unchanged entries must not force four-entry empty batches.");
}
{
  const f=fixture(65);let stopRequested=false,r=JSON.parse(f.api.beginDiagnosticEdit("fixture","stage-stop","no-delay"));
  while(!r.done&&r.nextStage!=="Tăng speed V1–A1")r=JSON.parse(f.api.advanceDiagnosticEdit("stage-stop",r.nextCall));
  // Simulate Stop arriving during the first native speed call. The panel can
  // act on it only once this synchronous host stage has returned.
  const push=f.actions.push;
  f.actions.push=function(row){if(row[0]==="speed")stopRequested=true;return push.apply(this,arguments);};
  assert(!r.done);r=JSON.parse(f.api.advanceDiagnosticEdit("stage-stop",r.nextCall));
  assert(stopRequested);
  assert(!r.done&&r.nextStage!=="Tăng speed V1–A1","Stop requested during speed takes effect after the whole stage.");
  assert(f.actions.filter(a=>a[0]==="speed").length>8);
  const count=f.actions.length;JSON.parse(f.api.abortDiagnosticEdit("stage-stop"));assert.equal(f.actions.length,count,"Cancel at the next stage boundary adds no native editing.");
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
console.log("PROFILE_NATIVE_EXECUTOR_OK:full-compact-call-and-report-parity;baseline-fast-four-pair-cap;no-delay-whole-stage;cancel-between-stages;native-progress;trace-failure-and-external-path-safe");
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
console.log("DIAGNOSTIC_EXECUTOR_MOCK_OK:exact-native-call-parity;exact-report-parity;profile-batch-policy;four-checkpoints;duplicate-call-guard;timeline-and-sequence-guard;abort-no-new-edit;no-save-or-Undo-clear;generated-source-current;review-markers-all-profiles;marker-failure-reports-partial-result");
