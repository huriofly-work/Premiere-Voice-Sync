param([string]$Package,[string]$Roaming,[string]$Local)
$ErrorActionPreference='Stop'
function Move-Item {
    [CmdletBinding()] param([string]$LiteralPath,[string]$Destination)
    if ((Split-Path $LiteralPath -Leaf) -like '*.installing-*') { throw 'INJECTED_RENAME_FAILURE' }
    Microsoft.PowerShell.Management\Move-Item @PSBoundParameters
}
& (Join-Path $Package 'scripts\install.ps1') -ApplicationDataRoot $Roaming -LocalApplicationDataRoot $Local -SkipRegistry -SkipProcessCheck
