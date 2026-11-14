$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$root=Resolve-Path (Join-Path $PSScriptRoot '..\..')
# Mocked processes/DOM only. No native helper, desktop, Windows registry or shortcuts.
foreach($file in @('native-notifications.test.js','notification-delivery.test.js','incident-notifications.test.js','notification-ux.test.js')) {
    & node (Join-Path $PSScriptRoot $file)
    if($LASTEXITCODE -ne 0){throw "NOTIFICATION_LOGIC_FAILED:$file"}
}
