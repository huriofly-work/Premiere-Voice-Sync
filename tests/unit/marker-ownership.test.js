"use strict";
const assert=require("assert"),fs=require("fs"),path=require("path"),vm=require("vm");
const host=fs.readFileSync(path.join(__dirname,"../../extension/jsx/host.jsx"),"utf8");
const context=vm.createContext({$:{_PVS:{}}});
vm.runInContext(host,context);
const api=context.$._PVS;
for (const [kind, workflow, tag] of [["Video","edit","video"],["Voice","edit","voice"],["Caption","edit","caption:edit"],["Caption","captions","caption:captions"]]) {
  const style=api._markerKind(kind,workflow), name="VOICE SYNC - "+kind;
  const row={name,type:"Comment",comments:"Cue 1: kiểm tra\n[PremiereVoiceSync:"+tag+"]"};
  assert(style.owns(row));
  for (const fields of [
    {name:"Personal"}, {type:"Chapter"}, {comments:"Cue 1: kiểm tra"},
    {comments:row.comments+" extra"}, {comments:row.comments+"\nextra"}
  ]) assert(!style.owns({...row,...fields}));
}
const bank={getFirstMarker:()=>null,getNextMarker:()=>null,deleteMarker(){},createMarker(){}};
const owner={nodeId:"shared",getMarkers:()=>bank};
const owners=[], index={};
api._addMarkerSource(owners,index,{projectItem:owner},"video");
api._addMarkerSource(owners,index,{projectItem:owner},"voice");
api._addMarkerSource(owners,index,{projectItem:{name:"unknown"}},"voice");
assert.equal(owners.length,1);
const group=api._prepareMarkerSources(owners,30,"edit")["node:shared"].Group;
for (const tag of ["video","voice","caption:edit"]) {
  const kind=tag.split(":")[0];
  assert(group.owns({name:"VOICE SYNC - "+kind[0].toUpperCase()+kind.slice(1),type:"Comment",comments:"[PremiereVoiceSync:"+tag+"]"}));
}
assert(!group.owns({name:"VOICE SYNC - Caption",type:"Comment",comments:"[PremiereVoiceSync:caption:captions]"}));
assert.equal(api._projectItemKey({name:"same"}),"","Display names cannot identify marker owners.");
console.log("MARKER_OWNERSHIP_OK:exact-name-and-final-tag;manual-and-unknown-preserved;shared-owner;durable-identity");
