"use strict";
const assert = require("assert"), fs = require("fs"), path = require("path"), vm = require("vm");
const source = fs.readFileSync(path.join(__dirname, "../../extension/js/main.js"), "utf8");
function fixture(options = {}) {
  const controls = {}, native = [], host = [], storage = new Map(), events = {}, callbacks = [];
  storage.set("pvs.focusOnIncident", options.disabled ? "false" : "true");
  const element = id => controls[id] || (controls[id] = { hidden: false, textContent: "", attrs: {}, setAttribute(k,v) { this.attrs[k]=v; }, focus() {}, addEventListener() {} });
  const context = { require: n => ({ fs: {}, path: path.win32, child_process: { execFile(file,args,opts,done) { native.push({file,args,opts}); callbacks.push(done); } } }[n]),
    window: { PvsSecurity: { assertNoLinks() {} }, __adobe_cep__: { requestOpenExtension(id) { host.push(id); } } },
    document: { getElementById: element, addEventListener() {}, hasFocus() { return true; } },
    localStorage: { getItem(k) { return storage.get(k) || null; }, setItem(k,v) { if(options.storageFailure) throw Error("STORAGE_UNAVAILABLE"); storage.set(k,v); }, removeItem(k) { storage.delete(k); } },
    process: { pid: 123, env: { SystemRoot: "C:\\Windows" } }, console,
    fixture: { options, events } };
  vm.runInNewContext(source.replace('  document.addEventListener("DOMContentLoaded", wire);', `
    extensionRoot=function(){return "C:\\\\panel";}; status=log=function(){};
    scanSequence=async function(){return {ok:true,sequenceId:fixture.options.recoveryMatches?'seq':'other'};};
    scanCaptionRange=async function(){return {sequenceId:'seq',snapshot:'original'};};
    evalHost=async function(){return {ok:true,count:fixture.options.noCaptionApi?null:fixture.options.captionChanged?1:0,bins:fixture.options.binChanged?1:0,inPoint:fixture.options.inChanged?1:0,outPoint:10};};
    window.api={show:showWorkflowNotice,confirm:confirmWorkflowNotice,choose:chooseWorkflowNotice,close:closeWorkflowNotice,begin:beginRun,stage:runStage,fail:reportRunFailure,finish:finishRunNotice,cleanup:appendCleanupNotice,busy:setWorkflowBusy,check:checkIncidentInputs,unexpected:reportUnexpectedError,load:loadNoticeHistory,health:updateRunHealth,
      history:function(){return noticeHistory;},queue:function(){return noticeQueue;},current:function(){return currentNotice;},context:function(){return runContext;},recovery:function(){return recoveryContext;},end:function(){runContext=null;saveRecoveryJournal();setWorkflowBusy(false);},setPending:function(n,engine){hostPending=engine?0:n;enginePending=engine?n:0;},state:state};
  `), context);
  return { api: context.window.api, controls, native, host, storage, callbacks };
}
(async () => {
  const f=fixture();
  f.api.show("Success","Done","ok"); f.api.show("Recovered","CPU fallback","warn");
  assert.strictEqual(f.native.length,0); assert.strictEqual(f.host.length,0);
  const options={code:"WORKFLOW_FAILED",impact:"unknown",stage:"timeline",details:"PRIVATE_TRANSCRIPT F:\\secret\\video.mp3"};
  f.api.show("PRIVATE_TITLE","PRIVATE_TRANSCRIPT","error",options);
  assert.strictEqual(f.native.length,0); assert.strictEqual(f.host.length,0);
  assert.strictEqual(f.controls.workflowNotice.attrs.role,"alert");
  assert(f.controls.workflowNoticeImpact.textContent.includes("chưa xác minh"));
  assert(!Array.from(f.storage.values()).join("").includes("PRIVATE"),"Persistent history must not contain raw errors, titles or transcript.");
  f.api.show("Again","PRIVATE_TRANSCRIPT","error",options);
  assert.strictEqual(f.native.length,0); assert.strictEqual(f.api.current().count,2);
  f.api.show("Cleanup","Warning","warn"); assert.strictEqual(f.controls.workflowNoticeTitle.textContent,"PRIVATE_TITLE");
  f.api.cleanup(Error("CLEANUP_DETAIL")); assert(f.controls.workflowNoticeTechnical.textContent.includes("PRIVATE_TRANSCRIPT"));
  assert(f.controls.workflowNoticeTechnical.textContent.includes("CLEANUP_DETAIL")); assert.strictEqual(f.native.length,0);
  f.api.close(); assert.strictEqual(f.controls.workflowNoticeTitle.textContent,"Cleanup");
   assert.strictEqual(f.controls.workflowNoticeAttention.textContent, "", "A stale helper callback cannot alter a newer notice.");
  f.api.load(); assert(f.api.history().every(x=>x.restored));
  assert(!f.api.history().some(x=>String(x.message).includes("PRIVATE")));
  for(const extra of [{disabled:true},{storageFailure:true}]) {
    const x=fixture(extra); assert.doesNotThrow(()=>x.api.show("Failure","Detail","error"));
    assert.strictEqual(x.controls.workflowNotice.hidden,false);
    assert.strictEqual(x.native.length,0);
  }
  const c=fixture(), choice=c.api.confirm("Start","Initial confirmation","Start","Cancel");
  assert.strictEqual(c.native.length,0); c.api.show("Failure","Background error","error");
  assert.strictEqual(c.controls.workflowNoticeTitle.textContent,"Start"); assert.strictEqual(c.native.length,0);
  c.api.choose(false); assert.strictEqual(await choice,false); assert.strictEqual(c.controls.workflowNoticeTitle.textContent,"Failure"); assert.strictEqual(c.native.length,0);
  const p=fixture(), midway=p.api.confirm("Review","Mid-run review","Continue","Stop",true);
  assert.strictEqual(p.native.length,0); p.api.choose(false); assert.strictEqual(await midway,false);
  const r=fixture({recoveryMatches:false}); r.api.begin("edit");
  r.api.context().baseline=JSON.stringify({ok:true,sequenceId:"seq"}); r.api.context().impact="changed";
  r.api.fail(Error("PARTIAL_EDIT"),"Edit failed"); r.api.end();
  assert(r.controls.runSync.disabled); assert(!r.controls.recoveryNotice.hidden);
  await r.api.check(); assert(r.api.recovery(),"Mismatching template must not unlock another edit.");
  const s=fixture({recoveryMatches:true}); s.api.begin("edit");
  s.api.context().baseline=JSON.stringify({ok:true,sequenceId:"seq"}); s.api.context().impact="unknown";
  s.api.fail(Error("NO_RESULT"),"Edit unknown"); s.api.end();
  s.api.setPending(1); await s.api.check(); assert(s.api.recovery(),"No read/retry can be queued behind a pending host mutation.");
  s.api.setPending(0); await s.api.check(); assert.strictEqual(s.api.recovery(),null); assert(!s.controls.runSync.disabled);
  for(const captionChanged of [false,true]) {
    const a=fixture({captionChanged}); a.api.begin("captions");
    Object.assign(a.api.context(),{sequenceId:"seq",baseline:"original",captionCount:JSON.stringify({count:0,bins:0,inPoint:0,outPoint:10}),impact:"unknown"});
    a.api.fail(Error("IMPORT_FAILED"),"Subtitle failed"); a.api.end(); await a.api.check();
    assert.strictEqual(!!a.api.recovery(),captionChanged,"Added caption must be checked before retry.");
  }
  for(const options of [{},{binChanged:true},{inChanged:true}]) {
    const a=fixture(Object.assign({noCaptionApi:true},options)); a.api.begin("captions");
    Object.assign(a.api.context(),{sequenceId:"seq",baseline:"original",captionCount:JSON.stringify({count:null,bins:0,inPoint:0,outPoint:10}),impact:"unknown"});
    a.api.fail(Error("IMPORT_FAILED"),"Subtitle failed"); a.api.end();
    let pending=a.api.check(); await Promise.resolve();
    assert(a.api.recovery(),"Unavailable caption API must not unlock recovery automatically.");
    assert(a.controls.workflowNoticeMessage.textContent.includes("không tự xác minh"));
    a.api.choose(false); await pending; assert(a.api.recovery(),"Cancel keeps recovery locked.");
    pending=a.api.check(); await Promise.resolve(); a.api.choose(true); await pending;
    assert.strictEqual(!!a.api.recovery(),!!(options.binChanged||options.inChanged),"Manual caption review must still enforce In/Out and temporary-bin checks.");
  }
  const u=fixture(); u.api.begin("edit"); u.api.context().impact="unknown"; u.api.unexpected(Error("ASYNC_FAILED"));
  assert(u.api.context().fatal); assert(u.api.recovery());
  u.api.finish("Edit","Done"); assert.strictEqual(u.controls.workflowNoticeCard.className,"workflow-notice-card error","Unhandled error cannot become green success.");
  const h=fixture(); h.api.begin("edit"); h.api.busy(true); h.api.context().lastProgress=Date.now()-180000; h.api.setPending(1); h.api.health();
  assert(h.controls.runHealth.textContent.includes("chờ lệnh hiện tại trả về")); assert(h.api.state.workflowBusy);
  h.api.setPending(1,true); h.api.health();
  assert(h.controls.runHealth.textContent.includes("có thể vẫn đang chạy"));
  assert(!h.controls.runHealth.textContent.includes("chờ lệnh hiện tại trả về")); assert(h.api.state.workflowBusy);
  console.log("INCIDENT_NOTIFICATIONS_OK:priority;dedup;privacy;one-attention;opt-out;helper-timeout;stale-callback;explicit-approval;mutation-recovery;pending-host-lock;fatal-error;no-timeout-retry");
})().catch(error=>{console.error(error);process.exitCode=1;});
