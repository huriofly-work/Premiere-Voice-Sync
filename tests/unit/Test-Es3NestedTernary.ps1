$ErrorActionPreference = 'Stop'
& node (Join-Path $PSScriptRoot 'es3-nested-ternary.test.js')
if ($LASTEXITCODE -ne 0) { throw 'ES3_NESTED_TERNARY_TEST_FAILED' }
