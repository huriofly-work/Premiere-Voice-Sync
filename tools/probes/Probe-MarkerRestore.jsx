// Developer-only probe. Loading defines functions without native access.
$._PVSMarkerRestoreProbe = (function () {
    var TAG = "[PremiereVoiceSync:marker-restore:v1]", SCOPE = "probe-tagged-only", TICKS = 254016000000;
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
    function projectItems() {
        var project = app.project, items = [], visited = 0;
        if (!project || !project.documentID || !project.rootItem) throw new Error("Project identity unavailable.");
        function visit(item, depth) {
            if (++visited > 10000 || depth > 32) throw new Error("Project traversal limit exceeded.");
            if (item.type === 1 && typeof item.getMarkers === "function" &&
                typeof item.isSequence === "function" && !item.isSequence()) items.push(item);
            var children = item.children;
            if (children) for (var i = 0; i < children.numItems; i++) visit(children[i], depth + 1);
        }
        visit(project.rootItem, 0);
        return { project: project, items: items };
    }
    function target(documentId, nodeId, tag, scope) {
        if (tag !== TAG || scope !== SCOPE || typeof documentId !== "string" || !documentId || typeof nodeId !== "string" || !nodeId) {
            throw new Error("Exact probe tag, scope, documentId and nodeId required.");
        }
        var found = projectItems(), matches = [];
        if (String(found.project.documentID) !== documentId) throw new Error("Project identity changed.");
        for (var i = 0; i < found.items.length; i++) if (String(found.items[i].nodeId) === nodeId) matches.push(found.items[i]);
        if (matches.length !== 1) throw new Error("Choose exactly one non-sequence media ProjectItem from list.");
        var collection = matches[0].getMarkers();
        if (!collection || typeof collection.createMarker !== "function" || typeof collection.deleteMarker !== "function") throw new Error("Marker API unavailable.");
        return collection;
    }
    function hostTools() {
        return $._PVS && $._PVS._markerTools;
    }
    function markerEnd(marker) {
        var end = marker.end;
        return end === undefined || end === null ? null : Number(typeof end === "number" ? end : end.seconds);
    }
    // Standalone copies of the host field normalization and fingerprint.
    function read(collection) {
        var tools = hostTools();
        if (tools) return tools.read(collection);
        var rows = [], marker = collection.getFirstMarker();
        while (marker) {
            if (rows.length >= 10000) throw new Error("Marker enumeration limit exceeded.");
            var seconds = Number(marker.start.seconds), end = markerEnd(marker), color = null;
            if (!isFinite(seconds)) throw new Error("Unreadable marker position.");
            if (end !== null && !isFinite(end)) throw new Error("Unreadable marker end.");
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
        var tools = hostTools();
        if (tools) return tools.fingerprint(rows, identity);
        var values = [];
        for (var i = 0; i < rows.length; i++) {
            var r = rows[i];
            values.push(encode([identity ? r.guid : "", r.seconds, r.end, r.name, r.comments, r.type, r.color]));
        }
        return values.sort().join("\n");
    }
    function find(rows, saved) {
        for (var i = 0; i < rows.length; i++) {
            if (rows[i].ref === saved.ref || (saved.guid && rows[i].guid === saved.guid)) return rows[i];
        }
        return null;
    }
    function tagged(comments) { return String(comments).split("\n")[0] === TAG; }
    function createFresh(collection, seconds) {
        var existing = read(collection), marker = collection.createMarker(seconds);
        if (!marker || find(existing, { ref: marker, guid: String(marker.guid || "") }) || marker.name || marker.comments) {
            throw new Error("createMarker did not return a fresh blank marker; inspect project.");
        }
        return marker;
    }
    function removeTagged(collection, expected, current) {
        var result = { attempted: 0, errors: [], verified: false };
        for (var i = 0; i < current.length; i++) {
            if (find(expected, current[i])) continue;
            try {
                if (!tagged(current[i].ref.comments)) continue;
                result.attempted++;
                collection.deleteMarker(current[i].ref);
            } catch (e) { result.errors.push(String(e.message || e)); }
        }
        try {
            var after = read(collection);
            result.afterCount = after.length;
            result.verified = fingerprint(after, true) === fingerprint(expected, true);
            if (!result.verified) result.errors.push("Collection differs from expected state; untagged markers are never deleted.");
        } catch (e) { result.errors.push(String(e.message || e)); }
        return result;
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
    function timeSample(item, field, fps) {
        try {
            var time = item[field], seconds = Number(time.seconds), ticks = String(time.ticks), tickSeconds = Number(ticks) / TICKS;
            if (!ticks || !isFinite(seconds) || !isFinite(tickSeconds)) throw new Error("Unreadable clip time.");
            var frame = Math.round(seconds * fps), frameSeconds = frame / fps;
            return { seconds: seconds, ticks: ticks, tickSeconds: tickSeconds, frame: frame, frameSeconds: frameSeconds,
                deltaVsTicks: (seconds - tickSeconds) * TICKS, deltaVsRoundedFrameTicks: (seconds - frameSeconds) * TICKS };
        } catch (e) { return { error: String(e.message || e) }; }
    }
    function projection(trackIndex) {
        var project = app.project, sequence = project && project.activeSequence;
        if (!project || !project.documentID) throw new Error("Project identity unavailable.");
        if (!sequence || sequence.sequenceID === undefined) throw new Error("Open the sequence to inspect first.");
        var tracks = sequence.audioTracks;
        if (typeof trackIndex !== "number" || trackIndex < 0 || Math.floor(trackIndex) !== trackIndex || trackIndex >= tracks.numTracks) throw new Error("Audio track index out of range.");
        var timebase = String(sequence.timebase), fps = TICKS / Number(timebase);
        if (!isFinite(fps) || fps <= 0) throw new Error("Unreadable sequence timebase.");
        var clips = tracks[trackIndex].clips, result = [], hostSpeed = $._PVS && typeof $._PVS._speedFactor === "function";
        for (var i = 0; i < clips.numItems; i++) {
            var item = clips[i];
            result.push({ index: i, nodeId: String(item.nodeId || ""),
                start: timeSample(item, "start", fps), end: timeSample(item, "end", fps),
                inPoint: timeSample(item, "inPoint", fps), outPoint: timeSample(item, "outPoint", fps),
                speed: hostSpeed ? $._PVS._speedFactor(item) : speedFactor(item) });
        }
        return { ok: true, documentId: String(project.documentID), sequenceId: String(sequence.sequenceID),
            trackIndex: trackIndex, timebase: timebase, fps: fps, speedSource: hostSpeed ? "host" : "replicated",
            clipCount: result.length, clips: result };
    }
    function differences(actual, prior) {
        if (!actual) return [{ field: "identity", actual: null, prior: prior.guid }];
        var fields = ["seconds", "end", "name", "comments", "type", "color"], result = [];
        for (var i = 0; i < fields.length; i++) {
            var field = fields[i], a = actual[field], b = prior[field];
            if (a === b && (a !== 0 || 1 / a === 1 / b)) continue;
            if (field === "comments") {
                var codes = [];
                for (var j = 0; j < Math.max(a.length, b.length); j++) {
                    if (a.charAt(j) !== b.charAt(j)) codes.push({ index: j,
                        actual: j < a.length ? a.charCodeAt(j) : null,
                        prior: j < b.length ? b.charCodeAt(j) : null });
                }
                result.push({ field: field, actualLength: a.length, priorLength: b.length, firstDiffIndex: codes[0].index, charCodes: codes });
            } else {
                var detail = { field: field, actual: a, prior: b };
                if ((field === "seconds" || field === "end") && typeof a === "number" && typeof b === "number") detail.deltaTicks = (a - b) * TICKS;
                if (a === 0 && b === 0) { detail.actualNegativeZero = 1 / a < 0; detail.priorNegativeZero = 1 / b < 0; }
                result.push(detail);
            }
        }
        return result;
    }
    // Mirror the single-row reverse writes when the panel has no marker tools.
    function restoreStandalone(collection, prior, current, replacement) {
        var marker;
        if (current) {
            marker = current.ref;
            if (prior.seconds !== current.seconds) marker.start = prior.seconds;
        } else {
            marker = createFresh(collection, prior.seconds);
            replacement.row = { ref: marker, guid: String(marker.guid || "") };
        }
        if (markerEnd(marker) !== prior.end) marker.end = prior.end;
        if (!current || prior.name !== current.name) marker.name = prior.name;
        if (!current || prior.comments !== current.comments) marker.comments = prior.comments;
        if (!current || prior.color !== current.color) marker.setColorByIndex(prior.color);
    }
    function snapshot(row) {
        if (!row) return null;
        return { guid: row.guid, seconds: row.seconds, end: row.end, name: row.name,
            commentsLength: row.comments.length, type: row.type, color: row.color };
    }
    var CASES = [
        { id: "move-point", duration: 0 },
        { id: "move-range", duration: 0.75 },
        { id: "recreate", duration: 0.5 },
        { id: "color", duration: 0 }
    ];
    function runCase(collection, spec, entry) {
        var marker = createFresh(collection, entry.requestedSeconds);
        var identity = { ref: marker, guid: String(marker.guid || "") };
        // Tag first so the finally block can find the marker.
        marker.comments = TAG + "\n" + spec.id;
        if (!tagged(marker.comments)) throw new Error("Probe tag readback failed; inspect untagged marker manually.");
        marker.name = "PVS RESTORE PROBE";
        if (spec.duration) marker.end = Number(marker.start.seconds) + spec.duration;
        marker.setColorByIndex(2);
        var prior = find(read(collection), identity);
        if (!prior || !tagged(prior.comments) || prior.end === null || prior.color === null) throw new Error("Initial tagged marker fields unavailable.");
        entry.prior = snapshot(prior);
        if (spec.id === "recreate") collection.deleteMarker(marker);
        else if (spec.id === "color") marker.setColorByIndex(prior.color === 4 ? 2 : 4);
        else {
            marker.start = prior.seconds + 1;
            if (spec.duration) marker.end = Number(marker.start.seconds) + 0.25;
        }
        var current = find(read(collection), prior);
        if (spec.id === "recreate") {
            if (current) throw new Error("Deleted probe marker is still present.");
        } else if (!current || !tagged(current.comments)) throw new Error("Modified tagged marker unavailable.");
        entry.modified = snapshot(current);
        var tools = hostTools(), replacement = {};
        entry.restoreErrors = [];
        try {
            if (tools) {
                var journal = [{ collection: collection, before: [prior], after: current ? [current] : [], tolerance: 0.01 }];
                entry.restoreErrors = tools.restore(journal);
                if (journal.replacements && journal.replacements.length) replacement.row = journal.replacements[0].fresh;
            } else restoreStandalone(collection, prior, current, replacement);
        } catch (e) { entry.restoreErrors.push(String(e.message || e)); }
        var actual = find(read(collection), replacement.row || prior);
        entry.actual = snapshot(actual);
        entry.differences = differences(actual, prior);
        entry.fingerprintMatches = !!actual && fingerprint([actual], false) === fingerprint([prior], false);
    }
    function freeBases(before, count) {
        var i;
        for (i = 0; i < before.length; i++) if (tagged(before[i].comments)) throw new Error("Probe-tagged markers already exist; run restore-cleanup first.");
        var bases = [], candidate = 1234 / 29.97;
        while (bases.length < count) {
            if (candidate > 100000) throw new Error("No free probe positions within limit.");
            var occupied = false;
            for (i = 0; i < before.length; i++) {
                if (Math.abs(before[i].seconds - candidate) < 3 || (before[i].end !== null && Math.abs(before[i].end - candidate) < 3)) occupied = true;
            }
            if (!occupied) bases.push(candidate);
            candidate += 6;
        }
        return bases;
    }
    function run(documentId, nodeId, tag, scope) {
        var collection = target(documentId, nodeId, tag, scope), before = read(collection);
        var bases = freeBases(before, CASES.length);
        var result = { ok: true, documentId: documentId, nodeId: nodeId, tag: TAG, beforeCount: before.length,
            markerToolsSource: hostTools() ? "host" : "replicated", cases: [], cleanup: { attempted: 0, errors: [], verified: false } };
        try {
            for (var i = 0; i < CASES.length; i++) {
                var entry = { id: CASES[i].id, requestedSeconds: bases[i] };
                result.cases.push(entry);
                runCase(collection, CASES[i], entry);
                if (entry.restoreErrors.length || entry.differences.length) result.ok = false;
            }
        } catch (e) { result.ok = false; result.error = String(e.message || e); }
        finally {
            try { result.cleanup = removeTagged(collection, before, read(collection)); }
            catch (e) { result.cleanup.errors.push(String(e.message || e)); }
            if (!result.cleanup.verified || result.cleanup.errors.length) result.ok = false;
        }
        return result;
    }
    function runJournal(documentId, nodeId, tag, scope) {
        var collection = target(documentId, nodeId, tag, scope), tools = hostTools();
        if (!tools || typeof tools.group !== "function" || typeof tools.commit !== "function" ||
            typeof tools.restore !== "function" || typeof tools.restoredRows !== "function") {
            throw new Error("Load the panel host marker tools before running restore-journal.");
        }
        var initial = tools.read(collection), bases = freeBases(initial, 4), journal = [];
        var voiceName = "VOICE SYNC - Kiem tra can voice (PVS probe)";
        var reviewName = "VOICE SYNC - Can kiem tra (PVS probe)";
        var result = { ok: true, documentId: documentId, nodeId: nodeId, tag: TAG, beforeCount: initial.length,
            markerToolsSource: "host", commits: [], restoreErrors: [], markers: [],
            cleanup: { attempted: 0, errors: [], verified: false } };
        function ownsVoice(row) { return tagged(row.comments) && row.name === voiceName; }
        function ownsReview(row) { return tagged(row.comments) && row.name === reviewName; }
        function spec(name, seconds, duration, note, color) {
            return { name: name, seconds: seconds, end: seconds + duration, color: color,
                comments: TAG + "\nC\u1ea7n ki\u1ec3m tra l\u1eddi voice\nNghe l\u1ea1i \u0111o\u1ea1n " + note };
        }
        function seed(request) {
            var marker = createFresh(collection, request.seconds);
            marker.comments = request.comments;
            if (!tagged(marker.comments)) throw new Error("Probe tag readback failed; inspect untagged marker manually.");
            marker.name = request.name;
            if (request.end !== request.seconds) marker.end = Number(marker.start.seconds) + (request.end - request.seconds);
            marker.setColorByIndex(request.color);
        }
        function commit(kind, group, keepSurplus) {
            if (!tools.reversible(group)) throw new Error("Incomplete probe marker snapshot.");
            var commitResult = tools.commit(group, null, journal, keepSurplus), timing = commitResult.timings;
            result.commits.push({ kind: kind, moves: timing.moves, creates: timing.creates, deletes: timing.deletes,
                failures: commitResult.failures, colorFailures: commitResult.colorFailures });
            if (commitResult.failures.length || commitResult.colorFailures.length) throw new Error("Probe commit failed: " + kind + ".");
        }
        try {
            seed(spec(voiceName, bases[0], 0.75, "1a", 4));
            seed(spec(voiceName, bases[0] + 1, 0, "1b", 4));
            seed(spec(reviewName, bases[2], 0.5, "2a", 1));
            seed(spec(reviewName, bases[2] + 1, 0, "2b", 4));
            var before = tools.read(collection), ranges = [{ start: 0, end: Number.MAX_VALUE }], tolerance = 0.25 / 30;
            var voice = tools.group(collection, ranges, ownsVoice, tolerance, true);
            tools.add(voice, spec(voiceName, bases[0] + 1.5, 0.25, "3a", 4));
            tools.add(voice, spec(voiceName, bases[0] + 2, 0, "3b", 4));
            tools.add(voice, spec(voiceName, bases[1], 0, "3c", 4));
            commit("voice", voice, true);

            // Force review recreation to cover the deletion path of final reconciliation.
            var review = tools.group(collection, ranges, ownsReview, tolerance, false);
            if (tools.fingerprint(review.before, true) !== tools.fingerprint(voice.after, true)) throw new Error("Probe collection changed after voice commit.");
            review.peerReservations = voice.reserved;
            tools.add(review, spec(reviewName, bases[3], 0, "4a", 1));
            tools.add(review, spec(reviewName, bases[3] + 1, 0, "4b", 4));
            commit("review", review, false);

            if (journal.length !== 2) throw new Error("Expected two committed probe journal entries.");
            if (tools.fingerprint(tools.read(collection), true) !== tools.fingerprint(review.after, true)) throw new Error("Probe collection changed before restore.");
            for (var j = 0; j < journal.length; j++) {
                var affected = journal[j].before.concat(journal[j].after);
                for (var a = 0; a < affected.length; a++) if (!tagged(affected[a].comments)) throw new Error("Unexpected marker outside probe ownership.");
            }
            result.restoreErrors = tools.restore(journal);
            result.remainingJournalEntries = journal.length;

            var after = tools.read(collection), diagnostic = { detail: "" };
            result.fingerprintMatches = tools.restoredRows(before, after, journal, diagnostic);
            result.restoreDifference = diagnostic.detail;
            result.commentsByteIdentical = true;
            var replacements = journal.replacements || [], matched = [];
            for (var i = 0; i < before.length; i++) {
                var prior = before[i];
                if (!tagged(prior.comments)) continue;
                var identity = prior;
                for (var r = 0; r < replacements.length; r++) {
                    if (find([identity], replacements[r].old)) identity = replacements[r].fresh;
                }
                var actual = find(after, identity), sameComments = !!actual && actual.comments === prior.comments;
                result.markers.push({ prior: snapshot(prior), actual: snapshot(actual),
                    commentsByteIdentical: sameComments, differences: differences(actual, prior) });
                if (actual) matched.push(actual);
                if (!sameComments) result.commentsByteIdentical = false;
            }
            result.unexpectedMarkers = [];
            for (var k = 0; k < after.length; k++) {
                if (!find(initial, after[k]) && !find(matched, after[k])) result.unexpectedMarkers.push(snapshot(after[k]));
            }
            if (result.unexpectedMarkers.length) result.commentsByteIdentical = false;
            result.ok = result.fingerprintMatches && result.commentsByteIdentical && !result.restoreErrors.length && !journal.length;
        } catch (e) { result.ok = false; result.error = String(e.message || e); }
        finally {
            try { result.cleanup = removeTagged(collection, initial, read(collection)); }
            catch (e) { result.cleanup.errors.push(String(e.message || e)); }
            if (!result.cleanup.verified || result.cleanup.errors.length) result.ok = false;
        }
        return result;
    }
    function cleanup(documentId, nodeId, tag, scope) {
        var collection = target(documentId, nodeId, tag, scope), before = read(collection), expected = [];
        for (var i = 0; i < before.length; i++) if (!tagged(before[i].comments)) expected.push(before[i]);
        var result = removeTagged(collection, expected, before);
        result.ok = result.verified && !result.errors.length;
        return result;
    }
    return {
        list: function () { return guarded(function () {
            var found = projectItems(), result = [];
            for (var i = 0; i < found.items.length; i++) result.push({ nodeId: String(found.items[i].nodeId), name: String(found.items[i].name || "") });
            return { ok: true, documentId: String(found.project.documentID), projectName: String(found.project.name || ""), items: result, tag: TAG, scope: SCOPE };
        }); },
        projection: function (trackIndex) { return guarded(function () { return projection(trackIndex); }); },
        run: function (documentId, nodeId, tag, scope) { return guarded(function () { return run(documentId, nodeId, tag, scope); }); },
        journal: function (documentId, nodeId, tag, scope) { return guarded(function () { return runJournal(documentId, nodeId, tag, scope); }); },
        cleanup: function (documentId, nodeId, tag, scope) { return guarded(function () { return cleanup(documentId, nodeId, tag, scope); }); }
    };
}());
