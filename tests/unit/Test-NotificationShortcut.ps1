$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$root=Resolve-Path (Join-Path $PSScriptRoot '..\..')
. (Join-Path $PSScriptRoot '..\helpers\PackageFixture.ps1')
$temp=Join-Path $env:TEMP ('PVS-NotificationShortcut-'+[guid]::NewGuid().ToString('N'))
$package=Join-Path $temp 'package'; $roaming=Join-Path $temp 'roaming'; $local=Join-Path $temp 'local'
$target=Join-Path $roaming 'Adobe\CEP\extensions\com.premierevoicesync.local'
$shortcut=Join-Path $roaming 'Microsoft\Windows\Start Menu\Programs\Premiere Voice Sync Notifications.lnk'
Add-Type -Path (Join-Path $root 'extension\native\NotificationIdentity.cs')
function Setup {
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $package 'scripts\install.ps1') -ApplicationDataRoot $roaming -LocalApplicationDataRoot $local -SkipRegistry -SkipProcessCheck
    if($LASTEXITCODE -ne 0){throw 'SHORTCUT_SETUP_FAILED'}
}
function Fail-Setup {
    $previous=$ErrorActionPreference
    try {
        $ErrorActionPreference='Continue'
        $output=& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot '..\helpers\Fail-NotificationInstall.ps1') -Package $package -Roaming $roaming -Local $local 2>&1 | Out-String
        if($LASTEXITCODE -eq 0 -or $output -notmatch 'INJECTED_POST_SHORTCUT_FAILURE'){throw "SHORTCUT_FAILURE_NOT_INJECTED:$output"}
    }finally{$ErrorActionPreference=$previous}
}
try {
    New-PvsPackageFixture -Root $package -SourceRoot $root
    Fail-Setup
    if((Test-Path $shortcut) -or (Test-Path $target)){throw 'FRESH_ROLLBACK_LEFT_SHORTCUT_OR_PANEL'}
    Setup
    if(-not [PvsNotificationIdentity]::IsOwned($shortcut,(Join-Path $target 'native\PvsNotifications.exe'))){throw 'AUMID_OR_TARGET_MISMATCH'}
    $before=(Get-FileHash -LiteralPath $shortcut).Hash
    Fail-Setup
    if((Get-FileHash -LiteralPath $shortcut).Hash -ne $before){throw 'ROLLBACK_CHANGED_SHORTCUT_BYTES'}
    if([PvsNotificationIdentity]::IsOwned($shortcut,(Join-Path $temp 'other.exe'))){throw 'WRONG_TARGET_ACCEPTED'}
    [PvsNotificationIdentity]::Remove($shortcut,(Join-Path $target 'native\PvsNotifications.exe'))
    $shell=New-Object -ComObject WScript.Shell
    try { $link=$shell.CreateShortcut($shortcut);$link.TargetPath=Join-Path $env:WINDIR 'notepad.exe';$link.Save() }finally{[void][Runtime.InteropServices.Marshal]::ReleaseComObject($shell)}
    $before=(Get-FileHash -LiteralPath $shortcut).Hash
    $previous=$ErrorActionPreference
    try {
        $ErrorActionPreference='Continue'
        $output=& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $package 'scripts\install.ps1') -ApplicationDataRoot $roaming -LocalApplicationDataRoot $local -SkipRegistry -SkipProcessCheck 2>&1 | Out-String
        if($LASTEXITCODE -eq 0 -or $output -notmatch 'SECURITY_NOTIFICATION_SHORTCUT_NOT_OWNED'){throw 'UNOWNED_SHORTCUT_ACCEPTED'}
    }finally{$ErrorActionPreference=$previous}
    if((Get-FileHash -LiteralPath $shortcut).Hash -ne $before){throw 'UNOWNED_SHORTCUT_CHANGED'}
    Write-Host 'NOTIFICATION_SHORTCUT_OK:real-COM;AUMID;target;fresh-and-update-rollback;byte-preservation;unowned-rejected'
}finally{if(Test-Path $temp){Remove-PvsSafeTree -Path $temp -Root $env:TEMP}}
