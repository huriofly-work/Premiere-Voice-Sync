(function (root) {
  "use strict";
  function timestamp(text) {
    var m = /^(\d+):(\d{2}):(\d{2})[,.](\d{3})$/.exec(text);
    if (!m || Number(m[2]) >= 60 || Number(m[3]) >= 60) throw new Error("Timestamp SRT không hợp lệ: " + text);
    var value = ((Number(m[1]) * 60 + Number(m[2])) * 60 + Number(m[3])) * 1000 + Number(m[4]);
    if (!Number.isSafeInteger(value)) throw new Error("Timestamp SRT vượt giới hạn.");
    return value;
  }
  function format(ms) {
    function pad(value, size) { var text = String(value); while (text.length < size) text = "0" + text; return text; }
    return pad(Math.floor(ms / 3600000), 2) + ":" + pad(Math.floor(ms / 60000) % 60, 2) + ":" + pad(Math.floor(ms / 1000) % 60, 2) + "," + pad(ms % 1000, 3);
  }
  function parse(text) {
    var clean = String(text).replace(/^\uFEFF/, "").replace(/\r\n?/g, "\n").trim();
    if (!clean) throw new Error("SRT không có nội dung.");
    return clean.split(/\n[ \t]*\n(?:[ \t]*\n)*/).map(function (block, i) {
      var lines = block.split("\n"), line = /^\s*\d+\s*$/.test(lines[0]) ? 1 : 0;
      var time = /^\s*(\d+:\d{2}:\d{2}[,.]\d{3})\s*-->\s*(\d+:\d{2}:\d{2}[,.]\d{3})(?:\s.*)?$/.exec(lines[line] || "");
      if (!time) throw new Error("Cue " + (i + 1) + " có timestamp không hợp lệ.");
      var start = timestamp(time[1]), end = timestamp(time[2]), content = lines.slice(line + 1).join("\n").trim();
      if (end <= start || !content) throw new Error("Cue " + (i + 1) + " thiếu chữ hoặc có thời lượng không hợp lệ.");
      return { start: start, end: end, text: content };
    });
  }
  function join(files, timing) {
    if (!Array.isArray(files) || files.length < 2) throw new Error("Hãy thêm ít nhất hai SRT để nối.");
    if (timing !== "preserve" && timing !== "append") throw new Error("Cách nối timestamp không hợp lệ.");
    var result = [], end = 0;
    files.forEach(function (file, index) {
      var cues;
      try { cues = parse(file.text); } catch (e) { throw new Error(file.path + ": " + e.message); }
      var offset = timing === "append" && index ? end : 0, previous = -1;
      cues.forEach(function (cue, cueIndex) {
        if (cue.start < previous) throw new Error(file.path + ": cue " + (cueIndex + 1) + " bị chồng hoặc đảo thời gian.");
        previous = cue.end;
        var start = cue.start + offset, stop = cue.end + offset;
        if (!Number.isSafeInteger(stop)) throw new Error("Thời gian SRT sau nối vượt giới hạn.");
        if (result.length && start < end) throw new Error("Timestamp giữa các SRT bị chồng hoặc bắt đầu lại. Chọn “Nối tiếp thời gian từng file” hoặc kiểm tra thứ tự file.");
        result.push({ start: start, end: stop, text: cue.text }); end = stop;
      });
    });
    return { cueCount: result.length, text: result.map(function (c, i) { return (i + 1) + "\n" + format(c.start) + " --> " + format(c.end) + "\n" + c.text + "\n"; }).join("\n") };
  }
  function panel(env) {
    var configs = { edit: { enabled: false, files: [], timing: "preserve" }, captions: { enabled: false, files: [], timing: "append" } };
    var projectCandidates = null;
    function config() { return configs[env.state.mode === "captions" ? "captions" : "edit"]; }
    function el(id) { return env.document.getElementById(id); }
    function element(tag, text) { var e = env.document.createElement(tag); if (text !== undefined) e.textContent = text; return e; }
    function selected() { return env.state.mode === "captions" ? env.state.captionSrt : env.state.targetSrt; }
    function projectFiles() {
      return (projectCandidates || []).slice().sort(function (a, b) {
        return String(a.name || env.path.basename(a.path)).localeCompare(String(b.name || env.path.basename(b.path)), "vi", { numeric: true }) || a.path.localeCompare(b.path);
      });
    }
    function hasFile(file) { return config().files.some(function (f) { return f.toLowerCase() === file.toLowerCase(); }); }
    function add(files) {
      if (env.state.workflowBusy) return;
      if (env.changed) env.changed();
      var c = config();
      files.forEach(function (file) {
        var normalized = env.path.normalize(file);
        if (/\.srt$/i.test(normalized) && !hasFile(normalized)) c.files.push(normalized);
      });
      render();
    }
    function renderProjectFiles() {
      var list = el("srtJoinProjectList"), query = String(el("srtJoinSearch").value || "").toLowerCase(), files = projectFiles();
      list.innerHTML = "";
      files.forEach(function (file, index) {
        var name = file.name || env.path.basename(file.path);
        if (query && name.toLowerCase().indexOf(query) < 0) return;
        var duplicateName = files.some(function (other) { return other.path !== file.path && String(other.name || env.path.basename(other.path)).toLowerCase() === name.toLowerCase(); });
        var label = element("label"), box = element("input"), text = element("span", name + (duplicateName ? " · " + env.path.dirname(file.path) : ""));
        label.className = "check file-choice"; label.title = file.path;
        box.type = "checkbox"; box.id = "srtJoinProject_" + index; box.checked = hasFile(file.path); box.disabled = env.state.workflowBusy;
        box.addEventListener("change", function () {
          if (env.state.workflowBusy) return;
          if (this.checked) add([file.path]);
          else { if (env.changed) env.changed(); config().files = config().files.filter(function (f) { return f.toLowerCase() !== file.path.toLowerCase(); }); render(); }
          var updated = el(box.id); if (updated && updated.focus) updated.focus();
        });
        label.appendChild(box); label.appendChild(text); list.appendChild(label);
      });
      el("srtJoinProjectHint").textContent = !projectCandidates ? "Đang đọc danh sách SRT trong Project…" : !files.length ? "Project chưa có SRT. Import file rồi Cập nhật đầu vào, hoặc chọn từ máy." : !list.children.length ? "Không có file khớp tên tìm kiếm." : "Đánh dấu những file cần nối; thứ tự được chỉnh trong Danh sách đã chọn.";
    }
    function render() {
      var c = config(), busy = env.state.workflowBusy;
      [["editSrtSingle", "srtCandidates", "pickTargetSrt", configs.edit], ["captionSrtSingle", "captionSrtCandidates", "pickCaptionSrt", configs.captions]].forEach(function (entry) {
        el(entry[0]).hidden = entry[3].enabled;
        el(entry[1]).disabled = el(entry[2]).disabled = busy || entry[3].enabled;
      });
      el("srtJoinEnabled").checked = c.enabled; el("srtJoinEnabled").disabled = busy;
      el("srtJoinBody").hidden = !c.enabled;
      el("srtJoinTiming").value = c.timing;
      ["srtJoinTiming", "srtJoinAddProject", "srtJoinAddFiles", "srtJoinSearch"].forEach(function (id) { el(id).disabled = busy; });
      el("srtJoinSelectionSummary").textContent = "Danh sách đã chọn · " + c.files.length + " file";
      el("srtJoinPreview").textContent = c.files.length ? c.files.slice(0, 2).map(function (file) { return env.path.basename(file); }).join(" → ") + (c.files.length > 2 ? " → +" + (c.files.length - 2) + " file" : "") : "Chọn ít nhất 2 file theo thứ tự nội dung.";
      var list = el("srtJoinFiles"); list.innerHTML = "";
      c.files.forEach(function (file, index) {
        var item = element("li"); item.appendChild(element("span", env.path.basename(file))); item.title = file;
        function button(text, label, action, disabled) { var b = element("button", text); b.type = "button"; b.className = "button secondary reorder-button"; b.disabled = busy || disabled; b.title = label; b.setAttribute("aria-label", label + " · " + env.path.basename(file)); b.addEventListener("click", function () { if (env.state.workflowBusy) return; if (env.changed) env.changed(); action(); }); item.appendChild(b); }
        button("↑", "Lên", function () { var previous = c.files[index - 1]; c.files[index - 1] = file; c.files[index] = previous; render(); }, index === 0);
        button("↓", "Xuống", function () { var next = c.files[index + 1]; c.files[index + 1] = file; c.files[index] = next; render(); }, index === c.files.length - 1);
        button("×", "Bỏ", function () { c.files.splice(index, 1); render(); }, false); list.appendChild(item);
      });
      if (!el("srtJoinEnabled").getAttribute || el("srtJoinEnabled").getAttribute("aria-invalid") !== "true") el("srtJoinHint").textContent = c.files.length < 2 ? "Cần chọn ít nhất 2 SRT để nối." : c.timing === "append" ? "File sau nối tiếp thời gian file trước." : "Giữ thời gian gốc; các file cần nối tiếp và không chồng nhau.";
      renderProjectFiles();
    }
    function selection() {
      var c = config(); return c.enabled ? { files: c.files.slice(), timing: c.timing } : null;
    }
    function read() {
      var c = selection(); if (!c) return null;
      try {
        var result = join(c.files.map(function (file) { return { path: file, text: env.fs.readFileSync(file, "utf8") }; }), c.timing);
        result.files = c.files.slice(); result.timing = c.timing; return result;
      } catch (e) { throw env.inputError(e.message, "srtJoinEnabled"); }
    }
    function write(prepared, folder) {
      var file = env.path.join(folder, "reference-joined.srt");
      env.security.assertNoLinks(env.fs, env.path, file, false);
      env.fs.writeFileSync(file, prepared.text, { encoding: "utf8", flag: "wx" }); return file;
    }
    function wire() {
      el("srtJoinEnabled").addEventListener("change", function () {
        if (env.changed) env.changed();
        var c = config(); c.enabled = this.checked;
        if (c.enabled && !c.files.length && selected()) add([selected()]);
        el("srtJoinProjectPicker").open = c.enabled && c.files.length < 2;
        el("srtJoinSelection").open = false;
        render();
      });
      el("srtJoinTiming").addEventListener("change", function () { if (env.changed) env.changed(); config().timing = this.value; render(); });
      el("srtJoinAddProject").addEventListener("click", function () { if (!env.state.workflowBusy) { el("srtJoinProjectPicker").open = !el("srtJoinProjectPicker").open; } });
      el("srtJoinSearch").addEventListener("input", renderProjectFiles);
      el("srtJoinAddFiles").addEventListener("click", function () {
        if (env.state.workflowBusy) return;
        var answer = env.window.cep.fs.showOpenDialog(true, false, "Chọn các SRT cần nối", null, ["srt"]);
        if (!answer.err && answer.data) add(answer.data);
      });
    }
    function setProjectCandidates(candidates) {
      var seen = {};
      projectCandidates = candidates.filter(function (item) {
        var key = env.path.normalize(item.path || "").toLowerCase();
        if (!/\.srt$/.test(key) || seen[key]) return false;
        seen[key] = true; return true;
      });

      render();
    }
    return { render: render, selection: selection, read: read, write: write, wire: wire, setProjectCandidates: setProjectCandidates };
  }
  var api = { parse: parse, join: join, panel: panel };
  root.PvsSrtJoin = api;
  if (typeof module !== "undefined" && module.exports) module.exports = api;
}(this));
