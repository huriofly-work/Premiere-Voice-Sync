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
// Instrument existing access points only, including cached sort key reads and
// comparisons, without adding native access.
function measurePrepare(code) {
  const wrapped = "function measured(){\n" + code + "\n}", ast = parser().parse(wrapped, { ecmaVersion: 5 });
  function property(node, name) { return node && node.type === "MemberExpression" && !node.computed && node.property.name === name; }
  function clipCollection(node) { return property(node, "clips") || (node.type === "Identifier" && /Clips$/.test(node.name)); }
  function render(node, parent, key) {
    if (node.type === "FunctionDeclaration" && node.id.name === "setClipSpeed") return wrapped.slice(node.start,node.end);
    const children = [];
    Object.keys(node).forEach(k => {
      const value = node[k];
      if (Array.isArray(value)) value.forEach(child => { if (child && child.type) children.push([child, k]); });
      else if (value && value.type) children.push([value, k]);
    });
    let value = wrapped.slice(node.start, node.end);
    children.sort((a,b) => b[0].start-a[0].start).forEach(([child,k]) => {
      value = value.slice(0,child.start-node.start) + render(child,node,k) + value.slice(child.end-node.start);
    });
    if (node.type === "MemberExpression" && !(parent && ((parent.type === "AssignmentExpression" && key === "left") || parent.type === "UpdateExpression"))) {
      let count = "", read = "";
      if (node.computed && property(node.object,"clips")) count = "clipItems";
      else if (property(node,"clips")) count = "clipCollectionReads";
      else if (property(node,"numItems") && clipCollection(node.object)) count = "clipCountReads";
      else if (property(node,"seconds")) read = property(node.object,"start") ? "startSecondsReads" : property(node.object,"end") ? "endSecondsReads" : "secondsReads";
      else if (property(node,"ticks")) read = "ticksReads";
      else if (property(node,"name") && /^(item|clip|originalMain|videoClip|audioClip|voiceItem|vItem|aItem|preservedV1Item)$/.test(wrapped.slice(node.object.start,node.object.end))) read = "nameReads";
      if (count) value = '(diagnosticCount("' + count + '"),' + value + ')';
      if (read) value = 'diagnosticRead("' + read + '",function(){return ' + value + ';})';
    }
    if (node.type === "CallExpression" && property(node.callee,"sort")) value = 'diagnosticSort(function(){return ' + value + ';})';
    if (node.type === "FunctionExpression" && parent && parent.type === "CallExpression" && property(parent.callee,"sort")) {
      const brace = value.indexOf("{");
      value = value.slice(0,brace+1) + 'diagnosticCount("comparatorCalls");' + value.slice(brace+1);
    }
    if (node.type === "ForStatement" && node.test && /(?:\.clips|\b\w*Clips)\.numItems/.test(wrapped.slice(node.test.start,node.test.end))) {
      value = "diagnosticEnumerationStart();try{" + value + "}finally{diagnosticEnumerationEnd();}";
    }
    if (node.type === "BlockStatement" && parent && parent.type === "ForStatement" && key === "body" && parent.test && /(?:\.clips|\b\w*Clips)\.numItems/.test(wrapped.slice(parent.test.start,parent.test.end))) {
      value = '{diagnosticCount("clipEnumerationItems");' + value.slice(1);
    }
    return value;
  }
  return render(ast.body[0].body,null,"").slice(2,-2);
}
// options.measure === false emits the same executor without trace counters; tests
// compare both builds to prove the counters add no native access.
function generate(source, options) {
  const measure = !(options && options.measure === false), instrument = measure ? measurePrepare : code => code;
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
    cleanupOwnerIndex: "Đọc marker nguồn", preOwnerIndex: "Ghi trước marker voice", preReviewIndex: "Ghi trước marker review",
    cutIndex: "Cắt V1–A1 linked", omitIndex: "Bỏ hình–A1 theo SRT đã lược", fastIndex: "Tăng speed V1–A1",
    moveIndex: "Dồn vị trí V1–A1", slowIndex: "Giảm speed V1–A1", reconcileIndex: "Đối chiếu mép V1–A1",
    voiceCutIndex: "Cắt voice A2", removeVoice: "Bỏ lát khoảng lặng A2", voiceMove: "Dồn voice A2",
    markerIndex: "Chuẩn bị marker voice", speedMarkerIndex: "Chuẩn bị marker tốc độ", markerOwnerIndex: "Cập nhật marker nguồn"
  };
  const boundaries = { voiceNames: "Hình V1–A1", fillRequests: "Voice A2", captionFile: "Marker", masterInOutReset: "Caption" };
  function insertMeasurement(code, point, replacement) {
    if (code.split(point).length !== 2) throw Error("Review diagnostic measurement placement: " + point);
    return code.replace(point, replacement);
  }
  const steps = []; let cursor = start, label = "Kiểm tra đầu vào và chuẩn bị";
  function flush(to, checkpoint) {
    let code = slice(cursor,to);
    if (measure && label === "Chuẩn bị sau " + loops.preOwnerIndex) {
      const prepareReview = "$._PVS._applyReviewMarkers(workingSequence, asArray(plan.reviewMarkers),";
      code = "var preparedReviewStats = null;\n" + insertMeasurement(code, prepareReview, "preparedReviewStats = " + prepareReview) + `
diagnosticDetail.unattachedMarkerCount = preparedReviewStats ? preparedReviewStats.unattachedMarkerCount : 0;
diagnosticDetail.unattachedReasons = [];
for (var ui = 0; preparedReviewStats && ui < preparedReviewStats.unattachedMarkers.length; ui++) {
    diagnosticDetail.unattachedReasons.push(diagnosticReviewReason(preparedReviewStats.unattachedMarkers[ui].reason));
}
diagnosticDetail.reviewOwnersLength = reviewOwners.length;
diagnosticDetail.reviewOwners = [];
for (var ri = 0; ri < reviewOwners.length; ri++) {
    var preparedOwner = reviewOwners[ri];
    diagnosticDetail.reviewOwners.push({
        key: diagnosticMarkerKey(preparedOwner.key), defer: !!preparedOwner.defer, error: !!preparedOwner.error,
        desired: preparedOwner.group ? preparedOwner.group.desired.length : 0, targets: preparedOwner.targets.length
    });
}`;
    }
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
    const ownerLoop = ["markerOwnerIndex","preOwnerIndex","preReviewIndex"].includes(loopVariable);
    const yieldCondition = ownerLoop ? "batchCount >= 1" :
      `!diagnosticNoDelay && (batchCount >= diagnosticBatchLimit || (batchCount > 0 && (new Date()).getTime() - batchStarted >= diagnosticBatchBudgetMs))`;
    let loopBody = slice(node.body.start+1,node.body.end-1);
    if (loopVariable === "markerOwnerIndex" && measure) {
      const point = "markerOwner.Group.collection =";
      if (loopBody.split(point).length !== 2) throw Error("Review marker owner measurement placement.");
      loopBody = loopBody.replace(point, "diagnosticMarkerOwner(markerOwner.Group, cleanupOwners.length);\n                " + point)
        .replace("markerCount += clipMarkerResult.count;", "diagnosticDetail.markerCommit = clipMarkerResult.timings;\n                markerCount += clipMarkerResult.count;");
    }
    if (measure && loopVariable === "preOwnerIndex") {
      loopBody = insertMeasurement(loopBody, "ownerByKey[projectItemKey(preOwner.Item)] = preOwner;",
        "var preKey = projectItemKey(preOwner.Item);\n            ownerByKey[preKey] = preOwner;");
      loopBody = insertMeasurement(loopBody, "preGroup.blocked = false;", `diagnosticDetail.markerCommit = preClipTiming;
            diagnosticDetail.preKey = diagnosticMarkerKey(preKey);
            diagnosticDetail.picture = !!preOwner.picture;
            diagnosticDetail.eligible = !!preOwner.eligible;
            diagnosticDetail.blocked = !!preGroup.blocked;
            diagnosticDetail.desired = preGroup.desired.length;
            diagnosticDetail.projected = !!projectedPieces;
            preGroup.blocked = false;`);
    }
    if (measure && loopVariable === "preReviewIndex") {
      const reviewGate = "if (sourceOwner && sourceOwner.eligible";
      loopBody = insertMeasurement(loopBody, reviewGate, `diagnosticDetail.reviewKey = diagnosticMarkerKey(reviewOwner.key);
            diagnosticDetail.sourceOwnerFound = !!sourceOwner;
            diagnosticDetail.sourceEligible = !!(sourceOwner && sourceOwner.eligible);
            diagnosticDetail.defer = !!reviewOwner.defer;
            diagnosticDetail.desired = reviewOwner.group ? reviewOwner.group.desired.length : 0;
            ${reviewGate}`);
      loopBody += "\ndiagnosticDetail.markerCommit = preReviewTiming;";
    }
    if (speedLoop) {
      // Baseline/fast count four atomic V1/A1 mutations after plan-only skips.
      // No-delay completes the whole stage before returning to the panel.
      const firstSpeedCall = `setClipSpeed(videoPieces[${loopVariable}],`;
      if (loopBody.split(firstSpeedCall).length !== 2) throw Error("Review speed work allowance placement.");
      loopBody = loopBody.replace(firstSpeedCall,
        `if (!diagnosticNoDelay && nativePairCount >= 4) return false;\n            nativePairCount++;\n            ${firstSpeedCall}`);
    }
    // Preserve for-loop test/update/continue semantics. A linked V1–A1 pair
    // stays atomic; yield only BEFORE the next whole iteration.
    const code = `if (!loopInitialized${index}) { ${init}; loopInitialized${index} = true; }\n` +
      `var batchCount = 0, ${speedLoop ? "nativePairCount = 0, " : ""}batchStarted = (new Date()).getTime();\n` +
      `for (; ${slice(node.test.start,node.test.end)}; ${slice(node.update.start,node.update.end)}) {\n` +
      `if (${yieldCondition}) return false;\n` +
      `batchCount++;\n${loopBody}\n}\n`;
    const postMode = speedLoop ? "speed" : ownerLoop || ["cleanupOwnerIndex","markerIndex","speedMarkerIndex"].includes(loopVariable) ? "read-only" : "full";
    steps.push({ label: loops[loopVariable], code, loop: true, checkpoint: "", postMode });
    cursor = node.end; label = "Chuẩn bị sau " + loops[loopVariable];
  }
  flush(end);
  if (steps.length < 15 || steps.filter(s=>s.loop).length !== Object.keys(loops).length) throw Error("Executor layout changed; review diagnostic stage map.");
  steps.forEach((step,index) => { step.measurePrepare = index === 0 || step.label.indexOf("Chuẩn bị") === 0; });
  const rawPrefix = source.slice(fn.body.start+1,attempt.start);
  if (rawPrefix.split("$._PVS._findQEClipAtTicks(qeTrack,").length !== 2) throw Error("Review QE lookup transformation.");
  const speedHelper = fn.body.body.find(n => n.type === "FunctionDeclaration" && n.id.name === "setClipSpeed");
  if (!speedHelper || speedHelper.params[0].name !== "item") throw Error("Review speed dirty-item instrumentation.");
  const insertion = speedHelper.body.start + 1 - fn.body.start - 1;
  let instrumentedPrefix = rawPrefix.slice(0,insertion) + "\n        diagnosticTouch(item);\n" + rawPrefix.slice(insertion);
  if (measure) {
    const ownerLookup = "var owner = ownerByKey[clipOwner.key];";
    instrumentedPrefix = insertMeasurement(instrumentedPrefix, ownerLookup, ownerLookup + "\n        var ownerKnown = !!owner;");
    const finalTiming = 'reviewTimings.push(phaseTiming(result, "post", "review", owner ? owner.index : -1));';
    instrumentedPrefix = insertMeasurement(instrumentedPrefix, finalTiming, `result.timings.ownerKey = diagnosticMarkerKey(clipOwner.key);
        result.timings.ownerKnown = ownerKnown;
        result.timings.ownerKeys = [];
        for (var ownerKey in ownerByKey) {
            if (ownerByKey.hasOwnProperty(ownerKey)) result.timings.ownerKeys.push(diagnosticMarkerKey(ownerKey));
        }
        ${finalTiming}`);
    instrumentedPrefix += `
function diagnosticMarkerKey(key) {
    return key.indexOf("path:") === 0 ? "path" : key;
}
function diagnosticReviewReason(reason) {
    // Only built-in allocation messages are safe to include in this trace.
    switch (reason) {
        case "Nhiều clip cùng phù hợp.":
        case "Không đọc được ánh xạ từ timeline sang nguồn.":
        case "Không có clip trong khoảng cảnh báo.":
        case "Không còn frame trống trên clip.":
            return reason;
        default:
            return "Lỗi khi chuẩn bị marker review.";
    }
}
`;
  }
  const speedSignature = "function setClipSpeed(item, qeTrack, factor, desiredFrames, fps, tolerance, label, allowTerminalEndFallback)";
  const qeLookup = "$._PVS._findQEClipAtTicks(qeTrack, item.start.ticks, tolerance)";
  if (instrumentedPrefix.split(speedSignature).length!==2 || instrumentedPrefix.split(qeLookup).length!==2) throw Error("Review logical QE helper signature.");
  const prefix = instrument(instrumentedPrefix.replace(speedSignature, speedSignature.slice(0,-1)+", lookupTrackKey)")
    .replace(qeLookup, "diagnosticQEClipAtTicks(qeTrack, item.start.ticks, tolerance, lookupTrackKey)"));
  const fastSupport = fs.readFileSync(path.join(__dirname,"diagnostic-fast-support.jsx"),"utf8").replace(/\r\n/g,"\n");
  const cleanup = source.slice(attempt.finalizer.start+1,attempt.finalizer.end-1);
  const catcher = source.slice(attempt.handler.body.start+1,attempt.handler.body.end-1);
  const suffix = source.slice(attempt.end,fn.body.end-1).replace(/return \$\._PVS\._result\(report\);/, "return report;");
  const hash = crypto.createHash("sha256").update(source).digest("hex");
  const ownerStage = ["markerOwnerIndex","preOwnerIndex","preReviewIndex"].map(key => "step.label===" + JSON.stringify(loops[key])).join("||");
  const reviewTrace = measure ? "if(reviewTimings.length && diagnosticDetail){diagnosticDetail.reviewCommits=reviewTimings;reviewTimings=[];}\n" : "";
  const generated = `// GENERATED by tools/Build-DiagnosticExecutor.js; do not hand-edit.\n// Stable host SHA256: ${hash}\n` +
    `(function () {\nvar session = null, failedMarkers = null;\n$._PVS.diagnosticInfo = function () { return $._PVS._result({ok:true, revision:"staged-edit-v3", baseHash:"${hash}", active:!!session}); };\n` +
    `$._PVS.beginDiagnosticEdit = function (planPath, token, profile, awaitAcceptance) {\nif(session)return $._PVS._result({ok:false,error:"DIAGNOSTIC_SESSION_ACTIVE"});\nif(!token || String(token).length>100)return $._PVS._result({ok:false,error:"DIAGNOSTIC_TOKEN_INVALID"});\nif(profile!==undefined && profile!=="baseline" && profile!=="fast" && profile!=="no-delay")return $._PVS._result({ok:false,error:"DIAGNOSTIC_PROFILE_INVALID"});\nvar diagnosticNoDelay=profile==="no-delay", diagnosticFast=profile==="fast" || diagnosticNoDelay, diagnosticBatchLimit=diagnosticNoDelay?0:diagnosticFast?100:20, diagnosticBatchBudgetMs=diagnosticNoDelay?0:diagnosticFast?600:200;\n` + prefix + "\n" + fastSupport +
    `\nvar ${Array.from(names).join(", ")};\n` + helpers.map(instrument).join("\n") + "\n" +
    steps.filter(s=>s.loop).map(s=>`var loopInitialized${steps.indexOf(s)} = false;`).join("\n") +
    `\nvar steps = [\n` + steps.map(s=>`{label:${JSON.stringify(s.label)},checkpoint:${JSON.stringify(s.checkpoint)},postMode:${JSON.stringify(s.postMode || "full")},measurePrepare:${s.measurePrepare},run:function(){\n${s.measurePrepare ? instrument(s.code) : s.code}\nreturn true;}}`).join(",\n") +
    `\n];\nvar stageIndex=0, expectedCall=0, expectedSignature=null, sequenceId=null, timings=[];\n` +
    `function signature(seq) {\nvar rows=[String(seq.sequenceID)], kinds=[seq.videoTracks,seq.audioTracks];\nfor(var k=0;k<kinds.length;k++)for(var t=0;t<kinds[k].numTracks;t++){var track=kinds[k][t];for(var c=0;c<track.clips.numItems;c++){var clip=track.clips[c];rows.push(k+":"+t+":"+String(clip.nodeId)+":"+String(clip.start.ticks)+":"+String(clip.end.ticks)+":"+String(clip.inPoint.ticks)+":"+String(clip.outPoint.ticks)+":"+String(readSpeedPercent(clip)));}}\nreturn rows.join("|");}\n` +
    `function rebind(seq){\nvar byId={},kinds=[seq.videoTracks,seq.audioTracks];\nfor(var k=0;k<kinds.length;k++)for(var t=0;t<kinds[k].numTracks;t++)for(var c=0;c<kinds[k][t].clips.numItems;c++){var clip=kinds[k][t].clips[c];byId[String(clip.nodeId)]=clip;}\nvar groups=[videoPieces,audioPieces,allVoicePieces,speechPieces];for(var g=0;g<groups.length;g++)if(groups[g])for(var i=0;i<groups[g].length;i++){if(g===2 && removeVoice!==undefined && i>removeVoice)continue;var fresh=byId[String(groups[g][i].nodeId)];if(fresh)groups[g][i]=fresh;}\nif(tailItems)for(var j=0;j<tailItems.length;j++){var tail=byId[String(tailItems[j].Item.nodeId)];if(tail)tailItems[j].Item=tail;}\nif(cleanupOwners && Number(cleanupOwnerIndex||0)<cleanupOwners.length)for(var oi=cleanupOwnerIndex||0;oi<cleanupOwners.length;oi++){var ownerItem=byId[cleanupOwners[oi].NodeId];if(!ownerItem)throw new Error("DIAGNOSTIC_MARKER_OWNER_MISSING");cleanupOwners[oi].Item=ownerItem;}\nif(qeSequence){qeSequence=qe.project.getActiveSequence();qeVideoTrack=qeSequence.getVideoTrackAt(0);qeAudioTrack=qeSequence.getAudioTrackAt(linkedTrackIndex);if(qeVoiceTrack)qeVoiceTrack=qeSequence.getAudioTrackAt(voiceTrackIndex);}\n}\n` +
    `function finish(e){\nif(e){${catcher}}\n${cleanup}\n${suffix}\n}\n` +
    `var initialSequence=app.project.activeSequence;if(!initialSequence)return $._PVS._result({ok:false,error:"DIAGNOSTIC_NO_ACTIVE_SEQUENCE"});\nsequenceId=String(initialSequence.sequenceID);expectedSignature=signature(initialSequence);\n` +
    `session={token:String(token),awaitAcceptance:awaitAcceptance===true,acceptedResult:false,retryMarkers:function(){markerRestorationFailures=[];restorePreOwners(true);return {ok:false,done:true,result:{ok:false,timelineMutated:timelineMutated,markerRestorationFailures:markerRestorationFailures}};},advance:function(call){\nif(this.acceptedResult)return {ok:false,error:"DIAGNOSTIC_AWAITING_ACCEPTANCE"};\nif(Number(call)!==expectedCall)return {ok:false,done:false,error:"DIAGNOSTIC_CALL_ORDER",timelineMutated:timelineMutated};\nexpectedCall++;var started=(new Date()).getTime(),step=steps[stageIndex],checkpoint="";diagnosticDetail=null;\ntry{var active=app.project.activeSequence;if(!active)throw new Error("DIAGNOSTIC_NO_ACTIVE_SEQUENCE");\nif(String(active.sequenceID)!==sequenceId)throw new Error("DIAGNOSTIC_SEQUENCE_CHANGED");\nvar checkStarted=(new Date()).getTime(),currentSnapshot=diagnosticFast?diagnosticSnapshot(active,true):null;\nif((diagnosticFast?currentSnapshot.signature:signature(active))!==expectedSignature)throw new Error("DIAGNOSTIC_TIMELINE_CHANGED_BETWEEN_BATCHES");\nvar checkMs=(new Date()).getTime()-checkStarted,rebindStarted=(new Date()).getTime();\nif(diagnosticFast)diagnosticRebind(active,currentSnapshot);else rebind(active);\nvar rebindMs=(new Date()).getTime()-rebindStarted;diagnosticDirtyItems={};diagnosticQeStats=diagnosticNewQeStats();diagnosticDetail=diagnosticNewDetail(step.measurePrepare,${ownerStage});\nvar workStarted=(new Date()).getTime(),complete=step.run(),workMs=(new Date()).getTime()-workStarted;if(complete){stageIndex++;checkpoint=step.checkpoint;}\n${reviewTrace}var snapshotStarted=(new Date()).getTime(),afterSnapshot=diagnosticFast?diagnosticSnapshotAfter(active,currentSnapshot,step.postMode):null;expectedSignature=diagnosticFast?afterSnapshot.signature:signature(active);var snapshotMs=(new Date()).getTime()-snapshotStarted;\ntimings.push({stage:step.label,milliseconds:(new Date()).getTime()-started,complete:complete,checkMs:checkMs,rebindMs:rebindMs,workMs:workMs,snapshotMs:snapshotMs,qeLookupMs:diagnosticQeStats.milliseconds,qeQueries:diagnosticQeStats.queries,qeHits:diagnosticQeStats.hits,qeBuilds:diagnosticQeStats.builds,qeFallbacks:diagnosticQeStats.fallbacks,qeCacheReuses:diagnosticQeStats.reuses,qeCountChanges:diagnosticQeStats.countChanges,qeCandidateMisses:diagnosticQeStats.candidateMisses,qeInvalidLayouts:diagnosticQeStats.invalidLayouts,qeItemReads:diagnosticQeStats.itemReads,qeEarlyHits:diagnosticQeStats.earlyHits,qeNearestScans:diagnosticQeStats.nearestScans,snapshotStrategy:diagnosticFast?afterSnapshot.strategy:"full",snapshotDetailReads:diagnosticFast?afterSnapshot.detailReads:0,detail:diagnosticDetail});\nif(stageIndex===steps.length)return {ok:true,done:true,result:finish(null),timings:timings};\nreturn {ok:true,done:false,nextCall:expectedCall,stage:step.label,nextStage:steps[stageIndex].label,stageIndex:stageIndex,stageCount:steps.length,checkpoint:checkpoint,timelineMutated:timelineMutated,milliseconds:timings[timings.length-1].milliseconds};\n}catch(e){timings.push({stage:step.label,milliseconds:(new Date()).getTime()-started,failed:true,detail:diagnosticDetail});return {ok:false,done:true,result:finish(e),timings:timings};}\n},abort:function(){return {ok:false,done:true,result:finish(new Error("DIAGNOSTIC_STOPPED_PARTIAL_TIMELINE")),timings:timings};}};\nreturn $._PVS._result({ok:true,token:String(token),stageCount:steps.length,nextCall:0,nextStage:steps[0].label,profile:diagnosticFast?"fast":"baseline"});\n};\n` +
    `$._PVS.advanceDiagnosticEdit=function(token,call){if(!session || session.token!==String(token))return $._PVS._result({ok:false,done:false,error:"DIAGNOSTIC_SESSION_NOT_FOUND"});var response=session.advance(call);if(response.done){if(session.awaitAcceptance && response.result && response.result.ok)session.acceptedResult=true;else {if(response.result && response.result.markerRestorationFailures)failedMarkers=session;session=null;}}return $._PVS._result(response);};\n` +
    `$._PVS.acceptDiagnosticEdit=function(token){if(!session || session.token!==String(token) || !session.acceptedResult)return $._PVS._result({ok:false,error:"DIAGNOSTIC_SESSION_NOT_FOUND"});session=null;return $._PVS._result({ok:true});};\n$._PVS.abortDiagnosticEdit=function(token){if(!session && failedMarkers && failedMarkers.token===String(token)){var retry=failedMarkers.retryMarkers();if(!retry.result.markerRestorationFailures.length)failedMarkers=null;return $._PVS._result(retry);}if(!session || session.token!==String(token))return $._PVS._result({ok:false,error:"DIAGNOSTIC_SESSION_NOT_FOUND"});var response=session.abort();if(response.result.markerRestorationFailures)failedMarkers=session;session=null;return $._PVS._result(response);};\n}());\n`;
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
function output(options) {
  const root = path.join(__dirname,"..");
  return { target:path.join(root,"extension/jsx/diagnostic-executor.jsx"), text:generate(fs.readFileSync(path.join(root,"extension/jsx/host.jsx"),"utf8"), options) };
}
if(require.main===module){const generated=output();if(process.argv.includes("--check")){if(fs.readFileSync(generated.target,"utf8")!==generated.text)throw Error("DIAGNOSTIC_GENERATED_SOURCE_STALE");console.log("DIAGNOSTIC_GENERATED_SOURCE_CURRENT");}else {fs.writeFileSync(generated.target,generated.text);console.log("DIAGNOSTIC_EXECUTOR_GENERATED");}}
module.exports={generate,output};
