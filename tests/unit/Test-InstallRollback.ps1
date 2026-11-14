$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$root=Resolve-Path (Join-Path $PSScriptRoot '..\..')
. (Join-Path $PSScriptRoot '..\helpers\PackageFixture.ps1')
$temp=Join-Path $env:TEMP ('PVS-Rollback-'+[guid]::NewGuid().ToString('N'))
$package=Join-Path $temp 'package'; $roaming=Join-Path $temp 'roaming'; $local=Join-Path $temp 'local'
$target=Join-Path $roaming 'Adobe\CEP\extensions\com.premierevoicesync.local'
try {
    New-PvsPackageFixture -Root $package -SourceRoot $root
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $package 'scripts\install.ps1') -ApplicationDataRoot $roaming -LocalApplicationDataRoot $local -SkipRegistry -SkipProcessCheck
    if ($LASTEXITCODE -ne 0) { throw 'ROLLBACK_SETUP_FAILED' }
    $sentinel=Join-Path $target 'keep-old-panel.txt'
    Set-Content -LiteralPath $sentinel -Value 'OLD_PANEL'
    $mode=Join-Path $local 'PremiereVoiceSync\deployment-mode.txt'
    $modeBefore=[IO.File]::ReadAllBytes($mode)
    $oldPreference=$ErrorActionPreference
    try {
        $ErrorActionPreference='Continue'
        $output=& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot '..\helpers\Fail-InstallRename.ps1') -Package $package -Roaming $roaming -Local $local 2>&1 | Out-String
        $code=$LASTEXITCODE
    } finally { $ErrorActionPreference=$oldPreference }
    if ($code -eq 0 -or $output -notmatch 'INJECTED_RENAME_FAILURE') { throw 'FAILURE_NOT_INJECTED' }
    if ((Get-Content -LiteralPath $sentinel -Raw).Trim() -ne 'OLD_PANEL') { throw 'ROLLBACK_LOST_OLD_PANEL' }
    if ([Convert]::ToBase64String([IO.File]::ReadAllBytes($mode)) -ne [Convert]::ToBase64String($modeBefore)) { throw 'ROLLBACK_CHANGED_MODE' }
    if (@(Get-ChildItem -LiteralPath (Split-Path $target -Parent) | Where-Object { $_.Name -match '\.(backup|installing)-' }).Count) { throw 'ROLLBACK_LEFT_STAGING' }
    Write-Host 'INSTALL_ROLLBACK_OK:old-panel-restored,mode-preserved,no-staging'
} finally { if (Test-Path $temp) { Remove-PvsSafeTree -Path $temp -Root $env:TEMP } }
