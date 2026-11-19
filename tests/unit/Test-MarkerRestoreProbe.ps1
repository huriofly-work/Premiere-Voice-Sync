$ErrorActionPreference = 'Stop'
& node (Join-Path $PSScriptRoot 'probe-marker-restore.test.js')
if ($LASTEXITCODE -ne 0) { throw 'MARKER_RESTORE_PROBE_TEST_FAILED' }
