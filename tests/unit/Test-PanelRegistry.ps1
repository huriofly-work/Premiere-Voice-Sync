$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$root = Resolve-Path (Join-Path $PSScriptRoot '..\..')
. (Join-Path $PSScriptRoot '..\helpers\PackageFixture.ps1')
$temp = Join-Path $env:TEMP ('PVS-PanelRegistry-' + [guid]::NewGuid().ToString('N'))
$registry = 'HKCU:\Software\PVS-PanelTest-' + [guid]::NewGuid().ToString('N')
$roaming = Join-Path $temp 'roaming'
$local = Join-Path $temp 'local'
$package = Join-Path $temp 'package'
$target = Join-Path $roaming 'Adobe\CEP\extensions\com.premierevoicesync.local'
$debugKey = Join-Path $registry 'Adobe\CSXS.12'
$appKey = Join-Path $registry 'Microsoft\Windows\CurrentVersion\Uninstall\PremiereVoiceSync'
$cache = Join-Path $local 'PremiereVoiceSync\Cache\Whisper\keep.json'
$neighbor = Join-Path $local 'Programs\OtherApp\unrelated.txt'
function Invoke-FixtureSetup {
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $package 'scripts\install.ps1') -ApplicationDataRoot $roaming -LocalApplicationDataRoot $local -RegistryBasePath $registry -SkipProcessCheck
    if ($LASTEXITCODE -ne 0) { throw 'PANEL_FIXTURE_SETUP_FAILED' }
}
try {
    New-PvsPackageFixture -Root $package -SourceRoot $root
    # Fresh setup: no Installed apps entry or Windows app directory, debug enabled.
    Invoke-FixtureSetup
    if (Test-Path $appKey) { throw 'FRESH_PANEL_REGISTERED_APP' }
    if (Test-Path (Join-Path $local 'Programs\PremiereVoiceSync')) { throw 'FRESH_PANEL_CREATED_APP_DIRECTORY' }
    if ((Get-ItemProperty $debugKey).PlayerDebugMode -ne '1') { throw 'PANEL_DEBUG_NOT_ENABLED' }
    if ((Get-Content (Join-Path $local 'PremiereVoiceSync\player-debug-mode-backup.txt') -Raw).Trim()) { throw 'PANEL_DEBUG_BACKUP_INCORRECT' }
    # Update and uninstall a ZIP panel with no Windows app registration or uninstaller.
    New-Item -ItemType Directory -Path (Split-Path $cache),(Split-Path $neighbor) -Force | Out-Null
    Set-Content -LiteralPath $neighbor -Value 'DO_NOT_DELETE' -Encoding ASCII
    Set-Content $cache -Value 'KEEP_CACHE' -Encoding ASCII
    Invoke-FixtureSetup
    Invoke-FixtureSetup
    if ((Get-Content $cache -Raw).Trim() -ne 'KEEP_CACHE') { throw 'PANEL_UPDATE_CHANGED_CACHE' }
    if ((Test-Path $appKey) -or (Test-Path (Join-Path $local 'Programs\PremiereVoiceSync'))) { throw 'PANEL_UPDATE_CREATED_WINDOWS_APP' }
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $package 'scripts\uninstall.ps1') -Quiet -ApplicationDataRoot $roaming -LocalApplicationDataRoot $local -RegistryBasePath $registry -SkipProcessCheck
    if ($LASTEXITCODE -ne 0) { throw 'PANEL_FIXTURE_REMOVAL_FAILED' }
    if (Test-Path $target) { throw 'REMOVAL_LEFT_PANEL' }
    if ((Get-Content -LiteralPath $neighbor -Raw).Trim() -ne 'DO_NOT_DELETE') { throw 'REMOVAL_CHANGED_UNRELATED_APP_FILES' }
    if (Test-Path (Join-Path $local 'PremiereVoiceSync')) { throw 'REMOVAL_LEFT_DATA' }
    if ((Get-ItemProperty $debugKey).PSObject.Properties['PlayerDebugMode']) { throw 'REMOVAL_DID_NOT_RESTORE_DEBUG' }
    New-ItemProperty $debugKey -Name PlayerDebugMode -Value '7' -PropertyType String | Out-Null
    Invoke-FixtureSetup
    if ((Get-Content (Join-Path $local 'PremiereVoiceSync\player-debug-mode-backup.txt') -Raw).Trim() -ne '7') { throw 'PREEXISTING_DEBUG_BACKUP_CHANGED' }
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $package 'scripts\uninstall.ps1') -Quiet -ApplicationDataRoot $roaming -LocalApplicationDataRoot $local -RegistryBasePath $registry -SkipProcessCheck
    if ($LASTEXITCODE -ne 0 -or (Get-ItemProperty $debugKey).PlayerDebugMode -ne '7') { throw 'PREEXISTING_DEBUG_NOT_RESTORED' }
    # Invalid package paths/hashes must fail before creating the panel/data.
    Set-Content (Join-Path $package 'SHA256SUMS.txt') -Value (('0' * 64) + '  ..\outside.txt') -Encoding ASCII
    $oldPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $package 'scripts\install.ps1') -ApplicationDataRoot $roaming -LocalApplicationDataRoot $local -RegistryBasePath $registry -SkipProcessCheck *> $null
    } finally { $ErrorActionPreference = $oldPreference }
    if ($LASTEXITCODE -eq 0 -or (Test-Path $target)) { throw 'PANEL_ACCEPTED_CHECKSUM_PATH_ESCAPE' }
    Set-Content (Join-Path $package 'SHA256SUMS.txt') -Value (('0' * 64) + '  extension\CSXS\manifest.xml') -Encoding ASCII
    $oldPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $package 'scripts\install.ps1') -ApplicationDataRoot $roaming -LocalApplicationDataRoot $local -RegistryBasePath $registry -SkipProcessCheck *> $null
    } finally { $ErrorActionPreference = $oldPreference }
    if ($LASTEXITCODE -eq 0 -or (Test-Path $target)) { throw 'PANEL_ACCEPTED_WRONG_CHECKSUM' }
    Write-Host 'PANEL_REGISTRY_OK:fresh,cache,repeated-setup,zip-only-uninstall,debug-restore,checksum-guards'
} finally {
    if (Test-Path $registry) { Remove-Item -LiteralPath $registry -Recurse -Force }
    $tempFull = [IO.Path]::GetFullPath($temp)
    if ((Split-Path $tempFull -Leaf) -notlike 'PVS-PanelRegistry-*' -or (Split-Path $tempFull -Parent) -ne [IO.Path]::GetFullPath($env:TEMP).TrimEnd('\')) { throw 'Unsafe test cleanup' }
    if (Test-Path $tempFull) { Remove-Item -LiteralPath $tempFull -Recurse -Force }
}
