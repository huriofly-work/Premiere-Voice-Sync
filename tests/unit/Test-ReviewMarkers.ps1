$ErrorActionPreference = 'Stop'
& node (Join-Path $PSScriptRoot 'review-markers.test.js')
if ($LASTEXITCODE -ne 0) { throw 'REVIEW_MARKERS_TEST_FAILED' }
& node (Join-Path $PSScriptRoot 'marker-reconciliation.test.js')
if ($LASTEXITCODE -ne 0) { throw 'MARKER_RECONCILIATION_TEST_FAILED' }
