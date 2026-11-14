param([Parameter(Mandatory)][string]$FixtureRoot,[double]$FrameRate=30,[double[]]$VoiceSpeeds=@(),[switch]$FreshAlignment,[string]$WhisperCacheRoot='',[string]$BackendDataRoot='',[switch]$SpeedMerge)
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$root=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$engine=Join-Path $root 'extension\engine'
. "$engine\lib\Native.ps1"
. "$engine\lib\DtwEditTrial.ps1"
. "$engine\lib\SpeedMergeTrial.ps1"
$fixture=(Resolve-Path -LiteralPath $FixtureRoot).Path
$metadata=Get-Content -LiteralPath (Join-Path $fixture 'inputs.private.json') -Raw -Encoding UTF8 | ConvertFrom-Json
foreach($file in $metadata.files){if((Get-FileHash -LiteralPath $file.Path).Hash -ne $file.Hash){throw 'TRIAL_FIXTURE_MEDIA_CHANGED'}}
$temporary=Join-Path $env:TEMP ('PVS-DtwTrialIntegration-'+[guid]::NewGuid().ToString('N'))
Assert-PvsSafePath -Path $temporary -Root $env:TEMP
$oldLocal=$env:LOCALAPPDATA;$oldTemp=$env:TEMP
try {
    New-Item -ItemType Directory -Path $temporary | Out-Null
    $job=Get-Content -LiteralPath (Join-Path $fixture 'job.private.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $job.outputFolder=$temporary;$job.sequence.frameRate=$FrameRate
    $job.sequence.sequenceId='mock-template-no-Premiere-calls'
    $job.sequence.mainVideoClip | Add-Member nodeId 'mock-video' -Force
    $job.sequence.linkedAudio=@([pscustomobject]@{nodeId='mock-audio';start=$job.sequence.mainVideoClip.start;end=$job.sequence.mainVideoClip.end})
    $alignment=Get-Content -LiteralPath (Join-Path $fixture 'alignment.private.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    if($VoiceSpeeds.Count){
        if($VoiceSpeeds.Count -eq 1){$VoiceSpeeds=@(foreach($v in $job.sequence.voices){$VoiceSpeeds[0]})}
        if($VoiceSpeeds.Count -ne @($job.sequence.voices).Count){throw 'TEST_CHAPTER_SPEED_COUNT_INVALID'}
        $cursor=0.0
        for($chapter=0;$chapter -lt $VoiceSpeeds.Count;$chapter++){
            $speed=$VoiceSpeeds[$chapter];if($speed -lt 1 -or [double]::IsNaN($speed) -or [double]::IsInfinity($speed)){throw 'TEST_CHAPTER_SPEED_INVALID'}
            $voice=$job.sequence.voices[$chapter];$oldStart=[double]$voice.start;$scale=[double]$voice.speedPercent/$speed
            $duration=([double]$voice.end-$oldStart)*$scale
            foreach($cue in @($alignment.cues | Where-Object Chapter -eq $chapter)){
                foreach($field in @('Start','End','CaptionStart','CaptionEnd')){if($cue.PSObject.Properties[$field] -and $null -ne $cue.$field){$cue.$field=$cursor+([double]$cue.$field-$oldStart)*$scale}}
                foreach($timingsField in @('WordTimings','CaptionWordTimings')){
                    if(-not $cue.PSObject.Properties[$timingsField]){continue}
                    foreach($word in @($cue.$timingsField)){
                        foreach($field in @('Start','End','ContinuousTokenStart')){if($word.PSObject.Properties[$field] -and $null -ne $word.$field){$word.$field=$cursor+([double]$word.$field-$oldStart)*$scale}}
                    }
                }
            }
            $voice.start=$cursor;$voice.end=$cursor+$duration;$voice.speedPercent=$speed;$cursor+=$duration
        }
    }
    foreach($voice in $job.sequence.voices){$voice | Add-Member inPoint 0.0 -Force}
    $job | Add-Member workflow 'experimental-dtw-direct' -Force
    $job | Add-Member editBoundaryTrial 'dtw-additive-v1' -Force
    if($SpeedMerge){
        $job | Add-Member speedMergeTrial 'adjacent-speed-v2' -Force
        if(-not $job.PSObject.Properties['speedWarningMinPercent']){$job | Add-Member speedWarningMinPercent 70.0}
        if(-not $job.PSObject.Properties['speedWarningMaxPercent']){$job | Add-Member speedWarningMaxPercent 130.0}
    }
    $jobPath=Join-Path $temporary 'job.json'
    [IO.File]::WriteAllText($jobPath,($job | ConvertTo-Json -Depth 20),(New-Object Text.UTF8Encoding($false)))
    [IO.File]::WriteAllText((Join-Path $temporary 'alignment-result.json'),($alignment | ConvertTo-Json -Depth 20),(New-Object Text.UTF8Encoding($false)))
    if($FreshAlignment){
        $env:LOCALAPPDATA=Join-Path $temporary 'local';$env:TEMP=Join-Path $temporary 'temp'
        $data=Join-Path $env:LOCALAPPDATA 'PremiereVoiceSync';$cache=Join-Path $data 'Cache\Whisper'
        New-Item -ItemType Directory -Path $cache,$env:TEMP -Force | Out-Null
        if($WhisperCacheRoot){foreach($file in (Get-ChildItem -LiteralPath $WhisperCacheRoot -File -Filter '*.json')){Copy-Item -LiteralPath $file.FullName -Destination $cache}}
        if($BackendDataRoot){Copy-Item -LiteralPath (Join-Path $BackendDataRoot 'backends') -Destination $data -Recurse;Copy-Item -LiteralPath (Join-Path $BackendDataRoot 'backend-state.json') -Destination $data}
        Write-Host "TRIAL_MEDIA_PHASE:fresh-alignment-at-voice-speeds=$($VoiceSpeeds -join ',');private-cache-fixture;no-Premiere-calls"
        $run=Invoke-NativeCapture (Join-Path $PSHOME 'powershell.exe') @('-NoProfile','-ExecutionPolicy','Bypass','-File',"$engine\run-alignment.ps1",'-JobPath',$jobPath)
        if($run.ExitCode -ne 0){throw "TRIAL_FRESH_ALIGNMENT_FAILED:$($run.Output)"}
        Write-Host 'TRIAL_MEDIA_PHASE:fresh-alignment-complete;baseline-and-candidate'
    }
    $before=@(foreach($name in @('job.json','alignment-result.json')){(Get-FileHash -LiteralPath (Join-Path $temporary $name)).Hash})
    $run=Invoke-NativeCapture (Join-Path $PSHOME 'powershell.exe') @('-NoProfile','-ExecutionPolicy','Bypass','-File',"$engine\build-sentence-plan.ps1",'-JobPath',$jobPath)
    if($run.ExitCode -ne 0){throw "TRIAL_MEDIA_BASELINE_FAILED:$($run.Output)"}
    $baselineHash=(Get-FileHash -LiteralPath (Join-Path $temporary 'sentence-edit-plan.json')).Hash
    $baseline=Get-Content -LiteralPath (Join-Path $temporary 'sentence-edit-plan.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $early=Invoke-NativeCapture (Join-Path $PSHOME 'powershell.exe') @('-NoProfile','-ExecutionPolicy','Bypass','-File',"$engine\build-dtw-trial-plan.ps1",'-JobPath',$jobPath,'-ValidateOnly')
    if($early.ExitCode -ne 0 -or $early.Output -notmatch 'DTW_EDIT_TRIAL_INPUT_OK'){throw 'TRIAL_MEDIA_PREFLIGHT_FAILED'}
    $run=Invoke-NativeCapture (Join-Path $PSHOME 'powershell.exe') @('-NoProfile','-ExecutionPolicy','Bypass','-File',"$engine\build-dtw-trial-plan.ps1",'-JobPath',$jobPath)
    if($run.ExitCode -ne 0){throw "TRIAL_MEDIA_WRAPPER_FAILED:$($run.Output)"}
    if($baselineHash -ne (Get-FileHash -LiteralPath (Join-Path $temporary 'sentence-edit-plan.json')).Hash){throw 'TRIAL_BASELINE_OVERWRITTEN'}
    $after=@(foreach($name in @('job.json','alignment-result.json')){(Get-FileHash -LiteralPath (Join-Path $temporary $name)).Hash})
    if(($before -join ',') -cne ($after -join ',')){throw 'TRIAL_MEDIA_INPUT_MUTATED'}
    $report=Get-Content -LiteralPath (Join-Path $temporary 'dtw-trial-report.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    if(-not $report.canApply -or -not $report.coverageVerified -or -not $report.existingCutsPreserved -or $report.addedCutCount -le 0 -or $report.stableGroups -ne $baseline.summary.safeSentenceGroupCount -or $report.trialGroups -ne $report.stableGroups+$report.addedCutCount){throw 'TRIAL_MEDIA_RESULT_CHANGED'}
    if(-not $VoiceSpeeds.Count -and ($report.addedCutCount -ne 5 -or $report.stableGroups -ne 222 -or $report.trialGroups -ne 227)){throw 'TRIAL_ORIGINAL_MEDIA_RESULT_CHANGED'}
    $candidate=Get-Content -LiteralPath $report.planPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if($candidate.sequenceId -ne $job.sequence.sequenceId -or $candidate.editBoundaryTrial -ne 'dtw-additive-v1'){throw 'TRIAL_MEDIA_PLAN_IDENTITY_CHANGED'}
    if(($candidate.voiceClips.speedPercent -join ',') -cne ($job.sequence.voices.speedPercent -join ',')){throw 'TRIAL_VOICE_SPEED_CHANGED'}
    if($SpeedMerge){
        $candidateHash=(Get-FileHash -LiteralPath $report.planPath).Hash
        $run=Invoke-NativeCapture (Join-Path $PSHOME 'powershell.exe') @('-NoProfile','-ExecutionPolicy','Bypass','-File',"$engine\build-speed-merge-trial-plan.ps1",'-JobPath',$jobPath,'-ValidateOnly')
        if($run.ExitCode -ne 0 -or $run.Output -notmatch 'SPEED_MERGE_INPUT_OK'){throw "SPEED_MERGE_MEDIA_PREFLIGHT_FAILED:$($run.Output)"}
        $run=Invoke-NativeCapture (Join-Path $PSHOME 'powershell.exe') @('-NoProfile','-ExecutionPolicy','Bypass','-File',"$engine\build-speed-merge-trial-plan.ps1",'-JobPath',$jobPath,'-PlanPath',$report.planPath)
        if($run.ExitCode -ne 0){throw "SPEED_MERGE_MEDIA_WRAPPER_FAILED:$($run.Output)"}
        $mergeReport=Get-Content -LiteralPath (Join-Path $temporary 'speed-merge-report.json') -Raw -Encoding UTF8 | ConvertFrom-Json
        $merged=Get-Content -LiteralPath $mergeReport.planPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $null=Assert-PvsSpeedMergePlan $candidate $merged
        if($candidateHash -ne (Get-FileHash -LiteralPath $report.planPath).Hash){throw 'SPEED_MERGE_OVERWROTE_DTW_CANDIDATE'}
        if($baselineHash -ne (Get-FileHash -LiteralPath (Join-Path $temporary 'sentence-edit-plan.json')).Hash){throw 'SPEED_MERGE_OVERWROTE_BASELINE'}
        $cross=@($merged.visualSegments | Where-Object {$_.PSObject.Properties['Chapters'] -and $_.Chapters.Count -gt 1}).Count
        Write-Host "SPEED_MERGE_MEDIA_OK:fps=$FrameRate;voice-speeds=$($VoiceSpeeds -join ',');visual=$($mergeReport.summary.visualGroupsBefore)-$($mergeReport.summary.visualGroupsAfter);merges=$($mergeReport.summary.mergeCount);warnings=$($mergeReport.summary.warningsBefore)-$($mergeReport.summary.warningsAfter);cross-chapter=$cross;voice-captions-unchanged;no-Premiere-calls"
    }
    foreach($file in $metadata.files){if((Get-FileHash -LiteralPath $file.Path).Hash -ne $file.Hash){throw 'TRIAL_FIXTURE_MEDIA_MUTATED'}}
    $mode=if($FreshAlignment){'fresh-alignment-native-recognition-or-verified-cache'}else{'scaled-prior-alignment-not-fresh-ASR'}
    Write-Host "DTW_EDIT_TRIAL_MEDIA_OK:fps=$FrameRate;voice-speeds=$($VoiceSpeeds -join ',');groups=$($report.stableGroups)-$($report.trialGroups);added-cuts=$($report.addedCutCount);old-cuts-preserved;voice-speed-preserved;source-voice-caption-conserved;baseline-and-media-unchanged;$mode;no-Premiere-calls"
} finally {
    $env:LOCALAPPDATA=$oldLocal;$env:TEMP=$oldTemp
    Remove-PvsSafeTree -Path $temporary -Root $oldTemp
}
