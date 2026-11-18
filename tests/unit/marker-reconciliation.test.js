"use strict";
const assert=require("assert"),fs=require("fs"),path=require("path"),vm=require("vm");
const source=fs.readFileSync(path.join(__dirname,"../../extension/jsx/host.jsx"),"utf8");
const context=vm.createContext({$:{_PVS:{}}});vm.runInContext(source,context);
const api=context.$._PVS._markerTools,apply=context.$._PVS._applyReviewMarkers;
const tag="[PremiereVoiceSync:review-marker:v1:captions]";
const owned=(seconds,note="old")=>({seconds,name:"VOICE SYNC - Can kiem tra",comments:note+"\n"+tag,color:4,end:seconds+0.25});
function fixture(initial=[],onMarker=m=>m){
  let id=0;const values=[],events=[],faults={},reads={first:0,next:0};
  function marker(data){
    let name=data.name||"",comments=data.comments||"",color=data.color===undefined?4:data.color,start={seconds:data.seconds};
    const m={guid:"marker-"+(id++),type:data.type||"Comment",get start(){return start;},set start(v){events.push(["start",this.guid,v]);start={seconds:v+(faults.positionOffset||0)};delete faults.positionOffset;},end:{seconds:data.end===undefined?data.seconds:data.end},
      get name(){return name;},set name(v){events.push(["name",this.guid,v]);name=v;if(faults.name){const f=faults.name;delete faults.name;throw Error(f);}},
      get comments(){return comments;},set comments(v){events.push(["comments",this.guid,v]);comments=v;if(faults.comments){const f=faults.comments;delete faults.comments;throw Error(f);}},
      getColorByIndex(){return color;},setColorByIndex(v){events.push(["color",this.guid,v]);if(faults.color)throw Error("COLOR_FAILED");color=v;}};
    values.push(m);return onMarker(m);
  }
  initial.forEach(marker);
  const collection={getFirstMarker(){reads.first++;return values[0]||null;},getNextMarker(m){reads.next++;return values[values.indexOf(m)+1]||null;},
    createMarker(seconds){events.push(["create",seconds]);if(faults.createAt===seconds)throw Error("CREATE_FAILED");
      if(faults.returnExisting)return faults.returnExisting;
      const m=marker({seconds:seconds+(faults.positionOffset||0)});
      if(faults.createAfter){delete faults.createAfter;throw Error("CREATE_AFTER_MUTATION");}return m;},
    deleteMarker(m){events.push(["delete",m.guid]);
      if(faults.deleteNoopOnce){delete faults.deleteNoopOnce;return true;}
      if(faults.deleteNoop||faults.deleteNoopId===m.guid)return true;
      const i=values.indexOf(m);if(i>=0)values.splice(i,1);
      if(faults.deleteAfter){delete faults.deleteAfter;throw Error("DELETE_AFTER_MUTATION");}
      return false; // A false return does not outweigh verified deletion.
    }};
  return {values,events,faults,reads,collection,seq:{timebase:254016000000/30,markers:collection},marker};
}
function state(f){return f.values.map(m=>({seconds:m.start.seconds,end:typeof m.end==="number"?m.end:m.end.seconds,name:m.name,comments:m.comments,color:m.getColorByIndex(),type:m.type})).sort((a,b)=>a.seconds-b.seconds);}
function group(f){return api.group(f.collection,[{start:0,end:10}],m=>m.comments.includes(tag),0.5/30);}
const desired=(seconds,comments="new")=>({seconds,name:"VOICE SYNC - Can kiem tra",comments:comments+"\n"+tag,color:4});
function run(f,issues){return apply(f.seq,issues,[{start:0,end:10}],"captions");}

// Half-open spans, half-frame ties and collision search on the timeline grid.
for (const [length, occupied, frame] of [
  [6, [], 3], [5, [], 3], [1, [], 0], [6, [3], 4], [6, [3,4], 2],
  [6, [1,2,3,4,5], 0], [3, [0,1,2], null]
]) {
  const f=fixture(occupied.map(i=>({seconds:1+i/30,name:"manual"})));
  const r=run(f,[{start:1,end:1+length/30,reason:"review"}]);
  assert.equal(r.reviewMarkerFailureCount,frame===null?1:0);
  const point=state(f).find(m=>m.name!=="manual");
  if(frame===null) assert.equal(point,undefined);
  else {assert(Math.abs(point.seconds-(1+frame/30))<1e-10);assert.equal(point.end,point.seconds);}
}
// Measure Out writes through a full create, range migration and steady rerun.
for (const defaultDuration of [0,0.25]) {
  const f=fixture(), create=f.collection.createMarker;let writes=0;
  f.collection.createMarker=seconds=>{
    const m=create(seconds);let end=seconds+defaultDuration;
    Object.defineProperty(m,"end",{get:()=>({seconds:end}),set:value=>{writes++;end=value;}});
    return m;
  };
  const issues=[{start:1,end:3,reason:"review"}];
  assert.equal(run(f,issues).reviewMarkerCount,1);assert.equal(writes,defaultDuration?1:0);
  const prior=f.values[0];prior.end=3;writes=0;
  assert.equal(run(f,issues).reviewMarkerCount,1);assert.equal(writes,1);assert.equal(prior.end.seconds,2);
  prior.end=2+1e-9;writes=0;f.events.length=0;
  assert.equal(run(f,issues).reviewMarkerCount,1);assert.equal(f.values[0],prior);
  assert.equal(writes,0);assert.deepEqual(f.events,[]);
}

