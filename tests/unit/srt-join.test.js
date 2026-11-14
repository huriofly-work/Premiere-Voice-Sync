"use strict";
const assert = require("assert"), path = require("path"), fs = require("fs"), vm = require("vm");
const joiner = require("../../extension/js/srt-join.js");
const first = "\uFEFF7\r\n0:00:00,500 --> 0:00:02,000\r\nXin chào\r\nthế giới.\r\n\r\n99\r\n00:00:03,000 --> 00:00:04,000\r\nPhần một.\r\n";
const second = "1\n00:00:00,250 --> 00:00:01,250\nPhần hai.\n";
const files = [{ path: "C:\\Phần 1.srt", text: first }, { path: "C:\\Phần 2.srt", text: second }];
const original = JSON.stringify(files), appended = joiner.join(files, "append"), cues = joiner.parse(appended.text);
assert.equal(appended.cueCount, 3); assert.equal(cues[2].start, 4250); assert.equal(cues[2].end, 5250);
assert.equal(cues[0].text, "Xin chào\nthế giới."); assert.equal(JSON.stringify(files), original);
assert(appended.text.includes("3\n00:00:04,250 --> 00:00:05,250\nPhần hai."));
assert(!appended.text.includes("\r") && !appended.text.includes("\uFEFF"));
assert.throws(() => joiner.join(files, "preserve"), /Timestamp giữa/);
const globalSecond = { path: "global.srt", text: "1\n00:00:06,000 --> 00:00:08,000\nKết.\n" };
assert.equal(joiner.parse(joiner.join([files[0], globalSecond], "preserve").text)[2].start, 6000);
assert.equal(joiner.join([files[0], files[1], files[1]], "append").cueCount, 4);
assert.throws(() => joiner.join([files[0]], "append"), /ít nhất hai/);
assert.throws(() => joiner.join(files, "unknown"), /không hợp lệ/);
for (const bad of ["", "1\n00:60:00,000 --> 01:00:01,000\nX", "1\n00:00:02,000 --> 00:00:01,000\nX", "1\n00:00:00,000 --> 00:00:01,000", "1\n00:00:00,00 --> 00:00:01,000\nX", "oops"]) {
  assert.throws(() => joiner.join([files[0], { path: "bad.srt", text: bad }], "append"), /bad\.srt/);
}
assert.throws(() => joiner.join([{ path: "bad.srt", text: "1\n00:00:02,000 --> 00:00:03,000\nA\n\n2\n00:00:01,000 --> 00:00:04,000\nB" }, files[1]], "append"), /chồng hoặc đảo/);

function element(tag = "div") {
  return { tag, children: [], handlers: {}, value: "", checked: false, hidden: false, disabled: false, textContent: "", set innerHTML(v) { this.children = []; }, appendChild(c) { this.children.push(c); }, addEventListener(name, fn) { this.handlers[name] = fn; }, setAttribute() {} };
}
function panelFixture() {
  const controls = {}, writes = [], state = { mode: "edit", targetSrt: files[0].path, captionSrt: "", workflowBusy: false };
  const document = { getElementById(id) { return controls[id] || (controls[id] = element()); }, createElement: element };
  let dialog = [];
  const store = new Map(files.map(f => [f.path, f.text]));
  const fileApi = { readFileSync(file) { if (!store.has(file)) throw Error("MISSING:" + file); return store.get(file); }, writeFileSync(file, text, options) { assert.equal(options.flag, "wx"); writes.push({ file, text }); } };
  const panel = joiner.panel({ state, document, path: path.win32, fs: fileApi, security: { assertNoLinks() {} }, window: { cep: { fs: { showOpenDialog(multi) { assert(multi); return { err: 0, data: dialog }; } } } }, inputError(message, field) { return Object.assign(Error(message), { pvsInputField: field }); } });
  panel.wire(); panel.render();
  const fire = (id, event = "click") => controls[id].handlers[event].call(controls[id]);
  return { panel, controls, state, writes, store, fileApi, document, fire, dialog(value) { dialog = value; } };
}
const f = panelFixture(); assert.equal(f.panel.read(), null);
assert.equal(f.panel.selection(), null);
f.controls.srtJoinEnabled.checked = true; f.fire("srtJoinEnabled", "change");
assert.throws(() => f.panel.read(), e => e.pvsInputField === "srtJoinEnabled");
f.dialog([files[1].path, files[0].path.toUpperCase()]); f.fire("srtJoinAddFiles");
assert.equal(f.controls.srtJoinFiles.children.length, 2, "deduplicate paths without changing selection order");
f.controls.srtJoinTiming.value = "append"; f.fire("srtJoinTiming", "change");
assert.deepEqual(f.panel.read().files, files.map(f => f.path));
f.controls.srtJoinFiles.children[1].children[1].handlers.click();
assert.deepEqual(f.panel.read().files, [files[1].path, files[0].path]);
f.controls.srtJoinFiles.children[0].children[2].handlers.click();
const prepared = f.panel.read(); f.store.set(files[0].path, "changed after preflight");
const selectedOnly = f.panel.selection();
assert.deepEqual(selectedOnly, { files: prepared.files, timing: prepared.timing });
selectedOnly.files.reverse();
assert.deepEqual(f.panel.selection().files, prepared.files, 'selection metadata never shares the mutable internal file list');
// Reading metadata must succeed even when file I/O is unavailable; parsing is
// still performed by read() on the existing legacy execution path.
const originalRead = f.fileApi.readFileSync;
f.fileApi.readFileSync = () => { throw Error('FILE_IO_TRAP'); };
assert.deepEqual(f.panel.selection().files, prepared.files);
assert.throws(() => f.panel.read(), /FILE_IO_TRAP/);
f.fileApi.readFileSync = originalRead;
const temp = f.panel.write(prepared, "C:\\Jobs\\Job_1");
assert.equal(temp, "C:\\Jobs\\Job_1\\reference-joined.srt"); assert.equal(f.writes[0].text, appended.text);
assert.equal(f.writes.length, 1, "write only the joined snapshot inside job output");
f.state.mode = "captions"; f.panel.render(); assert.equal(f.panel.read(), null, "keep mode choices separate");
f.state.mode = "edit"; f.state.workflowBusy = true; f.panel.render();
assert(f.controls.srtJoinEnabled.disabled && f.controls.srtJoinAddFiles.disabled);
assert(f.controls.srtJoinFiles.children.every(li => li.children.slice(1).every(b => b.disabled)));
f.state.workflowBusy = false; f.panel.render(); f.controls.srtJoinFiles.children[1].children[3].handlers.click();
assert.equal(f.controls.srtJoinFiles.children.length, 1);

