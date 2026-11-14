# Premiere Voice Sync: Claude Code guidance

@AGENTS.md

`AGENTS.md` (imported above) holds the shared repository rules. This file adds
what applies to Claude Code only.

- Start with `docs/MAINTAINER_BRIEFING.md` (project map) and `docs/HANDOFF.md`
  (current decisions and plan status).
- Reply to the user in Vietnamese unless asked otherwise. Keep code,
  identifiers, commit messages and file names in English; preserve Vietnamese
  text in product files and fixtures.
- The repository is public: code, issues, PRs, commit messages, release notes
  and Actions logs are visible to anyone. Never add secrets, personal data,
  local user paths or private media; list third-party payload in
  `THIRD_PARTY_NOTICES.md`.
- If CI is refused for billing, do not wait or retry: the standard suite is the
  merge gate, and the PR states that CI did not run and why.
- On Windows, run shell scripts with `C:\Program Files\Git\bin\bash.exe`, not
  the `bash` alias that may resolve to WSL.
