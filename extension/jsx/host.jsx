/* global app, ProjectItemType, Sequence */
$._PVS = $._PVS || {};

// Optional picture/audio-original grouping. Never replace A2 speech plans.
// Validate before any tail move, razor or speed mutation.
$._PVS._baseSpeedMergeVisualPlans = function (plan) {
    if (plan.visualSegments === undefined && plan.speedMergeTrial === undefined) return plan.segments;
    if (plan.speedMergeTrial !== "adjacent-speed-v2" || !plan.visualSegments || !plan.visualSegments.length) throw new Error("Invalid speed merge trial plan.");
    function integer(value) { return typeof value === "number" && isFinite(value) && value >= 0 && Math.floor(value) === value; }
    var next = 0, sourceEnd = null, outputEnd = null;
    for (var i = 0; i < plan.visualSegments.length; i++) {
        var visual = plan.visualSegments[i], members = visual.MemberSegmentIndices;
        if (!members || !members.length) throw new Error("Speed merge members missing.");
        if (members.length > 2) throw new Error("Speed merge allows one adjacent pair only.");
        for (var j = 0; j < members.length; j++) {
            if (!integer(members[j]) || members[j] !== next || next >= plan.segments.length) throw new Error("Speed merge coverage changed.");
            var part = plan.segments[next++];
            var keys = ["SourceStartFrame", "SourceEndFrame", "NewStartFrame", "NewEndFrame"];
            for (var k = 0; k < keys.length; k++) if (!integer(part[keys[k]])) throw new Error("Speed merge frame invalid.");
            if (part.SourceEndFrame <= part.SourceStartFrame || part.NewEndFrame <= part.NewStartFrame ||
                (sourceEnd !== null && (part.SourceStartFrame !== sourceEnd || part.NewStartFrame !== outputEnd))) throw new Error("Speed merge base discontinuous.");
            sourceEnd = part.SourceEndFrame; outputEnd = part.NewEndFrame;
            if (j > 0) {
                var previous = plan.segments[members[j - 1]];
                if (previous.Kind !== "retime" || part.Kind !== "retime" || previous.OriginalVoiceEndFrame !== part.OriginalVoiceStartFrame) throw new Error("Speed merge crossed protected gap.");
            }
        }
        var first = plan.segments[members[0]], last = plan.segments[members[members.length - 1]];
        var timeFields = ["SourceStart", "SourceEnd", "NewStart", "NewEnd"];
        for (var ti = 0; ti < timeFields.length; ti++) if (typeof visual[timeFields[ti]] !== "number" || !isFinite(visual[timeFields[ti]])) throw new Error("Speed merge time invalid.");
        var sourceFrames = last.SourceEndFrame - first.SourceStartFrame, outFrames = last.NewEndFrame - first.NewStartFrame;
        if (visual.Kind !== first.Kind || visual.SourceStartFrame !== first.SourceStartFrame || visual.SourceEndFrame !== last.SourceEndFrame ||
            visual.NewStartFrame !== first.NewStartFrame || visual.NewEndFrame !== last.NewEndFrame ||
            visual.SourceDurationFrames !== sourceFrames || visual.OutputDurationFrames !== outFrames ||
            Math.abs(Number(visual.SourceStart) * plan.frameRate - first.SourceStartFrame) > 0.001 ||
            Math.abs(Number(visual.SourceEnd) * plan.frameRate - last.SourceEndFrame) > 0.001 ||
            Math.abs(Number(visual.NewStart) * plan.frameRate - first.NewStartFrame) > 0.001 ||
            Math.abs(Number(visual.NewEnd) * plan.frameRate - last.NewEndFrame) > 0.001) throw new Error("Speed merge visual span changed.");
        if (visual.Kind === "retime") {
            if (visual.VisualDurationFrames !== outFrames || visual.EffectiveSourceDurationFrames !== sourceFrames ||
                !isFinite(Number(visual.AppliedSpeedPercent)) || Math.abs(Number(visual.AppliedSpeedPercent) - 100 * sourceFrames / outFrames) > 0.000001 ||
                Number(visual.BorrowFrames || 0) !== 0 || Number(visual.TrimTailFrames || 0) !== 0) throw new Error("Speed merge speed changed.");
        } else {
            // Preserved no-dialogue spans must remain exactly as planned.
            for (var key in first) if (first.hasOwnProperty(key) && JSON.stringify(visual[key]) !== JSON.stringify(first[key])) throw new Error("Speed merge changed preserved element.");
        }
    }
    if (next !== plan.segments.length || sourceEnd !== plan.mainVideoSourceEndFrame || outputEnd !== plan.plannedMainVideoEndFrame) throw new Error("Speed merge tail lost.");
    return plan.visualSegments;
};

// The planner/DTW/speed balancer operate on the contiguous retained picture.
// Expand that coordinate system to real source frames before touching Premiere.
$._PVS._cuePicturePlans = function (plan, fallback) {
    if (plan.pictureCueRevision === undefined && plan.pictureSegments === undefined) return fallback;
    if (plan.pictureCueRevision !== "srt-cue-picture-v1" || !plan.pictureSegments || !plan.pictureSegments.length || plan.editedSourceMap !== undefined) throw new Error("Invalid cue picture plan.");
    function integer(v) { return typeof v === "number" && isFinite(v) && v >= 0 && Math.floor(v) === v; }
    var at = 0, used = 0, anchors = plan.pictureCueBoundaries || [], fps = Number(plan.frameRate);
    if (!isFinite(fps) || fps <= 0) throw new Error("Cue picture frame rate invalid.");
    for (var ai = 0; ai < anchors.length; ai++) {
        var anchor = anchors[ai], af = ["ParentSegmentIndex", "SourceFrame", "OutputFrame", "VoiceFrame", "Chapter", "LeftCue", "RightCue"];
        for (var ax = 0; ax < af.length; ax++) if (!integer(anchor[af[ax]])) throw new Error("Cue picture anchor invalid.");
        var owner = plan.segments[anchor.ParentSegmentIndex];
        if (!owner || owner.Kind !== "retime" || anchor.LeftCue < 1 || anchor.RightCue !== anchor.LeftCue + 1 || anchor.Chapter !== owner.Chapter ||
            anchor.VoiceFrame <= owner.OriginalVoiceStartFrame || anchor.VoiceFrame >= owner.OriginalVoiceEndFrame ||
            anchor.OutputFrame !== anchor.VoiceFrame - owner.OriginalVoiceStartFrame + owner.NewVoiceStartFrame) throw new Error("Cue picture voice anchor changed.");
    }
    for (var p = 0; p < plan.segments.length; p++) {
        var parent = plan.segments[p], sf = parent.SourceStartFrame, of = parent.NewStartFrame, count = 0;
        while (at < plan.pictureSegments.length && plan.pictureSegments[at].ParentSegmentIndex === p) {
            var part = plan.pictureSegments[at++]; count++;
            if (!integer(part.SourceStartFrame) || !integer(part.SourceEndFrame) || !integer(part.NewStartFrame) || !integer(part.NewEndFrame) ||
                part.SourceStartFrame !== sf || part.NewStartFrame !== of || part.SourceEndFrame <= sf || part.NewEndFrame <= of || part.Kind !== parent.Kind ||
                part.SourceEndFrame > parent.SourceEndFrame || part.NewEndFrame > parent.NewEndFrame ||
                part.SourceDurationFrames !== part.SourceEndFrame - sf || part.OutputDurationFrames !== part.NewEndFrame - of) throw new Error("Cue picture frame coverage changed.");
            var fields = ["SourceStart", "SourceEnd", "NewStart", "NewEnd"], frames = [sf, part.SourceEndFrame, of, part.NewEndFrame];
            for (var f = 0; f < fields.length; f++) if (typeof part[fields[f]] !== "number" || !isFinite(part[fields[f]]) || Math.abs(part[fields[f]] * fps - frames[f]) > 0.001) throw new Error("Cue picture time invalid.");
            if (parent.Kind === "gap") {
                for (var key in parent) if (parent.hasOwnProperty(key) && JSON.stringify(part[key]) !== JSON.stringify(parent[key])) throw new Error("Cue picture preserved gap changed.");
            } else if (part.Kind !== "retime" || part.VisualDurationFrames !== part.OutputDurationFrames || part.EffectiveSourceDurationFrames !== part.SourceDurationFrames ||
                typeof part.AppliedSpeedPercent !== "number" || !isFinite(part.AppliedSpeedPercent) || Math.abs(part.AppliedSpeedPercent - 100 * part.SourceDurationFrames / part.OutputDurationFrames) > 0.000001 || Number(part.BorrowFrames || 0) !== 0 || Number(part.TrimTailFrames || 0) !== 0) throw new Error("Cue picture speed invalid.");
            if (part.SourceEndFrame !== parent.SourceEndFrame) {
                var matches = 0;
                for (var a = 0; a < anchors.length; a++) if (anchors[a].ParentSegmentIndex === p && anchors[a].SourceFrame === part.SourceEndFrame && anchors[a].OutputFrame === part.NewEndFrame) matches++;
                if (matches !== 1) throw new Error("Cue picture acoustic anchor missing.");
                used++;
            }
            sf = part.SourceEndFrame; of = part.NewEndFrame;
        }
        if (!count || sf !== parent.SourceEndFrame || of !== parent.NewEndFrame) throw new Error("Cue picture parent lost.");
    }
    if (at !== plan.pictureSegments.length || used !== anchors.length) throw new Error("Cue picture tail or anchor lost.");
    return plan.pictureSegments;
};

$._PVS._shouldMarkSpeed = function (plan, planned, video, audio, outside, merged) {
    if (plan.pictureCueRevision !== "srt-cue-picture-v1") return outside || merged;
    // Planned per-cue retime is diagnostic; unreadable or unexpected native
    // speed still needs a marker, including errors inside the warning band.
    return video === null || audio === null || Math.abs(video - planned) > 0.01 || Math.abs(audio - planned) > 0.01;
};

$._PVS._speedMergeVisualPlans = function (plan) {
    var base = $._PVS._cuePicturePlans(plan, $._PVS._baseSpeedMergeVisualPlans(plan)), map = plan.editedSourceMap;
    if (map === undefined) return base;
    function integer(v) { return typeof v === "number" && isFinite(v) && v >= 0 && Math.floor(v) === v; }
    function requireInteger(v) { if (!integer(v)) throw new Error("Edited source frame invalid."); }
    if (!map || map.revision !== "srt-omissions-v1" || !map.kept || !map.kept.length || !map.omissions || !map.omissions.length) throw new Error("Edited source map invalid.");
    var fields = ["physicalStartFrame", "physicalEndFrame", "planStartFrame", "planEndFrame"], i, j;
    for (i = 0; i < fields.length; i++) requireInteger(map[fields[i]]);
    if (!isFinite(plan.frameRate) || plan.frameRate <= 0 || !plan.mainVideoClip ||
        Math.round(plan.mainVideoClip.start * plan.frameRate) !== map.physicalStartFrame ||
        Math.round(plan.mainVideoClip.end * plan.frameRate) !== map.physicalEndFrame ||
        map.planStartFrame !== map.physicalStartFrame || map.planEndFrame !== plan.mainVideoSourceEndFrame) throw new Error("Edited source bounds changed.");
    var physical = [], virtual = map.planStartFrame;
    for (i = 0; i < map.kept.length; i++) {
        var kept = map.kept[i];
        fields = ["SourceStartFrame", "SourceEndFrame", "PlanStartFrame", "PlanEndFrame"];
        for (j = 0; j < fields.length; j++) requireInteger(kept[fields[j]]);
        if (kept.SourceEndFrame <= kept.SourceStartFrame || kept.PlanStartFrame !== virtual ||
            kept.PlanEndFrame - kept.PlanStartFrame !== kept.SourceEndFrame - kept.SourceStartFrame) throw new Error("Edited kept picture invalid.");
        virtual = kept.PlanEndFrame; physical.push(kept);
    }
    for (i = 0; i < map.omissions.length; i++) {
        var omitted = map.omissions[i];
        requireInteger(omitted.SourceStartFrame); requireInteger(omitted.SourceEndFrame);
        if (omitted.SourceEndFrame <= omitted.SourceStartFrame || omitted.Reason !== "join-rerecognized-with-retained-anchors" || !omitted.CueIndices || !omitted.CueIndices.length) throw new Error("Edited omission proof missing.");
        for (j = 0; j < omitted.CueIndices.length; j++) if (!integer(omitted.CueIndices[j]) || omitted.CueIndices[j] < 1) throw new Error("Edited omission cue invalid.");
        physical.push(omitted);
    }
    physical.sort(function (a, b) { return a.SourceStartFrame - b.SourceStartFrame; });
    var edge = map.physicalStartFrame;
    for (i = 0; i < physical.length; i++) {
        if (physical[i].SourceStartFrame !== edge) throw new Error("Edited physical picture lost or duplicated.");
        edge = physical[i].SourceEndFrame;
    }
    if (edge !== map.physicalEndFrame || virtual !== map.planEndFrame) throw new Error("Edited source tail changed.");
    var expanded = [], sourceEdge = map.planStartFrame, outputEdge = 0;
    for (i = 0; i < base.length; i++) {
        var part = base[i];
        fields = ["SourceStartFrame", "SourceEndFrame", "NewStartFrame", "NewEndFrame"];
        for (j = 0; j < fields.length; j++) requireInteger(part[fields[j]]);
        if (part.SourceStartFrame !== sourceEdge || part.NewStartFrame !== outputEdge || part.SourceEndFrame <= sourceEdge || part.NewEndFrame <= outputEdge ||
            (part.Kind !== "retime" && part.Kind !== "gap") || Number(part.BorrowFrames || 0) !== 0 || Number(part.TrimTailFrames || 0) !== 0) throw new Error("Edited base picture invalid.");
        if (part.Kind === "gap" && part.NewEndFrame - part.NewStartFrame !== part.SourceEndFrame - part.SourceStartFrame) throw new Error("Edited no-dialogue duration changed.");
        for (j = 0; j < map.kept.length; j++) {
            kept = map.kept[j];
            var a = Math.max(part.SourceStartFrame, kept.PlanStartFrame), b = Math.min(part.SourceEndFrame, kept.PlanEndFrame);
            if (b <= a) continue;
            var start = part.NewStartFrame + Math.round((a - part.SourceStartFrame) * (part.NewEndFrame - part.NewStartFrame) / (part.SourceEndFrame - part.SourceStartFrame));
            var end = part.NewStartFrame + Math.round((b - part.SourceStartFrame) * (part.NewEndFrame - part.NewStartFrame) / (part.SourceEndFrame - part.SourceStartFrame));
            if (end <= start) throw new Error("Edited picture part collapses on frame grid.");
            var copy = {};
            for (var key in part) if (part.hasOwnProperty(key)) copy[key] = part[key];
            copy.SourceStartFrame = kept.SourceStartFrame + a - kept.PlanStartFrame;
            copy.SourceEndFrame = copy.SourceStartFrame + b - a;
            copy.SourceStart = copy.SourceStartFrame / plan.frameRate; copy.SourceEnd = copy.SourceEndFrame / plan.frameRate;
            copy.SourceDurationFrames = b - a; copy.SourceDuration = (b - a) / plan.frameRate;
            copy.EffectiveSourceDurationFrames = b - a; copy.EffectiveSourceDuration = copy.SourceDuration;
            copy.NewStartFrame = start; copy.NewEndFrame = end; copy.NewStart = start / plan.frameRate; copy.NewEnd = end / plan.frameRate;
            copy.OutputDurationFrames = end - start; copy.OutputDuration = (end - start) / plan.frameRate; copy.VisualDurationFrames = end - start;
            if (copy.Kind === "retime") { copy.AppliedSpeedPercent = 100 * (b - a) / (end - start); copy.DesiredSpeedPercent = copy.AppliedSpeedPercent; }
            copy.EditedSourcePart = true; expanded.push(copy);
        }
        sourceEdge = part.SourceEndFrame; outputEdge = part.NewEndFrame;
    }
    if (sourceEdge !== map.planEndFrame || outputEdge !== plan.plannedMainVideoEndFrame) throw new Error("Edited plan tail changed.");
    return expanded;
};

$._PVS._result = function (value) {
    try { return JSON.stringify(value); }
    catch (e) { return '{"ok":false,"error":"JSON serialization failed"}'; }
};

$._PVS._error = function (e) {
    return $._PVS._result({ ok: false, error: e && e.message ? e.message : String(e) });
};

$._PVS.scanSequence = function () {
    try {
        var seq = app.project && app.project.activeSequence;
        if (!seq) return $._PVS._result({ ok: false, error: "Không có sequence đang mở." });
        if (seq.videoTracks.numTracks < 1) return $._PVS._result({ ok: false, error: "Sequence không có V1." });
        if (seq.audioTracks.numTracks < 2) return $._PVS._result({ ok: false, error: "Sequence cần có A2 chứa voice mới." });

        var v1 = seq.videoTracks[0];
        var v1Count = v1.clips.numItems;
        var mainVideoPieceCount = 0;
        var looksNested = false;
        var mainVideoClip = null;
        var linkedAudio = [];
        var fps = 30;
        try { fps = 254016000000 / Number(seq.timebase); } catch (ignoreFps) {}
        if (v1Count > 0) {
            var main = v1.clips[0];
            var mainSpeed = 100;
            try {
                mainSpeed = Number(main.getSpeed());
                if (mainSpeed > 0 && mainSpeed <= 10) mainSpeed *= 100;
            } catch (ignoreMainSpeed) { mainSpeed = 100; }
            mainVideoClip = {
                name: main.name,
                nodeId: main.nodeId,
                start: main.start.seconds,
                end: main.end.seconds,
                duration: main.duration.seconds,
                inPoint: main.inPoint.seconds,
                outPoint: main.outPoint.seconds,
                speedPercent: mainSpeed
            };
            try {
                var linked = main.getLinkedItems();
                for (var li = 0; li < linked.length; li++) {
                    var linkedItem = linked[li];
                    if (linkedItem.mediaType === "Audio") {
                        linkedAudio.push({
                            name: linkedItem.name,
                            nodeId: linkedItem.nodeId,
                            start: linkedItem.start.seconds,
                            end: linkedItem.end.seconds
                        });
                    }
                }
            } catch (ignoreLinked) {}
        }
        if (v1Count === 1) {
            try {
                var vItem = v1.clips[0].projectItem;
                looksNested = vItem && (!vItem.getMediaPath || vItem.getMediaPath() === "");
            } catch (ignore) { looksNested = true; }
        }
        if (mainVideoClip) {
            for (var mainPieceIndex = 0; mainPieceIndex < v1.clips.numItems; mainPieceIndex++) {
                if (String(v1.clips[mainPieceIndex].name) === String(mainVideoClip.name)) mainVideoPieceCount++;
            }
        }

        var a2 = seq.audioTracks[1];
        var voices = [];
        for (var i = 0; i < a2.clips.numItems; i++) {
            var clip = a2.clips[i];
            var mediaPath = "";
            var speed = 100;
            try { mediaPath = clip.projectItem.getMediaPath(); } catch (ignorePath) {}
            try {
                speed = Number(clip.getSpeed());
                if (speed > 0 && speed <= 10) speed *= 100;
            } catch (ignoreSpeed) { speed = 100; }
            voices.push({
                index: i,
                name: clip.name,
                path: mediaPath,
                start: clip.start.seconds,
                end: clip.end.seconds,
                duration: clip.duration.seconds,
                inPoint: clip.inPoint.seconds,
                outPoint: clip.outPoint.seconds,
                speedPercent: speed
            });
        }
        var mainVoiceCount = voices.length ? 1 : 0;
        for (var voiceIndex = 1; voiceIndex < voices.length; voiceIndex++) {
            if (Number(voices[voiceIndex].start) - Number(voices[voiceIndex - 1].end) > 2.0) break;
            mainVoiceCount++;
        }

        return $._PVS._result({
            ok: true,
            name: seq.name,
            projectId: String(app.project.documentID || app.project.path || ""),
            applicationFolder: Folder.startup.fsName,
            sequenceId: seq.sequenceID,
            videoTrackCount: seq.videoTracks.numTracks,
            audioTrackCount: seq.audioTracks.numTracks,
            captionTrackCount: seq.captionTracks ? seq.captionTracks.numTracks : 0,
            frameRate: fps,
            v1ClipCount: v1Count,
            mainVideoPieceCount: mainVideoPieceCount,
            v1LooksNested: looksNested,
            mainVideoClip: mainVideoClip,
            linkedAudio: linkedAudio,
            voiceTrackIndex: 1,
            mainVoiceCount: mainVoiceCount,
            voices: voices
        });
    } catch (e) { return $._PVS._error(e); }
};

