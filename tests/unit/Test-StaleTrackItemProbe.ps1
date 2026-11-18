$ErrorActionPreference = 'Stop'
& node (Join-Path $PSScriptRoot 'probe-stale-trackitem.test.js')
if ($LASTEXITCODE -ne 0) { throw 'STALE_TRACKITEM_PROBE_TEST_FAILED' }