// Each Project file is an explicit choice. Opening the picker or refreshing
// the scan cannot bulk-add files or undo user removals.
const all = panelFixture();
all.panel.setProjectCandidates([{name:'Part 10.srt',path:files[1].path},{name:'Part 2.srt',path:files[0].path},{name:'duplicate.srt',path:files[0].path.toUpperCase()}]);
all.controls.srtJoinEnabled.checked=true;all.fire('srtJoinEnabled','change');
assert.equal(all.controls.srtJoinFiles.children.length,1,'only seed the current single-file choice');
assert(!all.controls.srtJoinSelection.open,'selected file list starts collapsed');
assert.equal(all.controls.srtJoinProjectList.children.length,2,'case-insensitive path deduplication');
assert(all.controls.editSrtSingle.hidden && all.controls.srtCandidates.disabled && all.controls.pickTargetSrt.disabled);
function projectCheck(f,file,checked){
  const row=f.controls.srtJoinProjectList.children.find(row=>row.title.toLowerCase()===file.toLowerCase());assert(row);
  const box=row.children[0];box.checked=checked;box.handlers.change.call(box);
}
all.fire('srtJoinAddProject');assert.equal(all.controls.srtJoinFiles.children.length,1,'opening picker never adds files');
projectCheck(all,files[1].path,true);
all.controls.srtJoinTiming.value='append';all.fire('srtJoinTiming','change');
assert.deepEqual(all.panel.read().files,files.map(f=>f.path));
all.controls.srtJoinFiles.children[0].children[3].handlers.click();
all.panel.setProjectCandidates([{name:'Part 2.srt',path:files[0].path},{name:'Part 10.srt',path:files[1].path}]);
assert.equal(all.controls.srtJoinFiles.children.length,1,'refresh must keep user removals');
all.controls.srtJoinSearch.value='Part 2';all.fire('srtJoinSearch','input');
assert.equal(all.controls.srtJoinProjectList.children.length,1);projectCheck(all,files[0].path,true);
assert.deepEqual(all.panel.read().files,[files[1].path,files[0].path],'append in selection order; never silently sort chosen chapters');
all.controls.srtJoinSearch.value='';all.fire('srtJoinSearch','input');
all.state.mode='captions';all.panel.render();all.controls.srtJoinEnabled.checked=true;all.fire('srtJoinEnabled','change');
assert.equal(all.controls.srtJoinFiles.children.length,0,'ASR-only has no implicit SRT or bulk selection');
projectCheck(all,files[0].path,true);projectCheck(all,files[1].path,true);
assert.deepEqual(all.panel.read().files,files.map(f=>f.path));
all.controls.srtJoinEnabled.checked=false;all.fire('srtJoinEnabled','change');
assert(!all.controls.captionSrtSingle.hidden && !all.controls.captionSrtCandidates.disabled && !all.state.captionSrt,'restore ASR-only choice');
const pending=panelFixture();pending.state.mode='captions';pending.controls.srtJoinEnabled.checked=true;pending.fire('srtJoinEnabled','change');
pending.state.mode='edit';pending.panel.setProjectCandidates(files.map(f=>({name:path.win32.basename(f.path),path:f.path})));
pending.state.mode='captions';pending.panel.render();assert.equal(pending.controls.srtJoinFiles.children.length,0,'late scan must not silently select chapters');