$._PVS._srtProjectKey = function () {
    if (!app.project || !app.project.rootItem) throw new Error("Không có project đang mở.");
    return String(app.project.rootItem.nodeId) + "|" + String(app.project.path || "");
};
$._PVS._startSrtScan = function (token) {
    var root = app.project.rootItem, children = root.children;
    $._PVS._srtScanState = { token: token, projectKey: $._PVS._srtProjectKey(), stack: [{ bin: root, children: children, count: children.numItems, index: 0 }], seenBins: {}, scanned: 0, pass: 0 };
    $._PVS._srtScanState.seenBins["id:" + String(root.nodeId)] = true;
    return { ok: true, done: false, candidates: [], scanned: 0 };
};
$._PVS._advanceSrtScan = function (token) {
    var scan = $._PVS._srtScanState;
    if (!scan || scan.token !== token) throw new Error("Phiên quét SRT không còn hợp lệ. Hãy Đọc lại.");
    if (scan.projectKey !== $._PVS._srtProjectKey()) throw new Error("Project đã đổi trong lúc quét SRT. Hãy Đọc lại.");
    var found = [], started = new Date().getTime(), processed = 0;
    scan.pass++;
    while (scan.stack.length && processed < 64 && new Date().getTime() - started < 40) {
        var frame = scan.stack[scan.stack.length - 1];
        if (frame.checkedPass !== scan.pass) {
            if (frame.children.numItems !== frame.count) throw new Error("Project đã thay đổi trong lúc quét SRT. Hãy Đọc lại.");
            frame.checkedPass = scan.pass;
        }
        if (frame.index >= frame.count) { scan.stack.pop(); continue; }
        var item = frame.children[frame.index++]; processed++; scan.scanned++;
        if (scan.scanned > 100000 || scan.stack.length > 1000) throw new Error("Project quá lớn hoặc cây thư mục không hợp lệ. Hãy chọn SRT bằng Chọn ngoài.");
        if (!item) continue;
        // Only bins have traversable children. Accessing children recursively
        // on every native ProjectItem can revisit invalid/cyclic wrappers.
        if (item.type === ProjectItemType.BIN) {
            var key = "id:" + String(item.nodeId);
            if (scan.seenBins[key]) continue;
            scan.seenBins[key] = true;
            var children = item.children;
            scan.stack.push({ bin: item, children: children, count: children.numItems, index: 0 });
        } else {
            try {
                if (item.isSequence && item.isSequence()) continue;
                var mediaPath = item.getMediaPath ? String(item.getMediaPath() || "") : "";
                if (/\.srt$/i.test(mediaPath)) found.push({ name: String(item.name || ""), path: mediaPath });
            } catch (ignorePath) {}
        }
    }
    var done = !scan.stack.length, count = scan.scanned;
    if (done) $._PVS._srtScanState = null;
    return { ok: true, done: done, candidates: found, scanned: count };
};
$._PVS.beginSrtScan = function (token) {
    try { return $._PVS._result($._PVS._startSrtScan(String(token))); }
    catch (e) { return $._PVS._error(e); }
};
$._PVS.advanceSrtScan = function (token) {
    try { return $._PVS._result($._PVS._advanceSrtScan(String(token))); }
    catch (e) {
        if ($._PVS._srtScanState && $._PVS._srtScanState.token === String(token)) $._PVS._srtScanState = null;
        return $._PVS._error(e);
    }
};
$._PVS.findSrtCandidates = function () {
    // Compatibility entry point. The panel uses bounded begin/advance calls.
    try {
        var token = "legacy-" + new Date().getTime(), candidates = [], result;
        $._PVS._startSrtScan(token);
        do { result = $._PVS._advanceSrtScan(token); candidates = candidates.concat(result.candidates); } while (!result.done);
        return $._PVS._result({ ok: true, candidates: candidates });
    } catch (e) { $._PVS._srtScanState = null; return $._PVS._error(e); }
};

$._PVS._findItemByMediaPath = function (root, targetPath) {
    if (!root || !root.children) return null;
    for (var i = 0; i < root.children.numItems; i++) {
        var item = root.children[i];
        try {
            if (item.getMediaPath && item.getMediaPath() === targetPath) return item;
        } catch (ignore) {}
        if (item.type === ProjectItemType.BIN) {
            var found = $._PVS._findItemByMediaPath(item, targetPath);
            if (found) return found;
        }
    }
    return null;
};

$._PVS._readJsonFile = function (path) {
    var file = new File(path);
    if (!file.exists) throw new Error("File not found: " + path);
    file.encoding = "UTF-8";
    if (!file.open("r")) throw new Error("Could not open: " + path);
    var text = file.read();
    file.close();
    if (text.charCodeAt(0) === 0xFEFF) text = text.substring(1);
    return JSON.parse(text);
};

// Caption-only APIs are independent of the edit executor and template tracks.
$._PVS._captionOnlySnapshot = function (seq, structural) {
    var values = [String(seq.sequenceID), String(seq.timebase)];
    var groups = [seq.videoTracks, seq.audioTracks];
    for (var groupIndex = 0; groupIndex < groups.length; groupIndex++) {
        var tracks = groups[groupIndex];
        values.push("tracks:" + groupIndex + ":" + tracks.numTracks);
        for (var trackIndex = 0; trackIndex < tracks.numTracks; trackIndex++) {
            var track = tracks[trackIndex];
            if (!(structural && groupIndex === 1)) try { values.push("muted:" + groupIndex + ":" + trackIndex + ":" + track.isMuted()); } catch (ignoreMute) {}
            values.push("track:" + groupIndex + ":" + trackIndex + ":" + String(track.id === undefined ? track.name || "" : track.id));
            for (var clipIndex = 0; clipIndex < track.clips.numItems; clipIndex++) {
                var clip = track.clips[clipIndex];
                var speed = "";
                try { speed = String(clip.getSpeed()); } catch (ignoreSpeed) {}
                var disabled = "unavailable", sourceId = "";
                if (!(structural && groupIndex === 1)) try { if (typeof clip.disabled === "boolean") disabled = clip.disabled; } catch (ignoreDisabled) {}
                try { sourceId = clip.projectItem ? String(clip.projectItem.nodeId) : ""; } catch (ignoreSource) {}
                values.push([groupIndex, trackIndex, clip.nodeId, sourceId, clip.start.ticks, clip.end.ticks, clip.inPoint.ticks, clip.outPoint.ticks, speed, disabled].join("|"));
            }
        }
    }
    return values.join("\n");
};

// Read only; used solely at an explicit pause/resume boundary. Playhead and
// selection are intentionally excluded so playback does not invalidate a pause.
$._PVS.workflowPauseState = function () {
    try {
        var project = app.project, seq = project && project.activeSequence;
        if (!seq) throw new Error("Không có sequence đang mở để kiểm tra tạm dừng.");
        var ip = seq.getInPoint(), op = seq.getOutPoint();
        if (ip === undefined || ip === null || op === undefined || op === null || String(ip).replace(/\s/g, "") === "" || String(op).replace(/\s/g, "") === "" || !isFinite(Number(ip)) || !isFinite(Number(op))) throw new Error("Không đọc được In/Out để kiểm tra tiếp tục.");
        var rows = [String(project.documentID || ""), String(project.path || ""), $._PVS._captionOnlySnapshot(seq), "in:" + String(ip), "out:" + String(op)];
        var kinds = [seq.videoTracks, seq.audioTracks];
        for (var k = 0; k < kinds.length; k++) {
            for (var t = 0; t < kinds[k].numTracks; t++) {
                var clips = kinds[k][t].clips;
                for (var c = 0; c < clips.numItems; c++) {
                    var item = clips[c].projectItem;
                    rows.push("source:" + k + ":" + t + ":" + c + ":" + (item ? String(item.nodeId) : ""));
                }
            }
        }
        var captions = seq.captionTracks;
        if (captions !== undefined && captions !== null) {
            if (typeof captions.numTracks !== "number" || !isFinite(captions.numTracks) || captions.numTracks < 0 || Math.floor(captions.numTracks) !== captions.numTracks) throw new Error("Không đọc được số Caption Track.");
            rows.push("captions:" + captions.numTracks);
        } else rows.push("captions:unavailable");
        var root = project.rootItem;
        if (root && root.children) {
            rows.push("bins:" + root.children.numItems);
            for (var i = 0; i < root.children.numItems; i++) rows.push("bin:" + String(root.children[i].nodeId) + ":" + String(root.children[i].name));
        }
        return $._PVS._result({ ok: true, state: JSON.stringify(rows) });
    } catch (error) { return $._PVS._result({ ok: false, error: String(error) }); }
};

$._PVS.scanCaptionRange = function () {
    try {
        var seq = app.project && app.project.activeSequence;
        if (!seq) throw new Error("Hãy mở sequence cần tạo subtitle.");
        var fps = 254016000000 / Number(seq.timebase);
        if (!isFinite(fps) || fps <= 0 || fps > 240) throw new Error("Không đọc được frame rate của sequence.");
        var selections = seq.getSelection();
        var ranges = [];
        var selectedNames = [], selectedAudioNodes = {};
        for (var selectionIndex = 0; selections && selectionIndex < selections.length; selectionIndex++) {
            var selected = selections[selectionIndex];
            if (selected.mediaType !== "Video" && selected.mediaType !== "Audio") continue;
            if (selected.mediaType === "Audio" && selected.nodeId !== undefined) selectedAudioNodes["clip:" + String(selected.nodeId)] = true;
            var startFrame = Math.round(Number(selected.start.seconds) * fps);
            var endFrame = Math.round(Number(selected.end.seconds) * fps);
            if (endFrame > startFrame) {
                ranges.push({ startFrame: startFrame, endFrame: endFrame });
                selectedNames.push(String(selected.name));
            }
        }
        var selectionRanges = [];
        for (var sr = 0; sr < ranges.length; sr++) selectionRanges.push({ start: ranges[sr].startFrame / fps, end: ranges[sr].endFrame / fps });
        var useSelection = ranges.length > 0;
        if (!useSelection) {
            var maximumEnd = 0;
            var groups = [seq.videoTracks, seq.audioTracks];
            for (var groupIndex = 0; groupIndex < groups.length; groupIndex++) {
                for (var trackIndex = 0; trackIndex < groups[groupIndex].numTracks; trackIndex++) {
                    var clips = groups[groupIndex][trackIndex].clips;
                    for (var clipIndex = 0; clipIndex < clips.numItems; clipIndex++) maximumEnd = Math.max(maximumEnd, Math.round(Number(clips[clipIndex].end.seconds) * fps));
                }
            }
            if (maximumEnd <= 0) throw new Error("Sequence chưa có video hoặc audio.");
            ranges.push({ startFrame: 0, endFrame: maximumEnd });
        }
        ranges.sort(function (a, b) { return a.startFrame - b.startFrame; });
        var merged = [];
        for (var rangeIndex = 0; rangeIndex < ranges.length; rangeIndex++) {
            var current = ranges[rangeIndex];
            if (merged.length && current.startFrame <= merged[merged.length - 1].endFrame) {
                merged[merged.length - 1].endFrame = Math.max(merged[merged.length - 1].endFrame, current.endFrame);
            } else merged.push({ startFrame: current.startFrame, endFrame: current.endFrame });
        }
        for (rangeIndex = 0; rangeIndex < merged.length; rangeIndex++) {
            merged[rangeIndex].start = merged[rangeIndex].startFrame / fps;
            merged[rangeIndex].end = merged[rangeIndex].endFrame / fps;
        }
        var audioTracks = [], selectedAudio = [], sequenceEnd = 0;
        var allGroups = [seq.videoTracks, seq.audioTracks];
        for (var g = 0; g < allGroups.length; g++) for (var t = 0; t < allGroups[g].numTracks; t++) for (var c = 0; c < allGroups[g][t].clips.numItems; c++) sequenceEnd = Math.max(sequenceEnd, Number(allGroups[g][t].clips[c].end.seconds));
        for (var audioIndex = 0; audioIndex < seq.audioTracks.numTracks; audioIndex++) {
            var audioTrack = seq.audioTracks[audioIndex];
            var clipsMeta = [], muted = null;
            try { var muteValue = audioTrack.isMuted(); if (muteValue === true || muteValue === false || muteValue === 0 || muteValue === 1) muted = !!muteValue; } catch (ignoreTrackMute) {}
            for (var ac = 0; ac < audioTrack.clips.numItems; ac++) {
                var audioClip = audioTrack.clips[ac], disabled = null, sourceId = "";
                try { if (typeof audioClip.disabled === "boolean") disabled = audioClip.disabled; } catch (ignoreClipDisabled) {}
                try { sourceId = audioClip.projectItem ? String(audioClip.projectItem.nodeId) : ""; } catch (ignoreClipSource) {}
                var nodeId = audioClip.nodeId === undefined ? "" : String(audioClip.nodeId);
                clipsMeta.push({ nodeId: nodeId, sourceId: sourceId, name: String(audioClip.name), start: Number(audioClip.start.seconds), end: Number(audioClip.end.seconds), disabled: disabled });
                if (selectedAudioNodes["clip:" + nodeId]) selectedAudio.push({ trackIndex: audioIndex, nodeId: nodeId });
            }
            audioTracks.push({ index: audioIndex, key: audioTrack.id === undefined ? "name:" + String(audioTrack.name || "") : "id:" + String(audioTrack.id), name: String(audioTrack.name || ""), clipCount: audioTrack.clips.numItems, clips: clipsMeta, muted: muted });
        }
        var rawIn = seq.getInPoint(), rawOut = seq.getOutPoint(), inStart = Number(rawIn), inEnd = Number(rawOut);
        var validInOut = rawIn !== null && rawIn !== undefined && rawOut !== null && rawOut !== undefined && String(rawIn).replace(/\s/g, "") !== "" && String(rawOut).replace(/\s/g, "") !== "" && isFinite(inStart) && isFinite(inEnd) && inStart >= 0 && inEnd > inStart;
        return $._PVS._result({ ok: true, inputVersion: 1, projectId: String(app.project.documentID || app.project.path || ""), sequenceId: String(seq.sequenceID), name: seq.name, frameRate: fps, ranges: merged, useSelection: useSelection, selectedNames: selectedNames, audioTracks: audioTracks, sequenceEnd: sequenceEnd, selectionRanges: selectionRanges, selectedAudio: selectedAudio, inOut: { start: inStart, end: inEnd, valid: validInOut }, applicationFolder: Folder.startup.fsName, snapshot: $._PVS._captionOnlySnapshot(seq) });
    } catch (e) { return $._PVS._error(e); }
};

$._PVS._writeCaptionAudioJournal = function (path, value) {
    var file = new File(path);
    if (file.exists) throw new Error("Còn trạng thái khôi phục audio cũ. Hãy kiểm tra trước khi xuất lại.");
    file.encoding = "UTF-8";
    if (!file.open("w")) throw new Error("Không tạo được nhật ký khôi phục audio. Chưa thay đổi timeline.");
    try {
        try { if (file.write(JSON.stringify(value)) === false) throw new Error("Không ghi được nhật ký khôi phục audio."); }
        finally { file.close(); }
        if (JSON.stringify($._PVS._readJsonFile(path)) !== JSON.stringify(value)) throw new Error("Nhật ký khôi phục audio chưa được xác minh. Chưa thay đổi timeline.");
    } catch (error) { try { file.remove(); } catch (ignoreRemove) {} throw error; }
};
$._PVS._restoreCaptionAudioJournal = function (path) {
    try {
        if (typeof path !== "string" || !/\.audio-recovery\.json$/.test(path)) throw new Error("Đường dẫn khôi phục audio không hợp lệ.");
        if (!(new File(path)).exists) return { ok: true, restored: true, found: false };
        var record = $._PVS._readJsonFile(path), seq = app.project && app.project.activeSequence;
        if (record.revision !== 1 || !seq || String(app.project.documentID || app.project.path || "") !== record.projectId || String(seq.sequenceID) !== record.sequenceId || $._PVS._captionOnlySnapshot(seq, true) !== record.structure) throw new Error("Project/sequence hoặc cấu trúc timeline không khớp nhật ký. Chưa áp dụng trạng thái audio cũ.");
        if (Object.prototype.toString.call(record.tracks) !== "[object Array]" || record.tracks.length !== seq.audioTracks.numTracks || Object.prototype.toString.call(record.clips) !== "[object Array]" || typeof record.snapshot !== "string" || typeof record.inPoint !== "number" || typeof record.outPoint !== "number" || !isFinite(record.inPoint) || !isFinite(record.outPoint)) throw new Error("Nhật ký khôi phục audio không hợp lệ. Chưa thay đổi timeline.");
        var errors = [], i;
        for (i = 0; i < record.tracks.length; i++) if (typeof record.tracks[i] !== "boolean" || typeof seq.audioTracks[i].setMute !== "function" || typeof seq.audioTracks[i].isMuted !== "function") throw new Error("Không xác minh được track cần khôi phục.");
        // Validate identities before the first recovery write.
        for (i = 0; i < record.clips.length; i++) {
            var entry = record.clips[i];
            if (typeof entry.trackIndex !== "number" || Math.floor(entry.trackIndex) !== entry.trackIndex || entry.trackIndex < 0 || entry.trackIndex >= seq.audioTracks.numTracks || typeof entry.nodeId !== "string" || typeof entry.disabled !== "boolean") throw new Error("Danh tính clip trong nhật ký không hợp lệ.");
            var clips = seq.audioTracks[entry.trackIndex].clips, found = false;
            for (var ci = 0; ci < clips.numItems; ci++) if (String(clips[ci].nodeId) === entry.nodeId) { found = true; break; }
            if (!found || typeof clips[ci].disabled !== "boolean") throw new Error("Không xác minh được clip cần khôi phục: " + entry.nodeId);
        }
        for (i = 0; i < record.clips.length; i++) {
            entry = record.clips[i]; clips = seq.audioTracks[entry.trackIndex].clips;
            for (ci = 0; ci < clips.numItems; ci++) if (String(clips[ci].nodeId) === entry.nodeId) break;
            try { clips[ci].disabled = entry.disabled; if (clips[ci].disabled !== entry.disabled) throw new Error("enable chưa khôi phục"); }
            catch (clipError) { errors.push("Clip " + entry.nodeId + ": " + clipError.message); }
        }
        for (i = 0; i < record.tracks.length; i++) {
            try {
                var track = seq.audioTracks[i];
                track.setMute(record.tracks[i] ? 1 : 0);
                var muted = track.isMuted();
                if ((muted !== true && muted !== false && muted !== 0 && muted !== 1) || !!muted !== record.tracks[i]) throw new Error("mute chưa khôi phục");
            } catch (muteError) { errors.push("Track A" + (i + 1) + ": " + muteError.message); }
        }
        try { seq.setInPoint(record.inPoint); } catch (inError) { errors.push(String(inError)); }
        try { seq.setOutPoint(record.outPoint); } catch (outError) { errors.push(String(outError)); }
        var restoredIn = Number(seq.getInPoint()), restoredOut = Number(seq.getOutPoint());
        if (!isFinite(restoredIn) || !isFinite(restoredOut) || Math.abs(restoredIn - record.inPoint) > 0.000001 || Math.abs(restoredOut - record.outPoint) > 0.000001 || $._PVS._captionOnlySnapshot(seq) !== record.snapshot) errors.push("Chưa xác minh được trạng thái gốc sau khôi phục.");
        if (errors.length) throw new Error(errors.join("\n"));
        if (!(new File(path)).remove()) throw new Error("Đã khôi phục audio nhưng chưa xóa được nhật ký khôi phục.");
        return { ok: true, restored: true, found: true };
    } catch (error) { return { ok: false, restored: false, error: String(error.message || error) }; }
};

