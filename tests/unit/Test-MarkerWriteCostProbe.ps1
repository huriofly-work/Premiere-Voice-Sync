$ErrorActionPreference = 'Stop'
& node (Join-Path $PSScriptRoot 'probe-marker-write-cost.test.js')
if ($LASTEXITCODE -ne 0) { throw 'MARKER_WRITE_COST_PROBE_TEST_FAILED' }
