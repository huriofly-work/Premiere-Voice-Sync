$ErrorActionPreference='Stop'
& node (Join-Path $PSScriptRoot 'caption-state.test.js')
if ($LASTEXITCODE -ne 0) { throw 'CAPTION_STATE_FAILED' }