$._PVS.captionInputRevision = 1;
$._PVS.beginCaptionAudioExport = function (jobPath, presetPath, token) {
    var exportPhase = "preflight";
    var session = null;
    var hostStarted = (new Date()).getTime();
    function timedResult(value) {
        value.audioExportTiming = { hostMilliseconds: Math.max(0, (new Date()).getTime() - hostStarted) };
        if (session && typeof session.finalizeMilliseconds === "number") value.audioExportTiming.finalizeMilliseconds = session.finalizeMilliseconds;
        return $._PVS._result(value);
    }
    try {
        if ($._PVS._captionAudioExport) throw new Error("Một phiên xuất audio đang mở. Hãy hoàn tất/kiểm tra phiên trước.");
        if (typeof token !== "string" || !token.length) throw new Error("Thiếu mã phiên xuất audio.");
        var job = $._PVS._readJsonFile(jobPath);
        var seq = app.project && app.project.activeSequence;
        if (!seq || String(seq.sequenceID) !== String(job.sequenceId) || $._PVS._captionOnlySnapshot(seq) !== job.snapshot) throw new Error("Sequence đã thay đổi. Hãy đọc lại phạm vi subtitle.");
        if (job.workflow !== "caption-only" || !job.sources || !job.sources.length) throw new Error("Dữ liệu tạo subtitle không hợp lệ.");
        for (var ri = 0; ri < job.sources.length; ri++) {
            var range = job.sources[ri];
            if (typeof range.start !== "number" || typeof range.end !== "number" || !isFinite(range.start) || !isFinite(range.end) || range.start < 0 || range.end <= range.start) throw new Error("Phạm vi subtitle không hợp lệ.");
        }
        var frameSeconds = Number(seq.timebase) / 254016000000;
        if (!isFinite(frameSeconds) || frameSeconds <= 0) throw new Error("Không đọc được timebase của sequence.");
        if (!(new File(presetPath)).exists) throw new Error("Không tìm thấy preset xuất WAV của Premiere.");
        var voiceIndex = job.voiceTrackIndex, voiceIndices = [], inputPlan = null, clipStates = [], journalPath = null;
        if (job.audioInput) {
            if (!$._PVS.captionInput || $._PVS.captionInput.revision !== 1 || typeof $._PVS.captionInput.resolve !== "function" || typeof $._PVS.captionInput.sameKey !== "function") throw new Error("Chưa nạp bộ lập kế hoạch nguồn audio.");
            var scan = JSON.parse($._PVS.scanCaptionRange());
            if (!scan.ok || scan.projectId !== job.projectId) throw new Error("Project đã thay đổi. Hãy cập nhật đầu vào.");
            // Selection is frozen in the job. A later UI selection cannot change its source.
            if (job.audioInput.sourceMode === "clips") scan.selectedAudio = job.audioInput.selectedAudio;
            if (job.audioInput.scopeMode === "selection") scan.selectionRanges = job.audioInput.scopeRanges;
            inputPlan = $._PVS.captionInput.resolve(scan, job.audioInput);
            if (!$._PVS.captionInput.sameKey(inputPlan.key, job.audioInputKey, scan.frameRate)) throw new Error("Nguồn hoặc phạm vi audio đã thay đổi. Hãy cập nhật đầu vào.");
            if (!$._PVS.captionInput.sameRanges(job.sources, inputPlan.ranges, scan.frameRate)) throw new Error("Phạm vi xuất khác kế hoạch nguồn audio.");
            voiceIndices = inputPlan.trackIndices;
            voiceIndex = voiceIndices.length === 1 ? voiceIndices[0] : null;
        } else {
            if (typeof voiceIndex !== "number" || !isFinite(voiceIndex) || Math.floor(voiceIndex) !== voiceIndex || voiceIndex < 0 || voiceIndex >= seq.audioTracks.numTracks) throw new Error("Hãy chọn track voice cần nhận diện và cập nhật lại đầu vào.");
            voiceIndices = [voiceIndex];
        }
        function chosenTrack(index) { for (var i = 0; i < voiceIndices.length; i++) if (voiceIndices[i] === index) return true; return false; }
        var hasVoice = false;
        var voiceClips = seq.audioTracks[voiceIndices[0]].clips;
        for (var vi = 0; vi < voiceClips.numItems; vi++) {
            for (var si = 0; si < job.sources.length; si++) {
                if (Number(voiceClips[vi].start.seconds) < Number(job.sources[si].end) && Number(voiceClips[vi].end.seconds) > Number(job.sources[si].start)) hasVoice = true;
            }
        }
        if (!inputPlan && !hasVoice) throw new Error("Track A" + (voiceIndex + 1) + " không có clip audio trong phạm vi subtitle. Hãy chọn đúng track voice.");
        function readMute(track) {
            var value = track.isMuted();
            if (value !== true && value !== false && value !== 0 && value !== 1) throw new Error("Trạng thái mute không hợp lệ.");
            return value === true || value === 1;
        }
        var muteStates = [];
        // Read every state before changing anything, so partial setup can be restored.
        for (var ti = 0; ti < seq.audioTracks.numTracks; ti++) {
            var track = seq.audioTracks[ti];
            if (!track || typeof track.isMuted !== "function" || typeof track.setMute !== "function") throw new Error("Không điều khiển được mute của track A" + (ti + 1) + ". Chưa xuất audio.");
            muteStates.push({ track: track, muted: readMute(track), changed: false });
        }
        if (inputPlan && inputPlan.input.sourceMode === "clips") {
            for (ti = 0; ti < seq.audioTracks.numTracks; ti++) if (chosenTrack(ti)) {
                var trackClips = seq.audioTracks[ti].clips;
                for (var tci = 0; tci < trackClips.numItems; tci++) {
                    var item = trackClips[tci], overlaps = false, selectedClip = false;
                    for (ri = 0; ri < job.sources.length; ri++) if (Number(item.start.seconds) < job.sources[ri].end && Number(item.end.seconds) > job.sources[ri].start) overlaps = true;
                    if (!overlaps) continue;
                    for (var sci = 0; sci < inputPlan.selectedClips.length; sci++) if (inputPlan.selectedClips[sci].trackIndex === ti && inputPlan.selectedClips[sci].nodeId === String(item.nodeId)) selectedClip = true;
                    if (typeof item.disabled !== "boolean") throw new Error("Không đọc được enable của clip audio cùng track. Chưa xuất audio.");
                    clipStates.push({ clip: item, trackIndex: ti, disabled: item.disabled, target: selectedClip ? item.disabled : true, changed: false });
                }
            }
        }
        function verifyIsolation() {
            if (!app.project.activeSequence || String(app.project.activeSequence.sequenceID) !== String(seq.sequenceID) || seq.audioTracks.numTracks !== muteStates.length) throw new Error("Sequence đã thay đổi trong lúc xuất audio.");
            for (var mi = 0; mi < muteStates.length; mi++) {
                var targetMute = inputPlan && inputPlan.input.sourceMode === "mix" ? muteStates[mi].muted : !chosenTrack(mi);
                if (readMute(muteStates[mi].track) !== targetMute) throw new Error("Không xác minh được tập track audio đã chọn. Chưa xác minh audio xuất.");
            }
            for (var csi = 0; csi < clipStates.length; csi++) if (clipStates[csi].clip.disabled !== clipStates[csi].target) throw new Error("Không cô lập được đúng các clip audio đã chọn. Chưa xác minh audio xuất.");
        }
        var oldIn = seq.getInPoint();
        var oldOut = seq.getOutPoint();
        if (oldIn === null || oldIn === undefined || oldOut === null || oldOut === undefined || String(oldIn).replace(/\s/g, "") === "" || String(oldOut).replace(/\s/g, "") === "" || !isFinite(Number(oldIn)) || !isFinite(Number(oldOut))) throw new Error("Không lưu được In/Out ban đầu. Chưa thay đổi audio.");
        if (inputPlan) {
            journalPath = jobPath + ".audio-recovery.json";
            var record = { revision: 1, projectId: scan.projectId, sequenceId: String(seq.sequenceID), structure: $._PVS._captionOnlySnapshot(seq, true), snapshot: job.snapshot, inPoint: Number(oldIn), outPoint: Number(oldOut), tracks: [], clips: [] };
            for (ti = 0; ti < muteStates.length; ti++) record.tracks.push(muteStates[ti].muted);
            for (var cs = 0; cs < clipStates.length; cs++) if (clipStates[cs].target !== clipStates[cs].disabled) record.clips.push({ trackIndex: clipStates[cs].trackIndex, nodeId: String(clipStates[cs].clip.nodeId), disabled: clipStates[cs].disabled });
            $._PVS._writeCaptionAudioJournal(journalPath, record);
        }
        var index = 0, nextCall = 0, expectedSnapshot = null;
        var documentId = String(app.project.documentID || "");
        function checkRange() {
            var source = job.sources[index];
            var actualIn = Number(seq.getInPoint()), actualOut = Number(seq.getOutPoint());
            if (!isFinite(actualIn) || !isFinite(actualOut) || actualOut <= actualIn || Math.abs(actualIn - source.start) > frameSeconds + 0.000001 || Math.abs(actualOut - source.end) > frameSeconds + 0.000001) throw new Error("Premiere chưa nhận đúng In/Out của vùng subtitle. Đã dừng trước khi encoding.");
        }
        function prepareRange() {
            exportPhase = "range-setup";
            var source = job.sources[index];
            if ((new File(source.path)).exists) throw new Error("File audio tạm đã tồn tại; hãy chạy lại tác vụ.");
            seq.setInPoint(source.start);
            seq.setOutPoint(source.end);
            checkRange();
            verifyIsolation();
            expectedSnapshot = $._PVS._captionOnlySnapshot(seq);
        }
        function finish(error) {
            var finalizeStarted = (new Date()).getTime();
            var restorationErrors = [];
            for (var ci = 0; ci < clipStates.length; ci++) {
                try {
                    if (clipStates[ci].changed) clipStates[ci].clip.disabled = clipStates[ci].disabled;
                    if (clipStates[ci].clip.disabled !== clipStates[ci].disabled) throw new Error("enable chưa khôi phục đúng.");
                } catch (clipError) { restorationErrors.push("Không khôi phục được clip " + clipStates[ci].clip.nodeId + ": " + clipError.message); }
            }
            // Each restoration is independent, including when a native export
            // returns an error or a later host call detects an external edit.
            for (var ti = 0; ti < muteStates.length; ti++) {
                try {
                    if (muteStates[ti].changed) muteStates[ti].track.setMute(muteStates[ti].muted ? 1 : 0);
                    if (readMute(muteStates[ti].track) !== muteStates[ti].muted) throw new Error("Trạng thái mute chưa khôi phục đúng.");
                } catch (muteError) { restorationErrors.push("Không khôi phục được mute track A" + (ti + 1) + ": " + muteError.message); }
            }
            try { seq.setInPoint(Number(oldIn)); } catch (inError) { restorationErrors.push("Không khôi phục được In sequence: " + inError.message); }
            try { seq.setOutPoint(Number(oldOut)); } catch (outError) { restorationErrors.push("Không khôi phục được Out sequence: " + outError.message); }
            try {
                var restoredIn = Number(seq.getInPoint()), restoredOut = Number(seq.getOutPoint());
                if (!isFinite(restoredIn) || !isFinite(restoredOut) || Math.abs(restoredIn - Number(oldIn)) > 0.000001 || Math.abs(restoredOut - Number(oldOut)) > 0.000001) throw new Error("In/Out chưa khôi phục đúng.");
            } catch (restoreError) { restorationErrors.push(restoreError.message); }
            // Verify the full baseline even after native failure/cancellation.
            try { if (journalPath && $._PVS._captionOnlySnapshot(seq) !== job.snapshot) restorationErrors.push("Timeline không còn khớp trạng thái gốc. Giữ nhật ký khôi phục audio."); }
            catch (baselineError) { restorationErrors.push(String(baselineError)); }
            if (!restorationErrors.length && journalPath) {
                try { if (!(new File(journalPath)).remove()) throw new Error("Không xóa được nhật ký khôi phục audio."); }
                catch (journalError) { restorationErrors.push(journalError.message); }
            }
            if ($._PVS._captionAudioExport === session) $._PVS._captionAudioExport = null;
            if (restorationErrors.length) {
                exportPhase = "restore";
                error = new Error((error ? error.message + "\n" : "") + restorationErrors.join("\n") + "\nHãy kiểm tra mute và In/Out trước khi chạy lại.");
            }
            if (!error) {
                exportPhase = "snapshot";
                try { if ($._PVS._captionOnlySnapshot(seq) !== job.snapshot) throw new Error("Timeline đã thay đổi trong lúc xuất audio."); }
                catch (snapshotError) { error = snapshotError; }
            }
            session.finalizeMilliseconds = Math.max(0, (new Date()).getTime() - finalizeStarted);
            return error ? { ok: false, done: true, restored: restorationErrors.length === 0, error: String(error.message || error), exportFailurePhase: exportPhase } : { ok: true, done: true, restored: true, exportedRangeCount: index, voiceTrackIndex: voiceIndex, voiceTrackIndices: voiceIndices };
        }
        session = {
            token: token,
            finish: finish,
            advance: function (call) {
                session.nativeMilliseconds = null;
                session.finalizeMilliseconds = null;
                if (typeof call !== "number" || call !== nextCall) return { ok: false, done: false, error: "Sai thứ tự lượt xuất audio.", exportFailurePhase: "preflight" };
                nextCall++;
                try {
                    exportPhase = "between-calls";
                    if (!app.project || String(app.project.documentID || "") !== documentId) throw new Error("Project đã thay đổi trong lúc xuất audio.");
                    verifyIsolation();
                    if ($._PVS._captionOnlySnapshot(seq) !== expectedSnapshot) throw new Error("Timeline đã thay đổi giữa các lượt xuất audio.");
                    checkRange();
                    var output = new File(job.sources[index].path);
                    if (output.exists) throw new Error("File audio tạm đã tồn tại; hãy chạy lại tác vụ.");
                    exportPhase = "native-export";
                    // Begin/previous advance has already returned to Premiere.
                    // Do not mutate mute/In/Out immediately before this call.
                    var nativeStarted = (new Date()).getTime(), nativeResult;
                    try { nativeResult = seq.exportAsMediaDirect(output.fsName, (new File(presetPath)).fsName, 1); }
                    finally { session.nativeMilliseconds = Math.max(0, (new Date()).getTime() - nativeStarted); }
                    if (nativeResult === false || (typeof nativeResult === "number" && nativeResult < 0) || (typeof nativeResult === "string" && /^\s*(error\b|(export\s+)?fail(ed|ure)?\b|cancel(ed|led)?\b)/i.test(nativeResult))) throw new Error("Premiere báo lỗi/hủy xuất WAV: " + String(nativeResult));
                    verifyIsolation();
                    if ($._PVS._captionOnlySnapshot(seq) !== expectedSnapshot) throw new Error("Timeline đã thay đổi trong lúc xuất audio.");
                    exportPhase = "audio-file-check";
                    if (!output.exists || output.length <= 44) throw new Error("Premiere không xuất được audio WAV hoàn chỉnh.");
                    index++;
                    if (index === job.sources.length) return finish(null);
                    prepareRange();
                    return { ok: true, done: false, nextCall: nextCall, exportedRangeCount: index };
                } catch (error) { return finish(error); }
            }
        };
        // Register before mutating so even a partial preparation can restore.
        $._PVS._captionAudioExport = session;
        exportPhase = "isolation";
        for (ti = 0; ti < muteStates.length; ti++) {
            var targetMute = inputPlan && inputPlan.input.sourceMode === "mix" ? muteStates[ti].muted : !chosenTrack(ti);
            if (readMute(muteStates[ti].track) !== targetMute) {
                muteStates[ti].changed = true;
                muteStates[ti].track.setMute(targetMute ? 1 : 0);
            }
        }
        for (cs = 0; cs < clipStates.length; cs++) if (clipStates[cs].target !== clipStates[cs].disabled) { clipStates[cs].changed = true; clipStates[cs].clip.disabled = clipStates[cs].target; }
        verifyIsolation();
        prepareRange();
        return timedResult({ ok: true, done: false, nextCall: 0, rangeCount: job.sources.length });
    } catch (e) { return timedResult(session ? session.finish(e) : { ok: false, done: true, restored: !$._PVS._captionAudioExport, error: String(e.message || e), exportFailurePhase: exportPhase }); }
};
$._PVS.advanceCaptionAudioExport = function (token, call) {
    var hostStarted = (new Date()).getTime();
    var session = $._PVS._captionAudioExport;
    if (!session || session.token !== token) return $._PVS._result({ ok: false, done: false, error: "Không tìm thấy phiên xuất audio phù hợp.", exportFailurePhase: "between-calls" });
    var result = session.advance(call);
    result.audioExportTiming = { hostMilliseconds: Math.max(0, (new Date()).getTime() - hostStarted) };
    if (typeof session.nativeMilliseconds === "number") result.audioExportTiming.nativeMilliseconds = session.nativeMilliseconds;
    if (typeof session.finalizeMilliseconds === "number") result.audioExportTiming.finalizeMilliseconds = session.finalizeMilliseconds;
    return $._PVS._result(result);
};
$._PVS.abortCaptionAudioExport = function (token) {
    var session = $._PVS._captionAudioExport;
    if (!session || session.token !== token) return $._PVS._result({ ok: true, done: true, found: false });
    return $._PVS._result(session.finish(new Error("Đã dừng phiên xuất audio trước lượt kế tiếp.")));
};
$._PVS.restorePendingCaptionAudioExport = function (journalPath) {
    // Called only by the explicit recovery action after a panel reload. Host
    // calls are serial: this cannot run concurrently with native encoding.
    var session = $._PVS._captionAudioExport;
    if (!session) return $._PVS._result(journalPath ? $._PVS._restoreCaptionAudioJournal(journalPath) : { ok: true, done: true, found: false });
    return $._PVS._result(session.finish(new Error("Đã dừng phiên xuất audio cũ để kiểm tra đầu vào.")));
};

