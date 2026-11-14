$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$root=Resolve-Path (Join-Path $PSScriptRoot '..\..')
. "$root\extension\engine\lib\Srt.ps1"
. "$root\extension\engine\lib\Alignment.ps1"
. "$root\extension\engine\lib\CaptionOnly.ps1"
. "$root\extension\engine\lib\SubtitleTiming.ps1"
$windows=@(Get-PvsSubtitleContextPlan 10 55 0 60 @())
if($windows.Count -ne 3 -or $windows[0].ReadStart -ne 7.5 -or $windows[-1].ReadEnd -ne 57.5){throw 'CONTEXT_NOT_PADDED_OR_BOUNDED'}
foreach($w in $windows){if($w.ReadEnd-$w.ReadStart -gt 25.000001 -or $w.End -le $w.Start){throw 'CONTEXT_WINDOW_TOO_LARGE'}}
$edge=@(Get-PvsSubtitleContextPlan 0 1 0 2 @())
if($edge[0].ReadStart -ne 0 -or $edge[0].ReadEnd -ne 2){throw 'CONTEXT_ESCAPED_SOURCE'}
$paused=@(Get-PvsSubtitleContextPlan 0 40 0 40 @([pscustomobject]@{Start=16;End=17;Duration=1}))
if($paused[0].End -ne 16.5){throw 'CONTEXT_IGNORED_MEASURED_PAUSE'}
$json=[pscustomobject]@{transcription=@([pscustomobject]@{text='left alpha beta right.';offsets=[pscustomobject]@{from=0;to=4000}})}
$recognition=Convert-PvsSubtitleRecognition $json 0 4
foreach($w in $recognition.Words){$w | Add-Member NoteProperty SubtitleTimingQuality 'estimated';$w | Add-Member NoteProperty SubtitleTimingOrigin 'test-origin'}
$crop=Select-PvsSubtitleRecognitionWindow $recognition 1 3
if(($crop.Words.Text -join ' ') -cne 'alpha beta' -or $crop.Words[0].Start -ne 0 -or $crop.Words[-1].End -ne 2 -or $crop.Surfaces[0].Text -cne 'alpha beta' -or $crop.Words[0].SubtitleTimingQuality -ne 'estimated'){throw 'CONTEXT_CROP_LOST_TEXT_OFFSET_OR_QUALITY'}
$boundaryRecognition=Convert-PvsSubtitleRecognition ([pscustomobject]@{transcription=@([pscustomobject]@{text='left alpha bravo charlie new speech right delta echo foxtrot';offsets=[pscustomobject]@{from=0;to=10000}})}) 0 10
$inside=Get-PvsSubtitleContextInterior $boundaryRecognition 3.5 6.5 'left alpha bravo charlie' 'right delta echo foxtrot'
if($inside.Start -ne 4 -or $inside.End -ne 6){throw 'NEIGHBOR_CONTEXT_WOULD_BE_DUPLICATED'}
$repeatRecognition=Convert-PvsSubtitleRecognition ([pscustomobject]@{transcription=@([pscustomobject]@{text='right delta echo foxtrot new speech right delta echo foxtrot';offsets=[pscustomobject]@{from=0;to=10000}})}) 0 10
$inside=Get-PvsSubtitleContextInterior $repeatRecognition 3.5 6.5 '' 'right delta echo foxtrot'
if($inside.End -ne 6.5){throw 'AMBIGUOUS_REPETITION_WAS_TRIMMED'}
$tailRecognition=Convert-PvsSubtitleRecognition ([pscustomobject]@{transcription=@([pscustomobject]@{text='chúng ta vẫn chưa có lời dài';offsets=[pscustomobject]@{from=0;to=3000}})}) 0 3
$inside=Get-PvsSubtitleContextInterior $tailRecognition 2.8 3.2 'chúng ta vẫn chưa có lời giải' ''
if(-not $inside.LeftMatched -or $inside.Start -ne 3){throw 'RETAINED_SRT_TAIL_SUBSTITUTION_DUPLICATED_AS_NEW_SPEECH'}
$tailRecognition.Words[2].Text='khác'
if((Get-PvsSubtitleContextInterior $tailRecognition 2.8 3.2 'chúng ta vẫn chưa có lời giải' '').LeftMatched){throw 'MULTIPLE_UNRELATED_SUBSTITUTIONS_TRIMMED_AS_CONTEXT'}
$tailRecognition=Convert-PvsSubtitleRecognition ([pscustomobject]@{transcription=@([pscustomobject]@{text='chúng ta vẫn chưa có lời dài chúng ta vẫn chưa có lời dài';offsets=[pscustomobject]@{from=0;to=6000}})}) 0 6
if((Get-PvsSubtitleContextInterior $tailRecognition 2.8 3.2 'chúng ta vẫn chưa có lời giải' '').LeftMatched){throw 'REPEATED_SUBSTITUTED_CONTEXT_WAS_TRIMMED'}
function New-Energy([double]$Duration,[double]$Amplitude){[pscustomobject]@{Rms=[double[]]@(for($i=0;$i -lt [int]($Duration/0.005);$i++){$Amplitude})}}
$quietEnergy=New-Energy 4 0
$loudEnergy=New-Energy 4 0.1
$silent=Select-PvsSupportedSubtitleRecognition $recognition $quietEnergy
if($silent.Words.Count -or $silent.RejectedRanges.Count -ne 1){throw 'SILENCE_HALLUCINATION_ACCEPTED'}
$genuine=Select-PvsSupportedSubtitleRecognition $recognition $loudEnergy
if($genuine.Words.Count -ne 4 -or $genuine.RejectedRanges.Count){throw 'GENUINE_SPEECH_REJECTED'}
$cta=Convert-PvsSubtitleRecognition ([pscustomobject]@{transcription=@([pscustomobject]@{text='Subscribe to the channel for more videos.';offsets=[pscustomobject]@{from=0;to=3000}})}) 0 4
if((Select-PvsSupportedSubtitleRecognition $cta $loudEnergy).Words.Count -ne $cta.Words.Count){throw 'REAL_CTA_BLACKLISTED'}
$dense=Convert-PvsSubtitleRecognition ([pscustomobject]@{transcription=@([pscustomobject]@{text='Subscribe to the channel for more videos.';offsets=[pscustomobject]@{from=0;to=150}})}) 0 4
if((Select-PvsSupportedSubtitleRecognition $dense $loudEnergy).Words.Count){throw 'COMPRESSED_HALLUCINATION_ACCEPTED'}
$quiet=@([pscustomobject]@{Start=1;End=1.4;Duration=0.4})
if(-not (Test-PvsSubtitleQuietGap 1 1.4 $quiet) -or (Test-PvsSubtitleQuietGap 1 3 $quiet) -or (Test-PvsSubtitleQuietGap 0.8 1.4 $quiet)){throw 'QUIET_CLASSIFICATION_TOO_BROAD'}
$selection=[pscustomobject]@{Cues=@([pscustomobject]@{Index=1;Text='left';Start=0;End=1;Chapter=0},[pscustomobject]@{Index=3;Text='right';Start=1.4;End=2;Chapter=0});UnverifiedRanges=@([pscustomobject]@{sourceIndex=0;start=1;end=1.4;cueIndices=@(2)})}
$completed=Complete-PvsSubtitleReference $selection @() @([pscustomobject]@{start=0;end=2}) {throw 'MEASURED_BREATH_TRIGGERED_ASR'} -TestQuietWindow {param($source,$start,$end);Test-PvsSubtitleQuietGap $start $end $quiet}
if($completed.QuietRanges.Count -ne 1 -or $completed.EmptyRanges.Count -or $completed.Cues.Count -ne 2){throw 'BREATH_REPORTED_AS_MISSING_SUBTITLE'}
# Keep content omission proof unchanged while preserving timing evidence.
$cues=@(for($i=0;$i -lt 3;$i++){[pscustomobject]@{Index=$i+1;Start=$i*3;End=($i+1)*3;Text=((0..5 | ForEach-Object {"token$($i*6+$_)"}) -join ' ')}})
$all=@(for($i=0;$i -lt 18;$i++){[pscustomobject]@{Text="token$i";Start=$i*0.1;End=($i+1)*0.1;Chapter=0;SubtitleTimingQuality='estimated';SubtitleTimingOrigin='test-origin';DtwFirst=$i*0.1;DtwLast=($i+1)*0.1;DtwBoundaryStart=$i*0.1}})
$sources=@([pscustomobject]@{start=10.0;end=11.8})
$resolved=Resolve-PvsEditedReference $cues @($all[0..5]+$all[12..17]) $sources {param($source,$start,$end);$all}
if(-not $resolved.Resolved -or @($resolved.Words | Where-Object SubtitleTimingQuality -eq 'estimated').Count -ne 18 -or (Test-PvsSubtitleDtwCue $resolved.Cues[1] @{})){throw 'RECOVERED_ESTIMATES_PROMOTED_TO_DTW'}
if($resolved.Cues[1].WordTimings[0].SubtitleTimingOrigin -cne 'test-origin'){throw 'PROJECTED_WORD_LOST_ORIGIN'}
$overlayReview=@(Set-PvsDtwCaptionOverlay $resolved.Cues $resolved.Cues 42 @())
if($overlayReview.Count -ne 3 -or @($resolved.Cues | Where-Object {$_.PSObject.Properties['CaptionTimingRevision']}).Count){throw 'OVERLAY_PROMOTED_ESTIMATED_WORDS'}
$retryCue=$resolved.Cues[1].PSObject.Copy();$retryCue.WordTimings=@()
$edgeRetry=Repair-PvsDtwCaptionEdges @($retryCue) @() 11.8 {param($start,$end,$text,$chapter);$all} $sources 42
if($edgeRetry.Refined.Count -or ($edgeRetry.Unverified -join ',') -ne '2'){throw 'EDGE_RETRY_PROMOTED_ESTIMATED_WORDS'}
$numCue=[pscustomobject]@{Index=1;Text='alpha 100 bravo';Start=10.0;End=11.0;Chapter=0;WordTimings=@()}
$numWords=@(for($i=0;$i -lt 3;$i++){[pscustomobject]@{Text=@('alpha','100','bravo')[$i];Start=$i*0.2;End=($i+1)*0.2;Chapter=0;SubtitleTimingQuality='estimated';SubtitleTimingOrigin='numeric-attempt'}})
$numeric=Repair-PvsNumericCaptionTimings @($numCue) @([pscustomobject]@{start=10;end=12}) {param($voice,$start,$end,$prompt);$numWords}
if($numeric.Refined.Count -ne 1 -or $numCue.CaptionWordTimings[1].SubtitleTimingQuality -ne 'estimated' -or $numCue.CaptionWordTimings[1].SubtitleTimingOrigin -ne 'numeric-attempt'){throw 'NUMERIC_RETRY_LOST_TIMING_QUALITY'}
$spokenWords=@(for($i=0;$i -lt 4;$i++){[pscustomobject]@{Text=@('alpha','một','trăm','bravo')[$i];Start=$i*0.2;End=($i+1)*0.2;Chapter=0;SubtitleTimingQuality='estimated';SubtitleTimingOrigin='numeric-attempt'}})
$joined=@(Join-PvsRecognizedNumericWords @('alpha','100','bravo') $spokenWords)
if($joined.Count -ne 3 -or $joined[1].Text -ne '100' -or $joined[1].SubtitleTimingQuality -ne 'estimated'){throw 'NUMERIC_JOIN_LOST_TIMING_QUALITY'}
$range=@([pscustomobject]@{sourceIndex=0;start=10;end=12;origin='test-origin';reason='estimated'},[pscustomobject]@{sourceIndex=0;start=10;end=12;origin='discarded-attempt';reason='estimated'})
$used=@(Get-PvsUsedSubtitleEstimatedRanges $resolved.Cues $range)
if($used.Count -ne 1 -or $used[0].end -ne 11.8){throw 'UNUSED_ATTEMPT_BECAME_REVIEW_MARKER'}
$blocked=@([pscustomobject]@{sourceIndex=0;start=0;end=2;reason='rejected'})
$remaining=@(Get-PvsUncoveredSubtitleRecognitionRanges $blocked @([pscustomobject]@{Start=0;End=1}) @() 30)
if($remaining.Count -ne 1 -or $remaining[0].start -ne 1 -or $remaining[0].end -ne 2){throw 'RESOLVED_REJECTION_STILL_MARKED'}
# Equivalent Roman level is formatting; a different actual level is content.
foreach($heardLevel in @('2','3')){
    $ref=@([pscustomobject]@{Index=1;Text='alpha cấp độ ii bravo charlie';Start=900;End=901})
    $texts=@('alpha','cấp','độ',$heardLevel,'bravo','charlie')
    $heard=@(for($i=0;$i -lt $texts.Count;$i++){[pscustomobject]@{Text=$texts[$i];Start=$i*0.2;End=($i+1)*0.2;Chapter=0}})
    $aligned=@(Align-CuesToRecognizedWords $ref $heard @([pscustomobject]@{start=0;end=2}))
    $ok=Test-PvsSubtitlePartialReferenceCue $aligned[0] $heard @([pscustomobject]@{start=0;end=2})
    if($heardLevel -eq '2'){
        if(-not $ok -or -not $aligned[0].SubtitleReferenceFormatOnly){throw 'EQUIVALENT_ROMAN_LEVEL_NOT_RECOGNIZED'}
        Set-PvsSubtitlePartialReferenceReview $aligned[0]
        if($aligned[0].ReferenceReviewRequired){throw 'FORMATTING_FLAGGED_AS_CONTENT_ERROR'}
    }elseif($aligned[0].PSObject.Properties['SubtitleReferenceFormatOnly']){throw 'DIFFERENT_LEVEL_LABELLED_FORMATTING'}
}
# Decimal punctuation is evidence only when the raw numeric surface survives.
$ref=@([pscustomobject]@{Index=1;Text='alpha 13 phẩy 8 bravo charlie';Start=900;End=901})
$heard=@(for($i=0;$i -lt 5;$i++){$w=[pscustomobject]@{Text=@('alpha','13','8','bravo','charlie')[$i];Start=$i*0.2;End=($i+1)*0.2;Chapter=0};if($i -in @(1,2)){$w | Add-Member NoteProperty NumericSurfaceText '13,8'};$w})
$aligned=@(Align-CuesToRecognizedWords $ref $heard @([pscustomobject]@{start=0;end=2}))
if(-not (Test-PvsSubtitlePartialReferenceCue $aligned[0] $heard @([pscustomobject]@{start=0;end=2})) -or $aligned[0].WordTimings.Count -ne 5){throw 'DECIMAL_SRT_LOST_OR_FAKE_TIMESTAMP_CREATED'}
foreach($w in $heard){if($w.PSObject.Properties['NumericSurfaceText']){$w.NumericSurfaceText='13,9'}}
$aligned=@(Align-CuesToRecognizedWords $ref $heard @([pscustomobject]@{start=0;end=2}))
if(-not (Test-PvsSubtitlePartialReferenceCue $aligned[0] $heard @([pscustomobject]@{start=0;end=2})) -or -not $aligned[0].ReferenceNumberReviewRequired -or $aligned[0].ReferenceNumberRecognized -cne '13,9'){throw 'DIFFERENT_DECIMAL_NOT_KEPT_WITH_CONTENT_COMPARISON'}
foreach($w in $heard){if($w.PSObject.Properties['NumericSurfaceText']){$w.NumericSurfaceText='13,8'}}
$decimalInteger=@(Join-PvsRecognizedNumericWords @('alpha','138','bravo','charlie') $heard)
if(@($decimalInteger | Where-Object Text -eq '138').Count){throw 'DECIMAL_SURFACE_JOINED_AS_DIFFERENT_INTEGER'}
$longCues=@(for($i=0;$i -lt 3;$i++){[pscustomobject]@{Index=$i+1;Start=$i*30;End=($i+1)*30;Text=((0..9 | ForEach-Object {"long$($i*10+$_)"}) -join ' ')}})
$longWords=@(for($i=0;$i -lt 30;$i++){if($i -ne 15){[pscustomobject]@{Text="long$i";Start=$i*4.0;End=($i+1)*4.0;Chapter=0}}})
$long=Select-PvsSubtitleReference $longCues $longWords @([pscustomobject]@{start=0;end=120}) -AllowEditedReference -AllowUnmatchedRanges -SkipUnverifiedCues -RecognizeReferenceWindow {throw 'LONG_PROJECTION_TRIGGERED_UNBOUNDED_ASR'}
if(($long.Cues.Index -join ',') -ne '1,2,3' -or ($long.PartialReferenceCueIndices -join ',') -ne '2' -or $long.EditedReference.Resolved){throw 'LONG_BLOCK_DISCARDED_GOOD_REFERENCE_OR_CHANGED_OMISSION_PROOF'}
Write-Host 'SUBTITLE_RECOGNITION_SAFETY_OK:bounded-context;crop;real-CTA;silence;compressed-text;quiet-review;quality-origin;estimated-not-DTW;used-attempts;Roman;decimal'