// Commit counters cover the existing passes, including unchanged/manual rows.
{
  const f=fixture([owned(1),owned(2),{seconds:9,name:"manual"}]),g=group(f);
  api.add(g,Object.assign(desired(1),{end:1.5,color:3}));
  api.add(g,Object.assign(desired(3),{end:3.5}));
  const readsBefore=f.reads.first,r=api.commit(g),t=r.timings;
  assert.equal(r.failures.length,0);assert(t,"Commit must return aggregate timings");
  assert.equal(t.collectionBefore,3);assert.equal(t.collectionAfter,3);
  assert.equal(t.readPasses,3);assert.equal(t.readPasses,f.reads.first-readsBefore);
  assert.equal(t.creates,1);assert.equal(t.deletes,1);
  assert.equal(t.nameWrites,1);assert.equal(t.commentsWrites,2);assert.equal(t.endWrites,2);
  assert.equal(t.colorWrites,2);assert.equal(t.colorReads,3+4+3+2);
  for(const key of ["readMs","verificationMs","commitMs","createMs","nameWriteMs","commentsWriteMs","endWriteMs","colorWriteMs","colorReadMs","deleteMs"])assert(t[key]>=0,key);
  assert(t.commitMs>=t.readMs);assert(t.commitMs>=t.verificationMs);
}
{
  let tick=0;
  const timed=vm.createContext({$:{_PVS:{}},Date:function(){this.getTime=()=>tick++;}});
  vm.runInContext(source,timed);
  const tools=timed.$._PVS._markerTools,f=fixture(),g=tools.group(f.collection,[{start:0,end:10}],m=>m.comments.includes(tag),0.5/30);
  tools.add(g,desired(1));
  const t=tools.commit(g).timings;
  const operationMs=["createMs","nameWriteMs","commentsWriteMs","endWriteMs","colorWriteMs","colorReadMs","deleteMs"];
  assert(operationMs.every(k=>t[k]>=0));
  assert(operationMs.reduce((sum,k)=>sum+t[k],0)<=t.commitMs);
  assert(t.readMs>=3);assert(t.verificationMs>=7);assert(t.commitMs>=13);
}
// Charge only native operations on a deterministic clock, including mutations
// that throw and the compensation that follows. Timing adds no native access.
for(const failure of [null,"comments","createAfter","deleteAfter","deleteNoopOnce","color"]){
  let tick=0;
  const timed=vm.createContext({$:{_PVS:{}},Date:function(){this.getTime=()=>tick;}});
  vm.runInContext(source,timed);
  const tools=timed.$._PVS._markerTools;
  const costs={creates:2,nameWrites:3,commentsWrites:5,endWrites:7,colorWrites:11,colorReads:13,deletes:17};
  const actual=Object.fromEntries(Object.keys(costs).map(k=>[k,0]));
  function charge(counter){actual[counter]++;tick+=costs[counter];}
  function wrap(m){
    for(const [field,counter] of [["name","nameWrites"],["comments","commentsWrites"],["end","endWrites"]]){
      const desc=Object.getOwnPropertyDescriptor(m,field);let value=desc.value;
      Object.defineProperty(m,field,{configurable:true,get(){return desc.get?desc.get.call(m):value;},set(v){charge(counter);if(desc.set)desc.set.call(m,v);else value=v;}});
    }
    for(const [method,counter] of [["getColorByIndex","colorReads"],["setColorByIndex","colorWrites"]]){
      const fn=m[method];m[method]=function(...args){charge(counter);return fn.apply(this,args);};
    }
    return m;
  }
  const f=fixture([owned(1),owned(2),{seconds:9,name:"manual"}],wrap);
  for(const [method,counter] of [["createMarker","creates"],["deleteMarker","deletes"]]){
    const fn=f.collection[method];f.collection[method]=function(...args){charge(counter);return fn.apply(this,args);};
  }
  const g=tools.group(f.collection,[{start:0,end:10}],m=>m.comments.includes(tag),0.5/30);
  tools.add(g,Object.assign(desired(1),{end:1.5,color:3}));tools.add(g,Object.assign(desired(3),{end:3.5}));
  if(failure)f.faults[failure]=failure==="comments"?"TIMED_COMMENT_FAILURE":true;
  for(const key of Object.keys(actual))actual[key]=0;
  const before=tick,r=tools.commit(g),t=r.timings;
  const fields={creates:"createMs",nameWrites:"nameWriteMs",commentsWrites:"commentsWriteMs",endWrites:"endWriteMs",colorWrites:"colorWriteMs",colorReads:"colorReadMs",deletes:"deleteMs"};
  for(const [counter,field] of Object.entries(fields)){
    assert.equal(t[counter],actual[counter],failure+":"+counter);
    assert.equal(t[field],actual[counter]*costs[counter],failure+":"+field);
  }
  assert.equal(t.commitMs,tick-before);
  assert.equal(Object.values(fields).reduce((sum,k)=>sum+t[k],0),t.commitMs,"Operation totals are disjoint");
}
{
  const f=fixture([owned(1),{seconds:9,name:"manual"}]),g=group(f);
  api.add(g,Object.assign(desired(1),{end:1.5}));
  f.faults.comments="COMMENT_WRITE_FAILED";
  const r=api.commit(g),t=r.timings;
  assert(r.failures.some(x=>x.includes("COMMENT_WRITE_FAILED")));
  assert.equal(t.readPasses,2);assert.equal(t.collectionBefore,2);assert.equal(t.collectionAfter,2);
  assert.equal(t.creates,0);assert.equal(t.deletes,0);
  assert.equal(t.nameWrites,1);assert.equal(t.commentsWrites,2);assert.equal(t.endWrites,1);
  assert.equal(t.colorReads,5);assert.equal(t.colorWrites,0);
  assert.equal(f.values[0].comments,owned(1).comments,"Count compensation without changing restoration");
}

