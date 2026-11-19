$ErrorActionPreference = 'Stop'
& node (Join-Path $PSScriptRoot 'probe-picture-marker-plan.test.js')
if ($LASTEXITCODE -ne 0) { throw 'PICTURE_MARKER_PLAN_PROBE_TEST_FAILED' }
& node (Join-Path $PSScriptRoot 'probe-marker-move-end.test.js')
if ($LASTEXITCODE -ne 0) { throw 'MARKER_MOVE_END_PROBE_TEST_FAILED' }