// Shared by Auto edit, every diagnostic profile, and standalone subtitles.
// Synchronous reconciliation of one marker owner. Compensation covers marker
// data only, never timeline edits, user Undo, Save, or a process crash.
$._PVS._markerTools = (function () {
    function read(collection) {
        var rows = [], marker = collection.getFirstMarker();
        while (marker) {
            var seconds = Number(marker.start.seconds), end = null, color = null;
            if (!isFinite(seconds)) throw new Error("Unreadable marker position.");
            if (marker.end !== undefined) {
                end = Number(typeof marker.end === "number" ? marker.end : marker.end.seconds);
                if (!isFinite(end)) throw new Error("Unreadable marker end.");
            }
            try { if (typeof marker.getColorByIndex === "function") color = Number(marker.getColorByIndex()); } catch (ignoreColor) {}
            if (color === null || !isFinite(color)) color = null;
            rows.push({ ref: marker, guid: String(marker.guid || ""), seconds: seconds, end: end,
                name: String(marker.name || ""), comments: String(marker.comments || ""),
                type: String(marker.type || "Comment"), color: color });
            marker = collection.getNextMarker(marker);
        }
        return rows;
    }
    function fingerprint(rows, identity) {
        var values = [];
        for (var i = 0; i < rows.length; i++) {
            var r = rows[i];
            values.push(JSON.stringify([identity ? r.guid : "", r.seconds, r.end, r.name, r.comments, r.type, r.color]));
        }
        return values.sort().join("\n");
    }
    function inScope(group, seconds) {
        for (var i = 0; i < group.ranges.length; i++) if (seconds >= group.ranges[i].start && seconds < group.ranges[i].end) return true;
        return false;
    }
    function owned(group, row) { return row.type === "Comment" && group.owns(row) && inScope(group, row.seconds); }
    function index(rows, tolerance) {
        var buckets = {};
        for (var i = 0; i < rows.length; i++) {
            var key = "p" + Math.floor(rows[i].seconds / tolerance);
            if (!buckets[key]) buckets[key] = [];
            buckets[key].push(rows[i]);
        }
        return buckets;
    }
    function near(buckets, seconds, tolerance) {
        var result = [], base = Math.floor(seconds / tolerance);
        for (var b = base - 1; b <= base + 1; b++) {
            var values = buckets["p" + b] || [];
            for (var i = 0; i < values.length; i++) if (Math.abs(values[i].seconds - seconds) < tolerance) result.push(values[i]);
        }
        return result;
    }
    function group(collection, ranges, owns, tolerance) {
        if (!collection || typeof collection.createMarker !== "function" || typeof collection.deleteMarker !== "function") throw new Error("Marker API unavailable.");
        if (!ranges || !ranges.length || !isFinite(tolerance) || tolerance <= 0) throw new Error("Marker scope missing.");
        for (var i = 0; i < ranges.length; i++) if (!isFinite(ranges[i].start) || !isFinite(ranges[i].end) || ranges[i].start < 0 || ranges[i].end <= ranges[i].start) throw new Error("Invalid marker scope.");
        var rows = read(collection);
        return { collection: collection, ranges: ranges, owns: owns, tolerance: tolerance, before: rows,
            positions: index(rows, tolerance), reserved: {}, desired: [], blocked: false };
    }
    function available(g, seconds) {
        if (!inScope(g, seconds) || near(g.reserved, seconds, g.tolerance).length) return false;
        var rows = near(g.positions, seconds, g.tolerance), count = 0;
        for (var i = 0; i < rows.length; i++) { if (!owned(g, rows[i])) return false; count++; }
        return count <= 1;
    }
    function add(g, spec) {
        if (typeof spec.name !== "string" || typeof spec.comments !== "string" || !owned(g, { seconds: spec.seconds, name: spec.name, comments: spec.comments, type: "Comment" }) || !isFinite(spec.color) || Math.floor(spec.color) !== spec.color || spec.color < 0 || spec.color > 7) throw new Error("Invalid owned marker request.");
        if (!isFinite(spec.seconds) || !available(g, spec.seconds)) throw new Error("Marker position occupied or outside scope.");
        g.desired.push(spec);
        var key = "p" + Math.floor(spec.seconds / g.tolerance);
        if (!g.reserved[key]) g.reserved[key] = [];
        g.reserved[key].push(spec);
    }
    function same(a, b) { return a.ref === b.ref || (a.guid && a.guid === b.guid); }
    function find(rows, row) {
        for (var i = 0; i < rows.length; i++) if (same(rows[i], row)) return rows[i];
        return null;
    }
    function commit(g, touch) {
        var result = { count: 0, deleted: 0, merged: 0, colorFailures: [], failures: [] };
        var changed = [], created = [], removed = [], before, kept = [], wanted = [], mutationAttempted = false;
        if (g.blocked) { result.failures.push("Marker group has an invalid request; old markers retained."); return result; }
        function mutate() { mutationAttempted = true; if (touch) touch(); }
        function writeColor(marker, color, previous) {
            try {
                if (previous && previous.color === null) throw new Error("Cannot snapshot old marker color; color left unchanged.");
                if (previous && previous.color === color) return;
                marker.setColorByIndex(color);
                if (typeof marker.getColorByIndex === "function" && Number(marker.getColorByIndex()) !== color) throw new Error("Marker color verification failed.");
            } catch (e) { result.colorFailures.push(e.message || String(e)); }
        }
        function create(seconds, originalRows, journal) {
            mutate();
            var marker;
            try { marker = g.collection.createMarker(seconds); }
            catch (nativeError) {
                // Native APIs can mutate and then throw. Recover a single new,
                // blank comment marker only when its provenance is unambiguous.
                var rows = read(g.collection), additions = [];
                for (var n = 0; n < rows.length; n++) if (!find(originalRows, rows[n]) && !find(journal, rows[n])) additions.push(rows[n]);
                if (additions.length === 1 && !additions[0].name && !additions[0].comments && additions[0].type === "Comment") journal.push(additions[0]);
                throw nativeError;
            }
            if (!marker) throw new Error("Premiere could not create marker.");
            var row = { ref: marker, guid: String(marker.guid || "") };
            if (find(originalRows, row) || String(marker.name || "") || String(marker.comments || "")) throw new Error("Premiere returned an existing marker; left untouched.");
            journal.push(row);
            return marker;
        }
        try {
            before = read(g.collection);
            if (fingerprint(before, true) !== fingerprint(g.before, true)) throw new Error("Marker collection changed since preparation; inspect before retry.");
            var positions = index(before, g.tolerance);
            for (var i = 0; i < g.desired.length; i++) {
                var spec = g.desired[i], matches = near(positions, spec.seconds, g.tolerance), old = matches.length ? matches[0] : null;
                var marker = old ? old.ref : null;
                if (old && (!owned(g, old) || matches.length !== 1)) throw new Error("Marker ownership changed.");
                if (!marker) marker = create(spec.seconds, before, created);
                else if (old.name !== spec.name || old.comments !== spec.comments || old.color !== spec.color) { changed.push(old); mutate(); }
                if (!old || old.name !== spec.name) marker.name = spec.name;
                if (!old || old.comments !== spec.comments) marker.comments = spec.comments;
                writeColor(marker, spec.color, old);
                kept.push({ ref: marker, guid: String(marker.guid || "") });
                wanted.push(spec);
            }
            // Read back all replacements BEFORE the first obsolete marker goes.
            var after = read(g.collection);
            for (var v = 0; v < kept.length; v++) {
                var actual = find(after, kept[v]), target = wanted[v];
                if (!actual || actual.name !== target.name || actual.comments !== target.comments || !owned(g, actual) || (target.verify ? !target.verify(actual.seconds) : Math.abs(actual.seconds - target.seconds) > g.tolerance / 2)) throw new Error("Marker position/notes verification failed.");
            }
            var expectedRows = after.slice(0);
            for (var o = 0; o < before.length; o++) if (owned(g, before[o]) && !find(kept, before[o])) {
                // Verify the entire resulting collection as well as identity:
                // some hosts expose fresh proxies on each enumeration.
                var found = false, staleState = fingerprint([before[o]], false);
                for (var er = 0; er < expectedRows.length; er++) if (fingerprint([expectedRows[er]], false) === staleState) { expectedRows.splice(er, 1); found = true; break; }
                if (!found) throw new Error("Obsolete marker changed before cleanup.");
                removed.push(before[o]); mutate(); g.collection.deleteMarker(before[o].ref);
            }
            after = read(g.collection);
            for (var d = 0; d < removed.length; d++) if (find(after, removed[d])) throw new Error("Marker deletion verification failed.");
            if (fingerprint(after, false) !== fingerprint(expectedRows, false)) throw new Error("Marker deletion verification failed: collection differs.");
            result.count = kept.length; result.deleted = removed.length;
            for (var m = 0; m < wanted.length; m++) if (wanted[m].merged) result.merged++;
        } catch (e) {
            result.failures.push(e.message || String(e));
            // A preparation conflict has made no mutations. Do not overwrite it.
            if (!mutationAttempted) return result;
            for (var c = created.length - 1; c >= 0; c--) {
                try { g.collection.deleteMarker(created[c].ref); } catch (deleteError) { result.failures.push("Marker restoration: " + deleteError.message); }
            }
            for (var u = changed.length - 1; u >= 0; u--) {
                try {
                    var saved = changed[u];
                    saved.ref.name = saved.name; saved.ref.comments = saved.comments;
                    if (saved.color !== null && Number(saved.ref.getColorByIndex()) !== saved.color) saved.ref.setColorByIndex(saved.color);
                } catch (updateError) { result.failures.push("Marker restoration: " + updateError.message); }
            }
            for (var r = 0; r < removed.length; r++) {
                try {
                    var currentRows = read(g.collection), prior = removed[r];
                    if (find(currentRows, prior)) continue;
                    var restored = create(prior.seconds, currentRows, []);
                    restored.name = prior.name; restored.comments = prior.comments;
                    if (prior.end !== null) restored.end = prior.end;
                    if (prior.color !== null) restored.setColorByIndex(prior.color);
                } catch (restoreError) { result.failures.push("Marker restoration: " + restoreError.message); }
            }
            try {
                if (fingerprint(read(g.collection), false) !== fingerprint(g.before, false)) result.failures.push("Marker restoration incomplete; inspect markers before retry.");
            } catch (readError) { result.failures.push("Marker restoration could not be verified: " + readError.message); }
        }
        return result;
    }
    return { group: group, available: available, add: add, commit: commit };
}());

// Sequence markers use final timeline seconds and never modify clip media.
$._PVS._applyReviewMarkers = function (seq, issues, ranges, workflow) {
    var stats = { reviewMarkerCount: 0, reviewMarkerFailureCount: 0, reviewMarkerFailures: [], reviewMarkerColorFailureCount: 0 };
    if (issues === undefined) return stats; // Older plans have no review contract.
    var tag = "[PremiereVoiceSync:review-marker:v1:" + workflow + "]";
    var name = "VOICE SYNC - Can kiem tra";
    var fps = 254016000000 / Number(seq.timebase);
    var groups = [];
    function owned(m) { return String(m.name || "") === name && String(m.comments || "").indexOf(tag) >= 0; }
    function inScope(seconds) {
        for (var r = 0; r < ranges.length; r++) if (seconds >= Number(ranges[r].start) && seconds < Number(ranges[r].end)) return true;
        return false;
    }
    function failure(message) { stats.reviewMarkerFailures.push(String(message)); stats.reviewMarkerFailureCount++; }
    try {
        if (!isFinite(fps) || fps <= 0 || !ranges || !ranges.length) throw new Error("Review marker scope/frame rate missing.");
        // Preflight all coordinates before touching any marker.
        for (var i = 0; i < issues.length; i++) {
            var issue = issues[i], start = Number(issue.start), end = Number(issue.end);
            if (issue.start === null || issue.end === null || !isFinite(start) || !isFinite(end) || start < 0 || end <= start || !inScope(start) || !inScope(Math.max(start, end - 0.000001))) throw new Error("Invalid review marker range: " + i);
            var frame = Math.round(start * fps), group = null;
            for (var g = 0; g < groups.length; g++) if (groups[g].frame === frame) { group = groups[g]; break; }
            if (!group) { group = { frame: frame, end: end, notes: [], error: false }; groups.push(group); }
            group.end = Math.max(group.end, end);
            var noteLabel = issue.captionIndex ? "Caption " + issue.captionIndex + (issue.referenceCueIndex ? " (SRT " + issue.referenceCueIndex + ")" : "") + ": " : (issue.cueIndex ? "Đoạn phân tích " + issue.cueIndex + ": " : "");
            var note = noteLabel + String(issue.reason || "Can kiem tra") + " [" + start.toFixed(3) + " - " + end.toFixed(3) + "s]";
            var duplicate = false;
            for (var n = 0; n < group.notes.length; n++) if (group.notes[n] === note) duplicate = true;
            if (!duplicate) group.notes.push(note);
            if (issue.severity === "error") group.error = true;
        }
        var markers = seq.markers;
        if (!markers || typeof markers.createMarker !== "function") {
            if (!issues.length) return stats;
            throw new Error("Premiere does not expose sequence markers.");
        }
        var scope = [];
        for (var sr = 0; sr < ranges.length; sr++) scope.push({ start: Number(ranges[sr].start), end: Number(ranges[sr].end) });
        var group = $._PVS._markerTools.group(markers, scope, owned, 0.5 / fps);
        for (var j = 0; j < groups.length; j++) {
            var target = groups[j], candidate = target.frame, last = Math.ceil(target.end * fps - 0.0000001) - 1;
            // Plan all collisions before changing the first marker.
            for (; candidate <= last; candidate++) if ($._PVS._markerTools.available(group, candidate / fps)) break;
            if (candidate > last) throw new Error("No free frame inside review interval.");
            $._PVS._markerTools.add(group, { seconds: candidate / fps, name: name,
                comments: target.notes.join("\n") + "\n" + tag, color: target.error ? 1 : 4 });
        }
        var result = $._PVS._markerTools.commit(group);
        stats.reviewMarkerCount = result.count;
        stats.reviewMarkerColorFailureCount = result.colorFailures.length;
        for (var f = 0; f < result.failures.length; f++) failure(result.failures[f]);
    } catch (e) { failure(e.message || e); }
    return stats;
};

$._PVS.applyCaptionOnly = function (resultPath) {
    var captionCreated = false;
    var cleanupComplete = false;
    var captionBin = null;
    var seq = null;
    var markerStats = null;
    function withMarkers(value) {
        if (markerStats) for (var key in markerStats) if (markerStats.hasOwnProperty(key)) value[key] = markerStats[key];
        return $._PVS._result(value);
    }
    try {
        var result = $._PVS._readJsonFile(resultPath);
        seq = app.project && app.project.activeSequence;
        if (!result.ok || result.workflow !== "caption-only" || Number(result.schemaVersion) !== 1) throw new Error("Kết quả subtitle không hợp lệ.");
        if (!seq || String(seq.sequenceID) !== String(result.sequenceId) || $._PVS._captionOnlySnapshot(seq) !== result.snapshot) throw new Error("Timeline đã thay đổi trong lúc nhận diện. Hãy chạy lại chức năng subtitle.");
        if (!(new File(result.captionSrtPath)).exists) throw new Error("Không tìm thấy subtitle đã tạo.");
        function countTemporarySrt(root) {
            var count = 0;
            try { if (root.getMediaPath && String(root.getMediaPath() || "").toLowerCase() === String(result.captionSrtPath).toLowerCase()) count++; } catch (ignorePath) {}
            if (root.children) for (var childIndex = 0; childIndex < root.children.numItems; childIndex++) count += countTemporarySrt(root.children[childIndex]);
            return count;
        }
        var srtItemCountBefore = countTemporarySrt(app.project.rootItem);
        captionBin = app.project.rootItem.createBin("PVS_TEMP_SUBTITLE_" + String((new Date()).getTime()));
        if (!captionBin) throw new Error("Không tạo được bin subtitle tạm.");
        var binNodeId = String(captionBin.nodeId);
        function containsBin(root) {
            if (String(root.nodeId) === binNodeId) return true;
            if (root.children) for (var childIndex = 0; childIndex < root.children.numItems; childIndex++) if (containsBin(root.children[childIndex])) return true;
            return false;
        }
        try {
            if (!app.project.importFiles([result.captionSrtPath], true, captionBin, false)) throw new Error("Không import được subtitle tạm.");
            var item = $._PVS._findItemByMediaPath(captionBin, result.captionSrtPath);
            if (!item) throw new Error("Không tìm thấy subtitle sau khi import.");
            captionCreated = !!seq.createCaptionTrack(item, 0, Sequence.CAPTION_FORMAT_SUBTITLE);
            if (!captionCreated) throw new Error("Premiere không tạo được Caption Track.");
            markerStats = $._PVS._applyReviewMarkers(seq, result.reviewMarkers, result.reviewMarkerRanges, "captions");
        } finally {
            captionBin.deleteBin();
            for (var probe = 0; probe < 6; probe++) {
                if (!containsBin(app.project.rootItem) && countTemporarySrt(app.project.rootItem) === srtItemCountBefore) { cleanupComplete = true; break; }
                if (probe < 5) $.sleep(50);
            }
        }
        if (!cleanupComplete) throw new Error("Caption đã tạo nhưng bin tạm chưa dọn được; hãy xóa bin PVS_TEMP_SUBTITLE trong Project.");
        if ($._PVS._captionOnlySnapshot(seq) !== result.snapshot) throw new Error("Hậu kiểm phát hiện video/audio thay đổi trong lúc tạo caption.");
        if (markerStats.reviewMarkerFailureCount) throw new Error("Caption đã tạo nhưng có mốc chưa gắn được marker: " + markerStats.reviewMarkerFailures.join("; "));
        return withMarkers({ ok: true, captionCreated: true, captionCueCount: result.captionCueCount, mediaUnchanged: true, temporaryBinRemoved: true });
    } catch (e) {
        return withMarkers({ ok: false, error: e.message || String(e), captionCreated: captionCreated, temporaryBinRemoved: cleanupComplete });
    }
};

