"use strict";
const assert = require("assert"), fs = require("fs"), path = require("path"), vm = require("vm");
const root = path.join(__dirname, "../.."), main = fs.readFileSync(path.join(root, "extension/js/main.js"), "utf8");
const model = fs.readFileSync(path.join(root, "extension/js/caption-input.js"), "utf8");
const host = fs.readFileSync(path.join(root, "extension/jsx/host.jsx"), "utf8");
function fixture(options = {}) {
  const files = { "/panel/js/caption-input.js": options.brokenModel ? "" : model, "/panel/jsx/host.jsx": host }, reads = [], closes = [];
  const adobe = { _PVS: { scanSequence() {}, captionInputRevision: 1 } };
  function File(p) {
    this.fsName = p; this.exists = p in files; this.encoding = "CP1252"; this.error = "";
    this.open = () => !options.denied;
    this.read = () => { reads.push(p); assert.equal(this.encoding, "UTF-8"); return files[p]; };
    this.close = () => closes.push(p);
  }
  const engine = vm.createContext({ $: adobe, File, app: {} });
  adobe.global = vm.runInContext("this", engine);
  const context = { require: n => ({ fs: {}, path: path.posix, child_process: {} }[n]), window: { PvsSecurity: {} }, document: {}, localStorage: { getItem: () => null }, fixture: {
    raw: async script => vm.runInContext(script, engine)
  } };
  vm.runInNewContext(main.replace('  document.addEventListener("DOMContentLoaded", wire);',
    'extensionRoot=function(){return "/panel";};evalRaw=fixture.raw;window.load=ensureHostLoaded;window.reset=function(){hostReadyPromise=null;};'), context);
  return { load: context.window.load, reset: context.window.reset, engine, adobe, reads, closes, files };
}
(async () => {
  const f = fixture(); await f.load();
  assert.equal(f.adobe.bootstrapRevision, undefined);
  assert.equal(f.adobe._PVS.bootstrapRevision, 3);
  assert.equal(f.adobe._PVS.captionInput.revision, 1);
  assert.equal(f.reads.length, 2); assert.equal(f.closes.length, 2);
  // A later CEP call must see the planner even if no bare global survived eval.
  vm.runInContext("delete PvsCaptionInput", f.engine);
  assert.equal(vm.runInContext('typeof $._PVS.captionInput.resolve', f.engine), "function");
  const error = vm.runInContext('(function(){try{$._PVS.captionInput.resolve({});}catch(e){return e.message;}}())', f.engine);
  assert.equal(error, "Hãy cập nhật bộ điều khiển và đọc lại đầu vào subtitle.");
  // Host source was decoded as UTF-8 as well as the model.
  assert(String(f.adobe._PVS.beginCaptionAudioExport).includes("Chưa nạp bộ lập kế hoạch nguồn audio."));
  await f.load(); f.reset(); await f.load(); assert.equal(f.reads.length, 2, "warm host stays loaded");
  delete f.adobe._PVS.captionInput; f.reset(); await f.load(); assert.equal(f.reads.length, 4, "missing dependency reloads");
  for (const options of [{ brokenModel: true }, { denied: true }]) {
    const bad = fixture(options); await assert.rejects(bad.load(), /Không nạp được/);
    assert(!bad.adobe._PVS.bootstrapRevision, "partial bootstrap cannot mark ready");
    bad.files["/panel/js/caption-input.js"] = model;
    if (!options.denied) await bad.load(); // A failed promise must allow retry.
  }
  const scoped = vm.createContext({ $: { _PVS: {}, global: {} } });
  vm.runInContext('(function(){' + model + '}).call({})', scoped);
  assert.equal(typeof scoped.$._PVS.captionInput.resolve, "function", "temporary eval receiver cannot lose planner");
  console.log("HOST_BOOTSTRAP_RUNTIME_OK:utf8;separate-calls;temporary-this;full-readiness;partial-failure;retry;warm-host");
})().catch(e => { console.error(e); process.exitCode = 1; });
