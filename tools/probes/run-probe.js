"use strict";

const path = require("node:path");
const fs = require("node:fs");

function literal(value) {
    return JSON.stringify(value).replace(/\u2028/g, "\\u2028").replace(/\u2029/g, "\\u2029");
}

function scriptFor(args) {
    const [command, ...rest] = args;
    if (command === "cost-list" && rest.length === 0) return "$._PVSMarkerWriteCostProbe.list()";
    if (command === "move-list" && rest.length === 0) return "$._PVSMarkerMoveEndProbe.list()";
    if (command === "restore-list" && rest.length === 0) return "$._PVSMarkerRestoreProbe.list()";
    if (command === "restore-projection") {
        if (rest.length !== 1 || !/^\d+$/.test(rest[0]) || !Number.isSafeInteger(Number(rest[0]))) throw Error("Usage: restore-projection <audioTrackIndex>");
        return `$._PVSMarkerRestoreProbe.projection(${Number(rest[0])})`;
    }
    if (command === "stale-capture") {
        if (rest.length !== 1 || !/^\d+$/.test(rest[0])) throw Error("Usage: stale-capture <audioTrackIndex>");
        return `$._PVSStaleTrackItemProbe.capture(${Number(rest[0])})`;
    }
    if (command === "stale-compare" && rest.length === 0) return "$._PVSStaleTrackItemProbe.compare()";
    if (command === "stale-release" && rest.length === 0) return "$._PVSStaleTrackItemProbe.release()";
    if (["move-run", "move-cleanup"].includes(command)) {
        if (rest.length !== 4 || rest.some(v => typeof v !== "string" || !v)) throw Error("Usage: move-run|move-cleanup <documentId> <nodeId> <tag> <scope>");
        return `$._PVSMarkerMoveEndProbe.${command === "move-run" ? "run" : "cleanup"}(${rest.map(literal).join(",")})`;
    }
    if (["restore-run", "restore-cleanup"].includes(command)) {
        if (rest.length !== 4 || rest.some(v => typeof v !== "string" || !v)) throw Error("Usage: restore-run|restore-cleanup <documentId> <nodeId> <tag> probe-tagged-only");
        return `$._PVSMarkerRestoreProbe.${command === "restore-run" ? "run" : "cleanup"}(${rest.map(literal).join(",")})`;
    }
    if (["cost-run", "cost-cleanup"].includes(command)) {
        const max = command === "cost-run" ? 5 : 4;
        if (rest.length < 4 || rest.length > max || rest.slice(0, 4).some(v => typeof v !== "string" || !v)) throw Error("Usage: cost-run|cost-cleanup <documentId> <nodeId> <tag> <scope> [N for cost-run only]");
        const values = rest.slice(0, 4);
        if (rest.length === 5) {
            if (!/^\d+$/.test(rest[4]) || Number(rest[4]) < 1 || Number(rest[4]) > 100) throw Error("N must be an integer in 1..100.");
            values.push(Number(rest[4]));
        }
        return `$._PVSMarkerWriteCostProbe.${command === "cost-run" ? "run" : "cleanup"}(${values.map(literal).join(",")})`;
    }
    if (command === "load" && rest.length === 1) {
        if (!path.isAbsolute(rest[0])) throw Error("load requires an absolute JSX path.");
        const file = rest[0].replace(/\\/g, "/");
        if (!fs.statSync(file).isFile()) throw Error("Probe JSX is not a file.");
        return `(function(){try{var file=new File(${literal(file)});file.encoding="UTF-8";$.evalFile(file);` +
            `return '{"ok":true,"loaded":true}';}catch(e){return '{"ok":false,"error":"Probe load failed"}';}})()`;
    }
    const arities = { list: [0, 1], create: [3, 3], read: [2, 2], remove: [2, 2] };
    const [method, ...raw] = rest;
    if (command !== "call" || !Object.hasOwn(arities, method) ||
        raw.length < arities[method][0] || raw.length > arities[method][1]) {
        throw Error("Usage: node tools/probes/run-probe.js [port=8099] load <absolute JSX path> | call list [track] | call create <track> <clip> <source-offset> | call read|remove <track> <clip>");
    }
    const numbers = raw.map((value, i) => {
        if (!/^[+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:e[+-]?\d+)?$/i.test(value)) throw Error("Arguments must be finite numbers.");
        const number = Number(value);
        if (!Number.isFinite(number) || (i < 2 && (number < 0 || !Number.isInteger(number)))) throw Error("Track/clip indices must be nonnegative integers; offset must be finite.");
        return number;
    });
    return `$._PVSProbe.${method}(${numbers.map(literal).join(",")})`;
}

