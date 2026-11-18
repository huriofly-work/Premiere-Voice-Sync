// Developer-only probe. Loading defines functions without native access.
// Read-only: checks whether a TrackItem kept from an earlier evalScript call
// still reports the same source identity (projectItem.nodeId) as a fresh read.
// It never edits clips, markers, sequences or the project, and never saves.
$._PVSStaleTrackItemProbe = (function () {
    var MAX_CLIPS = 500, held = null;
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
    // Each read is isolated: a failing property must not hide the others.
    function field(read) {
        try {
            var value = read();
            if (value === undefined) return { kind: "undefined" };
            if (value === null) return { kind: "null" };
            return { kind: typeof value, value: typeof value === "object" || typeof value === "function" ? null : String(value) };
        } catch (e) { return { kind: "error", error: String(e.message || e) }; }
    }
    // Same rule as host.jsx projectItemKey(), copied so the probe stays standalone.
    function projectKey(item) {
        try {
            var projectItem = item && item.projectItem;
            if (!projectItem) return "";
            try { if (projectItem.nodeId !== undefined && projectItem.nodeId !== null && String(projectItem.nodeId)) return "node:" + String(projectItem.nodeId); } catch (ignoreNodeId) {}
            try { if (projectItem.treePath) return "path:" + String(projectItem.treePath); } catch (ignoreTreePath) {}
            return "";
        } catch (e) { return "error:" + String(e.message || e); }
    }
    function snapshot(item) {
        return {
            nodeId: field(function () { return item.nodeId; }),
            name: field(function () { return item.name; }),
            startTicks: field(function () { return item.start.ticks; }),
            endTicks: field(function () { return item.end.ticks; }),
            inPointTicks: field(function () { return item.inPoint.ticks; }),
            outPointTicks: field(function () { return item.outPoint.ticks; }),
            speed: field(function () { return item.getSpeed(); }),
            projectItem: field(function () { return item.projectItem; }),
            projectItemNodeId: field(function () { return item.projectItem.nodeId; }),
            projectItemTreePath: field(function () { return item.projectItem.treePath; }),
            projectItemGetMarkers: field(function () { return typeof item.projectItem.getMarkers; }),
            projectKey: projectKey(item)
        };
    }
    function same(a, b) { return a.kind === b.kind && a.value === b.value && a.error === b.error; }
    function differences(a, b) {
        var names = [], key;
        for (key in a) if (Object.prototype.hasOwnProperty.call(a, key)) {
            if (key === "projectKey" ? a[key] !== b[key] : !same(a[key], b[key])) names.push(key);
        }
        return names;
    }
    function context(trackIndex) {
        var project = app.project, sequence = project && project.activeSequence;
        if (!project || !project.documentID) throw new Error("Project identity unavailable.");
        if (!sequence || sequence.sequenceID === undefined) throw new Error("Open the sequence to inspect first.");
        var tracks = sequence.audioTracks;
        if (typeof trackIndex !== "number" || trackIndex < 0 || Math.floor(trackIndex) !== trackIndex || trackIndex >= tracks.numTracks) throw new Error("Audio track index out of range.");
        var clips = tracks[trackIndex].clips;
        if (clips.numItems < 1) throw new Error("The chosen audio track has no clips.");
        if (clips.numItems > MAX_CLIPS) throw new Error("Too many clips on the chosen track.");
        return { documentId: String(project.documentID), sequenceId: String(sequence.sequenceID), clips: clips };
    }
    // Call A: keep the TrackItem wrappers and their ProjectItems for a later call.
    function capture(trackIndex) {
        var found = context(trackIndex), rows = [], items = [], projectItems = [];
        for (var i = 0; i < found.clips.numItems; i++) {
            var item = found.clips[i], first = snapshot(item), again = found.clips[i];
            items.push(item);
            projectItems.push(field(function () { return item.projectItem; }).kind === "object" ? item.projectItem : null);
            // Same-call control: re-read the kept wrapper and a re-fetched one.
            rows.push({ index: i, fresh: first, sameCallHeldDiff: differences(first, snapshot(item)),
                sameCallRefetchDiff: differences(first, snapshot(again)), sameCallSameObject: again === item });
        }
        held = { documentId: found.documentId, sequenceId: found.sequenceId, trackIndex: trackIndex,
            items: items, projectItems: projectItems, rows: rows, capturedAt: (new Date()).getTime() };
        return { ok: true, step: "capture", documentId: found.documentId, sequenceId: found.sequenceId,
            trackIndex: trackIndex, clipCount: rows.length, clips: rows };
    }
    // Call B (a later evalScript): compare the kept wrappers with fresh reads.
    function compare() {
        if (!held) throw new Error("Run stale-capture first.");
        var found = context(held.trackIndex), rows = [], keyMismatches = 0;
        if (found.documentId !== held.documentId || found.sequenceId !== held.sequenceId) throw new Error("Active project or sequence changed since capture.");
        for (var i = 0; i < held.items.length; i++) {
            var oldItem = held.items[i], captured = held.rows[i].fresh, fresh = null;
            for (var c = 0; c < found.clips.numItems; c++) {
                if (captured.nodeId.kind !== "error" && String(found.clips[c].nodeId) === captured.nodeId.value) { fresh = found.clips[c]; break; }
            }
            var oldNow = snapshot(oldItem), freshNow = fresh ? snapshot(fresh) : null, keptProject = held.projectItems[i];
            if (!freshNow || oldNow.projectKey !== freshNow.projectKey) keyMismatches++;
            rows.push({ index: i, held: oldNow, fresh: freshNow, freshFound: !!fresh,
                sameObject: fresh === oldItem,
                heldVsFreshDiff: freshNow ? differences(oldNow, freshNow) : null,
                heldVsCaptureDiff: differences(oldNow, captured),
                keyMatchesFresh: !!freshNow && oldNow.projectKey === freshNow.projectKey,
                keptProjectItemNodeId: keptProject ? field(function () { return keptProject.nodeId; }) : { kind: "not-captured" },
                keptProjectItemGetMarkers: keptProject ? field(function () { return typeof keptProject.getMarkers; }) : { kind: "not-captured" } });
        }
        return { ok: true, step: "compare", millisecondsSinceCapture: (new Date()).getTime() - held.capturedAt,
            clipCount: rows.length, keyMismatches: keyMismatches, clips: rows };
    }
    function release() { var had = !!held; held = null; return { ok: true, step: "release", released: had }; }
    return {
        capture: function (trackIndex) { return guarded(function () { return capture(trackIndex); }); },
        compare: function () { return guarded(compare); },
        release: function () { return guarded(release); }
    };
}());