// PR #37 review: aggregate independent reproductions before legacy assertions.
{
  const failures=[];let passed=0;
  const test=(name,fn)=>{try{fn();passed++;}catch(e){failures.push(name+": "+e.message);}};
  function setup(ranges){
    const timeline=fixture();timeline.seq.sequenceID="review-fixes";
    const sources=ranges.map(()=>fixture());
    const clips=ranges.map(([start,end],i)=>({start:{seconds:start},end:{seconds:end},inPoint:{seconds:10},outPoint:{seconds:10+end-start},getSpeed:()=>1,projectItem:{nodeId:"source-"+i,getMarkers:()=>sources[i].collection}}));
    const invoke=(issues=[{start:1.9,end:3.5,reason:"padded caption"}])=>apply(timeline.seq,issues,[{start:0,end:10}],"captions",null,clips);
    return {timeline,sources,clips,invoke};
  }
  for(const previousEnd of [1.8,2])test("#3 padding selects largest overlap, previous end="+previousEnd,()=>{
    const v=setup([[0,previousEnd],[2,4]]),r=v.invoke();
    assert.equal(r.reviewMarkerClipCount,1);assert.equal(r.reviewMarkerSequenceFallbackCount,0);
    assert.equal(v.sources[0].values.length,0,"Previous tail must not own the issue");
    const point=state(v.sources[1])[0];assert(Math.abs(point.seconds-(10+23/30))<1e-8);assert.equal(point.end,point.seconds);
  });
  test("#3 equal overlaps use ruler",()=>{const v=setup([[0,2],[3,5]]);const r=v.invoke([{start:1,end:4,reason:"tie"}]);assert.equal(r.reviewMarkerSequenceFallbackCount,1);});
  test("#3 overlapping tracks use ruler despite unique largest",()=>{
    const v=setup([[1,2.5],[2,5]]);v.timeline.seq.audioTracks=[{clips:[v.clips[0]]},{clips:[v.clips[1]]}];
    assert.equal(v.invoke().reviewMarkerSequenceFallbackCount,1);
  });
  for(const missing of [undefined,{}]){
    test("#4 unavailable ruler commits clip "+String(missing),()=>{const v=setup([[1,4]]);v.timeline.seq.markers=missing;const r=v.invoke();assert.equal(r.reviewMarkerClipCount,1);assert.equal(r.reviewMarkerFailureCount,0);});
    test("#4 zero issues unavailable ruler "+String(missing),()=>{const v=setup([[1,4]]);v.timeline.seq.markers=missing;assert.equal(v.invoke([]).reviewMarkerFailureCount,0);});
    test("#4 only fallback failures counted "+String(missing),()=>{
      const v=setup([[1,4]]);v.timeline.seq.markers=missing;
      const r=v.invoke([{start:1.9,end:3.5,reason:"clip"},{start:5,end:6,reason:"gap one"},{start:7,end:8,reason:"gap two"}]);
      assert.equal(r.reviewMarkerClipCount,1);assert.equal(r.reviewMarkerCount,1);assert.equal(r.reviewMarkerFailureCount,2);
    });
  }
  test("#6 v1 belongs to ruler only",()=>{
    const v=setup([[1,4]]),legacy=owned(10.5);v.sources[0].marker(legacy);v.timeline.marker(owned(2));
    v.invoke([]);assert.equal(v.sources[0].values.length,1,"Never clean v1 on ProjectItems");assert.equal(v.timeline.values.length,0);
  });
  test("#7 shared speed normalization contract",()=>{
    const factor=context.$._PVS._speedFactor;assert.equal(typeof factor,"function");
    for(const [raw,expected] of [[1,1],[1.1,1.1],[110,1.1],[10,10],[10.1,10.1/100],[null,null],[undefined,null],["",null],[0,null],[-1,null],[NaN,null],[Infinity,null]])assert.equal(factor({getSpeed:()=>raw}),expected);
    assert.equal(factor({getSpeed:()=>{throw Error("unreadable");}}),null);
  });
  console.log("PR37_REVIEW_ADAPTER_CASES:passed="+passed+";failed="+failures.length);
  if(failures.length)throw Error(failures.join("\n"));
}

