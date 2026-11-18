"use strict";
const markerBounds=require("./marker-bounds");
const assert=require("assert"),fs=require("fs"),vm=require("vm"),path=require("path");
const host=fs.readFileSync(path.join(__dirname,"../../extension/jsx/host.jsx"),"utf8");
let clock=0;
const context=vm.createContext({$:{_PVS:{}},Date:function(){this.getTime=()=>clock;}});
vm.runInContext(host,context);
const api=context.$._PVS._markerTools;
const spec=(seconds,end=seconds+0.5)=>({seconds,end,name:"owned",comments:"new",color:4});
function fixture(positions,foreign=[]){
  const items=[],events=[],faults={};let id=0;
  function marker(data){
    let start=data.seconds,end=data.end===undefined?start+0.25:data.end,color=data.color===undefined?4:data.color;
    const bounds=markerBounds({},start,end,true);
    const m={guid:String(id++),type:"Comment",name:data.name===undefined?"owned":data.name,comments:data.comments===undefined?"old":data.comments,
      get start(){return bounds.start;},set start(v){
        events.push(["start",m.guid,v]);clock+=19;assert.equal(typeof v,"number");
        if(faults.move){delete faults.move;throw Error("MOVE_FAILED");}
        bounds.start=v+(faults.offset||0);delete faults.offset;
        if(faults.moveAfter){delete faults.moveAfter;throw Error("MOVE_AFTER_MUTATION");}
      },
      get end(){return bounds.end;},set end(v){events.push(["end",m.guid,v]);clock+=7;if(faults.end){delete faults.end;throw Error("END_FAILED");}bounds.end=v;assert(bounds.start.seconds<=v);if(faults.endAfter){delete faults.endAfter;throw Error("END_AFTER_MUTATION");}},
      getColorByIndex(){return color;},setColorByIndex(v){events.push(["color",m.guid,v]);color=v;}};
    for(const field of ["name","comments"]){let value=m[field];Object.defineProperty(m,field,{get:()=>value,set(v){events.push([field,m.guid,v]);value=v;if(faults[field]){delete faults[field];throw Error("FIELD_AFTER_MUTATION");}}});}
    items.push(m);return m;
  }
  positions.forEach(p=>marker(typeof p==="number"?{seconds:p}:p));foreign.forEach(p=>marker({seconds:p,name:"manual",comments:"keep"}));
  const collection={getFirstMarker:()=>items[0]||null,getNextMarker:m=>items[items.indexOf(m)+1]||null,
    createMarker(s){events.push(["create",s]);return marker({seconds:s,end:s,name:"",comments:""});},
    deleteMarker(m){events.push(["delete",m.guid]);items.splice(items.indexOf(m),1);if(faults.deleteAfter){delete faults.deleteAfter;throw Error("DELETE_FAILED");}}};
  return {items,events,faults,collection};
}
const state=f=>f.items.map(m=>({seconds:m.start.seconds,end:m.end.seconds,name:m.name,comments:m.comments,color:m.getColorByIndex(),type:m.type})).sort((a,b)=>a.seconds-b.seconds||a.comments.localeCompare(b.comments));
function run(f,specs,allowMove=true){const g=api.group(f.collection,[{start:0,end:100}],r=>r.name.startsWith("owned"),0.01,allowMove);specs.forEach(s=>api.add(g,s));return api.commit(g);}
let passed=0;const failures=[];
function test(name,fn){try{fn();passed++;}catch(e){failures.push(name+": "+e.stack);}}
test("N replacements reuse identity and equal delete/create fields",()=>{
  const f=fixture([1,3,5]),baseline=fixture([1,3,5]),specs=[spec(8),spec(4),spec(6)];
  const ids=f.items.slice(),r=run(f,specs),b=run(baseline,specs,false);
  assert.equal(r.failures.length,0);assert.equal(b.failures.length,0);
  assert.equal(b.timings.creates,3);assert.equal(b.timings.deletes,3);
  assert.equal(r.timings.moves,3);assert.equal(r.timings.moveMs,57);assert.equal(r.timings.creates,0);assert.equal(r.timings.deletes,0);
  assert.deepStrictEqual(state(f),state(baseline));assert(ids.every(m=>f.items.includes(m)));
  assert.deepStrictEqual(f.events.filter(e=>e[0]==="start").map(e=>[e[1],e[2]]).sort(),[["0",4],["1",6],["2",8]]);
});
for(const [old,wanted,moves,creates,deletes] of [[[1],[4,6,8],1,2,0],[[1,2,3],[6],1,0,2],[[2,2],[6,8],2,0,0]])test("mixed counts/ties "+old,()=>{
  const f=fixture(old,[5.95,9]),b=fixture(old,[5.95,9]),specs=wanted.map(s=>spec(s));
  const r=run(f,specs);run(b,specs,false);assert.equal(r.failures.length,0);
  assert.equal(r.timings.moves,moves);assert.equal(r.timings.creates,creates);assert.equal(r.timings.deletes,deletes);assert.deepStrictEqual(state(f),state(b));
});
for (const [start,end,target] of [[1,2,1.5],[2,3,1.5],[1,1,2],[2,2,1],[1,2,4]]) test("point target "+[start,end,target],()=>{
  const f=fixture([{seconds:start,end}]), r=run(f,[spec(target,target)]);
  assert.deepStrictEqual(Array.from(r.failures),[]);
  assert.equal(f.items[0].start.seconds,target);
  assert.equal(f.items[0].end.seconds,target);
  assert.equal(r.timings.endWrites,Number(start!==end));
});
test("duration ordering both directions and default point end",()=>{
  for(const [old,s] of [[1,spec(8)],[8,spec(1)],[8,{...spec(1),end:undefined}]]){
    const f=fixture([old]),r=run(f,[s]);assert.equal(r.failures.length,0);
    assert.equal(f.items[0].end.seconds,s.end===undefined?s.seconds:s.end);
    const fields=f.events.filter(e=>["start","end"].includes(e[0])).map(e=>e[0]);
    assert.deepStrictEqual(fields,["start","end"]);
  }
});
for(const mode of ["move","moveAfter","end","endAfter","name","comments","verify","deleteAfter","offset"])test("compensate "+mode,()=>{
  const f=fixture([1,3,5]),before=state(f),specs=[{...spec(8),name:"owned",comments:"changed",color:1}];
  if(mode==="name")specs[0].name="owned-new";
  if(mode==="verify")specs[0].verify=()=>false;else f.faults[mode]=mode==="offset"?0.02:true;
  const r=run(f,specs);assert(r.failures.length);assert.equal(r.count,0);assert.deepStrictEqual(state(f),before);
  assert.equal(r.timings.moveMs,19*r.timings.moves);assert.equal(r.timings.endWriteMs,7*r.timings.endWrites);
  assert(!r.failures.some(s=>s.includes("restoration")),r.failures.join(";"));
  if(mode!=="deleteAfter")assert(!f.events.some(e=>e[0]==="delete"),"Verify all replacements before deletion");
});
test("created replacements removed and deleted originals recreated on failure",()=>{
  const f=fixture([1]),before=state(f);f.faults.offset=0.02;
  const r=run(f,[spec(6),spec(8)]);assert(r.failures.length);assert.deepStrictEqual(state(f),before);
  assert.equal(r.timings.creates,1);assert.equal(r.timings.deletes,1);
});
test("unchanged fields and rerun write nothing",()=>{
  const f=fixture([{...spec(1),comments:"new"}]),r=run(f,[spec(6)]);
  assert.equal(r.failures.length,0);assert.deepStrictEqual(f.events.map(e=>e[0]),["start"]);
  f.events.length=0;assert.equal(run(f,[spec(6)]).failures.length,0);assert.deepStrictEqual(f.events,[]);
});
test("foreign collision, reserved positions and preparation guard",()=>{
  const f=fixture([1],[6]),g=api.group(f.collection,[{start:0,end:100}],r=>r.name==="owned",0.01,true);
  assert(!api.available(g,6));api.add(g,spec(8));assert(!api.available(g,8));assert(api.available(g,1));
  const before=state(f);f.items[1].comments="manual edit";const edited=state(f),r=api.commit(g);
  assert(r.failures.length);assert.deepStrictEqual(state(f),edited);assert.notDeepStrictEqual(edited,before);assert.equal(f.events.filter(e=>e[0]==="start").length,0);
});
test("readback rejects collision even if target verify accepts position",()=>{
  const f=fixture([1],[6.02]),before=state(f);f.faults.offset=0.02;
  const r=run(f,[{...spec(6),verify:()=>true}]);assert(r.failures.some(s=>s.includes("occupied")));assert.deepStrictEqual(state(f),before);
});
test("position matches win before pairing and keep old slot reserved",()=>{
  const f=fixture([1,3]),ids=f.items.slice(),r=run(f,[spec(6),spec(1)]);
  assert.equal(r.failures.length,0);assert.equal(r.timings.moves,1);
  assert.equal(ids[0].start.seconds,1);assert.equal(ids[1].start.seconds,6);
});
test("restore every moved marker and all fields after final verify fails",()=>{
  const f=fixture([1,3,5]),before=state(f);
  const specs=[6,7,8].map(s=>({...spec(s),name:"owned-new",comments:"changed",color:1,verify:()=>false}));
  const r=run(f,specs);assert(r.failures.length);assert.equal(r.timings.moves,6);assert.deepStrictEqual(state(f),before);
  assert.equal(r.timings.moveMs,114);assert(!f.events.some(e=>e[0]==="delete"));
});
for(const matched of [true,false])test("collision with "+(matched?"kept":"created")+" marker",()=>{
  const f=fixture(matched?[1,6.025]:[1]),before=state(f);f.faults.offset=0.02;
  const r=run(f,[{...spec(6),verify:()=>true},spec(6.025)]);
  assert(r.failures.some(s=>s.includes("occupied")));assert.deepStrictEqual(state(f),before);
});
test("ruler defaults never move",()=>{
  const b=fixture([1]),g=api.group(b.collection,[{start:0,end:100}],r=>r.name==="owned",0.01);api.add(g,spec(8));
  const result=api.commit(g);assert.equal(result.timings.moves,0);assert.equal(result.timings.creates,1);assert.equal(result.timings.deletes,1);
});
console.log("MARKER_MOVES:passed="+passed+";failed="+failures.length);
if(failures.length)throw Error(failures.join("\n"));
