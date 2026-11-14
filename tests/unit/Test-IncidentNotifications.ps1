$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$projectRoot = Resolve-Path (Join-Path $PSScriptRoot '..\..')
$helper = Join-Path $projectRoot 'extension\engine\request-attention.ps1'
. $helper
$script:attentionRecords = @{}
$read = { param($ProcessId) $script:attentionRecords[$ProcessId] }
function Set-Records {
    $script:attentionRecords = @{
        100 = [pscustomobject]@{ ProcessId=100; ParentProcessId=200; SessionId=1; CreationDate=[datetime]'2026-10-15T10:00:03'; Name='CEPHtmlEngine.exe'; ExecutablePath='C:\Adobe\CEPHtmlEngine.exe' }
        200 = [pscustomobject]@{ ProcessId=200; ParentProcessId=300; SessionId=1; CreationDate=[datetime]'2026-10-15T10:00:02'; Name='CEPHtmlEngine.exe'; ExecutablePath='C:\Adobe\CEPHtmlEngine.exe' }
        300 = [pscustomobject]@{ ProcessId=300; ParentProcessId=0; SessionId=1; CreationDate=[datetime]'2026-10-15T10:00:01'; Name='Adobe Premiere Pro.exe'; ExecutablePath='C:\Adobe\Adobe Premiere Pro.exe' }
    }
}
Set-Records
if ((Find-PvsAttentionHost -StartId 100 -ReadProcess $read).ProcessId -ne 300) { throw 'HOST_ANCESTRY_FAILED' }
foreach ($scenario in @('cycle','missing','session','reused-pid','wrong-executable','unrelated-premiere')) {
    Set-Records
    switch ($scenario) {
        'cycle' { $script:attentionRecords[200].ParentProcessId=100 }
        'missing' { $script:attentionRecords.Remove(200) }
        'session' { $script:attentionRecords[300].SessionId=2 }
        'reused-pid' { $script:attentionRecords[300].CreationDate=[datetime]'2026-10-15T10:01:00' }
        'wrong-executable' { $script:attentionRecords[300].ExecutablePath='C:\Adobe\other.exe' }
        'unrelated-premiere' { $script:attentionRecords[200].ParentProcessId=0 }
    }
    if ($null -ne (Find-PvsAttentionHost -StartId 100 -ReadProcess $read)) { throw "UNSAFE_HOST_SELECTION:$scenario" }
}
# Compile native declarations without ever activating or flashing a real window.
$text = [IO.File]::ReadAllText($helper)
$native = [regex]::Match($text,"(?s)Add-Type -TypeDefinition @'\r?\n(.*?)\r?\n'@").Groups[1].Value
if (-not $native) { throw 'NATIVE_DECLARATIONS_MISSING' }
Add-Type -TypeDefinition $native
$probe = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $helper -CallerProcessId $PID -ProbeOnly | ConvertFrom-Json
if ($probe.reason -notin @('host-not-in-ancestry','probe-only','attention-unavailable')) { throw 'READ_ONLY_PROBE_INVALID' }
& node (Join-Path $PSScriptRoot 'incident-notifications.test.js')
if ($LASTEXITCODE -ne 0) { throw 'INCIDENT_NOTIFICATIONS_FAILED' }
Write-Host 'ATTENTION_HOST_POLICY_OK:ancestry-only;cycles;session;pid-reuse;executable;unrelated-host;native-declarations-compiled;probe-only-no-window-activation'
