$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
& node (Join-Path $PSScriptRoot 'host-sequence-restore.test.js')
if ($LASTEXITCODE -ne 0) { throw 'HOST_SEQUENCE_RESTORE_TEST_FAILED' }
Write-Host 'HOST_SEQUENCE_RESTORE_OK (mock; not native Premiere responsiveness acceptance)'
