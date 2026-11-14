param([string]$Package,[string]$Roaming,[string]$Local)
$ErrorActionPreference='Stop'
$global:pvsShortcutFailureInjected=$false
function Set-Content {
    [CmdletBinding()]param([string]$LiteralPath,[object]$Value,[string]$Encoding,[switch]$NoNewline)
    if (-not $global:pvsShortcutFailureInjected -and $LiteralPath -like '*\deployment-mode.txt') { $global:pvsShortcutFailureInjected=$true; throw 'INJECTED_POST_SHORTCUT_FAILURE' }
    Microsoft.PowerShell.Management\Set-Content @PSBoundParameters
}
& (Join-Path $Package 'scripts\install.ps1') -ApplicationDataRoot $Roaming -LocalApplicationDataRoot $Local -SkipRegistry -SkipProcessCheck
