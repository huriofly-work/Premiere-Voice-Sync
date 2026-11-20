// Developer-only probe for a disposable sequence. Loading only defines functions.
$._PVSSlowedPieceCapProbe = (function () {
    var TICKS_PER_SECOND = 254016000000, MAX_SAFE_TICKS = 9007199254740991;
    var KEYS = ["video", "audio"], LABELS = ["V1", "A1"], IDS = ["A", "B", "C"];

    function quote(value) {
        return '"' + String(value).replace(/[\x00-\x1f\\"\u2028\u2029]/g, function (c) {
            return "\\u" + ("0000" + c.charCodeAt(0).toString(16)).slice(-4);
        }) + '"';
    }
    function encode(value) {
        var kind = typeof value, parts = [], key;
        if (value === null || kind === "undefined") return "null";
        if (kind === "string") return quote(value);
        if (kind === "number") return isFinite(value) ? String(value) : "null";
        if (kind === "boolean") return value ? "true" : "false";
        if (value instanceof Array) {
            for (var i = 0; i < value.length; i++) parts.push(encode(value[i]));
            return "[" + parts.join(",") + "]";
        }
        for (key in value) if (Object.prototype.hasOwnProperty.call(value, key)) parts.push(quote(key) + ":" + encode(value[key]));
        return "{" + parts.join(",") + "}";
    }
    function ticks(value) {
        var number = Number(value);
        if (value === null || value === "" || !isFinite(number) || Math.abs(number) > MAX_SAFE_TICKS || Math.floor(number) !== number) {
            throw new Error("Could not read safe integer ticks.");
        }
        return number;
    }
    function sourceId(item) {
        return item.projectItem && String(item.projectItem.nodeId || "");
    }
    function snapshot(item, timebase) {
        var start = ticks(item.start.ticks), end = ticks(item.end.ticks);
        var inTicks = ticks(item.inPoint.ticks), outTicks = ticks(item.outPoint.ticks);
        var rawSpeed = Number(item.getSpeed());
        if (!(rawSpeed > 0) || !isFinite(rawSpeed) || outTicks <= inTicks || end <= start) {
            throw new Error("Invalid clip speed, duration or source span.");
        }
        var speed = rawSpeed <= 10 ? rawSpeed : rawSpeed / 100;
        return {
            nodeId: String(item.nodeId), name: String(item.name), sourceId: sourceId(item),
            startFrame: Math.round(start / timebase), endFrame: Math.round(end / timebase),
            durationFrames: Math.round((end - start) / timebase), startTicks: String(start), endTicks: String(end),
            inTicks: String(inTicks), outTicks: String(outTicks),
            speed: speed, rawSpeed: rawSpeed, isSpeedReversed: !!item.isSpeedReversed(),
            // Retimed TrackItems expose speed-divided source coordinates.
            sourceSpanFrames: Math.round((outTicks - inTicks) * speed / timebase)
        };
    }
    function mediaEnd(project, sequence, id) {
        var sequences = project.sequences;
        for (var i = 0; id && sequences && i < sequences.numSequences; i++) {
            var source = sequences[i];
            if (String(source.sequenceID) !== String(sequence.sequenceID) &&
                source.projectItem && String(source.projectItem.nodeId) === id) {
                var duration = ticks(source.end) - ticks(source.zeroPoint);
                if (duration > 0) return ticks(duration);
                break;
            }
        }
        throw new Error("V1 must contain a nested sequence with positive source duration.");
    }
    function linkedOnlyToAudio(links, videoId, audioId) {
        var found = false;
        for (var i = 0; links && i < links.length; i++) {
            var id = String(links[i].nodeId);
            if (id === videoId) continue;
            if (id !== audioId || found) return false;
            found = true;
        }
        return found;
    }
    function context() {
        var project = app.project, sequence = project && project.activeSequence;
        if (!sequence || String(sequence.name).indexOf("PVS Probe") !== 0) throw new Error("Open a disposable sequence named PVS Probe first.");
        var v1 = sequence.videoTracks[0], a1 = sequence.audioTracks[0];
        if (!v1 || !a1 || v1.clips.numItems !== 1 || a1.clips.numItems !== 1) {
            throw new Error("V1 and A1 must each contain exactly one clip.");
        }
        var timebase = ticks(sequence.timebase), fps = TICKS_PER_SECOND / timebase;
        if (fps < 1 || fps > 240 || !isFinite(fps)) throw new Error("Invalid frame rate.");
        var video = v1.clips[0], audio = a1.clips[0], links = video.getLinkedItems();
        var videoBefore = snapshot(video, timebase), audioBefore = snapshot(audio, timebase);
        if (!linkedOnlyToAudio(links, videoBefore.nodeId, audioBefore.nodeId) ||
            videoBefore.sourceId !== audioBefore.sourceId) {
            throw new Error("V1 must be linked only to the matching A1 nest clip.");
        }
        var end = Number(videoBefore.endTicks);
        if (videoBefore.startTicks !== "0" || audioBefore.startTicks !== "0" ||
            videoBefore.endTicks !== audioBefore.endTicks || end % timebase !== 0 ||
            videoBefore.speed !== 1 || audioBefore.speed !== 1 || videoBefore.isSpeedReversed || audioBefore.isSpeedReversed) {
            throw new Error("The linked V1/A1 clips must start at frame 0, end on the same frame, and run forward at 100%.");
        }
        var mediaEndTicks = mediaEnd(project, sequence, videoBefore.sourceId);
        function checkSource(before) {
            if (Number(before.inTicks) < 0 || Number(before.outTicks) > mediaEndTicks ||
                Number(before.outTicks) - Number(before.inTicks) !== end) {
                throw new Error("The nest clips must have source spans matching their timeline duration.");
            }
        }
        checkSource(videoBefore);
        checkSource(audioBefore);
        return { v1: v1, a1: a1, sequence: sequence, before: {
            documentId: String(project.documentID), sequenceId: String(sequence.sequenceID), sequenceName: String(sequence.name),
            fps: fps, ticksPerFrame: timebase, mediaEndTicks: String(mediaEndTicks), video: videoBefore, audio: audioBefore,
            timeline: timeline(sequence)
        } };
    }
    // Same rounded nominal frame rate and duration timecode as setClipSpeed.
    function timecode(frames, fps) {
        var nominal = Math.round(fps), seconds = Math.floor(frames / nominal);
        function pad(value) { return value < 10 ? "0" + value : String(value); }
        return pad(Math.floor(seconds / 3600)) + ":" + pad(Math.floor(seconds / 60) % 60) + ":" +
            pad(seconds % 60) + ":" + pad(frames % nominal);
    }
    function itemPlan(before, original, piece) {
        var timebase = before.ticksPerFrame;
        var sourceIn = Number(original.inTicks) + piece.cutStartFrame * timebase;
        var remaining = Math.floor((Number(before.mediaEndTicks) - sourceIn) / timebase);
        var span = piece.cutEndFrame - piece.cutStartFrame;
        var target = remaining + 56, factor = span / target;
        var targetEnd = (piece.startFrame + target) * timebase;
        if (target <= span || targetEnd > MAX_SAFE_TICKS || sourceIn / factor + target * timebase > MAX_SAFE_TICKS) {
            throw new Error("The planned slowdown is outside the available frame range.");
        }
        return { remainingMediaFrames: remaining, excessFrames: 56, targetFrames: target, exactFactor: factor,
            durationTimecode: timecode(target, before.fps), endTicks: String(targetEnd), ripple: piece.id === "C" };
    }
    function plan(before) {
        var end = before.video.endFrame, gap = Math.ceil(before.fps);
        var length = Math.min(Math.round(10 * before.fps), Math.floor(end / 4));
        if (length < Math.max(2, gap)) throw new Error("The nest needs four pieces of at least one second (and at least two frames each).");
        var variants = [], cuts = [], start = end - 4 * length, lastEndFrame = end;
        // C ripples, so place it after the last clip on every track.
        for (var k = 0; k < before.timeline.length; k++) {
            if (!before.timeline[k].marker) lastEndFrame = Math.max(lastEndFrame, Math.ceil(Number(before.timeline[k].endTicks) / before.ticksPerFrame));
        }
        for (var i = 0; i < IDS.length; i++) {
            var cutStart = end - (4 - i) * length;
            if (cutStart > 0) cuts.push(cutStart);
            if (IDS[i] === "C") start = Math.max(start, lastEndFrame + gap);
            var piece = { id: IDS[i], cutStartFrame: cutStart, cutEndFrame: cutStart + length, startFrame: start };
            piece.video = itemPlan(before, before.video, piece);
            piece.audio = itemPlan(before, before.audio, piece);
            variants.push(piece);
            start = Math.max(end, start + Math.max(piece.video.targetFrames, piece.audio.targetFrames)) + gap;
        }
        var tail = end - length, rippleStart = variants[2].startFrame * before.ticksPerFrame;
        cuts.push(tail);
        for (var j = 0; j < before.timeline.length; j++) {
            var item = before.timeline[j];
            if (!item.marker && Number(item.endTicks) > rippleStart) {
                throw new Error("C must have no trailing clips on any track. Check " + item.track + " near frame " + variants[2].startFrame + ".");
            }
        }
        return { razor: cutList(cuts, before.fps), tailStartFrame: tail, variants: variants };
    }
    function cutList(frames, fps) {
        var cuts = [];
        for (var i = 0; i < frames.length; i++) cuts.push({ frame: frames[i], timecode: timecode(frames[i], fps) });
        return cuts;
    }
    function findClip(track, nodeId) {
        var clips = track.clips;
        for (var i = 0; i < clips.numItems; i++) if (String(clips[i].nodeId) === nodeId) return clips[i];
        return null;
    }
    function findQEClip(track, startTicks, label) {
        var found = null;
        for (var i = 0; i < track.numItems; i++) {
            var candidate = track.getItemAt(i);
            if (candidate && candidate.type === "Clip" && String(candidate.start.ticks) === startTicks) {
                if (found) throw new Error("Multiple QE " + label + " clips match the planned start.");
                found = candidate;
            }
        }
        if (!found) throw new Error("Could not map the planned clip to QE " + label + ".");
        return found;
    }
    function readPiece(track, original, start, end, timebase, label) {
        var clips = track.clips, found = null;
        for (var i = 0; i < clips.numItems; i++) {
            var item = clips[i];
            if (ticks(item.start.ticks) !== start * timebase) continue;
            var current = snapshot(item, timebase);
            if (found || current.sourceId !== original.sourceId || Number(current.endTicks) !== end * timebase ||
                current.speed !== 1 || current.isSpeedReversed ||
                Number(current.inTicks) !== Number(original.inTicks) + start * timebase ||
                Number(current.outTicks) !== Number(original.inTicks) + end * timebase) {
                throw new Error(label + " razor readback differs from the planned source or timeline span at frame " + start + ".");
            }
            found = current;
        }
        if (!found) throw new Error(label + " is missing a razor piece at frame " + start + ".");
        return found;
    }
    function readPartition(state, razor) {
        var original = state.before, timebase = original.ticksPerFrame, pieces = {};
        if (state.v1.clips.numItems !== razor.length + 1 || state.a1.clips.numItems !== razor.length + 1) {
            throw new Error("Linked razor did not produce the planned number of pieces on V1 and A1.");
        }
        var start = 0;
        for (var i = 0; i <= razor.length; i++) {
            var end = i < razor.length ? razor[i].frame : original.video.endFrame;
            pieces[start] = {
                video: readPiece(state.v1, original.video, start, end, timebase, "V1"),
                audio: readPiece(state.a1, original.audio, start, end, timebase, "A1")
            };
            start = end;
        }
        return pieces;
    }
    function requireClip(track, nodeId, label) {
        var item = findClip(track, nodeId);
        if (!item) throw new Error("Could not re-read " + label + " clip " + nodeId + ".");
        return item;
    }
    function remove(track, before, label, completed) {
        requireClip(track, before.nodeId, label).remove(false, false);
        if (findClip(track, before.nodeId)) throw new Error(label + " removal failed at frame " + before.startFrame + ".");
        completed.push({ track: label, startFrame: before.startFrame, endFrame: before.endFrame });
    }
    function time(value) {
        var result = new Time();
        result.ticks = String(ticks(value));
        return result;
    }
    function timeline(sequence) {
        var result = [], groups = [sequence.videoTracks, sequence.audioTracks], prefixes = ["V", "A"];
        for (var g = 0; g < groups.length; g++) {
            var group = groups[g];
            for (var t = 0; t < group.numTracks; t++) {
                var clips = group[t].clips;
                for (var i = 0; i < clips.numItems; i++) {
                    var clip = clips[i];
                    result.push({ track: prefixes[g] + (t + 1), nodeId: String(clip.nodeId),
                        startTicks: String(ticks(clip.start.ticks)), endTicks: String(ticks(clip.end.ticks)) });
                }
            }
        }
        var markers = sequence.markers, marker = markers && markers.getFirstMarker();
        while (marker) {
            result.push({ track: "sequence markers", nodeId: String(marker.guid), marker: true,
                startTicks: String(ticks(marker.start.ticks)), endTicks: String(ticks(marker.end.ticks)) });
            marker = markers.getNextMarker(marker);
        }
        return result;
    }
    function belongsTo(item, variant) {
        return (item.track === "V1" && item.nodeId === variant.video.before.nodeId) ||
            (item.track === "A1" && item.nodeId === variant.audio.before.nodeId);
    }
    function timelineChanges(before, after, variant) {
        var index = {}, changes = [], i, current, key, old;
        for (i = 0; i < before.length; i++) {
            old = before[i];
            if (!variant || !belongsTo(old, variant)) index[old.track + ":" + old.nodeId] = old;
        }
        for (i = 0; i < after.length; i++) {
            current = after[i];
            if (variant && belongsTo(current, variant)) continue;
            key = current.track + ":" + current.nodeId;
            old = index[key];
            delete index[key];
            if (!old || current.startTicks !== old.startTicks || current.endTicks !== old.endTicks) {
                changes.push({ before: old || null, after: current });
            }
        }
        for (key in index) {
            if (Object.prototype.hasOwnProperty.call(index, key)) changes.push({ before: index[key], after: null });
        }
        return changes;
    }
    function clipFor(state, i, before) {
        return requireClip(i === 0 ? state.v1 : state.a1, before.nodeId, LABELS[i]);
    }
    function readTrack(state, i, before) {
        return snapshot(clipFor(state, i, before), state.before.ticksPerFrame);
    }
    function place(state, piece, planned, completed) {
        var timebase = state.before.ticksPerFrame, destination = planned.startFrame * timebase;
        for (var i = 0; i < KEYS.length; i++) {
            var before = piece[KEYS[i]], current = readTrack(state, i, before);
            // A linked move can already have placed the other TrackItem.
            if (Number(current.startTicks) !== destination) {
                if (current.startTicks !== before.startTicks) throw new Error(LABELS[i] + " moved unexpectedly during setup.");
                clipFor(state, i, before).move(time(destination - Number(current.startTicks)));
                completed.push({ track: LABELS[i], variant: planned.id, startFrame: planned.startFrame });
            }
        }
        for (var j = 0; j < KEYS.length; j++) {
            var key = KEYS[j], cut = piece[key], placed = readTrack(state, j, cut);
            if (Number(placed.startTicks) !== destination ||
                Number(placed.endTicks) !== destination + cut.durationFrames * timebase ||
                placed.inTicks !== cut.inTicks || placed.outTicks !== cut.outTicks ||
                placed.sourceId !== cut.sourceId || placed.speed !== cut.speed || placed.isSpeedReversed !== cut.isSpeedReversed) {
                throw new Error(LABELS[j] + " placement changed the planned span for " + planned.id + ".");
            }
            piece[key] = placed;
        }
        var links = clipFor(state, 0, piece.video).getLinkedItems();
        if (!linkedOnlyToAudio(links, piece.video.nodeId, piece.audio.nodeId)) {
            throw new Error("The placed " + planned.id + " V1/A1 pieces must remain linked.");
        }
    }
    function qeTrack(sequence, index) {
        return index === 0 ? sequence.getVideoTrackAt(0) : sequence.getAudioTrackAt(0);
    }
    function qeField(item, field) {
        try {
            var value = item[field];
            if (value === null || typeof value === "undefined") return null;
            if (typeof value === "number" || typeof value === "string") return String(value);
            if (typeof value.ticks !== "undefined") return String(value.ticks);
            if (typeof value.timecode !== "undefined") return String(value.timecode);
        } catch (e) {}
        return null;
    }
    function qeRead(sequence, index, current) {
        if (!sequence) return { error: "QE sequence unavailable for readback." };
        try {
            var item = findQEClip(qeTrack(sequence, index), current.startTicks, LABELS[index]);
            return { start: qeField(item, "start"), end: qeField(item, "end"),
                inPoint: qeField(item, "inPoint") || qeField(item, "in"),
                outPoint: qeField(item, "outPoint") || qeField(item, "out") };
        } catch (e) {
            return { error: String(e.message || e) };
        }
    }
    function qeInOutChanged(before, after) {
        if (before.error || after.error) return null;
        var inKnown = before.inPoint !== null && after.inPoint !== null;
        var outKnown = before.outPoint !== null && after.outPoint !== null;
        if ((inKnown && before.inPoint !== after.inPoint) || (outKnown && before.outPoint !== after.outPoint)) return true;
        return inKnown && outKnown ? false : null;
    }
    function checkRoom(state, variant, planned, items) {
        var start = planned.startFrame * state.before.ticksPerFrame;
        var end = Math.max(Number(planned.video.endTicks), Number(planned.audio.endTicks));
        for (var i = 0; i < items.length; i++) {
            var item = items[i];
            if (item.marker || Number(item.endTicks) <= start || belongsTo(item, variant)) continue;
            if (planned.id === "C" || ((item.track === "V1" || item.track === "A1") && Number(item.startTicks) < end)) {
                throw new Error("Insufficient empty space for " + planned.id + " on " + item.track + ".");
            }
        }
    }
    function measure(result, state, piece, planned, qeSequence) {
        var i, key, entry, current;
        var timebase = state.before.ticksPerFrame, beforeTimeline = timeline(state.sequence);
        for (i = 0; i < KEYS.length; i++) {
            key = KEYS[i];
            var before = piece[key], change = planned[key];
            result[key] = { before: before, plannedChange: change, afterSetSpeed: null, afterRestoreOut: null,
                forcedEndAttempted: false, immediate: null, later: null, inOutChanged: null, qeInOutChanged: null, errors: [] };
            if (encode(readTrack(state, i, before)) !== encode(before)) throw new Error(LABELS[i] + " piece changed during setup.");
            findQEClip(qeTrack(qeSequence, i), before.startTicks, LABELS[i]);
        }
        checkRoom(state, result, planned, beforeTimeline);
        for (i = 0; i < KEYS.length; i++) {
            entry = result[KEYS[i]];
            current = readTrack(state, i, entry.before);
            if (current.startTicks !== entry.before.startTicks) throw new Error(LABELS[i] + " start changed before setSpeed.");
            var qeItem = findQEClip(qeTrack(qeSequence, i), current.startTicks, LABELS[i]);
            var request = entry.plannedChange;
            try {
                // Keep the host's factor/timecode and first two flags. Published
                // QE usage identifies the fifth argument as ripple edit.
                if (!qeItem.setSpeed(request.exactFactor, request.durationTimecode, false, false, request.ripple)) {
                    throw new Error("QE setSpeed returned false.");
                }
            } catch (e) {
                entry.errors.push("setSpeed: " + String(e.message || e));
            }
        }
        for (i = 0; i < KEYS.length; i++) {
            entry = result[KEYS[i]];
            entry.afterSetSpeed = readTrack(state, i, entry.before);
            entry.capRuleHeld = entry.afterSetSpeed.durationFrames === entry.plannedChange.remainingMediaFrames;
        }
        for (i = 0; planned.id !== "C" && i < KEYS.length; i++) {
            entry = result[KEYS[i]];
            current = readTrack(state, i, entry.before);
            if (current.startTicks !== entry.before.startTicks) throw new Error(LABELS[i] + " start changed before correction.");
            if (entry.errors.length) continue;
            restoreEdges(state, i, entry, current, planned.id === "B", timebase);
        }
        for (i = 0; i < KEYS.length; i++) {
            entry = result[KEYS[i]];
            entry.immediate = readTrack(state, i, entry.before);
            entry.qeImmediate = qeRead(qeSequence, i, entry.immediate);
        }
        result.otherTimelineChanges = timelineChanges(beforeTimeline, timeline(state.sequence), result);
        result.summary = summarize(result);
    }
    function restoreEdges(state, i, entry, current, restoreOut, timebase) {
        var targetTicks = entry.plannedChange.targetFrames * timebase;
        var targetEnd = Number(current.startTicks) + targetTicks;
        if (restoreOut && (Number(current.endTicks) < targetEnd || !spanPreserved(entry, current))) {
            try {
                clipFor(state, i, entry.before).outPoint = time(Number(current.inTicks) + targetTicks);
            } catch (outError) {
                entry.errors.push("outPoint: " + String(outError.message || outError));
            }
            current = entry.afterRestoreOut = readTrack(state, i, entry.before);
            if (current.startTicks !== entry.before.startTicks) throw new Error(LABELS[i] + " start changed after restoring Out.");
        }
        if (Number(current.endTicks) < targetEnd) {
            entry.forcedEndAttempted = true;
            try {
                clipFor(state, i, entry.before).end = time(targetEnd);
            } catch (endError) {
                entry.errors.push("end: " + String(endError.message || endError));
            }
        }
    }
    function reached(entry, readback) {
        return readback.startTicks === entry.before.startTicks && readback.endTicks === entry.plannedChange.endTicks;
    }
    function spanPreserved(entry, readback) {
        return readback.sourceSpanFrames === entry.before.sourceSpanFrames;
    }
    function summarize(variant) {
        var v = variant.video, a = variant.audio, laterRead = v.later && a.later;
        return {
            reachedTarget: laterRead ? reached(v, v.later) && reached(a, a.later) : reached(v, v.immediate) && reached(a, a.immediate),
            sourceSpanPreservedImmediate: spanPreserved(v, v.immediate) && spanPreserved(a, a.immediate),
            sourceSpanPreservedLater: laterRead ? spanPreserved(v, v.later) && spanPreserved(a, a.later) : null,
            anythingElseMoved: variant.otherTimelineChanges.length > 0
        };
    }
    function run(expected) {
        var state = context(), change = plan(state.before);
        if (expected !== encode(state.before)) throw new Error("Sequence or clip values changed after preview. Run the command again.");
        var report = { ok: false, setup: { before: state.before, plannedChange: change,
            cutsCompleted: [], removalsCompleted: [], movesCompleted: [] }, variants: [] };
        try {
            app.enableQE();
            var sequence = qe.project.getActiveSequence();
            if (!sequence || !qeTrack(sequence, 0) || !qeTrack(sequence, 1)) throw new Error("Could not access QE V1 and A1.");
            findQEClip(qeTrack(sequence, 0), "0", "V1");
            findQEClip(qeTrack(sequence, 1), "0", "A1");
            for (var i = 0; i < change.razor.length; i++) {
                var cut = change.razor[i];
                if (!qeTrack(sequence, 0).razor(cut.timecode, true, false)) throw new Error("Linked razor failed at frame " + cut.frame + ".");
                report.setup.cutsCompleted.push(cut.frame);
            }
            var pieces = readPartition(state, change.razor), tail = pieces[change.tailStartFrame];
            remove(state.v1, tail.video, "V1", report.setup.removalsCompleted);
            remove(state.a1, tail.audio, "A1", report.setup.removalsCompleted);
            if (state.v1.clips.numItems !== change.razor.length || state.a1.clips.numItems !== change.razor.length) {
                throw new Error("V1 or A1 clip count changed unexpectedly during removal.");
            }
            for (i = change.variants.length - 1; i >= 0; i--) {
                var planned = change.variants[i];
                place(state, pieces[planned.cutStartFrame], planned, report.setup.movesCompleted);
            }
            for (i = 0; i < change.variants.length; i++) {
                var trial = change.variants[i], result = { id: trial.id, startFrame: trial.startFrame };
                report.variants.push(result);
                measure(result, state, pieces[trial.cutStartFrame], trial, sequence);
            }
            report.timelineAfterWrites = timeline(state.sequence);
            report.ok = true;
        } catch (e) {
            report.error = String(e.message || e);
        }
        return report;
    }
    function reread(report) {
        var before = report.setup.before;
        var project = app.project, sequence = project && project.activeSequence;
        if (!sequence || String(project.documentID) !== before.documentId ||
            String(sequence.sequenceID) !== before.sequenceId || String(sequence.name) !== before.sequenceName ||
            ticks(sequence.timebase) !== before.ticksPerFrame) {
            throw new Error("Project or sequence changed before the later read. Inspect the immediate report.");
        }
        var state = { before: before, v1: sequence.videoTracks[0], a1: sequence.audioTracks[0] };
        var qeSequence = null;
        try { qeSequence = qe.project.getActiveSequence(); } catch (qeError) {}
        for (var i = 0; i < report.variants.length; i++) {
            var variant = report.variants[i];
            for (var j = 0; j < KEYS.length; j++) {
                var entry = variant[KEYS[j]];
                try {
                    entry.later = readTrack(state, j, entry.before);
                    entry.qeLater = qeRead(qeSequence, j, entry.later);
                    entry.inOutChanged = entry.immediate.inTicks !== entry.later.inTicks ||
                        entry.immediate.outTicks !== entry.later.outTicks;
                    entry.qeInOutChanged = qeInOutChanged(entry.qeImmediate, entry.qeLater);
                } catch (e) {
                    entry.errors.push("Later read: " + String(e.message || e));
                }
                if (entry.errors.length) report.ok = false;
            }
            variant.summary = summarize(variant);
        }
        report.timelineChangesBetweenCalls = timelineChanges(report.timelineAfterWrites, timeline(sequence), null);
        delete report.timelineAfterWrites;
        return report;
    }
    function guarded(action) {
        try { return encode(action()); }
        catch (e) { return encode({ ok: false, error: String(e.message || e) }); }
    }
    return {
        preview: function () {
            return guarded(function () {
                var before = context().before;
                return { ok: true, before: before, plannedChange: plan(before), expected: encode(before) };
            });
        },
        run: function (expected) { return guarded(function () { return run(expected); }); },
        reread: function (report) { return guarded(function () { return reread(report); }); }
    };
}());
