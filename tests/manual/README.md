# Manual tests

These scripts require an explicit real-media fixture and are intentionally not
part of CI. They must never discover arbitrary folders or stale temporary files
on the user's machine.

- `Run-ParameterMatrix.ps1 -TemplateJob <job.json>` replays planner settings
  against a captured alignment fixture.
- `Run-Sample.ps1 -SampleRoot <folder>` runs alignment against an explicit
  sample folder that contains `Voice` and `Script` subfolders.
- `Measure-LexicalMapping.ps1 -WordCount 1500 -Repeats 3` compares the exact
  lexical reference/compiled mapper on synthetic data, reporting compile cost
  separately and calculated array storage (not measured peak RAM).
- `Measure-LexicalMappingMedia.ps1 -FixtureJobPath <job.json> -LegacyCacheRoot
  <folder> [-VoiceSpeeds <array>]` compares full cue JSON using explicitly
  selected captured ASR. It reads existing media metadata/SRT/cache only, does
  not run recognition or Premiere, write timing, or update cache. Old metadata
  keys locate fixtures only; they are not production cache validation.
- `Test-DtwCaptionIntegrationMedia.ps1 -MediaRoot <folder> -SrtPath <file>
  -BaselineEngineRoot <engine> [-FixtureJobPath <job.json>] [-WarmCache]`
  compares complete cue/caption output, segments and markers in a disposable
  cache/backend copy. FixtureJobPath selects only the explicitly captured voice
  files, not every MP3 in their folder. WarmCache primes before either timed
  run; check hit/miss counters before comparing times. No Premiere mutation.
  `-VoiceSpeedPercent` reproduces a constant input voice speed;
  `-ReviewCaptionIndices <array> -ExportedCaptionSrtPath <file>` prints the
  explicit caption case. `-AllowCaptionTimingChanges` permits only Start/End
  differences; text, cue/part identity, full alignment, segments and markers
  must remain identical. Never use that switch to hide changed edit cuts.
