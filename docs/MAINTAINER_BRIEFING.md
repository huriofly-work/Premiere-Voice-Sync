# Maintainer briefing

Written 2026-11-04 for Claude Code taking over from Codex. It is a map of what the
repository documents, verified against the files named here. It does not replace
[AGENTS.md](../AGENTS.md), [ARCHITECTURE.md](ARCHITECTURE.md),
[REGRESSION_MEMORY.md](REGRESSION_MEMORY.md) or [HANDOFF.md](HANDOFF.md); read those
for detail. Not verified by running Premiere: nothing here is native acceptance.

## What the product is

A Windows Adobe Premiere Pro CEP panel (id `com.premierevoicesync.local`, runtime
2.20.90, baseline the user tested: 2.20.25). Two workflows share one alignment core:

- **Dựng theo voice (Auto edit):** from a template (one V1/A1 nest, A2 voice chapters)
  and a Vietnamese SRT, align the new voice to SRT cues and rebuild picture/audio
  timing: cut/keep gaps, retime pairs (speed 70–130% is a warning/merge threshold, not
  a clamp), marker the rest.
- **Chỉ tạo subtitle (caption-only):** make captions from the selected voice track/range
  without touching the edit. SRT optional: matched cues keep SRT text, genuine extra
  speech is captioned from ASR, unread cues go to review.

Hard rule for both: SRT identity, timing authority and cut/omission authority are
separate evidence. Never promote estimated/CTC/attention timing to verified DTW and
never let it authorize a cut.

## Runtime map

| Layer | Files | Role |
|---|---|---|
| Panel | `extension/index.html`, `js/main.js` (~2.5k lines) | State, settings, stop/pause (Promise waits at safe boundaries), jobs, recovery journal, notices; spawns PowerShell via `runPowerShell` |
| Panel helpers | `js/caption-input.js` (ES3, shared with host), `srt-join.js`, `security.js`, notification modules | Input resolution, SRT join, path safety |
| Host (ExtendScript, ES3) | `jsx/host.jsx`, generated `jsx/diagnostic-executor.jsx` | Premiere reads, audio export with mute/In/Out restore, timeline edits, caption import, `_markerTools`, postchecks. Regenerate executor with `node tools/Build-DiagnosticExecutor.js`; check with `--check` |
| Engine | `engine/run-workflow.ps1` (Job Object supervisor; allowlists 5 scripts), `run-alignment.ps1` → `build-sentence-plan.ps1` → `build-dtw-trial-plan.ps1` → `build-speed-merge-trial-plan.ps1` (Auto edit), `run-captions.ps1` (caption-only) | JSON jobs/results between panel, engine and host |
| Engine libs | `engine/lib/` — `ReferenceAlignment.ps1` (shared matching core), `Alignment.ps1`, `CaptionOnly.ps1`, `CaptionTiming.ps1`, `SubtitleTiming/Energy.ps1`, `AutoEditAcousticPartitions/ManualReview.ps1`, `RecognitionBackend.ps1`, `AudioCache.ps1`, `Security.ps1`, `Srt.ps1` | Alignment, DTW windows, caption layout, caching, safety |
| Pins | `engine/runtime-lock.json`, `cuda-lock.json`, `engine-config.json` | Hash-pinned whisper.cpp/FFmpeg/model; the one shipped model is Whisper large-v3-turbo (named in `Security.ps1:Get-PvsRuntimeModelProfile`) |
| Packaging | `installer/` (`build-release.ps1`, `install.ps1`, `build-notifications.ps1`), `tools/` | Allowlisted ZIP, hashes, install/uninstall/rollback; `dist/` is untracked |
| Data | `%LOCALAPPDATA%\PremiereVoiceSync` (Jobs, Logs, Cache, Models, Backends), panel in `%APPDATA%\Adobe\CEP\extensions\com.premierevoicesync.local` | Preserved across updates; never bulk-delete |

Pause is cooperative, Stop waits for a running native call (no fake timeouts), no
automatic Save/Undo/force-close. Marker handling reconciles with verify/compensate and
keeps manual markers. Cache keys on SHA-256 of audio+model+executable+argv.

## How correctness is protected

- `REGRESSION_MEMORY.md` (newest first) records every fix with cause, invariant,
  test and measured result. The table "Những điều cần giữ khi sửa" maps bug
  families to their tests. Read the relevant entry before touching that path.
- Tests: `tests/Run-Tests.ps1` parses all PowerShell and the manifest, then runs
  every `tests/unit/Test-*.ps1` group (with their Node mocks); `tests/helpers` and
  `tests/manual` hold fixtures and media/Premiere procedures. Six Windows
  integration groups are skipped with `-NoWindowsIntegration`. CI
  (`windows-ci.yml`) runs that plus JS syntax checks and
  `tools/Verify-GitHubDistribution.ps1`, only on pull requests that change code
  (Markdown and `docs/` changes skip it, except `docs/releases/*.json`).
- Every behavioral fix: reproducing regression first, trace all related/fallback
  workflows, add the case to the suite, update REGRESSION_MEMORY, then report what
  automation proved versus what only Premiere can prove.
- Gotchas seen repeatedly: ES3/ExtendScript syntax differs from V8 (nested
  conditionals broke native parsing; mind `File.encoding`), `Set-StrictMode` with
  `$null.Count`, PS5 vs PS7 module paths, sandbox junction `EPERM` (use project-local
  TEMP/TMP, never weaken the test).

## Product decisions (do not reopen)

Q17: SRT chosen as a file (internal SRT auto-import). Q18: keep the phased,
bounded-batch edit flow. Scope: Vietnamese SRT correctness. The ASR upgrade is done: on 2026-11-13 the
user chose Whisper large-v3-turbo as the only model (2.20.90) and dropped Qwen. Rare hard
errors may go to manual review ([ASR_ACCEPTANCE_POLICY.md](ASR_ACCEPTANCE_POLICY.md)).
Defaults: 0.5 s no-dialogue gap, 42-character captions, speed 70–130%. Build only
after the feasibility check in [DEVELOPMENT_FEASIBILITY_POLICY.md](DEVELOPMENT_FEASIBILITY_POLICY.md).

## Where the work stands

- Released line (old repo): 2.20.90 prerelease (Whisper large-v3-turbo; installed
  on the user's machine 2026-11-13, native acceptance pending); the accepted stable
  was 2.20.25. The repository restarted on 2026-11-14 with no releases; 2.20.91
  will be the first public one.
- Direction (2026-11-13): build the big update in small releases on the 2.20.x
  engine and panel. The cue-first rewrite, ASR model-selection research, Qwen and a
  separate result sequence were closed and their code, tests and reports removed
  (see the cleanup entry in [REGRESSION_MEMORY.md](REGRESSION_MEMORY.md)).
- Native authority comes only from the user, per bounded packet; used-up packets are
  never reused.

## How to start a task

1. `git status`, branch, worktrees; read AGENTS.md/CLAUDE.md rules for the task.
2. Read the REGRESSION_MEMORY entry and tests for the affected path.
3. Plan within the approved scope; work beyond it is allowed when it serves the
   task, and is reported with the reason.
4. Run the targeted test, then the baseline suite; report skipped groups and the
   native boundary. Ask before each commit, push, PR, merge, install or release.

## Known limits of this briefing

I (Claude) have read the documents above and the code structure, not every line of
`main.js`, `host.jsx` or the engine libraries, and have not run Premiere. Treat code
details as "read before editing", not as already known.
