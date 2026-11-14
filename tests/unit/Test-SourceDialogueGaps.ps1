$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
. "$root\extension\engine\lib\CaptionOnly.ps1"
. "$root\extension\engine\lib\CaptionTiming.ps1"
. "$root\extension\engine\lib\DtwEditTrial.ps1"
. "$root\extension\engine\lib\SpeedMergeTrial.ps1"
$testRoot=Join-Path $root '.tmp-source-gap-tests'
$temp=Join-Path $testRoot ([guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path "$temp\engine\lib","$temp\engine\runtime" -Force | Out-Null
function Invoke-GapCase($Cues,[string]$Quiet="silence_start: 1.4`nsilence_end: 1.6",[double]$Threshold=0.5,[double]$Fps=30,[double]$VoiceStart=0,[double]$VoiceEnd=3,[double]$MainEnd=3,$SourceGaps=@(),[switch]$OmitThreshold){
    $case=Join-Path $temp ([guid]::NewGuid().ToString('N'));New-Item -ItemType Directory -Path $case | Out-Null
    $voice=Join-Path $case 'voice.wav';Set-Content -LiteralPath $voice -Value '' -Encoding ASCII
    $native='. "$PSScriptRoot\Security.ps1"; . "$PSScriptRoot\AudioCache.ps1"; function Invoke-NativeCapture {param($FilePath,$Arguments);[pscustomobject]@{ExitCode=0;Output="'+$Quiet.Replace('"','`"').Replace("`r",'').Replace("`n",'`n')+'"}}'
    Set-Content -LiteralPath "$temp\engine\lib\Native.ps1" -Value $native -Encoding ASCII
    $alignment=[ordered]@{voiceChapterCount=1;cues=$Cues}
    if($SourceGaps.Count){$alignment.sourceSubtitleGaps=$SourceGaps}
    $alignment | ConvertTo-Json -Depth 18 | Set-Content "$case\alignment-result.json" -Encoding UTF8
    $job=@{outputFolder=$case;speedWarningMinPercent=70;speedWarningMaxPercent=130;algorithm=@{useWhisperCache=$false;minNoDialogueGapSeconds=$Threshold};sequence=@{frameRate=$Fps;sequenceId='source-gap';name='source-gap';mainVideoClip=@{start=0;end=$MainEnd};voices=@(@{start=$VoiceStart;end=$VoiceEnd;path=$voice;speedPercent=100;inPoint=0});linkedAudio=@();voiceTrackIndex=1}}
    if($OmitThreshold){$job.algorithm.Remove('minNoDialogueGapSeconds')}
    $job | ConvertTo-Json -Depth 12 | Set-Content "$case\job.json" -Encoding UTF8
    & "$temp\engine\build-sentence-plan.ps1" -JobPath "$case\job.json" | Out-Null
    Get-Content "$case\sentence-edit-plan.json" -Raw -Encoding UTF8 | ConvertFrom-Json
}
try {
    Copy-Item -LiteralPath "$root\extension\engine\build-sentence-plan.ps1" -Destination "$temp\engine"
    Get-ChildItem "$root\extension\engine\lib" -File | Copy-Item -Destination "$temp\engine\lib"
    foreach($name in @('runtime-lock.json','cuda-lock.json')){Copy-Item -LiteralPath "$root\extension\engine\$name" -Destination "$temp\engine"}
    Set-Content "$temp\engine\runtime\engine.json" -Value '{"ffmpeg":"fixture"}' -Encoding ASCII
    $cues=@(
        [pscustomobject]@{Index=1;Text='First words without sentence punctuation,';Start=0.0;End=1.4;OriginalStart=0.0;OriginalEnd=1.0;Chapter=0;Confidence=1.0;WordTimings=@()},
        [pscustomobject]@{Index=2;Text='next words complete this sentence.';Start=1.6;End=3.0;OriginalStart=2.0;OriginalEnd=3.0;Chapter=0;Confidence=1.0;WordTimings=@()}
    )
    foreach($fps in @(30.0,(30000.0/1001))){
        $plan=Invoke-GapCase -Cues $cues -Fps $fps
        $gaps=@($plan.segments | Where-Object Kind -eq 'gap')
        if($gaps.Count -ne 1 -or $gaps[0].SourceStartFrame -ne [Math]::Round($fps) -or $gaps[0].SourceEndFrame -ne [Math]::Round(2*$fps) -or $gaps[0].OutputDurationFrames -ne $gaps[0].SourceDurationFrames){throw 'SOURCE_GAP_SWALLOWED_BEFORE_PUNCTUATION'}
        $final=Get-PvsSpeedMergeTrial $plan
        Assert-PvsTrialPlanConservation $plan $final | Out-Null
        if(@($final.visualSegments | Where-Object Kind -eq 'gap').Count -ne 1 -or ($final.captions.Text -join ' ') -cne ($cues.Text -join ' ')){throw 'SOURCE_GAP_OR_CAPTION_LOST_AFTER_SPEED_MERGE'}
    }
    # No safe voice cut: retain speech, but explicitly disclose the source gap.
    $pending=Invoke-GapCase -Cues $cues -Quiet ''
    if(@($pending.segments | Where-Object Kind -eq 'retime').Count -ne 1 -or @($pending.sourceGapReviewRanges).Count -ne 1){throw 'UNSAFE_GAP_NOT_REPORTED_FOR_REVIEW'}
    $below=Invoke-GapCase -Cues $cues -Threshold 1.1
    if(@($below.segments | Where-Object Kind -eq 'gap').Count -or @($below.sourceGapReviewRanges).Count){throw 'CUSTOM_GAP_THRESHOLD_IGNORED'}
    $exact=@($cues | ForEach-Object {$_.PSObject.Copy()});$exact[1].OriginalStart=1.5
    $atThreshold=Invoke-GapCase -Cues $exact
    if(@($atThreshold.segments | Where-Object Kind -eq 'gap').Count -ne 1){throw 'GAP_EQUAL_TO_CUSTOM_THRESHOLD_LOST'}
    $fallback=Invoke-GapCase -Cues $exact -OmitThreshold
    if($fallback.minNoDialogueGapSeconds -ne 0.5 -or @($fallback.segments | Where-Object Kind -eq 'gap').Count -ne 1){throw 'ENGINE_DEFAULT_GAP_NOT_HALF_SECOND'}

    # A compact raw DTW token supplies a measured sentence edge, without
    # manufacturing the three individual word timestamps in the reference.
    $texts=@('Phần lớn trong số đó là những loài có một không hai.','Úc một lục địa được biển bao quanh.')
    $refs=@([pscustomobject]@{Index=1;Text=$texts[0];Start=0;End=4},[pscustomobject]@{Index=2;Text=$texts[1];Start=8.16;End=12})
    $raw=[pscustomobject]@{segments=@([pscustomobject]@{text='Phần lớn trong số đó là những loài có 102.';start=0;end=1.5},[pscustomobject]@{text=$texts[1];start=1.7;end=3})}
    $words=@((Convert-PvsReferenceRecognition $raw 0).Words)
    foreach($w in $words){$w | Add-Member SubtitleTimingQuality 'dtw'}
    $voices=@([pscustomobject]@{start=10.0;end=13.0})
    $observed=@(Align-CuesToRecognizedWords $refs $words $voices)
    $recovered=@($observed | ForEach-Object {$_.PSObject.Copy()})
    $recovered[0].WordTimings=@($recovered[0].WordTimings | ForEach-Object {$_.PSObject.Copy()})
    $recovered[0].WordTimings[-1].SubtitleTimingQuality='estimated'
    $recovered[0] | Add-Member EditBoundaryReviewRequired $true
    Set-PvsSourceGapSpeechEvidence $recovered $observed $words $voices
    if(-not $recovered[0].PSObject.Properties['SourceGapEndEvidence'] -or -not $recovered[1].PSObject.Properties['SourceGapStartEvidence'] -or $recovered[0].WordTimings[-1].SubtitleTimingQuality -ne 'estimated'){throw 'COMPACT_RAW_EDGE_MISSING_OR_TIMING_PROMOTED'}
    $numeric=Invoke-GapCase -Cues $recovered -Quiet "silence_start: 1.5`nsilence_end: 1.7" -VoiceStart 10 -VoiceEnd 13 -MainEnd 12
    if(@($numeric.segments | Where-Object Kind -eq 'gap').Count -ne 1 -or ($numeric.captions.Text -join ' ') -cne ($texts -join ' ')){throw 'RECOVERED_SOURCE_GAP_NOT_PRESERVED'}
    foreach($fault in @('estimated','ambiguous','wrong-digits','invalid-time')){
        $badWords=@($words | ForEach-Object {$_.PSObject.Copy()});$badObserved=@($observed | ForEach-Object {$_.PSObject.Copy()});$badCues=@($recovered | ForEach-Object {$_.PSObject.Copy()})
        foreach($c in $badCues){$c.PSObject.Properties.Remove('SourceGapStartEvidence');$c.PSObject.Properties.Remove('SourceGapEndEvidence')}
        switch($fault){estimated {$badWords[9].SubtitleTimingQuality='estimated'};ambiguous {$badWords=@($badWords+$badWords)};'wrong-digits' {$badWords[9].Text='103'};'invalid-time' {$badWords[9].End=[double]::NaN}}
        Set-PvsSourceGapSpeechEvidence $badCues $badObserved $badWords $voices
        if($badCues[0].PSObject.Properties['SourceGapEndEvidence']){throw "UNSAFE_RAW_EDGE_ACCEPTED:$fault"}
    }
    $withoutProof=@($recovered | ForEach-Object {$_.PSObject.Copy()});foreach($c in $withoutProof){$c.PSObject.Properties.Remove('SourceGapStartEvidence');$c.PSObject.Properties.Remove('SourceGapEndEvidence')}
    $guarded=Invoke-GapCase -Cues $withoutProof -Quiet "silence_start: 1.5`nsilence_end: 1.7" -VoiceStart 10 -VoiceEnd 13 -MainEnd 12
    if(@($guarded.segments | Where-Object Kind -eq 'gap').Count -or @($guarded.sourceGapReviewRanges).Count -ne 1){throw 'RECOVERED_TEXT_ALONE_AUTHORIZED_CUT'}
    $manual=[pscustomobject]@{Index=1;Text=($texts -join ' ');Start=10.0;End=13.0;OriginalStart=0;OriginalEnd=12;Chapter=0;Confidence=0;WordTimings=@();ManualEditBlock=$true;EditBoundaryReviewRequired=$true;ManualReferenceCueIndices=@(1,2);ManualCaptionCues=@([pscustomobject]@{Text=$texts[0];Start=10.0;End=11.5;ReferenceCueIndices=@(1)},[pscustomobject]@{Text=$texts[1];Start=11.7;End=13.0;ReferenceCueIndices=@(2)})}
    $manualPlan=Invoke-GapCase -Cues @($manual) -Quiet "silence_start: 1.5`nsilence_end: 1.7" -VoiceStart 10 -VoiceEnd 13 -MainEnd 12 -SourceGaps @([pscustomobject]@{leftCue=1;rightCue=2;sourceStart=4;sourceEnd=8.16})
    if(@($manualPlan.segments | Where-Object Kind -eq 'retime').Count -ne 1 -or @($manualPlan.sourceGapReviewRanges).Count -ne 1){throw 'MANUAL_BLOCK_CUT_OR_INTERNAL_GAP_HIDDEN'}
    Write-Host 'SOURCE_DIALOGUE_GAPS_OK:pre-punctuation;custom-threshold;30-29.97fps;raw-DTW-edge-not-estimated-words;unsafe-review;speed-merge;final-SRT;negative-evidence'
} finally {
    $full=[IO.Path]::GetFullPath($temp)
    if(-not $full.StartsWith(([IO.Path]::GetFullPath($testRoot).TrimEnd('\')+'\'),[StringComparison]::OrdinalIgnoreCase)){throw 'UNSAFE_TEST_CLEANUP'}
    Remove-Item -LiteralPath $full -Recurse -Force
}
