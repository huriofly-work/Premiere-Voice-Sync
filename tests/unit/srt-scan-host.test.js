"use strict";
const assert=require("assert"), fs=require("fs"), path=require("path"), vm=require("vm");
const source=fs.readFileSync(path.join(__dirname,"../../extension/jsx/host.jsx"),"utf8");
function collection(items){Object.defineProperty(items,"numItems",{get(){return this.length;}});return items;}
function fixture(){
  let reads=0;
  function media(id,p){const item={nodeId:id,type:1,name:id,isSequence(){return false;},getMediaPath(){reads++;return p;}};Object.defineProperty(item,"children",{get(){throw Error("NON_BIN_CHILDREN_READ");}});return item;}
  function bin(id,items){return {nodeId:id,type:2,name:id,children:collection(items),getMediaPath(){throw Error("BIN_MEDIA_READ");}};}
  const nested=bin("nested",[media("renamed subtitle","\\\\offline\\share\\renamed.srt")]);
  const root=bin("root",[nested,...Array.from({length:130},(_,i)=>media("video"+i,"C:\\video"+i+".mp4")),media("subtitle","C:\\reference.SRT"),{nodeId:"seq",type:1,isSequence(){return true;},getMediaPath(){throw Error("SEQUENCE_MEDIA_READ");}}]);
  nested.children.push(root); // cycle must be skipped by bin ID
  const context={$:{},app:{project:{rootItem:root,path:"fixture.prproj"}},ProjectItemType:{BIN:2},JSON,Date};
  vm.runInNewContext(source,context);
  return {api:context.$._PVS,context,root,reads:()=>reads};
}
const f=fixture();assert(JSON.parse(f.api.beginSrtScan("token")).ok);
let result,found=[],calls=0,last=0;
do{const before=f.reads();result=JSON.parse(f.api.advanceSrtScan("token"));assert(result.ok);assert(result.scanned-last<=64);assert(f.reads()-before<=64);last=result.scanned;found.push(...result.candidates);calls++;}while(!result.done);
assert(calls>=3);assert.deepStrictEqual(found.map(x=>x.name).sort(),["renamed subtitle","subtitle"]);assert.strictEqual(f.api._srtScanState,null);
const switched=fixture();switched.api.beginSrtScan("switch");switched.context.app.project.path="other.prproj";assert(!JSON.parse(switched.api.advanceSrtScan("switch")).ok);assert.strictEqual(switched.api._srtScanState,null);
const changed=fixture();changed.api.beginSrtScan("change");changed.root.children.pop();assert(!JSON.parse(changed.api.advanceSrtScan("change")).ok);
const token=fixture();token.api.beginSrtScan("current");assert(!JSON.parse(token.api.advanceSrtScan("stale")).ok);assert(JSON.parse(token.api.advanceSrtScan("current")).ok);
const capped=fixture();capped.api.beginSrtScan("cap");capped.api._srtScanState.scanned=100000;assert(!JSON.parse(capped.api.advanceSrtScan("cap")).ok);
console.log("SRT_SCAN_HOST_OK:bounded-batches;bin-only;cycles;renamed-and-offline-SRT;sequence-skipped;project-change;stale-token;limit-explicit");