// Issue #36: ProjectItem times are real source seconds, TrackItem in/out are
// speed-divided. Run all cases before failing so the pre-fix evidence is useful.
{
  const failures=[]; let checks=0;
  const test=(name,fn)=>{try{fn();checks++;}catch(e){failures.push(name+": "+e.message);}};
  function voice(speed=1){
    const source=fixture(),timeline=fixture();timeline.seq.sequenceID="seq36";
    const clip={start:{seconds:12.5667},end:{seconds:21.4},inPoint:{seconds:12.3667},outPoint:{seconds:21.2},
      getSpeed:()=>speed,projectItem:{nodeId:"voice36",getMarkers:()=>source.collection}};
    return {source,timeline,clip};
  }
  const issue={start:15.079,end:16.079,reason:"timing ước lượng – kiểm mép"};
  const invoke=(v,issues=[issue])=>apply(v.timeline.seq,issues,[{start:0,end:30}],"captions",null,[v.clip]);
  for(const speed of [1,1.1,110])test("voice range speed "+speed,()=>{
    const v=voice(speed),r=invoke(v),factor=speed>10?speed/100:speed;
    assert.equal(r.reviewMarkerClipCount,1);assert.equal(r.reviewMarkerSequenceFallbackCount,0);
    const m=v.source.values[0];assert(Math.abs(m.start.seconds-(467/30-12.5667+12.3667)*factor)<1e-7);
    assert(Math.abs(Number(m.end.seconds===undefined?m.end:m.end.seconds)-(467/30-12.5667+12.3667)*factor)<1e-7);
    assert.equal(state(v.source)[0].end,m.start.seconds);
    assert.equal(v.timeline.values.length,0);
    const before=state(v.source);v.source.events.length=0;invoke(v);assert.deepEqual(state(v.source),before);assert.deepEqual(v.source.events,[]);
  });
  for(const mode of ["gap","reverse","unreadable","remap","static-remap","nest","no-api","readback","end-readback"])test("fallback "+mode,()=>{
    const v=voice(1.1);
    if(mode==="gap")v.clip.start.seconds=20;
    if(mode==="reverse")v.clip.isSpeedReversed=()=>true;
    if(mode==="unreadable")v.clip.getSpeed=()=>{throw Error("speed unavailable");};
    if(mode==="remap")v.clip.components=[{matchName:"ADBE Time Remapping"}];
    if(mode==="static-remap"){const properties=[{isTimeVarying:()=>false}];properties.numItems=1;v.clip.components=[{matchName:"ADBE Time Remapping",properties}];}
    if(mode==="nest")v.clip.projectItem.isSequence=()=>true;
    if(mode==="no-api")delete v.clip.projectItem.getMarkers;
    if(mode==="readback")v.source.faults.positionOffset=10;
    if(mode==="end-readback"){
      const create=v.source.collection.createMarker;v.source.collection.createMarker=s=>{const m=create(s);Object.defineProperty(m,"end",{get:()=>({seconds:s+50}),set:()=>{}});return m;};
    }
    const r=invoke(v);assert.equal(r.reviewMarkerSequenceFallbackCount,1);assert.equal(r.reviewMarkerCount,1);assert.equal(r.reviewMarkerFailureCount,0);assert.equal(v.timeline.values.length,1);
  });
  test("clamp at covering clip end, never span gap",()=>{
    const v=voice();v.clip.end.seconds=15.5;v.clip.outPoint.seconds=15.3;
    const r=invoke(v);assert.equal(r.reviewMarkerClipCount,1);assert(Math.abs(state(v.source)[0].end-(459/30-0.2))<1e-7);
  });
  test("shared voice replaces the previous sequence review set",()=>{
    const v=voice(), name="VOICE SYNC - Can kiem tra";
    const oldTag="[PremiereVoiceSync:review-marker:v2:captions:A%20%2F%201]";
    v.source.marker({seconds:1,name:"manual",comments:oldTag});
    v.source.marker({seconds:2,name:"VOICE SYNC - Kiem tra can voice",comments:"[PremiereVoiceSync:owned-marker:v1]"});
    for(const comments of ["manual","[PremiereVoiceSync:owned-marker:v1]","[PremiereVoiceSync:review-marker:v2:edit:A]",
      "[PremiereVoiceSync:review-marker:v2:captions:]","[PremiereVoiceSync:review-marker:v2:captions:A:B]",
      "[PremiereVoiceSync:review-marker:v2:captions:A%Z1]"])v.source.marker({seconds:3,name,comments});
    const before=state(v.source);
    v.timeline.seq.sequenceID="A / 1";
    invoke(v);
    const original=v.source.values[v.source.values.length-1];
    v.timeline=fixture();
    v.timeline.seq.sequenceID="B";
    v.timeline.marker({seconds:2,name,comments:oldTag});
    const ruler=state(v.timeline);
    invoke(v);
    assert.equal(v.source.values.length,before.length+1,"two sequences share one review set");
    assert(original.comments.endsWith("[PremiereVoiceSync:review-marker:v2:captions:B]"));
    assert(v.source.values.includes(original),"matching source position keeps its marker");
    v.timeline.seq.sequenceID="C";
    invoke(v,[]);
    assert.deepStrictEqual(state(v.source),before);
    assert.deepStrictEqual(state(v.timeline),ruler);
  });
  test("scoped rerun and empty cleanup",()=>{
    const v=voice(),name="VOICE SYNC - Can kiem tra",tag="[PremiereVoiceSync:review-marker:v2:captions:seq36]";
    v.timeline.marker({seconds:2,name,comments:"legacy\n"+"[PremiereVoiceSync:review-marker:v1:captions]"});
    for(const comments of [tag,"[PremiereVoiceSync:review-marker:v1:captions]","[PremiereVoiceSync:review-marker:v2:edit:seq36]","[PremiereVoiceSync:review-marker:v2:captions:other]","manual"])
      v.source.marker({seconds:14,name,comments});
    assert.equal(invoke(v).reviewMarkerClipCount,1);assert.equal(v.timeline.values.length,0);assert.equal(v.source.values.length,4);
    invoke(v,[]);assert.equal(v.source.values.length,3);assert(v.source.values.some(m=>m.comments==="manual"));
  });
  test("same media across clips clamps to largest overlap at first clip",()=>{
    const v=voice(1.1);v.clip.end.seconds=15.5;v.clip.outPoint.seconds=15.3;
    const next=Object.assign({},v.clip,{start:{seconds:15.8},end:{seconds:20},inPoint:{seconds:17},outPoint:{seconds:21.2}});
    const r=apply(v.timeline.seq,[issue],[{start:0,end:30}],"captions",null,[v.clip,next]);
    assert.equal(r.reviewMarkerClipCount,1);assert.equal(v.source.values.length,1);assert(Math.abs(state(v.source)[0].end-(459/30-0.2)*1.1)<1e-7);
  });
  test("unsupported rerun cleans scoped v2 only",()=>{
    const v=voice();invoke(v);v.clip.isSpeedReversed=()=>true;
    const r=invoke(v);assert.equal(r.reviewMarkerSequenceFallbackCount,1);assert.equal(v.source.values.length,0);
  });
  test("mixed supported and unsupported sources use ruler",()=>{
    const v=voice(),other=Object.assign({},v.clip,{getSpeed:()=>NaN});
    const r=apply(v.timeline.seq,[issue],[{start:0,end:30}],"captions",null,[v.clip,other]);
    assert.equal(r.reviewMarkerSequenceFallbackCount,1);assert.equal(v.source.values.length,0);
  });
  console.log("VOICE_CLIP_REVIEW_CASES:passed="+checks+";failed="+failures.length);
  if(failures.length)throw Error("VOICE_CLIP_REVIEW_REGRESSION_FAILED\n"+failures.join("\n"));
}

