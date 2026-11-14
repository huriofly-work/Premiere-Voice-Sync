"use strict";
const assert=require("assert"),model=require("../../extension/js/caption-input.js");
const fs=require("fs"),vm=require("vm"),path=require("path"),parser={};
vm.runInNewContext(process.binding("natives")["internal/deps/acorn/acorn/dist/acorn"],{exports:parser,module:{exports:parser}});
parser.parse(fs.readFileSync(path.join(__dirname,"../../extension/js/caption-input.js"),"utf8"),{ecmaVersion:3});
function scan(){return {inputVersion:1,projectId:"p",sequenceId:"s",snapshot:"base",frameRate:30,sequenceEnd:50,selectionRanges:[{start:10,end:14},{start:12,end:16},{start:30,end:35}],selectedAudio:[],inOut:{valid:true,start:11,end:13},audioTracks:[
  {index:0,key:"a",muted:false,clips:[{nodeId:"a",start:0,end:50,disabled:false}]},
  {index:1,key:"b",muted:true,clips:[{nodeId:"b",start:10,end:20,disabled:false},{nodeId:"b2",start:30,end:35,disabled:true}]},
  {index:2,key:"c",muted:false,clips:[{nodeId:"c",start:40,end:50,disabled:false}]}
]};}
function explicit(s,indices,scopeMode="whole"){return {sourceMode:"tracks",scopeMode,trackIndices:indices,topology:model.topology(s),anchors:model.anchors(s,indices)};}
const s=scan();
assert.deepEqual(model.resolve(s,{}).trackIndices,[1]);
assert.deepEqual(model.resolve(s,{sourceMode:"mix"}).trackIndices,[0,2]);
assert.deepEqual(model.resolve(s,{sourceMode:"mix"}).ranges,[{start:0,end:50}],"whole sequence ignores selection/In-Out");
assert.deepEqual(model.resolve(s,{sourceMode:"mix",scopeMode:"selection"}).ranges,[{start:10,end:16},{start:30,end:35}]);
const p=model.resolve(s,explicit(s,[1],"selection"));assert.deepEqual(p.ranges,[{start:10,end:16}]);assert.deepEqual(p.skippedRanges,[{start:30,end:35}]);assert.deepEqual(p.unmuteTracks,[1]);
assert.deepEqual(model.resolve(s,explicit(s,[0,1,2])).trackIndices,[0,1,2]);
assert.deepEqual(model.resolve(s,{sourceMode:"tracks",scopeMode:"inout"}).ranges,[{start:11,end:13}]);
assert.throws(()=>model.resolve(s,explicit(s,[])),/ít nhất/);
assert.throws(()=>model.resolve(s,explicit(s,[2],"inout")),/không có clip/);
s.inOut.valid=false;assert.throws(()=>model.resolve(s,{scopeMode:"inout"}),/In\/Out/);
s.selectionRanges=[];assert.throws(()=>model.resolve(s,{scopeMode:"selection"}),/phạm vi/);
assert.throws(()=>model.resolve(s,{sourceMode:"clips"}),/clip audio/);
s.selectedAudio=[{trackIndex:1,nodeId:"b"},{trackIndex:1,nodeId:"b2"},{trackIndex:2,nodeId:"c"}];
const selected=model.resolve(s,{sourceMode:"clips"});assert.deepEqual(selected.trackIndices,[1,2]);assert.deepEqual(selected.ranges,[{start:10,end:20},{start:40,end:50}]);assert.equal(selected.disabledCount,1);
s.audioTracks[1].clips.push({nodeId:"unknown",start:12,end:14,disabled:null});assert.throws(()=>model.resolve(s,{sourceMode:"clips"}),/enable/);s.audioTracks[1].clips.pop();
const config=explicit(s,[1]);s.audioTracks[1].clips=[];assert.throws(()=>model.resolve(s,config),/không có clip/);assert.deepEqual(config.trackIndices,[1]);
const reorder=scan(),locked=explicit(reorder,[1]);reorder.audioTracks[1].key="changed";assert.throws(()=>model.resolve(reorder,locked),/thứ tự/);
const moved=scan(),before=explicit(moved,[1]);moved.audioTracks[0].clips.push(moved.audioTracks[1].clips.pop());assert.throws(()=>model.resolve(moved,before),/đổi track/);
const muted=scan();muted.audioTracks.forEach(t=>t.muted=true);assert.throws(()=>model.resolve(muted,{sourceMode:"mix"}),/không có clip/);
for(const invalid of [[1,1],["1"],[-1],[1.5],[NaN],[9]])assert.throws(()=>model.resolve(scan(),explicit(scan(),invalid)));
const key1=model.resolve(scan(),{}).key,keyScan=scan();keyScan.snapshot="changed";assert.notEqual(model.resolve(keyScan,{}).key,key1);
{
  const s=scan();s.sequenceEnd=50+1/30;
  const plan=model.resolve(s,{}),rounded=JSON.stringify(JSON.parse(plan.key),(k,v)=>typeof v==="number"?Number(v.toPrecision(15)):v,2);
  assert.notEqual(plan.key,rounded);assert(model.sameKey(plan.key,rounded,30));
  const reorder=v=>Array.isArray(v)?v.map(reorder):v&&typeof v==="object"?Object.fromEntries(Object.entries(v).reverse().map(([k,v])=>[k,reorder(v)])):v;
  assert(model.sameKey(plan.key,JSON.stringify(reorder(JSON.parse(rounded))),30));
  for(const mutate of [
    v=>v.projectId="other",v=>v.sequenceId="other",v=>v.snapshot="changed",
    v=>v.input.trackIndices=[2],v=>v.input.sourceMode="mix",v=>v.input.topology='[[0,"different"]]',
    v=>v.ranges[0].end+=1/30,v=>v.input.scopeRanges[0].end+=1/30,v=>v.ranges[0].end+=0.1/30,
    v=>v.disabledCount++,v=>v.unmuteTracks=[],v=>v.input.selectedAudio=[{nodeId:"other",trackIndex:1}]
  ]){const v=JSON.parse(rounded);mutate(v);assert(!model.sameKey(plan.key,JSON.stringify(v),30));}
  assert(!model.sameKey(plan.key,"bad",30));assert(!model.sameKey(plan.key,rounded,0));
  assert(model.sameRanges([{start:1/30,end:2/30,path:"audio.wav"}],[{start:0.0333333333333333,end:0.0666666666666667}],30));
  assert(!model.sameRanges([{start:1/30,end:2/30}],[{start:1/30,end:3/30}],30));
}
console.log("CAPTION_INPUT_OK:source-scope-matrix;explicit-source-never-replaced;enabled-overlap-default;mute;disabled;multi-track;frozen-identity;deduped-ranges;skipped-empty;invalid-inputs");
