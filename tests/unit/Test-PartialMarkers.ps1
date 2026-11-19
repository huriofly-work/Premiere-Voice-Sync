$ErrorActionPreference = 'Stop'
& node (Join-Path $PSScriptRoot 'partial-markers.test.js')
if ($LASTEXITCODE -ne 0) { throw 'PARTIAL_MARKERS_TEST_FAILED' }
