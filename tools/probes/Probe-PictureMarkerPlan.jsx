// Developer-only read-only probe. Loading defines functions without native access.
$._PVSPictureMarkerPlanProbe = (function () {
    var TICKS = 254016000000;
    function quote(value) {
        return '"' + String(value).replace(/[\x00-\x1f\\"\u2028\u2029]/g, function (c) {
            return "\\u" + ("0000" + c.charCodeAt(0).toString(16)).slice(-4);
        }) + '"';
    }
    function encode(value) {
        var kind = typeof value, parts = [], key, i;
        if (value === null || kind === "undefined") return "null";
        if (kind === "string") return quote(value);
        if (kind === "number") return isFinite(value) ? String(value) : "null";
        if (kind === "boolean") return value ? "true" : "false";
        if (value instanceof Array) {
            for (i = 0; i < value.length; i++) parts.push(encode(value[i]));
            return "[" + parts.join(",") + "]";
        }
        for (key in value) if (Object.prototype.hasOwnProperty.call(value, key)) parts.push(quote(key) + ":" + encode(value[key]));
        return "{" + parts.join(",") + "}";
    }
    function guarded(action) {
        try { return encode(action()); }
        catch (e) { return encode({ ok: false, error: String(e.message || e) }); }
    }
    // Replicated host helpers. The offline parity test compares these with host.jsx.
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
    function near(buckets, seconds, tolerance, radius) {
        var result = [], base = Math.floor(seconds / tolerance);
        radius = radius || tolerance;
        var reach = Math.ceil(radius / tolerance);
        for (var b = base - reach; b <= base + reach; b++) {
            var values = buckets["p" + b] || [];
            for (var i = 0; i < values.length; i++) if (Math.abs(values[i].seconds - seconds) < radius) result.push(values[i]);
        }
        return result;
    }
    function available(g, seconds) {
        if (!inScope(g, seconds) || near(g.reserved, seconds, g.tolerance).length) return false;
        if (g.peerReservations && near(g.peerReservations, seconds, g.tolerance).length) return false;
        var rows = near(g.positions, seconds, g.tolerance), count = 0;
        for (var i = 0; i < rows.length; i++) { if (!owned(g, rows[i])) return false; count++; }
        return count <= 1;
    }
    // Choose on the timeline grid before mapping into ProjectItem seconds.
    function point(g, start, end, fps, map) {
        var first = Math.ceil(start * fps - 0.0000001), last = Math.ceil(end * fps - 0.0000001) - 1;
        if (first > last) return null;
        var middle = Math.max(first, Math.min(last, Math.round((start + end) * fps / 2 + 0.0000001)));
        function inside(seconds) {
            var t = map ? map.timeline(seconds) : seconds;
            return t >= start - 0.0000001 / fps && t < end - 0.0000001 / fps;
        }
        function attempt(frame) {
            var t = frame / fps, seconds = map ? map.source(t) : t;
            if (!available(g, seconds)) return null;
            var halfFrame = (map ? map.speed : 1) / fps / 2;
            return { seconds: seconds, end: seconds, positionTolerance: halfFrame, verify: function (actual, actualEnd) {
                return actualEnd !== null && inside(actual) && inside(actualEnd) &&
                    Math.abs(actualEnd - actual) <= g.tolerance / 2 &&
                    Math.abs(actual - seconds) <= halfFrame;
            } };
        }
        for (var d = 0; middle + d <= last || middle - d >= first; d++) {
            var hit = middle + d <= last ? attempt(middle + d) : null;
            if (!hit && d && middle - d >= first) hit = attempt(middle - d);
            if (hit) return hit;
        }
        return null;
    }
    function add(g, spec) {
        if (spec.end !== undefined && (!isFinite(spec.end) || spec.end < spec.seconds)) throw new Error("Invalid marker duration.");
        if (typeof spec.name !== "string" || typeof spec.comments !== "string" || !owned(g, { seconds: spec.seconds, name: spec.name, comments: spec.comments, type: "Comment" }) || !isFinite(spec.color) || Math.floor(spec.color) !== spec.color || spec.color < 0 || spec.color > 7) throw new Error("Invalid owned marker request.");
        if (!isFinite(spec.seconds) || !available(g, spec.seconds)) throw new Error("Marker position occupied or outside scope.");
        function reserve(seconds) {
            var key = "p" + Math.floor(seconds / g.tolerance);
            if (!g.reserved[key]) g.reserved[key] = [];
            g.reserved[key].push({ seconds: seconds });
        }
        // A host-rounded point can be farther from the grid than the collision tolerance.
        if (g.allowMove && spec.positionTolerance && !near(g.positions, spec.seconds, g.tolerance).length) {
            var candidates = near(g.positions, spec.seconds, g.tolerance, spec.positionTolerance);
            for (var i = 0; i < candidates.length; i++) {
                var row = candidates[i];
                if (row.name === spec.name && row.comments === spec.comments && spec.verify(row.seconds, row.seconds) && available(g, row.seconds)) {
                    reserve(spec.seconds);
                    spec.seconds = row.seconds; spec.end = row.seconds;
                    break;
                }
            }
        }
        g.desired.push(spec);
        reserve(spec.seconds);
    }
    function speedFactor(item) {
        try {
            if (!item || typeof item.getSpeed !== "function") return null;
            var raw = item.getSpeed();
            if (raw === null || raw === undefined || raw === "") return null;
            var speed = Number(raw);
            if (!isFinite(speed) || speed <= 0) return null;
            return speed <= 10 ? speed : speed / 100;
        } catch (ignoreSpeedRead) { return null; }
    }
    function clipMarkerMapping(item, allowNested) {
        try {
            if (!item || !item.projectItem || typeof item.projectItem.getMarkers !== "function" || typeof item.getSpeed !== "function") return null;
            if (!allowNested && item.projectItem.isSequence && item.projectItem.isSequence()) return null;
            if (item.isSpeedReversed && item.isSpeedReversed()) return null;
            var speed = speedFactor(item);
            if (speed === null) return null;
            var components = item.components;
            if (components) for (var c = 0; c < (components.numItems === undefined ? components.length : components.numItems); c++) {
                var component = components[c];
                if (/time[\s_-]*remap/i.test(String(component.matchName || "") + " " + String(component.displayName || ""))) {
                    // No voice time-remap mapping was proven by #34, including a
                    // static remap. Existing V1 nest warnings retain their adapter.
                    if (!allowNested) return null;
                    // Premiere may expose the built-in static effect too. Only a
                    // readable, entirely non-varying effect is a constant mapping.
                    var properties = component.properties;
                    if (!properties || !properties.numItems) return null;
                    for (var p = 0; p < properties.numItems; p++) if (typeof properties[p].isTimeVarying !== "function" || properties[p].isTimeVarying()) return null;
                }
            }
            var start = Number(item.start.seconds), end = Number(item.end.seconds), input = Number(item.inPoint.seconds), output = Number(item.outPoint.seconds);
            if (!isFinite(start) || !isFinite(end) || !isFinite(input) || !isFinite(output) || start < 0 || input < 0 || end <= start || output <= input) return null;
            return { start: start, end: end, input: input, speed: speed,
                source: function (t) { return (t - start + input) * speed; },
                timeline: function (m) { return start + m / speed - input; } };
        } catch (ignoreMapping) { return null; }
    }
    function markerKind(kind, workflow) {
        var name = "VOICE SYNC - " + kind;
        var tag = "[PremiereVoiceSync:" + kind.toLowerCase() + (kind === "Caption" ? ":" + workflow : "") + "]";
        return { name: name, tag: tag, owns: function (row) {
            if (row.type !== "Comment" || row.name !== name) return false;
            var comments = String(row.comments || "");
            return comments.substring(comments.lastIndexOf("\n") + 1) === tag;
        } };
    }
    var pictureOwner = markerKind("Video").owns;
    var voiceOwner = markerKind("Voice").owns;
    var editCaptionOwner = markerKind("Caption", "edit").owns;
    var captionsCaptionOwner = markerKind("Caption", "captions").owns;
    function sample(time) {
        var value = time && time.seconds !== undefined ? time.seconds : time;
        var ticks = null;
        try { if (time) ticks = time.ticks; } catch (ignoreTicks) {}
        var seconds = value === null || value === undefined || value === "" ? null : Number(value);
        return { seconds: isFinite(seconds) ? seconds : null,
            ticks: ticks === undefined || ticks === null || ticks === "" ? null : String(ticks) };
    }
    function timebaseOf(sequence) {
        var ticks = Number(sequence.timebase);
        return isFinite(ticks) && ticks > 0 && Math.floor(ticks) === ticks ? String(sequence.timebase) : null;
    }
    function nestTiming(project, nodeId) {
        var found = null;
        if (!nodeId) return null;
        try {
            var sequences = project.sequences;
            for (var i = 0; sequences && i < sequences.numSequences; i++) {
                try {
                    var seq = sequences[i], item = seq && seq.projectItem;
                    if (!item || String(item.nodeId) !== nodeId) continue;
                    var timebase = timebaseOf(seq);
                    if (!timebase || found) return null;
                    found = { sequenceId: String(seq.sequenceID || ""), timebase: timebase, fps: TICKS / Number(timebase) };
                } catch (unreadableSequence) {}
            }
        } catch (unreadableCollection) { return null; }
        return found;
    }
    function gridDelta(ticks, timebase) {
        if (ticks === null || !timebase || !isFinite(Number(ticks))) return null;
        var remainder = Number(ticks) % Number(timebase);
        return remainder - Math.round(remainder / Number(timebase)) * Number(timebase);
    }
    function readOwner(item) {
        var collection = item.getMarkers(), rows = [], other = 0;
        if (!collection) throw new Error("ProjectItem marker collection unavailable.");
        var marker = collection.getFirstMarker();
        while (marker) {
            if (rows.length >= 10000) throw new Error("Marker enumeration limit exceeded.");
            var name = String(marker.name || ""), start = sample(marker.start), end = sample(marker.end);
            var color = null;
            if (start.seconds === null) throw new Error("Unreadable marker start.");
            var row = { guid: null, name: name, type: String(marker.type || "Comment"),
                comments: String(marker.comments || ""), seconds: start.seconds, order: rows.length,
                start: start, end: end.seconds, endTime: end, color: color, picture: false };
            if (voiceOwner(row) || editCaptionOwner(row) || captionsCaptionOwner(row)) other++;
            if (pictureOwner(row)) {
                row.picture = true;
                row.guid = String(marker.guid || "");
                try { if (typeof marker.getColorByIndex === "function") color = Number(marker.getColorByIndex()); } catch (ignoreColor) {}
                if (color !== null && isFinite(color)) row.color = color;
            }
            rows.push(row);
            marker = collection.getNextMarker(marker);
        }
        return { rows: rows, other: other };
    }
    function groupFor(map, fps, positions) {
        return { ranges: [{ start: map.source(map.start), end: map.source(map.end) }], owns: pictureOwner,
            tolerance: 0.25 / fps, allowMove: true, positions: positions, reserved: {}, desired: [] };
    }
    function verification(spec, map, fps, tolerance, row) {
        function inside(t) { return t >= map.start - 0.0000001 / fps && t < map.end - 0.0000001 / fps; }
        var startInRange = inside(map.timeline(row.seconds));
        var endInRange = row.end !== null && inside(map.timeline(row.end));
        return { startInRange: startInRange, endInRange: endInRange, inRange: startInRange && endInRange,
            endNearStart: row.end !== null && Math.abs(row.end - row.seconds) <= tolerance / 2,
            withinHalfFrame: Math.abs(row.seconds - spec.seconds) <= spec.positionTolerance,
            passed: spec.verify(row.seconds, row.end) };
    }
    function predict(tools, g, map, fps, row, rows, detail) {
        if (!owned(g, row)) { detail.reason = "outside-scope-or-unowned"; return; }
        var spec = tools.point(g, map.start, map.end, fps, map);
        if (!spec) { detail.reason = "no-available-frame"; return; }
        detail.targetSourceSeconds = spec.seconds;
        // The next Auto edit request metadata is unavailable. Use this marker's
        // metadata only when testing whether add() would snap back to its start.
        spec.name = row.name; spec.comments = row.comments; spec.color = row.color === null ? 0 : row.color;
        // add() changes reservations and the spec, all on this in-memory group.
        tools.add(g, spec);
        detail.commitSourceSeconds = spec.seconds;
        detail.snappedToStoredPosition = spec.seconds !== detail.targetSourceSeconds;
        var matches = near(g.positions, spec.seconds, g.tolerance), old = matches.length ? matches[0] : null;
        detail.commitNearMatch = old === row;
        var move = !!(old && spec.positionTolerance && !spec.verify(old.seconds, old.seconds));
        if (old && (old !== row || matches.length !== 1)) { detail.reason = "different-near-match"; return; }
        if (!old) {
            // The single request takes the earliest eligible leftover, using
            // the same tie breaker as commit() for equal source positions.
            for (var i = 0; i < rows.length; i++) {
                var candidate = rows[i];
                if (owned(g, candidate) && candidate.end !== null && candidate.color !== null &&
                    (!old || candidate.seconds < old.seconds || (candidate.seconds === old.seconds && candidate.order < old.order))) old = candidate;
            }
            if (old !== row) { detail.reason = "different-or-no-leftover"; return; }
            move = true;
        }
        if (move && (old.end === null || old.color === null)) { detail.reason = "move-snapshot-unavailable"; return; }
        var desiredEnd = old.seconds, currentEnd = old.end;
        var updateEnd = currentEnd === null || Math.abs(currentEnd - desiredEnd) > g.tolerance / 2;
        if (!updateEnd && !move && spec.positionTolerance && !spec.verify(desiredEnd, currentEnd) && spec.verify(desiredEnd, desiredEnd)) updateEnd = true;
        if (move && spec.seconds !== old.seconds) detail.predictedAction = "move";
        else if (move) detail.predictedAction = currentEnd === null || Math.abs(currentEnd - spec.end) > g.tolerance / 2 ? "endWrite" : "keep";
        else detail.predictedAction = updateEnd ? "endWrite" : "keep";
    }
    function inspectMarker(row, clip, map, middle, fps, positions, rows, tools) {
        var out = { guid: row.guid, name: row.name, start: row.start, end: row.endTime,
            isPoint: row.end === null ? null : (row.start.ticks !== null && row.endTime.ticks !== null
                ? row.start.ticks === row.endTime.ticks : row.seconds === row.end),
            timelineSeconds: null, distanceToMiddleFrames: null, insideClipRange: null,
            nestGridDeltaTicks: gridDelta(row.start.ticks, clip.nest && clip.nest.timebase),
            outerGridDeltaTicks: gridDelta(row.start.ticks, clip.timebase), timelineGridDeltaTicks: null,
            desiredSourceSeconds: null, sourceDeltaSeconds: null, endDeltaSeconds: row.end === null ? null : row.end - row.seconds,
            verify: null, nearMatch: null, targetSourceSeconds: null, commitSourceSeconds: null, commitNearMatch: null,
            snappedToStoredPosition: null, predictedAction: null, reason: null };
        if (!map) { out.reason = "mapping-unavailable"; return out; }
        out.timelineSeconds = map.timeline(row.seconds);
        out.insideClipRange = out.timelineSeconds >= map.start && out.timelineSeconds < map.end;
        out.timelineGridDeltaTicks = gridDelta(out.timelineSeconds * TICKS, clip.timebase);
        if (!middle) { out.reason = "no-middle-frame"; return out; }
        out.distanceToMiddleFrames = (out.timelineSeconds - clip.middleTimelineSeconds) * fps;
        out.desiredSourceSeconds = middle.seconds;
        out.sourceDeltaSeconds = row.seconds - middle.seconds;
        var g = groupFor(map, fps, positions);
        out.verify = verification(middle, map, fps, g.tolerance, row);
        out.nearMatch = Math.abs(out.sourceDeltaSeconds) < g.tolerance;
        predict(tools, g, map, fps, row, rows, out);
        return out;
    }
    function read(trackIndex) {
        var project = app.project, sequence = project && project.activeSequence;
        if (!project || !project.documentID) throw new Error("Project identity unavailable.");
        if (!sequence || sequence.sequenceID === undefined) throw new Error("Open the sequence to inspect first.");
        var tracks = sequence.videoTracks, timebase = timebaseOf(sequence);
        if (!tracks || typeof trackIndex !== "number" || trackIndex < 0 || Math.floor(trackIndex) !== trackIndex || trackIndex >= tracks.numTracks) {
            throw new Error("Video track index out of range.");
        }
        if (!timebase) throw new Error("Unreadable sequence timebase.");
        var fps = TICKS / Number(timebase), host = $._PVS, tools = host && host._markerTools;
        var useHostTools = tools && typeof tools.point === "function" && typeof tools.add === "function";
        if (!useHostTools) tools = { point: point, add: add };
        var getMapping = host && typeof host._clipMarkerMapping === "function" ? host._clipMarkerMapping : clipMarkerMapping;
        var clips = tracks[trackIndex].clips, result = [], owners = {};
        var summary = { keep: 0, move: 0, endWrite: 0, unclassified: 0, outsideClip: 0, sequenceOwners: 0, otherOwnedMarkers: 0,
            maxAbsDelta: { sourceSeconds: null, endSeconds: null, middleFrames: null, nestGridTicks: null,
                outerGridTicks: null, timelineGridTicks: null } };
        function recordMax(key, value) {
            if (value === null) return;
            var previous = summary.maxAbsDelta[key];
            summary.maxAbsDelta[key] = previous === null ? Math.abs(value) : Math.max(previous, Math.abs(value));
        }
        for (var i = 0; i < clips.numItems; i++) {
            var item = clips[i], owner = item.projectItem, nodeId = owner && String(owner.nodeId || "");
            var isSequence = owner && typeof owner.isSequence === "function" ? !!owner.isSequence() : null;
            var raw = null;
            try { if (typeof item.getSpeed === "function") raw = item.getSpeed(); } catch (ignoreSpeed) {}
            var clip = { index: i, name: String(item.name || ""), projectItemNodeId: nodeId, isSequence: isSequence,
                start: sample(item.start), end: sample(item.end), inPoint: sample(item.inPoint), outPoint: sample(item.outPoint),
                speed: { raw: raw, factor: speedFactor({ getSpeed: function () { return raw; } }) },
                timebase: timebase, fps: fps, nest: null, middleOutputFrame: null, middleTimelineSeconds: null,
                pictureMarkers: [], otherOwnedMarkers: null, markerReadError: null };
            result.push(clip);
            var key = nodeId ? "node:" + nodeId : "clip:" + i, data = owners[key];
            if (!data) {
                data = { nest: isSequence ? nestTiming(project, nodeId) : null, markers: null, error: null };
                owners[key] = data;
                if (isSequence) summary.sequenceOwners++;
                try { data.markers = readOwner(owner); summary.otherOwnedMarkers += data.markers.other; }
                catch (e) { data.error = String(e.message || e); }
            }
            clip.nest = data.nest;
            clip.markerReadError = data.error;
            if (!data.markers) continue;
            clip.otherOwnedMarkers = data.markers.other;
            var rows = data.markers.rows, map = getMapping(item, true), middle = null;
            var positions = index(rows, 0.25 / fps);
            if (map) {
                middle = tools.point(groupFor(map, fps, {}), map.start, map.end, fps, map);
                if (middle) {
                    clip.middleOutputFrame = Math.round(map.timeline(middle.seconds) * fps);
                    clip.middleTimelineSeconds = clip.middleOutputFrame / fps;
                }
            }
            for (var m = 0; m < rows.length; m++) {
                if (!rows[m].picture) continue;
                // A nest shares one marker collection across many clips; report
                // each marker only on the clip whose range it maps into.
                if (map) {
                    var mappedTimeline = map.timeline(rows[m].seconds);
                    if (!(mappedTimeline >= map.start && mappedTimeline < map.end)) { summary.outsideClip++; continue; }
                }
                rows[m].reported = true;
                var detail = inspectMarker(rows[m], clip, map, middle, fps, positions, rows, tools);
                clip.pictureMarkers.push(detail);
                summary[detail.predictedAction || "unclassified"]++;
                recordMax("sourceSeconds", detail.sourceDeltaSeconds);
                recordMax("endSeconds", detail.endDeltaSeconds);
                recordMax("middleFrames", detail.distanceToMiddleFrames);
                recordMax("nestGridTicks", detail.nestGridDeltaTicks);
                recordMax("outerGridTicks", detail.outerGridDeltaTicks);
                recordMax("timelineGridTicks", detail.timelineGridDeltaTicks);
            }
        }
        // Picture markers outside every clip range on this track are leftover
        // candidates that commit() may pair with a request and move.
        var unmatched = [];
        for (var ownerKey in owners) {
            if (!Object.prototype.hasOwnProperty.call(owners, ownerKey) || !owners[ownerKey].markers) continue;
            var ownerRows = owners[ownerKey].markers.rows;
            for (var u = 0; u < ownerRows.length; u++) {
                if (!ownerRows[u].picture || ownerRows[u].reported) continue;
                unmatched.push({ owner: ownerKey, guid: ownerRows[u].guid, name: ownerRows[u].name,
                    start: ownerRows[u].start, end: ownerRows[u].endTime });
            }
        }
        summary.unmatchedPictureMarkers = unmatched.length;
        return { ok: true, documentId: String(project.documentID), sequenceId: String(sequence.sequenceID),
            trackIndex: trackIndex, timebase: timebase, fps: fps, clipCount: result.length, unmatchedPictureMarkers: unmatched,
            markerToolsSource: useHostTools ? "host" : "replicated",
            mappingSource: getMapping === clipMarkerMapping ? "replicated" : "host", clips: result, summary: summary };
    }
    return { read: function (trackIndex) { return guarded(function () { return read(trackIndex); }); } };
}());
