"use strict";
const assert=require("assert"),fs=require("fs"),path=require("path"),vm=require("vm");
const source=fs.readFileSync(path.join(__dirname,"../../extension/jsx/host.jsx"),"utf8");
const context=vm.createContext({$:{_PVS:{}}});vm.runInContext(source,context);
const api=context.$._PVS._markerTools,apply=context.$._PVS._applyReviewMarkers;
const tag="[PremiereVoiceSync:review-marker:v1:captions]";
const owned=(seconds,note="old")=>({seconds,name:"VOICE SYNC - Can kiem tra",comments:note+"\n"+tag,color:4,end:seconds+0.25});
function fixture(initial=[]){
  let id=0;const values=[],events=[],faults={},reads={first:0,next:0};
  function marker(data){
    let name=data.name||"",comments=data.comments||"",color=data.color===undefined?4:data.color;
    const m={guid:"marker-"+(id++),type:data.type||"Comment",start:{seconds:data.seconds},end:{seconds:data.end===undefined?data.seconds:data.end},
      get name(){return name;},set name(v){events.push(["name",this.guid,v]);name=v;if(faults.name){const f=faults.name;delete faults.name;throw Error(f);}},
      get comments(){return comments;},set comments(v){events.push(["comments",this.guid,v]);comments=v;if(faults.comments){const f=faults.comments;delete faults.comments;throw Error(f);}},
      getColorByIndex(){return color;},setColorByIndex(v){events.push(["color",this.guid,v]);if(faults.color)throw Error("COLOR_FAILED");color=v;}};
    values.push(m);return m;
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
f=fixture([owned(1)]);f.faults.createAt=2;const beforeSequence=state(f);
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
  const item={name:"source",projectItem:{nodeId:"shared",getMarkers:()=>f.collection},inPoint:{seconds:2},outPoint:{seconds:10},start:{seconds:0},end:{seconds:4}};
  const owner={Item:item,Ranges:[{start:2,end:10}]},groups={};context.prepareClipMarkerGroup(owner,groups,30);
  return {...f,item,owner,groups};
}
const clipSpec={Owner:"A2",Name:"VOICE SYNC - Kiem tra can voice",Comments:"review"};
f=clipFixture();const oldClipState=state(f);context.planOwnedClipMarker(f.item,clipSpec,30,f.groups);
assert.deepEqual(state(f),oldClipState);assert.equal(f.events.length,0);
r=api.commit(f.owner.Group);assert.equal(r.count,1);assert.equal(r.deleted,1);assert.equal(f.values[0].start.seconds,6);assert.equal(f.values[0].getColorByIndex(),4);
// Reprepare simulates another run on the same input. Marker remains at 6s.
f.groups={};context.prepareClipMarkerGroup(f.owner,f.groups,30);context.planOwnedClipMarker(f.item,clipSpec,30,f.groups);f.events.length=0;
r=api.commit(f.owner.Group);assert.equal(r.count,1);assert.deepEqual(f.events,[]);
f=clipFixture();context.planOwnedClipMarker(f.item,clipSpec,30,f.groups);f.faults.positionOffset=10;
r=api.commit(f.owner.Group);assert(r.failures.length);assert.deepEqual(state(f),oldClipState);
f=clipFixture();context.planOwnedClipMarker(f.item,clipSpec,30,f.groups);context.blockClipMarkerGroup(f.item,f.groups);
r=api.commit(f.owner.Group);assert(r.failures.length);assert.deepEqual(state(f),oldClipState);assert.equal(f.events.length,0);
f=clipFixture();context.planOwnedClipMarker(f.item,clipSpec,30,f.groups);context.planOwnedClipMarker(f.item,clipSpec,30,f.groups);
assert.equal(f.owner.Group.desired.length,1,"Identical warnings on a repeated source do not duplicate.");
f.faults.positionOffset=0.01;r=api.commit(f.owner.Group);assert.equal(r.count,1);assert.equal(r.failures.length,0);
f.groups={};context.prepareClipMarkerGroup(f.owner,f.groups,30);context.planOwnedClipMarker(f.item,clipSpec,30,f.groups);f.events.length=0;
r=api.commit(f.owner.Group);assert.equal(r.count,1);assert.deepEqual(f.events,[],"Quantized source positions stay stable across reruns.");
console.log("CLIP_MARKER_RECONCILIATION_OK:read-only-plan;source-mapping;no-write-rerun;wrong-native-position;blocked-group-retains-old;shared-source-dedup;quantized-source-rerun");
const main=fs.readFileSync(path.join(__dirname,"../../extension/js/main.js"),"utf8");
vm.runInContext(main.slice(main.indexOf("  function postcheckError(result)"),main.indexOf("  var hostReadyPromise =")),context);
assert(context.postcheckError({clipMarkerFailureCount:1,clipMarkerFailures:["Marker restoration incomplete; inspect before retry."]}).includes("Marker restoration incomplete"),"Restoration details must reach the visible workflow error.");
