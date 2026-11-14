param(
    [Parameter(Mandatory)][string]$ArtifactsRoot,
    [string]$EngineRoot = (Join-Path (Split-Path $PSScriptRoot -Parent) 'extension\engine')
)
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
. (Join-Path $EngineRoot 'lib\Security.ps1')
# Developer-only import. End-user ZIPs already include this exact CPU runtime.
# Never silently substitute latest executables/models for the tested baseline.
$lock=Get-Content -LiteralPath (Join-Path $EngineRoot 'runtime-lock.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$artifacts=[IO.Path]::GetFullPath($ArtifactsRoot)
$runtime=Join-Path $EngineRoot 'runtime'
Assert-PvsLockedFiles -Root $artifacts -Lock $lock -BinaryDirectory (Join-Path $artifacts 'bin')
Assert-PvsSafePath -Path $runtime -Tree
foreach ($entry in $lock.files) {
    $destination=Join-Path $runtime $entry.path
    New-Item -ItemType Directory -Path (Split-Path $destination -Parent) -Force | Out-Null
    if ([IO.Path]::GetFullPath((Join-Path $artifacts $entry.path)) -ne [IO.Path]::GetFullPath($destination)) {
        Copy-Item -LiteralPath (Join-Path $artifacts $entry.path) -Destination $destination -Force
    }
}
Copy-Item -LiteralPath (Join-Path $EngineRoot 'engine-config.json') -Destination (Join-Path $runtime 'engine.json') -Force
Assert-PvsRuntimeLock -EngineRoot $EngineRoot
Write-Host 'ENGINE_READY:locked offline artifacts; no download or PATH changes.'