// Native checks use covering final caption indices, with no invented block label.
for (const [captions, expected] of [[[{Index:20,Start:1,End:1.5},{Index:21,Start:1.5,End:2}], "Cue 20–21: hở hình 3 frame – kiểm tra"],
  [[{Index:20,Start:3,End:4}], "Hở hình 3 frame – kiểm tra"]]) {
  const native = fixture();
  const result = apply(native.seq, [{start:1,end:2,reason:"hở hình 3 frame – kiểm tra"}], [{start:0,end:10}], "captions", captions);
  assert.equal(result.reviewMarkerCount, 1); assert.equal(result.reviewMarkerFailureCount, 0);
  assert.equal(native.values[0].comments, expected + "\n" + tag);
}

// Reuse the same native marker, including duration/GUID; identical reruns write nothing.
let f=fixture([owned(1)]),g=group(f),original=f.values[0];api.add(g,desired(1));
let r=api.commit(g);assert.equal(r.count,1);assert.equal(r.deleted,0);assert.equal(f.values[0],original);assert.equal(original.end.seconds,1.25);
f.events.length=0;g=group(f);api.add(g,desired(1));r=api.commit(g);assert.equal(r.count,1);assert.deepEqual(f.events,[]);

// Build/verify replacements before deletion; preserve manual/unknown/outside/other type.
f=fixture([owned(2),{...owned(3),comments:"manual"},{...owned(4),type:"Chapter"},owned(15)]);
g=group(f);api.add(g,desired(1));r=api.commit(g);assert.equal(r.deleted,1);assert.equal(f.values.length,4);
assert(f.events.findIndex(e=>e[0]==="delete")>f.events.findIndex(e=>e[0]==="comments"));
assert(f.values.some(m=>m.type==="Chapter"));assert(f.values.some(m=>m.comments==="manual"));assert(f.values.some(m=>m.start.seconds===15));
g=group(f);r=api.commit(g);assert.equal(r.deleted,1);assert.equal(f.values.length,3,"Empty desired set removes owned in-scope comments only.");

