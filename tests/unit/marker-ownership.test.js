"use strict";
const assert=require("assert"),fs=require("fs"),path=require("path"),vm=require("vm");
const host=fs.readFileSync(path.join(__dirname,"../../extension/jsx/host.jsx"),"utf8");
const start=host.indexOf("    function projectItemKey(trackItem)");
const end=host.indexOf("    function planOwnedClipMarker",start);
assert(start>0&&end>start);
const c=vm.createContext({$:{_PVS:{}},timelineMutated:false,clearedClipMarkerCount:0});
vm.runInContext(host,c);
vm.runInContext(host.slice(start,end),c);
const tag="[PremiereVoiceSync:owned-marker:v1]";
const speed={name:"VOICE SYNC - Kiem tra toc do",comments:"Sentence cues 1-2: actual speed=140.000%, warning range=70-130%"};
const voice={name:"VOICE SYNC - Kiem tra can voice",comments:"Sentence cues 3-4 need review"};
for(const m of [speed,voice,{name:"VOICE SYNC - Da gop hinh",comments:"merged\n"+tag}])assert(c.isOwnedClipMarker(m));
for(const m of [{name:speed.name,comments:"My note"},{name:"VOICE SYNC - personal",comments:speed.comments},{name:"My marker",comments:tag},{name:"VOICE SYNC - Kiem tra can voice",comments:"review this"},{name:"VOICE SYNC - old unknown",comments:""}])assert(!c.isOwnedClipMarker(m));
function item(id,sourceStart,sourceEnd,values){
  const markers={getFirstMarker:()=>values[0]||null,getNextMarker:m=>values[values.indexOf(m)+1]||null,deleteMarker:m=>values.splice(values.indexOf(m),1),createMarker:()=>{throw Error("NO_NEW_MARKER_EXPECTED");}};
  return {name:id,projectItem:{nodeId:id,getMarkers:()=>markers},start:{seconds:0},end:{seconds:sourceEnd-sourceStart},inPoint:{seconds:sourceStart},outPoint:{seconds:sourceEnd}};
}
function marker(spec,seconds){return Object.assign({},spec,{start:{seconds}});}
const manual=marker({name:speed.name,comments:"My note"},4),unknown=marker({name:"VOICE SYNC - unknown",comments:""},5);
const values=[marker(speed,0),marker(speed,2),manual,unknown,marker(voice,7),marker(speed,10),marker(speed,20)];
const owner=item("source",2,10,values),groups={},entry={Item:owner,Ranges:[{start:2,end:6},{start:7,end:10}]};
c.prepareClipMarkerGroup(entry,groups,30);
assert.strictEqual(values.length,7,"Preparation must not delete old warnings.");
const result=c.$._PVS._markerTools.commit(entry.Group,()=>{c.timelineMutated=true;});
assert.strictEqual(result.deleted,2);assert.strictEqual(c.timelineMutated,true);
assert.deepStrictEqual(values.map(m=>m.start.seconds),[0,4,5,10,20]);
assert(values.includes(manual)&&values.includes(unknown));
assert.throws(()=>c.prepareClipMarkerGroup(entry,groups,30),/Ambiguous/,"Shared owner is prepared once with the union of source ranges.");
const main=item("nested",0,12,[]),linked=Object.assign({},main),a2=item("voice",0,4,[]),a2second=Object.assign({},a2,{inPoint:{seconds:8},outPoint:{seconds:12},start:{seconds:4},end:{seconds:8}});
const clips=[a2,a2second];clips.numItems=2;const original=[linked];original.numItems=1;
const seq={audioTracks:[{clips:original},{clips}]};
const mapped=c.markerCleanupOwners(seq,main,0,"nested",1,[{name:"voice",start:0,end:4},{name:"voice",start:4,end:8}]);
assert.strictEqual(mapped.length,2,"Linked V1/A1 share one ProjectItem owner.");
assert.deepStrictEqual(JSON.parse(JSON.stringify(mapped[1].Ranges)),[{start:0,end:4},{start:8,end:12}]);
assert.throws(()=>c.markerCleanupOwners(seq,main,0,"nested",1,[{name:"missing",end:4}]),/Could not map voice/);
assert.strictEqual(values.length,5,"Owner mapping preflight cannot delete markers.");
assert.equal(c.projectItemKey({name:"same",projectItem:{name:"same"}}),"","Display names cannot identify marker owners.");
console.log("MARKER_OWNERSHIP_OK:new-tag;exact-legacy-signatures;manual-and-unknown-preserved;half-open-source-scope;shared-owner-union;read-only-preparation;durable-identity");
