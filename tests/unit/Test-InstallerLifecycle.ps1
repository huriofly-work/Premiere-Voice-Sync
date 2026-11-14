$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$root=Resolve-Path (Join-Path $PSScriptRoot '..\..')
. (Join-Path $PSScriptRoot '..\helpers\PackageFixture.ps1')
$temp=Join-Path $env:TEMP ('PVS-InstallerLifecycle-'+[guid]::NewGuid().ToString('N'))
$package=Join-Path $temp 'package'; $roaming=Join-Path $temp 'roaming'; $local=Join-Path $temp 'local'
$extensions=Join-Path $roaming 'Adobe\CEP\extensions'
$neighbor=Join-Path $extensions 'com.other.panel'
$legacyTemp=Join-Path $temp 'temporary\PremiereVoiceSync-cuda-123'
$target=Join-Path $extensions 'com.premierevoicesync.local'
try {
    New-PvsPackageFixture -Root $package -SourceRoot $root
    New-Item -ItemType Directory -Path (Join-Path $neighbor 'CSXS'),$legacyTemp -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $neighbor 'CSXS\manifest.xml') -Value '<ExtensionManifest ExtensionBundleName="Premiere Voice Sync" />'
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $package 'scripts\install.ps1') -ApplicationDataRoot $roaming -LocalApplicationDataRoot $local -SkipRegistry -SkipProcessCheck
    if ($LASTEXITCODE -ne 0) { throw 'INSTALL_FAILED' }
    foreach ($relative in (Get-PvsPackageFiles | Where-Object { $_.StartsWith('extension\') })) {
        if ((Get-FileHash -LiteralPath (Join-Path $package $relative)).Hash -ne (Get-FileHash -LiteralPath (Join-Path $target $relative.Substring(10))).Hash) { throw 'INSTALL_CHANGED_FILE' }
    }
    if (-not (Test-Path -LiteralPath $neighbor)) { throw 'INSTALL_DELETED_OTHER_ID' }
    if (Test-Path -LiteralPath (Join-Path $local 'Programs\PremiereVoiceSync')) { throw 'INSTALL_CREATED_WINDOWS_APP' }
    New-Item -ItemType Directory -Path (Join-Path $local 'PremiereVoiceSync\Cache\Whisper') -Force | Out-Null
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $package 'scripts\uninstall.ps1') -ApplicationDataRoot $roaming -LocalApplicationDataRoot $local -TemporaryRoot (Split-Path $legacyTemp -Parent) -SkipRegistry -SkipProcessCheck -Quiet
    if ($LASTEXITCODE -ne 0 -or (Test-Path $target) -or (Test-Path (Join-Path $local 'PremiereVoiceSync'))) { throw 'REMOVE_FAILED' }
    if (-not (Test-Path $neighbor) -or -not (Test-Path $legacyTemp)) { throw 'REMOVAL_DELETED_UNRELATED_DIRECTORY' }
    [xml]$manifest=Get-Content -LiteralPath (Join-Path $root 'extension\CSXS\manifest.xml') -Raw
    if ($manifest.ExtensionManifest.ExtensionBundleId -ne 'com.premierevoicesync.local') { throw 'NEUTRAL_ID_MISSING' }
    $brand=[string]::Concat('null','seek'); $owner=[string]::Concat('hu','rio')
    foreach ($relative in (Get-PvsPackageFiles)) {
        $source=if ($relative -like 'extension\*' -and $relative -notlike 'extension\engine\runtime\*') { Join-Path $root $relative } else { $null }
        if ($source -and (Test-Path $source)) {
            $text=[IO.File]::ReadAllText($source)
            if ($text.IndexOf($brand,[StringComparison]::OrdinalIgnoreCase) -ge 0 -or $text.IndexOf($owner,[StringComparison]::OrdinalIgnoreCase) -ge 0) { throw 'PERSONAL_IDENTITY_REMAINS' }
        }
    }
    Write-Host 'INSTALLER_LIFECYCLE_OK:exact-ID,checksums,source,unrelated-preserved'
} finally { if (Test-Path $temp) { Remove-PvsSafeTree -Path $temp -Root $env:TEMP } }
