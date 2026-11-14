$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$root=Resolve-Path (Join-Path $PSScriptRoot '..\..')
& (Join-Path $root 'installer\build-notifications.ps1')
foreach($file in @('native-notifications.test.js','native-notification-ipc.test.js','notification-delivery.test.js')) {
    & node (Join-Path $PSScriptRoot $file)
    if($LASTEXITCODE -ne 0){throw "NATIVE_NOTIFICATION_TEST_FAILED:$file"}
}
