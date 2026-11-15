$ErrorActionPreference = 'Stop'
& node (Join-Path $PSScriptRoot 'probe-voice-clip-markers.test.js')
if ($LASTEXITCODE -ne 0) { throw 'VOICE_CLIP_MARKER_PROBE_TEST_FAILED' }