// No changes if collection data changed while paused, including manual notes/color/duration.
for(const change of [m=>m.comments="edited while paused",m=>m.end={seconds:2},m=>m.setColorByIndex(1)]){
  f=fixture([owned(1)]);g=group(f);api.add(g,desired(1));change(f.values[0]);const before=state(f);f.events.length=0;
  r=api.commit(g);assert(r.failures.some(x=>x.includes("changed since preparation")));assert.deepEqual(state(f),before);assert.deepEqual(f.events,[]);
}

// Failure after updating an old marker must restore its old notes/color.
f=fixture([owned(1)]);const beforeUpdate=state(f);g=group(f);api.add(g,{...desired(1),color:1});api.add(g,desired(2));f.faults.createAt=2;
r=api.commit(g);assert(r.failures.length);assert.deepEqual(state(f),beforeUpdate);assert.equal(r.count,0);
for(const field of ["name","comments"]){
  f=fixture([owned(1)]);g=group(f);api.add(g,{...desired(1),name:"VOICE SYNC - updated"});const before=state(f);f.faults[field]="SET_AFTER_MUTATION";
  r=api.commit(g);assert(r.failures.length);assert.deepEqual(state(f),before);
}
f=fixture([owned(1)]);g=group(f);api.add(g,{...desired(1),end:1.8});api.add(g,desired(2));f.faults.createAt=2;
const beforeDuration=state(f);r=api.commit(g);assert(r.failures.length);assert.deepEqual(state(f),beforeDuration,"Duration updates are compensated with notes/color.");
f=fixture([owned(1)]);g=group(f);api.add(g,desired(2));const beforeCreate=state(f);f.faults.createAfter=true;
r=api.commit(g);assert(r.failures.length);assert.deepEqual(state(f),beforeCreate,"Creation that throws after mutation is compensated.");

// Both throw-after-delete and false-success/no-op deletion restore the group.
for(const mode of ["deleteAfter","deleteNoopOnce"]){
  f=fixture([owned(2),owned(3)]);g=group(f);api.add(g,desired(1));const before=state(f);f.faults[mode]=true;
  r=api.commit(g);assert(r.failures.length);assert.equal(r.deleted,0);assert.deepEqual(state(f),before);
}
f=fixture([owned(2),owned(3)]);g=group(f);api.add(g,desired(1));const beforePartialDelete=state(f);f.faults.deleteNoopId=f.values[1].guid;
r=api.commit(g);assert(r.failures.length);assert.deepEqual(state(f),beforePartialDelete,"An earlier successful deletion is restored if a later deletion fails.");

