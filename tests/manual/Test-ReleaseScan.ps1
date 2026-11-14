param([string]$Version='2.20.3')
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$root=Resolve-Path (Join-Path $PSScriptRoot '..\..')
. (Join-Path $root 'extension\engine\lib\Security.ps1')
if ($Version -notmatch '^\d+\.\d+\.\d+$') { throw 'INVALID_SCAN_VERSION' }
$dist=Join-Path $root 'dist'; $package=Join-Path $dist "Premiere-Voice-Sync-$Version-Panel"
$zip="$package.zip"
foreach ($target in @($package,$zip)) {
    Assert-PvsSafePath -Path $target -Root $dist -Tree
    if (-not (Test-Path -LiteralPath $target)) { throw 'SCAN_TARGET_MISSING' }
}
$status=Get-MpComputerStatus
if (-not $status.AntivirusEnabled -or -not $status.AMServiceEnabled) { throw 'DEFENDER_NOT_ENABLED' }
$started=Get-Date
foreach ($target in @($zip,$package)) { Start-MpScan -ScanType CustomScan -ScanPath $target }
$new=@(Get-MpThreatDetection | Where-Object { $_.InitialDetectionTime -ge $started })
$status=Get-MpComputerStatus
[pscustomobject]@{ScanCommandsCompleted=$true;AntivirusEnabled=$status.AntivirusEnabled;SignatureVersion=$status.AntivirusSignatureVersion;NewDetections=$new.Count;ZipSha256=(Get-FileHash -LiteralPath $zip).Hash} | ConvertTo-Json -Compress
if ($new.Count) { throw 'DEFENDER_NEW_DETECTION_REQUIRES_REVIEW' }
Write-Host 'DEFENDER_SCAN_COMPLETED:no new detections;not a security certification.'
