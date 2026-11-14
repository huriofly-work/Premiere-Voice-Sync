"use strict";
// Build-only transformation. Stable host.jsx is never rewritten. The generated
// ES3 executor changes scheduling, not the statements/order of the edit plan.
const fs = require("fs"), path = require("path"), vm = require("vm"), crypto = require("crypto");
function parser() {
  try { return require("acorn"); } catch (_) {
    // Node bundles Acorn; no download or runtime dependency is needed by CEP.
    const code = process.binding("natives")["internal/deps/acorn/acorn/dist/acorn"];
    if (!code) throw Error("Build requires Acorn (or a Node version bundling Acorn).");
    const exports = {};
    vm.runInNewContext(code, { exports, module: { exports } });
    return exports;
  }
}
function generate(source) {
  source = source.replace(/\r\n/g, "\n");
  const ast = parser().parse(source, { ecmaVersion: 5 });
  const assignment = ast.body.find(n => n.type === "ExpressionStatement" && source.slice(n.start, n.start + 29).startsWith("$._PVS.executePlan = function"));
  if (!assignment) throw Error("Diagnostic build: executor not found.");
  const fn = assignment.expression.right;
  const attempt = fn.body.body.find(n => n.type === "TryStatement");
  const start = attempt.block.start + 1, end = attempt.block.end - 1;
  const edits = [], names = new Set(), helpers = [];
  function walk(n) {
    if (!n || typeof n !== "object") return;
    if (n.type === "FunctionDeclaration") { helpers.push(source.slice(n.start, n.end)); edits.push([n.start, n.end, " ".repeat(n.end - n.start)]); return; }
    if (n.type === "FunctionExpression") return;
    if (n.type === "CallExpression" && n.callee.type === "Identifier" && n.callee.name === "setClipSpeed") {
      // Generated calls add a logical track key; native mutation arguments stay intact.
      const track = n.arguments[1];
      if (n.arguments.length !== 8 || !track || track.type !== "Identifier" || !["qeVideoTrack","qeAudioTrack"].includes(track.name)) throw Error("Review logical QE track key instrumentation.");
      edits.push([n.end-1, n.end-1, track.name === "qeVideoTrack" ? ', "V:0"' : ', "A:" + linkedTrackIndex']);
    }
    if (n.type === "VariableDeclaration") {
      if (n.kind !== "var" || n.declarations.some(d => d.id.type !== "Identifier")) throw Error("Unsupported executor declaration.");
      n.declarations.forEach(d => names.add(d.id.name));
      edits.push([n.start, n.start + 3, "   "]);
    }
    Object.keys(n).forEach(k => { const v = n[k]; if (Array.isArray(v)) v.forEach(walk); else if (v && typeof v === "object") walk(v); });
  }
  attempt.block.body.forEach(walk);
  if (edits.filter(e=>e[0]===e[1]).length!==4) throw Error("Review speed call count for logical QE track keys.");
  function slice(a, b) {
    let value = source.slice(a, b);
    edits.filter(e => e[0] >= a && e[1] <= b).sort((a,b) => b[0]-a[0]).forEach(e => { value = value.slice(0,e[0]-a)+e[2]+value.slice(e[1]-a); });
    return value;
  }
  const loops = {
    cleanupOwnerIndex: "Đọc marker nguồn",
    cutIndex: "Cắt V1–A1 linked", omitIndex: "Bỏ hình–A1 theo SRT đã lược", fastIndex: "Tăng speed V1–A1",
    moveIndex: "Dồn vị trí V1–A1", slowIndex: "Giảm speed V1–A1", reconcileIndex: "Đối chiếu mép V1–A1",
    voiceCutIndex: "Cắt voice A2", removeVoice: "Bỏ lát khoảng lặng A2", voiceMove: "Dồn voice A2",
    markerIndex: "Chuẩn bị marker voice", speedMarkerIndex: "Chuẩn bị marker tốc độ", markerOwnerIndex: "Cập nhật marker nguồn"
  };
  const boundaries = { voiceNames: "Hình V1–A1", fillRequests: "Voice A2", captionFile: "Marker", masterInOutReset: "Caption" };
  const steps = []; let cursor = start, label = "Kiểm tra đầu vào và chuẩn bị";
  function flush(to, checkpoint) {
    const code = slice(cursor,to);
    if (code.trim()) steps.push({ label, code, checkpoint: checkpoint || "" });
    else if (checkpoint && steps.length) steps[steps.length-1].checkpoint = checkpoint;
    cursor = to;
  }
  for (const node of attempt.block.body) {
    const variable = node.type === "VariableDeclaration" && node.declarations[0].id.name;
    if (boundaries[variable]) { flush(node.start, boundaries[variable]); label = "Chuẩn bị " + (variable === "voiceNames" ? "voice A2" : variable === "captionFile" ? "caption" : "hậu kiểm"); }
    const loopVariable = node.type === "ForStatement" && node.init && node.init.type === "VariableDeclaration" && node.init.declarations[0].id.name;
    if (!loops[loopVariable]) continue;
    flush(node.start);
    const index = steps.length;
    const init = slice(node.init.start,node.init.end);
    // A source marker transaction never spans host calls. Even no-delay yields
    // between source owners so cancellation keeps uncommitted owners intact.
    const speedLoop = ["fastIndex", "slowIndex"].includes(loopVariable);
    const yieldCondition = loopVariable === "markerOwnerIndex" ? "batchCount >= 1" :
      `(batchCount >= diagnosticBatchLimit || (batchCount > 0 && (new Date()).getTime() - batchStarted >= diagnosticBatchBudgetMs))`;
    let loopBody = slice(node.body.start+1,node.body.end-1);
    if (speedLoop) {
      // Plan-only skips cost no native work. Keep the scan/time bounds while
      // counting the four atomic V1/A1 mutations separately, after filters.
      const firstSpeedCall = `setClipSpeed(videoPieces[${loopVariable}],`;
      if (loopBody.split(firstSpeedCall).length !== 2) throw Error("Review speed work allowance placement.");
      loopBody = loopBody.replace(firstSpeedCall,
        `if (nativePairCount >= 4) return false;\n            nativePairCount++;\n            ${firstSpeedCall}`);
    }
    // Preserve for-loop test/update/continue semantics. A linked V1–A1 pair
    // stays atomic; yield only BEFORE the next whole iteration.
    const code = `if (!loopInitialized${index}) { ${init}; loopInitialized${index} = true; }\n` +
      `var batchCount = 0, ${speedLoop ? "nativePairCount = 0, " : ""}batchStarted = (new Date()).getTime();\n` +
      `for (; ${slice(node.test.start,node.test.end)}; ${slice(node.update.start,node.update.end)}) {\n` +
      `if (${yieldCondition}) return false;\n` +
      `batchCount++;\n${loopBody}\n}\n`;
    const postMode = ["fastIndex","slowIndex"].includes(loopVariable) ? "speed" : ["cleanupOwnerIndex","markerIndex","speedMarkerIndex","markerOwnerIndex"].includes(loopVariable) ? "read-only" : "full";
    steps.push({ label: loops[loopVariable], code, loop: true, checkpoint: "", postMode });
    cursor = node.end; label = "Chuẩn bị sau " + loops[loopVariable];
  }
  flush(end);
  if (steps.length < 15 || steps.filter(s=>s.loop).length !== Object.keys(loops).length) throw Error("Executor layout changed; review diagnostic stage map.");
  const rawPrefix = source.slice(fn.body.start+1,attempt.start);
  if (rawPrefix.split("$._PVS._findQEClipAtTicks(qeTrack,").length !== 2) throw Error("Review QE lookup transformation.");
  const speedHelper = fn.body.body.find(n => n.type === "FunctionDeclaration" && n.id.name === "setClipSpeed");
  if (!speedHelper || speedHelper.params[0].name !== "item") throw Error("Review speed dirty-item instrumentation.");
  const insertion = speedHelper.body.start + 1 - fn.body.start - 1;
  const instrumentedPrefix = rawPrefix.slice(0,insertion) + "\n        diagnosticTouch(item);\n" + rawPrefix.slice(insertion);
  const speedSignature = "function setClipSpeed(item, qeTrack, factor, desiredFrames, fps, tolerance, label, allowTerminalEndFallback)";
  const qeLookup = "$._PVS._findQEClipAtTicks(qeTrack, item.start.ticks, tolerance)";
  if (instrumentedPrefix.split(speedSignature).length!==2 || instrumentedPrefix.split(qeLookup).length!==2) throw Error("Review logical QE helper signature.");
  const prefix = instrumentedPrefix.replace(speedSignature, speedSignature.slice(0,-1)+", lookupTrackKey)")
    .replace(qeLookup, "diagnosticQEClipAtTicks(qeTrack, item.start.ticks, tolerance, lookupTrackKey)");
  const fastSupport = fs.readFileSync(path.join(__dirname,"diagnostic-fast-support.jsx"),"utf8").replace(/\r\n/g,"\n");
  const cleanup = source.slice(attempt.finalizer.start+1,attempt.finalizer.end-1);
  const catcher = source.slice(attempt.handler.body.start+1,attempt.handler.body.end-1);
  const suffix = source.slice(attempt.end,fn.body.end-1).replace(/return \$\._PVS\._result\(report\);/, "return report;");
  const hash = crypto.createHash("sha256").update(source).digest("hex");
  const generated = `// GENERATED by tools/Build-DiagnosticExecutor.js; do not hand-edit.\n// Stable host SHA256: ${hash}\n` +
    `(function () {\nvar session = null;\n$._PVS.diagnosticInfo = function () { return $._PVS._result({ok:true, revision:"staged-edit-v3", baseHash:"${hash}", active:!!session}); };\n` +
    `$._PVS.beginDiagnosticEdit = function (planPath, token, profile) {\nif(session)return $._PVS._result({ok:false,error:"DIAGNOSTIC_SESSION_ACTIVE"});\nif(!token || String(token).length>100)return $._PVS._result({ok:false,error:"DIAGNOSTIC_TOKEN_INVALID"});\nif(profile!==undefined && profile!=="baseline" && profile!=="fast" && profile!=="no-delay")return $._PVS._result({ok:false,error:"DIAGNOSTIC_PROFILE_INVALID"});\nvar diagnosticNoDelay=profile==="no-delay", diagnosticFast=profile==="fast" || diagnosticNoDelay, diagnosticBatchLimit=diagnosticNoDelay?20:diagnosticFast?100:20, diagnosticBatchBudgetMs=diagnosticNoDelay?250:diagnosticFast?600:200;\n` + prefix + "\n" + fastSupport +
    `\nvar ${Array.from(names).join(", ")};\n` + helpers.join("\n") + "\n" +
    steps.filter(s=>s.loop).map(s=>`var loopInitialized${steps.indexOf(s)} = false;`).join("\n") +
    `\nvar steps = [\n` + steps.map(s=>`{label:${JSON.stringify(s.label)},checkpoint:${JSON.stringify(s.checkpoint)},postMode:${JSON.stringify(s.postMode || "full")},run:function(){\n${s.code}\nreturn true;}}`).join(",\n") +
    `\n];\nvar stageIndex=0, expectedCall=0, expectedSignature=null, sequenceId=null, timings=[];\n` +
    `function signature(seq) {\nvar rows=[String(seq.sequenceID)], kinds=[seq.videoTracks,seq.audioTracks];\nfor(var k=0;k<kinds.length;k++)for(var t=0;t<kinds[k].numTracks;t++){var track=kinds[k][t];for(var c=0;c<track.clips.numItems;c++){var clip=track.clips[c];rows.push(k+":"+t+":"+String(clip.nodeId)+":"+String(clip.start.ticks)+":"+String(clip.end.ticks)+":"+String(clip.inPoint.ticks)+":"+String(clip.outPoint.ticks)+":"+String(readSpeedPercent(clip)));}}\nreturn rows.join("|");}\n` +
    `function rebind(seq){\nvar byId={},kinds=[seq.videoTracks,seq.audioTracks];\nfor(var k=0;k<kinds.length;k++)for(var t=0;t<kinds[k].numTracks;t++)for(var c=0;c<kinds[k][t].clips.numItems;c++){var clip=kinds[k][t].clips[c];byId[String(clip.nodeId)]=clip;}\nvar groups=[videoPieces,audioPieces,allVoicePieces,speechPieces];for(var g=0;g<groups.length;g++)if(groups[g])for(var i=0;i<groups[g].length;i++){if(g===2 && removeVoice!==undefined && i>removeVoice)continue;var fresh=byId[String(groups[g][i].nodeId)];if(fresh)groups[g][i]=fresh;}\nif(tailItems)for(var j=0;j<tailItems.length;j++){var tail=byId[String(tailItems[j].Item.nodeId)];if(tail)tailItems[j].Item=tail;}\nif(cleanupOwners && Number(cleanupOwnerIndex||0)<cleanupOwners.length)for(var oi=cleanupOwnerIndex||0;oi<cleanupOwners.length;oi++){var ownerItem=byId[cleanupOwners[oi].NodeId];if(!ownerItem)throw new Error("DIAGNOSTIC_MARKER_OWNER_MISSING");cleanupOwners[oi].Item=ownerItem;}\nif(qeSequence){qeSequence=qe.project.getActiveSequence();qeVideoTrack=qeSequence.getVideoTrackAt(0);qeAudioTrack=qeSequence.getAudioTrackAt(linkedTrackIndex);if(qeVoiceTrack)qeVoiceTrack=qeSequence.getAudioTrackAt(voiceTrackIndex);}\n}\n` +
    `function finish(e){\nif(e){${catcher}}\n${cleanup}\n${suffix}\n}\n` +
    `var initialSequence=app.project.activeSequence;if(!initialSequence)return $._PVS._result({ok:false,error:"DIAGNOSTIC_NO_ACTIVE_SEQUENCE"});\nsequenceId=String(initialSequence.sequenceID);expectedSignature=signature(initialSequence);\n` +
    `session={token:String(token),advance:function(call){\nif(Number(call)!==expectedCall)return {ok:false,done:false,error:"DIAGNOSTIC_CALL_ORDER",timelineMutated:timelineMutated};\nexpectedCall++;var started=(new Date()).getTime(),step=steps[stageIndex],checkpoint="";\ntry{var active=app.project.activeSequence;if(!active)throw new Error("DIAGNOSTIC_NO_ACTIVE_SEQUENCE");\nif(String(active.sequenceID)!==sequenceId)throw new Error("DIAGNOSTIC_SEQUENCE_CHANGED");\nvar checkStarted=(new Date()).getTime(),currentSnapshot=diagnosticFast?diagnosticSnapshot(active,true):null;\nif((diagnosticFast?currentSnapshot.signature:signature(active))!==expectedSignature)throw new Error("DIAGNOSTIC_TIMELINE_CHANGED_BETWEEN_BATCHES");\nvar checkMs=(new Date()).getTime()-checkStarted,rebindStarted=(new Date()).getTime();\nif(diagnosticFast)diagnosticRebind(active,currentSnapshot);else rebind(active);\nvar rebindMs=(new Date()).getTime()-rebindStarted;diagnosticDirtyItems={};diagnosticQeStats=diagnosticNewQeStats();\nvar workStarted=(new Date()).getTime(),complete=step.run(),workMs=(new Date()).getTime()-workStarted;if(complete){stageIndex++;checkpoint=step.checkpoint;}\nvar snapshotStarted=(new Date()).getTime(),afterSnapshot=diagnosticFast?diagnosticSnapshotAfter(active,currentSnapshot,step.postMode):null;expectedSignature=diagnosticFast?afterSnapshot.signature:signature(active);var snapshotMs=(new Date()).getTime()-snapshotStarted;\ntimings.push({stage:step.label,milliseconds:(new Date()).getTime()-started,complete:complete,checkMs:checkMs,rebindMs:rebindMs,workMs:workMs,snapshotMs:snapshotMs,qeLookupMs:diagnosticQeStats.milliseconds,qeQueries:diagnosticQeStats.queries,qeHits:diagnosticQeStats.hits,qeBuilds:diagnosticQeStats.builds,qeFallbacks:diagnosticQeStats.fallbacks,qeCacheReuses:diagnosticQeStats.reuses,qeCountChanges:diagnosticQeStats.countChanges,qeCandidateMisses:diagnosticQeStats.candidateMisses,qeInvalidLayouts:diagnosticQeStats.invalidLayouts,qeItemReads:diagnosticQeStats.itemReads,qeEarlyHits:diagnosticQeStats.earlyHits,qeNearestScans:diagnosticQeStats.nearestScans,snapshotStrategy:diagnosticFast?afterSnapshot.strategy:"full",snapshotDetailReads:diagnosticFast?afterSnapshot.detailReads:0});\nif(stageIndex===steps.length)return {ok:true,done:true,result:finish(null),timings:timings};\nreturn {ok:true,done:false,nextCall:expectedCall,stage:step.label,nextStage:steps[stageIndex].label,stageIndex:stageIndex,stageCount:steps.length,checkpoint:checkpoint,timelineMutated:timelineMutated,milliseconds:timings[timings.length-1].milliseconds};\n}catch(e){timings.push({stage:step.label,milliseconds:(new Date()).getTime()-started,failed:true});return {ok:false,done:true,result:finish(e),timings:timings};}\n},abort:function(){return {ok:false,done:true,result:finish(new Error("DIAGNOSTIC_STOPPED_PARTIAL_TIMELINE")),timings:timings};}};\nreturn $._PVS._result({ok:true,token:String(token),stageCount:steps.length,nextCall:0,nextStage:steps[0].label,profile:diagnosticFast?"fast":"baseline"});\n};\n` +
    `$._PVS.advanceDiagnosticEdit=function(token,call){if(!session || session.token!==String(token))return $._PVS._result({ok:false,done:false,error:"DIAGNOSTIC_SESSION_NOT_FOUND"});var response=session.advance(call);if(response.done)session=null;return $._PVS._result(response);};\n` +
    `$._PVS.abortDiagnosticEdit=function(token){if(!session || session.token!==String(token))return $._PVS._result({ok:false,error:"DIAGNOSTIC_SESSION_NOT_FOUND"});var response=session.abort();session=null;return $._PVS._result(response);};\n}());\n`;
  // $.evalFile may use the Windows codepage for a UTF-8 file without BOM.
  // Escape non-ASCII inside string literals, preserving literal values in ES3.
  if (generated.split("if (captionCleanupProbe < 5) {").length !== 2) throw Error("Review caption cleanup wait transformation.");
  const scheduled = generated.replace("if (captionCleanupProbe < 5) {", "if (!diagnosticNoDelay && captionCleanupProbe < 5) {")
    .replace('profile:diagnosticFast?"fast":"baseline"', 'profile:diagnosticNoDelay?"no-delay":diagnosticFast?"fast":"baseline"')
    .replace('var checkStarted=(new Date()).getTime(),currentSnapshot=', 'noteNative("before","snapshot");var checkStarted=(new Date()).getTime(),currentSnapshot=')
    .replace('var checkMs=(new Date()).getTime()-checkStarted', 'noteNative("after","snapshot");var checkMs=(new Date()).getTime()-checkStarted')
    .replace('var snapshotStarted=(new Date()).getTime(),afterSnapshot=', 'noteNative("before","snapshot");var snapshotStarted=(new Date()).getTime(),afterSnapshot=')
    .replace('var snapshotMs=(new Date()).getTime()-snapshotStarted', 'noteNative("after","snapshot");var snapshotMs=(new Date()).getTime()-snapshotStarted');
  const tokenizer = parser().tokenizer(scheduled,{ecmaVersion:5}), literalEdits=[];
  for(let token=tokenizer.getToken();token.type.label!=="eof";token=tokenizer.getToken()){
    if(token.type.label==="string")literalEdits.push([token.start,token.end,scheduled.slice(token.start,token.end).replace(/[^\x00-\x7f]/g,c=>"\\u"+c.charCodeAt(0).toString(16).padStart(4,"0"))]);
  }
  let asciiStrings=scheduled;
  literalEdits.reverse().forEach(e=>{asciiStrings=asciiStrings.slice(0,e[0])+e[2]+asciiStrings.slice(e[1]);});
  return asciiStrings.replace(/[ \t]+$/gm, "");
}
function output() {
  const root = path.join(__dirname,"..");
  return { target:path.join(root,"extension/jsx/diagnostic-executor.jsx"), text:generate(fs.readFileSync(path.join(root,"extension/jsx/host.jsx"),"utf8")) };
}
if(require.main===module){const generated=output();if(process.argv.includes("--check")){if(fs.readFileSync(generated.target,"utf8")!==generated.text)throw Error("DIAGNOSTIC_GENERATED_SOURCE_STALE");console.log("DIAGNOSTIC_GENERATED_SOURCE_CURRENT");}else {fs.writeFileSync(generated.target,generated.text);console.log("DIAGNOSTIC_EXECUTOR_GENERATED");}}
module.exports={generate,output};
