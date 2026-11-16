"use strict";
const assert = require("assert"), fs = require("fs"), path = require("path"), vm = require("vm");
const { generate } = require("../../tools/Build-DiagnosticExecutor.js");
const host = fs.readFileSync(path.join(__dirname, "../../extension/jsx/host.jsx"), "utf8");
const parser = {};
vm.runInNewContext(process.binding("natives")["internal/deps/acorn/acorn/dist/acorn"], { exports: parser, module: { exports: parser } });
const sites = ["videoPieces", "audioPieces", "coverageItems"];
const cases = [
  Array.from({length:260}, (_, i) => (i*97)%23),
  [], [4], [4, 1, 3, 2], [2, 1, 2, 1, 2, 1],
  Array.from({length:260}, (_, i) => i),
  Array.from({length:260}, (_, i) => 259-i),
  [NaN, 3, 1, NaN, 2, Infinity, -Infinity, Infinity, -0, 0],
  [Infinity, Infinity, -Infinity, -Infinity, "bad", undefined, null, "2", 1]
];
for (const [label, source] of [["host", host], ["executor", generate(host)]]) {
  const ast = parser.parse(source, {ecmaVersion:3});
  let helper = "";
  function walk(node) {
    if (!node || typeof node !== "object") return;
    if (node.type === "FunctionDeclaration" && node.id.name === "sortItemsByStart") helper = source.slice(node.start, node.end);
    Object.keys(node).forEach(key => { const value=node[key]; if (Array.isArray(value)) value.forEach(walk); else if (value && typeof value === "object") walk(value); });
  }
  walk(ast);
  for (const site of sites) {
    const statements = source.split("\n").filter(line => line.includes("sortItemsByStart("+site+")") || line.includes(site+".sort("));
    assert.equal(statements.length, 1, label+":"+site);
    for (const starts of cases) {
      let reads=0, comparatorReads=0;
      const comparisons=[],expectedComparisons=[];
      const items=starts.map((start, id) => ({id, start:{get seconds(){reads++;return start;}}}));
      const expected=starts.map((start,id) => ({id,start})).sort((a,b) => {expectedComparisons.push([a.id,b.id]);return Number(a.start)-Number(b.start);}).map(item => item.id);
      const alias=items;
      function compareObserved(compare,a,b){
        comparisons.push([a.item?a.item.id:a.id,b.item?b.item.id:b.id]);
        const before=reads,result=compare(a,b);comparatorReads+=reads-before;return result;
      }
      const context=vm.createContext({[site]:items, compareObserved, diagnosticCount(){}, diagnosticRead(_, read){return read();}, diagnosticSort(sort){return sort();}});
      vm.runInContext("Array.prototype.sort=(function(sort){return function(compare){return sort.call(this,function(a,b){return compareObserved(compare,a,b);});};})(Array.prototype.sort);",context);
      items.sort=function(compare){return Array.prototype.sort.call(this, (a,b) => compareObserved(compare,a,b));};
      vm.runInContext(helper+"\n"+statements[0],context);
      assert.strictEqual(context[site],alias,"Caller keeps the same array object");
      assert.deepStrictEqual(items.map(item=>item.id),expected,label+":"+site+": order, including ties/non-finite keys");
      assert.deepStrictEqual(comparisons,expectedComparisons,"Same comparison pairs/order without assuming a stable sort or normalizing NaN");
      assert(reads <= items.length,label+":"+site+": native start reads "+reads+" exceed item count "+items.length+"; comparisons="+comparisons.length);
      assert.equal(reads,items.length,"Read each key exactly once, including singleton");
      assert.equal(comparatorReads,0,"Comparator must not read native starts");
    }
  }
}
console.log("CACHE_CLIP_SORT_KEYS_OK:3-sites;host-and-generated-ES3;in-place;distinct-ties-sorted-reverse-nonfinite;one-read-per-item");
