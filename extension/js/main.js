(function () {
  "use strict";

  var nodeRequire = (window.cep_node && window.cep_node.require) ? window.cep_node.require : require;
  var fs = nodeRequire("fs");
  var path = nodeRequire("path");
  var childProcess = nodeRequire("child_process");
  var security = window.PvsSecurity;
  // Keep proof/text diagnostics in the full engine output. ExtendScript
  // needs geometry, identities and native checks, not the recognition graph.
  function projectHostInput(value, workflow) {
    var keys = workflow === "captions" ? ["ok", "workflow", "schemaVersion", "sequenceId", "snapshot", "captionSrtPath", "captionCueCount", "reviewMarkers", "reviewMarkerRanges"] :
      ["ok", "schemaVersion", "sequenceId", "frameRate", "settings", "speedWarningMinPercent", "speedWarningMaxPercent", "mainVideoClip", "mainVideoSourceEnd", "mainVideoSourceEndFrame", "plannedMainVideoEnd", "plannedMainVideoEndFrame", "voiceTrackIndex", "voiceClips", "linkedAudio", "segments", "visualSegments", "speedMergeTrial", "editBoundaryTrial", "pictureCueRevision", "pictureCueBoundaries", "pictureSegments", "editedSourceMap", "omittedReferenceCueIndices", "markers", "reviewMarkers", "captionSrtPath"];
    var compact = {};
    keys.forEach(function (key) { if (Object.prototype.hasOwnProperty.call(value, key)) compact[key] = value[key]; });
    if (workflow !== "captions") {
      if (Array.isArray(value.captions)) compact.captions = value.captions.map(function () { return null; });
      if (value.summary) {
        compact.summary = {};
        ["captionCueCount", "speedWarningCount"].forEach(function (key) { if (Object.prototype.hasOwnProperty.call(value.summary, key)) compact.summary[key] = value.summary[key]; });
      }
    }
    return compact;
  }
  function writeHostInput(value, workflow, folder) {
    var compact = projectHostInput(value, workflow);
    var target = path.join(folder, workflow === "captions" ? "caption-executor.json" : "timeline-executor.json");
    if (workflow !== "captions") {
      try {
        var progress = path.join(folder, "native-progress.jsonl");
        security.assertNoLinks(fs, path, progress, false);
        fs.writeFileSync(progress, "", { encoding: "utf8", flag: "wx" });
        compact.nativeProgressPath = progress;
        if (runContext) runContext.nativeProgressPath = progress;
      } catch (ignoreNativeTrace) { log("Không ghi được tiến độ lệnh Premiere; các kiểm tra và quyền dừng vẫn giữ nguyên.", "muted"); }
    }
    security.assertNoLinks(fs, path, target, false);
    fs.writeFileSync(target, JSON.stringify(compact), { encoding: "utf8", flag: "wx" });
    return target;
  }
  function readNativeProgress(owner) {
    if (!owner || !owner.nativeProgressPath) return null;
    var fd;
    try {
      security.assertNoLinks(fs, path, owner.nativeProgressPath, true);
      fd = fs.openSync(owner.nativeProgressPath, "r");
      var size = fs.fstatSync(fd).size, length = Math.min(2048, size);
      if (!length) return null;
      var buffer = nodeRequire("buffer").Buffer.alloc(length);
      fs.readSync(fd, buffer, 0, length, size - length);
      var lines = buffer.toString("utf8").split("\n");
      var row = JSON.parse(lines[lines.length - 2].replace(/^\uFEFF/, ""));
      if (typeof row.serial !== "number" || !isFinite(row.serial) || row.serial <= 0 || ["read-plan", "validate-plan", "snapshot", "qe-lookup", "set-speed", "move", "razor"].indexOf(row.operation) < 0 || ["before", "after"].indexOf(row.phase) < 0) return null;
      return row;
    } catch (ignoreNativeRead) { return null; }
    finally { if (fd !== undefined) try { fs.closeSync(fd); } catch (ignoreNativeClose) {} }
  }
  var state = {
    sequence: null,
    targetSrt: localStorage.getItem("pvs.targetSrt") || "",
    targetSrtExplicit: false,
    backend: null,
    backendPromise: null,
    backendChecking: false,
    workflowBusy: false,
    mode: "edit",
    captionSrt: "",
    captionSrtExplicit: false,
    captionConfigs: {},
    captionConfig: null,
    captionPlan: null,
    captionPlanError: null
  };
  var settingsStorageKey = "pvs.algorithm";
  var srtJoin = window.PvsSrtJoin ? window.PvsSrtJoin.panel({ state: state, document: document, window: window, fs: fs, path: path, security: security, inputError: inputError, changed: function () { if (inlineValidation && inlineValidation.fieldId === "srtJoinEnabled") closeWorkflowNotice(); } }) : null;
  var settingsSchemaKey = "pvs.algorithmSchema";
  var settingsSchemaVersion = "3";
  var settingDefaults = {
    minSpeed: 70, maxSpeed: 130, minDialogueGap: 0.5, voiceGroupGap: 2, maxCaptionCharacters: 42
  };
  var fixedAlgorithm = {
    silenceDb: -35,
    minSilence: 0.12,
    boundaryWindow: 0.12,
    confidence: 0.55,
    sentenceEndChars: ".?!;",
    voiceMapFrames: 2,
    validationFrames: 1,
    coverageFrames: 0,
    useCache: true
  };

  // All workflows use final timeline coordinates. Never place an audio-source
  // timestamp directly on a retimed timeline.
  function buildReviewMarkers(report, plan) {
    var issues = [], cues = report.reviewCueRanges || report.cues || [];
    var manualBlocks = report.autoEditManualReviewBlocks || (plan && plan.manualReviewBlocks) || [];
    function manualBlock(index) {
      for (var i = 0; i < manualBlocks.length; i++) if (Number(manualBlocks[i].cueIndex) === Number(index)) return manualBlocks[i];
      return null;
    }
    function add(start, end, reason, cueIndex, captionIndex, referenceCueIndex) {
      if (start === null || start === undefined || end === null || end === undefined ||
          !isFinite(Number(start)) || !isFinite(Number(end)) || Number(start) < 0 || Number(end) <= Number(start)) throw new Error("Không xác định được vị trí marker: " + reason);
      issues.push({ start: Number(start), end: Number(end), reason: reason, cueIndex: cueIndex || null, captionIndex: captionIndex || null, referenceCueIndex: referenceCueIndex || null, severity: "review" });
    }
    function cue(index, reason) {
      var matches = plan ? (plan.captions || []).filter(function (c) { return Number(c.SourceCueIndex) === Number(index); }) :
        cues.filter(function (c) { return Number(c.Index) === Number(index); });
      if (!matches.length) throw new Error("Không ánh xạ được marker cue " + index + ": " + reason);
      if (plan && manualBlock(index)) {
        // Manual proxies deliberately carry Confidence=0 and no word timing.
        // Those are edit-safety capabilities, not a diagnosis of every split
        // caption. Keep one review interval in final timeline coordinates.
        add(Math.min.apply(null, matches.map(function (c) { return Number(c.Start); })), Math.max.apply(null, matches.map(function (c) { return Number(c.End); })), reason, index);
        return;
      }
      matches.forEach(function (c) { add(c.Start, c.End, reason, index); });
    }
    function range(r, reason) {
      if (r.start === null || r.start === undefined || r.end === null || r.end === undefined || !isFinite(Number(r.start)) || !isFinite(Number(r.end)) || Number(r.start) < 0 || Number(r.end) <= Number(r.start)) throw new Error("Không xác định được vùng marker: " + reason);
      if (!plan) { add(r.start, r.end, reason); return; }
      var found = false;
      (plan.segments || []).forEach(function (s) {
        if (s.Kind !== "retime" || (r.sourceIndex !== undefined && Number(s.Chapter) !== Number(r.sourceIndex))) return;
        var start = Math.max(Number(r.start), Number(s.OriginalVoiceStart));
        var end = Math.min(Number(r.end), Number(s.OriginalVoiceEnd));
        if (end <= start) return;
        var shift = Number(s.NewVoiceStart) - Number(s.OriginalVoiceStart);
        add(start + shift, end + shift, reason); found = true;
      });
      if (!found) throw new Error("Không ánh xạ được vùng marker: " + reason);
    }
    [
      ["captionTimingReviewCues", "Chưa xác minh mốc DTW của caption"],
      ["acousticEditReviewCues", "Mốc căn voice theo âm thanh còn xung đột"],
      ["autoEditReferenceRecoveredCueIndices", "Đã phục hồi chữ SRT; giữ nhóm voice để kiểm tra lời và timing"],
      ["wordTimingRecoveredCues", "Đã phục hồi timestamp bị thiếu; cần nghe lại"]
    ].forEach(function (entry) { (report[entry[0]] || []).forEach(function (index) {
      if (entry[0] === "captionTimingReviewCues" && manualBlock(index)) return; // Covered by the block's timing review below.
      cue(index, entry[1]);
    }); });
    cues.forEach(function (c) {
      if (!manualBlock(c.Index) && c.Confidence !== undefined && Number(c.Confidence) < fixedAlgorithm.confidence) cue(c.Index, "Độ tin cậy căn lời thấp: " + Number(c.Confidence).toFixed(3));
      if (c.TimingRecovered) cue(c.Index, "Timestamp đã nội suy; cần nghe lại");
    });
    manualBlocks.forEach(function (block) {
      var blockParts = plan && (plan.captions || []).filter(function (c) { return Number(c.SourceCueIndex) === Number(block.cueIndex); });
      var measuredParts = blockParts && blockParts.filter(function (c) { return c.CaptionTimingQuality === "dtw" && c.IndependentSpeechEdges === true; });
      if (!measuredParts || !measuredParts.length) {
        cue(block.cueIndex, "Timing caption ước lượng trong vùng SRT " + block.cueIndices.join(", ") + "; cần rà thời gian hiển thị.");
      } else {
        var unresolved = null;
        blockParts.forEach(function (c) {
          if (c.CaptionTimingQuality === "dtw" && c.IndependentSpeechEdges === true) { unresolved = null; return; }
          if (unresolved) { unresolved.end = Number(c.End); return; }
          add(c.Start, c.End, "Timing caption ước lượng tại phần lời này; các phần đã căn DTW được xử lý tự động.", block.cueIndex);
          unresolved = issues[issues.length - 1];
        });
      }
      if (!plan) return;
      (block.captionCells || []).forEach(function (cell, cellIndex) {
        if ((cell.ReferenceCueIndices || []).length) return; // Proven SRT wording is not a recognition error.
        var parts = (plan.captions || []).filter(function (c) {
          return Number(c.SourceCueIndex) === Number(block.cueIndex) && c.ManualCaptionCellIndex !== undefined && Number(c.ManualCaptionCellIndex) === cellIndex;
        });
        if (!parts.length) throw new Error("Không ánh xạ được phần chữ nhận diện cần rà trong khối " + block.cueIndex);
        add(Math.min.apply(null, parts.map(function (c) { return Number(c.Start); })), Math.max.apply(null, parts.map(function (c) { return Number(c.End); })),
          "Chữ tự nhận diện chưa khớp SRT tại caption " + parts[0].Index + (parts.length > 1 ? "–" + parts[parts.length - 1].Index : "") + ": “" + cell.Text + "”. Cần đối chiếu chữ với voice.", block.cueIndex);
      });
    });
    (report.referenceReviewCues || []).forEach(function (r) {
      // Retaining mostly matched SRT text remains diagnostic information.
      // Independent timing, numeric and supplement warnings still create markers.
      if (String(r.reason).indexOf("Giữ chữ SRT khớp phần lớn") === 0) return;
      add(r.start, r.end, (String(r.reason).indexOf("Giữ chữ SRT") === 0 ? "" : "Chữ SRT khác nhận diện: ") + r.reason, r.cueIndex);
    });
    // Once the sentence is identified, SRT owns its text, including numbers.
    // Numeric ASR differences remain diagnostics, independent of timing checks.
    (report.editedReferenceRanges || []).forEach(function (r) {
      if (r.status === "omitted") range({ start: r.start, end: r.end, sourceIndex: r.chapter }, "Đã bỏ cue SRT " + r.cueIndices.join(", ") + "; nghe lại chỗ nối voice");
    });
    [
      ["captionTimingEstimatedRanges", "Timing ước lượng cấp câu; cần kiểm tra"],
      ["captionTimingLegacyRanges", "Timing dự phòng chưa xác minh DTW; cần nghe lại"],
      ["recognitionRejectedRanges", "Không thêm chữ ASR thiếu bằng chứng âm thanh; cần kiểm tra lời nói tại đây"],
      ["referenceSupplementEmptyRanges", "Chưa xác minh được lời bổ sung; kiểm tra caption tại đây"],
      ["referenceFallbackRanges", "Vùng SRT chưa khớp; đã dùng nhận diện dự phòng"]
    ].forEach(function (entry) { (report[entry[0]] || []).forEach(function (r) { range(r, entry[1] + (r.reason ? ": " + r.reason : "")); }); });
    (report.referenceSupplementRanges || []).forEach(function (r) {
      var captions = !plan && (report.reviewCaptionRanges || []).filter(function (c) {
        return c.Start < r.end && c.End > r.start && cues.some(function (source) { return Number(source.Index) === Number(c.SourceCueIndex) && source.RecognitionSupplement === true; });
      });
      if (captions && captions.length) {
        captions.forEach(function (c) {
          add(c.Start, c.End, "Chữ tự nhận diện được dùng tại caption " + c.Index + ": “" + c.Text + "”. Đoạn này chưa khớp SRT; hãy kiểm tra chữ.", null, c.Index);
        });
      } else range(r, "Đã thêm chữ tự nhận diện tại đoạn này vì chưa khớp SRT; hãy kiểm tra chữ.");
    });
    (report.captionOverlapReviewCues || []).forEach(function (index) { cue(index, "Đã điều chỉnh mép caption chồng nhau; cần nghe lại"); });
    if (plan) (plan.captionMappingReviewCues || []).forEach(function (index) { cue(index, "Mốc caption xung đột; đã giữ timing dự phòng"); });
    if (plan) (plan.sourceGapReviewRanges || []).forEach(function (gap) {
      var mapped = false;
      (plan.pictureSegments || plan.visualSegments || plan.segments || []).forEach(function (s) {
        var a = Math.max(Number(gap.sourceStartFrame), Number(s.SourceStartFrame)), b = Math.min(Number(gap.sourceEndFrame), Number(s.SourceEndFrame));
        if (!(b > a)) return;
        var scale = (s.NewEndFrame - s.NewStartFrame) / (s.SourceEndFrame - s.SourceStartFrame);
        add((s.NewStartFrame + (a - s.SourceStartFrame) * scale) / plan.frameRate, (s.NewStartFrame + (b - s.SourceStartFrame) * scale) / plan.frameRate,
          "Khoảng không lời nguồn giữa SRT " + gap.leftCue + "–" + gap.rightCue + " chưa tách: chưa có điểm cắt voice an toàn; cần rà tay");
        mapped = true;
      });
      if (!mapped) throw new Error("Không ánh xạ được khoảng không lời cần rà tay.");
    });
    return issues;
  }

  function manualReviewSummary(plan) {
    var blocks = plan.manualReviewBlocks || [], pending = {}, timingBlocks = 0;
    blocks.forEach(function (block) { (block.pendingReferenceCueIndices || []).forEach(function (index) { pending[String(index)] = true; }); });
    blocks.forEach(function (block) {
      var parts = (plan.captions || []).filter(function (c) { return Number(c.SourceCueIndex) === Number(block.cueIndex); });
      if (!parts.length || parts.some(function (c) { return c.CaptionTimingQuality !== "dtw" || c.IndependentSpeechEdges !== true; })) timingBlocks++;
    });
    return { timingBlocks: timingBlocks, pendingReferenceCues: Object.keys(pending).length };
  }

  function reviewPosition(start, end, reason, captionIndex) {
    if (!runContext || !isFinite(Number(start)) || !isFinite(Number(end)) || Number(end) <= Number(start)) return;
    var key = Number(start).toFixed(6) + ":" + Number(end).toFixed(6);
    var existing = runContext.reviewItems.filter(function (item) { return item.key === key; })[0];
    if (existing) { if (existing.reasons.indexOf(reason) < 0) existing.reasons.push(reason); return; }
    runContext.reviewItems.push({ key: key, start: Number(start), end: Number(end), captionIndex: captionIndex || null, reasons: [reason] });
  }
  function logReviewMarkers(result, markers, plan) {
    log("Marker timeline cần kiểm tra: " + Number(result.reviewMarkerCount || 0) + "; lỗi tạo marker: " + Number(result.reviewMarkerFailureCount || 0) + ".", Number(result.reviewMarkerFailureCount || 0) ? "warn" : "muted");
    (markers || []).forEach(function (marker) { reviewPosition(marker.start, marker.end, marker.reason, marker.captionIndex); });
    if (plan && plan.pictureCueRevision !== "srt-cue-picture-v1") (plan.visualSegments || plan.segments || []).forEach(function (segment) {
      if (segment.SpeedOutsideWarningRange) reviewPosition(segment.NewStart, segment.NewEnd, "Tốc độ hình ngoài ngưỡng đã chọn");
    });
    if (Number(result.reviewMarkerFailureCount || 0)) runWarning("Chưa tạo đủ marker; xem các vị trí trong Chi tiết.", true, "MARKER_MISSING");
    if (Number(result.reviewMarkerColorFailureCount || 0) || Number(result.clipMarkerColorFailureCount || 0)) runWarning("Một số marker chưa đúng màu; phân biệt bằng tên và ghi chú.", true, "MARKER_COLOR");
    if (Number(result.reviewMarkerCount || 0) || (markers || []).length) runWarning("Có vị trí cần nghe hoặc xem lại.", true, "POSITIONS");
  }

  function byId(id) { return document.getElementById(id); }
  var noticeHistory = [], noticeQueue = [], currentNotice = null, noticeSerial = 0;
  var runContext = null, recoveryContext = null, hostPending = 0, enginePending = 0;
  var externalPreference = localStorage.getItem("pvs.externalNotifications") !== "false";
  var soundPreference = localStorage.getItem("pvs.notificationSound") !== "false";
  var nativeBridge = null;
  var inlineValidation = null;
  var inputFeedback = { srtCandidates: "srtHint", captionSrtCandidates: "captionSrtHint", minSpeed: "minSpeedError", maxSpeed: "maxSpeedError", minDialogueGap: "minDialogueGapError", voiceGroupGap: "voiceGroupGapError", maxCaptionCharacters: "maxCaptionCharactersError", subtitleMaxCharacters: "subtitleMaxCharactersError", captionLanguage: "captionLanguageError", captionVoiceTrack: "captionVoiceTrackError", captionSourceMode: "captionSourceModeError", captionScopeMode: "captionScopeModeError" };
  inputFeedback.voiceLanguage = "voiceLanguageError";
  inputFeedback.srtJoinEnabled = "srtJoinHint";
  function inputError(message, fieldId) {
    var error = new Error(message);
    if (Object.prototype.hasOwnProperty.call(inputFeedback, fieldId)) error.pvsInputField = fieldId;
    return error;
  }
  function clearInlineValidation() {
    if (!inlineValidation) return;
    var previous = inlineValidation; inlineValidation = null;
    noticeAttribute(byId(previous.fieldId), "aria-invalid", "false");
    var hint = byId(inputFeedback[previous.fieldId]);
    if (hint) { hint.textContent = previous.text; hint.className = previous.className; hint.hidden = previous.hidden; noticeAttribute(hint, "role", "status"); }
  }
  function focusValidationField() {
    if (!inlineValidation || !document.hasFocus || !document.hasFocus()) return;
    var field = byId(inlineValidation.fieldId);
    if (field && !field.disabled && field.focus) field.focus();
  }
  function renderInlineValidation(item) {
    if (!Object.prototype.hasOwnProperty.call(inputFeedback, item.fieldId)) return;
    var hint = byId(inputFeedback[item.fieldId]), field = byId(item.fieldId);
    if (!hint || !field) return;
    if (!inlineValidation || inlineValidation.fieldId !== item.fieldId) {
      clearInlineValidation();
      inlineValidation = { fieldId: item.fieldId, text: hint.textContent, className: hint.className, hidden: hint.hidden };
    }
    hint.textContent = item.message; hint.className = "hint input-error"; hint.hidden = false;
    noticeAttribute(hint, "role", "alert"); noticeAttribute(field, "aria-invalid", "true");
    noticeAttribute(field, "aria-describedby", inputFeedback[item.fieldId]);
    if (/^(minSpeed|maxSpeed|minDialogueGap|voiceGroupGap|maxCaptionCharacters)$/.test(item.fieldId)) byId("editSettings").open = true;
    if (/^caption(SourceMode|ScopeMode|VoiceTrack)$/.test(item.fieldId)) byId("captionAudioOptions").open = true;
    if (item.fieldId === "captionVoiceTrack" && state.captionConfig && state.captionConfig.sourceMode === "tracks") byId("captionTrackPicker").open = true;
    focusValidationField();
  }
  function noticeEvent(item) {
    return { kind: item.kind === "approval" && !item.choice ? "warning" : item.kind || (item.choice ? "approval" : item.tone === "error" ? "failure" : item.tone === "ok" ? "completed" : "warning"), impact: item.impact, fatal: item.fatal, durationMilliseconds: item.durationMilliseconds || 0, reviewRequired: !!item.reviewRequired };
  }
  function noticeCardVisible(item) {
    var card=byId("workflowNotice");
    if(!item||currentNotice!==item||!card||card.hidden||document.visibilityState==="hidden")return false;
    if(card.getBoundingClientRect){
      var rect=card.getBoundingClientRect(),height=window.innerHeight||document.documentElement&&document.documentElement.clientHeight;
      if(rect.width<=0||rect.height<=0||rect.bottom<=0||(height&&rect.top>=height))return false;
    }
    return true;
  }
  function markNoticeObserved(item) {
    if(!noticeCardVisible(item)||item.seen)return;
    item.seen=true;persistNoticeHistory();renderNoticeHistory();
    if(nativeBridge)nativeBridge.hideToast();
    nativeStatus("observed");
    if(item.metrics&&item.metrics.notification)item.metrics.notification("native","observed");
  }
  function observeCurrentNotice() {
    var item=currentNotice;if(!item||item.seen)return;
    var visible=noticeCardVisible(item);
    if(visible&&document.hasFocus&&document.hasFocus())markNoticeObserved(item);
    if(!item.seen&&nativeBridge&&nativeBridge.observe)nativeBridge.observe(item,visible);
  }
  function syncTaskPresentation() {
    var progress=byId("workflowProgress"),card=byId("workflowNotice");
    if(progress&&card)progress.hidden=!card.hidden;
  }
  function noticeEnvironment(item,reopened) {
    var visible=noticeCardVisible(item);
    var observed=visible&&document.hasFocus&&document.hasFocus();
    return {background:!observed,panelVisible:visible,externalEnabled:externalPreference,soundEnabled:soundPreference,fieldAvailable:!reopened&&!!item.fieldId&&!!byId(inputFeedback[item.fieldId])};
  }
  function noticePresentation(item, reopened) {
    if (window.PvsNotificationPolicy) return window.PvsNotificationPolicy.route(noticeEvent(item), noticeEnvironment(item, reopened));
    // Keep feedback usable if the policy script failed to load.
    return { surface: item.choice ? "panel-choice" : item.fieldId && !reopened ? "field" : item.tone === "error" && (item.fatal || /^(changed|unknown)$/.test(item.impact)) ? "panel-alert" : "banner" };
  }
  function blockingNotice(item) { return !!item && item.surface === "panel-choice"; }
  function localFeedback(id, message, failed) {
    var element = byId(id);
    if (element) { element.textContent = message; element.className = "hint" + (failed ? " error" : ""); element.hidden = false; }
  }
  function nativeStatus(value) {
    var element=byId("nativeNotificationStatus");
    if(element)element.textContent=!externalPreference?"Đã tắt nhắc Windows. Kết quả vẫn được giữ trong panel.":value==="submitted"?"Đã gửi Windows; hiển thị theo quyền thông báo và Không làm phiền.":value==="observed"?"Kết quả đã được xem trong panel.":value==="available"?"Thông báo Windows sẵn sàng.":value==="pending"?"Chỉ nhắc khi hoàn tất hoặc cần bạn xử lý ở nền.":"Windows chưa cho gửi thông báo. Kết quả vẫn được giữ trong panel.";
  }
  function setExternalNotificationPreference(enabled) {
    externalPreference=!!enabled;
    try{localStorage.setItem("pvs.externalNotifications",String(externalPreference));}catch(ignore){}
    if(!externalPreference&&nativeBridge)nativeBridge.hideToast();
    var soundControl=byId("notificationSound");if(soundControl)soundControl.disabled=!externalPreference;
    nativeStatus("pending");
  }
  function setNotificationSoundPreference(enabled) {
    soundPreference=!!enabled;
    try{localStorage.setItem("pvs.notificationSound",String(soundPreference));}catch(ignore){}
  }
  function createNativeBridge(callbacks) {
    if(!window.PvsNativeNotifications||!childProcess.spawn)return null;
    var crypto=nodeRequire("crypto"),executable=path.join(extensionRoot(),"native","PvsNotifications.exe");
    return window.PvsNativeNotifications.create({
      sessionId:crypto.randomBytes(16).toString("hex"),parentId:process.pid,executable:executable,
      soundEnabled:function(){return externalPreference&&soundPreference;},
      spawn:function(file,args,options){return childProcess.spawn(file,args,options);},
      verify:function(){
        var lockPath=path.join(extensionRoot(),"native","helper-lock.json");
        security.assertNoLinks(fs,path,executable,false);security.assertNoLinks(fs,path,lockPath,false);
        var lock=JSON.parse(fs.readFileSync(lockPath,"utf8"));
        if(!/^[a-f0-9]{64}$/.test(lock.sha256)||crypto.createHash("sha256").update(fs.readFileSync(executable)).digest("hex")!==lock.sha256)throw Error("NOTIFICATION_HELPER_HASH_MISMATCH");
      },panelVisible:callbacks.panelVisible||noticeCardVisible,onStatus:callbacks.onStatus,onOpen:callbacks.onOpen,onObserved:callbacks.onObserved
    });
  }
  function getNativeBridge() {
    if(nativeBridge)return nativeBridge;
    try{nativeBridge=createNativeBridge({
      onStatus:function(value,item){nativeStatus(value);if(item&&item.metrics&&item.metrics.notification)item.metrics.notification("native",value);if(value==="unavailable"&&nativeBridge){nativeBridge.stop();nativeBridge=null;}},
      onObserved:markNoticeObserved,
      onOpen:function(item){
        if(currentNotice!==item||item.seen)return;
        try{if(window.__adobe_cep__)window.__adobe_cep__.requestOpenExtension("com.premierevoicesync.local.panel","");}catch(ignore){}
        displayNotice(item,true);
        if(byId("workflowNotice").scrollIntoView)byId("workflowNotice").scrollIntoView({block:"nearest"});
        observeCurrentNotice();
      }
    });}catch(ignore){nativeStatus("unavailable");}return nativeBridge;
  }
  function routeNativeNotice(item) {
    if(item.nativeRouted||item.reopened||item.seen||currentNotice!==item)return;
    var environment=noticeEnvironment(item,false),decision=window.PvsNotificationPolicy.route(noticeEvent(item),environment);
    if(item.metrics&&item.metrics.notification)item.metrics.notification("route",decision.toast,environment);
    item.nativeRouted=true;
    if(decision.toast!=="none"){
      var bridge=getNativeBridge();if(bridge)bridge.publish(item,true,environment.panelVisible,decision.toast!=="notification-center-only");
    }
  }
  var testNotificationBridge=null,testNotificationTimer=null;
  function testWindowsNotification() {
    if(testNotificationBridge)testNotificationBridge.stop();
    if(testNotificationTimer)window.clearTimeout(testNotificationTimer);
    localFeedback("notificationTestFeedback","Chuyển sang ứng dụng khác; thông báo kiểm thử sẽ gửi sau 5 giây.");
    testNotificationTimer=window.setTimeout(function(){
      try{
        testNotificationBridge=createNativeBridge({panelVisible:function(){return false;},onStatus:function(value){localFeedback("notificationTestFeedback",value==="submitted"?"Đã gửi thông báo kiểm thử theo thiết lập âm thanh hiện tại.":value==="available"?"Windows sẵn sàng; đang gửi thông báo kiểm thử.":"Windows chưa cho gửi thông báo; kiểm tra thiết lập thông báo.");},onOpen:function(){localFeedback("notificationTestFeedback","Đã nhận thao tác mở thông báo kiểm thử.");}});
        if(!testNotificationBridge)throw Error("NATIVE_UNAVAILABLE");
        testNotificationBridge.publish({test:true,runId:"test",kind:"completed",workflow:"other"},true,false);
        var own=testNotificationBridge;testNotificationTimer=window.setTimeout(function(){own.stop();if(testNotificationBridge===own)testNotificationBridge=null;},60000);
      }catch(ignore){localFeedback("notificationTestFeedback","Chưa dùng được thông báo Windows. Kết quả tác vụ vẫn nằm trong panel.",true);}
    },5000);
  }
  var stageLabels = { preflight: "Kiểm tra đầu vào", alignment: "Nhận diện và căn lời", planning: "Lập kế hoạch", timeline: "Dựng timeline và hậu kiểm", export: "Xuất audio", captions: "Thêm Caption Track", cleanup: "Dọn file tạm", unknown: "Chưa xác định" };
  function noticeAttribute(element, name, value) {
    if (element && element.setAttribute) element.setAttribute(name, value);
  }
  function focusNoticeButton() {
    var button = byId("closeWorkflowNotice");
    if (button && button.focus && document.hasFocus && document.hasFocus()) button.focus();
  }
  function safeNoticeSummary(tone) {
    return tone === "error" ? "Tác vụ chưa hoàn tất. Kiểm tra kết quả trước khi chạy lại." : tone === "warn" ? "Có cảnh báo cần kiểm tra." : "Thao tác đã hoàn tất.";
  }
  function persistNoticeHistory() {
    try {
      // Deliberately persist curated text only; never error.message, media names or transcripts.
      localStorage.setItem("pvs.notices.v1", JSON.stringify(noticeHistory.map(function (item) {
        return { id: item.id, tone: item.tone, at: item.at, count: item.count, seen: item.seen, impact: item.impact, stage: item.stage, code: item.code };
      })));
    } catch (ignoreNoticeStorage) { /* The live notice remains usable if storage is unavailable. */ }
  }
  function renderNoticeHistory() {
    var list = byId("noticeHistoryList"), badge = byId("noticeHistorySummary");
    if (badge) badge.textContent = "Cảnh báo gần đây (" + noticeHistory.filter(function (item) { return !item.seen && !item.restored; }).length + " chưa xem)";
    if (!list || !list.appendChild || !document.createElement) return;
    list.textContent = "";
    noticeHistory.forEach(function (item) {
      var button = document.createElement("button");
      button.type = "button"; button.className = "button secondary history-entry " + item.tone;
      button.textContent = new Date(item.at).toLocaleString("vi-VN") + " · " + (item.title || safeNoticeSummary(item.tone)) + (item.count > 1 ? " (" + item.count + " lần)" : "");
      button.addEventListener("click", function () {
        if (state.noticeChoice || (currentNotice && currentNotice.surface === "panel-alert" && currentNotice.id !== item.id)) {
          byId("noticeHistoryHint").textContent = "Đóng thông báo hiện tại trước khi xem thông báo khác."; return;
        }
        item.seen = true; persistNoticeHistory(); renderNoticeHistory(); displayNotice(item, true);
      });
      list.appendChild(button);
    });
  }
  function loadNoticeHistory() {
    try {
      var stored = JSON.parse(localStorage.getItem("pvs.notices.v1") || "[]");
      if (!Array.isArray(stored)) return;
      noticeHistory = stored.filter(function (item) {
        return item && /^(ok|warn|error)$/.test(item.tone) && /^(unchanged|changed|unknown|none)$/.test(item.impact) && Object.prototype.hasOwnProperty.call(stageLabels, item.stage) && /^[A-Z_]{1,60}$/.test(item.code) && typeof item.at === "number" && item.at <= Date.now() && Date.now() - item.at < 30 * 86400000;
      }).slice(0, 30).map(function (item, index) {
        return { id: "restored-" + index, tone: item.tone, at: item.at, count: Math.min(999, Math.max(1, Number(item.count) || 1)), seen: item.seen === true, impact: item.impact, stage: item.stage, code: item.code, message: safeNoticeSummary(item.tone) + "\nChi tiết kỹ thuật của phiên trước không được lưu; dùng file log đã xuất nếu có.", restored: true };
      });
    } catch (ignoreInvalidHistory) { noticeHistory = []; }
    renderNoticeHistory();
  }
  function requestIncidentAttention(item) {
    if(item.kind!=="validation"&&window.PvsNotificationPolicy)routeNativeNotice(item);
  }
  function displayNotice(item, reopened) {
    var wasCurrent = currentNotice === item;
    if (currentNotice && currentNotice !== item && nativeBridge) nativeBridge.clear(currentNotice);
    currentNotice = item; item.reopened = !!reopened;
    var presentation = noticePresentation(item, reopened);
    item.surface = presentation.surface;
    var important = blockingNotice(item);
    if (item.surface === "field") renderInlineValidation(item); else clearInlineValidation();
    byId("workflowNotice").className = "workflow-notice" + (important ? " attention" : "");
    noticeAttribute(byId("workflowNotice"), "role", important ? "alertdialog" : item.surface === "panel-alert" ? "alert" : "region");
    noticeAttribute(byId("workflowNotice"), "aria-modal", "false");
    byId("workflowNoticeTitle").textContent = item.title || (item.tone === "error" ? "Sự cố trước đó" : "Thông báo trước đó");
    byId("workflowNoticeMessage").textContent = item.message;
    byId("workflowNoticeCard").className = "workflow-notice-card " + item.tone;
    byId("workflowNoticeSymbol").textContent = item.tone === "error" ? "!" : item.tone === "warn" ? "△" : "✓";
    byId("workflowNoticeImpact").textContent = item.impact === "unchanged" ? "Timeline: chưa thay đổi" : item.impact === "changed" ? "Timeline / Project: đã thay đổi" : item.impact === "unknown" ? "Kết quả: chưa xác minh" : "";
    byId("workflowNoticeStage").textContent = item.stage && item.stage !== "unknown" ? "Bước: " + stageLabels[item.stage] : "";
    byId("workflowNoticeStage").hidden = !byId("workflowNoticeStage").textContent;
    byId("workflowNoticeDetails").hidden = item.choice || !(item.details || (item.reviewItems || []).length);
    byId("workflowNoticeDetails").open = false;
    byId("workflowNoticeTechnical").textContent = item.details || "";
    byId("workflowNoticeReview").textContent = (item.reviewItems || []).map(function (issue) {
      return (issue.captionIndex ? "Phụ đề " + issue.captionIndex + " · " : "") + reviewTime(issue.start) + "–" + reviewTime(issue.end) + "\n" + issue.reasons.join("; ");
    }).join("\n\n");
    byId("workflowNoticeReview").hidden = !(item.reviewItems || []).length;
    byId("workflowNoticeActionsNeeded").textContent = (item.issues || []).filter(function (issue) { return issue.code !== "POSITIONS"; }).map(function (issue) {
      return issue.code === "QUALITY_REVIEW" ? "Kiểm tra chữ và thời gian phụ đề tại các vùng được nêu trong danh sách hoặc báo cáo." : issue.message;
    }).join("\n");
    byId("workflowNoticeActionsNeeded").hidden = !(item.issues || []).length;
    byId("workflowNoticeAttention").textContent = "";
    byId("acceptWorkflowNotice").hidden = !item.choice;
    byId("acceptWorkflowNotice").textContent = item.acceptLabel || "Tiếp tục";
    byId("closeWorkflowNotice").textContent = item.cancelLabel || "Đóng thông báo";
    byId("closeWorkflowNotice").hidden = item.kind === "completed";
    byId("noticeViewLog").hidden = item.tone === "ok" || !!item.choice;
    byId("noticeExportLog").hidden = item.tone === "ok" || !!item.choice;
    byId("noticeExportLog").disabled = state.workflowBusy;
    byId("noticeCheckInputs").hidden = !(item.tone === "error" && !item.restored && !item.pickSrt);
    updateIncidentActions();
    byId("noticePickSrt").hidden = !item.pickSrt;
    byId("noticeReviewIssues").hidden = !item.reviewRequired;
    byId("noticePickSrt").disabled = state.workflowBusy;
    byId("workflowNotice").hidden = item.surface === "field";
    if (important && !wasCurrent) { state.noticeReturnFocus = document.activeElement; focusNoticeButton(); }
    if (!important && !reopened && (item.surface === "panel-alert" || item.kind === "completed") && byId("workflowNotice").scrollIntoView) byId("workflowNotice").scrollIntoView({ block: "nearest" });
    syncTaskPresentation();
    observeCurrentNotice();
    if (!reopened) requestIncidentAttention(item);
  }
  function closeWorkflowNotice() {
    if (state.noticeChoice) { chooseWorkflowNotice(false); return; }
    var closing = currentNotice;
    clearInlineValidation();
    if (closing) { closing.seen = true; persistNoticeHistory(); renderNoticeHistory(); }
    if (closing && nativeBridge) nativeBridge.clear(closing);
    currentNotice = null; byId("workflowNotice").hidden = true;
    syncTaskPresentation();
    var previous = state.noticeReturnFocus; state.noticeReturnFocus = null;
    if (previous && previous.focus && !previous.disabled && document.hasFocus && document.hasFocus()) previous.focus();
    if (noticeQueue.length) displayNotice(noticeQueue.shift(), false);
  }
  function showWorkflowNotice(title, message, tone, options) {
    options = options || {};
    tone = tone === "error" ? "error" : tone === "warn" ? "warn" : "ok";
    var item = { id: "notice-" + (++noticeSerial), title: String(title), message: String(message), tone: tone, at: Date.now(), count: 1, seen: false, code: options.code || (tone === "error" ? "OPERATION_FAILED" : tone === "warn" ? "REVIEW_REQUIRED" : "COMPLETED"), impact: options.impact || "none", stage: options.stage || "unknown", details: options.details || "", attention: tone === "error" || !!options.attention, choice: !!options.choice, acceptLabel: options.acceptLabel, cancelLabel: options.cancelLabel, pickSrt: !!options.pickSrt };
    item.durationMilliseconds = options.durationMilliseconds || 0;
    item.kind = options.kind || (item.choice ? "approval" : tone === "error" ? "failure" : tone === "ok" ? "completed" : "warning");
    if (item.kind === "completed") item.attention = true;
    item.metrics = runContext && runContext.metrics;
    item.workflow = runContext ? runContext.workflow : "other";
    item.fieldId = Object.prototype.hasOwnProperty.call(inputFeedback, options.fieldId) ? options.fieldId : null;
    item.fatal = !!options.fatal; item.reviewRequired = !!options.reviewRequired;
    item.reviewItems = options.reviewItems || [];
    item.issues = options.issues || [];
    if (item.kind === "validation") item.attention = false;
    var duplicate = (currentNotice && !currentNotice.restored && currentNotice.code === item.code && currentNotice.message === item.message && currentNotice.tone === item.tone && currentNotice.runId === (runContext && runContext.id) ? [currentNotice] : noticeHistory).filter(function (old) { return !old.restored && old.code === item.code && old.message === item.message && old.tone === item.tone && old.runId === (runContext && runContext.id); })[0];
    item.runId = runContext && runContext.id;
    if (duplicate && !item.choice) {
      duplicate.count++; persistNoticeHistory(); renderNoticeHistory();
      if (!currentNotice || byId("workflowNotice").hidden) displayNotice(duplicate, false);
      return duplicate;
    }
    if (item.kind !== "validation" && (item.tone === "error" || item.choice || item.reviewRequired || item.kind === "warning")) {
      noticeHistory.unshift(item); noticeHistory = noticeHistory.slice(0, 30); persistNoticeHistory(); renderNoticeHistory();
    }
    if (!item.choice && (state.noticeChoice || (currentNotice && currentNotice.tone === "error" && !byId("workflowNotice").hidden))) {
      noticeQueue.push(item); noticeQueue.sort(function (a, b) { return (b.tone === "error" ? 2 : b.tone === "warn" ? 1 : 0) - (a.tone === "error" ? 2 : a.tone === "warn" ? 1 : 0); });
      noticeQueue = noticeQueue.slice(0, 30); requestIncidentAttention(item); return item;
    }
    displayNotice(item, false); return item;
  }
  function confirmWorkflowNotice(title, message, acceptLabel, cancelLabel, attention) {
    if (state.noticeChoice) return Promise.reject(new Error("Một xác nhận trong panel vẫn đang chờ trả lời."));
    showWorkflowNotice(title, message, "warn", { choice: true, acceptLabel: acceptLabel || "Tiếp tục", cancelLabel: cancelLabel || "Hủy", attention: !!attention, code: "APPROVAL_REQUIRED" });
    return new Promise(function (resolve) { state.noticeChoice = resolve; updateStopControl(); });
  }
  function chooseWorkflowNotice(accepted) {
    if (!state.noticeChoice) return;
    var resolve = state.noticeChoice; state.noticeChoice = null;
    if (currentNotice) { currentNotice.choice = false; currentNotice.attention = false; }
    closeWorkflowNotice(); updateStopControl(); resolve(accepted === true);
  }
  function beginRun(workflow) {
    if (nativeBridge) nativeBridge.clear();
    if(currentNotice&&!state.noticeChoice){currentNotice=null;byId("workflowNotice").hidden=true;syncTaskPresentation();}
    runContext = { id: String(Date.now()) + "-" + (++noticeSerial), workflow: workflow, stage: "preflight", impact: "unchanged", warnings: [], issues: [], reviewItems: [], reviewRequired: false, lastProgress: Date.now(), fatal: false };
    runContext.startedAt = Date.now();
    noticeQueue = []; updateStopControl(); saveRecoveryJournal(); return runContext;
  }
  function updateStopControl() {
    var button = byId("stopWorkflow"), hint = byId("stopWorkflowHint");
    if (!button || !hint) return;
    var active = state.workflowBusy && !!runContext;
    button.hidden = !active; hint.hidden = !active || !runContext.cancelRequested;
    button.disabled = !active || !!runContext.cancelRequested || runContext.stage === "cleanup";
    button.textContent = active && runContext.cancelRequested ? "Đang yêu cầu dừng…" : "Dừng tác vụ";
    hint.textContent = active && runContext.cancelRequested ? "Chờ thao tác hiện tại kết thúc và dọn file tạm. Các thay đổi đã thực hiện không tự hoàn tác." : "Dừng ở bước an toàn tiếp theo. Các thay đổi đã thực hiện không tự hoàn tác.";
    var pause = byId("pauseWorkflow"), pauseHint = byId("pauseWorkflowHint");
    if (!pause || !pauseHint) return;
    pause.hidden = !active; pauseHint.hidden = !active || !(runContext.paused || runContext.pauseRequested || runContext.resuming);
    pause.disabled = !active || runContext.cancelRequested || runContext.pauseRequested || runContext.resuming || runContext.fatal || runContext.stage === "cleanup" || !!state.noticeChoice;
    pause.textContent = active && runContext.resuming ? "Đang kiểm tra để tiếp tục…" : active && runContext.paused ? "Tiếp tục" : active && runContext.pauseRequested ? "Đang yêu cầu tạm dừng…" : "Tạm dừng";
    noticeAttribute(pause, "aria-pressed", String(!!(active && runContext.paused)));
    pauseHint.textContent = active && runContext.paused ? "Đã tạm dừng. Không sửa timeline, đổi project/sequence hoặc mở lại panel. Dừng phát trước khi Tiếp tục; có thể Dừng tác vụ để hủy." : "Tạm dừng sau bước hiện tại; nhận diện và xuất audio cần hoàn tất bước đang chạy trước khi nghỉ.";
  }
  function requestWorkflowPause() {
    if (!state.workflowBusy || !runContext || runContext.cancelRequested || runContext.fatal || runContext.stage === "cleanup" || state.noticeChoice) return;
    if (runContext.paused) {
      if (runContext.resuming || !runContext.pauseResolver) return;
      runContext.resuming = true;
      var resume = runContext.pauseResolver; runContext.pauseResolver = null;
      status("Đang kiểm tra project, sequence và timeline trước khi tiếp tục…", "muted");
      updateStopControl(); resume(); return;
    }
    if (runContext.pauseRequested) return;
    runContext.pauseRequested = true;
    status("Đang yêu cầu tạm dừng. Chờ bước hiện tại kết thúc; vẫn có thể Dừng tác vụ.", "warn");
    updateStopControl(); updateRunHealth();
  }
  function wakePausedWorkflow() {
    if (!runContext || !runContext.pauseResolver) return;
    var resume = runContext.pauseResolver; runContext.pauseResolver = null; resume();
  }
  async function readWorkflowPauseState() {
    var result = await evalHost("$._PVS.workflowPauseState()");
    if (!result.ok || typeof result.state !== "string" || !result.state) throw new Error("WORKFLOW_PAUSE_STATE_UNAVAILABLE: " + (result.error || "Không đọc được trạng thái để tạm dừng/tiếp tục an toàn."));
    return result.state;
  }
  async function waitForWorkflowPause() {
    throwIfStopRequested();
    var owner = runContext;
    if (!owner || !owner.pauseRequested) return;
    var before = await readWorkflowPauseState();
    throwIfStopRequested();
    if (owner.fatal) throw new Error("Tác vụ dừng do lỗi giao diện.");
    owner.pauseRequested = false; owner.paused = true;
    if (owner.metrics && owner.metrics.pause) owner.metrics.pause(true);
    status("Đã tạm dừng. Bấm Tiếp tục để kiểm tra trạng thái và làm tiếp, hoặc Dừng tác vụ để hủy.", "warn");
    updateStopControl(); updateRunHealth();
    try {
      await new Promise(function (resolve) { owner.pauseResolver = resolve; });
      throwIfStopRequested();
      if (owner.fatal) throw new Error("Tác vụ dừng do lỗi giao diện.");
      var after;
      try { after = await readWorkflowPauseState(); }
      catch (resumeError) { if (!resumeError.pvsCancelled) owner.impact = "unknown"; throw resumeError; }
      if (after !== before) {
        owner.impact = "unknown";
        throw new Error("WORKFLOW_CHANGED_WHILE_PAUSED: Project, sequence hoặc trạng thái timeline đã thay đổi khi tạm dừng. Đã chặn tiếp tục; hãy kiểm tra/khôi phục trước khi chạy lại.");
      }
      throwIfStopRequested();
      status("Đang tiếp tục · " + stageLabels[owner.stage] + ".", "muted");
    } finally {
      if (owner.metrics && owner.metrics.pause) owner.metrics.pause(false);
      owner.pauseResolver = null; owner.paused = false; owner.resuming = false;
      owner.lastProgress = Date.now(); updateStopControl(); updateRunHealth();
    }
  }
  function stoppedError() {
    var error = new Error("Đã dừng tác vụ theo yêu cầu."); error.pvsCancelled = true; return error;
  }
  function throwIfStopRequested() {
    if (runContext && runContext.cancelRequested && !runContext.fatal) throw stoppedError();
  }
  function requestWorkflowStop() {
    if (!state.workflowBusy || !runContext || runContext.cancelRequested || runContext.stage === "cleanup") return;
    runContext.cancelRequested = true; runContext.cancelStage = runContext.stage;
    wakePausedWorkflow();
    if (state.noticeChoice) chooseWorkflowNotice(false);
    if (runContext.engineRequest) {
      try { signalEngineStop(runContext.engineRequest); }
      catch (error) { log("Không gửi được yêu cầu dừng bộ xử lý; sẽ chờ bước hiện tại kết thúc. " + error.message, "warn"); }
    }
    status("Đang yêu cầu dừng. Chờ thao tác hiện tại trả về; chưa thể chạy tác vụ khác.", "warn");
    updateStopControl();
  }
  function signalEngineStop(request) {
    security.assertNoLinks(fs, path, request.cancelPath, false);
    fs.writeFileSync(request.cancelPath, "stop", { encoding: "utf8", flag: "w" });
  }
  function reportRunCancelled() {
    var context = runContext;
    if (context.impact === "changed" || context.impact === "unknown") recoveryContext = context;
    var message = context.impact === "unchanged" ? "Đã dừng theo yêu cầu. Timeline chưa bị thay đổi bởi tác vụ này." : "Các thay đổi đã thực hiện chưa được hoàn tác. Kiểm tra hoặc khôi phục timeline trước khi chạy lại.";
    status(message, "warn");
    showWorkflowNotice("Đã dừng tác vụ", message, "warn", { kind: "cancelled", code: "WORKFLOW_CANCELLED", impact: context.impact, stage: context.cancelStage || context.stage, details: context.warnings.join("\n") });
  }
  function runStage(stage) {
    if (stage !== "cleanup") throwIfStopRequested();
    if (runContext) { runContext.stage = stage; runContext.lastProgress = Date.now(); }
    updateStopControl();
  }
  function runWarning(message, reviewRequired, code) {
    if (runContext && runContext.warnings.indexOf(message) < 0) runContext.warnings.push(message);
    if (runContext && reviewRequired) {
      runContext.reviewRequired = true;
      code = code || "QUALITY_REVIEW";
      if (!runContext.issues.some(function (issue) { return issue.code === code; })) runContext.issues.push({ code: code, message: message, action: "review-result", impact: runContext.impact, blocksRetry: false, resolved: false });
    }
  }
  function reviewTime(value) {
    var milliseconds = Math.round(Number(value) * 1000), seconds = Math.floor(milliseconds / 1000);
    function pad(number, length) { return ("000" + number).slice(-length); }
    return pad(Math.floor(seconds / 3600), 2) + ":" + pad(Math.floor(seconds / 60) % 60, 2) + ":" + pad(seconds % 60, 2) + "." + pad(milliseconds % 1000, 3);
  }
  function preservedRecognitionNotice(report, captionOnly) {
    var tasks = report.recognitionReviewTasks || [];
    var positions = tasks.map(function (task) { return "Voice " + (Number(task.chapter) + 1) + ": " + reviewTime(task.start) + "–" + reviewTime(task.end); });
    var message = (captionOnly ? "Chưa có caption đủ căn cứ để thêm; cần kiểm tra hoặc tạo phụ đề thủ công." : "Chưa đủ căn cứ ghép hình với voice; cần dựng thủ công, chưa dựng hoặc tạo caption cho phạm vi này.") + " Timeline được giữ nguyên.\n" + positions.join("\n");
    log(message, "warn");
    runContext.reviewItems = tasks.map(function (task) { return {start:Number(task.start),end:Number(task.end),reasons:[captionOnly ? "Chưa xác minh được lời nhận diện; cần tạo hoặc sửa phụ đề thủ công." : "Chưa xác định được vùng hình tương ứng; cần dựng thủ công."]}; });
    runWarning("Cần xử lý thủ công phạm vi được liệt kê; timeline được giữ nguyên.", true);
    runContext.resultHeadline = captionOnly ? "Đã phân tích — cần tạo phụ đề thủ công." : "Đã phân tích — cần dựng thủ công.";
    return message;
  }
  function inputMessage(raw, fieldId) {
    if (/^(srtCandidates|captionSrtCandidates)$/.test(fieldId)) return /chồng|đảo|timestamp/i.test(raw) ? "Kiểm tra thứ tự và thời gian trong file SRT đã chọn." : "Chọn file SRT đúng nội dung và ngôn ngữ lời nói.";
    if (fieldId === "srtJoinEnabled") return "Kiểm tra danh sách, thứ tự và cách nối thời gian của các file SRT.";
    if (/^caption(SourceMode|ScopeMode|VoiceTrack)$/.test(fieldId)) return "Chọn nguồn audio và phạm vi có lời nói, rồi cập nhật đầu vào.";
    return /[A-Z_]{5,}|[A-Z]:[\\/]|\n/.test(raw) ? "Kiểm tra giá trị đã chọn; xem chi tiết trong nhật ký nếu cần." : raw;
  }
  function reportRunFailure(error, title, fatal) {
    var context = runContext || { impact: "none", stage: "unknown" };
    fatal = !!fatal || !!context.fatal;
    if (context.impact === "changed" || context.impact === "unknown") recoveryContext = context;
    var raw = String(error && error.message || error || "Không xác định được nguyên nhân.");
    var message = /SUBTITLE_RECOGNITION_TAIL_UNVERIFIED|SUBTITLE_EDGE_RETRY_INVALID|SUBTITLE_RECOGNITION/.test(raw) ? "Chưa xác minh đầy đủ lời nhận diện trong vùng audio. Hãy kiểm tra vùng chọn và phần lời nói ở cuối; tác vụ đã dừng để tránh tạo subtitle thiếu." : /SRT|\.srt|subtitle.*file/i.test(raw) ? "Không xử lý được SRT. Kiểm tra file đã chọn, nội dung và quyền truy cập rồi kiểm tra lại đầu vào." : /ENOENT|không tìm thấy|không mở được/i.test(raw) ? "Không truy cập được một tài nguyên cần thiết. Kiểm tra file nguồn, ổ đĩa và bộ xử lý rồi thử kiểm tra lại đầu vào." : "Tác vụ đã dừng do lỗi. Xem chi tiết và nhật ký để xác định bước cần khắc phục.";
    if (/WORKFLOW_CHANGED_WHILE_PAUSED/.test(raw)) message = "Project, sequence hoặc trạng thái timeline đã thay đổi khi tạm dừng. Tool đã chặn tiếp tục để tránh dựng sai.";
    if (/WORKFLOW_PAUSE_STATE_UNAVAILABLE/.test(raw)) message = "Không xác minh được trạng thái để tạm dừng/tiếp tục an toàn. Tác vụ đã dừng; xem chi tiết để kiểm tra.";
    if (context.impact === "changed") message = "Tác vụ dừng khi timeline hoặc Project đã thay đổi. Kiểm tra hoặc khôi phục bản đã lưu trước khi chạy lại.";
    if (context.impact === "unknown") message = "Chưa xác minh được kết quả của thao tác vừa chạy. Kiểm tra timeline, phụ đề và trạng thái audio trước khi chạy lại.";
    var fieldId = null;
    if (!fatal && context.impact === "unchanged" && context.stage === "preflight") fieldId = error && error.pvsInputField || (/SRT/i.test(raw) ? context.workflow === "captions" ? "captionSrtCandidates" : "srtCandidates" : null);
    log(raw, "error");
    status(fieldId ? "Cần sửa mục được đánh dấu." : "Tác vụ chưa hoàn tất. Xem hướng xử lý bên dưới.", "error");
    showWorkflowNotice(title, fieldId ? inputMessage(raw, fieldId) : message, "error", { kind: fieldId ? "validation" : "failure", fieldId: fieldId, fatal: fatal, impact: context.impact, stage: context.stage, code: "WORKFLOW_FAILED", details: raw, reviewItems: context.reviewItems || [], pickSrt: !fieldId && context.impact === "unchanged" && /SRT/i.test(raw) });
  }
  function finishRunNotice(title, message, warnings) {
    warnings = (runContext ? runContext.warnings : []).concat(warnings || []);
    if (runContext && runContext.fatal) { reportRunFailure(new Error("Lỗi giao diện trong tác vụ; cần kiểm tra kết quả thực tế trước khi chạy lại."), "Tác vụ cần kiểm tra"); return; }
    var warn = !!(runContext && runContext.reviewRequired);
    var positions = runContext ? runContext.reviewItems.slice().sort(function (a, b) { return a.start - b.start || a.end - b.end; }) : [];
    var headline = runContext && runContext.resultHeadline || "Đã hoàn tất.";
    var regionCount = 0, coveredEnd = -1;
    positions.forEach(function (position) { if (position.start >= coveredEnd) regionCount++; coveredEnd = Math.max(coveredEnd, position.end); });
    var summary = warn ? (positions.length ? "Có " + regionCount + " vùng cần xem hoặc nghe lại; mở danh sách bên dưới trước khi lưu project." : "Kết quả cần được kiểm tra trước khi lưu project; mở Chi tiết để xem lý do.") : "Xem và nghe lại trước khi lưu project.";
    if (warn && runContext.issues.some(function (issue) { return issue.code === "REFERENCE_NOT_RETAINED"; })) summary = "Không giữ được chữ từ SRT; toàn bộ phụ đề dùng chữ tự nhận diện. Kiểm tra chữ trước khi lưu project.";
    if (warn && runContext.issues.some(function (issue) { return issue.code === "RECOVERY_STORAGE"; })) summary = "Không lưu được trạng thái phục hồi của lần chạy. Kiểm tra timeline trước khi đóng hoặc mở lại panel.";
    if (warn && runContext.issues.some(function (issue) { return issue.code === "MARKER_MISSING"; })) summary = summary.replace(/\.$/, "") + "; một số vị trí chưa có marker trên timeline.";
    log("Hoàn tất · Chương trình không tự lưu project.", "ok");
    showWorkflowNotice(headline, summary, warn ? "warn" : "ok", { kind: "completed", reviewRequired: warn, reviewItems: positions, issues: runContext ? runContext.issues.slice() : [], details: [message].concat(warnings).join("\n"), stage: "cleanup", durationMilliseconds: runContext ? Date.now() - runContext.startedAt : 0 });
  }
  function appendCleanupNotice(error) {
    if (!currentNotice || currentNotice.tone !== "error") return;
    currentNotice.details += "\nDọn file tạm: " + String(error.message || error);
    displayNotice(currentNotice, true);
  }
  async function captionTrackCount(sequenceId) {
    // Read only. Include In/Out and temporary bins so a failed export/import is not mistaken for an untouched project.
    // The CEP Sequence DOM does not expose captionTracks on every Premiere build.
    // null means unavailable, never an assertion that the sequence has zero captions.
    var script = '(function(){try{var s=app.project&&app.project.activeSequence;if(!s||String(s.sequenceID)!==' + jsxString(sequenceId) + ')return $._PVS._result({ok:false,error:"Active sequence changed"});var n=0,r=app.project.rootItem;for(var i=0;i<r.children.numItems;i++)if(String(r.children[i].name).indexOf("PVS_TEMP_SUBTITLE_")===0)n++;var c=s.captionTracks,ct=c===undefined||c===null?null:c.numTracks;if(c!==undefined&&c!==null&&(typeof ct!=="number"||!isFinite(ct)||ct<0||Math.floor(ct)!==ct))throw new Error("Invalid caption track count");var ip=s.getInPoint(),op=s.getOutPoint();if(ip===null||ip===undefined||String(ip).replace(/\\s/g,"")===""||op===null||op===undefined||String(op).replace(/\\s/g,"")==="")throw new Error("Missing sequence In/Out");return $._PVS._result({ok:true,count:ct,bins:n,inPoint:Number(ip),outPoint:Number(op)});}catch(e){return $._PVS._result({ok:false,error:String(e)});}}())';
    var result = await evalHost(script);
    if (!result.ok || (result.count !== null && (!Number.isInteger(result.count) || result.count < 0)) || !Number.isInteger(result.bins) || result.bins < 0 || !Number.isFinite(result.inPoint) || !Number.isFinite(result.outPoint)) throw new Error("Không đọc được trạng thái caption/In/Out để xác minh trước thao tác. Tool chưa thực hiện bước tiếp theo." + (result.error ? " Chi tiết: " + result.error : ""));
    return JSON.stringify({ count: result.count, bins: result.bins, inPoint: result.inPoint, outPoint: result.outPoint });
  }
  function saveRecoveryJournal() {
    try {
      var context = recoveryContext || runContext;
      if (context) localStorage.setItem("pvs.recovery.v1", JSON.stringify({ workflow: context.workflow, at: Date.now(), audioRecoveryPath: context.audioRecoveryPath || null }));
      else if (localStorage.removeItem) localStorage.removeItem("pvs.recovery.v1");
    } catch (ignoreRecoveryStorage) { runWarning("Không lưu được trạng thái kiểm tra sau lỗi; hãy kiểm tra timeline trước khi mở lại panel.", true, "RECOVERY_STORAGE"); }
  }
  async function checkIncidentInputs() {
    if (state.workflowBusy || hostPending || enginePending) return;
    var recovery = recoveryContext;
    var manualCaptionReview = recovery && recovery.workflow === "captions" && recovery.captionCount && JSON.parse(recovery.captionCount).count === null;
    if (recovery && (recovery.restored || manualCaptionReview)) {
      var recoveryMessage = recovery.restored ? "Lần chạy trước chưa được xác nhận an toàn." : "Chương trình không tự xác minh được phụ đề sau lỗi.";
      var approved = await confirmWorkflowNotice("Đã kiểm tra hoặc khôi phục timeline?", recoveryMessage + " Chỉ tiếp tục sau khi thao tác cũ kết thúc và bạn đã kiểm tra timeline, phụ đề cùng trạng thái audio.", "Đã kiểm tra — Xác minh", "Để sau");
      if (!approved) return;
    }
    setWorkflowBusy(true);
    try {
      if (recovery) {
        if (recovery.workflow === "edit") {
          var sequence = await scanSequence();
          if (!recovery.restored && JSON.stringify(sequence) !== recovery.baseline) throw new Error("Template chưa trở lại trạng thái trước lần dựng lỗi. Hãy Undo hoặc mở lại template đã lưu và kiểm tra lại.");
        } else {
          if (recovery.audioRecoveryPath) {
            var recoveryRoot = path.join(applicationDataRoot(), "Jobs");
            if (!isInside(recovery.audioRecoveryPath, recoveryRoot) || !/\.audio-recovery\.json$/.test(recovery.audioRecoveryPath)) throw new Error("Đường dẫn khôi phục audio không thuộc thư mục Jobs.");
            security.assertNoLinks(fs, path, recovery.audioRecoveryPath, true);
          }
          var pendingExport = await evalHost("$._PVS.restorePendingCaptionAudioExport(" + jsxString(recovery.audioRecoveryPath || "") + ")");
          if (!pendingExport.ok && !pendingExport.restored) throw new Error(pendingExport.error || "Chưa khôi phục được phiên xuất audio trước.");
          var range = await scanCaptionRange();
          if (!recovery.restored && (range.sequenceId !== recovery.sequenceId || range.snapshot !== recovery.baseline || await captionTrackCount(range.sequenceId) !== recovery.captionCount)) throw new Error("Caption, timeline, In/Out hoặc bin tạm chưa trở lại trạng thái trước lỗi. Hãy kiểm tra/khôi phục rồi xác minh lại.");
        }
        recoveryContext = null; saveRecoveryJournal();
        if (recovery.audioRecoveryPath) {
          cleanupStaleJobs();
          if (recoveryContext) throw new Error("Còn nhật ký khôi phục audio khác. Hãy kiểm tra lần lượt trước khi chạy tác vụ mới.");
        }
      } else {
        if (state.mode === "captions") await scanCaptionRange(); else await scanSequence();
      }
      closeWorkflowNotice(); status("Đầu vào sẵn sàng.", "ok");
    } catch (error) {
      log(String(error.message || error), "error");
      showWorkflowNotice("Chưa thể chạy tiếp", recovery ? "Trạng thái timeline chưa được xác minh an toàn. Kiểm tra hoặc khôi phục rồi xác minh lại." : "Kiểm tra nguồn và phạm vi đang chọn; mở Chi tiết nếu cần.", "error", { code: "RECOVERY_REQUIRED", impact: recovery ? "unknown" : "unchanged", details: String(error.message || error) });
    } finally { setWorkflowBusy(false); }
  }
  function reportUnexpectedError(error) {
    try {
      if (runContext) { runContext.fatal = true; if (runContext.impact !== "unchanged") recoveryContext = runContext; }
      wakePausedWorkflow();
      if (state.noticeChoice) chooseWorkflowNotice(false);
      reportRunFailure(error || new Error("Giao diện gặp lỗi chưa xác định."), "Chương trình gặp lỗi", true);
      saveRecoveryJournal();
      if (!state.workflowBusy) setWorkflowBusy(false);
    } catch (ignoreReportingFailure) { /* Never recursively throw from a global error handler. */ }
  }
  function noticeKeyboard(event) {
    if (!currentNotice || byId("workflowNotice").hidden || !blockingNotice(currentNotice)) return;
    if (event.key === "Escape") { event.preventDefault(); closeWorkflowNotice(); return; }
  }
  function updateRunHealth() {
    if (!runContext || !state.workflowBusy) return;
    if (runContext.paused || ((runContext.cancelRequested || runContext.pauseRequested) && !hostPending)) { byId("runHealth").textContent = ""; return; }
    var native = readNativeProgress(runContext);
    if (native && native.serial > Number(runContext.nativeProgressSerial || 0)) {
      runContext.nativeProgressSerial = native.serial;
      runContext.nativeOperation = native.phase === "before" ? native.operation : null;
      runContext.lastProgress = Date.now();
    }
    var elapsed = Date.now() - runContext.lastProgress;
    var operationNames = {"read-plan":"đọc kế hoạch dựng", "validate-plan":"kiểm tra kế hoạch dựng", "snapshot":"đọc trạng thái timeline", "qe-lookup":"tìm clip để đổi tốc độ", "set-speed":"đổi tốc độ clip", "move":"dời clip", "razor":"cắt clip"};
    var operation = operationNames[runContext.nativeOperation];
    byId("runHealth").textContent = elapsed >= 120000 && (hostPending || enginePending) ? "Chưa nhận phản hồi mới trong " + Math.floor(elapsed / 60000) + " phút · " + stageLabels[runContext.stage] + (hostPending && operation ? ". Đang chờ Premiere " + operation : "") + (hostPending ? ". Yêu cầu dừng phải chờ lệnh hiện tại trả về; chưa thể bắt đầu lượt khác." : ". Thao tác có thể vẫn đang chạy; chưa thể bắt đầu lượt khác.") : "";
  }
  function updateIncidentActions() {
    var disabled = state.workflowBusy || hostPending > 0 || enginePending > 0;
    byId("noticeCheckInputs").disabled = disabled;
    byId("checkRecovery").disabled = disabled;
  }
  function extensionRoot() {
    var pathname = decodeURIComponent(window.location.pathname || "");
    if (/^\/[A-Za-z]:/.test(pathname)) pathname = pathname.slice(1);
    return path.dirname(pathname.replace(/\//g, path.sep));
  }
  function jsxString(value) {
    return '"' + String(value).replace(/\\/g, "\\\\").replace(/"/g, '\\"').replace(/\r/g, "\\r").replace(/\n/g, "\\n") + '"';
  }
  function timestamp() {
    var d = new Date();
    function p(n) { return String(n).padStart(2, "0"); }
    return d.getFullYear() + p(d.getMonth() + 1) + p(d.getDate()) + "_" + p(d.getHours()) + p(d.getMinutes()) + p(d.getSeconds());
  }
  function applicationDataRoot() {
    var localAppData = process.env.LOCALAPPDATA;
    if (!localAppData) throw new Error("Windows không cung cấp LOCALAPPDATA; không thể tạo vùng làm việc an toàn.");
    var root = path.join(localAppData, "PremiereVoiceSync");
    security.assertNoLinks(fs, path, root, false);
    return root;
  }
  function isInside(childPath, parentPath) {
    var child = path.resolve(childPath).toLowerCase();
    var parent = path.resolve(parentPath).toLowerCase();
    return child === parent || child.indexOf(parent + path.sep) === 0;
  }
  function removeTreeSafe(targetPath, allowedRoot) {
    security.removeOwnedTree(fs, path, targetPath, allowedRoot);
  }
  function cleanupStaleJobs() {
    var jobsRoot = path.join(applicationDataRoot(), "Jobs");
    if (!fs.existsSync(jobsRoot)) return 0;
    security.assertNoLinks(fs, path, jobsRoot, false);
    var cutoff = Date.now() - (24 * 60 * 60 * 1000);
    var removed = 0;
    fs.readdirSync(jobsRoot).forEach(function (name) {
      var item = path.join(jobsRoot, name);
      var stat = fs.lstatSync(item);
      if (!/^Job_/.test(name) || stat.isSymbolicLink() || !stat.isDirectory()) return;
      var audioRecoveryPath = path.join(item, "job.json.audio-recovery.json");
      if (fs.existsSync(audioRecoveryPath)) {
        if (!recoveryContext) { recoveryContext = { workflow: "captions", restored: true, impact: "unknown", audioRecoveryPath: audioRecoveryPath }; saveRecoveryJournal(); }
        return;
      }
      if (stat.mtime.getTime() >= cutoff) return;
      removeTreeSafe(item, jobsRoot);
      removed++;
    });
    if (fs.existsSync(jobsRoot) && fs.readdirSync(jobsRoot).length === 0) fs.rmdirSync(jobsRoot);
    return removed;
  }
  function log(message, level) {
    var el = byId("log");
    el.textContent += "\n[" + new Date().toLocaleTimeString("vi-VN") + "] " + message;
    el.scrollTop = el.scrollHeight;
    if (level === "error") console.error(message);
  }
  function status(message, kind) {
    var el = byId("status");
    el.textContent = message;
    el.className = "summary wide" + (kind ? " " + kind : "");
    log(message, kind);
    syncTaskPresentation();
  }
  function logAudioCache(result, stage) {
    var cache = result.audioCache;
    if (cache && cache.enabled) {
      log("Cache audio" + (stage ? " · " + stage : "") + ": dùng lại " + cache.whisperHits + " lượt nhận diện và " + cache.quietHits + " lượt tìm khoảng nghỉ; xử lý mới " + cache.whisperMisses + " lượt nhận diện và " + cache.quietMisses + " lượt tìm khoảng nghỉ. Timestamp và kế hoạch được tính lại theo đầu vào hiện tại.", "muted");
    }
    if (cache && !cache.enabled && cache.writeFailures) log("Cache audio không khả dụng; tác vụ đang nhận diện trực tiếp, không dùng lại kết quả cũ.", "warn");
    if (cache && (cache.invalidEntries || cache.writeFailures)) log("Cache: " + cache.invalidEntries + " mục không hợp lệ đã được xử lý lại; " + cache.writeFailures + " kết quả không lưu được. Không dùng mốc lỗi.", "warn");
  }
  // Persist only allowlisted metrics, never raw logs, errors, media names or paths.
  function createWorkflowMetrics(workflow) {
    var file = "", active = null, disabled = false, warned = false;
    var startedAt = Date.now(), pausedAt = null, pausedMilliseconds = 0;
    var stages = ["preflight", "alignment", "sentence-plan", "dtw-plan", "speed-merge", "template-check", "timeline", "audio-export", "caption-alignment", "caption-import", "cleanup"];
    var cacheKeys = ["whisperHits", "whisperMisses", "quietHits", "quietMisses", "invalidEntries", "writeFailures"];
    function unavailable() {
      disabled = true;
      if (!warned) { warned = true; log("Không lưu được nhật ký hiệu năng tự động. Tác vụ vẫn tiếp tục; mục Hỗ trợ và nhật ký trong panel vẫn sử dụng được.", "warn"); }
    }
    function write(event) {
      if (disabled) return;
      try {
        security.assertNoLinks(fs, path, file, false);
        fs.appendFileSync(file, JSON.stringify(event) + "\n", "utf8");
      } catch (ignoreMetricsWrite) { unavailable(); }
    }
    function safeCount(value) {
      return typeof value === "number" && isFinite(value) && value >= 0 ? value : null;
    }
    function cacheMetrics(cache) {
      if (!cache || typeof cache.enabled !== "boolean") return null;
      var clean = { enabled: cache.enabled };
      cacheKeys.forEach(function (key) { var value = safeCount(cache[key]); if (value !== null) clean[key] = value; });
      return clean;
    }
    try {
      if (["auto-edit", "diagnostic-edit", "caption-only"].indexOf(workflow) < 0) throw new Error("INVALID_METRICS_WORKFLOW");
      var root = path.join(applicationDataRoot(), "Logs");
      security.assertNoLinks(fs, path, root, false);
      fs.mkdirSync(root, { recursive: true });
      // Prune only this logger's own files; never follow links or touch other logs.
      var ownName = /^Workflow_\d{8}_\d{6}_\d{13}_[a-f0-9]{24}\.jsonl$/;
      var owned = fs.readdirSync(root).filter(function (name) { return ownName.test(name); }).map(function (name) {
        var target = path.join(root, name), stat = fs.lstatSync(target);
        return { target: target, stat: stat };
      }).filter(function (item) { return item.stat.isFile() && !item.stat.isSymbolicLink(); }).sort(function (a, b) { return b.stat.mtime.getTime() - a.stat.mtime.getTime(); });
      owned.forEach(function (item, index) {
        var age = startedAt - item.stat.mtime.getTime();
        if (age > 30 * 86400000 || (index >= 99 && age > 86400000)) {
          security.assertNoLinks(fs, path, item.target, true);
          fs.unlinkSync(item.target);
        }
      });
      var token = String(startedAt) + "_" + nodeRequire("crypto").randomBytes(12).toString("hex");
      file = path.join(root, "Workflow_" + timestamp() + "_" + token + ".jsonl");
      security.assertNoLinks(fs, path, file, false);
      fs.writeFileSync(file, JSON.stringify({ type: "start", schemaVersion: 1, toolVersion: "2.20.90", workflow: workflow, createdAt: new Date(startedAt).toISOString() }) + "\n", { encoding: "utf8", flag: "wx" });
      log("Nhật ký hiệu năng tự lưu (không có lời nói/đường dẫn media): " + file, "muted");
    } catch (ignoreMetricsCreate) { unavailable(); }
    return {
      notification: function (stage, value, environment) {
        var allowed = { route: ["none", "try-foreground-once", "flash-taskbar-bounded", "defer-until-foreground-result", "banner-and-center", "notification-center-only"], attention: ["invalid-caller", "host-not-in-ancestry", "host-identity-changed", "no-host-window", "window-owner-changed", "already-foreground", "taskbar-flashed", "foreground-requested", "attention-unavailable", "unavailable"], native: ["available", "disabled", "unavailable", "submitted", "observed"] };
        if (!Object.prototype.hasOwnProperty.call(allowed, stage) || allowed[stage].indexOf(value) < 0) return;
        var event = { type: "notification", stage: stage, value: value, at: new Date().toISOString() };
        if (stage === "route" && environment) ["background", "externalEnabled", "foregroundEnabled"].forEach(function (key) { if (typeof environment[key] === "boolean") event[key] = environment[key]; });
        write(event);
      },
      audioExport: function (phase, action, rangeIndex, milliseconds, result) {
        if (workflow !== "caption-only" || !active || active.stage !== "audio-export" || ["prepare", "yield", "render", "abort"].indexOf(phase) < 0 || ["start", "end"].indexOf(action) < 0) return;
        var event = { type: "audio-export-" + action, phase: phase, at: new Date().toISOString() };
        if (Number.isInteger(rangeIndex) && rangeIndex >= 0) event.rangeIndex = rangeIndex;
        if (action === "end") {
          var elapsed = safeCount(milliseconds);
          if (elapsed !== null) event.milliseconds = elapsed;
          if (result && typeof result.ok === "boolean") event.outcome = result.ok ? "success" : "failed";
          var timing = result && result.audioExportTiming;
          ["hostMilliseconds", "nativeMilliseconds", "finalizeMilliseconds"].forEach(function (key) {
            var value = timing && typeof timing === "object" ? safeCount(timing[key]) : null;
            if (typeof value === "number") event[key] = value;
          });
        }
        write(event);
      },
      begin: function (stage) {
        if (stages.indexOf(stage) < 0) return;
        active = { stage: stage, startedAt: Date.now(), pausedAtStart: pausedMilliseconds };
        write({ type: "stage-start", stage: stage, at: new Date(active.startedAt).toISOString() });
      },
      end: function (result, outcome) {
        if (!active) return;
        var event = { type: "stage-end", stage: active.stage, milliseconds: Math.max(0, Date.now() - active.startedAt - (pausedMilliseconds - active.pausedAtStart)), outcome: outcome === "cancelled" ? "cancelled" : outcome === "failed" ? "failed" : "success" };
        active = null;
        if (result) {
          if (event.stage === "audio-export" && ["preflight", "isolation", "range-setup", "between-calls", "native-export", "audio-file-check", "restore", "snapshot"].indexOf(result.exportFailurePhase) >= 0) event.exportFailurePhase = result.exportFailurePhase;
          var cache = cacheMetrics(result.audioCache);
          if (cache) event.audioCache = cache;
          if (["cpu", "cuda"].indexOf(result.recognitionBackend) >= 0) event.recognitionBackend = result.recognitionBackend;
          if (typeof result.gpuFallbackUsed === "boolean") event.gpuFallbackUsed = result.gpuFallbackUsed;
          if (["dtw-word-boundary-v1", "legacy"].indexOf(result.captionTimingMode) >= 0) event.captionTiming = {
            mode: result.captionTimingMode,
            retryRangeCount: safeCount((result.captionTimingRetryRanges || []).length),
            estimatedRangeCount: safeCount((result.captionTimingEstimatedRanges || []).length),
            acousticBoundaryCount: safeCount(result.captionTimingAcousticBoundaryCount) || 0
          };
          var counts = {};
          ["captionCueCount", "voiceCueCount", "pictureCueCount", "addedCutCount", "reviewMarkerCount", "recognitionSuppressedRangeCount"].forEach(function (key) { var value = safeCount(result[key]); if (value !== null) counts[key] = value; });
          if (Object.keys(counts).length) event.counts = counts;
          if (typeof result.minNoDialogueGapSeconds === "number" && result.settings) {
            var settings = { minNoDialogueGapSeconds: result.minNoDialogueGapSeconds, speedWarningMinPercent: result.speedWarningMinPercent, speedWarningMaxPercent: result.speedWarningMaxPercent,
              voiceGroupGapSeconds: result.settings.voiceGroupGapSeconds, maxCaptionCharacters: result.settings.maxCaptionCharacters };
            event.effectiveSettings = {};
            Object.keys(settings).forEach(function (key) { if (typeof settings[key] === "number" && isFinite(settings[key]) && settings[key] > 0) event.effectiveSettings[key] = settings[key]; });
          }
        }
        write(event);
      },
      reviewPlan: function (result) {
        result = result || {};
        var counts = {}, keys = ["referenceReviewCues", "referenceNumberReviewCues", "referenceInformationCues", "referenceSupplementRanges", "referenceSupplementEmptyRanges", "referenceQuietRanges", "numericCaptionReviewCues", "captionTimingEstimatedRanges", "recognitionRejectedRanges"];
        keys.forEach(function (key) { counts[key] = Array.isArray(result[key]) ? result[key].length : 0; });
        var markers = Array.isArray(result.reviewMarkers) ? result.reviewMarkers : [];
        var ranges = markers.slice(0, 5000).map(function (item) {
          return { start: Number(item.start), end: Number(item.end), cueIndex: safeCount(item.cueIndex), captionIndex: safeCount(item.captionIndex), referenceCueIndex: safeCount(item.referenceCueIndex) };
        }).filter(function (item) { return isFinite(item.start) && isFinite(item.end) && item.start >= 0 && item.end > item.start; });
        write({ type: "review-plan", counts: counts, plannedIssueCount: markers.length, ranges: ranges });
      },
      linkTimeline: function (name) {
        if (/^Performance_\d{8}_\d{6}_\d{13}_[a-f0-9]{24}\.jsonl$/.test(name)) write({ type: "timeline-trace", fileName: name });
      },
      pause: function (paused) {
        if (paused && pausedAt === null) { pausedAt = Date.now(); write({ type: "pause-start", at: new Date(pausedAt).toISOString() }); }
        if (!paused && pausedAt !== null) {
          var duration = Math.max(0, Date.now() - pausedAt); pausedMilliseconds += duration; pausedAt = null;
          write({ type: "pause-end", milliseconds: duration });
        }
      },
      finish: function (outcome) {
        if (["success", "failed", "cancelled"].indexOf(outcome) < 0) outcome = "failed";
        this.pause(false);
        this.end(null, outcome);
        write({ type: "finish", outcome: outcome, processingMilliseconds: Math.max(0, Date.now() - startedAt - pausedMilliseconds), pausedMilliseconds: pausedMilliseconds, finishedAt: new Date().toISOString() });
      }
    };
  }
  function logCaptionTiming(result) {
    logAudioCache(result, "căn lời");
    if (!result.captionTimingMode) return;
    log("Căn caption: " + (result.captionBoundaryMode === "waveform-valley-v1" ? "DTW và đáy sóng âm quanh từ đứng trước ranh giới" : result.captionTimingMode === "dtw-word-boundary-v1" ? "DTW theo ranh giới token và khoảng nghỉ thật" : "mốc nhận diện thông thường") + (result.captionTimingBackend ? " · " + result.captionTimingBackend : "") + ".", "muted");
    (result.captionTimingReasons || []).forEach(function (reason) { log("Căn caption: " + reason, "warn"); });
    if ((result.captionTimingRetryRanges || []).length) log("Đã căn lại DTW riêng " + result.captionTimingRetryRanges.length + " vùng audio; giữ mốc theo từ ở các vùng còn lại.", "muted");
    if (result.captionTimingAcousticBoundaryCount) log("Đã đặt " + result.captionTimingAcousticBoundaryCount + " ranh giới từ tại giữa khoảng âm lượng thấp đo được trên audio.", "muted");
    if ((result.acousticEditRefinedCues || []).length) log("Auto edit: dùng mốc âm học mới cho " + result.acousticEditRefinedCues.length + " cue để căn mép câu và chọn điểm cắt dựng.", "muted");
    if ((result.acousticEditReviewCues || []).length) log("Auto edit: giữ mốc dự phòng ở " + result.acousticEditReviewCues.length + " cue có mép chưa tương thích với cue lân cận; các vùng khác vẫn dùng mốc mới.", "warn");
    var estimatedTiming = result.captionTimingEstimatedRanges || [];
    if (estimatedTiming.length) {
      var estimatedMessage = "Có " + estimatedTiming.length + " vùng chỉ có timing ước lượng cấp câu: " + estimatedTiming.map(function (item) { return Number(item.start).toFixed(2) + "–" + Number(item.end).toFixed(2) + "s"; }).join("; ") + ". Cần kiểm tra các vùng này; chưa xác minh được ranh giới từng từ.";
      log(estimatedMessage, "warn"); runWarning(estimatedMessage, true);
    }
    if ((result.captionTimingReviewCues || []).length) {
      var reviewMessage = "Chưa xác minh được mốc caption mới, giữ đường căn cũ và cần nghe lại: cue " + result.captionTimingReviewCues.join(", ") + ".";
      log(reviewMessage, "warn"); runWarning(reviewMessage, true);
    }
    if ((result.captionTimingRefinedCues || []).length) log("Đã nhận diện lại mép caption: cue " + result.captionTimingRefinedCues.join(", ") + ".", "muted");
  }
  function diagnosticStatus(message, kind) {
    var el = byId("diagnosticSummary");
    el.textContent = message;
    el.className = "summary" + (kind ? " " + kind : "");
  }
  function setWorkflowBusy(busy) {
    state.workflowBusy = !!busy;
    if (state.workflowBusy) closeWorkflowNotice();
    ["clearWhisperCache", "exportSafeLog", "allowGpuDownload", "runSync", "runCaptions", "modeEdit", "modeCaptions", "captionVoiceTrack", "captionSourceMode", "captionScopeMode", "captionLanguage", "voiceLanguage", "captionSrtCandidates", "pickCaptionSrt", "subtitleMaxCharacters", "runDiagnostics", "scanSequence", "pickTargetSrt", "srtCandidates", "resetSettings", "minSpeed", "maxSpeed", "minDialogueGap", "voiceGroupGap", "maxCaptionCharacters"].forEach(function (id) {
      var element = byId(id);
      if (element) element.disabled = state.workflowBusy || (id === "scanSequence" && !!inputRefreshPromise);
    });
    syncCaptionInputControls();
    if (srtJoin) srtJoin.render();
    var retryButton = byId("retryBackend");
    if (retryButton) retryButton.disabled = state.workflowBusy || state.backendChecking;
    byId("allowGpuDownload").disabled = state.workflowBusy || state.backendChecking;
    ["runSync", "runCaptions"].forEach(function (id) { byId(id).disabled = state.workflowBusy || !!recoveryContext; });
    updateIncidentActions();
    byId("noticePickSrt").disabled = state.workflowBusy;
    byId("noticeExportLog").disabled = state.workflowBusy;
    byId("recoveryNotice").hidden = !recoveryContext;
    if (!busy) byId("runHealth").textContent = "";
    if (!busy && currentNotice && currentNotice.surface === "field") focusValidationField();
    updateStopControl();
  }
  function postcheckError(result) {
    var reasons = [];
    var validationLimit = Number((result.settings && result.settings.validationToleranceFrames) === undefined ? 1 : result.settings.validationToleranceFrames);
    var largestStartError = Math.max(Number(result.maxVideoStartErrorFrames || 0), Number(result.maxAudioStartErrorFrames || 0), Number(result.maxVoiceStartErrorFrames || 0));
    var largestPairError = Math.max(Number(result.maxPairStartErrorFrames || 0), Number(result.maxPairEndErrorFrames || 0));
    if (largestStartError > validationLimit) reasons.push("sai lệch điểm bắt đầu lớn nhất " + largestStartError + " frame");
    if (largestPairError > validationLimit) reasons.push("sai lệch cặp V1–A1 lớn nhất " + largestPairError + " frame");
    if (Number(result.finalVideoTailMissingFrames || 0) > 0) reasons.push("V1 bị thiếu " + result.finalVideoTailMissingFrames + " frame ở cuối");
    if (Number(result.finalVideoTailExtraFrames || 0) > 0) reasons.push("V1 bị thừa " + result.finalVideoTailExtraFrames + " frame ở cuối");
    if (Number(result.finalAudioTailMissingFrames || 0) > 0) reasons.push("A1 bị thiếu " + result.finalAudioTailMissingFrames + " frame ở cuối");
    if (Number(result.finalAudioTailExtraFrames || 0) > 0) reasons.push("A1 bị thừa " + result.finalAudioTailExtraFrames + " frame ở cuối");
    if (Number(result.speedNonConvergenceCount || 0) > 0) reasons.push(result.speedNonConvergenceCount + " clip không hội tụ duration, còn lệch tối đa " + Number(result.maxSpeedDurationErrorAfterCorrectionFrames || 0) + " frame");
    else if (Number(result.timelineEndMismatchCount || 0) > 0) reasons.push(result.timelineEndMismatchCount + " cặp clip không đúng duration kế hoạch");
    var internalCoverageGap = 0;
    if (result.videoCoverageGaps && result.videoCoverageGaps.length) {
      for (var gapIndex = 0; gapIndex < result.videoCoverageGaps.length; gapIndex++) {
        if (result.videoCoverageGaps[gapIndex].type !== "tail") internalCoverageGap = Math.max(internalCoverageGap, Number(result.videoCoverageGaps[gapIndex].gapFrames || 0));
      }
    }
    if (internalCoverageGap > Number((result.settings && result.settings.maxCoverageGapFrames) || 0)) reasons.push("khe hở hình bên trong lớn nhất " + internalCoverageGap + " frame");
    if (Number(result.linkMismatchCount || 0) > 0) reasons.push(result.linkMismatchCount + " cặp V1–A1 mất liên kết");
    if (Number(result.clipMarkerFailureCount || 0) > 0) reasons.push(result.clipMarkerFailureCount + " lỗi cập nhật marker clip: " + (result.clipMarkerFailures || []).join("; "));
    if (Number(result.reviewMarkerFailureCount || 0) > 0) reasons.push(result.reviewMarkerFailureCount + " mốc chưa gắn được marker timeline: " + (result.reviewMarkerFailures || []).join("; "));
    if (result.masterInOutReset === false) reasons.push("không xóa được In/Out của master nest");
    if (result.captionCreated === false) reasons.push("không tạo được caption track");
    if (result.captionTemporaryBinRemoved === false || Number(result.captionProjectItemCountAfter || 0) !== Number(result.captionProjectItemCountBefore || 0)) reasons.push("file caption tạm vẫn còn trong Project");
    if (result.unrelatedPreserved === false) reasons.push("element ngoài phạm vi đã thay đổi");
    return reasons.length ? "Hậu kiểm không đạt: " + reasons.join("; ") + "." : (result.error || "Hậu kiểm timeline không đạt.");
  }
  var hostReadyPromise = null;
  function evalRaw(script) {
    return new Promise(function (resolve, reject) {
      if (script.indexOf("abortDiagnosticEdit") < 0 && script.indexOf("abortCaptionAudioExport") < 0) throwIfStopRequested();
      if (!window.__adobe_cep__) { reject(new Error("Hãy mở panel bên trong Premiere Pro.")); return; }
      if (runContext && runContext.fatal && script.indexOf("abortDiagnosticEdit") < 0 && script.indexOf("abortCaptionAudioExport") < 0) { reject(new Error("Giao diện đã gặp lỗi; dừng trước thao tác kế tiếp để kiểm tra kết quả.")); return; }
      hostPending++;
      try { window.__adobe_cep__.evalScript(script, function (raw) {
        hostPending--; if (runContext) runContext.lastProgress = Date.now(); updateIncidentActions();
        if (raw === "EvalScript error.") {
          reject(new Error("Premiere không thể chạy ExtendScript. Hãy đóng Premiere, mở lại rồi bấm Cập nhật đầu vào."));
          return;
        }
        resolve(String(raw === undefined || raw === null ? "" : raw));
      }); } catch (error) { hostPending--; reject(error); }
    });
  }
  function ensureHostLoaded() {
    if (hostReadyPromise) return hostReadyPromise;
    var hostPath = path.join(extensionRoot(), "jsx", "host.jsx");
    var inputPath = path.join(extensionRoot(), "js", "caption-input.js");
    var bootstrap = '(function(){try{' +
      'function ready(){return $._PVS&&$._PVS.captionInputRevision===1&&$._PVS.captionInput&&$._PVS.captionInput.revision===1&&typeof $._PVS.captionInput.resolve==="function"&&typeof $._PVS.captionInput.sameKey==="function"&&typeof $._PVS.scanSequence==="function"&&typeof $._PVS.scanCaptionRange==="function"&&typeof $._PVS.beginSrtScan==="function"&&typeof $._PVS.beginCaptionAudioExport==="function"&&typeof $._PVS.workflowPauseState==="function";}' +
      'if($._PVS&&$._PVS.bootstrapRevision===3&&ready())return "PVS_HOST_READY";' +
      // Read explicitly: BOM-less source otherwise follows Windows ANSI in
      // ExtendScript. Evaluate in this call and publish dependencies on $._PVS.
      'function load(p){var f=new File(p);if(!f.exists)throw new Error("Missing script: "+f.fsName);f.encoding="UTF-8";if(!f.open("r"))throw new Error("Cannot read script: "+f.fsName);var s;try{s=f.read();if(f.error)throw new Error(f.error);}finally{f.close();}eval(s);}' +
      'load(' + jsxString(inputPath) + ');' +
      'load(' + jsxString(hostPath) + ');' +
      'if(ready()){$._PVS.bootstrapRevision=3;return "PVS_HOST_READY";}' +
      'return "PVS_HOST_ERROR|Incomplete Premiere host or audio planner";' +
      '}catch(e){return "PVS_HOST_ERROR|"+String(e)+"|line="+(e.line||"")+"|file="+(e.fileName||"");}}())';
    hostReadyPromise = evalRaw(bootstrap).then(function (raw) {
      if (raw !== "PVS_HOST_READY") {
        var detail = raw.indexOf("PVS_HOST_ERROR|") === 0 ? raw.substring(15) : raw;
        throw new Error("Không nạp được bộ điều khiển Premiere: " + detail);
      }
      return true;
    }).catch(function (error) {
      hostReadyPromise = null;
      throw error;
    });
    return hostReadyPromise;
  }
  function evalHost(script) {
    return ensureHostLoaded().then(function () {
      return evalRaw(script);
    }).then(function (raw) {
      try { return JSON.parse(raw); }
      catch (error) { throw new Error("Premiere trả về dữ liệu không hợp lệ: " + raw); }
    });
  }
  async function runPowerShell(scriptPath, args) {
    await waitForWorkflowPause();
    var output = await new Promise(function (resolve, reject) {
      throwIfStopRequested();
      if (runContext && runContext.fatal) { reject(new Error("Tác vụ dừng do lỗi giao diện.")); return; }
      var commandArgs = ["-NoProfile", "-ExecutionPolicy", "Bypass", "-File", scriptPath].concat(args || []);
      var powershell = path.join(process.env.SystemRoot || process.env.WINDIR, "System32", "WindowsPowerShell", "v1.0", "powershell.exe");
      security.assertNoLinks(fs, path, powershell, false);
      security.assertNoLinks(fs, path, scriptPath, false);
      var owner = runContext, request = null;
      if (owner && owner.outputFolder) {
        var wrapper = path.join(extensionRoot(), "engine", "run-workflow.ps1");
        owner.engineSerial = (owner.engineSerial || 0) + 1;
        var requestPath = path.join(owner.outputFolder, "engine-" + owner.engineSerial + ".json");
        request = { cancelPath: requestPath + ".cancel" };
        security.assertNoLinks(fs, path, wrapper, true);
        security.assertNoLinks(fs, path, requestPath, false);
        fs.writeFileSync(requestPath, JSON.stringify({ script: path.basename(scriptPath), args: args || [] }), { encoding: "utf8", flag: "wx" });
        owner.engineRequest = request;
        commandArgs = ["-NoProfile", "-ExecutionPolicy", "Bypass", "-File", wrapper, "-RequestPath", requestPath];
      }
      enginePending++;
      try { childProcess.execFile(powershell, commandArgs, { windowsHide: true, maxBuffer: 16 * 1024 * 1024 }, function (error, stdout, stderr) {
        if (owner && owner.engineRequest === request) owner.engineRequest = null;
        enginePending--; if (runContext) runContext.lastProgress = Date.now(); updateIncidentActions();
        // Wrapper exit 1223 means its entire owned process job has been drained.
        // Preserve setup/engine errors even if a stop was requested concurrently.
        if (owner && owner.cancelRequested && (!error || error.code === 1223)) { reject(stoppedError()); return; }
        if (error) { reject(new Error((stderr || stdout || error.message).trim())); return; }
        resolve(stdout);
      }); } catch (error) { if (owner && owner.engineRequest === request) owner.engineRequest = null; enginePending--; reject(error); }
    });
    await waitForWorkflowPause();
    return output;
  }
  function parsePowerShellJson(output) {
    var lines = String(output || "").split(/\r?\n/).filter(function (line) { return line.trim(); });
    for (var index = lines.length - 1; index >= 0; index--) {
      try { return JSON.parse(lines[index]); } catch (ignoreLine) {}
    }
    throw new Error("Engine không trả về trạng thái backend hợp lệ.");
  }
  function localizeBackendReason(reason) {
    return String(reason || "")
      .replace(/^Khong phat hien NVIDIA CUDA hoac nvidia-smi; ban hien tai dung CPU tren may nay\./, "Không phát hiện NVIDIA CUDA hoặc nvidia-smi; bản hiện tại dùng CPU trên máy này.")
      .replace(/^Chua co backend CUDA hop le\./, "Chưa có backend CUDA hợp lệ.")
      .replace(/^Chua tai backend CUDA\. Bat quyen tai GPU trong panel neu muon; CPU van dung offline\./, "Chưa tải backend CUDA. Cho phép tải GPU trong panel nếu muốn; CPU vẫn dùng offline.")
      .replace(/^Backend CUDA khong vuot qua kiem tra toan ven; khong thuc thi va dung CPU\./, "Backend CUDA không vượt kiểm tra toàn vẹn; không thực thi và dùng CPU.")
      .replace(/^Khong cai duoc CUDA:/, "Không cài được CUDA:")
      .replace(/^CUDA dang tam tat sau loi runtime den /, "CUDA đang tạm tắt sau lỗi runtime đến ")
      .replace(/; dung CPU de bao dam tac vu hoan tat\./, "; dùng CPU để bảo đảm tác vụ hoàn tất.")
      .replace(/^CUDA da duoc xac minh bang nhan dien thuc te cho GPU va driver hien tai\./, "CUDA đã được xác minh bằng nhận diện thực tế cho GPU và driver hiện tại.")
      .replace(/^CUDA da vuot qua phep thu nhan dien thuc te\./, "CUDA đã vượt qua phép thử nhận diện thực tế.")
      .replace(/^Phep thu CUDA that bai nen chuyen sang CPU\./, "Phép thử CUDA thất bại nên chuyển sang CPU.");
  }
  function renderBackend(backend) {
    var summary = byId("backendSummary");
    var isGpu = backend && backend.backend === "cuda";
    var heading = isGpu ? "GPU đang hoạt động" : "CPU đang hoạt động";
    var label = backend && backend.label ? backend.label : "CPU fallback";
    var reason = backend && backend.reason ? localizeBackendReason(backend.reason) : "Không có thông tin chi tiết.";
    summary.textContent = heading + " · " + label;
    summary.title = reason;
    summary.className = "summary backend-state " + (isGpu ? "ok" : "warn");
    var reasonElement = byId("backendReason");
    if (reasonElement) {
      reasonElement.textContent = isGpu ? "" : "Lý do không dùng GPU: " + reason;
      reasonElement.hidden = isGpu;
    }
  }
  async function detectBackend(forceProbe) {
    var summary = byId("backendSummary");
    var retryButton = byId("retryBackend");
    try {
      state.backendChecking = true;
      byId("allowGpuDownload").disabled = true;
      summary.textContent = "Đang tự nhận diện GPU và kiểm tra Whisper backend...";
      summary.className = "summary backend-state muted";
      if (byId("backendReason")) byId("backendReason").hidden = true;
      retryButton.disabled = true;
      var backendArgs = byId("allowGpuDownload").checked ? ["-InstallIfNeeded"] : [];
      if (forceProbe) backendArgs.push("-ForceProbe");
      var output = await runPowerShell(path.join(extensionRoot(), "engine", "resolve-backend.ps1"), backendArgs);
      state.backend = parsePowerShellJson(output);
      if (state.backend.installedNow) state.backend.reason += " Backend GPU vừa được cài tự động trên máy này.";
      renderBackend(state.backend);
      log("Whisper backend: " + state.backend.label + ". " + state.backend.reason, state.backend.backend === "cpu" ? "muted" : "ok");
      return state.backend;
    } catch (error) {
      state.backend = { backend: "cpu", label: "CPU fallback", reason: error.message };
      renderBackend(state.backend);
      log("Không kiểm tra được GPU; alignment sẽ tự dùng CPU: " + error.message, "muted");
      return state.backend;
    } finally {
      state.backendChecking = false;
      retryButton.disabled = state.workflowBusy;
      byId("allowGpuDownload").disabled = state.workflowBusy;
    }
  }
  function setTargetSrt(filePath, origin, automatic) {
    if (!filePath || !/\.srt$/i.test(filePath)) throw new Error("Không đọc được file SRT đã chọn.");
    if (inlineValidation && inlineValidation.fieldId === "srtCandidates") closeWorkflowNotice();
    state.targetSrt = path.normalize(filePath);
    if (!automatic) state.targetSrtExplicit = true;
    localStorage.setItem("pvs.targetSrt", state.targetSrt);
    var select = byId("srtCandidates");
    noticeAttribute(select, "aria-invalid", "false");
    byId("srtHint").className = "hint"; noticeAttribute(byId("srtHint"), "role", "status");
    var found = false;
    for (var optionIndex = 0; optionIndex < select.options.length; optionIndex++) {
      if (String(select.options[optionIndex].value).toLowerCase() === state.targetSrt.toLowerCase()) { found = true; break; }
    }
    if (!found) {
      var option = document.createElement("option");
      option.value = state.targetSrt;
      option.textContent = "Ngoài Project — " + path.basename(state.targetSrt);
      select.appendChild(option);
    }
    select.value = state.targetSrt;
    byId("srtHint").textContent = "Đang chọn" + (origin ? " từ " + origin : "") + ": " + path.basename(state.targetSrt);
    byId("srtHint").title = state.targetSrt;
  }
  function readSettings(readOnly) {
    function numberSetting(id, label, minimum, maximum, integerOnly) {
      var element = byId(id);
      var raw = String(element.value === undefined ? "" : element.value).trim().replace(",", ".");
      if (!raw) throw inputError(label + " chưa có giá trị.", id);
      var value = Number(raw);
      if (!isFinite(value)) throw inputError(label + " phải là một số hợp lệ.", id);
      if (integerOnly && Math.round(value) !== value) throw inputError(label + " phải là số nguyên.", id);
      if (value < minimum || value > maximum) throw inputError(label + " phải nằm trong khoảng " + minimum + "–" + maximum + ".", id);
      if (!readOnly) element.value = value;
      return value;
    }
    var values = {
      minSpeed: numberSetting("minSpeed", "Ngưỡng cảnh báo chậm", 10, 100, false),
      maxSpeed: numberSetting("maxSpeed", "Ngưỡng cảnh báo nhanh", 100, 400, false),
      minDialogueGap: numberSetting("minDialogueGap", "Gap không lời tối thiểu", 0.2, 10, false),
      voiceGroupGap: numberSetting("voiceGroupGap", "Gap tách nhóm voice", 0.2, 20, false),
      maxCaptionCharacters: numberSetting("maxCaptionCharacters", "Ký tự tối đa mỗi caption", 20, 80, true)
    };
    if (values.minSpeed > values.maxSpeed) throw inputError("Ngưỡng cảnh báo chậm không được lớn hơn ngưỡng cảnh báo nhanh.", "minSpeed");
    if (!readOnly) {
      localStorage.setItem(settingsStorageKey, JSON.stringify(values));
      localStorage.setItem(settingsSchemaKey, settingsSchemaVersion);
    }
    return values;
  }
  function readVoiceLanguage(readOnly) {
    var language = byId("voiceLanguage").value || "vi";
    if (!/^(vi|auto|en|zh|ja|ko|fr|de|es|pt|ru|it|id|hi|ar)$/.test(language)) throw inputError("Hãy chọn ngôn ngữ voice.", "voiceLanguage");
    if (!readOnly) localStorage.setItem("pvs.voiceLanguage", language);
    return language;
  }
  function readCaptionSettings() {
    var maxCharacters = Number(byId("subtitleMaxCharacters").value);
    if (!isFinite(maxCharacters) || Math.round(maxCharacters) !== maxCharacters || maxCharacters < 20 || maxCharacters > 80) throw inputError("Ký tự tối đa mỗi caption phải là số nguyên từ 20 đến 80.", "subtitleMaxCharacters");
    var language = byId("captionLanguage").value;
    if (!/^(auto|[a-z]{2,3})$/.test(language)) throw inputError("Hãy chọn ngôn ngữ lời nói.", "captionLanguage");
    return { language: language, maxCaptionCharacters: maxCharacters };
  }
  function loadSettings() {
    var stored = null;
    try { stored = JSON.parse(localStorage.getItem(settingsStorageKey) || "null"); }
    catch (ignoreStoredSettings) { localStorage.removeItem(settingsStorageKey); }
    if (!stored || typeof stored !== "object") return settingDefaults;

    var migrated = {
      minSpeed: stored.minSpeed === undefined ? settingDefaults.minSpeed : stored.minSpeed,
      maxSpeed: stored.maxSpeed === undefined ? settingDefaults.maxSpeed : stored.maxSpeed,
      minDialogueGap: stored.minDialogueGap === undefined ? settingDefaults.minDialogueGap : stored.minDialogueGap,
      voiceGroupGap: stored.voiceGroupGap === undefined ? settingDefaults.voiceGroupGap : stored.voiceGroupGap,
      maxCaptionCharacters: stored.maxCaptionCharacters === undefined ? settingDefaults.maxCaptionCharacters : stored.maxCaptionCharacters
    };
    if (localStorage.getItem(settingsSchemaKey) !== settingsSchemaVersion && Number(migrated.maxSpeed) === 110) {
      migrated.maxSpeed = settingDefaults.maxSpeed;
    }
    localStorage.setItem(settingsStorageKey, JSON.stringify(migrated));
    localStorage.setItem(settingsSchemaKey, settingsSchemaVersion);
    return migrated;
  }
  function applySettings(values) {
    values = values || settingDefaults;
    Object.keys(settingDefaults).forEach(function (key) {
      var element = byId(key);
      var value = values[key] === undefined ? settingDefaults[key] : values[key];
      if (element.type === "checkbox") element.checked = !!value;
      else element.value = value;
    });
  }
  async function scanSequence() {
    try {
      var info = await evalHost("$._PVS.scanSequence()");
      if (!info.ok) throw new Error(info.error);
      if (!info.mainVideoClip || !info.linkedAudio.length) throw new Error("V1 phải là nested video đã linked với audio gốc A1.");
      if (!info.voices.length) throw new Error("Không tìm thấy voice mới trên A2.");
      if (Number(info.mainVideoPieceCount) !== 1 || Number(info.captionTrackCount) > 0) throw new Error("Sequence này có vẻ đã được dựng. Hãy mở lại sequence template sạch.");
      state.sequence = info;
      byId("sequenceSummary").textContent = info.name + "\nV1+A1 linked: " + info.mainVideoClip.name + "\nA2: " + info.voices.length + " clip voice";
      byId("sequenceSummary").className = "summary edit-only";
      return info;
    } catch (error) {
      state.sequence = null;
      byId("sequenceSummary").textContent = error.message;
      byId("sequenceSummary").className = "summary error edit-only";
      throw error;
    }
  }
  function pickTargetSrt() {
    var start = state.targetSrt ? path.dirname(state.targetSrt) : null;
    var result = window.cep.fs.showOpenDialog(false, false, "Chọn SRT cùng ngôn ngữ với voice", start, ["srt"]);
    if (result.err === 0 && result.data && result.data.length) {
      setTargetSrt(result.data[0], "ổ đĩa");
    }
  }
  var srtHostRequest = null, srtScanPromise = null;
  function requestSrtScan(script, deadline) {
    if (srtHostRequest) return Promise.reject(new Error("Premiere chưa trả lời lượt quét SRT trước. Có thể dùng Chọn ngoài hoặc mở lại panel."));
    var request = evalHost(script);
    srtHostRequest = request;
    request.then(function () { if (srtHostRequest === request) srtHostRequest = null; }, function () { if (srtHostRequest === request) srtHostRequest = null; });
    return new Promise(function (resolve, reject) {
      var settled = false;
      var timer = window.setTimeout(function () {
        settled = true;
        reject(new Error("Premiere không trả lời quét SRT trong 30 giây. Có thể dùng Chọn ngoài; không cần đóng project."));
      }, Math.max(1, deadline - Date.now()));
      request.then(function (result) { if (!settled) { settled = true; window.clearTimeout(timer); resolve(result); } }, function (error) { if (!settled) { settled = true; window.clearTimeout(timer); reject(error); } });
    });
  }
  async function readProjectSrtCandidates() {
    var token = "srt-" + Date.now() + "-" + Math.random().toString(16).slice(2), deadline = Date.now() + 30000;
    var result = await requestSrtScan("$._PVS.beginSrtScan(" + jsxString(token) + ")", deadline), candidates = [];
    while (true) {
      if (!result.ok) throw new Error(result.error);
      if (!Array.isArray(result.candidates) || typeof result.done !== "boolean") throw new Error("Premiere trả về danh sách SRT không hợp lệ.");
      candidates = candidates.concat(result.candidates);
      if (result.done) return { ok: true, candidates: candidates };
      if (Date.now() >= deadline) throw new Error("Quét SRT quá lâu. Có thể dùng Chọn ngoài.");
      // Give CEP a turn between read-only batches. No timeout is applied to
      // editing/import operations, and a timed-out native read is not retried.
      await new Promise(function (resolve) { window.setTimeout(resolve, 0); });
      result = await requestSrtScan("$._PVS.advanceSrtScan(" + jsxString(token) + ")", deadline);
    }
  }
  async function detectSrt(silent) {
    if (srtScanPromise) return srtScanPromise;
    var selectedBefore = state.targetSrt;
    byId("srtHint").textContent = "Đang quét SRT trong Project...";
    byId("captionSrtHint").textContent = "Đang quét SRT trong Project...";
    var operation = (async function () { try {
      var result = await readProjectSrtCandidates();
      var seenPaths = {};
      var candidates = result.candidates.filter(function (item) {
        var key = String(item.path || "").toLowerCase();
        if (!key || !/\.srt$/i.test(key) || seenPaths[key]) return false;
        seenPaths[key] = true; return true;
      });
      if (srtJoin && srtJoin.setProjectCandidates) srtJoin.setProjectCandidates(candidates);
      var voiceStem = state.sequence && state.sequence.voices.length ? path.basename(state.sequence.voices[0].name, path.extname(state.sequence.voices[0].name)).replace(/\s*\d+\s*$/, "").toLowerCase() : "";
      function rankCandidates(language) {
        return candidates.map(function (item) {
          var text = (item.name + " " + item.path).toLowerCase();
          var matchesLanguage = language === "vi" ? /vietnamese|tiếng việt|\.vi\.|[-_ ]vi[-_ .]/i.test(text) : language !== "auto" && /^(en|zh|ja|ko|fr|de|es|pt|ru|it|id|hi|ar)$/.test(language) && new RegExp("(?:^|[. _-])" + language + "(?:[. _-]|$)", "i").test(text);
          return { name: item.name, path: item.path, score: (matchesLanguage ? 10 : 0) + (voiceStem && text.indexOf(voiceStem) >= 0 ? 5 : 0) };
        }).sort(function (a, b) { return b.score - a.score || a.name.localeCompare(b.name); });
      }
      renderCaptionSrtCandidates(rankCandidates(byId("captionLanguage").value || "vi"));
      candidates = rankCandidates(byId("voiceLanguage").value || "vi");
      var select = byId("srtCandidates");
      select.innerHTML = "";
      var placeholder = document.createElement("option"); placeholder.value = ""; placeholder.textContent = candidates.length ? "Chọn một SRT trong Project..." : "Project chưa có SRT — bấm Chọn ngoài"; select.appendChild(placeholder);
      candidates.forEach(function (item) {
        var option = document.createElement("option"); option.value = item.path; option.textContent = item.name; option.title = item.path; select.appendChild(option);
      });
      var persistedInList = candidates.filter(function (item) { return state.targetSrt && item.path.toLowerCase() === state.targetSrt.toLowerCase(); });
      if (state.targetSrtExplicit || state.targetSrt !== selectedBefore) {
        if (state.targetSrt) setTargetSrt(state.targetSrt, "bạn đã chọn", true);
        else { select.value = ""; byId("srtHint").textContent = "Hãy chọn SRT trong Project hoặc dùng Chọn ngoài."; }
      }
      else if (persistedInList.length) setTargetSrt(persistedInList[0].path, "Project", true);
      else if (candidates.length === 1 || (candidates.length > 1 && candidates[0].score > candidates[1].score)) setTargetSrt(candidates[0].path, "Project tự nhận diện", true);
      else if (state.targetSrt) setTargetSrt(state.targetSrt, "lần chọn trước", true);
      else { state.targetSrt = ""; select.value = ""; byId("srtHint").textContent = candidates.length ? "Tìm thấy " + candidates.length + " SRT trong Project. Hãy chọn một file." : "Không có SRT trong Project. Có thể dùng nút Chọn ngoài."; }
    } catch (error) {
      byId("srtHint").textContent = error.message;
      byId("captionSrtHint").textContent = error.message;
      if (!silent) log(error.message, "warn");
    } })();
    srtScanPromise = operation;
    try { return await operation; } finally { if (srtScanPromise === operation) srtScanPromise = null; }
  }
  var inputRefreshPromise = null;
  function refreshProjectInputs(startup) {
    if (state.workflowBusy) return Promise.resolve();
    if (inputRefreshPromise) return inputRefreshPromise;
    var button = byId("scanSequence");
    button.disabled = true;
    button.textContent = "Đang cập nhật...";
    var operation = (async function () {
      // Project discovery stays independent of edit eligibility. Read only
      // the current mode's timeline data, without polling or native writes.
      await detectSrt(true);
      if (state.workflowBusy) return;
      var readingMode;
      do {
        readingMode = state.mode;
        if (readingMode === "captions") {
          try { await scanCaptionRange(); }
          catch (error) { log("Không đọc được phạm vi subtitle: " + error.message, startup ? "muted" : "error"); }
        } else {
          try { await scanSequence(); }
          catch (error) { log((startup ? "Sequence chưa sẵn sàng: " : "Không đọc được sequence: ") + error.message, startup ? "muted" : "error"); }
        }
        // A tab changed while the native read was pending: read the new mode,
        // not the Project again. This is user-triggered, never timer polling.
      } while (!state.workflowBusy && readingMode !== state.mode);
    })();
    inputRefreshPromise = operation.then(function () {
      inputRefreshPromise = null;
      button.disabled = state.workflowBusy;
      button.textContent = "Cập nhật đầu vào";
    }, function (error) {
      inputRefreshPromise = null;
      button.disabled = state.workflowBusy;
      button.textContent = "Cập nhật đầu vào";
      throw error;
    });
    return inputRefreshPromise;
  }
  function inspectSrt(filePath) {
    var content = fs.readFileSync(filePath, "utf8").replace(/^\uFEFF/, "");
    var timestampPattern = /^\s*(\d{1,2}):(\d{2}):(\d{2})[,.](\d{3})\s*-->\s*(\d{1,2}):(\d{2}):(\d{2})[,.](\d{3})/;
    var cueCount = 0;
    var invalidDurationCount = 0;
    content.split(/\r?\n/).forEach(function (line) {
      var match = timestampPattern.exec(line);
      if (!match) return;
      cueCount++;
      var start = (((Number(match[1]) * 60 + Number(match[2])) * 60 + Number(match[3])) * 1000) + Number(match[4]);
      var end = (((Number(match[5]) * 60 + Number(match[6])) * 60 + Number(match[7])) * 1000) + Number(match[8]);
      if (end <= start) invalidDurationCount++;
    });
    if (!cueCount) throw new Error("File SRT không có timestamp hợp lệ.");
    if (invalidDurationCount) throw new Error("File SRT có " + invalidDurationCount + " cue có thời lượng không hợp lệ.");
    return { cueCount: cueCount };
  }
  async function runDiagnostics() {
    if (state.workflowBusy) return;
    try {
      setWorkflowBusy(true);
      diagnosticStatus("Đang kiểm tra sequence, voice, SRT và bộ xử lý...", "muted");
      var sequence = await scanSequence();
      var settings = readSettings();
      var joinedReference = srtJoin && srtJoin.read();
      if (!joinedReference && (!state.targetSrt || !fs.existsSync(state.targetSrt))) await detectSrt(false);
      if (!joinedReference && (!state.targetSrt || !fs.existsSync(state.targetSrt))) throw new Error("Chưa chọn được file SRT cùng ngôn ngữ với voice.");
      var srt = joinedReference || inspectSrt(state.targetSrt);
      var missingVoices = sequence.voices.filter(function (voice) { return !voice.path || !fs.existsSync(voice.path); });
      if (missingVoices.length) throw new Error("Có " + missingVoices.length + " clip A2 không đọc được file nguồn.");
      for (var voiceIndex = 1; voiceIndex < sequence.voices.length; voiceIndex++) {
        if (Number(sequence.voices[voiceIndex].start) < Number(sequence.voices[voiceIndex - 1].end) - (0.5 / Number(sequence.frameRate || 30))) {
          throw new Error("Các clip voice A2 đang chồng lên nhau.");
        }
      }
      var mainVoiceCount = sequence.voices.length ? 1 : 0;
      for (var chapterIndex = 1; chapterIndex < sequence.voices.length; chapterIndex++) {
        if (Number(sequence.voices[chapterIndex].start) - Number(sequence.voices[chapterIndex - 1].end) > settings.voiceGroupGap) break;
        mainVoiceCount++;
      }
      if (state.backendPromise) await state.backendPromise;
      var backendLabel = state.backend && state.backend.label ? state.backend.label : "CPU fallback";
      var notes = [];
      if (!sequence.v1LooksNested) notes.push("V1 chưa được Premiere nhận diện rõ là nested sequence");
      if (sequence.voices.length > mainVoiceCount) notes.push((sequence.voices.length - mainVoiceCount) + " clip A2 sau gap sẽ được giữ nguyên");
      var message = "Sẵn sàng dựng · V1+A1 linked · " + mainVoiceCount + " chapter voice · " + srt.cueCount + " cue SRT · " + backendLabel + ".";
      if (notes.length) message += "\nLưu ý: " + notes.join("; ") + ".";
      diagnosticStatus(message, notes.length ? "warn" : "ok");
      log("Chẩn đoán hoàn tất: " + message.replace(/\n/g, " "), notes.length ? "muted" : "ok");
      localFeedback("supportFeedback", "Đã kiểm tra đầu vào; xem kết quả chẩn đoán bên trên.");
    } catch (error) {
      diagnosticStatus("Chưa sẵn sàng: " + error.message, "error");
      log("Chẩn đoán: " + error.message, "error");
      var diagnosticField = error.pvsInputField || (/SRT/i.test(error.message) ? "srtCandidates" : null);
      showWorkflowNotice("Cần sửa đầu vào", diagnosticField ? inputMessage(error.message, diagnosticField) : "Kiểm tra nguồn trên timeline; mở Chi tiết để xem nguyên nhân.", "error", { kind: diagnosticField ? "validation" : "failure", fieldId: diagnosticField, impact: "unchanged", details: error.message });
    } finally {
      setWorkflowBusy(false);
    }
  }
  async function runSync() {
    return runSyncWorkflow();
  }
  async function runPerformanceTrial() {
    return runSyncWorkflow({ diagnostic: true });
  }
  async function runFastPerformanceTrial() {
    return runSyncWorkflow({ diagnostic: true, fast: true });
  }
  function waitPerformanceCheckpoint(stage) {
    var message = "Xong " + stage + ". Thử scrub/Play, dừng playback rồi chọn kết quả bên dưới. Không sửa clip, đổi sequence hoặc lưu timeline đang dựng dở. Chọn Dừng không hoàn tác các bước đã dựng.";
    status("CHẨN ĐOÁN · " + message, "warn");
    var choice = confirmWorkflowNotice("Kiểm tra Preview/Play", message, "Play bình thường — Tiếp tục", "Preview/Play bị đơ — Dừng", true);
    state.performanceChoice = true;
    return choice.then(function (healthy) { state.performanceChoice = null; return healthy; });
  }
  function choosePerformanceCheckpoint(healthy) {
    if (!state.performanceChoice) return;
    chooseWorkflowNotice(healthy);
  }
  async function executeStagedPlan(planPath, pauseAtStages, fastProfile, workflow, metrics, noDelay) {
    await waitForWorkflowPause();
    await ensureHostLoaded();
    var diagnosticPath = path.join(extensionRoot(), "jsx", "diagnostic-executor.jsx");
    security.assertNoLinks(fs, path, diagnosticPath, true);
    var loaded = await evalRaw('(function(){try{if(typeof $._PVS.diagnosticInfo!=="function")$.evalFile(new File(' + jsxString(diagnosticPath) + '));return $._PVS.diagnosticInfo();}catch(e){return $._PVS._result({ok:false,error:String(e)});}}())');
    var info = JSON.parse(loaded);
    var crypto = nodeRequire("crypto");
    var baseHash = crypto.createHash("sha256").update(fs.readFileSync(path.join(extensionRoot(), "jsx", "host.jsx"), "utf8").replace(/\r\n/g, "\n")).digest("hex");
    if (!info.ok || info.revision !== "staged-edit-v3" || info.baseHash !== baseHash) throw new Error("Bộ dựng chia đợt không khớp executor gốc. Timeline chưa được chỉnh.");
    var profile = noDelay ? "no-delay" : fastProfile ? "fast" : "baseline";
    var yieldMilliseconds = noDelay ? 0 : fastProfile ? 20 : 150;
    var token = String(Date.now()) + "_" + crypto.randomBytes(12).toString("hex");
    var tracePath = "", traceDisabled = false;
    function disableTrace() {
      if (!traceDisabled) log("Không ghi được nhật ký timeline. Tác vụ vẫn tiếp tục; các kiểm tra timeline không bị bỏ qua.", "warn");
      traceDisabled = true;
    }
    try {
      var logsRoot = path.join(applicationDataRoot(), "Logs");
      security.assertNoLinks(fs, path, logsRoot, false);
      fs.mkdirSync(logsRoot, { recursive: true });
      tracePath = path.join(logsRoot, "Performance_" + timestamp() + "_" + token + ".jsonl");
      security.assertNoLinks(fs, path, tracePath, false);
      fs.writeFileSync(tracePath, JSON.stringify({ type: "start", revision: info.revision, baseHash: baseHash, profile: profile, workflow: workflow || "diagnostic", yieldMilliseconds: yieldMilliseconds, batchLimitsDisabled: false, nativeSpeedPairsPerBatch: 4, captionCleanupDelayMilliseconds: noDelay ? 0 : 50, pauseAtStages: pauseAtStages, createdAt: new Date().toISOString() }) + "\n", { encoding: "utf8", flag: "wx" });
      if (metrics) metrics.linkTimeline(path.basename(tracePath));
      log("Nhật ký hiệu năng chỉ lưu tên bước/thời gian, không có lời nói hay đường dẫn media: " + tracePath, "muted");
    } catch (ignoreTraceCreate) { disableTrace(); }
    var began = false, finished = false;
    function record(value) {
      if (traceDisabled) return;
      try {
        security.assertNoLinks(fs, path, tracePath, false);
        fs.appendFileSync(tracePath, JSON.stringify(value) + "\n", "utf8");
      } catch (ignoreTraceWrite) { disableTrace(); }
    }
    try {
      if (runContext) runContext.impact = "unknown";
      var begun = await evalHost("$._PVS.beginDiagnosticEdit(" + jsxString(planPath) + "," + jsxString(token) + "," + jsxString(profile) + ")");
      if (!begun.ok) throw new Error(begun.error || "Không khởi tạo được phiên chẩn đoán.");
      began = true;
      var nextCall = begun.nextCall;
      var nextStage = begun.nextStage;
      var lastLoggedStage = "";
      while (true) {
        await waitForWorkflowPause();
        throwIfStopRequested();
        // Default Auto edit skips the timer entirely (not setTimeout(0)).
        // CEP native calls still complete serially via their normal callbacks.
        if (yieldMilliseconds > 0) await new Promise(function (resolve) { window.setTimeout(resolve, yieldMilliseconds); });
        throwIfStopRequested();
        record({ type: "request", call: nextCall, stage: nextStage, at: new Date().toISOString() });
        var requestedAt = Date.now();
        var response = await evalHost("$._PVS.advanceDiagnosticEdit(" + jsxString(token) + "," + Number(nextCall) + ")");
        if (runContext) {
          runContext.lastProgress = Date.now();
          var mutation = response.done && response.result ? response.result.timelineMutated : response.timelineMutated;
          if (mutation === true) runContext.impact = "changed";
          else if (mutation === false && runContext.impact !== "changed") runContext.impact = "unchanged";
        }
        record({ type: "response", call: nextCall, wallMilliseconds: Date.now() - requestedAt, ok: response.ok, done: response.done, stage: response.stage || "", hostMilliseconds: response.milliseconds, checkpoint: response.checkpoint || "" });
        if (response.done) {
          finished = true;
          record({ type: "finish", ok: !!(response.result && response.result.ok), timings: response.timings || [] });
          if (!response.result) throw new Error("Chẩn đoán không trả về hậu kiểm.");
          if (response.result.ok) throwIfStopRequested();
          return response.result;
        }
        if (!response.ok) throw new Error(response.error || "Chẩn đoán dừng trước khi hoàn tất.");
        throwIfStopRequested();
        if (!fastProfile || response.stage !== lastLoggedStage) {
          log("Dựng " + response.stageIndex + "/" + response.stageCount + " · " + response.stage + " · " + response.milliseconds + " ms.", "muted");
          lastLoggedStage = response.stage;
        }
        nextCall = response.nextCall;
        nextStage = response.nextStage;
        if (pauseAtStages && response.checkpoint) {
          var healthy = await waitPerformanceCheckpoint(response.checkpoint);
          throwIfStopRequested();
          record({ type: "user-observation", checkpoint: response.checkpoint, previewHealthy: healthy });
          if (!healthy) {
            var aborted = await evalHost("$._PVS.abortDiagnosticEdit(" + jsxString(token) + ")");
            finished = true;
            record({ type: "stopped", timings: aborted.timings || [] });
            throw new Error("Đã dừng tại bước " + response.checkpoint + " do Preview/Play bị đơ. Timeline mới dựng một phần; không lưu kết quả này. Hãy Undo hoặc mở lại bản đã lưu.");
          }
        }
      }
    } finally {
      if (state.performanceChoice) closeWorkflowNotice();
      state.performanceChoice = null;
      if (began && !finished) {
        try {
          var abortResult = await evalHost("$._PVS.abortDiagnosticEdit(" + jsxString(token) + ")");
          if (runContext && abortResult.result && typeof abortResult.result.timelineMutated === "boolean") runContext.impact = abortResult.result.timelineMutated ? "changed" : "unchanged";
        } catch (ignoreAbort) { if (runContext) runContext.impact = "unknown"; }
      }
    }
  }
  async function runSyncWorkflow(options) {
    if (state.workflowBusy || recoveryContext) return;
    options = options || {};
    var enhanced = !options.diagnostic;
    var performanceTrial = !!options.diagnostic;
    var fastPerformance = enhanced || options.fast === true;
    var speedMergeRequested = enhanced;
    var pauseAtStages = performanceTrial && !fastPerformance && !!byId("pausePerformanceTrial").checked;
    var directStarted = false;
    var started = Date.now();
    var jobsRoot = "";
    var outputFolder = "";
    var metrics = null, outcome = "failed", completedMessage = "";
    try {
      setWorkflowBusy(true);
      beginRun("edit");
      if (state.backendPromise) await state.backendPromise;
      throwIfStopRequested();
      var sequence = await scanSequence();
      throwIfStopRequested();
      runContext.baseline = JSON.stringify(sequence);
      await waitForWorkflowPause();
      var settings = readSettings();
      var language = readVoiceLanguage();
      var joinedReference = srtJoin && srtJoin.read();
      if (!joinedReference && (!state.targetSrt || !fs.existsSync(state.targetSrt))) throw new Error("Hãy chọn SRT cùng ngôn ngữ với voice.");
      var initialPrompt = "Chương trình sẽ dựng lại hình và audio theo voice, đồng thời thêm phụ đề. Hãy lưu bản hiện tại trước khi bắt đầu; chương trình không tự lưu.";
      if (performanceTrial) initialPrompt = "CHẨN ĐOÁN HIỆU NĂNG — dựng thử theo đợt nhỏ trên template sạch.\n\nGiữ nguyên kế hoạch ổn định; không dùng điểm cắt DTW hay gộp đoạn. Không tự lưu hoặc xóa Undo.\n\n" + (pauseAtStages ? "Tool dừng sau các nhóm để bạn thử Play. Không sửa clip/đổi sequence, không lưu timeline dựng dở. Dừng khi lag thì cần Undo hoặc mở lại bản đã lưu." : "Chạy liên tục theo các đợt nhỏ, ghi thời gian từng bước. Sau cùng kiểm Play và Save.");
      if (performanceTrial && fastPerformance) initialPrompt = "DỰNG CHIA ĐỢT NHANH — CHẨN ĐOÁN trên template sạch.\n\nDùng kế hoạch câu cơ sở để đối chiếu, không dùng điểm cắt DTW/gộp đoạn. Không tự lưu, Play hoặc xóa Undo.\n\nKhông sửa clip/đổi sequence trong lúc chạy; kiểm Preview, Play và Save sau cùng.";
      if (!await confirmWorkflowNotice(performanceTrial ? "Xác nhận dựng chẩn đoán" : "Dựng sequence “" + sequence.name + "”?", initialPrompt, "Bắt đầu dựng", "Hủy")) {
        throwIfStopRequested();
        status("Đã hủy.", "muted");
        return;
      }
      if (runContext.fatal) throw new Error("Tác vụ dừng do lỗi giao diện trong khi chờ xác nhận.");
      await waitForWorkflowPause();

      metrics = createWorkflowMetrics(enhanced ? "auto-edit" : "diagnostic-edit");
      runContext.metrics = metrics;
      metrics.begin("preflight");
      jobsRoot = path.join(applicationDataRoot(), "Jobs");
      outputFolder = path.join(jobsRoot, "Job_" + timestamp() + "_" + String(Date.now()));
      security.assertNoLinks(fs, path, outputFolder, false);
      fs.mkdirSync(outputFolder, { recursive: true });
      runContext.outputFolder = outputFolder;
      var jobPath = path.join(outputFolder, "job.json");
      var targetReferencePath = joinedReference ? srtJoin.write(joinedReference, outputFolder) : state.targetSrt;
      if (joinedReference) log("Đã nối " + joinedReference.files.length + " SRT thành " + joinedReference.cueCount + " cue theo thứ tự đã chọn.", "ok");
      var job = {
        schemaVersion: 2,
        workflow: "one-click-direct",
        createdAt: new Date().toISOString(),
        sequence: sequence,
        targetSrtPath: targetReferencePath,
        language: language,
        outputFolder: outputFolder,
        speedWarningMinPercent: settings.minSpeed,
        speedWarningMaxPercent: settings.maxSpeed,
        algorithm: {
          minNoDialogueGapSeconds: settings.minDialogueGap,
          silenceNoiseDb: fixedAlgorithm.silenceDb,
          minSilenceDurationSeconds: fixedAlgorithm.minSilence,
          boundarySearchSeconds: fixedAlgorithm.boundaryWindow,
          voiceGroupGapSeconds: settings.voiceGroupGap,
          lowConfidenceThreshold: fixedAlgorithm.confidence,
          sentenceEndCharacters: fixedAlgorithm.sentenceEndChars,
          maxCaptionCharacters: settings.maxCaptionCharacters,
          voiceMappingToleranceFrames: fixedAlgorithm.voiceMapFrames,
          validationToleranceFrames: fixedAlgorithm.validationFrames,
          maxCoverageGapFrames: fixedAlgorithm.coverageFrames,
          useWhisperCache: fixedAlgorithm.useCache
        },
        createCaption: true
      };
      if (enhanced) {
        job.workflow = "one-click-dtw-direct";
        job.editBoundaryTrial = "dtw-additive-v1";
        job.speedMergeTrial = "adjacent-speed-v2";
        log("Thuật toán mặc định: DTW + gộp hình một lần ngoài ngưỡng + dựng không delay.", "ok");
      }
      fs.writeFileSync(jobPath, JSON.stringify(job, null, 2), "utf8");
      if (enhanced) {
        status("Đang kiểm tra đầu vào DTW trước khi nhận diện...", "muted");
        await runPowerShell(path.join(extensionRoot(), "engine", "build-dtw-trial-plan.ps1"), ["-JobPath", jobPath, "-ValidateOnly"]);
        if (speedMergeRequested) await runPowerShell(path.join(extensionRoot(), "engine", "build-speed-merge-trial-plan.ps1"), ["-JobPath", jobPath, "-ValidateOnly"]);
        log("DTW: giữ tốc độ voice hiện tại, quy đổi timestamp và khoảng lặng theo từng chapter.", "ok");
        var trialVoices = sequence.voices.slice().sort(function (a, b) { return Number(a.start) - Number(b.start); });
        for (var chapterIndex = 0; chapterIndex < trialVoices.length; chapterIndex++) {
          if (chapterIndex > 0 && Number(trialVoices[chapterIndex].start) - Number(trialVoices[chapterIndex - 1].end) > settings.voiceGroupGap) break;
          log("Voice chapter " + (chapterIndex + 1) + ": speed " + Number(trialVoices[chapterIndex].speedPercent).toFixed(6) + "%; media In " + Number(trialVoices[chapterIndex].inPoint).toFixed(6) + "s.", "muted");
        }
      }
      log("Tùy chỉnh áp dụng: cảnh báo speed ngoài " + settings.minSpeed + "–" + settings.maxSpeed + "%; gap không lời ≥ " + settings.minDialogueGap + "s; gap tách nhóm voice " + settings.voiceGroupGap + "s.", "ok");
      metrics.end();

      log("Ngôn ngữ nhận diện voice: " + language + ".", "muted");
      status("1/3 · Đang nhận diện và căn voice...", "muted");
      runStage("alignment");
      var phase = Date.now();
      metrics.begin("alignment");
      await runPowerShell(path.join(extensionRoot(), "engine", "run-alignment.ps1"), ["-JobPath", jobPath]);
      var alignment = JSON.parse(fs.readFileSync(path.join(outputFolder, "alignment-result.json"), "utf8").replace(/^\uFEFF/, ""));
      metrics.end(alignment);
      if (alignment.preserveTimeline === true) {
        completedMessage = preservedRecognitionNotice(alignment, false);
        outcome = "success";
        return;
      }
      state.backend = {
        backend: alignment.recognitionBackend,
        label: alignment.recognitionBackendLabel,
        reason: alignment.gpuFallbackUsed ? ("GPU lỗi trong tác vụ; đã tự chạy lại bằng CPU. " + alignment.gpuFallbackReason) : alignment.backendReason
      };
      renderBackend(state.backend);
      log((alignment.audioCache && alignment.audioCache.whisperMisses === 0 ? "Nhận diện dùng cache; backend sẵn sàng: " : "Backend thực tế: ") + alignment.recognitionBackendLabel + (alignment.gpuFallbackUsed ? "; đã fallback vì: " + alignment.gpuFallbackReason : "") + ".", alignment.recognitionBackend === "cpu" ? "muted" : "ok");
      if (alignment.gpuFallbackUsed) runWarning("GPU gặp lỗi; đã nhận diện lại bằng CPU. Kết quả tiếp tục được kiểm tra như bình thường.");
      if (alignment.wordTimingRecoveredCueCount) log("Đã nhận diện lại vùng bị Whisper bỏ sót: cue " + alignment.wordTimingRecoveredCues.join(", ") + ". Không dùng timestamp ước lượng để chia caption.", "muted");
      if ((alignment.omittedReferenceCueIndices || []).length) log("Voice đã bỏ cue SRT " + alignment.omittedReferenceCueIndices.join(", ") + ". Đã kiểm tra lại các chỗ nối; kế hoạch sẽ bỏ hình và A1 tương ứng theo timestamp SRT.", "warn");
      if ((alignment.numericCaptionRefinedCues || []).length) log("Đã căn riêng caption quanh số: cue " + alignment.numericCaptionRefinedCues.join(", ") + ".", "muted");
      if ((alignment.numericCaptionReviewCues || []).length) log("Tinh chỉnh số giữ mốc đã căn tại cue " + alignment.numericCaptionReviewCues.join(", ") + ".", "muted");
      logCaptionTiming(alignment);
      if ((alignment.autoEditManualReviewBlocks || []).length) log("Có " + alignment.autoEditManualReviewBlocks.length + " vùng cần sửa tay: giữ toàn bộ hình/voice thành khối, caption chưa chắc có marker để rà lại. Các vùng đã xác minh tiếp tục dựng.", "warn");
      if ((alignment.autoEditReferenceRecoveredCueIndices || []).length) log("Đã phục hồi chữ SRT bằng lớp đối chiếu dùng chung: cue " + alignment.autoEditReferenceRecoveredCueIndices.join(", ") + ". Giữ nhóm voice quanh câu cần rà; xem marker trên caption.", "warn");
      log("Căn voice: " + ((Date.now() - phase) / 1000).toFixed(1) + " giây.", "ok");

      status("2/3 · Đang lập kế hoạch theo câu...", "muted");
      runStage("planning");
      phase = Date.now();
      metrics.begin("sentence-plan");
      await runPowerShell(path.join(extensionRoot(), "engine", "build-sentence-plan.ps1"), ["-JobPath", jobPath]);
      var planPath = path.join(outputFolder, "sentence-edit-plan.json");
      var plan = JSON.parse(fs.readFileSync(planPath, "utf8").replace(/^\uFEFF/, ""));
      if (!plan.ok || Number(plan.schemaVersion) !== 8) throw new Error("Planner không tạo được kế hoạch workflow 8.");
      metrics.end(plan);
      logAudioCache(plan, "tìm điểm cắt");
      log("Lập kế hoạch: " + ((Date.now() - phase) / 1000).toFixed(1) + " giây; " + plan.summary.punctuationSentenceCount + " câu, " + plan.summary.safeSentenceGroupCount + " đoạn cắt voice an toàn.", "ok");
      log("Caption: " + plan.summary.captionCueCount + " đoạn, tối đa " + settings.maxCaptionCharacters + " ký tự/đoạn; " + Number(plan.summary.voiceAlignedCaptionBoundaryCount || 0) + " ranh giới bám word timestamp.", "ok");
      if (plan.captionMappingReviewCues && plan.captionMappingReviewCues.length) log("Mốc caption mới xung đột với caption bên cạnh; giữ cách căn dự phòng và cần nghe lại cue SRT: " + plan.captionMappingReviewCues.join(", ") + ".", "warn");
      if (Number(plan.summary.recoveredUnalignedCueCount || 0) > 0) {
        log("Đã nội suy an toàn " + plan.summary.recoveredUnalignedCueCount + " cue thiếu timestamp; clip voice A2 sẽ có marker để kiểm tra.", "muted");
      }
      if (Number(plan.summary.unsafeBoundaryMergeCount || 0) > 0) {
        log("Đã gộp " + plan.summary.unsafeBoundaryMergeCount + " ranh giới câu không có khoảng lặng đủ an toàn; không cắt vào lời nói.", "muted");
      }

      if (enhanced) {
        status("2/3 · Đang đối chiếu kế hoạch DTW...", "muted");
        metrics.begin("dtw-plan");
        await runPowerShell(path.join(extensionRoot(), "engine", "build-dtw-trial-plan.ps1"), ["-JobPath", jobPath]);
        var trial = JSON.parse(fs.readFileSync(path.join(outputFolder, "dtw-trial-report.json"), "utf8").replace(/^\uFEFF/, ""));
        if (!trial.ok || trial.revision !== "dtw-additive-v1") throw new Error("Báo cáo DTW không hợp lệ.");
        logAudioCache(trial, "đối chiếu DTW");
        if (Number(trial.addedCutCount) > 0) {
          var expectedTrialPath = path.join(outputFolder, "dtw-trial", "sentence-edit-plan.json");
          if (trial.canApply !== true || trial.coverageVerified !== true || trial.existingCutsPreserved !== true || Number(trial.durationChangedFrames) !== 0 || Number(trial.newPauses) !== 0 || !(Number(trial.addedCutCount) > 0) || path.resolve(trial.planPath) !== path.resolve(expectedTrialPath)) throw new Error("Kế hoạch DTW không vượt qua kiểm bảo toàn.");
          security.assertNoLinks(fs, path, expectedTrialPath, true);
          planPath = expectedTrialPath;
          plan = JSON.parse(fs.readFileSync(planPath, "utf8").replace(/^\uFEFF/, ""));
          if (!plan.ok || Number(plan.schemaVersion) !== 8 || plan.editBoundaryTrial !== "dtw-additive-v1" || plan.sequenceId !== sequence.sequenceId) throw new Error("Kế hoạch DTW không khớp sequence vừa đọc.");
          log("DTW: " + trial.stableGroups + " → " + trial.trialGroups + " nhóm; thêm " + trial.addedCutCount + " điểm cắt; cảnh báo speed " + trial.stableSpeedWarnings + " → " + trial.trialSpeedWarnings + ". Bảo toàn hình/voice, thời lượng và khoảng không lời.", "warn");
          trial.boundaries.forEach(function (boundary) { log("Điểm cắt mới: chapter " + (Number(boundary.Chapter) + 1) + ", cue " + boundary.LeftCue + "/" + boundary.RightCue + ", frame voice gốc " + boundary.CutFrame + ".", "muted"); });
        } else if (Number(trial.addedCutCount) !== 0 || trial.canApply !== false) {
          throw new Error("Báo cáo DTW không có điểm cắt không hợp lệ.");
        }
        metrics.end(trial);
        var mergeSummary = "";
        if (speedMergeRequested) {
          status("2/3 · Đang cân bằng tốc độ hình...", "muted");
          metrics.begin("speed-merge");
          await runPowerShell(path.join(extensionRoot(), "engine", "build-speed-merge-trial-plan.ps1"), ["-JobPath", jobPath, "-PlanPath", planPath]);
          var merge = JSON.parse(fs.readFileSync(path.join(outputFolder, "speed-merge-report.json"), "utf8").replace(/^\uFEFF/, ""));
          var mergePath = path.join(outputFolder, "speed-merge-trial", "sentence-edit-plan.json");
          if (!merge.ok || merge.revision !== "adjacent-speed-v2" || merge.coverageVerified !== true || merge.voiceUnchanged !== true || merge.captionsUnchanged !== true || Number(merge.durationChangedFrames) !== 0 || Number(merge.newPauses) !== 0 || !merge.summary || !(Number(merge.summary.mergeCount) >= 0) || merge.canApply !== (Number(merge.summary.mergeCount) > 0) || path.resolve(merge.planPath) !== path.resolve(mergePath)) throw new Error("Kế hoạch gộp tốc độ không vượt qua kiểm bảo toàn.");
          security.assertNoLinks(fs, path, mergePath, true);
          planPath = mergePath;
          plan = JSON.parse(fs.readFileSync(planPath, "utf8").replace(/^\uFEFF/, ""));
          if (!plan.ok || Number(plan.schemaVersion) !== 8 || plan.speedMergeTrial !== "adjacent-speed-v2" || !Array.isArray(plan.visualSegments) || plan.sequenceId !== sequence.sequenceId) throw new Error("Kế hoạch gộp tốc độ không khớp sequence.");
          metrics.end();
          mergeSummary = "\nCân bằng tốc độ: " + merge.summary.visualGroupsBefore + " → " + merge.summary.visualGroupsAfter + " đoạn hình; " + merge.summary.mergeCount + " cặp gộp một lần; cảnh báo " + merge.summary.warningsBefore + " → " + merge.summary.warningsAfter + ".\nKhông gộp tiếp các cặp đã gộp. A2 và caption giữ nguyên; hình có thể gộp nhiều câu và qua chapter liền nhau.";
          log(mergeSummary, "muted");
        }

      }

      plan.reviewMarkers = buildReviewMarkers(alignment, plan);
      fs.writeFileSync(planPath, JSON.stringify(plan, null, 2), "utf8");
      var executorPath = writeHostInput(plan, "edit", outputFolder);
      status("3/3 · Đang dựng trực tiếp và hậu kiểm...", "muted");
      runStage("timeline");
      metrics.begin("template-check");
      {
        var diagnosticSequence = await scanSequence();
        if (JSON.stringify(diagnosticSequence) !== JSON.stringify(sequence)) throw new Error("Template đã thay đổi trong lúc phân tích. Timeline chưa được tool chỉnh; hãy dùng template sạch.");
      }
      metrics.end();
      directStarted = true;
      phase = Date.now();
      metrics.begin("timeline");
      var result = await executeStagedPlan(executorPath, pauseAtStages, fastPerformance, enhanced ? "auto-edit-dtw-merge" : "diagnostic-baseline", metrics, enhanced);
      if (typeof result.timelineMutated === "boolean") runContext.impact = result.timelineMutated ? "changed" : "unchanged";
      if (result && result.timelineMutated === false) directStarted = false;
      fs.writeFileSync(path.join(outputFolder, "direct-apply-report.json"), JSON.stringify(result, null, 2), "utf8");
      logReviewMarkers(result, plan.reviewMarkers, plan);
      if (!result.ok || Number(result.executorVersion) !== 25) throw new Error(postcheckError(result));
      metrics.end(result);
      if (Number(result.tailShiftFrames || 0) > 0) log("Đã dời " + Number(result.tailShiftItemCount || 0) + " element cuối timeline thêm " + Number(result.tailShiftFrames) + " frame để theo đuôi video mới.", "ok");
      if (result.speedMetadataReadable) log("Tốc độ Premiere thực tế: " + Number(result.minimumObservedSpeedPercent).toFixed(3) + "–" + Number(result.maximumObservedSpeedPercent).toFixed(3) + "%; sai số metadata lớn nhất " + Number(result.maxSpeedMetadataErrorPercent || 0).toFixed(3) + "%.", "ok");
      else log("Premiere không cung cấp API đọc lại speed cho ít nhất một clip; marker cảnh báo vẫn dùng speed đã tính chính xác theo frame.", "muted");
      log("Caption Track đã được tạo; không giữ file sentence-plan.vi.srt trong Project.", "ok");
      log("Marker: đã xóa " + Number(result.clearedClipMarkerCount || 0) + " marker cũ của tool; đánh dấu " + Number(result.mergeClipMarkerCount || 0) + " đoạn hình đã gộp. Giữ marker người dùng.", "ok");
      if (Number(result.clipMarkerColorFailureCount || 0) > 0) log("Premiere chưa đặt đúng màu cho " + Number(result.clipMarkerColorFailureCount) + " marker. Vị trí/ghi chú vẫn được kiểm tra; xem tên và ghi chú để phân biệt.", "warn");
      log("Dựng timeline: " + ((Date.now() - phase) / 1000).toFixed(1) + " giây.", "ok");
      var successMessage = "Hoàn tất trong " + ((Date.now() - started) / 1000).toFixed(1) + " giây · " + (plan.pictureCueSummary ? plan.pictureCueSummary.sourceCueCount : plan.summary.punctuationSentenceCount) + " cue nguồn · " + Number(result.pictureCueCount || result.voiceCueCount) + " đoạn hình · " + result.voiceCueCount + " đoạn voice · " + result.captionCueCount + " caption · khe hở hình 0 frame. Project chưa được lưu.";
      if (Number(result.reviewMarkerCount || 0)) successMessage += " Có " + result.reviewMarkerCount + " marker cần kiểm tra trên thước timeline.";
      var manualSummary = manualReviewSummary(plan);
      if (manualSummary.timingBlocks || manualSummary.pendingReferenceCues) successMessage += " Còn " + manualSummary.timingBlocks + " vùng timing ước lượng; " + manualSummary.pendingReferenceCues + " câu SRT chưa khớp đầy đủ. Các phần có bằng chứng âm thanh đã được căn tự động.";
      if (manualSummary.timingBlocks || manualSummary.pendingReferenceCues) runWarning("Còn " + manualSummary.timingBlocks + " vùng timing ước lượng; " + manualSummary.pendingReferenceCues + " câu SRT chưa khớp đầy đủ. Xem các đoạn được đánh dấu.", true);
      if ((plan.sourceGapReviewRanges || []).length) successMessage += " Có " + plan.sourceGapReviewRanges.length + " khoảng không lời chưa tách vì thiếu điểm cắt voice an toàn; xem marker để rà tay.";
      if ((result.omittedReferenceCueIndices || []).length) successMessage += " Đã bỏ hình/A1 ứng với " + result.omittedReferenceCueIndices.length + " cue không còn trong voice (" + (Number(result.omittedSourceFrameCount) / plan.frameRate).toFixed(2) + " giây hình nguồn).";
      if (speedMergeRequested && plan.speedMergeSummary && !plan.pictureCueRevision) successMessage += " Hình sau cân bằng: " + plan.speedMergeSummary.visualGroupsAfter + " đoạn; A2 giữ " + result.voiceCueCount + " đoạn voice.";
      if (enhanced) successMessage += " Đã dùng quy trình DTW/gộp hình/dựng không delay; " + Number(result.mergeClipMarkerCount || 0) + " đoạn hình gộp có marker. Hãy kiểm kết quả trước khi lưu.";
      if (Number(result.clipMarkerColorFailureCount || 0) > 0) successMessage += " Có " + Number(result.clipMarkerColorFailureCount) + " marker chưa đặt đúng màu; xem Hỗ trợ và nhật ký.";
      if (performanceTrial) successMessage = "CHẨN ĐOÁN · " + successMessage + " Hậu kiểm timeline không xác nhận hết lag; hãy kiểm Preview/Play và khả năng lưu.";
      if (Number(result.speedWarningSentenceCount || 0)) {
        if (plan.pictureCueRevision) log(result.speedWarningSentenceCount + " đoạn hình dùng tốc độ ngoài khoảng để khớp cue/voice; giữ trong chẩn đoán. Marker tốc độ dành cho kết quả native chưa đọc được hoặc sai kế hoạch.", "muted");
        else runWarning(result.speedWarningSentenceCount + " đoạn ngoài ngưỡng tốc độ; kiểm tra marker đỏ/cam.", true);
      }
      runContext.resultHeadline = (manualSummary.timingBlocks || manualSummary.pendingReferenceCues) ? "Đã dựng — còn một số đoạn cần rà." : "Đã dựng xong.";
      completedMessage = successMessage;
      outcome = "success";
    } catch (error) {
      if (error.pvsCancelled) outcome = "cancelled";
      if (metrics) metrics.end(null, outcome);
      var failureMessage = error.message + (directStarted ? " Hãy Undo hoặc đóng project không lưu." : "");
      if (enhanced && error.message.indexOf("TRIAL_VOICE_MEDIA_IN_NONZERO") >= 0) failureMessage = "DTW chưa hỗ trợ voice đã trim phần đầu media. Hãy dùng template có đầu voice nguyên vẹn; speed voice vẫn được giữ. Timeline chưa được tool chỉnh.\n\n" + failureMessage;
      if (!error.pvsCancelled) reportRunFailure(inputError(failureMessage, error.pvsInputField), "Dựng theo voice — Không hoàn tất");
    } finally {
      if (outputFolder) {
        runStage("cleanup");
        if (metrics) metrics.begin("cleanup");
        try {
          removeTreeSafe(outputFolder, jobsRoot);
          log("Đã xóa toàn bộ file tạm của lần chạy.", "ok");
          if (fs.existsSync(jobsRoot) && fs.readdirSync(jobsRoot).length === 0) fs.rmdirSync(jobsRoot);
          if (metrics) metrics.end();
        } catch (cleanupError) {
          if (metrics) metrics.end(null, "failed");
          log("Không dọn hết file tạm: " + cleanupError.message, "error");
          runWarning("Không dọn hết file tạm. Xem nhật ký; không cần dựng lại chỉ để dọn file.");
          appendCleanupNotice(cleanupError);
        }
      }
      if (runContext && runContext.fatal) outcome = "failed";
      if (metrics) metrics.finish(outcome);
      if (outcome === "cancelled") reportRunCancelled();
      if (completedMessage) finishRunNotice("Dựng theo voice", completedMessage);
      runContext = null;
      saveRecoveryJournal();
      setWorkflowBusy(false);
    }
  }
  function setMode(mode) {
    state.mode = mode === "captions" ? "captions" : "edit";
    Array.prototype.forEach.call(document.querySelectorAll(".edit-only"), function (element) { element.hidden = state.mode !== "edit"; });
    Array.prototype.forEach.call(document.querySelectorAll(".caption-only"), function (element) { element.hidden = state.mode !== "captions"; });
    ["modeEdit", "modeCaptions"].forEach(function (id) {
      var active = (id === "modeCaptions") === (state.mode === "captions");
      byId(id).className = "button workflow-tab" + (active ? " active" : "");
      byId(id).setAttribute("aria-pressed", String(active));
    });
    if (srtJoin) srtJoin.render();
  }
  function renderCaptionSrtCandidates(candidates) {
    var select = byId("captionSrtCandidates");
    select.innerHTML = "";
    var automatic = document.createElement("option");
    automatic.value = ""; automatic.textContent = "Tự nhận diện · không dùng SRT"; select.appendChild(automatic);
    candidates.forEach(function (item) {
      var option = document.createElement("option"); option.value = item.path; option.textContent = item.name; option.title = item.path; select.appendChild(option);
    });
    var selectedInProject = candidates.some(function (item) { return state.captionSrt && item.path.toLowerCase() === state.captionSrt.toLowerCase(); });
    // Read the current choice after the asynchronous scan. An explicit empty
    // choice means ASR only and must survive refreshes and tab changes too.
    if (state.captionSrtExplicit || selectedInProject) setCaptionSrt(state.captionSrt, true);
    else if (candidates.length === 1 || (candidates.length > 1 && candidates[0].score > candidates[1].score)) setCaptionSrt(candidates[0].path, true);
    else {
      setCaptionSrt("", true);
      if (candidates.length) byId("captionSrtHint").textContent = "Tìm thấy " + candidates.length + " SRT trong Project, chưa xác định được file ưu tiên. Hãy chọn SRT đúng lời nói hoặc giữ Tự nhận diện · không dùng SRT.";
    }
  }
  function setCaptionSrt(filePath, automatic) {
    if (filePath && !/\.srt$/i.test(filePath)) throw new Error("Không đọc được SRT đã chọn.");
    if (!automatic) state.captionSrtExplicit = true;
    if (inlineValidation && inlineValidation.fieldId === "captionSrtCandidates") closeWorkflowNotice();
    state.captionSrt = filePath ? path.normalize(filePath) : "";
    var select = byId("captionSrtCandidates");
    noticeAttribute(select, "aria-invalid", "false");
    byId("captionSrtHint").className = "hint"; noticeAttribute(byId("captionSrtHint"), "role", "status");
    if (state.captionSrt) {
      var exists = Array.prototype.some.call(select.options, function (option) { return String(option.value).toLowerCase() === state.captionSrt.toLowerCase(); });
      if (!exists) {
        var option = document.createElement("option"); option.value = state.captionSrt; option.textContent = "Ngoài Project — " + path.basename(state.captionSrt); select.appendChild(option);
      }
    }
    select.value = state.captionSrt;
    byId("captionSrtHint").textContent = state.captionSrt ? "Giữ chữ và căn thời gian theo audio: " + path.basename(state.captionSrt) : "Tự nhận diện lời nói; không dùng SRT.";
    byId("captionSrtHint").title = state.captionSrt;
  }
  function renderCaptionVoiceTracks(range) {
    var key = JSON.stringify([range.projectId, range.sequenceId]);
    if (!state.captionConfigs[key]) state.captionConfigs[key] = { sourceMode: "auto", scopeMode: "whole", trackIndices: null };
    state.captionConfig = state.captionConfigs[key];
    updateCaptionSummary();
    var list = byId("captionTrackList"); list.innerHTML = "";
    (range.audioTracks || []).forEach(function (track) {
      var label = document.createElement("label"), checkbox = document.createElement("input"), text = document.createElement("span");
      label.className = "check"; checkbox.type = "checkbox"; checkbox.id = "captionTrack_" + track.index;
      var chosen = state.captionConfig.sourceMode !== "tracks" || state.captionConfig.trackIndices === null ? state.captionPlan ? state.captionPlan.trackIndices : [] : state.captionConfig.trackIndices;
      checkbox.checked = chosen.indexOf(track.index) >= 0;
      text.textContent = "A" + (track.index + 1) + (track.name ? " · " + track.name : "") + (!track.clipCount ? " · trống" : "") + (track.muted ? " · đang mute" : "");
      checkbox.addEventListener("change", function () {
        var indices = [];
        Array.prototype.forEach.call(list.querySelectorAll("input"), function (input) { if (input.checked) indices.push(Number(input.id.substring("captionTrack_".length))); });
        setCaptionTracks(indices);
      });
      label.appendChild(checkbox); label.appendChild(text); list.appendChild(label);
    });
    syncCaptionInputControls();
  }
  function setCaptionTracks(indices) {
    if (state.workflowBusy || !state.captionConfig || !state.captionRange) return;
    state.captionConfig.sourceMode = "tracks";
    state.captionConfig.trackIndices = indices.slice();
    state.captionConfig.topology = window.PvsCaptionInput.topology(state.captionRange);
    state.captionConfig.anchors = window.PvsCaptionInput.anchors(state.captionRange, indices);
    if (inlineValidation) closeWorkflowNotice();
    renderCaptionVoiceTracks(state.captionRange);
  }
  function syncCaptionInputControls() {
    if (!state.captionConfig) return;
    byId("captionSourceMode").value = state.captionConfig.sourceMode;
    var automatic = state.captionConfig.sourceMode === "auto";
    byId("captionAutomaticHint").textContent = automatic ? "Ưu tiên clip audio đang chọn; nếu không có, gợi ý track có audio." : state.captionConfig.sourceMode === "clips" ? "Chỉ dùng các clip audio đang chọn." : state.captionConfig.sourceMode === "tracks" ? "Dùng các track bạn đã chọn; mở bên dưới để thay đổi." : "Dùng bản phối của tất cả track đang bật.";
    byId("captionScopeMode").value = state.captionConfig.sourceMode === "clips" || automatic && state.captionPlan && state.captionPlan.input.sourceMode === "clips" ? "clips" : automatic && state.captionPlan ? state.captionPlan.input.scopeMode : state.captionConfig.scopeMode;
    byId("captionSourceMode").disabled = state.workflowBusy;
    byId("captionScopeMode").disabled = state.workflowBusy || automatic || state.captionConfig.sourceMode === "clips";
    byId("captionVoiceTrack").disabled = state.workflowBusy || state.captionConfig.sourceMode !== "tracks";
    byId("captionTrackPicker").hidden = state.captionConfig.sourceMode !== "tracks";
    byId("captionScopeControl").hidden = automatic || state.captionConfig.sourceMode === "clips";
    var indices = state.captionConfig.trackIndices === null && state.captionPlan ? state.captionPlan.trackIndices : state.captionConfig.trackIndices || [];
    byId("captionTrackSummary").textContent = indices.length ? "Track đã chọn: " + indices.map(function (index) { return "A" + (index + 1); }).join(", ") + " · Thay đổi" : "Chọn track nguồn";
  }
  function updateCaptionSummary() {
    var range = state.captionRange;
    if (!range || !state.captionConfig) return;
    state.captionPlan = null; state.captionPlanError = null;
    try {
      if (!window.PvsCaptionInput) throw inputError("Không nạp được bộ lập kế hoạch nguồn audio.", "captionSourceMode");
      var automatic = state.captionConfig.sourceMode === "auto";
      // UI preference only: the job/host still receive the existing explicit
      // clips/tracks contract, resolved once from the latest scan then frozen.
      var effectiveConfig = automatic ? { sourceMode: (range.selectedAudio || []).length ? "clips" : "tracks", scopeMode: (range.selectionRanges || []).length ? "selection" : "whole", trackIndices: null } : state.captionConfig;
      var plan = window.PvsCaptionInput.resolve(range, effectiveConfig);
      state.captionPlan = plan;
      var duration = plan.ranges.reduce(function (total, item) { return total + item.end - item.start; }, 0);
      var scopeText = { whole: "Toàn sequence", selection: "Theo thời gian clip đang chọn", inout: "Theo In/Out", clips: "Theo chính các clip audio đang chọn" }[plan.input.scopeMode];
      var sourceText = plan.input.sourceMode === "mix" ? "Tất cả track đang bật" : plan.input.sourceMode === "clips" ? plan.selectedClips.length + " clip audio đã chọn" : "Track chỉ định";
      var names = function (indices) { return indices.map(function (i) { return "A" + (i + 1); }).join(", "); };
      var summary = range.name + "\n" + sourceText + ": " + names(plan.trackIndices) + (automatic ? " · tự động" : "") + "\n" + (plan.input.sourceMode === "clips" ? "" : scopeText + " · ") + plan.ranges.length + " vùng · " + duration.toFixed(1) + " giây";
      if (plan.unmuteTracks.length) summary += "\nMở tiếng tạm: " + names(plan.unmuteTracks) + ".";
      if (plan.skippedRanges.length) summary += "\nBỏ qua " + plan.skippedRanges.length + " vùng không có clip audio từ nguồn đã chọn.";
      if (plan.emptyTracks.length) summary += "\nTrack không có audio trong phạm vi: " + names(plan.emptyTracks) + ".";
      if (plan.disabledCount) summary += "\nBỏ qua " + plan.disabledCount + " clip đã disabled.";
      byId("captionSummary").textContent = summary;
      byId("captionSummary").className = "summary caption-only";
    } catch (error) {
      state.captionPlanError = error;
      byId("captionSummary").textContent = range.name + "\n" + error.message;
      byId("captionSummary").className = "summary error caption-only";
    }
    syncCaptionInputControls();
  }
  async function scanCaptionRange() {
    try {
      var range = await evalHost("$._PVS.scanCaptionRange()");
      if (!range.ok) throw new Error(range.error);
      state.captionRange = range;
      renderCaptionVoiceTracks(range);
      range.plan = state.captionPlan;
      return range;
    } catch (error) {
      state.captionPlan = null; state.captionPlanError = error;
      byId("captionSummary").textContent = error.message;
      byId("captionSummary").className = "summary error caption-only";
      throw error;
    }
  }
  function findWavePreset(applicationFolder) {
    var roots = [applicationFolder];
    try { roots.push(window.__adobe_cep__.getSystemPath("hostApplication")); } catch (ignoreHostPath) {}
    var adobeRoot = path.join(process.env.ProgramFiles || "C:\\Program Files", "Adobe");
    if (fs.existsSync(adobeRoot)) fs.readdirSync(adobeRoot).filter(function (name) { return /^Adobe Premiere Pro/.test(name); }).sort().reverse().forEach(function (name) { roots.push(path.join(adobeRoot, name)); });
    for (var rootIndex = 0; rootIndex < roots.length; rootIndex++) {
      if (!roots[rootIndex]) continue;
      var root = String(roots[rootIndex]);
      if (fs.existsSync(root) && fs.statSync(root).isFile()) root = path.dirname(root);
      var presetFolder = path.join(root, "MediaIO", "systempresets", "3F3F3F3F_57415645");
      if (!fs.existsSync(presetFolder)) continue;
      var files = fs.readdirSync(presetFolder).filter(function (name) { return /\.epr$/i.test(name); }).sort();
      for (var fileIndex = 0; fileIndex < files.length; fileIndex++) {
        var preset = path.join(presetFolder, files[fileIndex]);
        var xml = fs.readFileSync(preset, "utf8");
        if (/<DoVideo>false<\/DoVideo>/.test(xml) && /<DoAudio>true<\/DoAudio>/.test(xml) && /<ExporterFileType>1463899717<\/ExporterFileType>/.test(xml)) return preset;
      }
    }
    throw new Error("Không tìm thấy preset WAV có sẵn của Premiere Pro. Hãy kiểm tra phần cài đặt Premiere/MediaIO.");
  }
  async function exportCaptionAudio(jobPath, preset, rangeCount, metrics) {
    await waitForWorkflowPause();
    var token = timestamp() + "_" + String(Date.now()), active = true, result = null, failure = null;
    function measure(phase, action, index, milliseconds, response) {
      // Diagnostics must not change whether export/restoration can proceed.
      try { if (metrics && typeof metrics.audioExport === "function") metrics.audioExport(phase, action, index, milliseconds, response); } catch (ignoreExportMetrics) {}
    }
    async function hostCall(phase, expression, index) {
      measure(phase, "start", index);
      var started = Date.now(), response = { ok: false };
      try { response = await evalHost(expression); return response; }
      finally { measure(phase, "end", index, Math.max(0, Date.now() - started), response); }
    }
    try {
      result = await hostCall("prepare", "$._PVS.beginCaptionAudioExport(" + jsxString(jobPath) + "," + jsxString(preset) + "," + jsxString(token) + ")");
      active = !result.done;
      if (result.restored && runContext) runContext.impact = "unchanged";
      if (result.ok) throwIfStopRequested();
      if (result.ok) {
        if (result.rangeCount !== rangeCount || result.nextCall !== 0) throw new Error("Premiere trả về phiên xuất WAV không hợp lệ.");
        for (var call = 0; call < rangeCount; call++) {
          // Return out of ExtendScript and yield the CEP event loop. $.sleep
          // inside the host would still occupy Premiere's scripting thread.
          measure("yield", "start", call);
          var yieldStarted = Date.now();
          await new Promise(function (resolve) { setTimeout(resolve, 100); });
          measure("yield", "end", call, Math.max(0, Date.now() - yieldStarted));
          throwIfStopRequested();
          result = await hostCall("render", "$._PVS.advanceCaptionAudioExport(" + jsxString(token) + "," + call + ")", call);
          active = !result.done;
          if (result.restored && runContext) runContext.impact = "unchanged";
          if (result.ok) throwIfStopRequested();
          if (!result.ok || result.done) break;
          if (result.nextCall !== call + 1) throw new Error("Sai thứ tự lượt xuất WAV.");
        }
        if (result.ok && !result.done) throw new Error("Phiên xuất WAV chưa hoàn tất.");
      }
    } catch (error) { failure = error; }
    finally {
      if (active) {
        try {
          var aborted = await hostCall("abort", "$._PVS.abortCaptionAudioExport(" + jsxString(token) + ")");
          if (aborted.restored === false || (!aborted.ok && aborted.exportFailurePhase === "restore")) throw new Error(aborted.error);
          if (aborted.restored && runContext) runContext.impact = "unchanged";
        } catch (restoreError) { failure = new Error((failure ? failure.message : result && result.error || "Xuất WAV không hoàn tất.") + "\nKhông xác minh được khôi phục: " + restoreError.message); }
      }
    }
    if (failure) throw failure;
    return result;
  }
  async function runCaptions() {
    if (state.workflowBusy || recoveryContext) return;
    var jobsRoot = "", outputFolder = "", captionCreated = false;
    var started = Date.now();
    var metrics = null, outcome = "failed", completedMessage = "";
    try {
      setWorkflowBusy(true);
      beginRun("captions");
      var displayedInputKey = state.captionPlan && state.captionPlan.key;
      var range = await scanCaptionRange();
      throwIfStopRequested();
      var inputPlan = range.plan;
      if (!inputPlan) throw state.captionPlanError || inputError("Hãy cập nhật nguồn audio và phạm vi trước khi chạy.", "captionSourceMode");
      if (inputPlan.key !== displayedInputKey) throw inputError("Nguồn hoặc phạm vi đã thay đổi. Tóm tắt đã được cập nhật; hãy kiểm tra rồi bấm Tạo phụ đề lại.", "captionSourceMode");
      runContext.baseline = range.snapshot;
      runContext.sequenceId = range.sequenceId;
      runContext.captionCount = await captionTrackCount(range.sequenceId);
      throwIfStopRequested();
      await waitForWorkflowPause();
      if (JSON.parse(runContext.captionCount).count === null) log("Premiere không cung cấp số Caption Track qua CEP. Tool vẫn kiểm tra video/audio, In/Out và bin tạm; nếu lỗi sau thao tác, cần kiểm tra caption thủ công trước khi chạy lại.", "muted");
      var captionSettings = readCaptionSettings();
      var maxCharacters = captionSettings.maxCaptionCharacters;
      var language = captionSettings.language;
      var joinedReference = srtJoin && srtJoin.read();
      if (!joinedReference && state.captionSrt) inspectSrt(state.captionSrt);
      var preset = findWavePreset(range.applicationFolder);
      if (state.backendPromise) await state.backendPromise;
      localStorage.setItem("pvs.subtitleLanguage", language);
      localStorage.setItem("pvs.subtitleMaxCharacters", String(maxCharacters));
      metrics = createWorkflowMetrics("caption-only");
      runContext.metrics = metrics;
      metrics.begin("preflight");
      jobsRoot = path.join(applicationDataRoot(), "Jobs");
      outputFolder = path.join(jobsRoot, "Job_Subtitle_" + timestamp() + "_" + String(Date.now()));
      security.assertNoLinks(fs, path, outputFolder, false);
      fs.mkdirSync(outputFolder, { recursive: true });
      runContext.outputFolder = outputFolder;
      var sources = inputPlan.ranges.map(function (item, index) { return { start: item.start, end: item.end, path: path.join(outputFolder, "timeline-" + String(index) + ".wav") }; });
      var jobPath = path.join(outputFolder, "job.json");
      var captionReferencePath = joinedReference ? srtJoin.write(joinedReference, outputFolder) : state.captionSrt;
      if (joinedReference) log("Đã nối " + joinedReference.files.length + " SRT thành " + joinedReference.cueCount + " cue theo thứ tự đã chọn.", "ok");
      fs.writeFileSync(jobPath, JSON.stringify({ schemaVersion: 1, workflow: "caption-only", projectId: range.projectId, sequenceId: range.sequenceId, snapshot: range.snapshot, audioInput: inputPlan.input, audioInputKey: inputPlan.key, frameRate: range.frameRate, language: language, maxCaptionCharacters: maxCharacters, targetSrtPath: captionReferencePath, sources: sources, outputFolder: outputFolder }, null, 2), "utf8");
      runContext.audioRecoveryPath = jobPath + ".audio-recovery.json";
      saveRecoveryJournal();
      metrics.end();
      status("1/3 · Premiere đang xuất WAV của vùng timeline. Giao diện Premiere sẽ bận trong bước này; có thể hủy trong bảng Encoding.", "muted");
      runStage("export");
      runContext.impact = "unknown";
      metrics.begin("audio-export");
      var exported = await exportCaptionAudio(jobPath, preset, sources.length, metrics);
      if (!exported.ok) {
        metrics.end(exported, "failed");
        throw new Error(exported.error + "\nBước xuất WAV: " + (exported.exportFailurePhase || "unknown") + ". Chưa chạy nhận diện hoặc thêm caption." + (exported.exportFailurePhase === "native-export" ? " Nếu Encoding kẹt 0%, hãy thử xuất WAV thủ công của cùng vùng để đối chiếu." : ""));
      }
      runContext.impact = "unchanged";
      throwIfStopRequested();
      log("Đã xuất audio đúng nguồn/phạm vi đã chốt; mute, enable và In/Out đã được khôi phục.", "ok");
      metrics.end();
      status("2/3 · Đang nhận diện và căn subtitle...", "muted");
      runStage("alignment");
      metrics.begin("caption-alignment");
      await runPowerShell(path.join(extensionRoot(), "engine", "run-captions.ps1"), ["-JobPath", jobPath]);
      var resultPath = path.join(outputFolder, "caption-result.json");
      var result = JSON.parse(fs.readFileSync(resultPath, "utf8").replace(/^\uFEFF/, ""));
      if (!result.ok || result.workflow !== "caption-only" || Number(result.schemaVersion) !== 1) throw new Error("Engine không tạo được subtitle hợp lệ.");
      metrics.end(result);
      if (result.preserveTimeline === true) {
        completedMessage = preservedRecognitionNotice(result, true);
        outcome = "success";
        return;
      }
      state.backend = { backend: result.recognitionBackend, label: result.recognitionBackendLabel, reason: result.gpuFallbackReason ? "GPU lỗi trong tác vụ; đã chạy lại bằng CPU. " + result.gpuFallbackReason : result.backendReason };
      if (result.gpuFallbackReason) runWarning("GPU gặp lỗi; đã nhận diện lại bằng CPU. Kết quả tiếp tục được kiểm tra như bình thường.");
      renderBackend(state.backend);
      log("Subtitle: ngôn ngữ " + result.language + " · " + result.captionCueCount + " caption · " + result.recognitionBackendLabel + (result.usedReferenceSrt ? " · giữ chữ SRT " + result.referenceSelectedCueCount + "/" + result.referenceCueCount + " cue." : " · tự nhận diện nội dung."), "ok");
      if (result.usedReferenceSrt && Number(result.referenceSelectedCueCount) === 0) runWarning("Không giữ được câu nào từ SRT đã chọn; toàn bộ phụ đề dùng chữ tự nhận diện.", true, "REFERENCE_NOT_RETAINED");
      logCaptionTiming(result);
      var referenceScope = result.referenceScopeRanges || [];
      if ((result.omittedReferenceCueIndices || []).length) log("Không thêm subtitle cho cue đã bỏ khỏi voice: " + result.omittedReferenceCueIndices.join(", ") + ". Hình và audio được giữ nguyên.", "muted");
      if ((result.unresolvedReferenceCueIndices || []).length) log("Chưa xác minh được phần SRT: cue " + result.unresolvedReferenceCueIndices.join(", ") + ". Dùng nhận diện thực tế ở vùng còn lời nói; cần nghe lại.", "warn");
      if ((result.referenceRecoveredCueIndices || []).length) log("Đã nhận diện lại và khôi phục chữ SRT cho cue " + result.referenceRecoveredCueIndices.join(", ") + ".", "muted");
      if (result.recognitionEdgeRetryCount) log("Đã nhận diện lại phần cuối " + result.recognitionEdgeRetryCount + " vùng audio do timestamp/lời nhận diện ở mép chưa đầy đủ.", "muted");
      if ((result.numericCaptionRefinedCues || []).length) log("Đã căn riêng caption quanh số: cue " + result.numericCaptionRefinedCues.join(", ") + ".", "muted");
      if ((result.numericCaptionReviewCues || []).length) log("Tinh chỉnh số giữ mốc đã căn tại cue " + result.numericCaptionReviewCues.join(", ") + ".", "muted");
      if ((result.referenceNumberReviewCues || []).length) log("Giữ chữ SRT tại " + result.referenceNumberReviewCues.length + " câu đã nhận ra có phần số khác cách ghi của nhận diện.", "muted");
      if (referenceScope.length) log("Phạm vi SRT: " + referenceScope.map(function (item) { return "vùng " + (Number(item.sourceIndex) + 1) + " dùng cue " + item.firstCue + "–" + item.lastCue; }).join("; ") + " / " + result.referenceCueCount + " cue. " + result.referenceOutsideCueCount + " cue nằm ngoài audio được chọn.", "muted");
      var referenceSupplements = result.referenceSupplementRanges || [];
      if (referenceSupplements.length) log("Đã thêm chữ tự nhận diện tại " + referenceSupplements.length + " vùng audio chưa khớp SRT: " + referenceSupplements.map(function (item) { return Number(item.start).toFixed(2) + "–" + Number(item.end).toFixed(2) + "s"; }).join("; ") + ". Xem caption được trích trong marker để kiểm tra chữ.", "warn");
      if ((result.referenceContextCoveredRanges || []).length) log("Đã loại " + result.referenceContextCoveredRanges.length + " vùng nhận diện trùng với đuôi/đầu câu SRT liền kề.", "muted");
      if ((result.referenceSupplementEmptyRanges || []).length) log("Có " + result.referenceSupplementEmptyRanges.length + " vùng chưa xác minh được lời bổ sung và còn khoảng chưa được caption bao phủ; cần nghe lại tại các marker.", "warn");
      var referenceReviews = (result.referenceReviewCues || []).filter(function (cue) { return String(cue.reason).indexOf("Giữ chữ SRT khớp phần lớn") !== 0; });
      if ((result.referenceInformationCues || []).length) log("Giữ chữ SRT tại " + result.referenceInformationCues.length + " cue chỉ khác cách viết cấp độ; không coi khác biệt định dạng này là lỗi nội dung.", "muted");
      if ((result.referenceQuietRanges || []).length) log("Bỏ qua nhận diện bổ sung ở " + result.referenceQuietRanges.length + " khoảng nghỉ ngắn đã đo; thông tin đối chiếu được lưu trong nhật ký.", "muted");
      if (result.recognitionSuppressedRangeCount) log("Đã từ chối " + result.recognitionSuppressedRangeCount + " giả thuyết ASR thiếu bằng chứng âm thanh. Những vùng còn chưa được subtitle/SRT bao phủ được đánh dấu cần kiểm tra.", "warn");
      if (referenceReviews.length) log("Giữ chữ SRT tại " + referenceReviews.length + " cue có phần nhận diện chưa trùng khớp; cần kiểm tra chữ và timing: " + referenceReviews.map(function (cue) { return "cue " + cue.cueIndex + " (" + Number(cue.start).toFixed(2) + "–" + Number(cue.end).toFixed(2) + "s)"; }).join(", ") + ".", "warn");
      status("3/3 · Đang thêm Caption Track...", "muted");
      runStage("captions");
      metrics.begin("caption-import");
      if (await captionTrackCount(range.sequenceId) !== runContext.captionCount) throw new Error("Caption hoặc In/Out đã thay đổi trong lúc nhận diện. Hãy kiểm tra lại đầu vào; tool chưa thêm caption.");
      result.reviewMarkers = buildReviewMarkers(result, null);
      metrics.reviewPlan(result);
      result.reviewMarkerRanges = sources.map(function (source) { return { start: source.start, end: source.end }; });
      fs.writeFileSync(resultPath, JSON.stringify(result, null, 2), "utf8");
      var captionExecutorPath = writeHostInput(result, "captions", outputFolder);
      await waitForWorkflowPause();
      runContext.impact = "unknown";
      var applied = await evalHost("$._PVS.applyCaptionOnly(" + jsxString(captionExecutorPath) + ")");
      captionCreated = !!applied.captionCreated;
      // Even a failed import can have changed the Project bin; do not assume untouched.
      runContext.impact = applied.ok ? "changed" : "unknown";
      logReviewMarkers(applied, result.reviewMarkers);
      if (!applied.ok) throw new Error(applied.error);
      throwIfStopRequested();
      metrics.end(applied);
      var message = "Đã tạo " + applied.captionCueCount + " caption trong " + ((Date.now() - started) / 1000).toFixed(1) + " giây. Video/audio được giữ nguyên. Hãy nghe lại để kiểm tra từ nhận diện; project chưa được lưu.";
      if (result.usedReferenceSrt && Number(result.referenceSelectedCueCount) === 0) message += " Không giữ được câu nào từ SRT đã chọn; toàn bộ caption dùng chữ tự nhận diện.";
      if ((result.omittedReferenceCueIndices || []).length) message += " Bỏ " + result.omittedReferenceCueIndices.length + " cue SRT không còn trong voice.";
      if (Number(applied.reviewMarkerCount || 0)) message += " Có " + applied.reviewMarkerCount + " marker cần kiểm tra trên thước timeline.";
      if (referenceScope.length) message += " SRT: " + referenceScope.map(function (item) { return "cue " + item.firstCue + "–" + item.lastCue; }).join(", ") + "/" + result.referenceCueCount + "; " + result.referenceOutsideCueCount + " cue ngoài vùng không được thêm.";
      if (referenceSupplements.length) message += " Đã tự nhận diện bổ sung " + referenceSupplements.length + " vùng thiếu hoặc khác SRT, gồm cả lời nói ngoài SRT; cần nghe lại phần bổ sung.";
      if ((result.referenceSupplementEmptyRanges || []).length) message += " Có " + result.referenceSupplementEmptyRanges.length + " vùng không nhận diện được lời nói; xem log để kiểm tra.";
      if ((result.captionTimingReviewCues || []).length) message += " Có " + result.captionTimingReviewCues.length + " cue chưa xác minh mốc DTW; xem Hỗ trợ và nhật ký.";
      if ((result.captionTimingEstimatedRanges || []).length) message += " Có " + result.captionTimingEstimatedRanges.length + " vùng chỉ có timing ước lượng cấp câu; xem nhật ký để biết vị trí cần kiểm tra.";
      if (referenceReviews.length) message += " Có " + referenceReviews.length + " cue SRT cần nghe lại; xem Hỗ trợ và nhật ký.";
      if (referenceReviews.length) runWarning("Có cue subtitle cần nghe lại; xem Hỗ trợ và nhật ký.", true);
      runContext.resultHeadline = "Đã tạo " + applied.captionCueCount + " phụ đề.";
      completedMessage = message;
      outcome = "success";
    } catch (error) {
      if (error.pvsCancelled) outcome = "cancelled";
      if (metrics) metrics.end(null, outcome);
      var failure = error.message + (captionCreated ? " Caption Track có thể đã được thêm; hãy kiểm tra trước khi chạy lại." : "");
      if (!error.pvsCancelled) reportRunFailure(inputError(failure, error.pvsInputField), "Tạo phụ đề — Không hoàn tất");
    } finally {
      if (outputFolder) {
        runStage("cleanup");
        if (metrics) metrics.begin("cleanup");
        try {
          if (runContext && runContext.audioRecoveryPath && fs.existsSync(runContext.audioRecoveryPath)) throw new Error("Giữ lại nhật ký khôi phục audio và thư mục job để kiểm tra trạng thái timeline.");
          removeTreeSafe(outputFolder, jobsRoot);
          if (fs.existsSync(jobsRoot) && fs.readdirSync(jobsRoot).length === 0) fs.rmdirSync(jobsRoot);
          log("Đã dọn file tạm của tác vụ subtitle.", "ok");
          if (metrics) metrics.end();
        } catch (cleanupError) {
          if (metrics) metrics.end(null, "failed");
          log("Không dọn hết file tạm: " + cleanupError.message, "error");
          runWarning("Không dọn hết file tạm. Xem nhật ký; caption đã tạo không cần tạo lại vì lỗi dọn file.");
          appendCleanupNotice(cleanupError);
        }
      }
      if (runContext && runContext.fatal) outcome = "failed";
      if (metrics) metrics.finish(outcome);
      if (outcome === "cancelled") reportRunCancelled();
      if (completedMessage) finishRunNotice("Tạo phụ đề", completedMessage);
      runContext = null;
      saveRecoveryJournal();
      setWorkflowBusy(false);
    }
  }
  async function clearWhisperCache() {
    if (state.workflowBusy) return;
    setWorkflowBusy(true);
    try {
      if (!await confirmWorkflowNotice("Xóa cache nhận diện?", "Các kết quả nhận diện đã lưu sẽ bị xóa. Lần chạy sau cần nhận diện lại.", "Xóa cache", "Hủy")) return;
      var root = applicationDataRoot();
      removeTreeSafe(path.join(root, "Cache", "Whisper"), root);
      var message = "Đã xóa cache nhận diện. Model và backend GPU được giữ nguyên.";
      log(message, "ok");
      localFeedback("supportFeedback", "Đã xóa cache nhận diện.");
    } catch (error) {
      var failure = "Không xóa được cache: " + error.message;
      log(failure, "error");
      localFeedback("supportFeedback", "Chưa xóa được cache nhận diện; xem nhật ký để kiểm tra.", true);
    } finally { setWorkflowBusy(false); }
  }
  function exportSafeLog() {
    if (state.workflowBusy) return;
    try {
      var result = window.cep.fs.showOpenDialog(false, true, "Chọn thư mục lưu log đã che thông tin", null);
      if (result.err !== 0 || !result.data || !result.data.length) return;
      var values = [state.targetSrt, state.captionSrt, process.env.USERNAME];
      if (state.captionRange) values.push(state.captionRange.sequenceName, state.captionRange.name);
      if (state.sequence) {
        values.push(state.sequence.name);
        if (state.sequence.mainVideoClip) values.push(state.sequence.mainVideoClip.name);
        (state.sequence.voices || []).forEach(function (voice) { values.push(voice.name, voice.path); });
      }
      var report = security.redactLog(byId("log").textContent, values);
      var destination = path.join(result.data[0], "PremiereVoiceSync-Support-" + timestamp() + ".txt");
      security.assertNoLinks(fs, path, destination, false);
      fs.writeFileSync(destination, report, { encoding: "utf8", flag: "wx" });
      localFeedback("supportFeedback", "Đã xuất log: " + destination + "\nĐọc lại nội dung trước khi chia sẻ.");
    } catch (error) {
      var failure = "Không xuất được log: " + error.message;
      log(failure, "error");
      localFeedback("supportFeedback", "Chưa xuất được log; kiểm tra thư mục lưu và xem nhật ký.", true);
    }
  }
  function wire() {
    loadNoticeHistory();
    try {
      var recovery = JSON.parse(localStorage.getItem("pvs.recovery.v1") || "null");
      if (recovery && /^(edit|captions)$/.test(recovery.workflow)) recoveryContext = { workflow: recovery.workflow, restored: true, impact: "unknown", audioRecoveryPath: recovery.audioRecoveryPath || null };
    } catch (ignoreRecoveryJournal) {}
    byId("externalNotifications").checked = externalPreference;
    byId("notificationSound").checked=soundPreference;
    byId("notificationSound").disabled=!externalPreference;
    byId("notificationSound").addEventListener("change",function(){setNotificationSoundPreference(this.checked);});
    nativeStatus("pending");
    byId("externalNotifications").addEventListener("change", function () { setExternalNotificationPreference(this.checked); });
    Object.keys(inputFeedback).forEach(function (id) {
      byId(id).addEventListener("input", function () { if (inlineValidation && inlineValidation.fieldId === id) closeWorkflowNotice(); });
    });
    byId("noticeCheckInputs").addEventListener("click", checkIncidentInputs);
    byId("stopWorkflow").addEventListener("click", requestWorkflowStop);
    byId("pauseWorkflow").addEventListener("click", requestWorkflowPause);
    byId("checkRecovery").addEventListener("click", checkIncidentInputs);
    byId("noticePickSrt").addEventListener("click", function () { if (!state.workflowBusy) { closeWorkflowNotice(); pickTargetSrt(); } });
    byId("noticeViewLog").addEventListener("click", function () {
      closeWorkflowNotice(); byId("supportTools").open = true;
      if (byId("supportTools").scrollIntoView) byId("supportTools").scrollIntoView({ block: "start" });
    });
    byId("noticeExportLog").addEventListener("click", exportSafeLog);
    byId("noticeReviewIssues").addEventListener("click", function () {
      byId("workflowNoticeDetails").open = true;
      if (byId("workflowNoticeReview").scrollIntoView) byId("workflowNoticeReview").scrollIntoView({ block: "nearest" });
    });
    document.addEventListener("keydown", noticeKeyboard);
    if (window.addEventListener) {
      window.addEventListener("unload", function () { if (nativeBridge) nativeBridge.stop(); if(testNotificationBridge)testNotificationBridge.stop(); if(testNotificationTimer)window.clearTimeout(testNotificationTimer); });
      window.addEventListener("error", function (event) { reportUnexpectedError(event.error || new Error(event.message || "Không tải được thành phần giao diện.")); });
      window.addEventListener("unhandledrejection", function (event) { reportUnexpectedError(event.reason); if (event.preventDefault) event.preventDefault(); });
      window.addEventListener("focus", function () { if (blockingNotice(currentNotice) && !byId("workflowNotice").hidden) focusNoticeButton(); });
    }
    document.addEventListener("visibilitychange",observeCurrentNotice);
    document.addEventListener("scroll",observeCurrentNotice,true);
    if(window.addEventListener){window.addEventListener("focus",observeCurrentNotice);window.addEventListener("resize",observeCurrentNotice);}
    if(window.IntersectionObserver){var noticeObserver=new window.IntersectionObserver(observeCurrentNotice);noticeObserver.observe(byId("workflowNotice"));}
    byId("testWindowsNotification").addEventListener("click",testWindowsNotification);
    if (window.setInterval) window.setInterval(updateRunHealth, 10000);
    byId("closeWorkflowNotice").addEventListener("click", closeWorkflowNotice);
    byId("acceptWorkflowNotice").addEventListener("click", function () { chooseWorkflowNotice(true); });
    byId("allowGpuDownload").checked = localStorage.getItem("pvs.allowGpuDownload") === "true";
    byId("allowGpuDownload").addEventListener("change", function () {
      localStorage.setItem("pvs.allowGpuDownload", String(this.checked));
      state.backendPromise = detectBackend();
    });
    byId("clearWhisperCache").addEventListener("click", clearWhisperCache);
    byId("exportSafeLog").addEventListener("click", exportSafeLog);
    try {
      var staleJobs = cleanupStaleJobs();
      if (staleJobs) log("Đã dọn " + staleJobs + " job tạm còn sót từ lần chạy cũ.", "ok");
    } catch (cleanupError) {
      log("Không dọn được job tạm cũ: " + cleanupError.message, "warn");
      localFeedback("supportFeedback", "Có file tạm chưa dọn được; xem nhật ký khi cần giải phóng dung lượng.");
    }
    applySettings(loadSettings());
    if (srtJoin) srtJoin.wire();
    var storedVoiceLanguage = localStorage.getItem("pvs.voiceLanguage");
    if (storedVoiceLanguage) { byId("voiceLanguage").value = storedVoiceLanguage; if (!byId("voiceLanguage").value) byId("voiceLanguage").value = "vi"; }
    byId("voiceLanguage").addEventListener("change", function () { readVoiceLanguage(); if (inlineValidation && inlineValidation.fieldId === "voiceLanguage") closeWorkflowNotice(); });
    var storedLanguage = localStorage.getItem("pvs.subtitleLanguage");
    if (storedLanguage) { byId("captionLanguage").value = storedLanguage; if (!byId("captionLanguage").value) byId("captionLanguage").value = "vi"; }
    var storedCaptionLength = Number(localStorage.getItem("pvs.subtitleMaxCharacters"));
    if (storedCaptionLength >= 20 && storedCaptionLength <= 80 && Math.round(storedCaptionLength) === storedCaptionLength) byId("subtitleMaxCharacters").value = storedCaptionLength;
    byId("modeEdit").addEventListener("click", function () { setMode("edit"); refreshProjectInputs(false); });
    byId("modeCaptions").addEventListener("click", function () { setMode("captions"); refreshProjectInputs(false); });
    ["captionSourceMode", "captionScopeMode"].forEach(function (id) {
      byId(id).addEventListener("change", function () {
        if (state.workflowBusy || !state.captionConfig) return;
        state.captionConfig[id === "captionSourceMode" ? "sourceMode" : "scopeMode"] = this.value;
        if (inlineValidation) closeWorkflowNotice();
        renderCaptionVoiceTracks(state.captionRange);
      });
    });
    byId("captionSrtCandidates").addEventListener("change", function () { setCaptionSrt(this.value); });
    byId("pickCaptionSrt").addEventListener("click", function () {
      var result = window.cep.fs.showOpenDialog(false, false, "Chọn SRT đúng nội dung của vùng subtitle", state.captionSrt ? path.dirname(state.captionSrt) : null, ["srt"]);
      if (result.err === 0 && result.data && result.data.length) setCaptionSrt(result.data[0]);
    });
    byId("runCaptions").addEventListener("click", runCaptions);
    byId("pickTargetSrt").addEventListener("click", pickTargetSrt);
    byId("srtCandidates").addEventListener("change", function () { if (this.value) setTargetSrt(this.value, "Project"); else { state.targetSrt = ""; state.targetSrtExplicit = true; } });
    byId("resetSettings").addEventListener("click", function () {
      applySettings(settingDefaults);
      localStorage.setItem(settingsStorageKey, JSON.stringify(settingDefaults));
      localStorage.setItem(settingsSchemaKey, settingsSchemaVersion);
      localFeedback("settingsFeedback", "Đã khôi phục thiết lập mặc định.");
    });
    byId("scanSequence").addEventListener("click", function () {
      refreshProjectInputs(false);
    });
    byId("runDiagnostics").addEventListener("click", runDiagnostics);
    byId("retryBackend").addEventListener("click", function () {
      state.backendPromise = detectBackend(true);
    });
    byId("runSync").addEventListener("click", runSync);
    state.backendPromise = detectBackend();
    setWorkflowBusy(false);
    refreshProjectInputs(true);
  }
  document.addEventListener("DOMContentLoaded", wire);
}());
