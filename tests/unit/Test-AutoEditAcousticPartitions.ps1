$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$root=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
. "$root\extension\engine\lib\CaptionOnly.ps1"
. "$root\extension\engine\lib\Srt.ps1"
. "$root\extension\engine\lib\CaptionTiming.ps1"
. "$root\extension\engine\lib\AutoEditManualReview.ps1"
. "$root\extension\engine\lib\SpeedMergeTrial.ps1"
. "$root\extension\engine\lib\DtwEditTrial.ps1"
function Check([bool]$Value,[string]$Message){if(-not $Value){throw "ACOUSTIC_PARTITION_TEST_FAILED:$Message"}}
function Copy-Json($Value){$copy=ConvertFrom-Json (ConvertTo-Json -InputObject $Value -Depth 30);foreach($item in $copy){$item}}
$refs=@();$words=@();$cells=@();$quiet=@()
for($i=0;$i -lt 4;$i++){
    $tokens=@(0..5|ForEach-Object {"word$($i)token$_"})
    $start=if($i -eq 0){0.0}elseif($i -eq 1){3.7}else{1.0+3*$i}
    $end=if($i -eq 0){3.0}else{4.0+3*$i}
    $text=($tokens -join ' ')+'.'
    $refs+=[pscustomobject]@{Index=$i+1;Text=$text;Start=$start;End=$end}
    $cells+=[pscustomobject]@{Text=$text;Start=10.0+$i*3;End=12.8+$i*3;ReferenceCueIndices=@($i+1)}
    for($w=0;$w -lt 6;$w++){$words+=[pscustomobject]@{Text=$tokens[$w];Start=$i*3+0.3+$w*0.3;End=$i*3+0.5+$w*0.3;Chapter=0;SubtitleTimingQuality='dtw'}}
    if($i -lt 3){$quiet+=[pscustomobject]@{Start=12.3+$i*3;End=13.0+$i*3;Duration=0.7}}
}
$voices=@([pscustomobject]@{start=10.0;end=22.0;speedPercent=100;inPoint=0;path='';name='fixture'})
$cuts=@(Get-PvsAcousticReferenceCuts $refs $words $voices $quiet 30)
Check ($cuts.Count -eq 3) 'all-quiet-intervals-remain-available'
foreach($cut in $cuts){Check (Test-PvsAcousticReferenceCut $cut $refs $voices $quiet 30) 'proof-roundtrip'}
foreach($fault in @('estimated','duplicate','extra-speech','overlap','nan','outside','different-chapter','trimmed','no-quiet','too-short','no-frame')){
    $w=Copy-Json $words;$v=Copy-Json $voices;$q=Copy-Json $quiet;$fps=30
    switch($fault){
        estimated {$w[2].SubtitleTimingQuality='estimated'}
        duplicate {$w=@($w)+@($w[2..5])}
        extra-speech {$extra=$w[5].PSObject.Copy();$extra.Text='extra';$extra.Start=2.1;$extra.End=2.2;$w=@($w[0..5]) + @($extra) + @($w[6..23])}
        overlap {$w[3].Start=$w[2].Start}
        nan {$w[3].End=[double]::NaN}
        outside {$w[3].End=50}
        different-chapter {$w[6].Chapter=1}
        trimmed {$v[0].inPoint=1}
        no-quiet {$q=@()}
        too-short {$q[0].Duration=0.01}
        no-frame {$fps=0.01}
    }
    $bad=@(Get-PvsAcousticReferenceCuts $refs $w $v $q $fps)
    Check (-not @($bad|Where-Object leftCue -eq 1).Count) "cut-rejected-$fault"
}
foreach($fps in @(0,-1,[double]::NaN,[double]::PositiveInfinity)){
    $rejected=$false;try{Get-PvsAcousticReferenceCuts $refs $words $voices $quiet $fps|Out-Null}catch{$rejected=$_.Exception.Message -eq 'ACOUSTIC_PARTITION_FRAME_RATE_INVALID'}
    Check $rejected 'invalid-frame-rate'
}
$cue=[pscustomobject]@{Index=1;Chapter=0;Text=($cells.Text -join ' ');Start=10.0;End=22.0;OriginalStart=0;OriginalEnd=13.0;Confidence=0.0;ManualEditBlock=$true;EditBoundaryReviewRequired=$true;ManualReferenceCueIndices=@(1,2,3,4);ManualCaptionCues=$cells;WordTimings=@()}
$cues=@($cue)
$uncalibrated=Copy-Json $cues
Check ((Set-PvsManualAcousticCaptionTimings $cues $words $voices) -eq 4) 'complete-cells-refined-automatically'
$retryCues=Copy-Json $uncalibrated;$broken=Copy-Json $words;$broken[0].Text='wrong'
$script:goldRetryWords=$words
$retryStats=[pscustomobject]@{Calls=0}
$refined=Set-PvsManualAcousticCaptionTimings $retryCues $broken $voices {
    param($start,$end,$text,$chapter,$manualOnly)
    Check $manualOnly 'retry-estimates-are-local-diagnostics'
    foreach($w in $script:goldRetryWords){if(10+$w.Start -ge $start -and 10+$w.End -le $end){$copy=$w.PSObject.Copy();$copy.Start+=10-$start;$copy.End+=10-$start;$copy}}
} $retryStats
Check ($refined -eq 4 -and $retryStats.Calls -eq 1) 'local-acoustic-retry-resolves-model-error'
$failed=$false;try{Set-PvsManualAcousticCaptionTimings (Copy-Json $uncalibrated) $broken $voices {throw 'FIXTURE_NATIVE_FAILURE'}|Out-Null}catch{$failed=$_.Exception.Message -eq 'FIXTURE_NATIVE_FAILURE'}
Check $failed 'technical-retry-error-propagates'
Check ($cue.Confidence -eq 0 -and $cue.WordTimings.Count -eq 0 -and $cue.EditBoundaryReviewRequired) 'manual-caption-not-edit-authority'
$badCell=Copy-Json $cells[0];$badCell.CaptionWordTimings[0].SubtitleTimingQuality='estimated'
Check (-not (Test-PvsManualAcousticCell $badCell $voices[0])) 'estimated-cell-not-promoted'
$parts=@(Split-PvsManualReviewCaptionCue $cue 30 30 -UseAcousticTiming)
Check (@($parts|Where-Object CaptionTimingQuality -eq 'dtw').Count -eq $parts.Count) 'measured-splits'
Check (($parts.Text -join ' ') -ceq ($cells.Text -join ' ')) 'split-text-conservation'
$legacy=@(Split-PvsManualReviewCaptionCue $cue 30 30)
Check (-not @($legacy|Where-Object VoiceBoundaryAligned).Count) 'no-capability-keeps-old-manual-safety'
$testRoot=Join-Path $root '.tmp-acoustic-partition-tests'
$temp=Join-Path $testRoot ([guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path "$temp\engine\lib","$temp\engine\runtime" -Force|Out-Null
try {
    $engine=Join-Path $temp 'engine'
    Copy-Item "$root\extension\engine\build-sentence-plan.ps1" $engine
    Get-ChildItem "$root\extension\engine\lib" -File|Copy-Item -Destination "$engine\lib"
    foreach($name in @('runtime-lock.json','cuda-lock.json')){Copy-Item "$root\extension\engine\$name" $engine}
    Set-Content "$engine\lib\Native.ps1" -Encoding ASCII -Value '. "$PSScriptRoot\Security.ps1"; . "$PSScriptRoot\AudioCache.ps1"; function Invoke-NativeCapture {param($FilePath,$Arguments);[pscustomobject]@{ExitCode=0;Output="silence_start: 2.3`nsilence_end: 3.0`nsilence_start: 5.3`nsilence_end: 6.0`nsilence_start: 8.3`nsilence_end: 9.0"}}'
    Set-Content "$engine\runtime\engine.json" -Encoding ASCII -Value '{"ffmpeg":"fixture"}'
    $voices[0].path="$temp\voice.wav";Set-Content $voices[0].path '' -Encoding ASCII
    $task=[pscustomobject]@{cueIndex=1;cueIndices=@(1,2,3,4);chapter=0;sourceStart=0;sourceEnd=13;start=10;end=22;captionCells=$cells;pendingReferenceCueIndices=@();status='manual-review-pending'}
    $alignment=[ordered]@{voiceChapterCount=1;cues=$cues;autoEditManualReviewBlocks=@($task);referenceCueCount=4;acousticEditBoundaryRevision='raw-dtw-quiet-partition-v1';acousticEditWords=$words;acousticEditReferenceCues=$refs}
    $job=@{outputFolder=$temp;speedWarningMinPercent=70;speedWarningMaxPercent=130;algorithm=@{useWhisperCache=$false};sequence=@{frameRate=30;sequenceId='acoustic';name='acoustic';mainVideoClip=@{start=0;end=13};voices=$voices;linkedAudio=@();voiceTrackIndex=1}}
    $job|ConvertTo-Json -Depth 12|Set-Content "$temp\job.json" -Encoding UTF8
    $oldAlignment=Copy-Json ([pscustomobject]$alignment)
    foreach($field in @('acousticEditBoundaryRevision','acousticEditWords','acousticEditReferenceCues')){$oldAlignment.PSObject.Properties.Remove($field)}
    $oldAlignment|ConvertTo-Json -Depth 25|Set-Content "$temp\alignment-result.json" -Encoding UTF8
    & "$engine\build-sentence-plan.ps1" -JobPath "$temp\job.json"|Out-Null
    $oldPlan=Get-Content "$temp\sentence-edit-plan.json" -Raw -Encoding UTF8|ConvertFrom-Json
    Check ($oldPlan.summary.safeSentenceGroupCount -eq 1 -and -not @($oldPlan.captions|Where-Object VoiceBoundaryAligned).Count) 'reproduces-coarse-manual-block-without-independent-proof'
    $oldAlignment|Add-Member manualCaptionTimingRevision 'raw-dtw-cell-overlay-v1'
    $oldAlignment|ConvertTo-Json -Depth 25|Set-Content "$temp\alignment-result.json" -Encoding UTF8
    & "$engine\build-sentence-plan.ps1" -JobPath "$temp\job.json"|Out-Null
    $captionOnlyPlan=Get-Content "$temp\sentence-edit-plan.json" -Raw -Encoding UTF8|ConvertFrom-Json
    Check ($captionOnlyPlan.summary.safeSentenceGroupCount -eq 1 -and @($captionOnlyPlan.captions|Where-Object VoiceBoundaryAligned).Count -eq $captionOnlyPlan.captions.Count) 'measured-captions-work-without-picture-cut-permission'
    Assert-PvsManualReviewPlan $captionOnlyPlan
    $alignment|ConvertTo-Json -Depth 25|Set-Content "$temp\alignment-result.json" -Encoding UTF8
    & "$engine\build-sentence-plan.ps1" -JobPath "$temp\job.json"|Out-Null
    $plan=Get-Content "$temp\sentence-edit-plan.json" -Raw -Encoding UTF8|ConvertFrom-Json
    Check ($plan.summary.safeSentenceGroupCount -eq 4 -and $plan.summary.longNoDialogueGapCount -eq 1) 'independent-picture-partitions-and-source-gap'
    Assert-PvsManualReviewPlan $plan
    $candidate=Get-PvsSpeedMergeTrial $plan
    Assert-PvsManualReviewPlan $candidate
    Assert-PvsTrialPlanConservation $plan $candidate|Out-Null
    Check ((@(Read-SrtFile $plan.captionSrtPath).Text -join ' ') -ceq ($cells.Text -join ' ')) 'final-srt-text'
    foreach($fault in @('source','voice','text','proof','omission','timing','chapter','reference')){
        $bad=Copy-Json $plan
        switch($fault){
            source {$bad.segments[0].SourceEndFrame--}
            voice {$bad.segments[0].OriginalVoiceEndFrame--}
            text {$bad.captions[0].Text='lost'}
            proof {$bad.acousticEditBoundaryProofs[0].context[0].SubtitleTimingQuality='estimated'}
            omission {$bad|Add-Member omittedReferenceCueIndices @(1)}
            timing {$bad.captions[0].CaptionTimingQuality='estimated'}
            chapter {$bad.segments[0].Chapter=1}
            reference {$bad.segments[0].LastTargetCue=2}
        }
        $rejected=$false;try{Assert-PvsManualReviewPlan $bad}catch{$rejected=$true};Check $rejected "tamper-$fault"
    }
    # The shipping v2 planner must refine picture even without a single
    # permitted physical-voice cut; a long source gap remains protected.
    $alignment.acousticEditBoundaryRevision='dtw-cue-quiet-partition-v2'
    Set-Content "$engine\lib\Native.ps1" -Encoding ASCII -Value '. "$PSScriptRoot\Security.ps1"; . "$PSScriptRoot\AudioCache.ps1"; function Invoke-NativeCapture {param($FilePath,$Arguments);[pscustomobject]@{ExitCode=0;Output=""}}'
    $alignment|ConvertTo-Json -Depth 25|Set-Content "$temp\alignment-result.json" -Encoding UTF8
    & "$engine\build-sentence-plan.ps1" -JobPath "$temp\job.json"|Out-Null
    $picturePlan=Get-Content "$temp\sentence-edit-plan.json" -Raw -Encoding UTF8|ConvertFrom-Json
    Check ($picturePlan.summary.safeSentenceGroupCount -eq 1 -and $picturePlan.pictureCueSummary.pictureGroups -eq 3) 'shipping-v2-creates-picture-only-cue-cuts'
    Check ($picturePlan.pictureCueBoundaries.Count -eq 2 -and -not @($picturePlan.pictureCueBoundaries|Where-Object LeftCue -eq 1).Count) 'source-gap-not-swallowed-by-picture-only-cut'
    Assert-PvsManualReviewPlan $picturePlan
    $pictureMerged=Get-PvsSpeedMergeTrial $picturePlan
    Assert-PvsManualReviewPlan $pictureMerged
    Assert-PvsTrialPlanConservation $picturePlan $pictureMerged|Out-Null
    Check (($pictureMerged.pictureSegments|ConvertTo-Json -Depth 20 -Compress) -ceq ($picturePlan.pictureSegments|ConvertTo-Json -Depth 20 -Compress)) 'speed-merge-preserves-every-picture-cue'
} finally {
    $full=[IO.Path]::GetFullPath($temp)
    if(-not $full.StartsWith(([IO.Path]::GetFullPath($testRoot).TrimEnd('\')+'\'),[StringComparison]::OrdinalIgnoreCase)){throw 'UNSAFE_TEST_CLEANUP'}
    Remove-Item -LiteralPath $full -Recurse -Force
}
Write-Host 'AUTO_EDIT_ACOUSTIC_PARTITIONS_OK:raw-DTW;unique-context;quiet-margin;frames;all-quiet-candidates;negative-evidence;manual-text-preserved;caption-recovery;source-and-voice-conserved;speed-merge;tamper'
