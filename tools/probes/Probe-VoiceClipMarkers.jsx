// Developer-only native feasibility probe. Loading this file only defines functions.
// No dependency on host.jsx or its JSON serializer. All times are seconds.
$._PVSProbe = (function () {
    var TAG = "[PremiereVoiceSync:probe:v1]";
    var NOTES = "probe clip marker\n" + TAG;

    function quote(value) {
        return '"' + String(value).replace(/[\x00-\x1f\\"\u2028\u2029]/g, function (c) {
            var hex = c.charCodeAt(0).toString(16);
            return "\\u" + ("0000" + hex).slice(-4);
        }) + '"';
    }
    function tinyJSON(value) {
        var parts = [], i, key, kind = typeof value;
        if (value === null || kind === "undefined") return "null";
        if (kind === "string") return quote(value);
        if (kind === "number") return isFinite(value) ? String(value) : "null";
        if (kind === "boolean") return value ? "true" : "false";
        if (value instanceof Array) {
            for (i = 0; i < value.length; i++) parts.push(tinyJSON(value[i]));
            return "[" + parts.join(",") + "]";
        }
        for (key in value) if (Object.prototype.hasOwnProperty.call(value, key)) {
            parts.push(quote(key) + ":" + tinyJSON(value[key]));
        }
        return "{" + parts.join(",") + "}";
    }
    function encode(value) {
        if (typeof JSON !== "undefined" && typeof JSON.stringify === "function") {
            try { return JSON.stringify(value); } catch (ignoreJSON) {}
        }
        return tinyJSON(value);
    }
    function guarded(action) {
        try { return encode(action()); }
        catch (e) { return encode({ ok: false, error: String(e.message || e) }); }
    }
    function index(value, fallback, label) {
        if (value === undefined) value = fallback;
        if (typeof value !== "number" || !isFinite(value) || value < 0 || Math.floor(value) !== value) {
            throw new Error("Invalid " + label + ". Use a zero-based integer.");
        }
        return value;
    }
    function seconds(time) {
        var n = Number(time && time.seconds !== undefined ? time.seconds : time);
        if (time === null || time === undefined || !isFinite(n)) throw new Error("Unreadable time.");
        return n;
    }
    function active() {
        var seq = app.project && app.project.activeSequence;
        if (!seq) throw new Error("No active sequence.");
        return seq;
    }
    function sequenceInfo(seq) {
        var fps = 254016000000 / Number(seq.timebase);
        return { name: String(seq.name || ""), id: String(seq.sequenceID || ""),
            frameRate: isFinite(fps) && fps > 0 ? fps : null };
    }
    function audioTrack(seq, trackIndex) {
        if (!seq.audioTracks || trackIndex >= seq.audioTracks.numTracks) throw new Error("Audio track not found.");
        return seq.audioTracks[trackIndex];
    }
    function target(trackIndex, clipIndex) {
        var seq = active(), ti = index(trackIndex, 1, "trackIndex"), ci = index(clipIndex, undefined, "clipIndex");
        var track = audioTrack(seq, ti);
        if (ci >= track.clips.numItems) throw new Error("Clip not found.");
        var clip = track.clips[ci], item = clip.projectItem;
        if (!item || typeof item.getMarkers !== "function") throw new Error("ProjectItem.getMarkers unavailable.");
        return { seq: seq, clip: clip, item: item, markers: item.getMarkers() };
    }
    function speedInfo(clip) {
        var raw = null, factor = null, reversed = null;
        try {
            raw = Number(clip.getSpeed());
            // Same ratio/percent normalization as host.jsx readSpeedPercent.
            if (isFinite(raw) && raw > 0) factor = raw <= 10 ? raw : raw / 100;
            else raw = null;
        } catch (ignoreSpeed) {}
        try { reversed = !!clip.isSpeedReversed(); } catch (ignoreReverse) {}
        return { raw: raw, factor: factor, reversed: reversed };
    }
    function projectInfo(item) {
        if (!item) return null;
        return { name: String(item.name || ""), nodeId: String(item.nodeId || ""),
            treePath: String(item.treePath || ""), getMarkers: typeof item.getMarkers === "function" };
    }
    function clipInfo(clip, ci) {
        return { index: ci, name: String(clip.name || ""), nodeId: String(clip.nodeId || ""),
            start: seconds(clip.start), end: seconds(clip.end), inPoint: seconds(clip.inPoint),
            outPoint: seconds(clip.outPoint), speed: speedInfo(clip), projectItem: projectInfo(clip.projectItem) };
    }
    function markerRows(collection) {
        var rows = [], marker = collection.getFirstMarker();
        while (marker) {
            if (rows.length >= 100000) throw new Error("Marker enumeration limit exceeded.");
            rows.push({ ref: marker, guid: String(marker.guid || ""), start: seconds(marker.start),
                end: seconds(marker.end), name: String(marker.name || ""),
                comments: String(marker.comments || ""), type: String(marker.type || "") });
            marker = collection.getNextMarker(marker);
        }
        return rows;
    }
    function tagged(row) { return row.comments.indexOf(TAG) !== -1; }
    function sameMarker(a, b) { return a.ref === b.ref || (a.guid && b.guid && a.guid === b.guid); }
    function sameItem(a, b) {
        if (!a || !b) return false;
        if (a === b) return true;
        if (a.nodeId && b.nodeId) return String(a.nodeId) === String(b.nodeId);
        return !!(a.treePath && b.treePath && String(a.treePath) === String(b.treePath));
    }
    function uses(seq, item, sourceTime) {
        var result = [], groups = [seq.videoTracks, seq.audioTracks], kinds = ["video", "audio"];
        for (var g = 0; g < groups.length; g++) {
            var tracks = groups[g];
            if (!tracks) continue;
            for (var ti = 0; ti < tracks.numTracks; ti++) {
                var clips = tracks[ti].clips;
                for (var ci = 0; ci < clips.numItems; ci++) if (sameItem(clips[ci].projectItem, item)) {
                    var row = clipInfo(clips[ci], ci), speed = row.speed;
                    row.trackType = kinds[g]; row.trackIndex = ti;
                    row.insideSourceRange = sourceTime >= row.inPoint && sourceTime < row.outPoint;
                    row.expectedTimelineTime = speed.factor !== null && speed.reversed !== true ?
                        row.start + (sourceTime - row.inPoint) / speed.factor : null;
                    row.mappingNote = speed.reversed === true ? "Reverse speed: mapping unsupported." :
                        (speed.factor === null ? "Speed unknown." : "Formula prediction; verify in Premiere. No time-remapping proof.");
                    result.push(row);
                }
            }
        }
        return result;
    }
    function publicMarker(row, seq, item) {
        return { guid: row.guid, start: row.start, end: row.end, name: row.name, comments: row.comments,
            type: row.type, trackItems: uses(seq, item, row.start) };
    }
    function probeRows(rows, seq, item) {
        var result = [];
        for (var i = 0; i < rows.length; i++) if (tagged(rows[i])) result.push(publicMarker(rows[i], seq, item));
        return result;
    }
    return {
        list: function (trackIndex) { return guarded(function () {
            var seq = active(), ti = index(trackIndex, 1, "trackIndex"), track = audioTrack(seq, ti), clips = [];
            for (var ci = 0; ci < track.clips.numItems; ci++) {
                var clip = track.clips[ci], row = clipInfo(clip, ci);
                row.markerCount = null; row.probeMarkerCount = null;
                if (row.projectItem && row.projectItem.getMarkers) {
                    var markers = markerRows(clip.projectItem.getMarkers()), count = 0;
                    for (var mi = 0; mi < markers.length; mi++) if (tagged(markers[mi])) count++;
                    row.markerCount = markers.length; row.probeMarkerCount = count;
                }
                clips.push(row);
            }
            return { ok: true, sequence: sequenceInfo(seq), trackIndex: ti, clips: clips };
        }); },
        create: function (trackIndex, clipIndex, offsetSeconds) { return guarded(function () {
            var t = target(trackIndex, clipIndex), sourceTime = seconds(t.clip.inPoint) + offsetSeconds;
            if (typeof offsetSeconds !== "number" || !isFinite(offsetSeconds) ||
                sourceTime < seconds(t.clip.inPoint) || sourceTime >= seconds(t.clip.outPoint)) {
                throw new Error("Offset must put the marker inside [inPoint, outPoint); offset is SOURCE seconds.");
            }
            // Finish all reads/validation before creating anything; avoid occupied source positions.
            uses(t.seq, t.item, sourceTime);
            var before = markerRows(t.markers), i;
            for (i = 0; i < before.length; i++) if (Math.abs(before[i].start - sourceTime) < 0.000000001) {
                throw new Error("Source position already occupied. Choose another offset.");
            }
            var marker = t.markers.createMarker(sourceTime);
            if (!marker) throw new Error("createMarker returned no marker; inspect before retry.");
            var identity = { ref: marker, guid: String(marker.guid || "") };
            for (i = 0; i < before.length; i++) if (sameMarker(before[i], identity)) {
                throw new Error("createMarker returned an existing marker; left untouched.");
            }
            if (String(marker.name || "") || String(marker.comments || "") || String(marker.type || "Comment") !== "Comment") {
                throw new Error("createMarker returned a nonblank/non-Comment marker; left untouched.");
            }
            // Tag first so a later metadata failure can still be cleaned by explicit remove.
            marker.comments = NOTES;
            marker.name = "PVS PROBE";
            var after = markerRows(t.markers), created = null;
            for (i = 0; i < after.length; i++) if (sameMarker(after[i], identity)) created = after[i];
            if (!created || created.comments !== NOTES || created.name !== "PVS PROBE" || created.type !== "Comment") {
                throw new Error("Marker readback failed; inspect and remove tagged markers before retry. No automatic cleanup.");
            }
            return { ok: true, sequence: sequenceInfo(t.seq), projectItem: projectInfo(t.item),
                requestedSourceTime: sourceTime, sourceTimeDelta: created.start - sourceTime,
                marker: publicMarker(created, t.seq, t.item) };
        }); },
        read: function (trackIndex, clipIndex) { return guarded(function () {
            var t = target(trackIndex, clipIndex), rows = markerRows(t.markers);
            return { ok: true, sequence: sequenceInfo(t.seq), projectItem: projectInfo(t.item),
                markers: probeRows(rows, t.seq, t.item) };
        }); },
        remove: function (trackIndex, clipIndex) { return guarded(function () {
            var t = target(trackIndex, clipIndex), rows = markerRows(t.markers), attempted = 0;
            // Snapshot first: do not walk an iterator while deleting its current marker.
            for (var i = 0; i < rows.length; i++) if (tagged(rows[i]) &&
                String(rows[i].ref.comments || "").indexOf(TAG) !== -1) {
                t.markers.deleteMarker(rows[i].ref); attempted++;
            }
            var after = markerRows(t.markers), remaining = probeRows(after, t.seq, t.item);
            return { ok: remaining.length === 0, error: remaining.length ? "Tagged markers remain after deletion." : null,
                attempted: attempted, remaining: remaining.length, markers: remaining, totalMarkerCount: after.length };
        }); }
    };
}());
