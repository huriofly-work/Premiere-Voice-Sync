$ErrorActionPreference = 'Stop'
& node (Join-Path $PSScriptRoot 'probe-slowed-piece-cap.test.js')
if ($LASTEXITCODE -ne 0) { throw 'SLOWED_PIECE_CAP_PROBE_TEST_FAILED' }
