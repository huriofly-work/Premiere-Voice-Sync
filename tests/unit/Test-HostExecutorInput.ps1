$ErrorActionPreference='Stop'
& node (Join-Path $PSScriptRoot 'host-executor-input.test.js')
if($LASTEXITCODE -ne 0){throw 'HOST_EXECUTOR_INPUT_TEST_FAILED'}
