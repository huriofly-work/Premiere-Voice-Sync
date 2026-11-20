$ErrorActionPreference = 'Stop'
& node (Join-Path $PSScriptRoot 'edit-input.test.js')
if ($LASTEXITCODE -ne 0) { throw 'EDIT_INPUT_FAILED' }