function isPanel(page) {
    // Require the panel id, or the product name AND index.html. Never pick a generic CEP page.
    const label = `${page.title || ""} ${page.url || ""}`;
    return page.type === "page" && !!page.webSocketDebuggerUrl &&
        (/com\.premierevoicesync\.local\.panel(?:\b|\/)/i.test(label) ||
         (/index\.html(?:[?#\s]|$)/i.test(page.url || "") &&
          /com\.premierevoicesync\.local\b|premiere[\s_-]*voice[\s_-]*sync/i.test(label)));
}

async function evaluate(url, script, timeoutMs = 30000) {
    const endpoint = new URL(url);
    if (!["ws:", "wss:"].includes(endpoint.protocol) ||
        !["localhost", "127.0.0.1", "[::1]"].includes(endpoint.hostname)) throw Error("Debugger WebSocket must be localhost.");
    return new Promise((resolve, reject) => {
        const socket = new WebSocket(endpoint);
        const timer = setTimeout(() => finish(Error(`CDP/evalScript timed out after ${timeoutMs / 1000}s. A native mutation may have happened; inspect/read before retrying.`)), timeoutMs);
        let finished = false;
        function finish(error, value) {
            if (finished) return;
            finished = true;
            clearTimeout(timer);
            socket.close();
            if (error) reject(error); else resolve(value);
        }
        socket.addEventListener("error", () => finish(Error("Debugger WebSocket connection failed.")));
        socket.addEventListener("close", () => finish(Error("Debugger disconnected before evalScript returned.")));
        socket.addEventListener("open", () => {
            const expression = `new Promise(function(resolve,reject){if(!window.__adobe_cep__ || typeof window.__adobe_cep__.evalScript!=="function"){reject(new Error("CEP evalScript unavailable"));return;}window.__adobe_cep__.evalScript(${literal(script)},resolve);})`;
            socket.send(JSON.stringify({ id: 1, method: "Runtime.evaluate", params: {
                expression, awaitPromise: true, returnByValue: true
            } }));
        });
        socket.addEventListener("message", event => {
            try {
                const packet = JSON.parse(event.data);
                if (packet.id !== 1) return;
                if (packet.error) throw Error(`CDP: ${packet.error.message}`);
                if (packet.result?.exceptionDetails) throw Error(`Panel evaluation failed: ${packet.result.exceptionDetails.exception?.description || packet.result.exceptionDetails.text}`);
                const value = packet.result?.result?.value;
                if (typeof value !== "string") throw Error("evalScript did not return a string.");
                if (value.trim() === "EvalScript error.") throw Error("CEP returned EvalScript error. Load the probe first and check the ExtendScript error.");
                finish(null, JSON.parse(value));
            } catch (error) { finish(error); }
        });
    });
}

async function main(args) {
    if (typeof WebSocket !== "function" || typeof fetch !== "function") throw Error("Node 22+ with global WebSocket and fetch is required.");
    let port = 8099;
    if (/^\d+$/.test(args[0] || "")) port = Number(args.shift());
    if (!Number.isInteger(port) || port < 1 || port > 65535) throw Error("Port must be 1..65535.");
    const script = scriptFor(args);
    const response = await fetch(`http://localhost:${port}/json`, { signal: AbortSignal.timeout(5000) });
    if (!response.ok) throw Error(`Debugger /json returned HTTP ${response.status}.`);
    const pages = await response.json();
    if (!Array.isArray(pages)) throw Error("Debugger /json did not return a page list.");
    const matches = pages.filter(isPanel);
    if (!matches.length) throw Error("No Premiere Voice Sync panel page found. Check .debug, PlayerDebugMode and the open panel.");
    if (matches.length !== 1) throw Error("Multiple Premiere Voice Sync panel pages found; use the port for exactly one panel.");
    const result = await evaluate(matches[0].webSocketDebuggerUrl, script, args[0] === "cost-run" || args[0] === "cost-cleanup" ? 600000 : 30000);
    console.log(JSON.stringify(result, null, 2));
    if (result?.ok === false) process.exitCode = 1;
}

if (require.main === module) main(process.argv.slice(2)).catch(error => {
    console.error(`PROBE_FAILED: ${error.message}`);
    process.exitCode = 1;
});

module.exports = { scriptFor, isPanel, main };
