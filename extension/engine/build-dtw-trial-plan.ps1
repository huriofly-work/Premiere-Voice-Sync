param([Parameter(Mandatory)][string]$JobPath,[switch]$ValidateOnly)
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
. "$PSScriptRoot\lib\Srt.ps1"
. "$PSScriptRoot\lib\Alignment.ps1"
. "$PSScriptRoot\lib\Native.ps1"
. "$PSScriptRoot\lib\Paths.ps1"
. "$PSScriptRoot\lib\DtwEditTrial.ps1"

$job=Get-Content -LiteralPath $JobPath -Raw -Encoding UTF8 | ConvertFrom-Json
$output=[IO.Path]::GetFullPath([string]$job.outputFolder)
Assert-PvsSafePath -Path $JobPath -Root $output
Assert-PvsSafePath -Path $output -Tree
Assert-PvsDtwTrialInput $job
if($ValidateOnly){Write-Host 'DTW_EDIT_TRIAL_INPUT_OK:voice-speed-preserved;no-ASR;no-Premiere-calls';return}
$baseline=Get-Content -LiteralPath (Join-Path $output 'sentence-edit-plan.json') -Raw -Encoding UTF8 | ConvertFrom-Json
Assert-PvsDtwTrialJob $job $baseline
Assert-PvsRuntimeLock -EngineRoot $PSScriptRoot
$useAudioCache=if($job.PSObject.Properties['algorithm'] -and $job.algorithm.PSObject.Properties['useWhisperCache']){[bool]$job.algorithm.useWhisperCache}else{$true}
Initialize-PvsAudioCache -Enabled $useAudioCache -RuntimeIdentity ((Get-PvsAudioFileDigest "$PSScriptRoot\runtime-lock.json")+'|'+(Get-PvsAudioFileDigest "$PSScriptRoot\cuda-lock.json"))
$alignment=Get-Content -LiteralPath (Join-Path $output 'alignment-result.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$voices=@($baseline.voiceClips);$fps=[double]$baseline.frameRate;$settings=$baseline.settings
if($voices.Count -ne [int]$alignment.voiceChapterCount){throw 'TRIAL_CHAPTER_COUNT_MISMATCH'}
# Extract only detector functions, without executing script-scope planner code.
$ast=[Management.Automation.Language.Parser]::ParseFile("$PSScriptRoot\build-sentence-plan.ps1",[ref]$null,[ref]$null)
foreach($name in @('Find-SafeVoiceBoundary','Get-VoiceSilences')){
    $function=$ast.Find({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name},$true)
    if(-not $function){throw 'TRIAL_STABLE_DETECTOR_MISSING'}
    . ([scriptblock]::Create($function.Extent.Text))
}
$config=Get-Content -LiteralPath "$PSScriptRoot\runtime\engine.json" -Raw -Encoding UTF8 | ConvertFrom-Json
$ffmpeg=Join-Path "$PSScriptRoot\runtime" ([string]$config.ffmpeg)
$quiet=@(foreach($voice in $voices){
    $media=Resolve-PvsExistingPath -Path $voice.path -Purpose 'Trial voice'
    Get-VoiceSilences -MediaPath $media -TimelineStart $voice.start -SpeedPercent $voice.speedPercent -FfmpegPath $ffmpeg -NoiseDb $settings.silenceNoiseDb -MinDuration $settings.minSilenceDurationSeconds
})
$legacy={param($p,$q,$d,$r,$m,$f) Find-SafeVoiceBoundary $p $q $d $r $m $f}
$quietCache=Get-PvsAudioCacheStats
$rows=@(Get-PvsDtwBoundaryTrial -Cues @($alignment.cues | Sort-Object Index) -Voices $voices -Silences $quiet -FrameRate $fps -LegacyFinder $legacy -MinimumSilence $settings.minSilenceDurationSeconds -SearchRadius $settings.boundarySearchSeconds -SafetyMargin $settings.boundarySafetyMarginSeconds -MinimumLegacyConfidence $settings.lowConfidenceThreshold -MinimumNoDialogueGap $baseline.minNoDialogueGapSeconds -EndCharacters $settings.sentenceEndCharacters -PreserveCuePictures:([bool]$baseline.PSObject.Properties['pictureCueRevision']))
$added=@($rows | Where-Object Status -eq 'candidate')
$report=[ordered]@{ok=$true;revision='dtw-additive-v1';canApply=$false;addedCutCount=$added.Count;stableGroups=$baseline.summary.safeSentenceGroupCount;trialGroups=$baseline.summary.safeSentenceGroupCount;stableSpeedWarnings=$baseline.summary.speedWarningCount;trialSpeedWarnings=$baseline.summary.speedWarningCount;coverageVerified=$false;existingCutsPreserved=$false;durationChangedFrames=0;newPauses=0;planPath='';boundaries=$added}
$report.audioCache=$quietCache
function Write-TrialJson($Value,[string]$Path){[IO.File]::WriteAllText($Path,(ConvertTo-Json -InputObject $Value -Depth 20),(New-Object Text.UTF8Encoding($false)))}
if($added.Count){
    $candidateFolder=Join-Path $output 'dtw-trial'
    Assert-PvsSafePath -Path $candidateFolder -Root $output -Tree
    if(Test-Path -LiteralPath $candidateFolder){throw 'TRIAL_OUTPUT_EXISTS'}
    New-Item -ItemType Directory -Path $candidateFolder | Out-Null
    $candidateJob=$job | ConvertTo-Json -Depth 20 | ConvertFrom-Json
    $candidateJob.outputFolder=$candidateFolder
    $candidateJobPath=Join-Path $candidateFolder 'job.json'
    Write-TrialJson $candidateJob $candidateJobPath
    $candidateAlignment=ConvertTo-PvsTrialAlignment $alignment $rows $fps
    Write-TrialJson $candidateAlignment (Join-Path $candidateFolder 'alignment-result.json')
    # Fresh child process, same stable planner/settings, no ASR retry.
    $run=Invoke-NativeCapture -FilePath (Join-Path $PSHOME 'powershell.exe') -Arguments @('-NoProfile','-ExecutionPolicy','Bypass','-File',"$PSScriptRoot\build-sentence-plan.ps1",'-JobPath',$candidateJobPath)
    if($run.ExitCode -ne 0){throw "TRIAL_CANDIDATE_PLANNER_FAILED:$($run.Output)"}
    $planPath=Join-Path $candidateFolder 'sentence-edit-plan.json'
    $candidate=Get-Content -LiteralPath $planPath -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-PvsDtwTrialJob $candidateJob $candidate
    Assert-PvsDtwTrialCuts $baseline $candidate $rows
    $candidate | Add-Member -NotePropertyName editBoundaryTrial -NotePropertyValue 'dtw-additive-v1'
    Write-TrialJson $candidate $planPath
    $report.canApply=$true;$report.coverageVerified=$true;$report.existingCutsPreserved=$true
    $report.trialGroups=$candidate.summary.safeSentenceGroupCount;$report.trialSpeedWarnings=$candidate.summary.speedWarningCount;$report.planPath=$planPath
}
Write-TrialJson $report (Join-Path $output 'dtw-trial-report.json')
Write-Host "DTW_EDIT_TRIAL_READY:added-cuts=$($added.Count);can-apply=$($report.canApply);no-Premiere-calls"
