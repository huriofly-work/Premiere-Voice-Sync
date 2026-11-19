"use strict";

const assert = require("assert");
const vm = require("vm");
const { host, diagnostic, markerReferenceCases, markerReferenceFixture, finishTrial } =
  require("./diagnostic-executor.test");

const ownedTag = "[PremiereVoiceSync:owned-marker:v1]";
const reviewTag = /\[PremiereVoiceSync:review-marker:(?:v2:([^:\]]+):[^\]]+|v3:([^:\]]+))\]/;
const fault = "A1_INJECTED_FAULT";
const stopped = "DIAGNOSTIC_STOPPED_PARTIAL_TIMELINE";
const profiles = ["direct", "baseline", "fast", "no-delay"];
const tick = 1 / 254016000000;

function replaceOnce(source, anchor, replacement) {
  const pattern = typeof anchor === "string" ? source.split(anchor).length - 1 : [...source.matchAll(anchor)].length;
  assert.equal(pattern, 1, "Review test hook location: " + anchor);
  return source.replace(anchor, replacement);
}

function instrument(source, direct) {
  const before = (anchor, hook) => {
    source = replaceOnce(source, anchor, match => hook + "\n" + match);
  };
  const after = (anchor, hook) => {
    source = replaceOnce(source, anchor, match => match + "\n" + hook);
  };
  // Staged Stop is available between calls. These hooks interrupt operations
  // that can share a host call, and supply boundaries for synchronous direct.
  after('noteNative("after", "set-speed");', 'partialProbe.hit("first-speed");');
  assert.equal(source.split('noteNative("after", "razor");').length, 3);
  source = source.replace('noteNative("after", "razor");',
    'noteNative("after", "razor"); partialProbe.hit("first-razor");');
  after(/for \((?:var voiceCutIndex = 0)?; voiceCutIndex < voiceCuts.length; voiceCutIndex\+\+\) \{/g,
    'if (voiceClips.length > 1 && voiceCuts[voiceCutIndex] >= Math.round(voiceClips[1].start * fps)) partialProbe.hit("between-chapters");');
  if (direct) {
    after("for (var markerOwnerIndex = 0; markerOwnerIndex < cleanupOwners.length; markerOwnerIndex++) {",
      'if (markerOwnerIndex === 2) partialProbe.hit("between-chapter-commits");');
    before("var plannedClipMarkers = voiceMarkerSpecs(asArray(plan.markers));", 'partialProbe.hit("after-post-check");');
    before(/try \{\s+var rulerCleanup = cleanLegacyOwnedRulerMarkers\(workingSequence, plannedEndFrame \/ fps, fps\);/g,
      'partialProbe.hit("after-source-markers");');
    before("report = {\n            ok: masterInOutReset", 'partialProbe.hit("after-post-review");');
    before("var maxVideoError = 0;", 'partialProbe.hit("after-caption");');
    before(/\n    \} catch \(e\) \{\n        report = \{ ok: false, executorVersion: 25, timelineMutated/g,
      '\n        partialProbe.hit("after-report");');
  }
  return new vm.Script(source, { filename: direct ? "host.jsx" : "diagnostic-executor.jsx" });
}

const directScript = instrument(host, true);
const stagedScript = instrument(diagnostic, false);

function fields(marker) {
  return {
    guid: marker.guid,
    start: marker.start.seconds,
    end: typeof marker.end === "number" ? marker.end : marker.end.seconds,
    name: marker.name,
    comments: marker.comments,
    type: marker.type,
    color: marker.getColorByIndex ? marker.getColorByIndex() : marker.colorIndex
  };
}

function sortedFields(rows, includeGuid) {
  return rows.map(({ guid, ...rest }) => JSON.stringify(includeGuid ? { guid, ...rest } : rest)).sort();
}

function kind(row) {
  const comments = row.comments || "";
  if (comments.includes(ownedTag)) return row.name;
  const review = comments.match(reviewTag);
  return review ? "review:" + (review[1] || review[2]) : null;
}

function protectedKind(row) {
  const group = kind(row);
  if (group === "review:captions") return "other-workflow";
  if (group) return null;
  if (/^Sentence cues \d+-\d+: actual speed=[0-9.]+%, warning range=/.test(row.comments || "") &&
      row.name === "VOICE SYNC - Kiem tra toc do") return "untagged-legacy";
  return "manual";
}

function addMarker(bank, row) {
  const marker = bank.createMarker(row.start);
  Object.assign(marker, { guid: row.guid, end: row.end, name: row.name, comments: row.comments,
    type: row.type, colorIndex: row.color });
  return marker;
}

function prepare(make, index, profile, stop, { seed, surplus = false, longRange = false } = {}) {
  const f = markerReferenceFixture(make, index);
  const { api } = f;
  const readPlan = api._readJsonFile;
  const findCaption = api._findItemByMediaPath;
  const probe = { hits: 0, half: null, writeFailure: null, voiceCommits: 0,
    hit(point) {
      if (point !== stop) return;
      probe.hits++;
      throw Error(fault + ":" + point);
    }
  };
  f.context.partialProbe = probe;
  directScript.runInContext(f.context);
  if (profile !== "direct") stagedScript.runInContext(f.context);
  api._readJsonFile = readPlan;
  api._findItemByMediaPath = findCaption;

  const owners = [f.voice, ...(f.secondVoice ? [f.secondVoice] : [])];
  const voiceBanks = owners.map(item => item.getMarkers());
  const banks = [...voiceBanks, f.nested.getMarkers(), f.seq.markers];
  const labels = [...owners.map(item => item.nodeId), "nested", "ruler"];
  const initialSpans = owners.map(item => f.seq.audioTracks[f.plan.voiceTrackIndex].clips
    .filter(clip => clip.projectItem === item)
    .map(clip => api._clipMarkerMapping(clip))
    .map(map => [map.source(map.start), map.source(map.end)]));
  if (seed) {
    banks.forEach((bank, i) => {
      bank.items.length = 0;
      seed[i].forEach(row => addMarker(bank, row));
    });
  } else {
    voiceBanks.forEach((bank, i) => {
      const [start] = initialSpans[i][0];
      addMarker(bank, { guid: labels[i] + "-captions", start: start + 0.01, end: start + 0.02,
        type: "Comment", name: "VOICE SYNC - Can kiem tra",
        comments: "Chữ gốc\r\n[PremiereVoiceSync:review-marker:v2:captions:previous]", color: 3 });
    });
    if (surplus) {
      for (const [i, start] of [0.18, 0.32].entries()) {
        addMarker(voiceBanks[0], { guid: "previous-review-" + i, start, end: start + 0.40,
          type: "Comment", name: "VOICE SYNC - Can kiem tra",
          comments: "Previous review " + i + "\n[PremiereVoiceSync:review-marker:v2:edit:previous]", color: 4 });
      }
    }
    if (longRange) voiceBanks[0].items.find(m => m.guid === "old").end = initialSpans[0][0][1] - tick;
  }

  const snapshot = () => banks.map(bank => bank.items.map(fields));
  const original = snapshot();
  const protectedByOwner = original.map(rows => new Map(rows.filter(protectedKind)
    .map(row => [row.guid, protectedKind(row)])));
  const writes = {};
  const writeTrace = [];
  const touched = banks.map(() => new Set());
  const protectedWrites = [];
  const bindings = banks.map(() => new Map());
  const spans = new WeakMap();
  let activeGroup = null;

  function count(i, operation, marker, before, after) {
    writes[operation] = (writes[operation] || 0) + 1;
    const { guid } = marker;
    touched[i].add(guid);
    writeTrace.push({ owner: labels[i], guid, kind: kind(fields(marker)), operation, before, after,
      phase: activeGroup?.phase || null });
    if (protectedByOwner[i].has(guid)) {
      protectedWrites.push({ owner: labels[i], operation, guid, group: protectedByOwner[i].get(guid) });
    }
  }
  function watch(i, marker) {
    const applyColor = marker.setColorByIndex;
    if (applyColor) {
      marker.setColorByIndex = function (color) {
        count(i, "color", this, this.getColorByIndex(), color);
        return applyColor.call(this, color);
      };
    }
    for (const field of ["start", "end", "name", "comments"]) {
      const descriptor = Object.getOwnPropertyDescriptor(marker, field);
      let value = marker[field];
      Object.defineProperty(marker, field, {
        configurable: true, enumerable: true,
        get: descriptor?.get || (() => value),
        set(next) {
          count(i, field, marker, field === "start" ? marker.start.seconds :
            field === "end" ? fields(marker).end : marker[field], next);
          if (stop === "end-write-fault" && field === "end" && marker.guid === "old" &&
              !probe.writeFailure && activeGroup && marker.start.seconds !== original[0].find(row => row.guid === "old").start) {
            const target = activeGroup.desired.find(spec => spec.seconds === marker.start.seconds);
            assert(target && spans.has(target), "End fault must follow a move to a production-planned point");
            const row = fields(marker);
            probe.writeFailure = { row, requestedEnd: next, span: spans.get(target) };
            probe.half = { state: snapshot(), bindings: bindings.slice() };
            probe.half.bindings[0] = new Map(bindings[0]).set(row.guid, { row, span: spans.get(target) });
            throw Error(fault + ":" + stop);
          }
          if (descriptor?.set) descriptor.set.call(this, next);
          else value = next;
        }
      });
    }
    return marker;
  }
  banks.forEach((bank, i) => {
    let serial = 0;
    bank.items.forEach(marker => watch(i, marker));
    const create = bank.createMarker, remove = bank.deleteMarker;
    bank.createMarker = function (seconds) {
      const marker = create.call(this, seconds);
      do { marker.guid = labels[i] + "-new-" + serial++; }
      while (bank.items.some(other => other !== marker && other.guid === marker.guid));
      count(i, "create", marker, undefined, seconds);
      return watch(i, marker);
    };
    bank.deleteMarker = function (marker) {
      count(i, "delete", marker, fields(marker));
      return remove.call(this, marker);
    };
  });

  const tools = api._markerTools;
  const { point, commit } = tools;
  tools.point = function (group, start, end, fps, map) {
    const spec = point(group, start, end, fps, map);
    if (spec && map) spans.set(spec, [map.source(start), map.source(end)]);
    return spec;
  };
  tools.commit = function (group, ...args) {
    activeGroup = { desired: group.desired, phase: "post" };
    try {
      const result = commit(group, ...args);
      if (result.count && group.desired.some(spec => spec.name === "VOICE SYNC - Kiem tra can voice")) {
        probe.voiceCommits++;
      }
      if (!result.failures.length && group.after) {
        for (const spec of group.desired) {
          if (!spans.has(spec)) continue;
          const written = group.after.find(row => row.name === spec.name && row.comments === spec.comments &&
            spec.verify(row.seconds, row.end));
          if (written) {
            // Observed executions wrap the marker collections and their rows.
            const owner = banks.findIndex(bank => bank.items.some(marker => marker.guid === written.guid));
            assert(owner >= 0, "Committed marker is missing from the mock banks");
            bindings[owner].set(written.guid, { row: fields(written.ref), span: spans.get(spec) });
          }
        }
      }
      if (probe.writeFailure && result.failures.some(message => message.includes(fault))) {
        probe.writeFailure.commitErrors = [...result.failures];
        probe.writeFailure.afterCompensation = snapshot()[0].find(row => row.guid === "old");
      }
      return result;
    } finally {
      activeGroup = null;
    }
  };
  if (stop === "during-post-check") {
    const clear = f.nested.clearInPoint;
    f.nested.clearInPoint = () => {
      clear.call(f.nested);
      probe.hit(stop);
    };
  }
  f.actions.length = 0;
  return { f, probe, labels, original, initialSpans, snapshot, bindings, writes, touched, writeTrace, protectedWrites };
}

const stages = {
  "after-source-markers": "Gắn marker"
};
const checkpoints = { "after-post-review": "Marker", "after-post-check": "Hậu kiểm", "after-caption": "Caption" };

function run(test, profile, stop) {
  const { f, probe } = test;
  if (profile === "direct") return { report: JSON.parse(f.api.executePlan("fixture")) };
  if (!stop) return finishTrial(f, profile);
  const token = "partial";
  const abort = () => {
    const response = JSON.parse(f.api.abortDiagnosticEdit(token));
    assert.equal(response.result.error, stopped);
    probe.hits++;
    return { report: response.result };
  };
  let response = JSON.parse(f.api.beginDiagnosticEdit("fixture", token, profile, true));
  assert(response.ok);
  for (let calls = 0; calls < 500; calls++) {
    response = JSON.parse(f.api.advanceDiagnosticEdit(token, response.nextCall));
    if (response.done) {
      if (stop === "after-report") {
        assert(response.result.ok);
        const closed = JSON.parse(f.api.abortDiagnosticEdit(token));
        assert.deepStrictEqual(closed, response, "Closing after completion returns the successful result");
        assert(!JSON.parse(f.api.diagnosticInfo()).active);
        probe.hits++;
        return { report: closed.result };
      }
      if (response.result.ok) assert(JSON.parse(f.api.acceptDiagnosticEdit(token)).ok);
      return { report: response.result };
    }
    if ((stages[stop] === response.stage && response.nextStage !== response.stage) ||
        (checkpoints[stop] && checkpoints[stop] === response.checkpoint) ||
        (stop === "between-chapter-commits" && response.nextStage === stages["after-source-markers"] &&
          probe.voiceCommits === 1)) return abort();
  }
  assert.fail("Missing terminal host response");
}

function positionFailures(test, state, bindings, touchedOnly = true) {
  const failures = [];
  test.initialSpans.forEach((chapterSpans, i) => {
    for (const row of state[i]) {
      if (!kind(row) || (touchedOnly && !test.touched[i].has(row.guid))) continue;
      const binding = bindings[i].get(row.guid);
      const planned = binding && row.start === binding.row.start && row.name === binding.row.name &&
        row.comments === binding.row.comments;
      const unchanged = test.original[i].some(prior => JSON.stringify(prior) === JSON.stringify(row));
      const spans = planned ? [binding.span] : unchanged ? chapterSpans : [];
      if (!(row.end >= row.start && spans.some(([start, end]) => row.start >= start - tick && row.end <= end + tick))) {
        failures.push({ owner: test.labels[i], guid: row.guid, kind: kind(row),
          bounds: [row.start, row.end], spans });
      }
    }
  });
  return failures;
}

function isolationFailures(test, state, writes = test.protectedWrites) {
  const failures = [...writes];
  state.forEach((rows, i) => {
    for (const group of ["manual", "other-workflow", "untagged-legacy"]) {
      const select = row => protectedKind(row) === group;
      for (const prior of test.original[i].filter(select)) {
        const actual = rows.find(row => row.guid === prior.guid);
        if (JSON.stringify(actual) !== JSON.stringify(prior)) {
          failures.push({ owner: test.labels[i], guid: prior.guid, group,
            error: "protected fields differ", before: prior, after: actual || null });
        }
      }
      for (const actual of rows.filter(select)) {
        if (!test.original[i].some(prior => prior.guid === actual.guid)) {
          failures.push({ owner: test.labels[i], guid: actual.guid, group,
            error: "unexpected protected marker", after: actual });
        }
      }
    }
    const byKind = new Map();
    for (const row of rows) {
      const groupKind = kind(row);
      if (!groupKind) continue;
      if (!byKind.has(groupKind)) byKind.set(groupKind, []);
      byKind.get(groupKind).push(row);
    }
    for (const [groupKind, markers] of byKind) {
      markers.sort((a, b) => a.start - b.start);
      for (let n = 1; n < markers.length; n++) {
        const previous = markers[n - 1], next = markers[n];
        if (Math.abs(next.start - previous.start) <= tick || next.start < previous.end - tick) {
          failures.push({ owner: test.labels[i], kind: groupKind, overlap: [previous.guid, next.guid],
            bounds: [[previous.start, previous.end], [next.start, next.end]] });
        }
      }
    }
  });
  return failures;
}

function equalityFailures(test, expected, actual) {
  return actual.flatMap((rows, i) => {
    const wanted = sortedFields(expected[i], false), found = sortedFields(rows, false);
    if (JSON.stringify(wanted) === JSON.stringify(found)) return [];
    const missing = wanted.slice(), extra = [];
    for (const row of found) {
      const index = missing.indexOf(row);
      if (index === -1) extra.push(row);
      else missing.splice(index, 1);
    }
    return [{ owner: test.labels[i], expected: wanted.length, actual: found.length,
      missing: missing.map(JSON.parse), extra: extra.map(JSON.parse) }];
  });
}

function sameEvidence(errors, candidate) {
  return errors.some(error => JSON.stringify(error) === JSON.stringify(candidate));
}

function comparableWrite({ owner, kind, operation, before, after }) {
  return JSON.stringify({ owner, kind, operation, before, after });
}

function repeatedWrites(actual, baseline) {
  // Match transitions, with multiplicity, even if reconciliation picked a different GUID.
  const available = baseline.writeTrace.map(comparableWrite);
  return actual.writeTrace.map(write => {
    const match = available.indexOf(comparableWrite(write));
    if (match === -1) return { class: "partial-worse", ...write };
    available.splice(match, 1);
    return { class: "pre-existing", ...write };
  });
}

const stopPoints = [
  "first-razor", "first-speed", "between-chapters",
  "after-source-markers", "after-post-review", "after-caption", "during-post-check",
  "after-post-check", "after-report", "end-write-fault"
];
const classes = ["pre-existing", "final-marker", "transient-surplus", "partial-worse"];
const counts = () => Object.fromEntries(classes.map(name => [name, 0]));
const summary = {};
const classifiedChecks = counts();
const classifiedCases = counts();
let compensatedOnly = 0;
let harnessFailures = 0;
let injectedFaults = 0;
let compensatedFaults = 0;
let survivingHalfWrites = 0;
function record(row) {
  const tally = summary[row.stop] ||= { total: 0, skipped: 0, harness: 0, passed: 0, ...counts() };
  tally.total++;
  if (row.skip) tally.skipped++;
  else if (row.harness) { tally.harness++; harnessFailures++; }
  else {
    const findings = Object.values(row.checks).flat();
    for (const check of Object.values(row.checks)) {
      const classification = classes.findLast(name => check.some(finding => finding.class === name));
      if (classification) classifiedChecks[classification]++;
    }
    row.class = classes.findLast(name => findings.some(finding => finding.class === name)) || "passed";
    tally[row.class]++;
    if (row.class !== "passed") classifiedCases[row.class]++;
    if (row.halfWrite) {
      injectedFaults++;
      if (row.compensated) compensatedFaults++;
      if (row.faultOutcome.halfRemains) survivingHalfWrites++;
      if (row.class === "passed" && row.faultOutcome.transientPositions.length) compensatedOnly++;
    }
  }
  console.log(JSON.stringify(row));
}

const cases = markerReferenceCases();
assert.equal(cases.length, 42);
for (const [index, make] of cases.entries()) {
  for (const profile of profiles) {
    const reruns = new Map();
    // Targeted stress cases supplement the original indexed fixture matrix.
    const scenarios = stopPoints.map(stop => ({ stop }));
    if (index === 0) {
      scenarios.push({ stop: "end-write-fault", longRange: true });
      scenarios.push({ stop: "after-post-review", surplus: true });
    }
    if (index === 7) scenarios.push({ stop: "between-chapter-commits" });
    const clean = new Map();
    for (const { stop, surplus, longRange } of scenarios) {
      const row = { fixture: index, executor: profile, stop: stop +
        (longRange ? "-long-range" : surplus ? "-retained-surplus" : "") };
      try {
        const flags = { surplus, longRange };
        const flagsKey = JSON.stringify(flags);
        if (!clean.has(flagsKey)) {
          const reference = prepare(make, index, profile, null, flags);
          const { report } = run(reference, profile);
          assert(report.ok, "Clean reference failed: " + JSON.stringify(report));
          const state = reference.snapshot();
          const seedProblems = positionFailures(reference, reference.original, reference.original.map(() => new Map()), false);
          const positions = positionFailures(reference, state, reference.bindings, false);
          const isolation = isolationFailures(reference, state);
          const seedIsolation = isolationFailures(reference, reference.original, []);
          const repeat = prepare(make, index, profile, null, { seed: state });
          const repeatResult = run(repeat, profile).report;
          assert(repeatResult.ok, "Clean-seeded replay failed: " + JSON.stringify(repeatResult));
          const repeatDiff = equalityFailures(repeat, state, repeat.snapshot());
          clean.set(flagsKey, { state, seedProblems, positions, isolation, seedIsolation, repeat, repeatDiff });
          const writesToSeedProblems = reference.writeTrace.filter(write =>
            seedProblems.some(problem => problem.owner === write.owner && problem.guid === write.guid));
          console.log(JSON.stringify({ fixture: index, executor: profile, reference: flagsKey, seedProblems,
            cleanPositions: positions, writesToSeedProblems, cleanIsolation: isolation, cleanRepeat: { writes: repeat.writes,
              trace: repeat.writeTrace, diff: repeatDiff } }));
        }
        const baseline = clean.get(flagsKey);
        const expected = baseline.state;
        const test = prepare(make, index, profile, stop, flags);
        if (stop === "between-chapters" && test.f.plan.voiceClips.length < 2) {
          record({ ...row, skip: "one voice chapter" });
          continue;
        }
        const { report } = run(test, profile, stop);
        if (stop === "end-write-fault" && !test.probe.writeFailure) {
          record({ ...row, skip: "fixture did not move the seeded range before writing its end" });
          continue;
        }
        if (["first-razor", "first-speed"].includes(stop) && !test.probe.hits) {
          assert(report.ok, JSON.stringify(report));
          const operation = stop === "first-razor" ? "razor" : "speed";
          assert(!test.f.actions.some(action => action[0] === operation), "Native mutation escaped hook");
          record({ ...row, skip: "fixture has no " + operation + " operation" });
          continue;
        }
        if (stop !== "end-write-fault") {
          assert.equal(test.probe.hits, 1, "Stop boundary did not run exactly once");
          assert.equal(report.ok, stop === "after-report" && profile !== "direct",
            "Only a completed staged run survives Stop as success");
          if (stop === "during-post-check") assert.strictEqual(report.masterInOutReset, false);
          else if (!report.ok) assert([fault + ":" + stop, stopped].includes(report.error), "Unexpected interruption: " + report.error);
          if (stop === "between-chapter-commits") {
            assert.equal(test.probe.voiceCommits, 1);
            assert(!test.snapshot()[1].some(marker => kind(marker) && kind(marker) !== "review:captions"));
          }
        }
        function rerun(seed) {
          const key = JSON.stringify([flagsKey, seed]);
          if (reruns.has(key)) return reruns.get(key);
          const first = prepare(make, index, profile, null, { seed });
          const result = run(first, profile).report;
          const reconciled = first.snapshot();
          const diff = equalityFailures(first, expected, reconciled);
          const errors = diff.map(error => ({ class: "partial-worse", ...error }));
          if (!result.ok) errors.push({ class: "partial-worse", error: "reconciliation failed", result });
          // Use the same full-run behavior for both idempotency baselines.
          const repeat = prepare(make, index, profile, null, { seed: reconciled });
          const repeatResult = run(repeat, profile).report;
          if (!repeatResult.ok) errors.push({ class: "partial-worse", error: "repeat failed", result: repeatResult });
          const repeatDiff = equalityFailures(repeat, reconciled, repeat.snapshot());
          const repeatWrites = repeatedWrites(repeat, baseline.repeat);
          if (repeatWrites.length) {
            errors.push({ class: repeatWrites.some(write => write.class === "partial-worse") ?
              "partial-worse" : "pre-existing", repeatWrites: repeat.writes, cleanRepeatWrites: baseline.repeat.writes,
              unmatchedWrites: repeatWrites.filter(write => write.class === "partial-worse") });
          }
          errors.push(...repeatDiff.map(error => ({ class: sameEvidence(baseline.repeatDiff, error) ?
            "pre-existing" : "partial-worse", ...error })));
          const outcome = { errors, reconciled, writes: first.writeTrace };
          reruns.set(key, outcome);
          return outcome;
        }

        const state = test.snapshot();
        const a = positionFailures(test, state, test.bindings);
        const b = isolationFailures(test, state);
        const c = rerun(state);
        row.checks = {
          a: a.map(error => ({ class: sameEvidence(baseline.positions, error) ||
            sameEvidence(baseline.seedProblems, error) ? "pre-existing" : "partial-worse", ...error })),
          b: b.map(error => ({ class: sameEvidence(baseline.seedIsolation, error) ? "pre-existing" :
            sameEvidence(baseline.isolation, error) ? (error.overlap ? "pre-existing" : "final-marker") :
              "partial-worse", ...error })),
          c: c.errors
        };
        const untouched = positionFailures(test, state, test.bindings, false)
          .filter(error => !sameEvidence(a, error));
        row.checks.a.push(...untouched.map(error => {
          assert(sameEvidence(baseline.seedProblems, error), "Untouched position differs from the seed");
          return { class: "pre-existing", excludedFromPositionCheck: true, ...error };
        }));
        if (surplus) {
          const select = rows => rows[0].filter(marker => kind(marker) === "review:edit");
          row.review = { owner: test.labels[0], seed: select(test.original), partial: select(state),
            clean: select(expected), reconciled: select(c.reconciled),
            rerunWrites: c.writes.filter(write => write.kind === "review:edit") };
          assert.deepStrictEqual(row.review.partial, row.review.clean);
          assert.deepStrictEqual(row.review.reconciled, row.review.clean);
        }
        if (test.probe.half) {
          const half = test.probe.half;
          const transientPositions = positionFailures(test, half.state, half.bindings, false);
          const after = test.probe.writeFailure.afterCompensation;
          assert(after && test.probe.writeFailure.commitErrors, "Commit did not consume the injected field fault");
          row.halfWrite = test.probe.writeFailure;
          const prior = test.original[0].find(marker => marker.guid === "old");
          const final = state[0].find(marker => marker.guid === "old");
          const moved = test.probe.writeFailure.row;
          const halfRemains = final && final.start === moved.start && final.end === moved.end;
          row.compensated = JSON.stringify(after) === JSON.stringify(prior);
          row.faultOutcome = { reportOk: report.ok, final, halfRemains: Boolean(halfRemains), transientPositions };
          if (halfRemains) row.checks.a.push({ class: "partial-worse", error: "Half-written bounds survived", final });
        }
        record(row);
      } catch (error) {
        record({ ...row, harness: error.stack });
      }
    }
  }
}
console.log(JSON.stringify({ summary, classifiedCases, classifiedChecks,
  compensatedOnly, injectedFaults, compensatedFaults, survivingHalfWrites, harnessFailures }));
assert.equal(classifiedCases["transient-surplus"], 0);
assert.equal(classifiedCases["partial-worse"], 0);
assert.equal(harnessFailures, 0);
assert.equal(injectedFaults, 172);
assert.equal(compensatedFaults, injectedFaults);
assert.equal(survivingHalfWrites, 0);
