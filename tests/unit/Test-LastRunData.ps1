$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
& node (Join-Path $PSScriptRoot 'last-run-data.test.js')
if ($LASTEXITCODE -ne 0) { throw 'LAST_RUN_DATA_FAILED' }
