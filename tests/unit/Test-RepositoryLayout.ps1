$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$projectRoot = Resolve-Path (Join-Path $PSScriptRoot '..\..')
$version = (Get-Content -LiteralPath (Join-Path $projectRoot 'VERSION') -Raw -Encoding UTF8).Trim()
[xml]$manifest = Get-Content -LiteralPath (Join-Path $projectRoot 'extension\CSXS\manifest.xml') -Raw -Encoding UTF8
if ($version -ne '2.20.90') { throw "VERSION_FILE_INVALID:$version" }
if ([string]$manifest.ExtensionManifest.ExtensionBundleVersion -ne $version) { throw 'MANIFEST_VERSION_MISMATCH' }
if ([string]$manifest.ExtensionManifest.ExtensionList.Extension.Version -ne $version) { throw 'EXTENSION_VERSION_MISMATCH' }
$html = [IO.File]::ReadAllText((Join-Path $projectRoot 'extension\index.html'), [Text.Encoding]::UTF8)
if (-not $html.Contains(('<span class="version">' + $version + '</span>'))) { throw 'PANEL_DISPLAY_VERSION_MISMATCH' }

foreach ($required in @(
    'installer\build-release.ps1', 'Setup-Panel.cmd', 'Remove-Panel.cmd',
    'tests\Run-Tests.ps1', 'tools\setup-engine.ps1',
    'docs\ARCHITECTURE.md'
)) {
    if (-not (Test-Path -LiteralPath (Join-Path $projectRoot $required))) { throw "REPOSITORY_LAYOUT_MISSING:$required" }
}
foreach ($forbidden in @(
    'extension\engine\tests', 'extension\engine\setup-engine.ps1',
    'extension\engine\lib\TimelinePlan.ps1', 'scripts',
    'installer\build-installer.ps1', 'installer\setup-offline.ps1',
    'Install-Premiere-Voice-Sync.cmd', 'Uninstall-Premiere-Voice-Sync.cmd',
    'experiments\cue-first', 'extension\ui', 'extension\js\big-update-lock.js',
    'extension\js\product-installation.js', 'installer\build-cue-first-payload.js', 'installer\node-runtime-lock.json'
)) {
    if (Test-Path -LiteralPath (Join-Path $projectRoot $forbidden)) { throw "REPOSITORY_LAYOUT_LEGACY_PATH:$forbidden" }
}

$releaseCommon = [IO.File]::ReadAllText((Join-Path $projectRoot 'installer\release-common.ps1'), [Text.Encoding]::UTF8)
foreach ($forbidden in @('tests', 'experiments', 'tools', 'TimelinePlan.ps1')) {
    if ($releaseCommon.IndexOf($forbidden, [StringComparison]::OrdinalIgnoreCase) -ge 0) { throw "RELEASE_INCLUDES_NON_RUNTIME_AREA:$forbidden" }
}

Write-Host 'REPOSITORY_LAYOUT_OK'
