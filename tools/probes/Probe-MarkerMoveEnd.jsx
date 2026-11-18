// Developer-only probe. Loading defines functions without native access.
// Records how Premiere changes marker start/end when either one is written.
$._PVSMarkerMoveEndProbe = (function () {
    var TAG = "[PremiereVoiceSync:marker-move-end:v1]", SCOPE = "probe-tagged-only";
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
    function seconds(value) {
        var n = Number(value && value.seconds !== undefined ? value.seconds : value);
        if (value === null || value === undefined || !isFinite(n)) throw new Error("Unreadable marker time.");
        return n;
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
    function rows(collection) {
        var result = [], marker = collection.getFirstMarker();
        while (marker) {
            if (result.length >= 10000) throw new Error("Marker enumeration limit exceeded.");
            var color = null;
            try { color = Number(marker.getColorByIndex()); } catch (ignoreColor) {}
            result.push({ ref: marker, guid: String(marker.guid || ""), start: seconds(marker.start), end: seconds(marker.end),
                name: String(marker.name || ""), comments: String(marker.comments || ""), type: String(marker.type || "Comment"), color: color });
            marker = collection.getNextMarker(marker);
        }
        return result;
    }
    function identity(a, b) { return a.ref === b.ref || (!!a.guid && a.guid === b.guid); }
    function contains(values, row) {
        for (var i = 0; i < values.length; i++) if (identity(values[i], row)) return true;
        return false;
    }
    function tagged(comments) { return String(comments).split("\n")[0] === TAG; }
    function fingerprint(values) {
        var data = [];
        for (var i = 0; i < values.length; i++) {
            var r = values[i];
            data.push(encode([r.guid, r.start, r.end, r.name, r.comments, r.type, r.color]));
        }
        return data.sort().join("\n");
    }
    function bounds(marker) {
        var out = { start: null, end: null, readError: null };
        try { out.start = seconds(marker.start); out.end = seconds(marker.end); }
        catch (e) { out.readError = String(e.message || e); }
        return out;
    }
    // Each case starts from a fresh tagged marker at base p, then applies writes in order.
    // Values are offsets from p; "point" means end = start before the writes.
    var CASES = [
        { id: "new-default", initialEnd: null, writes: [] },
        { id: "range-start-later-inside", initialEnd: 1, writes: [["start", 0.5]] },
        { id: "range-end-then-start-later", initialEnd: 1, writes: [["end", 0.5], ["start", 0.5]] },
        { id: "range-start-then-end-later", initialEnd: 1, writes: [["start", 0.5], ["end", 0.5]] },
        { id: "range-start-past-end", initialEnd: 1, writes: [["start", 2]] },
        { id: "range-start-earlier-then-end", initialEnd: 1, writes: [["start", -0.5], ["end", -0.5]] },
        { id: "range-end-equals-start", initialEnd: 1, writes: [["end", 0]] },
        { id: "point-start-later", initialEnd: 0, writes: [["start", 0.5]] },
        { id: "point-start-earlier", initialEnd: 0, writes: [["start", -0.5]] },
        { id: "point-end-later", initialEnd: 0, writes: [["end", 0.5]] }
    ];
    return {
        list: function () { return guarded(function () {
            var found = projectItems(), result = [];
            for (var i = 0; i < found.items.length; i++) result.push({ nodeId: String(found.items[i].nodeId), name: String(found.items[i].name || "") });
            return { ok: true, documentId: String(found.project.documentID), projectName: String(found.project.name || ""), items: result, tag: TAG, scope: SCOPE };
        }); },
        run: function (documentId, nodeId, tag, scope) { return guarded(function () {
            var collection = target(documentId, nodeId, tag, scope), before = rows(collection), created = [], i, j;
            for (i = 0; i < before.length; i++) if (tagged(before[i].comments)) throw new Error("Probe-tagged markers already exist; run move-cleanup first.");
            // Reserve bases 6 s apart with no existing marker within 3 s.
            var bases = [], candidate = 4;
            while (bases.length < CASES.length) {
                if (candidate > 100000) throw new Error("No free probe positions within limit.");
                var occupied = false;
                for (j = 0; j < before.length; j++) if (Math.abs(before[j].start - candidate) < 3 || Math.abs(before[j].end - candidate) < 3) occupied = true;
                if (!occupied) bases.push(candidate);
                candidate += 6;
            }
            var result = { ok: false, documentId: documentId, nodeId: nodeId, tag: TAG, beforeCount: before.length, cases: [],
                cleanup: { attempted: 0, errors: [], verified: false } };
            try {
                for (i = 0; i < CASES.length; i++) {
                    var spec = CASES[i], p = bases[i], entry = { id: spec.id, base: p, steps: [] };
                    result.cases.push(entry);
                    var marker = collection.createMarker(p);
                    if (!marker) throw new Error("createMarker returned no marker; inspect project.");
                    var row = { ref: marker, guid: String(marker.guid || "") };
                    if (contains(before, row) || contains(created, row)) throw new Error("createMarker returned an existing marker; left untouched.");
                    created.push(row);
                    entry.created = bounds(marker);
                    // Tag first so cleanup can always find it.
                    marker.comments = TAG + "\n" + spec.id;
                    if (!tagged(marker.comments)) throw new Error("Probe tag readback failed; inspect untagged marker manually.");
                    marker.name = "PVS MOVE PROBE";
                    if (spec.initialEnd !== null) {
                        try { marker.end = p + spec.initialEnd; } catch (setupError) { entry.setupError = String(setupError.message || setupError); }
                    }
                    entry.initial = bounds(marker);
                    for (j = 0; j < spec.writes.length; j++) {
                        var field = spec.writes[j][0], value = p + spec.writes[j][1], step = { field: field, requested: value, error: null };
                        try { marker[field] = value; } catch (writeError) { step.error = String(writeError.message || writeError); }
                        var now = bounds(marker);
                        step.start = now.start; step.end = now.end; step.readError = now.readError;
                        entry.steps.push(step);
                    }
                }
                result.ok = true;
            } catch (e) { result.error = String(e.message || e); }
            finally {
                try {
                    var current = rows(collection), additions = [];
                    for (i = 0; i < current.length; i++) if (!contains(before, current[i])) additions.push(current[i]);
                    for (i = 0; i < additions.length; i++) {
                        try {
                            if (!tagged(additions[i].ref.comments)) continue;
                            result.cleanup.attempted++;
                            collection.deleteMarker(additions[i].ref);
                        } catch (deleteError) { result.cleanup.errors.push(String(deleteError.message || deleteError)); }
                    }
                    var after = rows(collection);
                    result.afterCount = after.length;
                    result.cleanup.verified = fingerprint(after) === fingerprint(before);
                    if (!result.cleanup.verified) result.cleanup.errors.push("Collection differs from pre-probe state; untagged additions are never deleted.");
                } catch (cleanupError) { result.cleanup.errors.push(String(cleanupError.message || cleanupError)); }
                if (!result.cleanup.verified || result.cleanup.errors.length) result.ok = false;
            }
            return result;
        }); },
        cleanup: function (documentId, nodeId, tag, scope) { return guarded(function () {
            var collection = target(documentId, nodeId, tag, scope), before = rows(collection), expected = [], attempted = 0, errors = [];
            for (var i = 0; i < before.length; i++) {
                if (!tagged(before[i].comments)) { expected.push(before[i]); continue; }
                try { attempted++; collection.deleteMarker(before[i].ref); } catch (e) { errors.push(String(e.message || e)); }
            }
            var verified = fingerprint(rows(collection)) === fingerprint(expected);
            return { ok: verified && !errors.length, attempted: attempted, errors: errors, verified: verified };
        }); }
    };
}());