// Exercise production main.js up to the native boundary, using an immutable joined snapshot.
async function workflow(mode, enabled, language = 'vi') {
  const g = panelFixture(), captured = {}, data = new Map(), errors = [];
  g.store.set(files[0].path, first);
  const mockFs = { ...g.fileApi, existsSync: () => false, mkdirSync() {}, readdirSync: () => ["job"], writeFileSync(file, text) { data.set(file, text); }, readFileSync(file) { return data.has(file) ? data.get(file) : g.fileApi.readFileSync(file); } };
  const fakeJoin = { panel: () => ({ render() {}, read: () => enabled ? { ...appended, files: files.map(f => f.path) } : null, write(value, folder) { const file = path.win32.join(folder, "reference-joined.srt"); mockFs.writeFileSync(file, value.text); return file; } }) };
  const plan = { key: "plan", input: {}, ranges: [{ start: 0, end: 10 }] };
  const sequence = { name: "Test", frameRate: 30, sequenceId: "s", voices: [{ name: "voice" }] };
  const range = { projectId: "p", sequenceId: "s", snapshot: "original", plan, frameRate: 30 };
  const context = { require: n => ({ fs: mockFs, path: path.win32, child_process: {} }[n]), window: { PvsSecurity: { assertNoLinks() {} }, PvsSrtJoin: fakeJoin }, document: { ...g.document, addEventListener() {} }, localStorage: { getItem: () => null, setItem() {}, removeItem() {} }, fixture: { captured, errors, sequence, range, plan } };
  const injected = `
    setWorkflowBusy=function(b){state.workflowBusy=b;};beginRun=function(w){runContext={workflow:w};};
    scanSequence=async function(){return fixture.sequence;};scanCaptionRange=async function(){return fixture.range;};
    readSettings=function(){return {minSpeed:70,maxSpeed:130,minDialogueGap:1,voiceGroupGap:2,maxCaptionCharacters:42};};
    waitForWorkflowPause=async function(){};confirmWorkflowNotice=async function(){return true;};
    applicationDataRoot=function(){return 'C:\\\\Data';};extensionRoot=function(){return 'C:\\\\Extension';};
    createWorkflowMetrics=function(){return {begin:function(){},end:function(){},finish:function(){}};};
    status=function(){};log=function(){};runStage=function(){};reportRunFailure=function(e){fixture.errors.push(e.message);};
    removeTreeSafe=function(){};saveRecoveryJournal=function(){};findWavePreset=function(){return 'preset';};captionTrackCount=async function(){return JSON.stringify({count:0});};
    function capture(jobPath){fixture.captured.job=JSON.parse(fs.readFileSync(jobPath,'utf8'));throw new Error('EXPECTED_NATIVE_BOUNDARY');}
    runPowerShell=async function(script,args){capture(args[1]);};exportCaptionAudio=async function(jobPath){capture(jobPath);};
    state.mode='${mode}';state.targetSrt='${files[0].path.replace(/\\/g, "\\\\")}';state.captionSrt=state.targetSrt;state.captionPlan=fixture.plan;
    byId('subtitleMaxCharacters').value='42';byId('captionLanguage').value='vi';byId('voiceLanguage').value='${language}';
    window.runFixture=${mode === "edit" ? "runSyncWorkflow" : "runCaptions"};`;
  const main = fs.readFileSync(path.join(__dirname, "../../extension/js/main.js"), "utf8");
  vm.runInNewContext(main.replace('  document.addEventListener("DOMContentLoaded", wire);', injected), context);
  await context.window.runFixture();
  if(language === 'invalid') { assert(!captured.job); assert(errors.some(e=>e.includes('ngôn ngữ voice'))); return; }
  assert(errors.includes("EXPECTED_NATIVE_BOUNDARY"), errors.join(";"));
  assert(captured.job.targetSrtPath.endsWith("reference-joined.srt"));
  assert.equal(mockFs.readFileSync(captured.job.targetSrtPath), appended.text);
  assert(!("referencePairs" in captured.job));
  assert.equal(captured.job.language, mode === 'edit' ? language : 'vi');
}
(async () => {
  await workflow("edit", true); await workflow("captions", true);
  await workflow('edit',true,'en'); await workflow('edit',true,'auto'); await workflow('edit',true,'invalid');
  console.log("SRT_JOIN_OK:ordered-concat;renumber;multiline;BOM;CRLF;preserve-global;append-local;invalid-inputs;reorder;remove;dedupe;busy;mode-isolation;immutable-job-snapshot;both-production-workflows");
})().catch(e => { console.error(e); process.exitCode = 1; });
