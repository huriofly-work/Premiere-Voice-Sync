// Build-only ES3 helpers inserted into the generated executor's closure.
// No native writes here. Keep the baseline helpers and edit statements intact.
var diagnosticGroupIds = [];
var diagnosticDirtyItems = {};
function diagnosticNewQeStats() {
    // Keep old counters at zero for existing log readers; no index is built.
    return { queries: 0, hits: 0, builds: 0, fallbacks: 0, milliseconds: 0, reuses: 0, countChanges: 0, candidateMisses: 0, invalidLayouts: 0, itemReads: 0, earlyHits: 0, nearestScans: 0 };
}
var diagnosticQeStats = diagnosticNewQeStats();
function diagnosticSnapshot(sequence, collectItems) {
    var rows = [String(sequence.sequenceID)], byId = {};
    var layout = [], positions = {}, clipTotal = 0, uniqueIds = true;
    var kinds = [sequence.videoTracks, sequence.audioTracks];
    for (var kind = 0; kind < kinds.length; kind++) {
        var tracks = kinds[kind], trackCount = tracks.numTracks;
        layout[kind] = [];
        for (var trackIndex = 0; trackIndex < trackCount; trackIndex++) {
            var clips = tracks[trackIndex].clips, clipCount = clips.numItems;
            var ids = [];
            for (var clipIndex = 0; clipIndex < clipCount; clipIndex++) {
                var clip = clips[clipIndex], id = String(clip.nodeId);
                if (positions["n" + id] !== undefined) uniqueIds = false;
                positions["n" + id] = rows.length;
                ids.push(id); clipTotal++;
                rows.push(diagnosticClipRow(kind, trackIndex, clip, id));
                if (collectItems) byId[id] = clip;
            }
            layout[kind][trackIndex] = ids;
        }
    }
    return { signature: rows.join("|"), byId: byId, rows: rows, layout: layout, positions: positions, uniqueIds: uniqueIds, clipCount: clipTotal, strategy: "full" };
}
function diagnosticClipRow(kind, trackIndex, clip, id) {
    var start = clip.start, end = clip.end, sourceIn = clip.inPoint, sourceOut = clip.outPoint;
    return kind + ":" + trackIndex + ":" + id + ":" + String(start.ticks) + ":" + String(end.ticks) + ":" + String(sourceIn.ticks) + ":" + String(sourceOut.ticks) + ":" + String(readSpeedPercent(clip));
}
function diagnosticTouch(item) {
    if (diagnosticFast) diagnosticDirtyItems["n" + String(item.nodeId)] = true;
}
function diagnosticSnapshotAfter(sequence, before, mode) {
    function full(fallback) {
        var value = diagnosticSnapshot(sequence, false);
        value.strategy = fallback ? "full-fallback" : "full";
        value.detailReads = value.clipCount;
        return value;
    }
    // Only generated, explicitly reviewed speed/marker loops are eligible.
    // Structural edits, moves, setup, captions and final audit always rescan.
    if (mode !== "speed" && mode !== "read-only") return full(false);
    if (!before || !before.uniqueIds || String(sequence.sequenceID) !== before.rows[0]) return full(true);
    var kinds = [sequence.videoTracks, sequence.audioTracks], rows = before.rows.slice(0), changed = {}, updated = 0;
    for (var kind = 0; kind < kinds.length; kind++) {
        var tracks = kinds[kind], trackCount = tracks.numTracks;
        if (trackCount !== before.layout[kind].length) return full(true);
        for (var trackIndex = 0; trackIndex < trackCount; trackIndex++) {
            var clips = tracks[trackIndex].clips, count = clips.numItems, expectedIds = before.layout[kind][trackIndex];
            if (count !== expectedIds.length) return full(true);
            for (var index = 0; index < count; index++) {
                // Verify every ID/order using fresh native items; the returned
                // post-snapshot retains no native item proxies. All source/speed fields
                // of every clip are still checked BEFORE the next batch.
                var item = clips[index], id = String(item.nodeId), key = "n" + id;
                if (id !== expectedIds[index]) return full(true);
                if (mode === "speed" && diagnosticDirtyItems[key]) {
                    rows[before.positions[key]] = diagnosticClipRow(kind, trackIndex, item, id);
                    changed[key] = true; updated++;
                }
            }
        }
    }
    for (var dirtyKey in diagnosticDirtyItems) {
        if (diagnosticDirtyItems.hasOwnProperty(dirtyKey) && !changed[dirtyKey]) return full(true);
    }
    return { signature: rows.join("|"), strategy: mode === "speed" ? "incremental-speed" : "read-only", detailReads: updated };
}
function diagnosticRebind(sequence, snapshot) {
    var groups = [videoPieces, audioPieces, allVoicePieces, speechPieces];
    for (var groupIndex = 0; groupIndex < groups.length; groupIndex++) {
        var group = groups[groupIndex];
        if (!group) continue;
        var cached = diagnosticGroupIds[groupIndex];
        if (!cached || cached.array !== group || cached.ids.length !== group.length) {
            cached = { array: group, ids: [] };
            for (var initialIndex = 0; initialIndex < group.length; initialIndex++) {
                // A removed native proxy must never be touched, even for nodeId.
                cached.ids.push(groupIndex === 2 && removeVoice !== undefined && initialIndex > removeVoice ? "" : String(group[initialIndex].nodeId));
            }
            diagnosticGroupIds[groupIndex] = cached;
        }
        for (var index = 0; index < group.length; index++) {
            if (groupIndex === 2 && removeVoice !== undefined && index > removeVoice) continue;
            var fresh = snapshot.byId[cached.ids[index]];
            if (fresh) group[index] = fresh;
        }
    }
    if (tailItems) for (var tailIndex = 0; tailIndex < tailItems.length; tailIndex++) {
        var tail = snapshot.byId[String(tailItems[tailIndex].Item.nodeId)];
        if (tail) tailItems[tailIndex].Item = tail;
    }
    if (typeof cleanupOwners !== "undefined" && cleanupOwners && Number(cleanupOwnerIndex || 0) < cleanupOwners.length) {
        for (var cleanupIndex = cleanupOwnerIndex || 0; cleanupIndex < cleanupOwners.length; cleanupIndex++) {
            var ownerItem = snapshot.byId[cleanupOwners[cleanupIndex].NodeId];
            if (!ownerItem) throw new Error("DIAGNOSTIC_MARKER_OWNER_MISSING");
            cleanupOwners[cleanupIndex].Item = ownerItem;
        }
    }
    if (qeSequence) {
        qeSequence = qe.project.getActiveSequence();
        qeVideoTrack = qeSequence.getVideoTrackAt(0);
        qeAudioTrack = qeSequence.getAudioTrackAt(linkedTrackIndex);
        if (qeVoiceTrack) qeVoiceTrack = qeSequence.getAudioTrackAt(voiceTrackIndex);
    }
}
function diagnosticQEClipAtTicks(track, ticks, tolerance, trackKey) {
    var started = (new Date()).getTime();
    diagnosticQeStats.queries++;
    try {
        if (!diagnosticFast || typeof trackKey !== "string" || !/^(V:0|A:[0-9]+)$/.test(trackKey)) {
            diagnosticQeStats.fallbacks++;
            return $._PVS._findQEClipAtTicks(track, ticks, tolerance);
        }
        // Read CURRENT items on every query; setSpeed can insert/remove gaps.
        // An exact match has distance zero, so no later item can be nearer.
        // Returning the FIRST exact match also preserves the legacy tie rule,
        // even for duplicate/unordered starts. Never early-return a near match.
        var count = track.numItems, target = Number(ticks);
        var best = null, bestDistance = Number.MAX_VALUE;
        for (var itemIndex = 0; itemIndex < count; itemIndex++) {
            var item = track.getItemAt(itemIndex);
            diagnosticQeStats.itemReads++;
            try {
                if (item.type !== "Clip") continue;
                var distance = Math.abs(Number(item.start.ticks) - target);
                if (distance < bestDistance) { best = item; bestDistance = distance; }
                if (distance === 0 && distance <= tolerance) {
                    diagnosticQeStats.hits++;
                    diagnosticQeStats.earlyHits++;
                    return item;
                }
            } catch (ignoreItemFields) {}
        }
        // Full nearest-start scan, including the original first-item tie rule.
        diagnosticQeStats.nearestScans++;
        diagnosticQeStats.fallbacks++;
        return bestDistance <= tolerance ? best : null;
    } finally { diagnosticQeStats.milliseconds += (new Date()).getTime() - started; }
}
