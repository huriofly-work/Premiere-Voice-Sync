$ErrorActionPreference = 'Stop'
& node (Join-Path $PSScriptRoot 'diagnostic-fast-support.test.js')
if ($LASTEXITCODE -ne 0) { throw 'DIAGNOSTIC_FAST_SUPPORT_TEST_FAILED' }
& node (Join-Path $PSScriptRoot 'diagnostic-executor.test.js')
if ($LASTEXITCODE -ne 0) { throw 'DIAGNOSTIC_EXECUTOR_TEST_FAILED' }
& node (Join-Path $PSScriptRoot 'performance-trial-ui.test.js')
if ($LASTEXITCODE -ne 0) { throw 'PERFORMANCE_TRIAL_UI_TEST_FAILED' }
Write-Host 'DIAGNOSTIC_EXECUTOR_OK (mock; requires native Premiere playback/save acceptance)'
