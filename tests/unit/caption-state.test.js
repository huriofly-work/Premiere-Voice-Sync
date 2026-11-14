"use strict";
const assert = require("assert"), fs = require("fs"), path = require("path"), vm = require("vm");
const source = fs.readFileSync(path.join(__dirname, "../../extension/js/main.js"), "utf8");
const start = source.indexOf("  async function captionTrackCount(");
const end = source.indexOf("  function saveRecoveryJournal(", start);
assert(start >= 0 && end > start);
async function read(options = {}) {
  const sequence = { sequenceID: "seq", getInPoint: () => options.inPoint === undefined ? "-400000" : options.inPoint, getOutPoint: () => "60" };
  if (options.tracks !== undefined) sequence.captionTracks = options.tracks;
  if (options.throwIn) sequence.getInPoint = () => { throw Error("IN_READ_FAILED"); };
  const children = [{name:"Source.srt"},{name:"PVS_TEMP_SUBTITLE_123"}]; children.numItems = children.length;
  const host = {app:{project:{activeSequence:options.noSequence ? null : sequence,rootItem:{children}}},$:{_PVS:{_result:JSON.stringify}}};
  const panel = {jsxString:JSON.stringify, evalHost:async script => JSON.parse(vm.runInNewContext(script, host))};
  vm.runInNewContext(source.slice(start, end) + "this.read = captionTrackCount;", panel);
  const snapshot = await panel.read(options.sequenceId || "seq");
  assert.strictEqual(sequence.getOutPoint(), "60");
  assert.strictEqual(children.length, 2, "Reading the guard must not create/delete Project items.");
  return JSON.parse(snapshot);
}
(async () => {
  assert.deepStrictEqual(await read(), {count:null,bins:1,inPoint:-400000,outPoint:60});
  assert.strictEqual((await read({tracks:null})).count, null);
  for (const count of [0, 1, 5]) assert.strictEqual((await read({tracks:{numTracks:count}})).count,count);
  for (const numTracks of [undefined, null, -1, 0.5, "0", NaN, Infinity]) await assert.rejects(read({tracks:{numTracks}}), /Không đọc được trạng thái/);
  for (const inPoint of [null, "", "   ", "bad", Infinity]) await assert.rejects(read({inPoint}), /Không đọc được trạng thái/);
  await assert.rejects(read({noSequence:true}), /Active sequence changed/);
  await assert.rejects(read({sequenceId:"other"}), /Active sequence changed/);
  await assert.rejects(read({throwIn:true}), /IN_READ_FAILED/);
  console.log("CAPTION_STATE_OK:real-host-expression;missing-captionTracks-is-unknown;valid-counts;invalid-counts-and-InOut-block;sequence-guard;host-error-details;read-only");
})().catch(error => {console.error(error);process.exitCode=1;});
