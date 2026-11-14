"use strict";
const fs=require("fs"),path=require("path"),vm=require("vm"),assert=require("assert");
const plan=JSON.parse(fs.readFileSync(process.argv[2],"utf8").replace(/^\uFEFF/,""));
const context={ $:{_PVS:{}},app:{get project(){throw Error("No Premiere access in a plan check");}}};
vm.runInNewContext(fs.readFileSync(path.join(__dirname,"../../extension/jsx/host.jsx"),"utf8"),context);
const physical=context.$._PVS._speedMergeVisualPlans(plan),map=plan.editedSourceMap;
assert.strictEqual(physical.length,3);
assert.strictEqual(physical[0].NewStartFrame,0);
assert.strictEqual(physical.at(-1).NewEndFrame,plan.plannedMainVideoEndFrame);
let frames=0;
physical.forEach((p,i)=>{
  assert.strictEqual(p.SourceStartFrame,map.kept[i].SourceStartFrame);
  assert.strictEqual(p.SourceEndFrame,map.kept[i].SourceEndFrame);
  if(i)assert.strictEqual(p.NewStartFrame,physical[i-1].NewEndFrame);
  frames+=p.SourceEndFrame-p.SourceStartFrame;
});
assert.strictEqual(frames,map.planEndFrame-map.planStartFrame);
assert.strictEqual(plan.segments.filter(s=>s.Kind==="retime").length,1,"Unsafe voice remains a single group");
console.log("EDITED_PLANNER_HOST_MAP_OK:actual-planner;DTW-conservation;speed-merge;physical-picture-partition;voice-group-unchanged");
