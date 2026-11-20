/* Shared edit-input rules. Keep this module ES3-compatible. */
(function (root) {
  function mainVoiceGroup(voices, gapSeconds) {
    // Match run-alignment.ps1: sort by start and stop at the first gap
    // from the previous clip's end strictly greater than the threshold.
    var sorted = voices.slice(0).sort(function (a, b) { return Number(a.start) - Number(b.start); });
    for (var i = 1; i < sorted.length; i++) {
      if (Number(sorted[i].start) - Number(sorted[i - 1].end) > gapSeconds) return sorted.slice(0, i);
    }
    return sorted;
  }

  function validateEditInput(scan, settings, fileExists) {
    var reasons = [], seen = {};
    function add(code, message) {
      var key = code + "|" + message;
      if (seen[key]) return;
      seen[key] = true;
      reasons.push({ code: code, message: message });
    }
    if (!scan || scan.hasSequence === false) {
      add("NO_SEQUENCE", "Chưa mở sequence. Hãy mở sequence template cần dựng.");
      return { ok: false, reasons: reasons };
    }
    var video = scan.mainVideoClip, linked = scan.linkedAudio || [];
    if (!video) add("NO_V1", "V1 đang trống. Hãy đặt nest hình chính lên V1.");
    else {
      if (!linked.length) add("V1_NOT_LINKED", "V1 chưa liên kết với audio gốc. Hãy Link nest V1 với clip A1.");
      else if (!(scan.linkedTrackIndex >= 0) || !(Math.abs(Number(linked[0].start)) < 0.05) ||
          !(Math.abs(Number(linked[0].end) - Number(video.end)) < 0.1)) {
        add("LINKED_AUDIO_MISALIGNED", "A1 không khớp với V1. Hãy đưa cặp V1/A1 về đầu timeline, cùng điểm kết thúc và kiểm tra tên clip audio.");
      }
      if (scan.mainVideoPieceCount > 1) add("ALREADY_CUT", "V1 đã bị cắt thành nhiều đoạn. Hãy mở sequence template chưa dựng.");
      if (Math.abs(Number(video.start)) > 0.000001) add("V1_MOVED", "V1 không còn bắt đầu ở đầu timeline. Hãy đưa cặp V1/A1 về mốc 0.");
      if (Math.abs(Number(video.inPoint)) > 0.000001) add("V1_HEAD_TRIMMED", "V1 đã bị cắt phần đầu. Hãy dùng nest còn nguyên phần đầu.");
      if (video.speedPercent == null || !isFinite(video.speedPercent) || Math.abs(Number(video.speedPercent) - 100) > 0.000001) {
        add("V1_SPEED", "Tốc độ V1 phải là 100%. Hãy đặt lại tốc độ cho nest V1.");
      }
      if (video.isSpeedReversed) add("V1_REVERSED", "V1 đang chạy ngược (Reverse). Hãy tắt Reverse cho nest V1.");
      if (video.timeRemap === "varying") add("V1_TIME_REMAP", "Tốc độ V1 thay đổi theo thời gian. Hãy đưa Time Remapping trên V1 về tốc độ cố định.");
      else if (video.timeRemap !== "none" && video.timeRemap !== "static") {
        add("V1_TIME_REMAP", "Không đọc được Time Remapping trên V1. Hãy đặt lại Time Remapping cho nest V1.");
      }
    }
    var fps = Number(scan.frameRate);
    if (!(fps >= 1 && fps <= 240)) add("FRAME_RATE_INVALID", "Tốc độ khung hình phải từ 1 đến 240 fps. Hãy kiểm tra cài đặt sequence.");
    var voices = mainVoiceGroup(scan.voices || [], settings.voiceGroupGap);
    if (!voices.length) add("NO_A2_VOICE", "A2 chưa có voice. Hãy đặt các clip voice lên A2.");
    var voiceEnd = -Infinity;
    for (var i = 0; i < voices.length; i++) {
      var voice = voices[i];
      if (voice.isSpeedReversed) add("VOICE_REVERSED", "Voice A2 đang chạy ngược (Reverse). Tắt Reverse cho clip voice rồi chạy lại.");
      else if (Math.abs(Number(voice.inPoint)) > 0.000001) {
        add("VOICE_HEAD_TRIMMED", "Voice A2 đã bị cắt phần đầu. Hãy dùng clip voice còn nguyên phần đầu.");
      }
      if (voice.timeRemap === "static" || voice.timeRemap === "varying") {
        add("VOICE_TIME_REMAP", "Voice A2 có Time Remapping. Hãy dùng clip voice không áp dụng Time Remapping.");
      } else if (voice.timeRemap !== "none") {
        add("VOICE_TIME_REMAP", "Không đọc được Time Remapping trên voice A2. Hãy dùng clip voice không áp dụng Time Remapping.");
      }
      // The silence mapper uses a minimum scale of 1% for source timestamps.
      if (!isFinite(voice.speedPercent) || !(Number(voice.speedPercent) >= 1)) {
        add("VOICE_SPEED_INVALID", "Tốc độ voice A2 phải từ 1% trở lên. Hãy kiểm tra và đặt lại tốc độ clip.");
      }
      if (!voice.path || !fileExists(voice.path)) add("VOICE_FILE_MISSING", "Không tìm thấy file nguồn của voice A2. Hãy liên kết lại file trong Premiere.");
      // Adjacent clips read back from ticks can differ by rounding; allow half a frame.
      if (Number(voice.start) < voiceEnd - 0.5 / (fps >= 1 && fps <= 240 ? fps : 30)) add("VOICES_OVERLAP", "Các clip voice A2 đang chồng lên nhau. Hãy xếp các clip nối tiếp nhau.");
      voiceEnd = Math.max(voiceEnd, Number(voice.end));
    }
    return { ok: reasons.length === 0, reasons: reasons };
  }
  var api = { validateEditInput: validateEditInput, mainVoiceGroup: mainVoiceGroup };
  root.PvsEditInput = api;
  if (typeof module !== "undefined" && module.exports) module.exports = api;
}(this));
