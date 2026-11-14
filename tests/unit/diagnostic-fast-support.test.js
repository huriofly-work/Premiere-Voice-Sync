"use strict";
const assert=require("assert"),fs=require("fs"),path=require("path"),vm=require("vm");
const host=fs.readFileSync(path.join(__dirname,"../../extension/jsx/host.jsx"),"utf8");
const support=fs.readFileSync(path.join(__dirname,"../../tools/diagnostic-fast-support.jsx"),"utf8");
const context=vm.createContext({$:{_PVS:{}},diagnosticFast:true});
vm.runInContext(host,context);vm.runInContext(support,context);
const api=context.$._PVS,fast=context.diagnosticQEClipAtTicks;
function track(starts){return {items:starts.map((s,i)=>({id:i,type:s===null?"Gap":"Clip",start:{ticks:String(s)}})),get numItems(){return this.items.length;},getItemAt(i){return this.items[i];}};}
function parity(t,ticks,tolerance){assert.strictEqual(fast(t,ticks,tolerance),api._findQEClipAtTicks(t,ticks,tolerance));}
for(const starts of [[],[0,100,200],[null,0,null,100],[100,0,200],[0,100,100,200]]){
  const t=track(starts);
  for(const ticks of [0,99,100,105,200,500])for(const tolerance of [-1,0,4,10,1000])parity(t,ticks,tolerance);
}
// Cached indices must be re-read and verified, never stale native proxies.
let t=track([0,100,200]);parity(t,100,0);t.items.unshift({id:99,type:"Gap",start:{ticks:"-10"}});parity(t,100,0);
t=track([0,100,200]);parity(t,100,0);t.items=[t.items[2],t.items[0],t.items[1]];parity(t,100,0);
t=track([0,100,200]);parity(t,100,0);const replacement={id:77,type:"Clip",start:{ticks:"100"}};t.items[1]=replacement;assert.strictEqual(fast(t,100,0),replacement);
// Early exact lookup reads fresh items, without any count-sensitive index.
function resetQe(){context.diagnosticQeStats=context.diagnosticNewQeStats();}
function keyedParity(t,ticks,tolerance,key){assert.strictEqual(fast(t,ticks,tolerance,key),api._findQEClipAtTicks(t,ticks,tolerance));}
let fastReads=0,legacyReads=0,countReads=0;
function wrapper(base,legacy){return {get numItems(){if(!legacy)countReads++;return base.numItems;},getItemAt(i){if(legacy)legacyReads++;else fastReads++;return base.getItemAt(i);}};}
resetQe();
const underlying=track(Array.from({length:200},(_,i)=>i*100));
for(let i=0;i<100;i++){
  assert.strictEqual(fast(wrapper(underlying),i*100,0,"V:0"),underlying.items[i]);
  api._findQEClipAtTicks(wrapper(underlying,true),i*100,0);
}
assert.strictEqual(context.diagnosticQeStats.builds,0);
assert.strictEqual(context.diagnosticQeStats.hits,100);
assert.strictEqual(context.diagnosticQeStats.earlyHits,100);
assert.strictEqual(context.diagnosticQeStats.itemReads,5050);
assert.strictEqual(fastReads,5050);assert.strictEqual(legacyReads,20000);
assert.strictEqual(countReads,100);
// Speed edits insert gaps after each processed clip: count changes on EVERY
// query. No index rebuild; each lookup still returns the same current item.
resetQe();fastReads=0;legacyReads=0;
const changing=track(Array.from({length:200},(_,i)=>i*100));
for(let i=0;i<100;i++){
  const result=fast(wrapper(changing),i*100,0,"V:0");
  assert.strictEqual(result,api._findQEClipAtTicks(wrapper(changing,true),i*100,0));
  changing.items.splice(2*i+1,0,{type:"Gap",start:{ticks:String(i*100+10)}});
}
assert.strictEqual(fastReads,10000);assert.strictEqual(legacyReads,24950);
assert.strictEqual(context.diagnosticQeStats.builds,0);
assert.strictEqual(context.diagnosticQeStats.earlyHits,100);
// Duplicate/unordered starts preserve FIRST exact/nearest tie. A near hit must
// never stop a scan: a closer or exact hit can still occur later.
for(const [starts,ticks,tolerance] of [[[200,0],100,100],[[0,100,100],100,0],[[99,500,100],100,2],[[105,500,101],100,6]]){
  resetQe();keyedParity(wrapper(track(starts)),ticks,tolerance,"A:2");
}
resetQe();t=track([0,100,200]);keyedParity(wrapper(t),105,10,"V:0");
assert.strictEqual(context.diagnosticQeStats.nearestScans,1);
assert.strictEqual(context.diagnosticQeStats.earlyHits,0);
assert.strictEqual(context.diagnosticQeStats.itemReads,3);
// Reordered items, count changes and replacement proxies are observed afresh.
t.items=[t.items[2],t.items[0],t.items[1]];keyedParity(wrapper(t),100,0,"V:0");
t.items[2]=replacement;assert.strictEqual(fast(wrapper(t),100,0,"V:0"),replacement);
t.items.unshift({type:"Gap"});keyedParity(wrapper(t),100,0,"V:0");t.items.shift();keyedParity(wrapper(t),100,0,"V:0");
for(const starts of [[],[0,100,200],[null,0,null,100],[100,0,200],[0,100,100,200],[0,NaN,200],[0,Infinity,200]]){
  resetQe();t=track(starts);
  for(const ticks of [0,50,99,100,105,200,500,NaN,Infinity])for(const tolerance of [-1,0,4,10,1000,NaN,Infinity])keyedParity(wrapper(t),ticks,tolerance,"V:0");
}
// Unreadable fields are skipped like legacy; getItemAt errors still propagate.
t=track([0,100]);t.items.unshift({get type(){throw Error("BAD_NATIVE_FIELDS");}});
keyedParity(wrapper(t),100,0,"V:0");
const broken={numItems:1,getItemAt(){throw Error("NATIVE_READ_FAILED");}};
assert.throws(()=>fast(broken,100,0,"V:0"),/NATIVE_READ_FAILED/);
assert.throws(()=>api._findQEClipAtTicks(broken,100,0),/NATIVE_READ_FAILED/);
// Deterministic randomized nearest/exact parity across changing layouts.
let seed=17;function random(n){seed=(seed*1664525+1013904223)>>>0;return seed%n;}
for(let fixture=0;fixture<120;fixture++){
  resetQe();t=track(Array.from({length:1+random(40)},()=>random(5)===0?null:random(50)*100));
  for(let query=0;query<15;query++){
    keyedParity(wrapper(t),random(100)*50,random(300)-1,"A:3");
    if(query%3===0)t.items.reverse();
    if(query%4===0)t.items.push({type:"Gap"});
  }
}
resetQe();t=track([0,100]);for(const key of [undefined,null,"","V:1","A:-1","__proto__",{}])keyedParity(wrapper(t),100,0,key);
assert.strictEqual(context.diagnosticQeStats.itemReads,0);
context.diagnosticFast=false;keyedParity(wrapper(t),100,0,"V:0");assert.strictEqual(context.diagnosticQeStats.itemReads,0);context.diagnosticFast=true;
// Optimized snapshot is byte-identical to the baseline fingerprint, but reads
// collection bridges once per track rather than repeatedly in the inner loop.
let reads=0;function collection(items,key){Object.defineProperty(items,key,{get(){reads++;return this.length;}});return items;}
const clip={nodeId:"one",start:{ticks:"0"},end:{ticks:"100"},inPoint:{ticks:"0"},outPoint:{ticks:"200"},speed:2};
context.readSpeedPercent=c=>c.speed*100;
const clips=collection(Array.from({length:100},()=>clip),"numItems");
const sequence={sequenceID:"seq",videoTracks:collection([{clips}],"numTracks"),audioTracks:collection([],"numTracks")};
function baseline(seq){const rows=[String(seq.sequenceID)],kinds=[seq.videoTracks,seq.audioTracks];for(let k=0;k<kinds.length;k++)for(let ti=0;ti<kinds[k].numTracks;ti++){const tr=kinds[k][ti];for(let ci=0;ci<tr.clips.numItems;ci++){const c=tr.clips[ci];rows.push(k+":"+ti+":"+c.nodeId+":"+c.start.ticks+":"+c.end.ticks+":"+c.inPoint.ticks+":"+c.outPoint.ticks+":"+c.speed*100);}}return rows.join("|");}
const expected=baseline(sequence),baselineReads=reads;reads=0;
const snapshot=context.diagnosticSnapshot(sequence,true);assert.strictEqual(snapshot.signature,expected);assert.strictEqual(snapshot.byId.one,clip);assert(reads<baselineReads);
// Incremental post-speed snapshots must match a full scan exactly and read
// detailed fields only for touched items. Structural/order changes fall back.
function mediaClip(id){return {nodeId:id,start:{ticks:"0"},end:{ticks:"100"},inPoint:{ticks:"0"},outPoint:{ticks:"100"},speed:1};}
function seqFixture(){return {sequenceID:"seq2",videoTracks:collection([{clips:collection(Array.from({length:100},(_,i)=>mediaClip("v"+i)),"numItems")}],"numTracks"),audioTracks:collection([{clips:collection([mediaClip("a0")],"numItems")}],"numTracks")};}
let seq=seqFixture(),before=context.diagnosticSnapshot(seq,true);
context.diagnosticDirtyItems={};context.diagnosticTouch(seq.videoTracks[0].clips[12]);
seq.videoTracks[0].clips[12].end={ticks:"123"};seq.videoTracks[0].clips[12].speed=0.8;
let after=context.diagnosticSnapshotAfter(seq,before,"speed");
assert.strictEqual(after.signature,context.diagnosticSnapshot(seq,false).signature);assert.strictEqual(after.strategy,"incremental-speed");assert.strictEqual(after.detailReads,1);
assert.strictEqual(context.diagnosticSnapshotAfter(seq,before,"full").strategy,"full");
for(const mutate of [s=>s.videoTracks[0].clips.push(mediaClip("extra")),s=>s.audioTracks.push({clips:collection([],"numItems")}),s=>s.videoTracks[0].clips.reverse(),s=>s.videoTracks[0].clips[20]=mediaClip("replacement")]){
  seq=seqFixture();before=context.diagnosticSnapshot(seq,true);context.diagnosticDirtyItems={};mutate(seq);
  after=context.diagnosticSnapshotAfter(seq,before,"speed");assert.strictEqual(after.strategy,"full-fallback");assert.strictEqual(after.signature,context.diagnosticSnapshot(seq,false).signature);
}
seq=seqFixture();before=context.diagnosticSnapshot(seq,true);context.diagnosticDirtyItems={nmissing:true};
assert.strictEqual(context.diagnosticSnapshotAfter(seq,before,"speed").strategy,"full-fallback");
context.diagnosticDirtyItems={};after=context.diagnosticSnapshotAfter(seq,before,"read-only");assert.strictEqual(after.strategy,"read-only");assert.strictEqual(after.detailReads,0);assert.strictEqual(after.signature,before.signature);
// Out-of-scope source/speed changes are not silently absorbed into expected
// state: the next full guard must detect them, including on untouched tracks.
seq.audioTracks[0].clips[0].inPoint={ticks:"2"};
after=context.diagnosticSnapshotAfter(seq,before,"read-only");assert.notStrictEqual(after.signature,context.diagnosticSnapshot(seq,false).signature);
// Unknown modes and duplicate node IDs never use incremental reuse.
assert.strictEqual(context.diagnosticSnapshotAfter(seq,before,"unknown").strategy,"full");
seq=seqFixture();seq.videoTracks[0].clips[1].nodeId="v0";before=context.diagnosticSnapshot(seq,true);
assert.strictEqual(context.diagnosticSnapshotAfter(seq,before,"speed").strategy,"full-fallback");
// Cleanup owner native proxies must be replaced before the first cleanup batch,
// including when its loop index has not yet been initialized.
vm.runInContext("var videoPieces,audioPieces,allVoicePieces,speechPieces,removeVoice,tailItems,qeSequence,cleanupOwnerIndex;",context);
const freshOwner=mediaClip("owner");
context.cleanupOwners=[{NodeId:"owner",Item:{get nodeId(){throw Error("STALE_OWNER_PROXY");}}}];
context.diagnosticRebind({}, {byId:{owner:freshOwner}});
assert.strictEqual(context.cleanupOwners[0].Item,freshOwner);
assert.throws(()=>context.diagnosticRebind({}, {byId:{}}),/DIAGNOSTIC_MARKER_OWNER_MISSING/);
context.cleanupOwnerIndex=1;
context.diagnosticRebind({}, {byId:{}}); // Completed owners are never read again.
console.log("DIAGNOSTIC_FAST_SUPPORT_OK:first-exact-and-nearest-tie-parity;duplicate-unordered-nonfinite-gap-negative-tolerance;fresh-layout-every-query;20000-to-5050-stable-and-24950-to-10000-changing-gap-mock-reads;randomized-mutable-layout-parity;native-read-errors;fingerprint-parity;fewer-collection-reads;cleanup-owner-rebind");