// Compensation failure must be explicit; never report this as a successful run.
f=fixture([owned(2)]);g=group(f);api.add(g,desired(1));f.faults.positionOffset=1;f.faults.deleteNoop=true;
r=api.commit(g);assert(r.failures.some(x=>x.includes("restoration incomplete")));assert.equal(r.count,0);
f=fixture([owned(2)]);g=group(f);api.add(g,desired(1));f.faults.deleteAfter=true;f.faults.createAt=2;
r=api.commit(g);assert(r.failures.some(x=>x.includes("Marker restoration:")));assert(r.failures.some(x=>x.includes("restoration incomplete")));

// Never adopt or delete a manual marker returned by a faulty createMarker.
f=fixture([{seconds:8,name:"manual",comments:"mine"}]);g=group(f);api.add(g,desired(1));f.faults.returnExisting=f.values[0];const beforeManual=state(f);
r=api.commit(g);assert(r.failures.length);assert.deepEqual(state(f),beforeManual);assert(!f.events.some(e=>e[0]==="delete"));
f=fixture([owned(1)]);g=group(f);g.blocked=true;r=api.commit(g);assert(r.failures.length);assert.equal(f.events.length,0);

// A collision later in a sequence plan cannot partially update its first marker.
f=fixture([owned(1),{seconds:2,name:"manual",comments:"mine"}]);const beforeCollision=state(f);
r=run(f,[{start:1,end:1.5,reason:"new notes"},{start:2,end:2+1/30,reason:"blocked"}]);
assert(r.reviewMarkerFailureCount);assert.deepEqual(state(f),beforeCollision);assert.equal(f.events.length,0);
f=fixture([owned(1)]);f.faults.createAt=68/30;const beforeSequence=state(f);
r=run(f,[{start:1,end:1.5,reason:"new notes"},{start:2,end:2.5,reason:"new"}]);assert(r.reviewMarkerFailureCount);assert.deepEqual(state(f),beforeSequence);

// Native collection enumerations are bounded per owner, not per desired marker.
f=fixture(Array.from({length:150},(_,i)=>owned(i/30)));g=group(f);
for(let i=0;i<150;i++)api.add(g,desired(i/30));r=api.commit(g);assert.equal(r.count,150);assert(f.reads.first<=4,JSON.stringify(f.reads));
console.log("MARKER_RECONCILIATION_OK:reuse;no-write-rerun;ownership;duration;scope;pause-conflict;partial-update;create-and-delete-after-throw;false-success-delete;compensation-failure;manual-return;preflight-collision;bounded-native-reads");

