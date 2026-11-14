# Marker reconciliation — 17/10/2026

Initial scope approved by the user's “Tiếp tục” after the marker optimization proposal:
change source and tests only, without operating Premiere, Save, Undo or installation.
The subsequent continuation authorized packaging and installation; see the release
follow-up below. Premiere/project interaction remains excluded.

## Contract

- Capture each ProjectItem's marker collection and source ranges before editing,
  without removing markers. Shared V1/A1 and repeated voice sources form one group.
- Collect desired clip markers after actual clip boundaries are known. Reconcile
  each source group synchronously, with no pause/cancel boundary inside a group.
- Sequence review markers use the same reconciliation core, with separate
  timeline coordinate planning and workflow ownership.
- Preserve manual, unknown, non-comment, other-workflow, and out-of-scope markers.
  Shared-source clip markers remain shared across sequences; do not imply isolation.
- Reuse owned markers at desired positions; unchanged marker data causes no writes.
  Write and read back replacements before deleting obsolete owned markers.
- Verify deletions by reading the collection, not by trusting the API return value.
- Snapshot touched data and compensate only this group's marker mutations on
  failure. Report failed compensation; never claim atomicity across crashes or
  across timeline edits. Never automatically Undo, Save, or retry a workflow.
- An invalid clip-marker request blocks its source group's cleanup. Other groups
  can complete. Cancellation retains completed groups and leaves uncommitted
  source groups' old markers intact. Native failures before marker commit leave
  clip markers untouched.
- Recheck captured marker state before committing a source group, so edits made
  while paused cannot be overwritten silently. Use durable source identity.

## Reporting and lifecycle

Existing marker failure fields remain actionable workflow failures. Color-only
failures remain informational. Include restoration failures in those existing
error details; keep partial timeline/recovery behavior. No new approval dialog,
notification lifecycle, retry, persistence service, or timeline rollback.

## Verification

Test repeated identical runs, changed/empty desired sets, source-range unions,
manual collisions, changed marker state, partial update/create/delete failures,
false-success deletion, compensation failure, native failure before commit,
cancel before/during collection and between source groups, and parity of direct,
baseline, fast, and no-delay executors. Regenerate the staged executor from host.

Native acceptance still requires a disposable Premiere project: shared media in
two sequences; clip and timeline marker position/notes/color; pause/resume/cancel;
manual markers; playback and user-controlled Save/Undo. VM tests cannot prove it.

## Result

Implemented in `extension/jsx/host.jsx`; the staged executor is regenerated from
the same source. Clip request planning does not call marker mutation APIs. Each
source commit has its own complete compensation scope and uses a stable source
ID/path, never a display name. Invalid requests block that source (or all prepared
sources if ownership cannot be mapped). Source marker edits made after preparation
cause a visible conflict. Identical repeated uses of a source warning are deduplicated.
Valid existing source positions survive native timestamp quantization on reruns.

Snapshots include marker duration, type, notes and readable color. Only owned
Comment markers can be replaced/deleted. Compensating a deletion can create a new
native GUID; only marker data is restored. If an old color cannot be read, updating
that old marker's color is skipped and reported. The source collection is enumerated
a bounded number of times per group; candidate searches use an in-memory position
index. Native writes are skipped when the desired data already matches.

On 17/10/2026, `Run-Tests.ps1 -NoWindowsIntegration` passed **46 groups**, parsed
**115 PowerShell scripts**. Six Windows integration groups were excluded by the
runner. The security junction fixture passed with escalation; the initial sandbox
run stopped because creating that test junction was denied. Both runs used isolated
TEMP/TMP/LOCALAPPDATA under `.tmp-marker-reconcile/`. Final suite log:
`.tmp-marker-reconcile/suite-final.log`.

New cases cover partial metadata writes, native create/delete throwing after a
mutation, deletion returning success without removing a marker, deletion returning
false despite verified removal, incomplete compensation, duration preservation,
empty desired sets, invalid requests, source identity, manual/other-type markers,
bounded native reads, quantized source positions, and source deduplication. Actual
executor VM cases verify native failure before commit, cancellation between source
owners, marker state changes before commit, and direct/baseline/fast/no-delay parity.
The final panel error formatting test confirms restoration details reach the user.
Generated-executor consistency, JS syntax and diff whitespace checks passed.

Initial implementation stopped at source changes: no release version bump or
installation at that stage. No Premiere interaction, user project access, Save or
Undo was performed. Native acceptance remains pending.

## Release follow-up — 2.20.55

The subsequent user continuation produced and installed 2.20.55 on 17/10/2026.
ZIP payload verification passed (70 payload files plus checksum manifest), nine
packaged-runtime VM suites passed, and packaging/install/rollback/registry fixture
tests passed. Real installation verified 62 panel files, preserved 1,568 data files
and 24 directories, kept the existing CEP registry state, and retained a full backup
of the previous 2.20.54 panel. Premiere and the helper were closed at setup; no
application was opened/closed and no project actions were performed. See
[release and installation evidence](../releases/notes/REVIEW_MARKERS_2.20.55.md).
