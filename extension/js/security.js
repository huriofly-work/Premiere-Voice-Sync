(function (root, factory) {
  var api = factory();
  if (typeof module === "object" && module.exports) module.exports = api;
  if (root) root.PvsSecurity = api;
}(typeof window !== "undefined" ? window : null, function () {
  "use strict";
  function assertNoLinks(fs, path, target, tree) {
    var full = path.resolve(target), cursor = full, chain = [], i;
    while (cursor) {
      chain.unshift(cursor);
      var parent = path.dirname(cursor);
      if (parent === cursor) break;
      cursor = parent;
    }
    // From the root down: an lstat of a deeper path would already pass through a link above it
    // (for example a junction to a network share) before that link is seen.
    for (i = 0; i < chain.length; i++) {
      try { if (fs.lstatSync(chain[i]).isSymbolicLink()) throw new Error("SECURITY_LINKED_PATH"); }
      catch (error) { if (error.code !== "ENOENT") throw error; }
    }
    if (tree && fs.existsSync(full) && fs.lstatSync(full).isDirectory()) {
      fs.readdirSync(full).forEach(function (name) { assertNoLinks(fs, path, path.join(full, name), true); });
    }
  }
  function removeOwnedTree(fs, path, target, allowedRoot) {
    var full = path.resolve(target), parent = path.resolve(allowedRoot);
    if (full.toLowerCase().indexOf(parent.toLowerCase() + path.sep) !== 0) throw new Error("SECURITY_DELETE_OUTSIDE_ROOT");
    assertNoLinks(fs, path, full, true);
    function remove(item) {
      if (!fs.existsSync(item)) return;
      var stat = fs.lstatSync(item);
      if (stat.isSymbolicLink()) throw new Error("SECURITY_LINKED_PATH");
      if (stat.isDirectory()) {
        fs.readdirSync(item).forEach(function (name) { remove(path.join(item, name)); });
        fs.rmdirSync(item);
      } else fs.unlinkSync(item);
    }
    remove(full);
  }
  function redactLog(text, privateValues) {
    var output = String(text || "");
    (privateValues || []).filter(function (value) { return value && String(value).length > 2; }).sort(function (a, b) { return String(b).length - String(a).length; }).forEach(function (value) {
      output = output.split(String(value)).join("[PRIVATE]");
    });
    output = output.replace(/[A-Za-z]:[\\/][^\r\n"<>|]*/g, "[LOCAL_PATH]");
    output = output.replace(/\\\\[^\r\n"<>|]+/g, "[NETWORK_PATH]");
    output = output.replace(/\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b/gi, "[EMAIL]");
    output = output.replace(/\b(?:gh[pousr]_[A-Za-z0-9_]+|github_pat_[A-Za-z0-9_]+)\b/g, "[TOKEN]");
    return output;
  }
  return { assertNoLinks: assertNoLinks, removeOwnedTree: removeOwnedTree, redactLog: redactLog };
}));
