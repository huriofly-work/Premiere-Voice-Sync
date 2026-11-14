"use strict";
const assert=require("assert"), fs=require("fs"), path=require("path"), vm=require("vm");
const source=fs.readFileSync(path.join(__dirname,"../../extension/js/main.js"),"utf8");
function fixture(options={}){
  const controls={},calls=[],messages=[],timers=new Map();let timerId=0,late,sequenceReply;
  function element(){let options=[];return {get options(){return options;},set innerHTML(v){options=[];},appendChild(o){options.push(o);},addEventListener(){},value:"",textContent:""};}
  const host=script=>{
    calls.push(script);
    if(script.includes("scanSequence")) {
      const result={ok:false,error:options.sequenceError||"Sequence này có vẻ đã được dựng. Hãy mở lại sequence template sạch."};
      return options.deferSequence?new Promise(resolve=>{sequenceReply=()=>resolve(result);}):Promise.resolve(result);
    }
    if(script.includes("scanCaptionRange")) return Promise.resolve({ok:true,inputVersion:1,projectId:"project",sequenceId:"seq",name:"Caption sequence",snapshot:"base",frameRate:30,sequenceEnd:5,selectionRanges:[{start:1,end:5}],selectedAudio:[],audioTracks:[{index:1,key:"A2",clipCount:1,muted:false,clips:[{nodeId:"voice",start:1,end:5,disabled:false}]}]});
    if(options.stalled)return new Promise(resolve=>{late=resolve;});
    const begin=script.includes("beginSrtScan");
    const result=begin?{ok:true,done:false,candidates:[]}:{ok:true,done:true,candidates:options.candidates||[{name:"renamed",path:"\\\\offline\\share\\reference.srt"},{name:"duplicate",path:"\\\\OFFLINE\\share\\reference.srt"}]};
    return new Promise(resolve=>setImmediate(()=>resolve(result)));
  };
  const context={require:n=>({fs:{existsSync(){throw Error("SCAN_MUST_NOT_TOUCH_DISK");}},path:path.win32,child_process:{}}[n]),
    window:{PvsSecurity:{},PvsCaptionInput:require("../../extension/js/caption-input.js"),setTimeout(fn,ms){const id=++timerId;if(ms===0)setImmediate(fn);else timers.set(id,fn);return id;},clearTimeout(id){timers.delete(id);}},
    document:{getElementById(id){return controls[id]||(controls[id]=element());},createElement:element,addEventListener(){}},localStorage:{getItem(){return null;},setItem(){}},process:{env:{}},console,fixture:{host,messages}};
  vm.runInNewContext(source.replace('  document.addEventListener("DOMContentLoaded", wire);',`evalHost=fixture.host;log=function(t){fixture.messages.push(t);};window.scanApi={detect:detectSrt,read:readProjectSrtCandidates,refresh:typeof refreshProjectInputs==='function'?refreshProjectInputs:null,backend:renderBackend,caption:setCaptionSrt,edit:setTargetSrt,state:state};`),context);
  return {api:context.window.scanApi,controls,calls,messages,timers,replySequence(){sequenceReply();},reply(){late({ok:true,done:true,candidates:[{name:"late",path:"C:\\late.srt"}]});}};
}
(async()=>{
  assert(!source.includes('scanSequence().then(function () { return detectSrt(true); })'),"Project SRT discovery must not depend on a valid clean Auto edit sequence");
  assert(source.includes('refreshProjectInputs(true);') && source.includes('refreshProjectInputs(false);'),"startup and Read again must use independent Project discovery");
  for(const sequenceError of ["Sequence này có vẻ đã được dựng.","Không có sequence đang mở.","Không tìm thấy voice mới trên A2."]){
    const invalid=fixture({sequenceError});await invalid.api.refresh(true);
    assert.strictEqual(invalid.api.state.targetSrt,"\\\\offline\\share\\reference.srt");assert.strictEqual(invalid.calls.length,3);assert(invalid.calls[0].includes('beginSrtScan'));assert(invalid.calls[2].includes('scanSequence'));assert(invalid.messages.some(m=>m.includes(sequenceError)));assert.strictEqual(invalid.api.state.sequence,null);
    assert(invalid.controls.sequenceSummary.className.includes('edit-only'));
  }
  const captions=fixture();captions.api.state.mode="captions";
  await Promise.all([captions.api.refresh(false),captions.api.refresh(false)]);
  assert.strictEqual(captions.calls.length,3,"shared refresh must not double-read Project/timeline");
  assert(captions.calls[2].includes('scanCaptionRange'));assert(!captions.calls.some(x=>x.includes('scanSequence')));
  assert(captions.controls.captionSummary.textContent.includes('1 vùng'));assert(!captions.controls.scanSequence.disabled);
  assert(captions.controls.captionSummary.className.includes('caption-only'));
  assert.strictEqual(captions.controls.scanSequence.textContent,'Cập nhật đầu vào');
  assert.strictEqual(captions.api.state.captionSrt,"\\\\offline\\share\\reference.srt","caption-only must automatically select the only Project SRT, including deduplication");
  assert.strictEqual(captions.controls.captionSrtCandidates.value,captions.api.state.captionSrt);
  const candidates=[{name:'Original.srt',path:'C:\\Original.srt'},{name:'Narration.vi.srt',path:'C:\\Narration.vi.srt'}];
  const multilingual=fixture({candidates:[candidates[1],{name:'Narration.en.srt',path:'C:\\Narration.en.srt'}]});
  multilingual.controls.voiceLanguage={value:'en'}; await multilingual.api.detect(false);
  assert.strictEqual(multilingual.api.state.targetSrt,'C:\\Narration.en.srt','voice language must rank the matching SRT');
  assert.strictEqual(multilingual.api.state.captionSrt,'C:\\Narration.vi.srt','subtitle ranking must use its independent language');
  const autoLanguage=fixture({candidates:[candidates[1],{name:'Narration.en.srt',path:'C:\\Narration.en.srt'}]});
  autoLanguage.api.state.mode='captions';autoLanguage.controls.captionLanguage={value:'auto'}; await autoLanguage.api.detect(false);
  assert.strictEqual(autoLanguage.api.state.captionSrt,'','auto language must not arbitrarily prefer Vietnamese');
  const rankedOptions={candidates},ranked=fixture(rankedOptions);
  await ranked.api.detect(false);
  assert.strictEqual(ranked.api.state.captionSrt,'C:\\Narration.vi.srt','unique highest score must be selected just as in Auto edit');
  assert.strictEqual(ranked.api.state.captionSrt,ranked.api.state.targetSrt);
  const editManual=fixture({candidates});await editManual.api.detect(false);editManual.api.edit('C:\\external-edit.srt','ổ đĩa');await editManual.api.detect(false);
  assert.strictEqual(editManual.api.state.targetSrt,'C:\\external-edit.srt','an explicit external edit SRT survives refresh just like captions');
  const voiceMatch=fixture({candidates:[{name:'Story.srt',path:'C:\\Story.srt'},{name:'Other.srt',path:'C:\\Other.srt'}]});
  voiceMatch.api.state.sequence={voices:[{name:'Story 1.wav'}]};await voiceMatch.api.detect(false);
  assert.strictEqual(voiceMatch.api.state.captionSrt,'C:\\Story.srt','voice stem ranking must also apply to captions');
  const tied=fixture({candidates:[{name:'A.vi.srt',path:'C:\\A.vi.srt'},{name:'B.vi.srt',path:'C:\\B.vi.srt'}]});
  await tied.api.detect(false);assert.strictEqual(tied.api.state.captionSrt,'');
  assert(tied.controls.captionSrtHint.textContent.includes('2 SRT'),'ambiguous candidates need a visible selection hint');
  const empty=fixture({candidates:[]});await empty.api.detect(false);assert.strictEqual(empty.api.state.captionSrt,'');
  assert(empty.controls.captionSrtHint.textContent.includes('Tự nhận diện lời nói'));
  // No candidate yet is not an explicit opt-out: a later import can be selected.
  const importedOptions={candidates:[]},imported=fixture(importedOptions);await imported.api.detect(false);
  importedOptions.candidates=[candidates[1]];await imported.api.detect(false);assert.strictEqual(imported.api.state.captionSrt,candidates[1].path);
  ranked.api.caption(candidates[0].path);await ranked.api.detect(false);
  assert.strictEqual(ranked.api.state.captionSrt,candidates[0].path,'manual lower-ranked choice must survive refresh');
  ranked.api.caption('C:\\external.srt');await ranked.api.detect(false);
  assert.strictEqual(ranked.api.state.captionSrt,'C:\\external.srt','external manual SRT must survive refresh');
  assert(ranked.controls.captionSrtCandidates.options.some(o=>o.value==='C:\\external.srt'));
  ranked.api.caption('');ranked.api.state.mode='captions';await ranked.api.refresh(false);
  ranked.api.state.mode='edit';await ranked.api.refresh(false);
  assert.strictEqual(ranked.api.state.captionSrt,'','explicit ASR-only choice must survive refresh and tab changes');
  for(const choice of ['', 'C:\\during-scan.srt']) {
    const during=fixture({candidates}),pending=during.api.detect(false);during.api.caption(choice);await pending;
    assert.strictEqual(during.api.state.captionSrt,choice,'scan must not replace any manual choice made while waiting');
  }
  const removedOptions={candidates:[candidates[1]]},removed=fixture(removedOptions);await removed.api.detect(false);
  removedOptions.candidates=[candidates[0]];await removed.api.detect(false);
  assert.strictEqual(removed.api.state.captionSrt,candidates[0].path,'automatic choice no longer in Project must be reconsidered');
  removedOptions.candidates=[];await removed.api.detect(false);assert.strictEqual(removed.api.state.captionSrt,'');
  // A new better-ranked import must not replace a selection still in Project.
  const stableOptions={candidates:[candidates[0]]},stable=fixture(stableOptions);await stable.api.detect(false);
  stableOptions.candidates=candidates;await stable.api.detect(false);assert.strictEqual(stable.api.state.captionSrt,candidates[0].path);
  const switched=fixture({deferSequence:true}),switchRead=switched.api.refresh(false);
  while(!switched.calls.some(x=>x.includes('scanSequence')))await new Promise(resolve=>setImmediate(resolve));
  switched.api.state.mode='captions';const sharedRead=switched.api.refresh(false);switched.replySequence();
  await Promise.all([switchRead,sharedRead]);
  assert.strictEqual(switched.calls.length,4,'tab changed during read must only add the new mode read, not another Project scan');
  assert(switched.calls[3].includes('scanCaptionRange'));assert(switched.controls.captionSummary.textContent.includes('1 vùng'));
  const busy=fixture();busy.api.state.workflowBusy=true;await busy.api.refresh(false);assert.strictEqual(busy.calls.length,0);
  const backend=fixture();backend.api.backend({backend:'cpu',label:'CPU fallback',reason:'Không có CUDA'});
  assert.strictEqual(backend.controls.backendReason.hidden,false);assert(backend.controls.backendReason.textContent.includes('Không có CUDA'));
  backend.api.backend({backend:'cuda',label:'NVIDIA GPU',reason:'Đã xác minh'});assert.strictEqual(backend.controls.backendReason.hidden,true);assert(backend.controls.backendSummary.textContent.includes('NVIDIA GPU'));
  const f=fixture();await Promise.all([f.api.detect(false),f.api.detect(true)]);
  assert.strictEqual(f.calls.length,2);assert.strictEqual(f.controls.srtCandidates.options.length,2);assert.strictEqual(f.api.state.targetSrt,"\\\\offline\\share\\reference.srt");assert.strictEqual(f.timers.size,0);
  const chosen=fixture();const pending=chosen.api.detect(false);chosen.api.state.targetSrt="C:\\manual.srt";await pending;assert.strictEqual(chosen.api.state.targetSrt,"C:\\manual.srt","scan must not replace a selection made while waiting");
  const stalled=fixture({stalled:true});const first=stalled.api.detect(false);
  await new Promise(resolve=>setImmediate(resolve));assert.strictEqual(stalled.timers.size,1);
  [...stalled.timers.values()][0]();await first;assert(stalled.controls.srtHint.textContent.includes("30 giây"));
  await stalled.api.detect(false);assert.strictEqual(stalled.calls.length,1,"must not queue retries behind a timed-out native read");
  stalled.reply();await new Promise(resolve=>setImmediate(resolve));assert.strictEqual(stalled.api.state.targetSrt,"");assert(!stalled.controls.srtCandidates);
  console.log("SRT_SCAN_UI_OK:startup-and-refresh-independent-of-clean-template;built-sequence;no-active-sequence;no-A2;shared-inflight;incremental;no-synchronous-disk-check;timeout-visible;no-queued-retry;late-result-ignored");
  console.log("CAPTION_SRT_SELECTION_OK:single;ranked;voice-stem;ambiguous;empty;later-import;manual-project;external;explicit-ASR;tab-change;inflight-choice;removed-auto;preserve-current");
})().catch(e=>{console.error(e);process.exitCode=1;});
