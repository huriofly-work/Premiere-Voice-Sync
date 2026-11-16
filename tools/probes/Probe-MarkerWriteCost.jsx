// Developer-only probe. Loading defines functions without native access.
$._PVSMarkerWriteCostProbe = (function () {
    var TAG = "[PremiereVoiceSync:marker-write-cost:v1]", SCOPE = "throwaway-project";
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
            // CLIP is 1; reject sequences and items whose media type is unknown.
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
            throw new Error("Exact probe tag, throwaway-project scope, documentId and nodeId required.");
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
            if (typeof marker.getColorByIndex !== "function") throw new Error("Color read API unavailable.");
            var color = Number(marker.getColorByIndex());
            if (!isFinite(color)) throw new Error("Unreadable marker color.");
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
    function now() { return (new Date()).getTime(); }
    function timed(metrics, key, action) {
        var entry = metrics[key], started = now();
        entry.count++;
        try { return action(); }
        finally { entry.totalMs += Math.max(0, now() - started); entry.averageMs = entry.totalMs / entry.count; }
    }
    function metric() { return { count: 0, totalMs: 0, averageMs: 0 }; }
    function removeTagged(collection, values, cleanup) {
        for (var i = 0; i < values.length; i++) {
            try {
                // Recheck the tag immediately before each deletion.
                if (!tagged(values[i].ref.comments)) continue;
                var started = now();
                cleanup.attempted++;
                try { collection.deleteMarker(values[i].ref); }
                finally { cleanup.totalMs += Math.max(0, now() - started); }
            } catch (e) { cleanup.errors.push(String(e.message || e)); }
        }
    }
    return {
        list: function () { return guarded(function () {
            var found = projectItems(), result = [];
            for (var i = 0; i < found.items.length; i++) result.push({ nodeId: String(found.items[i].nodeId), name: String(found.items[i].name || "") });
            return { ok: true, documentId: String(found.project.documentID), projectName: String(found.project.name || ""), items: result, tag: TAG, scope: SCOPE };
        }); },
        run: function (documentId, nodeId, tag, scope, count) { return guarded(function () {
            if (count === undefined) count = 10;
            if (typeof count !== "number" || !isFinite(count) || count < 1 || count > 100 || Math.floor(count) !== count) throw new Error("N must be an integer in 1..100.");
            var collection = target(documentId, nodeId, tag, scope), before = rows(collection), created = [], i, j;
            for (i = 0; i < before.length; i++) if (tagged(before[i].comments)) throw new Error("Probe-tagged markers already exist; inspect and clean before running.");
            // Reserve empty source positions before any writes, including move targets.
            var positions = [], candidate = 1;
            while (positions.length < count) {
                if (candidate > 100000) throw new Error("No free probe positions within limit.");
                var occupied = false;
                for (j = 0; j < before.length; j++) if (Math.abs(before[j].start - candidate) < 1 || Math.abs(before[j].start - (candidate + 0.5)) < 1) occupied = true;
                if (!occupied) positions.push(candidate);
                candidate += 2;
            }
            var metrics = { createMarker: metric(), name: metric(), comments: metric(), end: metric(),
                setColorByIndex: metric(), getColorByIndex: metric(), deleteMarker: metric(), collectionRead: metric() };
            var result = { ok: false, count: count, documentId: documentId, nodeId: nodeId, tag: TAG, scope: SCOPE,
                beforeCount: before.length, sourcePositions: positions, metrics: metrics, moves: [], deletionVerified: false,
                cleanup: { attempted: 0, totalMs: 0, errors: [], verified: false } };
            try {
                for (i = 0; i < count; i++) {
                    var marker = timed(metrics, "createMarker", function () { return collection.createMarker(positions[i]); });
                    if (!marker) throw new Error("createMarker returned no marker; inspect throwaway project.");
                    var row = { ref: marker, guid: String(marker.guid || "") };
                    if (contains(before, row) || contains(created, row) || String(marker.name || "") || String(marker.comments || "") || String(marker.type || "Comment") !== "Comment") throw new Error("createMarker returned an existing/nonblank marker; left untouched.");
                    created.push(row);
                    if (Math.abs(seconds(marker.start) - positions[i]) > 0.000001) throw new Error("Created marker position differs; inspect untagged marker manually.");
                    // Tag before other writes; setup cost is separate from measured comments writes.
                    marker.comments = TAG;
                    if (!tagged(marker.comments)) throw new Error("Probe tag readback failed; inspect untagged marker manually.");
                }
                for (i = 0; i < count; i++) {
                    var m = created[i].ref;
                    if (!tagged(m.comments)) throw new Error("Probe tag missing; marker retained.");
                    timed(metrics, "name", function () { m.name = "PVS WRITE COST " + i; });
                    timed(metrics, "comments", function () { m.comments = TAG + "\nwrite " + i; });
                    if (String(m.comments) !== TAG + "\nwrite " + i) throw new Error("Comments write readback failed; marker retained unless tagged.");
                    timed(metrics, "end", function () { m.end = positions[i] + 0.75; });
                    timed(metrics, "setColorByIndex", function () { m.setColorByIndex(3); });
                    var color = Number(timed(metrics, "getColorByIndex", function () { return m.getColorByIndex(); }));
                    if (String(m.name) !== "PVS WRITE COST " + i || String(m.comments) !== TAG + "\nwrite " + i ||
                        Math.abs(seconds(m.end) - (positions[i] + 0.75)) > 0.000001 || color !== 3) throw new Error("Property write readback failed.");
                }
                timed(metrics, "collectionRead", function () { return rows(collection); });
                // Try both assignment forms independently; read the actual start even after a throw.
                for (i = 0; i < 2; i++) {
                    var move = { form: i === 0 ? "Time" : "seconds", before: seconds(created[0].ref.start), requested: positions[0] + (i === 0 ? 0.25 : 0.5), assignmentError: null, readError: null, after: null, accepted: false };
                    result.moves.push(move);
                    try {
                        var value = move.requested;
                        if (i === 0) { value = new Time(); value.seconds = move.requested; }
                        created[0].ref.start = value;
                    } catch (moveError) { move.assignmentError = String(moveError.message || moveError); }
                    try { move.after = seconds(created[0].ref.start); move.accepted = Math.abs(move.after - move.requested) <= 0.000001; }
                    catch (readError) { move.readError = String(readError.message || readError); }
                }
                for (i = 0; i < count; i++) {
                    if (!tagged(created[i].ref.comments)) throw new Error("Probe tag missing before deletion.");
                    timed(metrics, "deleteMarker", function () { collection.deleteMarker(created[i].ref); });
                }
                result.deletionVerified = fingerprint(rows(collection)) === fingerprint(before);
                if (!result.deletionVerified) throw new Error("Timed deletion verification failed; cleanup will attempt remaining tagged additions.");
                result.ok = true;
            } catch (e) { result.error = String(e.message || e); }
            finally {
                try {
                    // Discover tagged additions even if createMarker mutated then threw.
                    var current, additions = [];
                    try {
                        current = rows(collection);
                        for (i = 0; i < current.length; i++) if (!contains(before, current[i])) additions.push(current[i]);
                    } catch (enumerationError) {
                        // A failed metadata read must not prevent cleanup of known creations.
                        additions = created;
                        result.cleanup.errors.push("Cleanup enumeration: " + String(enumerationError.message || enumerationError));
                    }
                    removeTagged(collection, additions, result.cleanup);
                    var after = rows(collection);
                    result.afterCount = after.length;
                    result.cleanup.verified = fingerprint(after) === fingerprint(before);
                    if (!result.cleanup.verified) result.cleanup.errors.push("Collection differs from pre-probe state; inspect throwaway project. Untagged additions are never deleted.");
                } catch (cleanupError) { result.cleanup.errors.push(String(cleanupError.message || cleanupError)); }
                if (!result.cleanup.verified || result.cleanup.errors.length) result.ok = false;
            }
            return result;
        }); },
        cleanup: function (documentId, nodeId, tag, scope) { return guarded(function () {
            var collection = target(documentId, nodeId, tag, scope), before = rows(collection), expected = [], cleanup = { attempted: 0, totalMs: 0, errors: [], verified: false };
            for (var i = 0; i < before.length; i++) if (!tagged(before[i].comments)) expected.push(before[i]);
            removeTagged(collection, before, cleanup);
            cleanup.verified = fingerprint(rows(collection)) === fingerprint(expected);
            return { ok: cleanup.verified && !cleanup.errors.length, cleanup: cleanup };
        }); }
    };
}());
