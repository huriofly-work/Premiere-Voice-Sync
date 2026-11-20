"use strict";
const assert = require("assert"), fs = require("fs"), path = require("path"), vm = require("vm");
const source = fs.readFileSync(path.join(__dirname, "../../extension/js/main.js"), "utf8");
const hostSource = fs.readFileSync(path.join(__dirname, "../../extension/jsx/host.jsx"), "utf8");
const start = source.indexOf("  function captionStateKey(");
const end = source.indexOf("  async function checkInputs(", start);
assert(start >= 0 && end > start);
function read(options = {}) {
  let inReads = 0, outReads = 0;
  const videoTracks = [], audioTracks = [];
  videoTracks.numTracks = audioTracks.numTracks = 0;
  const sequence = { sequenceID: "seq", timebase: 254016000000 / 30, videoTracks, audioTracks,
    getSelection: () => {
      assert(!options.stateOnly, "The import guard must not rescan timeline selection.");
      return [{ mediaType: "Video", name: "Selected", start: {seconds:0}, end: {seconds:10} }];
    },
    getInPoint: () => { inReads++; return options.inPoint === undefined ? "-400000" : options.inPoint; },
    getOutPoint: () => { outReads++; return "60"; }
  };
  if (options.tracks !== undefined) sequence.captionTracks = options.tracks;
  if (options.throwIn) sequence.getInPoint = () => { throw Error("IN_READ_FAILED"); };
  const children = [{name:"Source.srt"},{name:"PVS_TEMP_SUBTITLE_123"}]; children.numItems = children.length;
  const host = {app:{project:{activeSequence:options.noSequence ? null : sequence,rootItem:{children}}},$:{_PVS:{}},Folder:{startup:{fsName:"fixture"}}};
  vm.runInNewContext(hostSource, host);
  const panel = {};
  vm.runInNewContext(source.slice(start, end) + "this.key = captionStateKey;", panel);
  const scan = host.$._PVS.scanCaptionRange;
  const state = options.stateOnly ? JSON.parse(scan(options.sequenceId || "seq")) : JSON.parse(scan()).captionState;
  const snapshot = panel.key(state);
  assert.strictEqual(inReads, 1, "Read In once per scan.");
  assert.strictEqual(outReads, 1, "Read Out once per scan.");
  assert.strictEqual(children.length, 2, "Reading the guard must not create/delete Project items.");
  return JSON.parse(snapshot);
}
for (const stateOnly of [false, true]) {
  assert.deepStrictEqual(read({stateOnly}), {count:null,bins:1,inPoint:-400000,outPoint:60});
  assert.strictEqual(read({stateOnly,tracks:null}).count, null);
  for (const count of [0, 1, 5]) assert.strictEqual(read({stateOnly,tracks:{numTracks:count}}).count,count);
  for (const numTracks of [undefined, null, -1, 0.5, "0", NaN, Infinity]) assert.throws(() => read({stateOnly,tracks:{numTracks}}), /Không đọc được trạng thái/);
  for (const inPoint of [null, "", "   ", "bad", Infinity]) assert.throws(() => read({stateOnly,inPoint}), /Không đọc được trạng thái/);
}
assert.throws(() => read({stateOnly:true,noSequence:true}), /Active sequence changed/);
assert.throws(() => read({stateOnly:true,sequenceId:"other"}), /Active sequence changed/);
assert.throws(() => read({stateOnly:true,throwIn:true}), /IN_READ_FAILED/);
console.log("CAPTION_STATE_OK:full-and-state-only-scan;one-InOut-read;missing-captionTracks-is-unknown;invalid-state-blocks;sequence-guard;read-only");
