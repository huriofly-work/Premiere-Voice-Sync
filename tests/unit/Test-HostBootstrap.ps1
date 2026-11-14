$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$projectRoot = Resolve-Path (Join-Path $PSScriptRoot '..\..')
$mainPath = Join-Path $projectRoot 'extension\js\main.js'
$source = [IO.File]::ReadAllText($mainPath,[Text.Encoding]::UTF8)

foreach ($required in @(
    'function evalRaw(script)',
    'function ensureHostLoaded()',
    'path.join(extensionRoot(), "jsx", "host.jsx")',
    'f.encoding="UTF-8";',
    'eval(s);',
    'PVS_HOST_READY',
    'PVS_HOST_ERROR|',
    'hostReadyPromise = null;',
    'return ensureHostLoaded().then(function ()',
    'evalRaw(bootstrap)',
    'return evalRaw(script);'
)) {
    if ($source.IndexOf($required,[StringComparison]::Ordinal) -lt 0) { throw "HOST_BOOTSTRAP_MISSING:$required" }
}
if ($source.IndexOf('if (raw === "EvalScript error.") { reject(new Error(raw)); return; }',[StringComparison]::Ordinal) -ge 0) {
    throw 'HOST_BOOTSTRAP_STILL_RETURNS_OPAQUE_EVALSCRIPT_ERROR'
}

$hostPathIndex = $source.IndexOf('path.join(extensionRoot(), "jsx", "host.jsx")',[StringComparison]::Ordinal)
$evalFileIndex = $source.IndexOf('eval(s);',[StringComparison]::Ordinal)
$scanIndex = $source.IndexOf('var info = await evalHost("$._PVS.scanSequence()")',[StringComparison]::Ordinal)
if ($hostPathIndex -lt 0 -or $evalFileIndex -lt $hostPathIndex -or $scanIndex -lt $evalFileIndex) {
    throw 'HOST_BOOTSTRAP_ORDER_INVALID'
}

& node (Join-Path $projectRoot 'tests\unit\host-bootstrap.test.js')
if ($LASTEXITCODE -ne 0) { throw 'HOST_BOOTSTRAP_RUNTIME_FAILED' }
Write-Host 'HOST_BOOTSTRAP_OK'
