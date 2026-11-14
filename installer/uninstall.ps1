param([switch]$Quiet,[string]$ApplicationDataRoot,[string]$LocalApplicationDataRoot,[string]$TemporaryRoot,[string]$RegistryBasePath='HKCU:\Software',[switch]$SkipRegistry,[switch]$SkipProcessCheck)
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
if ($RegistryBasePath -notmatch '^HKCU:\\Software(?:\\[^.\\]+)*$') { throw 'Unsafe registry base path.' }
. "$PSScriptRoot\package-security.ps1"
$roamingRoot=if ($ApplicationDataRoot) { $ApplicationDataRoot } else { $env:APPDATA }
$localRoot=if ($LocalApplicationDataRoot) { $LocalApplicationDataRoot } else { $env:LOCALAPPDATA }
$extensionRoot=Join-Path $roamingRoot 'Adobe\CEP\extensions'
$target=Join-Path $extensionRoot 'com.premierevoicesync.local'
$appDataRoot=Join-Path $localRoot 'PremiereVoiceSync'
$backupFile=Join-Path $appDataRoot 'player-debug-mode-backup.txt'
$debugKey=Join-Path $RegistryBasePath 'Adobe\CSXS.12'
$uninstallKey=Join-Path $RegistryBasePath 'Microsoft\Windows\CurrentVersion\Uninstall\PremiereVoiceSync'
if (-not $SkipProcessCheck -and @(Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.ProcessName -like 'Adobe Premiere Pro*' }).Count) { throw 'Hay dong Adobe Premiere Pro truoc khi go panel.' }
Assert-PvsSafePath -Path $target -Tree
Assert-PvsSafePath -Path $appDataRoot -Tree
if ((Get-Content -LiteralPath (Join-Path $appDataRoot 'deployment-mode.txt') -Raw).Trim() -ne 'panel-only') { throw 'SECURITY_PANEL_DEPLOYMENT_MISSING' }
if (Test-Path -LiteralPath $target) { Assert-PvsPanelIdentity -Path $target }
if (-not $SkipRegistry -and (Test-Path -LiteralPath $uninstallKey)) { throw 'Hay chay Setup-Panel.cmd de chuyen ban Installed apps cu truoc khi go.' }
$notificationShortcut=Join-Path $roamingRoot 'Microsoft\Windows\Start Menu\Programs\Premiere Voice Sync Notifications.lnk'
Assert-PvsSafePath -Path $notificationShortcut
if (Test-Path -LiteralPath $notificationShortcut) {
    if (-not ('PvsNotificationIdentity' -as [type])) { Add-Type -Path (Join-Path $target 'native\NotificationIdentity.cs') }
    [PvsNotificationIdentity]::Remove($notificationShortcut,(Join-Path $target 'native\PvsNotifications.exe'))
}
if (-not $SkipRegistry -and (Test-Path -LiteralPath $backupFile -PathType Leaf)) {
    $previous=(Get-Content -LiteralPath $backupFile -Raw).Trim()
    $current=if (Test-Path $debugKey) { (Get-ItemProperty $debugKey).PSObject.Properties['PlayerDebugMode'] } else { $null }
    # Do not overwrite a setting another application/user changed since setup.
    if ($null -ne $current -and [string]$current.Value -eq '1') {
        if ($previous) { New-ItemProperty -Path $debugKey -Name PlayerDebugMode -Value $previous -PropertyType String -Force | Out-Null }
        else { Remove-ItemProperty -Path $debugKey -Name PlayerDebugMode -ErrorAction SilentlyContinue }
    }
}
Remove-PvsSafeTree -Path $target -Root $extensionRoot
Remove-PvsSafeTree -Path $appDataRoot -Root $localRoot
# No wildcard cleanup outside the dedicated data root; legacy temp folders are not deleted by name.
if (-not $Quiet) {
    Write-Host 'Da go panel ZIP va du lieu cua tool. Thu muc ZIP duoc giu lai.'
    Write-Host 'Whisper/FFmpeg do ung dung khac cai dat khong bi thay doi.'
}
