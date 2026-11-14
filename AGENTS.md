# Premiere Voice Sync: repository rules for coding agents

## Roles and approvals

- Claude Code develops; Codex is only an optional second reviewer. Report which
  review passes ran; two passes from one provider are not independent review.
- Ask the user first, every time: commit, push, open or merge a PR, build or
  publish a release, install, each native Premiere run, UX or safety changes.
- Small work outside the approved plan is fine when it serves the task; report
  what was added and why. Larger additions need approval first.

## Invariants not visible in the code

- Host code and `extension/js/caption-input.js` stay ExtendScript ES3-compatible.
- `extension/jsx/diagnostic-executor.jsx` is generated: edit the source, run
  `node tools/Build-DiagnosticExecutor.js`, check parity; never hand-edit it.
- Recovery journals must survive failures.
- Whisper.cpp, FFmpeg, model and CUDA files are hash-pinned in the engine lock and
  config files; never fetch a latest version. End users need no Python or npm.

## Commands

Run from the repository root in Windows PowerShell. There is no npm project,
linter or typecheck; syntax parsing does not replace them.

| Purpose | Command |
| --- | --- |
| Standard suite | `powershell.exe -NoProfile -ExecutionPolicy Bypass -File tests/Run-Tests.ps1 -NoWindowsIntegration` |
| Full suite (Windows integration) | `powershell.exe -NoProfile -ExecutionPolicy Bypass -File tests/Run-Tests.ps1` |
| One PowerShell group / JS mock | `... -File tests/unit/Test-<Name>.ps1` / `node tests/unit/<name>.test.js` |
| JS syntax (CI) | `node --check extension/js/main.js`, `node --check extension/js/security.js` |
| Executor parity | `node tools/Build-DiagnosticExecutor.js --check` |
| Distribution metadata | `powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools/Verify-GitHubDistribution.ps1` |
| Import runtime (user asks only) | `... -File tools/setup-engine.ps1 -ArtifactsRoot <folder-with-bin-and-models>` |
| Build ZIP / notification helper (user asks only) | `... -File installer/build-release.ps1` / `installer/build-notifications.ps1` |
| Run installed panel | Premiere: `Window > Extensions (Legacy) > Premiere Voice Sync` |

- `-NoWindowsIntegration` skips six integration groups; report them as skipped.
- [windows-ci.yml](.github/workflows/windows-ci.yml) is the full CI command list.
- Media/Premiere tests need the fixtures in [docs/TESTING.md](docs/TESTING.md).
- Build, bootstrap and install commands write artifacts or installed state; never
  use them as checks.

## Git and local data

- Check status, branch and worktrees first; keep unrelated changes; never reset,
  stash or switch branches to clean a checkout. New branches use `claude/`.
- Developer output goes in ignored `_local/`. `.tmp*` and `_local/` are disposable
  only from a user-confirmed list, with nothing using them, never through a
  junction (PowerShell 5.1 `Remove-Item -Recurse` follows junctions). Never delete
  `extension/engine/runtime/`, `dist/` or `%LOCALAPPDATA%\PremiereVoiceSync`.

## Engine and caption safety

- Before changing engine behavior, read [docs/REGRESSION_MEMORY.md](docs/REGRESSION_MEMORY.md)
  and the tests for that path. Prove new native capabilities first
  ([feasibility policy](docs/DEVELOPMENT_FEASIBILITY_POLICY.md)).
- Each fix: trace the cause through related and fallback paths, write a
  reproducing regression before the fix, run it and the standard suite, record
  cause, invariant, test and result in REGRESSION_MEMORY (pending if
  incomplete). Use a project-local TEMP/TMP if the sandbox blocks temp; never
  change runtime logic for tests.
- A selected SRT does not prove retained text: check final captions, including
  splits, supplements, numbers, letter labels and genuine extra speech. Hard cases
  go to manual review per [ASR_ACCEPTANCE_POLICY.md](docs/ASR_ACCEPTANCE_POLICY.md).
- Keep subtitle text recovery separate from Auto edit cut evidence; never weaken
  safety thresholds or promote estimated timing to verified DTW.
- Preserve source SRT/project files, jobs, caches, models and backups. Never drive
  Premiere Save/Undo or force-close Premiere or helpers.
- Replay, CI and package checks are not native acceptance; mark it pending.
- Releases follow [GITHUB_DISTRIBUTION.md](docs/GITHUB_DISTRIBUTION.md): never
  overwrite published assets or promote stable automatically.