$._PVS._timecodeFromSeconds = function (seconds, fps) {
    var negative = seconds < 0;
    var frames = Math.round(Math.abs(seconds) * fps);
    var ff = frames % Math.round(fps);
    var totalSeconds = Math.floor(frames / Math.round(fps));
    var ss = totalSeconds % 60;
    var totalMinutes = Math.floor(totalSeconds / 60);
    var mm = totalMinutes % 60;
    var hh = Math.floor(totalMinutes / 60);
    function pad(value) { return value < 10 ? "0" + value : String(value); }
    return (negative ? "-" : "") + pad(hh) + ":" + pad(mm) + ":" + pad(ss) + ":" + pad(ff);
};

$._PVS._findQEClipAtTicks = function (track, ticks, tolerance) {
    var best = null;
    var bestDistance = Number.MAX_VALUE;
    for (var i = 0; i < track.numItems; i++) {
        var item = track.getItemAt(i);
        try {
            if (item.type !== "Clip") continue;
            var distance = Math.abs(Number(item.start.ticks) - Number(ticks));
            if (distance < bestDistance) { best = item; bestDistance = distance; }
        } catch (ignore) {}
    }
    return bestDistance <= tolerance ? best : null;
};

$._PVS.executePlan = function (planPath) {
    var original = null;
    var workingSequence = null;
    var cleanupError = "";
    var report = { ok: false };
    var speedNonConvergenceCount = 0;
    var speedCorrectionCount = 0;
    var terminalEndFallbackCount = 0;
    var maxSpeedDurationErrorBeforeCorrectionFrames = 0;
    var maxSpeedDurationErrorAfterCorrectionFrames = 0;
    var speedConvergenceFailures = [];
    var timelineMutated = false;
    var clearedClipMarkerCount = 0;
    var markerColorFailures = [];
    var reviewMarkerStats = { reviewMarkerCount: 0, reviewMarkerFailureCount: 0, reviewMarkerFailures: [], reviewMarkerColorFailureCount: 0 };
    var pendingNativeReview = null;
    var nativeProgressSerial = 0;
    function noteNative(phase, operation) {
        var file = null;
        try {
            var source = new File(planPath);
            var progressPath = plan && plan.nativeProgressPath ? plan.nativeProgressPath : source.name === "timeline-executor.json" ? source.parent.fsName + "/native-progress.jsonl" : "";
            if (!progressPath) return;
            file = new File(progressPath);
            if (!file.exists || file.name !== "native-progress.jsonl" || String(file.parent.fsName).toLowerCase() !== String(source.parent.fsName).toLowerCase()) return;
            file.encoding = "UTF-8";
            if (!file.open("a")) return;
            file.write(JSON.stringify({serial:++nativeProgressSerial,phase:phase,operation:operation,at:(new Date()).getTime()}) + "\n");
        } catch (ignoreProgressWrite) {} finally { if (file) try { file.close(); } catch (ignoreProgressClose) {} }
    }
    function asArray(value) { return value instanceof Array ? value : (value ? [value] : []); }
    function findLinkedTrack(sequence, spec, mainEnd) {
        for (var ti = 0; ti < sequence.audioTracks.numTracks; ti++) {
            var track = sequence.audioTracks[ti];
            for (var ci = 0; ci < track.clips.numItems; ci++) {
                var clip = track.clips[ci];
                if (String(clip.name) === String(spec.name) && Math.abs(Number(clip.start.seconds)) < 0.05 && Math.abs(Number(clip.end.seconds) - mainEnd) < 0.1) return ti;
            }
        }
        return -1;
    }
    function preservedSignatures(sequence, linkedTrackIndex, voiceTrackIndex, mainName, linkedName, voiceNames) {
        var values = [];
        function add(kind, trackIndex, clip) {
            values.push(kind + trackIndex + "|" + clip.name + "|" + Math.round(Number(clip.start.seconds) * 1000) + "|" + Math.round(Number(clip.end.seconds) * 1000));
        }
        for (var vt = 0; vt < sequence.videoTracks.numTracks; vt++) {
            var videoTrack = sequence.videoTracks[vt];
            for (var vc = 0; vc < videoTrack.clips.numItems; vc++) {
                var videoClip = videoTrack.clips[vc];
                if (vt > 0 || String(videoClip.name) !== String(mainName)) add("V", vt, videoClip);
            }
        }
        for (var at = 0; at < sequence.audioTracks.numTracks; at++) {
            var audioTrack = sequence.audioTracks[at];
            for (var ac = 0; ac < audioTrack.clips.numItems; ac++) {
                var audioClip = audioTrack.clips[ac];
                if (at === linkedTrackIndex) {
                    if (String(audioClip.name) !== String(linkedName)) add("A", at, audioClip);
                } else if (at === voiceTrackIndex) {
                    if (!voiceNames[String(audioClip.name)]) add("A", at, audioClip);
                } else add("A", at, audioClip);
            }
        }
        values.sort();
        return values;
    }
    function sameSignatures(a, b) {
        if (a.length !== b.length) return false;
        for (var i = 0; i < a.length; i++) if (a[i] !== b[i]) return false;
        return true;
    }
    function setClipSpeed(item, qeTrack, factor, desiredFrames, fps, tolerance, label, allowTerminalEndFallback) {
        pendingNativeReview = { start: Number(item.start.seconds), end: Number(item.end.seconds), reason: "Native retime failed: " + label, severity: "error" };
        var destinationSeconds = desiredFrames / fps;
        var durationTimecode = $._PVS._timecodeFromSeconds(destinationSeconds, fps);
        var savedSourceTicks = Number(item.outPoint.ticks) - Number(item.inPoint.ticks);
        var exactFactor = savedSourceTicks > 0 && desiredFrames > 0 ? savedSourceTicks / (desiredFrames * ticksPerFrame) : Number(factor);
        var appliedFactor = isFinite(exactFactor) && exactFactor > 0 ? exactFactor : Number(factor);
        noteNative("before", "qe-lookup");
        var qeItem = $._PVS._findQEClipAtTicks(qeTrack, item.start.ticks, tolerance);
        noteNative("after", "qe-lookup");
        if (!qeItem) throw new Error("Could not map QE item at " + item.start.seconds + ".");
        timelineMutated = true;
        // One exact rational retime preserves the complete source interval.
        // Repeated corrections can converge the visible duration by silently
        // changing outPoint, which trims a few source frames from every cut.
        noteNative("before", "set-speed");
        if (!qeItem.setSpeed(appliedFactor, durationTimecode, false, false, false)) throw new Error("setSpeed failed at " + item.start.seconds + ".");
        noteNative("after", "set-speed");
        var actualFrames = Math.round((Number(item.end.ticks) - Number(item.start.ticks)) / ticksPerFrame);
        var firstError = Math.abs(actualFrames - desiredFrames);
        maxSpeedDurationErrorBeforeCorrectionFrames = Math.max(maxSpeedDurationErrorBeforeCorrectionFrames, firstError);
        // Premiere 26.2.2 keeps the old visible duration for a slowed clip
        // that touches the nested source tail. The supported TrackItem.end
        // setter was verified to update both standard and QE edges. Use it
        // only for this terminal mismatch; never rewrite outPoint.
        if (firstError !== 0 && allowTerminalEndFallback) {
            var forcedEnd = new Time();
            forcedEnd.ticks = String(Math.round(Number(item.start.ticks) + desiredFrames * ticksPerFrame));
            try {
                item.end = forcedEnd;
            } catch (terminalEndError) {
                throw new Error("Terminal duration fallback failed for " + label + ": " + terminalEndError.message);
            }
            actualFrames = Math.round((Number(item.end.ticks) - Number(item.start.ticks)) / ticksPerFrame);
            speedCorrectionCount++;
            terminalEndFallbackCount++;
        }
        var finalError = Math.abs(actualFrames - desiredFrames);
        maxSpeedDurationErrorAfterCorrectionFrames = Math.max(maxSpeedDurationErrorAfterCorrectionFrames, finalError);
        if (finalError !== 0) {
            speedNonConvergenceCount++;
            speedConvergenceFailures.push({
                label: label,
                startFrame: Math.round(Number(item.start.ticks) / ticksPerFrame),
                desiredFrames: desiredFrames,
                actualFrames: actualFrames,
                finalSpeedPercent: appliedFactor * 100
            });
        }
        pendingNativeReview = null;
        return appliedFactor;
    }
    function readSpeedPercent(item) {
        try {
            if (!item || typeof item.getSpeed !== "function") return null;
            var raw = Number(item.getSpeed());
            if (!isFinite(raw) || raw <= 0) return null;
            return raw <= 10 ? raw * 100 : raw;
        } catch (ignoreSpeedRead) { return null; }
    }
    function projectItemKey(trackItem) {
        var projectItem = trackItem && trackItem.projectItem;
        if (!projectItem) return "";
        try { if (projectItem.nodeId !== undefined && projectItem.nodeId !== null && String(projectItem.nodeId)) return "node:" + String(projectItem.nodeId); } catch (ignoreNodeId) {}
        try { if (projectItem.treePath) return "path:" + String(projectItem.treePath); } catch (ignoreTreePath) {}
        return ""; // A display name is not a durable source identity.
    }
    function isOwnedClipMarker(marker) {
        var name = String(marker.name || ""), comments = String(marker.comments || "");
        if (name.indexOf("VOICE SYNC -") !== 0) return false;
        if (comments.indexOf("[PremiereVoiceSync:owned-marker:v1]") >= 0) return true;
        if (name === "VOICE SYNC - Kiem tra toc do") return /^Sentence cues \d+-\d+: actual speed=[0-9.]+%, warning range=/.test(comments);
        if (name === "VOICE SYNC - Kiem tra can voice") return /^Sentence cues \d+-\d+ /.test(comments);
        return false;
    }
    function prepareClipMarkerGroup(owner, markerGroups, fps) {
        var key = projectItemKey(owner.Item);
        if (!key || markerGroups[key]) throw new Error("Ambiguous clip marker source.");
        owner.ProjectItem = owner.Item.projectItem;
        owner.Group = $._PVS._markerTools.group(owner.ProjectItem.getMarkers(), owner.Ranges, isOwnedClipMarker, 0.25 / fps);
        markerGroups[key] = owner.Group;
    }
    function blockClipMarkerGroup(item, markerGroups) {
        var key = projectItemKey(item);
        if (key && markerGroups[key]) markerGroups[key].blocked = true;
        else for (var k in markerGroups) if (markerGroups.hasOwnProperty(k)) markerGroups[k].blocked = true;
    }
    function markerCleanupOwners(sequence, main, linkedTrack, linkedName, voiceTrack, voiceSpecs) {
        var owners = [], byKey = {};
        function add(item) {
            var key = projectItemKey(item), sourceStart = Number(item.inPoint.seconds), sourceEnd = Number(item.outPoint.seconds);
            if (!key || !isFinite(sourceStart) || !isFinite(sourceEnd) || sourceEnd <= sourceStart) throw new Error("Invalid owned source range for marker cleanup.");
            if (!byKey[key]) { byKey[key] = { Item: item, NodeId: String(item.nodeId), Ranges: [] }; owners.push(byKey[key]); }
            byKey[key].Ranges.push({ start: sourceStart, end: sourceEnd });
        }
        add(main);
        var linkedClips = sequence.audioTracks[linkedTrack].clips, linkedFound = false;
        for (var ai = 0; ai < linkedClips.numItems; ai++) {
            var linked = linkedClips[ai];
            if (String(linked.name) === String(linkedName) && Math.abs(Number(linked.start.seconds)) < 0.05 && Math.abs(Number(linked.end.seconds) - Number(main.end.seconds)) < 0.1) { add(linked); linkedFound = true; break; }
        }
        if (!linkedFound) throw new Error("Could not map original audio for marker cleanup.");
        var voiceClips = sequence.audioTracks[voiceTrack].clips;
        for (var vi = 0; vi < voiceSpecs.length; vi++) {
            var spec = voiceSpecs[vi], found = false;
            for (var ci = 0; ci < voiceClips.numItems; ci++) {
                var voice = voiceClips[ci];
                var matches = spec.nodeId !== undefined ? String(voice.nodeId) === String(spec.nodeId) :
                    String(voice.name) === String(spec.name) && Math.abs(Number(voice.start.seconds) - Number(spec.start || 0)) < 0.05 && Math.abs(Number(voice.end.seconds) - Number(spec.end)) < 0.1;
                if (matches) { add(voice); found = true; break; }
            }
            if (!found) throw new Error("Could not map voice chapter for marker cleanup: " + (vi + 1));
        }
        return owners;
    }
    function planOwnedClipMarker(trackItem, spec, fps, markerGroups, plannedRange) {
        // Collect requests only. The complete source group is committed later.
        var group = markerGroups[projectItemKey(trackItem)];
        if (!group) throw new Error("Clip marker source was not prepared.");
        var actualTimelineStartFrame = Math.round(Number(trackItem.start.seconds) * fps);
        var actualTimelineEndFrame = Math.round(Number(trackItem.end.seconds) * fps);
        var sourceStartFrame;
        var sourceEndFrame;
        var outputStartFrame;
        var outputEndFrame;
        if (plannedRange) {
            sourceStartFrame = Number(plannedRange.sourceStartFrame);
            sourceEndFrame = Number(plannedRange.sourceEndFrame);
            outputStartFrame = Number(plannedRange.outputStartFrame);
            outputEndFrame = Number(plannedRange.outputEndFrame);
        } else {
            sourceStartFrame = Number(trackItem.inPoint.seconds) * fps;
            sourceEndFrame = Number(trackItem.outPoint.seconds) * fps;
            outputStartFrame = actualTimelineStartFrame;
            outputEndFrame = actualTimelineEndFrame;
        }
        if (!isFinite(sourceStartFrame) || !isFinite(sourceEndFrame) || sourceEndFrame <= sourceStartFrame) {
            throw new Error("Invalid source range for clip marker on '" + trackItem.name + "'.");
        }
        if (!isFinite(outputStartFrame) || !isFinite(outputEndFrame) || outputEndFrame <= outputStartFrame) {
            throw new Error("Invalid output range for clip marker on '" + trackItem.name + "'.");
        }
        var sourceDurationFrames = sourceEndFrame - sourceStartFrame;
        var candidateFractions = [0.5, 0.4, 0.6, 0.3, 0.7, 0.25, 0.75, 0.2, 0.8];
        // Premiere marker palette: 1 red, 3 orange, 4 yellow, 6 blue.
        // Color is informational; ownership is determined by provenance only.
        var markerColorIndex = spec.Owner === "A2" ? 4 : Number(spec.ColorIndex === undefined ? 1 : spec.ColorIndex);
        if (!isFinite(markerColorIndex) || markerColorIndex < 0 || markerColorIndex > 7 || Math.floor(markerColorIndex) !== markerColorIndex) markerColorIndex = 1;
        var sourceInteriorToleranceFrames = Math.min(0.01, sourceDurationFrames / 100);
        function verifyPosition(seconds) {
            var actualSourceFrame = seconds * fps;
            var sourceInsideTarget = isFinite(actualSourceFrame) &&
                actualSourceFrame > sourceStartFrame + sourceInteriorToleranceFrames &&
                actualSourceFrame < sourceEndFrame - sourceInteriorToleranceFrames;
            var sourceProgress = (actualSourceFrame - sourceStartFrame) / sourceDurationFrames;
            var projectedTimelineFrame = Math.round(outputStartFrame + sourceProgress * (outputEndFrame - outputStartFrame));
            var projectedInsideActualClip = projectedTimelineFrame > actualTimelineStartFrame && projectedTimelineFrame < actualTimelineEndFrame;
            return sourceInsideTarget && projectedInsideActualClip;
        }
        var markerName = String(spec.Name), markerComments = String(spec.Comments || "") + "\n[PremiereVoiceSync:owned-marker:v1]";
        var requestKey = "r" + JSON.stringify([sourceStartFrame, sourceEndFrame, markerName, markerComments, markerColorIndex, !!spec.Merged]);
        if (!group.requests) group.requests = {};
        if (group.requests[requestKey] !== undefined) {
            if (!verifyPosition(group.requests[requestKey])) throw new Error("Shared source marker cannot map to this clip.");
            return; // Repeated uses of one source warning share one clip marker.
        }
        var candidateSourceFrame = null;
        // Retain a valid existing warning even if Premiere quantized its source
        // timestamp. Clip geometry, rather than timeline FPS, defines validity.
        for (var existingIndex = 0; existingIndex < group.before.length; existingIndex++) {
            var existing = group.before[existingIndex];
            if (existing.name === markerName && existing.comments === markerComments && verifyPosition(existing.seconds) && $._PVS._markerTools.available(group, existing.seconds)) { candidateSourceFrame = existing.seconds * fps; break; }
        }
        for (var attempt = 0; candidateSourceFrame === null && attempt < candidateFractions.length; attempt++) {
            var proposedSourceFrame = sourceStartFrame + sourceDurationFrames * candidateFractions[attempt];
            if ($._PVS._markerTools.available(group, proposedSourceFrame / fps)) { candidateSourceFrame = proposedSourceFrame; break; }
        }
        if (candidateSourceFrame === null) throw new Error("No free source position for clip marker on '" + trackItem.name + "'.");
        if (!verifyPosition(candidateSourceFrame / fps)) throw new Error("Clip marker outside the planned source segment.");
        $._PVS._markerTools.add(group, { seconds: candidateSourceFrame / fps, name: markerName,
            comments: markerComments, color: markerColorIndex, verify: verifyPosition, merged: !!spec.Merged });
        group.requests[requestKey] = candidateSourceFrame / fps;
    }
    try {
        noteNative("before", "read-plan");
        var plan = $._PVS._readJsonFile(planPath);
        noteNative("after", "read-plan");
        if (Number(plan.schemaVersion) !== 8) throw new Error("Unsupported plan schema; expected 8.");
        noteNative("before", "validate-plan");
        var visualPlans = $._PVS._speedMergeVisualPlans(plan);
        noteNative("after", "validate-plan");
        var executorSettings = plan.settings || {};
        var voiceMappingToleranceFrames = Number(executorSettings.voiceMappingToleranceFrames === undefined ? 2 : executorSettings.voiceMappingToleranceFrames);
        var validationToleranceFrames = Number(executorSettings.validationToleranceFrames === undefined ? 1 : executorSettings.validationToleranceFrames);
        var maxCoverageGapFramesAllowed = Number(executorSettings.maxCoverageGapFrames === undefined ? 0 : executorSettings.maxCoverageGapFrames);
        var reconcileToleranceFrames = 1; // Internal edit rule; never controlled by postcheck tolerance.
        original = app.project && app.project.activeSequence;
        if (!original) throw new Error("No active sequence.");
        if (String(original.sequenceID) !== String(plan.sequenceId)) throw new Error("Active sequence ID does not match direct plan.");
        var originalId = original.sequenceID;
        var fps = Number(plan.frameRate || 30);
        var ticksPerFrame = 254016000000 / fps;
        function frameOf(timeValue) { return Math.round(Number(timeValue.ticks) / ticksPerFrame); }
        function durationFramesOf(item) { return Math.round((Number(item.end.ticks) - Number(item.start.ticks)) / ticksPerFrame); }
        function moveItemToFrame(item, destinationFrame) {
            var deltaTicks = destinationFrame * ticksPerFrame - Number(item.start.ticks);
            if (Math.abs(deltaTicks) < ticksPerFrame * 0.25) return false;
            var delta = new Time();
            delta.ticks = String(Math.round(deltaTicks));
            timelineMutated = true;
            pendingNativeReview = { start: Number(item.start.seconds), end: Number(item.end.seconds), reason: "Native move failed: " + item.name + "; destination frame=" + destinationFrame, severity: "error" };
            noteNative("before", "move");
            item.move(delta);
            noteNative("after", "move");
            pendingNativeReview = null;
            return true;
        }
        var mainEnd = plan.editedSourceMap ? Number(plan.editedSourceMap.physicalEndFrame) / fps : Number(plan.mainVideoSourceEnd);
        var plannedEnd = Number(plan.plannedMainVideoEnd);
        var voiceTrackIndex = Number(plan.voiceTrackIndex);
        var voiceClips = asArray(plan.voiceClips);
        var voiceEnd = Number(voiceClips[voiceClips.length - 1].end);
        var linkedSpecs = asArray(plan.linkedAudio);
        if (!linkedSpecs.length) throw new Error("Plan has no linked original audio.");
        var linkedTrackIndex = findLinkedTrack(original, linkedSpecs[0], mainEnd);
        if (linkedTrackIndex < 0) throw new Error("Could not locate linked original audio.");
        var originalMain = original.videoTracks[0].clips[0];
        if (!originalMain || Math.abs(Number(originalMain.end.seconds) - mainEnd) > 0.1) throw new Error("V1 main clip no longer matches plan.");
        var originalMainName = String(originalMain.name), originalMainProjectItem = originalMain.projectItem;
        var originalMainTimelineStartFrame = frameOf(originalMain.start);
        var originalMainSourceInFrame = frameOf(originalMain.inPoint);
        var originalMainSpeedPercent = readSpeedPercent(originalMain);
        if (originalMainSpeedPercent === null) originalMainSpeedPercent = Number(plan.mainVideoClip && plan.mainVideoClip.speedPercent ? plan.mainVideoClip.speedPercent : 100);
        var originalMainSpeedFactor = originalMainSpeedPercent / 100;
        var clipMarkerGroups = {};
        var cleanupOwners = markerCleanupOwners(original, originalMain, linkedTrackIndex, linkedSpecs[0].name, voiceTrackIndex, voiceClips);
        for (var cleanupOwnerIndex = 0; cleanupOwnerIndex < cleanupOwners.length; cleanupOwnerIndex++) {
            prepareClipMarkerGroup(cleanupOwners[cleanupOwnerIndex], clipMarkerGroups, fps);
        }
        var plannedCollisionEndFrame = plan.plannedMainVideoEndFrame === undefined ? Math.round(plannedEnd * fps) : Number(plan.plannedMainVideoEndFrame);
        var tailAnchorFrame = null;
        for (var preservedV1Index = 1; preservedV1Index < original.videoTracks[0].clips.numItems; preservedV1Index++) {
            var preservedV1Item = original.videoTracks[0].clips[preservedV1Index];
            var preservedV1StartFrame = frameOf(preservedV1Item.start);
            if (preservedV1StartFrame < plannedCollisionEndFrame && (tailAnchorFrame === null || preservedV1StartFrame < tailAnchorFrame)) tailAnchorFrame = preservedV1StartFrame;
        }
        var tailShiftFrames = tailAnchorFrame === null ? 0 : plannedCollisionEndFrame - tailAnchorFrame;
        var tailShiftItemCount = 0;
        if (tailShiftFrames > 0) {
            var tailItems = [];
            for (var tailVideoTrackIndex = 0; tailVideoTrackIndex < original.videoTracks.numTracks; tailVideoTrackIndex++) {
                var tailVideoTrack = original.videoTracks[tailVideoTrackIndex];
                for (var tailVideoClipIndex = 0; tailVideoClipIndex < tailVideoTrack.clips.numItems; tailVideoClipIndex++) {
                    var tailVideoClip = tailVideoTrack.clips[tailVideoClipIndex];
                    var tailVideoStartFrame = frameOf(tailVideoClip.start);
                    if (tailVideoStartFrame >= tailAnchorFrame) tailItems.push({ Item: tailVideoClip, StartFrame: tailVideoStartFrame, Kind: "V", Track: tailVideoTrackIndex });
                }
            }
            for (var tailAudioTrackIndex = 0; tailAudioTrackIndex < original.audioTracks.numTracks; tailAudioTrackIndex++) {
                var tailAudioTrack = original.audioTracks[tailAudioTrackIndex];
                for (var tailAudioClipIndex = 0; tailAudioClipIndex < tailAudioTrack.clips.numItems; tailAudioClipIndex++) {
                    var tailAudioClip = tailAudioTrack.clips[tailAudioClipIndex];
                    var tailAudioStartFrame = frameOf(tailAudioClip.start);
                    if (tailAudioStartFrame >= tailAnchorFrame) tailItems.push({ Item: tailAudioClip, StartFrame: tailAudioStartFrame, Kind: "A", Track: tailAudioTrackIndex });
                }
            }
            tailItems.sort(function (leftTail, rightTail) { return rightTail.StartFrame - leftTail.StartFrame; });
            for (var tailMoveIndex = 0; tailMoveIndex < tailItems.length; tailMoveIndex++) {
                var tailMove = tailItems[tailMoveIndex];
                var tailDestinationFrame = tailMove.StartFrame + tailShiftFrames;
                moveItemToFrame(tailMove.Item, tailDestinationFrame);
                var tailActualFrame = frameOf(tailMove.Item.start);
                if (tailActualFrame !== tailDestinationFrame) throw new Error("Không dời chính xác được element cuối timeline '" + tailMove.Item.name + "' trên " + tailMove.Kind + (tailMove.Track + 1) + ": cần frame " + tailDestinationFrame + ", thực tế " + tailActualFrame + ".");
                tailShiftItemCount++;
            }
        }
        var combinedVoiceNames = {};
        for (var cvn = 0; cvn < voiceClips.length; cvn++) combinedVoiceNames[String(voiceClips[cvn].name)] = true;
        var preservedBefore = preservedSignatures(original, linkedTrackIndex, voiceTrackIndex, originalMain.name, linkedSpecs[0].name, combinedVoiceNames);

        workingSequence = original;
        app.enableQE();
        var qeSequence = qe.project.getActiveSequence();
        var qeVideoTrack = qeSequence.getVideoTrackAt(0);
        var qeAudioTrack = qeSequence.getAudioTrackAt(linkedTrackIndex);

        var sourceSegments = [];
        var cutFrames = {};
        for (var ps = 0; ps < visualPlans.length; ps++) {
            var sourcePlan = visualPlans[ps];
            if (Number(sourcePlan.SourceDuration) <= 0.0005) continue;
            sourcePlan._PlanSegmentIndex = ps;
            sourceSegments.push(sourcePlan);
            var sf = sourcePlan.SourceStartFrame === undefined ? Math.round(Number(sourcePlan.SourceStart) * fps) : Number(sourcePlan.SourceStartFrame);
            var ef = sourcePlan.SourceEndFrame === undefined ? Math.round(Number(sourcePlan.SourceEnd) * fps) : Number(sourcePlan.SourceEndFrame);
            if (sf > 0 && sf < Math.round(mainEnd * fps)) cutFrames[sf] = true;
            if (ef > 0 && ef < Math.round(mainEnd * fps)) cutFrames[ef] = true;
        }
        if (plan.editedSourceMap) {
            for (var omissionCut = 0; omissionCut < plan.editedSourceMap.omissions.length; omissionCut++) {
                var omissionRange = plan.editedSourceMap.omissions[omissionCut];
                if (omissionRange.SourceStartFrame > 0) cutFrames[omissionRange.SourceStartFrame] = true;
                if (omissionRange.SourceEndFrame < Math.round(mainEnd * fps)) cutFrames[omissionRange.SourceEndFrame] = true;
            }
        }
        var cuts = [];
        for (var cutKey in cutFrames) if (cutFrames.hasOwnProperty(cutKey)) cuts.push(Number(cutKey));
        cuts.sort(function (a, b) { return a - b; });
        for (var cutIndex = 0; cutIndex < cuts.length; cutIndex++) {
            pendingNativeReview = {start:cuts[cutIndex]/fps,end:(cuts[cutIndex]+1)/fps,reason:"Linked razor failed at source timeline cut.",severity:"error"};
            timelineMutated = true;
            noteNative("before", "razor");
            if (!qeVideoTrack.razor($._PVS._timecodeFromSeconds(cuts[cutIndex] / fps, fps), true, false)) throw new Error("Linked razor failed at frame " + cuts[cutIndex] + ".");
            noteNative("after", "razor");
            pendingNativeReview = null;
            timelineMutated = true;
        }

        var videoTrack = workingSequence.videoTracks[0];
        var audioTrack = workingSequence.audioTracks[linkedTrackIndex];
        var videoPieces = [];
        var audioPieces = [];
        for (var vi = 0; vi < videoTrack.clips.numItems; vi++) {
            var vItem = videoTrack.clips[vi];
            if (String(vItem.name) === String(originalMain.name) && Number(vItem.start.seconds) < mainEnd - 0.001) videoPieces.push(vItem);
        }
        for (var ai = 0; ai < audioTrack.clips.numItems; ai++) {
            var aItem = audioTrack.clips[ai];
            if (String(aItem.name) === String(linkedSpecs[0].name) && Number(aItem.start.seconds) < mainEnd - 0.001) audioPieces.push(aItem);
        }
        videoPieces.sort(function (a, b) { return Number(a.start.seconds) - Number(b.start.seconds); });
        audioPieces.sort(function (a, b) { return Number(a.start.seconds) - Number(b.start.seconds); });
        var omittedPieceFlags = [];
        if (plan.editedSourceMap) {
            var expectedPieces = sourceSegments.slice(0);
            for (var omissionExpected = 0; omissionExpected < plan.editedSourceMap.omissions.length; omissionExpected++) expectedPieces.push(plan.editedSourceMap.omissions[omissionExpected]);
            expectedPieces.sort(function (a, b) { return a.SourceStartFrame - b.SourceStartFrame; });
            if (videoPieces.length !== expectedPieces.length || audioPieces.length !== expectedPieces.length) throw new Error("Edited linked piece count mismatch.");
            // Validate the complete physical partition before removing any pair.
            for (var omissionCheck = 0; omissionCheck < expectedPieces.length; omissionCheck++) {
                var expectedPiece = expectedPieces[omissionCheck];
                if (frameOf(videoPieces[omissionCheck].start) !== expectedPiece.SourceStartFrame || frameOf(videoPieces[omissionCheck].end) !== expectedPiece.SourceEndFrame ||
                    frameOf(audioPieces[omissionCheck].start) !== expectedPiece.SourceStartFrame || frameOf(audioPieces[omissionCheck].end) !== expectedPiece.SourceEndFrame) throw new Error("Edited linked piece bounds mismatch.");
                omittedPieceFlags[omissionCheck] = expectedPiece.Reason === "join-rerecognized-with-retained-anchors";
            }
        }
        for (var omitIndex = omittedPieceFlags.length - 1; omitIndex >= 0; omitIndex--) {
            if (!omittedPieceFlags[omitIndex]) continue;
            var omittedVideoId = String(videoPieces[omitIndex].nodeId), omittedAudioId = String(audioPieces[omitIndex].nodeId);
            pendingNativeReview = {start:Number(videoPieces[omitIndex].start.seconds),end:Number(videoPieces[omitIndex].end.seconds),reason:"Remove picture/original audio for a verified omitted SRT range.",severity:"error"};
            timelineMutated = true;
            videoPieces[omitIndex].remove(false, false);
            // Some hosts also remove the linked counterpart. Do not reuse a
            // deleted TrackItem proxy; look up the cached identity afresh.
            for (var omissionAudioScan = 0; omissionAudioScan < audioTrack.clips.numItems; omissionAudioScan++) {
                if (String(audioTrack.clips[omissionAudioScan].nodeId) === omittedAudioId) { audioTrack.clips[omissionAudioScan].remove(false, false); break; }
            }
            for (var omissionVideoScan = 0; omissionVideoScan < videoTrack.clips.numItems; omissionVideoScan++) if (String(videoTrack.clips[omissionVideoScan].nodeId) === omittedVideoId) throw new Error("Omitted picture removal failed.");
            for (var omissionAudioVerify = 0; omissionAudioVerify < audioTrack.clips.numItems; omissionAudioVerify++) if (String(audioTrack.clips[omissionAudioVerify].nodeId) === omittedAudioId) throw new Error("Omitted original audio removal failed.");
            videoPieces.splice(omitIndex, 1); audioPieces.splice(omitIndex, 1);
            pendingNativeReview = null;
        }
        if (videoPieces.length !== sourceSegments.length || audioPieces.length !== sourceSegments.length) throw new Error("Linked pair mapping mismatch V=" + videoPieces.length + ", A=" + audioPieces.length + ", plan=" + sourceSegments.length + ".");
        var speedChangeCount = 0;
        for (var fastIndex = 0; fastIndex < sourceSegments.length; fastIndex++) {
            var fastPlan = sourceSegments[fastIndex];
            if (fastPlan.Kind !== "retime") continue;
            var fastFactor = Number(fastPlan.AppliedSpeedPercent) / 100;
            if (fastFactor < 1 || Math.abs(fastFactor - 1) < 0.0001) continue;
            var fastFrames = fastPlan.VisualDurationFrames === undefined ? Math.max(1, Math.round((Number(fastPlan.NewEnd) - Number(fastPlan.BorrowSeconds || 0)) * fps) - Math.round(Number(fastPlan.NewStart) * fps)) : Number(fastPlan.VisualDurationFrames);
            var fastSourceEndFrame = fastPlan.SourceEndFrame === undefined ? Math.round(Number(fastPlan.SourceEnd) * fps) : Number(fastPlan.SourceEndFrame);
            var fastTouchesSourceTail = fastSourceEndFrame === Math.round(mainEnd * fps);
            setClipSpeed(videoPieces[fastIndex], qeVideoTrack, fastFactor, fastFrames, fps, ticksPerFrame * 0.6, "V1 segment " + fastIndex, fastTouchesSourceTail);
            setClipSpeed(audioPieces[fastIndex], qeAudioTrack, fastFactor, fastFrames, fps, ticksPerFrame * 0.6, "A1 segment " + fastIndex, fastTouchesSourceTail);
            speedChangeCount++;
        }
        var moveCount = 0;
        for (var moveIndex = sourceSegments.length - 1; moveIndex >= 0; moveIndex--) {
            var desiredStartFrame = sourceSegments[moveIndex].NewStartFrame === undefined ? Math.round(Number(sourceSegments[moveIndex].NewStart) * fps) : Number(sourceSegments[moveIndex].NewStartFrame);
            var videoMoved = moveItemToFrame(videoPieces[moveIndex], desiredStartFrame);
            var audioMoved = moveItemToFrame(audioPieces[moveIndex], desiredStartFrame);
            if (videoMoved || audioMoved) moveCount++;
        }
        qeSequence = qe.project.getActiveSequence();
        qeVideoTrack = qeSequence.getVideoTrackAt(0);
        qeAudioTrack = qeSequence.getAudioTrackAt(linkedTrackIndex);
        for (var slowIndex = 0; slowIndex < sourceSegments.length; slowIndex++) {
            var slowPlan = sourceSegments[slowIndex];
            if (slowPlan.Kind !== "retime") continue;
            var slowFactor = Number(slowPlan.AppliedSpeedPercent) / 100;
            if (slowFactor >= 1 || Math.abs(slowFactor - 1) < 0.0001) continue;
            var slowFrames = slowPlan.VisualDurationFrames === undefined ? Math.max(1, Math.round((Number(slowPlan.NewEnd) - Number(slowPlan.BorrowSeconds || 0)) * fps) - Math.round(Number(slowPlan.NewStart) * fps)) : Number(slowPlan.VisualDurationFrames);
            var slowSourceEndFrame = slowPlan.SourceEndFrame === undefined ? Math.round(Number(slowPlan.SourceEnd) * fps) : Number(slowPlan.SourceEndFrame);
            var slowTouchesSourceTail = slowSourceEndFrame === Math.round(mainEnd * fps);
            setClipSpeed(videoPieces[slowIndex], qeVideoTrack, slowFactor, slowFrames, fps, ticksPerFrame * 0.6, "V1 segment " + slowIndex, slowTouchesSourceTail);
            setClipSpeed(audioPieces[slowIndex], qeAudioTrack, slowFactor, slowFrames, fps, ticksPerFrame * 0.6, "A1 segment " + slowIndex, slowTouchesSourceTail);
            speedChangeCount++;
        }

        // Some nested clips can only resolve to the adjacent whole-frame
        // duration. Keep their coherent speed metadata and pack the following
        // linked pair to the actual preceding edge instead of forcing end/out.
        var coverageReconcileCount = 0;
        for (var reconcileIndex = 1; reconcileIndex < sourceSegments.length; reconcileIndex++) {
            var plannedReconcileFrame = sourceSegments[reconcileIndex].NewStartFrame === undefined ? Math.round(Number(sourceSegments[reconcileIndex].NewStart) * fps) : Number(sourceSegments[reconcileIndex].NewStartFrame);
            var previousActualEndFrame = frameOf(videoPieces[reconcileIndex - 1].end);
            if (Math.abs(previousActualEndFrame - plannedReconcileFrame) > reconcileToleranceFrames) continue;
            var reconcileVideoMoved = moveItemToFrame(videoPieces[reconcileIndex], previousActualEndFrame);
            var reconcileAudioMoved = moveItemToFrame(audioPieces[reconcileIndex], previousActualEndFrame);
            if (reconcileVideoMoved || reconcileAudioMoved) coverageReconcileCount++;
        }

        // Never force end/outPoint after setSpeed: doing so creates internally
        // inconsistent clips that make Premiere's Rate Stretch tool jump.
        var timelineEndMismatchCount = 0;
        var speedMetadataReadable = true;
        var actualSpeedWarningMarkers = [];
        var speedWarningCount = 0;
        var maxSpeedMetadataErrorPercent = 0;
        var minimumObservedSpeedPercent = Number.MAX_VALUE;
        var maximumObservedSpeedPercent = 0;
        for (var normalizeIndex = 0; normalizeIndex < sourceSegments.length; normalizeIndex++) {
            var normalizePlan = sourceSegments[normalizeIndex];
            var expectedDurationFrames = normalizePlan.Kind === "retime" && normalizePlan.VisualDurationFrames !== undefined ? Number(normalizePlan.VisualDurationFrames) : (normalizePlan.OutputDurationFrames === undefined ? Math.round(Number(normalizePlan.OutputDuration) * fps) : Number(normalizePlan.OutputDurationFrames));
            var videoDurationFrames = durationFramesOf(videoPieces[normalizeIndex]);
            var audioDurationFrames = durationFramesOf(audioPieces[normalizeIndex]);
            if (videoDurationFrames !== expectedDurationFrames || audioDurationFrames !== expectedDurationFrames) timelineEndMismatchCount++;
            if (normalizePlan.Kind === "retime") {
                var plannedSpeedPercent = Number(normalizePlan.AppliedSpeedPercent);
                var observedVideoSpeed = readSpeedPercent(videoPieces[normalizeIndex]);
                var observedAudioSpeed = readSpeedPercent(audioPieces[normalizeIndex]);
                if (observedVideoSpeed === null || observedAudioSpeed === null) speedMetadataReadable = false;
                var reviewSpeed = observedVideoSpeed === null ? plannedSpeedPercent : observedVideoSpeed;
                var outsideSpeedRange = reviewSpeed < Number(plan.speedWarningMinPercent) - 0.01 || reviewSpeed > Number(plan.speedWarningMaxPercent) + 0.01;
                var mergedVisualGroup = normalizePlan.MemberSegmentIndices && normalizePlan.MemberSegmentIndices.length === 2;
                if (outsideSpeedRange) speedWarningCount++;
                if ($._PVS._shouldMarkSpeed(plan, plannedSpeedPercent, observedVideoSpeed, observedAudioSpeed, outsideSpeedRange, mergedVisualGroup)) actualSpeedWarningMarkers.push({
                    SegmentIndex: Number(normalizePlan._PlanSegmentIndex),
                    Owner: "V1",
                    Merged: !!mergedVisualGroup,
                    ColorIndex: outsideSpeedRange ? (reviewSpeed < Number(plan.speedWarningMinPercent) ? 3 : 1) : 6,
                    Name: mergedVisualGroup ? (outsideSpeedRange ? "VOICE SYNC - Gop hinh / Kiem tra toc do" : "VOICE SYNC - Da gop hinh") : "VOICE SYNC - Kiem tra toc do",
                    Comments: "Sentence cues " + normalizePlan.FirstTargetCue + "-" + normalizePlan.LastTargetCue + ": actual speed=" + reviewSpeed.toFixed(3) + "%, warning range=" + plan.speedWarningMinPercent + "-" + plan.speedWarningMaxPercent + "%" + (mergedVisualGroup ? "; merged adjacent source segments " + (normalizePlan.MemberSegmentIndices[0] + 1) + " + " + (normalizePlan.MemberSegmentIndices[1] + 1) + "; one merge only" : "")
                });
                var observedSpeeds = [observedVideoSpeed, observedAudioSpeed];
                for (var observedIndex = 0; observedIndex < observedSpeeds.length; observedIndex++) {
                    if (observedSpeeds[observedIndex] === null) continue;
                    minimumObservedSpeedPercent = Math.min(minimumObservedSpeedPercent, observedSpeeds[observedIndex]);
                    maximumObservedSpeedPercent = Math.max(maximumObservedSpeedPercent, observedSpeeds[observedIndex]);
                    maxSpeedMetadataErrorPercent = Math.max(maxSpeedMetadataErrorPercent, Math.abs(observedSpeeds[observedIndex] - plannedSpeedPercent));
                }
            }
        }
        if (minimumObservedSpeedPercent === Number.MAX_VALUE) minimumObservedSpeedPercent = null;

        var linkMismatchCount = 0;
        var maxPairStartError = 0;
        var maxPairEndError = 0;
        for (var pairIndex = 0; pairIndex < sourceSegments.length; pairIndex++) {
            var pairStartError = Math.abs(frameOf(videoPieces[pairIndex].start) - frameOf(audioPieces[pairIndex].start));
            var pairEndError = Math.abs(frameOf(videoPieces[pairIndex].end) - frameOf(audioPieces[pairIndex].end));
            maxPairStartError = Math.max(maxPairStartError, pairStartError);
            maxPairEndError = Math.max(maxPairEndError, pairEndError);
            var linkedOk = false;
            try {
                var linkedItems = videoPieces[pairIndex].getLinkedItems();
                for (var linkedIndex = 0; linkedIndex < linkedItems.length; linkedIndex++) {
                    if (String(linkedItems[linkedIndex].nodeId) === String(audioPieces[pairIndex].nodeId)) linkedOk = true;
                }
            } catch (ignoreLinked) {}
            if (!linkedOk) linkMismatchCount++;
        }

        // Voice speech pieces: cut from the untouched voice track, discard old
        // silence slices, then move speech right-to-left into the new timing.
        var voiceNames = {};
        for (var vn = 0; vn < voiceClips.length; vn++) voiceNames[String(voiceClips[vn].name)] = true;
        var qeVoiceTrack = qeSequence.getAudioTrackAt(voiceTrackIndex);
        var speechPlans = [];
        var speechIndexByPlanSegment = {};
        var voiceCutFrames = {};
        for (var spi = 0; spi < plan.segments.length; spi++) {
            var speechPlan = plan.segments[spi];
            if (speechPlan.Kind !== "retime") continue;
            speechIndexByPlanSegment[String(spi)] = speechPlans.length;
            speechPlans.push(speechPlan);
            var vsf = speechPlan.OriginalVoiceStartFrame === undefined ? Math.round(Number(speechPlan.OriginalVoiceStart) * fps) : Number(speechPlan.OriginalVoiceStartFrame);
            var vef = speechPlan.OriginalVoiceEndFrame === undefined ? Math.round(Number(speechPlan.OriginalVoiceEnd) * fps) : Number(speechPlan.OriginalVoiceEndFrame);
            if (vsf > 0 && vsf < Math.round(voiceEnd * fps)) voiceCutFrames[vsf] = true;
            if (vef > 0 && vef < Math.round(voiceEnd * fps)) voiceCutFrames[vef] = true;
        }
        var voiceCuts = [];
        for (var voiceKey in voiceCutFrames) if (voiceCutFrames.hasOwnProperty(voiceKey)) voiceCuts.push(Number(voiceKey));
        voiceCuts.sort(function (a, b) { return a - b; });
        for (var voiceCutIndex = 0; voiceCutIndex < voiceCuts.length; voiceCutIndex++) {
            pendingNativeReview = {start:voiceCuts[voiceCutIndex]/fps,end:(voiceCuts[voiceCutIndex]+1)/fps,reason:"Voice razor failed at source timeline cut.",severity:"error"};
            timelineMutated = true;
            noteNative("before", "razor");
            qeVoiceTrack.razor($._PVS._timecodeFromSeconds(voiceCuts[voiceCutIndex] / fps, fps), false, false);
            noteNative("after", "razor");
            pendingNativeReview = null;
            timelineMutated = true;
        }
        var voiceTrack = workingSequence.audioTracks[voiceTrackIndex];
        var allVoicePieces = [];
        for (var av = 0; av < voiceTrack.clips.numItems; av++) {
            var voiceItem = voiceTrack.clips[av];
            if (voiceNames[String(voiceItem.name)] && Number(voiceItem.start.seconds) < voiceEnd + 0.1) allVoicePieces.push(voiceItem);
        }
        var speechPieces = [];
        var usedVoiceIds = {};
        var maxVoiceMappingStartErrorFrames = 0;
        var maxVoiceMappingEndErrorFrames = 0;
        for (var mapIndex = 0; mapIndex < speechPlans.length; mapIndex++) {
            var wantedStart = speechPlans[mapIndex].OriginalVoiceStartFrame === undefined ? Math.round(Number(speechPlans[mapIndex].OriginalVoiceStart) * fps) : Number(speechPlans[mapIndex].OriginalVoiceStartFrame);
            var wantedEnd = speechPlans[mapIndex].OriginalVoiceEndFrame === undefined ? Math.round(Number(speechPlans[mapIndex].OriginalVoiceEnd) * fps) : Number(speechPlans[mapIndex].OriginalVoiceEndFrame);
            var bestPiece = null;
            var bestStartError = Number.MAX_VALUE;
            var bestEndError = Number.MAX_VALUE;
            var bestBoundaryError = Number.MAX_VALUE;
            var bestTotalError = Number.MAX_VALUE;
            for (var voicePieceIndex = 0; voicePieceIndex < allVoicePieces.length; voicePieceIndex++) {
                var possibleVoice = allVoicePieces[voicePieceIndex];
                if (usedVoiceIds[String(possibleVoice.nodeId)]) continue;
                var candidateStartError = Math.abs(frameOf(possibleVoice.start) - wantedStart);
                var candidateEndError = Math.abs(frameOf(possibleVoice.end) - wantedEnd);
                var candidateBoundaryError = Math.max(candidateStartError, candidateEndError);
                var candidateTotalError = candidateStartError + candidateEndError;
                if (candidateBoundaryError < bestBoundaryError || (candidateBoundaryError === bestBoundaryError && candidateTotalError < bestTotalError)) {
                    bestPiece = possibleVoice;
                    bestStartError = candidateStartError;
                    bestEndError = candidateEndError;
                    bestBoundaryError = candidateBoundaryError;
                    bestTotalError = candidateTotalError;
                }
            }
            if (!bestPiece) throw new Error("Không tìm thấy đoạn voice cho cue " + speechPlans[mapIndex].FirstTargetCue + ".");
            if (bestStartError > voiceMappingToleranceFrames || bestEndError > voiceMappingToleranceFrames) {
                throw new Error("Voice mapping vượt dung sai tại cue " + speechPlans[mapIndex].FirstTargetCue + ": mép đầu lệch " + bestStartError + " frame, mép cuối lệch " + bestEndError + " frame, giới hạn " + voiceMappingToleranceFrames + " frame mỗi mép; clip gần nhất '" + bestPiece.name + "' từ frame " + frameOf(bestPiece.start) + " đến " + frameOf(bestPiece.end) + ".");
            }
            maxVoiceMappingStartErrorFrames = Math.max(maxVoiceMappingStartErrorFrames, bestStartError);
            maxVoiceMappingEndErrorFrames = Math.max(maxVoiceMappingEndErrorFrames, bestEndError);
            speechPieces.push(bestPiece);
            usedVoiceIds[String(bestPiece.nodeId)] = true;
        }
        var removedSilenceCount = 0;
        for (var removeVoice = allVoicePieces.length - 1; removeVoice >= 0; removeVoice--) {
            if (!usedVoiceIds[String(allVoicePieces[removeVoice].nodeId)]) { timelineMutated = true; allVoicePieces[removeVoice].remove(false, false); removedSilenceCount++; }
        }
        for (var voiceMove = speechPieces.length - 1; voiceMove >= 0; voiceMove--) {
            var newVoiceStartFrame = speechPlans[voiceMove].NewVoiceStartFrame === undefined ? Math.round(Number(speechPlans[voiceMove].NewVoiceStart) * fps) : Number(speechPlans[voiceMove].NewVoiceStartFrame);
            moveItemToFrame(speechPieces[voiceMove], newVoiceStartFrame);
        }

        // Schema 8 retimes the complete source span directly. Copied visual
        // fills are forbidden because Premiere can leave unstable TrackItem
        // proxies after inserting them into the same nested-video track.
        var fillRequests = [];
        for (var fpi = 0; fpi < plan.segments.length; fpi++) {
            var fillPlan = plan.segments[fpi];
            if (Number(fillPlan.BorrowSeconds || 0) > 0.0005 || Number(fillPlan.VisualExtension || 0) > 0.0005) throw new Error("Schema 8 does not allow copied visual fills.");
        }
        var fillClips = [];

        var maxVideoError = 0;
        var maxAudioError = 0;
        var maxVoiceError = 0;
        var maxVideoCoverageGapFrames = 0;
        var videoCoverageGaps = [];
        for (var validateIndex = 0; validateIndex < sourceSegments.length; validateIndex++) {
            var expectedFrame = sourceSegments[validateIndex].NewStartFrame === undefined ? Math.round(Number(sourceSegments[validateIndex].NewStart) * fps) : Number(sourceSegments[validateIndex].NewStartFrame);
            maxVideoError = Math.max(maxVideoError, Math.abs(frameOf(videoPieces[validateIndex].start) - expectedFrame));
            maxAudioError = Math.max(maxAudioError, Math.abs(frameOf(audioPieces[validateIndex].start) - expectedFrame));
        }
        var coverageItems = videoPieces.slice(0);
        for (var coverageFillIndex = 0; coverageFillIndex < fillClips.length; coverageFillIndex++) coverageItems.push(fillClips[coverageFillIndex]);
        coverageItems.sort(function (left, right) { return Number(left.start.seconds) - Number(right.start.seconds); });
        for (var coverageIndex = 1; coverageIndex < coverageItems.length; coverageIndex++) {
            var previousCoverageEnd = frameOf(coverageItems[coverageIndex - 1].end);
            var nextCoverageStart = frameOf(coverageItems[coverageIndex].start);
            var coverageGapFrames = Math.max(0, nextCoverageStart - previousCoverageEnd);
            maxVideoCoverageGapFrames = Math.max(maxVideoCoverageGapFrames, coverageGapFrames);
            if (coverageGapFrames > 0 && nextCoverageStart <= Math.round(plannedEnd * fps)) videoCoverageGaps.push({
                previousIndex: coverageIndex - 1,
                nextIndex: coverageIndex,
                previousEndFrame: previousCoverageEnd,
                nextStartFrame: nextCoverageStart,
                gapFrames: coverageGapFrames
            });
        }
        var plannedEndFrame = plan.plannedMainVideoEndFrame === undefined ? Math.round(plannedEnd * fps) : Number(plan.plannedMainVideoEndFrame);
        var finalVideoEndFrame = coverageItems.length ? frameOf(coverageItems[coverageItems.length - 1].end) : 0;
        var finalAudioEndFrame = audioPieces.length ? frameOf(audioPieces[audioPieces.length - 1].end) : 0;
        var finalVideoTailDeltaFrames = finalVideoEndFrame - plannedEndFrame;
        var finalAudioTailDeltaFrames = finalAudioEndFrame - plannedEndFrame;
        var finalVideoTailMissingFrames = Math.max(0, -finalVideoTailDeltaFrames);
        var finalAudioTailMissingFrames = Math.max(0, -finalAudioTailDeltaFrames);
        var finalVideoTailExtraFrames = Math.max(0, finalVideoTailDeltaFrames);
        var finalAudioTailExtraFrames = Math.max(0, finalAudioTailDeltaFrames);
        if (finalVideoTailMissingFrames > 0) {
            maxVideoCoverageGapFrames = Math.max(maxVideoCoverageGapFrames, finalVideoTailMissingFrames);
            videoCoverageGaps.push({
                type: "tail",
                previousIndex: coverageItems.length - 1,
                previousEndFrame: finalVideoEndFrame,
                nextStartFrame: plannedEndFrame,
                gapFrames: finalVideoTailMissingFrames
            });
        }
        for (var validateVoice = 0; validateVoice < speechPieces.length; validateVoice++) {
            var expectedVoiceFrame = speechPlans[validateVoice].NewVoiceStartFrame === undefined ? Math.round(Number(speechPlans[validateVoice].NewVoiceStart) * fps) : Number(speechPlans[validateVoice].NewVoiceStartFrame);
            maxVoiceError = Math.max(maxVoiceError, Math.abs(frameOf(speechPieces[validateVoice].start) - expectedVoiceFrame));
        }
        var markerCount = 0;
        var mergeClipMarkerCount = 0;
        var markerFailures = [];
        var plannedClipMarkers = asArray(plan.markers);
        for (var markerIndex = 0; markerIndex < plannedClipMarkers.length; markerIndex++) {
            var plannedMarkerSpec = plannedClipMarkers[markerIndex];
            var plannedSegmentIndex = plannedMarkerSpec.SegmentIndex;
            var plannedMarkerItem = null;
            if (plannedSegmentIndex === undefined || plannedSegmentIndex === null) {
                for (var fallbackSegmentIndex = 0; fallbackSegmentIndex < plan.segments.length; fallbackSegmentIndex++) {
                    if (plan.segments[fallbackSegmentIndex].Kind === "retime" && Math.abs(Number(plan.segments[fallbackSegmentIndex].NewStart) - Number(plannedMarkerSpec.Time)) < 0.001) { plannedSegmentIndex = fallbackSegmentIndex; break; }
                }
            }
            var speechPieceIndex = speechIndexByPlanSegment[String(plannedSegmentIndex)];
            try {
                if (speechPieceIndex === undefined || !speechPieces[speechPieceIndex]) throw new Error("Could not map A2 clip marker to sentence segment " + plannedSegmentIndex + ".");
                plannedMarkerItem = speechPieces[speechPieceIndex];
                planOwnedClipMarker(plannedMarkerItem, plannedMarkerSpec, fps, clipMarkerGroups);
            } catch (plannedMarkerError) { blockClipMarkerGroup(plannedMarkerItem, clipMarkerGroups); markerFailures.push(plannedMarkerError.message); }
        }
        for (var speedMarkerIndex = 0; speedMarkerIndex < actualSpeedWarningMarkers.length; speedMarkerIndex++) {
            var speedMarkerSpec = actualSpeedWarningMarkers[speedMarkerIndex];
            var speedVideoPiece = null;
            var speedSourceSegment = null;
            for (var speedPieceIndex = 0; speedPieceIndex < sourceSegments.length; speedPieceIndex++) {
                if (Number(sourceSegments[speedPieceIndex]._PlanSegmentIndex) === Number(speedMarkerSpec.SegmentIndex)) {
                    speedVideoPiece = videoPieces[speedPieceIndex];
                    speedSourceSegment = sourceSegments[speedPieceIndex];
                    break;
                }
            }
            try {
                if (!speedVideoPiece || !speedSourceSegment) throw new Error("Could not map V1 clip marker to sentence segment " + speedMarkerSpec.SegmentIndex + ".");
                var markerSourceTimelineStartFrame = speedSourceSegment.SourceStartFrame === undefined ? Number(speedSourceSegment.SourceStart) * fps : Number(speedSourceSegment.SourceStartFrame);
                var markerSourceTimelineEndFrame = speedSourceSegment.SourceEndFrame === undefined ? Number(speedSourceSegment.SourceEnd) * fps : Number(speedSourceSegment.SourceEndFrame);
                var markerOutputStartFrame = speedSourceSegment.NewStartFrame === undefined ? Number(speedSourceSegment.NewStart) * fps : Number(speedSourceSegment.NewStartFrame);
                var markerOutputDurationFrames = speedSourceSegment.VisualDurationFrames === undefined ? durationFramesOf(speedVideoPiece) : Number(speedSourceSegment.VisualDurationFrames);
                var markerPlannedRange = {
                    sourceStartFrame: originalMainSourceInFrame + (markerSourceTimelineStartFrame - originalMainTimelineStartFrame) * originalMainSpeedFactor,
                    sourceEndFrame: originalMainSourceInFrame + (markerSourceTimelineEndFrame - originalMainTimelineStartFrame) * originalMainSpeedFactor,
                    outputStartFrame: markerOutputStartFrame,
                    outputEndFrame: markerOutputStartFrame + markerOutputDurationFrames
                };
                planOwnedClipMarker(speedVideoPiece, speedMarkerSpec, fps, clipMarkerGroups, markerPlannedRange);
            } catch (speedMarkerError) { blockClipMarkerGroup(speedVideoPiece, clipMarkerGroups); markerFailures.push(speedMarkerError.message); }
        }
        // One synchronous commit per source; pause/cancel only between groups.
        for (var markerOwnerIndex = 0; markerOwnerIndex < cleanupOwners.length; markerOwnerIndex++) {
            var markerOwner = cleanupOwners[markerOwnerIndex];
            try {
                markerOwner.Group.collection = markerOwner.ProjectItem.getMarkers();
                var clipMarkerResult = $._PVS._markerTools.commit(markerOwner.Group, function () { timelineMutated = true; });
                markerCount += clipMarkerResult.count;
                mergeClipMarkerCount += clipMarkerResult.merged;
                clearedClipMarkerCount += clipMarkerResult.deleted;
                for (var cmf = 0; cmf < clipMarkerResult.failures.length; cmf++) markerFailures.push(clipMarkerResult.failures[cmf]);
                for (var ccf = 0; ccf < clipMarkerResult.colorFailures.length; ccf++) markerColorFailures.push(clipMarkerResult.colorFailures[ccf]);
            } catch (clipMarkerOwnerError) { markerFailures.push("Marker source " + markerOwnerIndex + ": " + clipMarkerOwnerError.message); }
        }
        var reviewIssues = asArray(plan.reviewMarkers).slice(0);
        function addNativeReview(startFrame, endFrame, reason, severity) {
            var start = Math.max(0, Math.min(startFrame, plannedEndFrame - 1));
            var end = Math.min(plannedEndFrame, Math.max(start + 1, endFrame));
            reviewIssues.push({ start: start / fps, end: end / fps, reason: reason, severity: severity || "error" });
        }
        for (var reviewIndex = 0; reviewIndex < sourceSegments.length; reviewIndex++) {
            var reviewVideo = videoPieces[reviewIndex], reviewAudio = audioPieces[reviewIndex];
            var reviewStart = Math.round(Number(sourceSegments[reviewIndex].NewStart) * fps);
            var reviewEnd = reviewStart + durationFramesOf(reviewVideo);
            if (Math.abs(frameOf(reviewVideo.start) - reviewStart) > validationToleranceFrames || Math.abs(frameOf(reviewAudio.start) - reviewStart) > validationToleranceFrames) addNativeReview(reviewStart, reviewEnd, "V1/A1 position differs from plan.");
            if (Math.abs(frameOf(reviewVideo.start) - frameOf(reviewAudio.start)) > validationToleranceFrames || Math.abs(frameOf(reviewVideo.end) - frameOf(reviewAudio.end)) > validationToleranceFrames) addNativeReview(reviewStart, reviewEnd, "V1/A1 boundaries differ.");
            var reviewLinked = false;
            try {
                var reviewLinks = reviewVideo.getLinkedItems();
                for (var reviewLink = 0; reviewLink < reviewLinks.length; reviewLink++) if (String(reviewLinks[reviewLink].nodeId) === String(reviewAudio.nodeId)) reviewLinked = true;
            } catch (ignoreReviewLink) {}
            if (!reviewLinked) addNativeReview(reviewStart, reviewEnd, "V1/A1 link could not be verified.");
            if (readSpeedPercent(reviewVideo) === null || readSpeedPercent(reviewAudio) === null) addNativeReview(reviewStart, reviewEnd, "Premiere speed metadata unavailable; check playback.", "review");
        }
        for (var reviewVoice = 0; reviewVoice < speechPieces.length; reviewVoice++) {
            var reviewVoiceStart = Math.round(Number(speechPlans[reviewVoice].NewVoiceStart) * fps);
            if (Math.abs(frameOf(speechPieces[reviewVoice].start) - reviewVoiceStart) > validationToleranceFrames) addNativeReview(reviewVoiceStart, reviewVoiceStart + durationFramesOf(speechPieces[reviewVoice]), "Voice position differs from plan.");
        }
        for (var reviewGap = 0; reviewGap < videoCoverageGaps.length; reviewGap++) addNativeReview(videoCoverageGaps[reviewGap].previousEndFrame, videoCoverageGaps[reviewGap].nextStartFrame, "Video coverage gap: " + videoCoverageGaps[reviewGap].gapFrames + " frames.");
        for (var reviewSpeed = 0; reviewSpeed < speedConvergenceFailures.length; reviewSpeed++) addNativeReview(speedConvergenceFailures[reviewSpeed].startFrame, speedConvergenceFailures[reviewSpeed].startFrame + speedConvergenceFailures[reviewSpeed].desiredFrames, "Speed duration did not converge: " + speedConvergenceFailures[reviewSpeed].label);
        if (finalVideoTailDeltaFrames !== 0 || finalAudioTailDeltaFrames !== 0) addNativeReview(Math.min(finalVideoEndFrame, finalAudioEndFrame, plannedEndFrame) - 1, plannedEndFrame, "Video/audio tail differs from plan: V1=" + finalVideoTailDeltaFrames + ", A1=" + finalAudioTailDeltaFrames + " frames.");
        reviewMarkerStats = $._PVS._applyReviewMarkers(workingSequence, plan.reviewMarkers !== undefined || reviewIssues.length ? reviewIssues : undefined, [{start:0,end:plannedEndFrame/fps}], "edit");
        var captionFile = new File(plan.captionSrtPath);
        var captionCreated = false;
        var captionTemporaryBinRemoved = false;
        var captionProjectItemCountBefore = 0;
        var captionProjectItemCountAfter = 0;
        var captionTemporaryBinStillPresent = false;
        var captionDeleteReturnValue = "";
        var captionCleanupProbeCount = 0;
        function countCaptionProjectItems(root, targetPath) {
            var count = 0;
            if (!root) return count;
            try {
                if (root.getMediaPath && String(root.getMediaPath() || "").toLowerCase() === String(targetPath || "").toLowerCase()) count++;
            } catch (ignoreCaptionCountPath) {}
            try {
                if (root.children) for (var childIndex = 0; childIndex < root.children.numItems; childIndex++) count += countCaptionProjectItems(root.children[childIndex], targetPath);
            } catch (ignoreCaptionCountChildren) {}
            return count;
        }
        function projectTreeContainsNodeId(root, targetNodeId) {
            if (!root || targetNodeId === "") return false;
            try { if (String(root.nodeId) === targetNodeId) return true; } catch (ignoreCaptionNodeId) {}
            try {
                if (root.children) for (var childIndex = 0; childIndex < root.children.numItems; childIndex++) {
                    if (projectTreeContainsNodeId(root.children[childIndex], targetNodeId)) return true;
                }
            } catch (ignoreCaptionNodeChildren) {}
            return false;
        }
        if (captionFile.exists) {
            captionProjectItemCountBefore = countCaptionProjectItems(app.project.rootItem, plan.captionSrtPath);
            var captionBin = null;
            var captionBinNodeId = "";
            try {
                captionBin = app.project.rootItem.createBin("PVS_TEMP_CAPTION_" + String((new Date()).getTime()));
                if (!captionBin) throw new Error("Could not create temporary caption bin.");
                try { captionBinNodeId = String(captionBin.nodeId); } catch (ignoreCaptionBinNodeId) {}
                if (captionBinNodeId === "") throw new Error("Temporary caption bin has no nodeId.");
                if (!app.project.importFiles([plan.captionSrtPath], true, captionBin, false)) throw new Error("Could not import aligned caption SRT into temporary bin.");
                var captionItem = $._PVS._findItemByMediaPath(captionBin, plan.captionSrtPath);
                if (!captionItem) throw new Error("Could not import aligned caption SRT.");
                captionCreated = !!workingSequence.createCaptionTrack(captionItem, 0, Sequence.CAPTION_FORMAT_SUBTITLE);
                if (!captionCreated) throw new Error("Premiere could not create caption track.");
            } finally {
                if (captionBin) {
                    try {
                        var deleteResult = captionBin.deleteBin();
                        captionDeleteReturnValue = deleteResult === undefined ? "undefined" : String(deleteResult);
                    } catch (captionBinDeleteError) {
                        captionDeleteReturnValue = "throw: " + captionBinDeleteError.message;
                    }
                }
                for (var captionCleanupProbe = 0; captionCleanupProbe < 6; captionCleanupProbe++) {
                    captionCleanupProbeCount = captionCleanupProbe + 1;
                    captionTemporaryBinStillPresent = projectTreeContainsNodeId(app.project.rootItem, captionBinNodeId);
                    captionProjectItemCountAfter = countCaptionProjectItems(app.project.rootItem, plan.captionSrtPath);
                    if (!captionTemporaryBinStillPresent && captionProjectItemCountAfter === captionProjectItemCountBefore) {
                        captionTemporaryBinRemoved = true;
                        break;
                    }
                    if (captionCleanupProbe < 5) {
                        try { $.sleep(50); } catch (ignoreCaptionCleanupSleep) {}
                    }
                }
            }
            if (!captionTemporaryBinRemoved) throw new Error("Temporary caption cleanup failed: deleteBin returned " + captionDeleteReturnValue + "; bin still present=" + captionTemporaryBinStillPresent + "; SRT ProjectItems before=" + captionProjectItemCountBefore + ", after=" + captionProjectItemCountAfter + ".");
        }
        var masterInOutReset = false;
        try {
            var masterNestedItem = originalMainProjectItem;
            if (masterNestedItem && masterNestedItem.clearInPoint && masterNestedItem.clearOutPoint) {
                masterNestedItem.clearInPoint();
                masterNestedItem.clearOutPoint();
                masterInOutReset = true;
            }
        } catch (ignoreMasterReset) {}
        var preservedAfter = preservedSignatures(workingSequence, linkedTrackIndex, voiceTrackIndex, originalMainName, linkedSpecs[0].name, combinedVoiceNames);
        var unrelatedPreserved = sameSignatures(preservedBefore, preservedAfter);
        var captionCueCount = plan.captions && plan.captions.length ? plan.captions.length : 0;
        var expectedCaptionCueCount = plan.summary && plan.summary.captionCueCount ? Number(plan.summary.captionCueCount) : captionCueCount;
        var captionsValid = captionFile.exists && captionCueCount > 0 && captionCueCount === expectedCaptionCueCount;
        report = {
            ok: masterInOutReset && markerFailures.length === 0 && speedNonConvergenceCount === 0 && timelineEndMismatchCount === 0 && maxVideoError <= validationToleranceFrames && maxAudioError <= validationToleranceFrames && maxVoiceError <= validationToleranceFrames && maxPairStartError <= validationToleranceFrames && maxPairEndError <= validationToleranceFrames && maxVideoCoverageGapFrames <= maxCoverageGapFramesAllowed && finalVideoTailDeltaFrames === 0 && finalAudioTailDeltaFrames === 0 && linkMismatchCount === 0 && unrelatedPreserved && fillClips.length === fillRequests.length && captionsValid && captionCreated && captionTemporaryBinRemoved && captionProjectItemCountAfter === captionProjectItemCountBefore,
            executorVersion: 25,
            directApplied: true,
            timelineMutated: timelineMutated,
            tailAnchorFrame: tailAnchorFrame,
            tailShiftFrames: tailShiftFrames,
            tailShiftItemCount: tailShiftItemCount,
            originalSequenceId: originalId,
            workingSequenceId: workingSequence.sequenceID,
            linkedTrackIndex: linkedTrackIndex,
            linkedCutCount: cuts.length,
            pairSegmentCount: sourceSegments.length,
            omittedSourceFrameCount: plan.editedSourceMap ? plan.editedSourceMap.physicalEndFrame - plan.editedSourceMap.planEndFrame : 0,
            omittedReferenceCueIndices: plan.omittedReferenceCueIndices || [],
            speedChangeCount: speedChangeCount,
            timelineEndMismatchCount: timelineEndMismatchCount,
            speedNonConvergenceCount: speedNonConvergenceCount,
            speedCorrectionCount: speedCorrectionCount,
            terminalEndFallbackCount: terminalEndFallbackCount,
            maxSpeedDurationErrorBeforeCorrectionFrames: maxSpeedDurationErrorBeforeCorrectionFrames,
            maxSpeedDurationErrorAfterCorrectionFrames: maxSpeedDurationErrorAfterCorrectionFrames,
            speedConvergenceFailures: speedConvergenceFailures,
            speedMetadataReadable: speedMetadataReadable,
            plannedSpeedWarningSentenceCount: Number(plan.summary && plan.summary.speedWarningCount ? plan.summary.speedWarningCount : 0),
            speedWarningSentenceCount: speedWarningCount,
            clearedClipMarkerCount: clearedClipMarkerCount,
            mergeClipMarkerCount: mergeClipMarkerCount,
            clipMarkerColorFailureCount: markerColorFailures.length,
            clipMarkerColorFailures: markerColorFailures,
            minimumObservedSpeedPercent: minimumObservedSpeedPercent,
            maximumObservedSpeedPercent: maximumObservedSpeedPercent,
            maxSpeedMetadataErrorPercent: maxSpeedMetadataErrorPercent,
            coverageReconcileCount: coverageReconcileCount,
            moveCount: moveCount,
            linkMismatchCount: linkMismatchCount,
            maxPairStartErrorFrames: maxPairStartError,
            maxPairEndErrorFrames: maxPairEndError,
            voiceCueCount: speechPieces.length,
            pictureCueCount: (function () { var n = 0; for (var i = 0; i < visualPlans.length; i++) if (visualPlans[i].Kind === "retime") n++; return n; }()),
            removedSilenceCount: removedSilenceCount,
            maxVoiceMappingStartErrorFrames: maxVoiceMappingStartErrorFrames,
            maxVoiceMappingEndErrorFrames: maxVoiceMappingEndErrorFrames,
            fillCount: fillClips.length,
            markerCount: markerCount + reviewMarkerStats.reviewMarkerCount,
            clipMarkerCount: markerCount,
            sequenceMarkerCount: reviewMarkerStats.reviewMarkerCount,
            markerPlacementMode: "clip-project-item-planned-source-range-verified",
            clipMarkerFailureCount: markerFailures.length,
            clipMarkerFailures: markerFailures,
            captionReady: captionsValid,
            captionCueCount: captionCueCount,
            captionCreated: captionCreated,
            captionTemporaryBinRemoved: captionTemporaryBinRemoved,
            captionTemporaryBinStillPresent: captionTemporaryBinStillPresent,
            captionDeleteReturnValue: captionDeleteReturnValue,
            captionCleanupProbeCount: captionCleanupProbeCount,
            captionProjectItemCountBefore: captionProjectItemCountBefore,
            captionProjectItemCountAfter: captionProjectItemCountAfter,
            masterInOutReset: masterInOutReset,
            unrelatedPreserved: unrelatedPreserved,
            preservedBefore: preservedBefore,
            preservedAfter: preservedAfter,
            maxVideoStartErrorFrames: maxVideoError,
            maxAudioStartErrorFrames: maxAudioError,
            maxVoiceStartErrorFrames: maxVoiceError
            ,maxVideoCoverageGapFrames: maxVideoCoverageGapFrames,
            videoCoverageGaps: videoCoverageGaps
            ,plannedMainVideoEndFrame: plannedEndFrame,
            finalVideoEndFrame: finalVideoEndFrame,
            finalAudioEndFrame: finalAudioEndFrame,
            finalVideoTailDeltaFrames: finalVideoTailDeltaFrames,
            finalAudioTailDeltaFrames: finalAudioTailDeltaFrames,
            finalVideoTailMissingFrames: finalVideoTailMissingFrames,
            finalAudioTailMissingFrames: finalAudioTailMissingFrames,
            finalVideoTailExtraFrames: finalVideoTailExtraFrames,
            finalAudioTailExtraFrames: finalAudioTailExtraFrames
            ,settings: { voiceMappingToleranceFrames: voiceMappingToleranceFrames, validationToleranceFrames: validationToleranceFrames, maxCoverageGapFrames: maxCoverageGapFramesAllowed }
        };
    } catch (e) {
        report = { ok: false, executorVersion: 25, timelineMutated: timelineMutated, error: e.message };
        // Only a captured native operation supplies a trustworthy failure
        // location on a partially built timeline. Never guess from a global
        // error, a cancellation, or a changed active sequence.
        if (pendingNativeReview && timelineMutated && workingSequence && app.project.activeSequence && String(app.project.activeSequence.sequenceID) === String(workingSequence.sequenceID)) {
            pendingNativeReview.reason += "; " + e.message + "; timeline is partially built; inspect before retry.";
            reviewMarkerStats = $._PVS._applyReviewMarkers(workingSequence, [pendingNativeReview], [{start:pendingNativeReview.start,end:pendingNativeReview.end}], "failure");
        }
    } finally {
        try {
            // Direct editing already uses original; do not reactivate it.
            // Restore only if another sequence (or none) is now active.
            if (original) {
                var activeAtCleanup = app.project.activeSequence;
                if (!activeAtCleanup || String(activeAtCleanup.sequenceID) !== String(original.sequenceID)) {
                    app.project.openSequence(original.sequenceID);
                }
            }
        } catch (openError) { cleanupError += "open original: " + openError.message + "; "; }
    }
    report.cleanupError = cleanupError;
    for (var reviewStatKey in reviewMarkerStats) if (reviewMarkerStats.hasOwnProperty(reviewStatKey)) report[reviewStatKey] = reviewMarkerStats[reviewStatKey];
    if (reviewMarkerStats.reviewMarkerFailureCount) report.ok = false;
    if (cleanupError !== "") report.ok = false;
    return $._PVS._result(report);
};
