"use strict";
const assert=require("assert"),{EventEmitter}=require("events"),{create}=require("../../extension/js/native-notifications");
function fixture(verify=()=>{}){
 const child=new EventEmitter(),statuses=[],opened=[],observed=[],writes=[];let spawns=0,visible=false,sound=false;
 child.stdin=new EventEmitter();child.stdin.write=s=>writes.push(JSON.parse(s));child.stdin.end=()=>{child.ended=true;};
 child.stdout=new EventEmitter();child.stdout.setEncoding=()=>{};child.stderr=new EventEmitter();child.kill=()=>{child.killed=true;};
 const bridge=create({sessionId:"a".repeat(32),parentId:123,executable:"helper",verify,panelVisible:()=>visible,soundEnabled:()=>sound,
 spawn(file,args,opts){spawns++;assert(opts.windowsHide);assert(!opts.shell);assert.deepEqual(args,["--pipe","123","a".repeat(32)]);return child;},
 onStatus:v=>statuses.push(v),onOpen:i=>opened.push(i),onObserved:i=>observed.push(i)});
 const emit=d=>child.stdout.emit("data",JSON.stringify({sessionId:"a".repeat(32),...d})+"\n");
 return {bridge,child,statuses,opened,observed,writes,emit,spawns:()=>spawns,visible:v=>visible=v,sound:v=>sound=v};
}
const item={runId:"r-1",kind:"completed",workflow:"captions",reviewRequired:true,message:"PRIVATE SPEECH",title:"PRIVATE PATH"};
const f=fixture();f.bridge.publish(item,true,false);assert.equal(f.spawns(),1);f.visible(true);f.emit({type:"ready",toast:"available"});
assert.equal(f.writes.length,1);assert.equal(f.writes[0].panelVisible,true);assert.equal(f.writes[0].kind,"completed");assert.equal(f.writes[0].workflow,"captions");assert(f.writes[0].hasWarnings);assert(!JSON.stringify(f.writes).includes("PRIVATE"));
f.bridge.publish(item,true);assert.equal(f.writes.length,1);
const identity={incidentId:f.writes[0].incidentId,runId:f.writes[0].runId};
f.emit({type:"open",...identity,runId:"old"});assert.equal(f.opened.length,0);f.emit({type:"open",...identity});assert.equal(f.opened.length,1);
f.emit({type:"observed",toast:"visible",...identity});assert.equal(f.observed[0],item);f.bridge.observe(item,false);assert.equal(f.writes.at(-1).type,"observe");
f.bridge.clear(item);f.emit({type:"open",...identity});assert.equal(f.opened.length,1);assert.equal(f.writes.at(-1).type,"clear");f.bridge.stop();assert(f.child.ended);
const read=fixture();read.bridge.publish(item,true,true);item.seen=true;read.bridge.observe(item,true);read.emit({type:"ready",toast:"available"});assert.equal(read.writes.length,0,"A result read during handshake cannot send a late toast");read.bridge.stop();delete item.seen;
const clear=fixture();clear.bridge.publish(item,true);clear.bridge.clear(item);clear.emit({type:"ready",toast:"available"});assert.equal(clear.writes.length,0,"Cleared queued incident never flashes");clear.bridge.stop();
const off=fixture();off.bridge.publish(item,true);off.bridge.hideToast();off.emit({type:"ready",toast:"available"});assert.equal(off.writes[0].toast,false);off.bridge.stop();
const replacement=fixture();replacement.bridge.publish(item,true);replacement.bridge.publish({...item,runId:"r-2"},true);replacement.emit({type:"ready",toast:"available"});assert.equal(replacement.writes.length,1);assert.equal(replacement.writes[0].runId,"r-2");replacement.bridge.stop();
const bad=fixture(()=>{throw Error("HASH");});bad.bridge.publish(item,true);assert.equal(bad.spawns(),0);assert.deepEqual(bad.statuses,["unavailable"]);
for(const payload of [null,[],true,42,"text",{}, {type:"ready"}]){const x=fixture();x.bridge.publish(item,true);assert.doesNotThrow(()=>x.child.stdout.emit("data",JSON.stringify(payload)+"\n"));assert(x.child.killed);x.emit({type:"ready",toast:"available"});assert.equal(x.writes.length,0);}
assert.equal(typeof f.bridge.review,"undefined");
const audible=fixture();audible.sound(true);audible.bridge.publish(item,true,false);audible.emit({type:"ready",toast:"available"});assert.equal(audible.writes[0].playSound,true);audible.bridge.publish(item,true,false);assert.equal(audible.writes.length,1,"Duplicate completion cannot replay audio");audible.bridge.stop();
for(const finalSound of [false,true]){const queued=fixture();queued.sound(!finalSound);queued.bridge.publish(item,true,false);queued.sound(finalSound);queued.emit({type:"ready",toast:"available"});assert.equal(queued.writes[0].playSound,finalSound,"Use latest sound preference at handshake");queued.bridge.stop();}
const center=fixture();center.sound(true);center.bridge.publish(item,true,false,false);center.emit({type:"ready",toast:"available"});assert.equal(center.writes[0].playSound,false,"Notification center only cannot sound");center.bridge.stop();
const hiddenSound=fixture();hiddenSound.sound(true);hiddenSound.bridge.publish(item,false,false);hiddenSound.emit({type:"ready",toast:"available"});assert.equal(hiddenSound.writes[0].playSound,false);hiddenSound.bridge.stop();
console.log("NATIVE_NOTIFICATION_BRIDGE_OK:one-channel;no-review;curated-protocol;read-before-ready;stale;replacement;opt-out;hash;malformed");
