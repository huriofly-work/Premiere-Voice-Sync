"use strict";
const assert = require("assert");
const fs = require("fs");
const path = require("path");
const os = require("os");
const security = require("../../extension/js/security.js");
const root = fs.mkdtempSync(path.join(os.tmpdir(), "PVS-SecurityNode-"));
const own = path.join(root, "owned");
const other = path.join(root, "unrelated");
let checks = 0;
function rejects(fn) { assert.throws(fn, /SECURITY_/); checks++; }
try {
  fs.mkdirSync(own); fs.mkdirSync(other);
  fs.writeFileSync(path.join(other, "keep.txt"), "KEEP");
  rejects(() => security.removeOwnedTree(fs, path, root, root));
  rejects(() => security.removeOwnedTree(fs, path, other, own));
  const link = path.join(own, "link");
  fs.symlinkSync(other, link, process.platform === "win32" ? "junction" : "dir");
  rejects(() => security.assertNoLinks(fs, path, path.join(link, "new.txt"), false));
  // Ancestors are checked from the root down, so no path below the link is probed first
  // (an lstat there would already pass through the link, e.g. a junction to a network share).
  {
    const seen = [], realLstat = fs.lstatSync, below = path.join(link, "deep").toLowerCase();
    fs.lstatSync = function (p) { seen.push(String(p)); return realLstat.apply(this, arguments); };
    try { rejects(() => security.assertNoLinks(fs, path, path.join(link, "deep", "new.txt"), false)); }
    finally { fs.lstatSync = realLstat; }
    assert.strictEqual(seen.some(p => p.toLowerCase().startsWith(below)), false); checks++;
    assert.strictEqual(seen[seen.length - 1].toLowerCase(), link.toLowerCase()); checks++;
  }
  rejects(() => security.removeOwnedTree(fs, path, own, root));
  assert.strictEqual(fs.readFileSync(path.join(other, "keep.txt"), "utf8"), "KEEP"); checks++;
  fs.unlinkSync(link);
  fs.mkdirSync(path.join(own, "cache"));
  fs.writeFileSync(path.join(own, "cache", "recognition.json"), "PRIVATE");
  security.removeOwnedTree(fs, path, path.join(own, "cache"), own);
  assert(!fs.existsSync(path.join(own, "cache"))); checks++;
  const raw = 'USER_A Video secret email@example.com ghp_EXAMPLE_SECRET\nC:\\Users\\USER_A\\Videos\\secret.mp4\n\\\\server\\share\\data\n';
  const redacted = security.redactLog(raw, ["USER_A", "Video secret"]);
  ["USER_A", "Video secret", "email@example.com", "ghp_EXAMPLE_SECRET", "secret.mp4", "server"].forEach(value => { assert(!redacted.includes(value)); checks++; });
  console.log("SECURITY_NODE_OK:checks=" + checks);
} finally { fs.rmSync(root, { recursive: true, force: true }); }
