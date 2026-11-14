param([string]$ApplicationDataRoot,[string]$LocalApplicationDataRoot,[string]$RegistryBasePath='HKCU:\Software',[switch]$SkipRegistry,[switch]$SkipProcessCheck)
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
if ($RegistryBasePath -notmatch '^HKCU:\\Software(?:\\[^.\\]+)*$') { throw 'Unsafe registry base path.' }
. "$PSScriptRoot\package-security.ps1"
$packageRoot=Split-Path $PSScriptRoot -Parent
$files=Assert-PvsPackage -Root $packageRoot
$extensionId='com.premierevoicesync.local'
$roamingRoot=if ($ApplicationDataRoot) { $ApplicationDataRoot } else { $env:APPDATA }
$localRoot=if ($LocalApplicationDataRoot) { $LocalApplicationDataRoot } else { $env:LOCALAPPDATA }
$targetRoot=Join-Path $roamingRoot 'Adobe\CEP\extensions'
$target=Join-Path $targetRoot $extensionId
$appDataRoot=Join-Path $localRoot 'PremiereVoiceSync'
$debugKey=Join-Path $RegistryBasePath 'Adobe\CSXS.12'
$uninstallKey=Join-Path $RegistryBasePath 'Microsoft\Windows\CurrentVersion\Uninstall\PremiereVoiceSync'
$backupFile=Join-Path $appDataRoot 'player-debug-mode-backup.txt'
$deploymentFile=Join-Path $appDataRoot 'deployment-mode.txt'
$programRoot=Join-Path $localRoot 'Programs\PremiereVoiceSync'
$notificationShortcut=Join-Path $roamingRoot 'Microsoft\Windows\Start Menu\Programs\Premiere Voice Sync Notifications.lnk'
$notificationExecutable=Join-Path $target 'native\PvsNotifications.exe'
Assert-PvsSafePath -Path $notificationShortcut
if (-not ('PvsNotificationIdentity' -as [type])) { Add-Type -Path (Join-Path $packageRoot 'extension\native\NotificationIdentity.cs') }
if ((Test-Path -LiteralPath $notificationShortcut) -and -not [PvsNotificationIdentity]::IsOwned($notificationShortcut,$notificationExecutable)) { throw 'SECURITY_NOTIFICATION_SHORTCUT_NOT_OWNED' }
$shortcutBefore=if (Test-Path -LiteralPath $notificationShortcut) { [IO.File]::ReadAllBytes($notificationShortcut) } else { $null }
$shortcutChanged=$false
foreach ($path in @($target,$appDataRoot,$programRoot)) { Assert-PvsSafePath -Path $path -Tree }
if (Test-Path -LiteralPath $target) { Assert-PvsPanelIdentity -Path $target }
if (-not $SkipProcessCheck -and @(Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.ProcessName -like 'Adobe Premiere Pro*' }).Count) { throw 'Hay dong Adobe Premiere Pro truoc khi thiet lap panel.' }
$legacyValues=@{}
if (-not $SkipRegistry -and (Test-Path -LiteralPath $uninstallKey)) {
    $registration=Get-ItemProperty -LiteralPath $uninstallKey
    if ([string]$registration.DisplayName -ne 'Premiere Voice Sync' -or [IO.Path]::GetFullPath([string]$registration.InstallLocation) -ne [IO.Path]::GetFullPath($target)) { throw 'SECURITY_LEGACY_REGISTRATION_MISMATCH' }
    $key=Get-Item -LiteralPath $uninstallKey
    foreach ($name in $key.GetValueNames()) { $legacyValues[$name]=@($key.GetValue($name),$key.GetValueKind($name)) }
}
$debugBefore=$null
if (-not $SkipRegistry -and (Test-Path -LiteralPath $debugKey)) {
    $key=Get-Item -LiteralPath $debugKey
    if ($key.GetValueNames() -contains 'PlayerDebugMode') { $debugBefore=[string]$key.GetValue('PlayerDebugMode') }
}
$modeBefore=if (Test-Path -LiteralPath $deploymentFile) { Get-Content -LiteralPath $deploymentFile -Raw } else { $null }
$hadBackup=Test-Path -LiteralPath $backupFile
$installStage=Join-Path $targetRoot ($extensionId+'.installing-'+[guid]::NewGuid().ToString('N'))
$oldPanel=Join-Path $targetRoot ($extensionId+'.backup-'+[guid]::NewGuid().ToString('N'))
$oldMoved=$false; $newMoved=$false; $committed=$false
try {
    New-Item -ItemType Directory -Path $installStage,$appDataRoot -Force | Out-Null
    foreach ($relative in ($files.Keys | Where-Object { $_.StartsWith('extension\',[StringComparison]::OrdinalIgnoreCase) })) {
        $destination=Join-Path $installStage $relative.Substring(10)
        New-Item -ItemType Directory -Path (Split-Path $destination -Parent) -Force | Out-Null
        Copy-Item -LiteralPath (Join-Path $packageRoot $relative) -Destination $destination
        if ((Get-FileHash -LiteralPath $destination).Hash -ne $files[$relative]) { throw 'SECURITY_STAGED_HASH_MISMATCH' }
    }
    Assert-PvsPanelIdentity -Path $installStage
    Assert-PvsSafePath -Path $target -Tree
    if (Test-Path -LiteralPath $target) { Move-Item -LiteralPath $target -Destination $oldPanel; $oldMoved=$true }
    Move-Item -LiteralPath $installStage -Destination $target; $newMoved=$true
    Assert-PvsSafePath -Path $notificationShortcut
    $shortcutChanged=$true
    [PvsNotificationIdentity]::Install($notificationShortcut,$notificationExecutable)
    if (-not $SkipRegistry) {
        if (-not $hadBackup) { Set-Content -LiteralPath $backupFile -Value ([string]$debugBefore) -Encoding ASCII }
        New-Item -Path $debugKey -Force | Out-Null
        New-ItemProperty -Path $debugKey -Name PlayerDebugMode -Value '1' -PropertyType String -Force | Out-Null
    }
    Set-Content -LiteralPath $deploymentFile -Value 'panel-only' -Encoding ASCII
    if (-not $SkipRegistry -and $legacyValues.Count) { Remove-Item -LiteralPath $uninstallKey -Recurse -Force }
    $committed=$true
} catch {
    $failure=$_
    if ($shortcutChanged) {
        Assert-PvsSafePath -Path $notificationShortcut
        if ($null -ne $shortcutBefore) { [IO.File]::WriteAllBytes($notificationShortcut,[byte[]]$shortcutBefore) }
        elseif (Test-Path -LiteralPath $notificationShortcut) { [PvsNotificationIdentity]::Remove($notificationShortcut,$notificationExecutable) }
    }
    if ($newMoved) { Remove-PvsSafeTree -Path $target -Root $targetRoot }
    if ($oldMoved) { Assert-PvsSafePath -Path $oldPanel -Root $targetRoot -Tree; Move-Item -LiteralPath $oldPanel -Destination $target }
    if ($null -ne $modeBefore) { Set-Content -LiteralPath $deploymentFile -Value $modeBefore -NoNewline -Encoding ASCII }
    elseif (Test-Path -LiteralPath $deploymentFile) { Remove-Item -LiteralPath $deploymentFile -Force }
    if (-not $SkipRegistry) {
        if ($null -ne $debugBefore) { New-Item -Path $debugKey -Force | Out-Null; New-ItemProperty -Path $debugKey -Name PlayerDebugMode -Value $debugBefore -PropertyType String -Force | Out-Null }
        elseif (Test-Path -LiteralPath $debugKey) { Remove-ItemProperty -Path $debugKey -Name PlayerDebugMode -ErrorAction SilentlyContinue }
        if (-not $hadBackup -and (Test-Path -LiteralPath $backupFile)) { Remove-Item -LiteralPath $backupFile -Force }
        if ($legacyValues.Count) {
            New-Item -Path $uninstallKey -Force | Out-Null
            foreach ($name in $legacyValues.Keys) { New-ItemProperty -Path $uninstallKey -Name $name -Value $legacyValues[$name][0] -PropertyType $legacyValues[$name][1] -Force | Out-Null }
        }
    }
    throw $failure
} finally {
    if (Test-Path -LiteralPath $installStage) { Remove-PvsSafeTree -Path $installStage -Root $targetRoot }
    if ($committed -and $oldMoved) { Remove-PvsSafeTree -Path $oldPanel -Root $targetRoot }
}
# Do not discover/delete extensions merely by their display name.
$oldUninstaller=Join-Path $programRoot 'uninstall.ps1'
if (Test-Path -LiteralPath $oldUninstaller -PathType Leaf) {
    $oldSource=[IO.File]::ReadAllText($oldUninstaller)
    if ($oldSource -match "\`$extensionId\s*=\s*'com\.premierevoicesync\.local'") {
        Remove-Item -LiteralPath $oldUninstaller -Force
        if (@(Get-ChildItem -LiteralPath $programRoot -Force).Count -eq 0) { Remove-Item -LiteralPath $programRoot -Force }
    }
}
Write-Host 'PANEL_SETUP_OK:checksums,allowlist,rollback; no Installed apps.'
Write-Host 'Mo Premiere: Window > Extensions (Legacy) > Premiere Voice Sync.'
Write-Host 'Go sach bang Remove-Panel.cmd trong goi ZIP; cache/model duoc giu khi cap nhat.'
Write-Warning 'CEP chua ky: PlayerDebugMode cho phep ca extension CEP chua ky khac. Chi dung goi da doi chieu SHA256 tu nguon tin cay.'