// Actual clip coordinate adapter: request planning stays read-only; source scope
// survives trimmed/pre-retimed clips; actual returned positions are rechecked.
const helperStart=source.indexOf("    function projectItemKey(trackItem)");
const helperEnd=source.indexOf("\n    try {\n",helperStart);
assert(helperStart>=0&&helperEnd>helperStart,"Extract marker helpers before the executor's outer try block.");
vm.runInContext(source.slice(helperStart,helperEnd),context);
const clipTag="[PremiereVoiceSync:owned-marker:v1]";
function clipFixture(){
  const f=fixture([{seconds:9,name:"VOICE SYNC - Kiem tra toc do",comments:"old\n"+clipTag}]);
  const item={name:"source",projectItem:{nodeId:"shared",getMarkers:()=>f.collection},getSpeed:()=>2,inPoint:{seconds:2},outPoint:{seconds:6},start:{seconds:0},end:{seconds:4}};
  const owner={Item:item,Ranges:[{start:4,end:12}]},groups={};context.prepareClipMarkerGroup(owner,groups,30);
  return {...f,item,owner,groups};
}
const clipSpec={Owner:"A2",Name:"VOICE SYNC - Kiem tra can voice",Comments:"review"};
f=clipFixture();const oldClipState=state(f);context.planOwnedClipMarker(f.item,clipSpec,30,f.groups);
assert.deepEqual(state(f),oldClipState);assert.equal(f.events.length,0);
r=api.commit(f.owner.Group);assert.equal(r.count,1);assert.equal(r.deleted,0);assert.equal(r.timings.moves,1);assert.equal(r.timings.creates,0);assert.equal(f.values[0].start.seconds,8);assert.equal(state(f)[0].end,8);assert.equal(f.values[0].getColorByIndex(),4);
// Reprepare simulates another run on the same input. Marker remains at 8s.
f.groups={};context.prepareClipMarkerGroup(f.owner,f.groups,30);context.planOwnedClipMarker(f.item,clipSpec,30,f.groups);f.events.length=0;
r=api.commit(f.owner.Group);assert.equal(r.count,1);assert.deepEqual(f.events,[]);
f=clipFixture();context.planOwnedClipMarker(f.item,clipSpec,30,f.groups);f.faults.positionOffset=10;
r=api.commit(f.owner.Group);assert(r.failures.length);assert.deepEqual(state(f),oldClipState);
f=clipFixture();context.planOwnedClipMarker(f.item,clipSpec,30,f.groups);context.blockClipMarkerGroup(f.item,f.groups);
r=api.commit(f.owner.Group);assert(r.failures.length);assert.deepEqual(state(f),oldClipState);assert.equal(f.events.length,0);
f=clipFixture();context.planOwnedClipMarker(f.item,clipSpec,30,f.groups);context.planOwnedClipMarker(f.item,clipSpec,30,f.groups);
assert.equal(f.owner.Group.desired.length,1,"Identical warnings on a repeated source do not duplicate.");
// The host rounds both Time fields of the point to the same source instant.
const rounded=f.values[0];let roundedEnd=rounded.end;
Object.defineProperty(rounded,"end",{get:()=>roundedEnd,set:value=>{roundedEnd=value+0.01;}});
f.faults.positionOffset=0.01;r=api.commit(f.owner.Group);assert.equal(r.count,1);assert.equal(r.failures.length,0);
f.groups={};context.prepareClipMarkerGroup(f.owner,f.groups,30);context.planOwnedClipMarker(f.item,clipSpec,30,f.groups);f.events.length=0;
r=api.commit(f.owner.Group);assert.equal(r.count,1);assert.deepEqual(f.events,[],"Quantized source positions stay stable across reruns.");
console.log("CLIP_MARKER_RECONCILIATION_OK:read-only-plan;source-mapping;no-write-rerun;wrong-native-position;blocked-group-retains-old;shared-source-dedup;quantized-source-rerun");
// Owned V1/A2 ruler fallbacks reconcile only their tagged sequence/range.
{
  const timeline=fixture([{seconds:1,name:"manual",comments:"keep"}]);timeline.seq.sequenceID="owned-rerun";
  const clip={start:{seconds:0},end:{seconds:2}};
  context.ownedMarkerFallbacks=[];context.timelineMutated=false;
  context.queueOwnedMarkerFallback(clip,{Owner:"A2",Name:"VOICE SYNC - Kiem tra can voice",Comments:"listen"},30,{},null,"unreadable");
  r=context.commitOwnedMarkerFallbacks(timeline.seq,6,30);assert.equal(r.count,1);assert.equal(r.failures.length,0);
  const marker=timeline.values.find(m=>m.name===clipSpec.Name);assert(Math.abs(marker.start.seconds-31/30)<1e-8);assert.equal(state(timeline).find(m=>m.name===clipSpec.Name).end,31/30);
  timeline.events.length=0;r=context.commitOwnedMarkerFallbacks(timeline.seq,6,30);assert.equal(r.count,1);assert.deepEqual(timeline.events,[],"Fallback reruns reuse the same marker");
  timeline.marker({seconds:4,name:clipSpec.Name,comments:"foreign\n[PremiereVoiceSync:owned-marker:sequence:v1:other]"});
  timeline.marker({seconds:8,name:clipSpec.Name,comments:marker.comments});
  context.ownedMarkerFallbacks=[];r=context.commitOwnedMarkerFallbacks(timeline.seq,6,30);assert.equal(r.count,0);assert.equal(timeline.values.length,3);assert(!timeline.values.includes(marker));
  assert(timeline.values.some(m=>m.name==="manual"));assert(timeline.values.some(m=>m.start.seconds===8));
  const combined="VOICE SYNC - Gop hinh / Kiem tra toc do";
  context.queueOwnedMarkerFallback(clip,{Owner:"V1",Name:combined,Comments:"merged speed"},30,{},null,"unreadable");
  r=context.commitOwnedMarkerFallbacks(timeline.seq,6,30);assert.equal(r.count,1);
  const point=state(timeline).find(m=>m.name===combined);assert.equal(point.seconds,31/30);assert.equal(point.end,point.seconds);
  console.log("OWNED_RULER_FALLBACK_LIFECYCLE_OK:collision-stays-in-segment;duration;no-write-rerun;empty-cleanup;manual-foreign-outside-preserved");
}
const main=fs.readFileSync(path.join(__dirname,"../../extension/js/main.js"),"utf8");
vm.runInContext(main.slice(main.indexOf("  function postcheckError(result)"),main.indexOf("  var hostReadyPromise =")),context);
assert(context.postcheckError({clipMarkerFailureCount:1,clipMarkerFailures:["Marker restoration incomplete; inspect before retry."]}).includes("Marker restoration incomplete"),"Restoration details must reach the visible workflow error.");
