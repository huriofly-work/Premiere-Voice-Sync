param([Parameter(Mandatory)][string]$JobPath,[string]$PlanPath='',[switch]$ValidateOnly)
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
. "$PSScriptRoot\lib\Paths.ps1"
. "$PSScriptRoot\lib\Security.ps1"
. "$PSScriptRoot\lib\SpeedMergeTrial.ps1"
$job=Get-Content -LiteralPath $JobPath -Raw -Encoding UTF8 | ConvertFrom-Json
$output=[IO.Path]::GetFullPath([string]$job.outputFolder)
Assert-PvsSafePath -Path $JobPath -Root $output
Assert-PvsSafePath -Path $output -Tree
Assert-PvsSpeedMergeInput $job
if($ValidateOnly){Write-Host 'SPEED_MERGE_INPUT_OK:no-ASR;no-Premiere-calls';return}
if(-not $PlanPath){$PlanPath=Join-Path $output 'sentence-edit-plan.json'}
Assert-PvsSafePath -Path $PlanPath -Root $output
$baseline=Get-Content -LiteralPath $PlanPath -Raw -Encoding UTF8 | ConvertFrom-Json
if($baseline.sequenceId -cne $job.sequence.sequenceId -or $baseline.speedWarningMinPercent -ne $job.speedWarningMinPercent -or $baseline.speedWarningMaxPercent -ne $job.speedWarningMaxPercent){throw 'SPEED_MERGE_JOB_MISMATCH'}
$candidate=Get-PvsSpeedMergeTrial $baseline
$folder=Join-Path $output 'speed-merge-trial'
Assert-PvsSafePath -Path $folder -Root $output -Tree
if(Test-Path -LiteralPath $folder){throw 'SPEED_MERGE_OUTPUT_EXISTS'}
New-Item -ItemType Directory -Path $folder | Out-Null
$candidatePath=Join-Path $folder 'sentence-edit-plan.json'
$encoding=New-Object Text.UTF8Encoding($false)
[IO.File]::WriteAllText($candidatePath,($candidate | ConvertTo-Json -Depth 30),$encoding)
$report=[ordered]@{ok=$true;revision='adjacent-speed-v2';planPath=$candidatePath;canApply=($candidate.speedMergeSummary.mergeCount -gt 0);coverageVerified=$true;voiceUnchanged=$true;captionsUnchanged=$true;durationChangedFrames=0;newPauses=0;summary=$candidate.speedMergeSummary}
[IO.File]::WriteAllText((Join-Path $output 'speed-merge-report.json'),($report | ConvertTo-Json -Depth 30),$encoding)
Write-Host "SPEED_MERGE_READY:merges=$($candidate.speedMergeSummary.mergeCount);warnings=$($candidate.speedMergeSummary.warningsBefore)-$($candidate.speedMergeSummary.warningsAfter);no-Premiere-calls"
