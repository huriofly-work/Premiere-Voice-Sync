"use strict";
// ExtendScript groups an unparenthesized nested conditional from the left:
// `a ? b : c ? d : e` runs as `(a ? b : c) ? d : e` (native check 2026-11-18,
// Premiere 2026: "P" where V8 gives "N"). Mocks run on V8 and cannot see it,
// so every ExtendScript source must parenthesize a conditional nested in
// another conditional's branch.
const assert = require("node:assert/strict"), fs = require("node:fs"), path = require("node:path"), vm = require("node:vm");
const root = path.resolve(__dirname, "../..");
const parser = {};
vm.runInNewContext(process.binding("natives")["internal/deps/acorn/acorn/dist/acorn"], { exports: parser, module: { exports: parser } });

function nestedWithoutParentheses(source) {
    const ast = parser.parse(source, { ecmaVersion: 5, locations: true }), hits = [];
    function wrapped(node) {
        let before = node.start - 1, after = node.end;
        while (before >= 0 && /\s/.test(source[before])) before--;
        while (after < source.length && /\s/.test(source[after])) after++;
        return source[before] === "(" && source[after] === ")";
    }
    (function walk(node) {
        if (!node || typeof node.type !== "string") return;
        if (node.type === "ConditionalExpression") {
            for (const branch of [node.consequent, node.alternate]) {
                if (branch.type === "ConditionalExpression" && !wrapped(branch)) hits.push(node.loc.start.line);
            }
        }
        for (const key of Object.keys(node)) {
            const value = node[key];
            if (Array.isArray(value)) value.forEach(walk);
            else if (value && typeof value.type === "string") walk(value);
        }
    })(ast);
    return hits;
}

// The rule itself: flags the ambiguous form, accepts the parenthesized one.
assert.deepEqual(nestedWithoutParentheses('var k = a ? "n" : b ? "p" : "";'), [1]);
assert.deepEqual(nestedWithoutParentheses('var k = a ? b ? 1 : 2 : 3;'), [1]);
assert.deepEqual(nestedWithoutParentheses('var k = a ? "n" : (b ? "p" : "");'), []);
assert.deepEqual(nestedWithoutParentheses('var k = (a ? 1 : 2) ? 3 : 4;'), []);

const files = [
    "extension/jsx/host.jsx",
    "extension/jsx/diagnostic-executor.jsx",
    "extension/js/caption-input.js",
    "tools/diagnostic-fast-support.jsx",
    ...fs.readdirSync(path.join(root, "tools/probes")).filter(name => name.endsWith(".jsx")).map(name => "tools/probes/" + name)
];
const offenders = [];
for (const file of files) {
    for (const line of nestedWithoutParentheses(fs.readFileSync(path.join(root, file), "utf8"))) offenders.push(file + ":" + line);
}
assert.deepEqual(offenders, [], "Parenthesize nested conditionals in ExtendScript sources");

// #72: review markers keyed the voice source as "path:" while the pre-commit
// owners used "node:", so the early review write never found its source.
// Every marker owner must take its key from the one shared helper.
const host = fs.readFileSync(path.join(root, "extension/jsx/host.jsx"), "utf8");
assert.equal(host.split('"node:" +').length - 1, 1, "Only $._PVS._projectItemKey builds node: keys");
assert.equal(host.split('"path:" +').length - 1, 1, "Only $._PVS._projectItemKey builds path: keys");
const context = vm.createContext({ $: { _PVS: {} } });
vm.runInContext(host, context);
const key = context.$._PVS._projectItemKey;
assert.equal(key({ nodeId: "000f42bc", treePath: "\\Project\\voice.wav" }), "node:000f42bc");
assert.equal(key({ nodeId: "", treePath: "\\Project\\voice.wav" }), "path:\\Project\\voice.wav");
assert.equal(key({ treePath: "\\Project\\voice.wav" }), "path:\\Project\\voice.wav");
assert.equal(key({}), "");
assert.equal(key(null), "");
assert.equal(key({ get nodeId() { throw Error("unreadable"); }, treePath: "\\p" }), "path:\\p");
console.log("ES3_NESTED_TERNARY_OK:" + files.length + " files;shared-source-key");
