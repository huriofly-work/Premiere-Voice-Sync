/* Shared by CEP and ExtendScript. Keep this module ES3-compatible. */
(function (root) {
  function fail(message, field) {
    var error = new Error(message); error.pvsInputField = field || "captionSourceMode"; throw error;
  }
  function contains(values, value) { for (var i = 0; i < values.length; i++) if (values[i] === value) return true; return false; }
  function overlap(clip, range) { return clip.start < range.end && clip.end > range.start; }
  function merge(ranges, fps) {
    var result = [], sorted = [], i;
    for (i = 0; i < ranges.length; i++) {
      var start = Number(ranges[i].start), end = Number(ranges[i].end);
      if (!isFinite(start) || !isFinite(end) || start < 0 || end <= start) fail("Phạm vi subtitle không hợp lệ.", "captionScopeMode");
      // Match the frame-based export and caption contract.
      start = Math.round(start * fps) / fps; end = Math.round(end * fps) / fps;
      if (end > start) sorted.push({ start: start, end: end });
    }
    sorted.sort(function (a, b) { return a.start - b.start; });
    for (i = 0; i < sorted.length; i++) {
      var last = result.length ? result[result.length - 1] : null;
      if (last && sorted[i].start <= last.end) last.end = Math.max(last.end, sorted[i].end);
      else result.push({ start: sorted[i].start, end: sorted[i].end });
    }
    return result;
  }
  function topology(scan) {
    var rows = [];
    for (var i = 0; i < scan.audioTracks.length; i++) rows.push([scan.audioTracks[i].index, scan.audioTracks[i].key]);
    return JSON.stringify(rows);
  }
  function anchors(scan, indices) {
    var rows = [];
    for (var i = 0; i < scan.audioTracks.length; i++) {
      var track = scan.audioTracks[i];
      if (contains(indices, track.index)) for (var j = 0; j < track.clips.length; j++) rows.push({ index: track.index, nodeId: track.clips[j].nodeId });
    }
    return rows;
  }
  function equalValue(a, b) {
    if (a === b) return true;
    if (!a || !b || typeof a !== "object" || typeof b !== "object" || Object.prototype.toString.call(a) !== Object.prototype.toString.call(b)) return false;
    var left = [], right = [], key, i;
    for (key in a) if (Object.prototype.hasOwnProperty.call(a, key)) left.push(key);
    for (key in b) if (Object.prototype.hasOwnProperty.call(b, key)) right.push(key);
    if (left.length !== right.length) return false;
    left.sort(); right.sort();
    for (i = 0; i < left.length; i++) if (left[i] !== right[i] || !equalValue(a[left[i]], b[right[i]])) return false;
    return true;
  }
  function frameRanges(ranges, fps) {
    if (!(fps > 0) || !isFinite(fps) || Object.prototype.toString.call(ranges) !== "[object Array]") throw new Error("Invalid frame ranges");
    var result = [];
    for (var i = 0; i < ranges.length; i++) {
      var range = ranges[i], start = range.start, end = range.end;
      if (typeof start !== "number" || typeof end !== "number" || !isFinite(start) || !isFinite(end) || start < 0 || end <= start) throw new Error("Invalid frame range");
      var a = Math.round(start * fps), b = Math.round(end * fps);
      if (b <= a || Math.abs(start * fps - a) > 0.001 || Math.abs(end * fps - b) > 0.001) throw new Error("Range is not frame aligned");
      result.push({ start: a, end: b });
    }
    return result;
  }
  function sameRanges(a, b, fps) {
    try { return equalValue(frameRanges(a, fps), frameRanges(b, fps)); } catch (error) { return false; }
  }
  function sameKey(a, b, fps) {
    // CEP and ExtendScript can serialize the same number/property order
    // differently. Compare identity/state exactly and derived times as frames.
    function normalize(text) {
      if (typeof text !== "string") throw new Error("Invalid planner key");
      var value = JSON.parse(text);
      value.input.topology = JSON.parse(value.input.topology);
      value.input.scopeRanges = frameRanges(value.input.scopeRanges, fps);
      value.ranges = frameRanges(value.ranges, fps);
      value.skippedRanges = frameRanges(value.skippedRanges, fps);
      return value;
    }
    try { return equalValue(normalize(a), normalize(b)); } catch (error) { return false; }
  }
  function resolve(scan, config) {
    config = config || {};
    if (scan.inputVersion !== 1 || !scan.audioTracks || !(scan.frameRate > 0)) fail("Hãy cập nhật bộ điều khiển và đọc lại đầu vào subtitle.");
    var mode = config.sourceMode || "tracks", scope = mode === "clips" ? "clips" : (config.scopeMode || "whole");
    if (mode !== "mix" && mode !== "tracks" && mode !== "clips") fail("Nguồn audio không hợp lệ.");
    var tracks = scan.audioTracks, requested = [], chosen = [], selected = [], ranges = [], skipped = [], emptyTracks = [], unmute = [], disabledCount = 0, i, j, k;
    if (scope === "whole") { if (scan.sequenceEnd > 0) requested.push({ start: 0, end: scan.sequenceEnd }); }
    else if (scope === "selection") requested = scan.selectionRanges || [];
    else if (scope === "inout") {
      if (!scan.inOut || !scan.inOut.valid) fail("Hãy đặt In/Out hợp lệ trong sequence hoặc chọn phạm vi khác.", "captionScopeMode");
      requested.push({ start: scan.inOut.start, end: scan.inOut.end });
    } else if (scope !== "clips") fail("Phạm vi thời gian không hợp lệ.", "captionScopeMode");
    if (mode === "clips") {
      var selectedIds = scan.selectedAudio || [];
      for (i = 0; i < tracks.length; i++) for (j = 0; j < tracks[i].clips.length; j++) {
        var candidate = tracks[i].clips[j], isSelected = false;
        for (k = 0; k < selectedIds.length; k++) if (selectedIds[k].trackIndex === tracks[i].index && selectedIds[k].nodeId === candidate.nodeId) isSelected = true;
        if (!isSelected) continue;
        if (candidate.disabled === null) fail("Premiere không cung cấp trạng thái enable của clip audio đã chọn. Chưa xuất audio.");
        if (candidate.disabled) { disabledCount++; continue; }
        if (!candidate.nodeId) fail("Không xác minh được danh tính clip audio đã chọn.");
        selected.push({ trackIndex: tracks[i].index, nodeId: candidate.nodeId });
        requested.push({ start: candidate.start, end: candidate.end });
        if (!contains(chosen, tracks[i].index)) chosen.push(tracks[i].index);
      }
      if (!selected.length) fail("Hãy chọn ít nhất một clip audio đang enabled trên timeline. Clip video không được dùng làm nguồn audio.");
    }
    requested = merge(requested, scan.frameRate);
    if (!requested.length) fail("Không có phạm vi hợp lệ. Hãy chọn clip hoặc đổi phạm vi thời gian.", "captionScopeMode");
    function contributes(track) {
      for (var ci = 0; ci < track.clips.length; ci++) if (track.clips[ci].disabled !== true) for (var ri = 0; ri < requested.length; ri++) if (overlap(track.clips[ci], requested[ri])) return true;
      return false;
    }
    if (mode === "mix") {
      for (i = 0; i < tracks.length; i++) {
        if (tracks[i].muted === null) fail("Không đọc được mute track A" + (tracks[i].index + 1) + ".");
        if (!tracks[i].muted && contributes(tracks[i])) chosen.push(tracks[i].index);
      }
    } else if (mode === "tracks") {
      if (config.trackIndices === null || config.trackIndices === undefined) {
        for (i = 0; i < tracks.length; i++) if (contributes(tracks[i])) {
          if (!chosen.length || tracks[i].index === 1) chosen = [tracks[i].index];
          if (tracks[i].index === 1) break;
        }
      } else {
        if (Object.prototype.toString.call(config.trackIndices) !== "[object Array]") fail("Danh sách track không hợp lệ.", "captionVoiceTrack");
        var sameTopology = false;
        try { sameTopology = equalValue(JSON.parse(config.topology), JSON.parse(topology(scan))); } catch (ignoreTopology) {}
        if (!sameTopology) fail("Danh sách hoặc thứ tự track đã thay đổi. Hãy chọn lại các track nguồn.", "captionVoiceTrack");
        var oldAnchors = config.anchors || [], locations = {};
        for (j = 0; j < tracks.length; j++) for (k = 0; k < tracks[j].clips.length; k++) locations["clip:" + tracks[j].clips[k].nodeId] = tracks[j].index;
        for (i = 0; i < oldAnchors.length; i++) {
          var location = locations["clip:" + oldAnchors[i].nodeId];
          if (location !== undefined && location !== oldAnchors[i].index) fail("Clip nguồn đã đổi track. Hãy kiểm tra và chọn lại các track nguồn.", "captionVoiceTrack");
        }
        for (i = 0; i < config.trackIndices.length; i++) {
          var index = config.trackIndices[i], found = false;
          if (typeof index !== "number" || index < 0 || Math.floor(index) !== index || contains(chosen, index)) fail("Danh sách track không hợp lệ.", "captionVoiceTrack");
          for (j = 0; j < tracks.length; j++) if (tracks[j].index === index) found = true;
          if (!found) fail("Track đã chọn không còn tồn tại. Hãy chọn lại nguồn.", "captionVoiceTrack");
          chosen.push(index);
        }
      }
      if (!chosen.length) fail("Hãy chọn ít nhất một track có audio trong phạm vi subtitle.", "captionVoiceTrack");
    }
    chosen.sort(function (a, b) { return a - b; });
    for (i = 0; i < tracks.length; i++) if (contains(chosen, tracks[i].index)) {
      if (mode !== "mix" && tracks[i].muted) unmute.push(tracks[i].index);
      if (!contributes(tracks[i])) emptyTracks.push(tracks[i].index);
      if (mode === "clips") for (j = 0; j < tracks[i].clips.length; j++) if (tracks[i].clips[j].disabled === null) {
        for (k = 0; k < requested.length; k++) if (overlap(tracks[i].clips[j], requested[k])) fail("Không đọc được enable của clip cùng track; chưa thể cô lập đúng các clip được chọn.");
      }
    }
    for (i = 0; i < requested.length; i++) {
      var hasAudio = false;
      for (j = 0; j < tracks.length; j++) if (contains(chosen, tracks[j].index)) for (k = 0; k < tracks[j].clips.length; k++) {
        var clip = tracks[j].clips[k], allowed = mode !== "clips";
        if (!allowed) for (var si = 0; si < selected.length; si++) if (selected[si].trackIndex === tracks[j].index && selected[si].nodeId === clip.nodeId) allowed = true;
        if (allowed && clip.disabled !== true && overlap(clip, requested[i])) hasAudio = true;
      }
      (hasAudio ? ranges : skipped).push(requested[i]);
    }
    if (!ranges.length) fail("Nguồn đã chọn không có clip audio enabled trong phạm vi subtitle. Tool không tự đổi nguồn.", mode === "tracks" ? "captionVoiceTrack" : "captionSourceMode");
    var effective = { sourceMode: mode, scopeMode: scope, trackIndices: chosen, topology: topology(scan), selectedClips: selected, selectedAudio: mode === "clips" ? scan.selectedAudio : [], scopeRanges: requested };
    var key = JSON.stringify({ projectId: scan.projectId, sequenceId: scan.sequenceId, snapshot: scan.snapshot, input: effective, ranges: ranges, skippedRanges: skipped, unmuteTracks: unmute, disabledCount: disabledCount });
    return { key: key, input: effective, trackIndices: chosen, ranges: ranges, skippedRanges: skipped, emptyTracks: emptyTracks, unmuteTracks: unmute, selectedClips: selected, disabledCount: disabledCount, automatic: mode === "tracks" && (config.trackIndices === null || config.trackIndices === undefined) };
  }
  var api = { revision: 1, resolve: resolve, topology: topology, anchors: anchors, contains: contains, overlap: overlap, sameKey: sameKey, sameRanges: sameRanges };
  root.PvsCaptionInput = api;
  // evalFile/eval may supply a temporary `this` in Premiere. Keep the host
  // dependency on the persistent Adobe object shared by later CEP calls.
  if (typeof $ !== "undefined") {
    $._PVS = $._PVS || {};
    $._PVS.captionInput = api;
  }
  if (typeof module !== "undefined" && module.exports) module.exports = api;
}(typeof $ !== "undefined" && $.global ? $.global : this));
