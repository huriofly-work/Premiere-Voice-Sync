# Called after the baseline planner by default Auto edit or the legacy trial protocol.
Set-StrictMode -Version Latest

function Get-PvsTrialSentences {
    param([object[]]$Cues,[string]$EndCharacters='.?!;')
    $start=0
    for($i=0;$i -lt $Cues.Count;$i++){
        $text=([string]$Cues[$i].Text).Trim()
        $chapterEnd=$i -eq $Cues.Count-1 -or [int]$Cues[$i+1].Chapter -ne [int]$Cues[$i].Chapter
        if(-not $chapterEnd -and ($text.Length -eq 0 -or $EndCharacters.IndexOf($text[$text.Length-1]) -lt 0)){continue}
        $slice=@($Cues[$start..$i])
        [pscustomobject]@{Cues=$slice;First=$slice[0];Last=$slice[-1];Chapter=[int]$slice[0].Chapter;Confidence=[double](($slice | Measure-Object Confidence -Minimum).Minimum)}
        $start=$i+1
    }
}

function Test-PvsTrialCueEvidence {
    param($Cue,$Voice,[double]$MinimumExactRatio=0.85)
    if($Cue.PSObject.Properties['EditBoundaryReviewRequired'] -and $Cue.EditBoundaryReviewRequired){return $false}
    if(-not $Cue.PSObject.Properties['CaptionTimingRevision'] -or $Cue.CaptionTimingRevision -ne 'dtw-word-boundary-v1' -or -not $Cue.PSObject.Properties['CaptionWordTimings']){return $false}
    if($Cue.PSObject.Properties['AcousticTimingQuality'] -and $Cue.AcousticTimingQuality -ne 'dtw'){return $false}
    $tokens=@(ConvertTo-NormalizedWords $Cue.Text);$timings=@($Cue.CaptionWordTimings)
    if(-not $tokens.Count -or $tokens.Count -ne $timings.Count){return $false}
    $previous=[double]$Voice.start;$exact=0
    for($i=0;$i -lt $timings.Count;$i++){
        $t=$timings[$i]
        if([int]$t.TargetWordIndex -ne $i -or [int]$t.Chapter -ne [int]$Cue.Chapter -or [string]$t.Text -cne $tokens[$i]){return $false}
        foreach($value in @([double]$t.Start,[double]$t.End)){if([double]::IsNaN($value) -or [double]::IsInfinity($value)){return $false}}
        if($t.Start -lt $previous-0.000001 -or $t.End -le $t.Start -or $t.End -gt [double]$Voice.end+0.000001){return $false}
        if($t.Exact){$exact++};$previous=[double]$t.End
    }
    return $timings[0].Exact -and $timings[-1].Exact -and $exact/[double]$tokens.Count -ge $MinimumExactRatio
}

function Get-PvsDtwBoundaryTrial {
    param([object[]]$Cues,[object[]]$Voices,[object[]]$Silences,[double]$FrameRate,
        [scriptblock]$LegacyFinder,[double]$MinimumSilence=0.12,[double]$SearchRadius=0.12,
        [double]$SafetyMargin=0.04,[double]$MinimumLegacyConfidence=0.55,
        [double]$MinimumExactRatio=0.85,[double]$MinimumNoDialogueGap=0.5,[string]$EndCharacters='.?!;',[switch]$PreserveCuePictures)
    if($FrameRate -le 0 -or [double]::IsNaN($FrameRate) -or [double]::IsInfinity($FrameRate)){throw 'TRIAL_FRAME_RATE_INVALID'}
    $sentences=@(Get-PvsTrialSentences $Cues $EndCharacters)
    for($i=0;$i+1 -lt $sentences.Count;$i++){
        $left=$sentences[$i];$right=$sentences[$i+1];$chapter=$left.Chapter
        $row=[ordered]@{LeftCue=[int]$left.Last.Index;RightCue=[int]$right.First.Index;Chapter=$chapter;Status='';Reason='';OldCutFrame=$null;CutFrame=$null;QuietStart=$null;QuietEnd=$null;LeftSpeechEnd=$null;RightSpeechStart=$null;LeftText=[string]$left.Last.Text;RightText=[string]$right.First.Text}
        if($chapter -ne $right.Chapter){$row.Status='unchanged';$row.Reason='chapter-boundary';[pscustomobject]$row;continue}
        if($chapter -lt 0 -or $chapter -ge $Voices.Count){$row.Status='rejected';$row.Reason='chapter-invalid';[pscustomobject]$row;continue}
        $voice=$Voices[$chapter]
        if(@(@($left.Cues)+@($right.Cues) | Where-Object {$_.PSObject.Properties['EditBoundaryReviewRequired'] -and $_.EditBoundaryReviewRequired}).Count){$row.Status='rejected';$row.Reason='reference-text-recovery-review';[pscustomobject]$row;continue}
        if($left.Confidence -lt $MinimumLegacyConfidence -or $right.Confidence -lt $MinimumLegacyConfidence){$row.Status='rejected';$row.Reason='legacy-confidence-low';[pscustomobject]$row;continue}
        $old=& $LegacyFinder (($left.Last.End+$right.First.Start)/2.0) $Silences $MinimumSilence $SearchRadius $SafetyMargin $FrameRate
        if($old){$row.OldCutFrame=[int]$old.CutFrame;$row.Status='unchanged';$row.Reason='existing-safe-cut';[pscustomobject]$row;continue}
        # Require complete evidence in both sentences, not just a caption edge
        # or a display-padded timestamp. A sparse overlay is insufficient.
        $valid=$true
        foreach($cue in @($left.Cues)+@($right.Cues)){if(-not (Test-PvsTrialCueEvidence $cue $voice $MinimumExactRatio)){$valid=$false;break}}
        if(-not $valid){$row.Status='rejected';$row.Reason='speech-evidence-incomplete';[pscustomobject]$row;continue}
        $end=[double]$left.Last.CaptionWordTimings[-1].End;$start=[double]$right.First.CaptionWordTimings[0].Start
        $row.LeftSpeechEnd=$end;$row.RightSpeechStart=$start
        if($start -le $end){$row.Status='rejected';$row.Reason='no-separated-speech-edges';[pscustomobject]$row;continue}
        $midpoint=($end+$start)/2.0
        $candidates=@(foreach($quiet in $Silences){
            $a=[double]$quiet.Start;$b=[double]$quiet.End
            if($a -lt [double]$voice.start -or $b -gt [double]$voice.end -or $b-$a -lt $MinimumSilence-0.000001){continue}
            # Quiet must be supported by both speech edges, not merely near
            # their midpoint. Multiple possible intervals are rejected.
            if($a -lt $end-0.08 -or $b -gt $start+0.08){continue}
            $distance=if($midpoint -lt $a){$a-$midpoint}elseif($midpoint -gt $b){$midpoint-$b}else{0.0}
            if($distance -gt $SearchRadius){continue}
            $first=[int][Math]::Ceiling([Math]::Max($a+$SafetyMargin,$end)*$FrameRate-0.0000001)
            $last=[int][Math]::Floor([Math]::Min($b-$SafetyMargin,$start)*$FrameRate+0.0000001)
            if($first -gt $last){continue}
            $cut=[Math]::Max($first,[Math]::Min($last,[int][Math]::Round(($a+$b)/2.0*$FrameRate)))
            [pscustomobject]@{CutFrame=$cut;Start=$a;End=$b}
        })
        if($candidates.Count -ne 1){$row.Status='rejected';$row.Reason=if($candidates.Count){'quiet-ambiguous'}else{'no-guarded-quiet'};[pscustomobject]$row;continue}
        $candidate=$candidates[0];$cut=[double]$candidate.CutFrame/$FrameRate
        if($cut -le [double]$left.Last.Start -or $cut -ge [double]$right.First.End){$row.Status='rejected';$row.Reason='cue-would-collapse';[pscustomobject]$row;continue}
        if([double]$right.First.OriginalStart-[double]$left.Last.OriginalEnd -ge $MinimumNoDialogueGap){$row.Status='rejected';$row.Reason='would-add-dialogue-gap';[pscustomobject]$row;continue}
        $row.Status='candidate';$row.Reason='new-guarded-quiet';$row.CutFrame=[int]$candidate.CutFrame;$row.QuietStart=$candidate.Start;$row.QuietEnd=$candidate.End
        # Picture cues already have their measured mapping independently of
        # A2. Extra physical-voice cuts add no picture precision and would
        # reparent/move the protected picture anchors during a second plan.
        if($PreserveCuePictures){$row.Status='unchanged';$row.Reason='cue-picture-anchors-already-planned'}
        [pscustomobject]$row
    }
}

function ConvertTo-PvsTrialAlignment {
    param($Alignment,[object[]]$Boundaries,[double]$FrameRate)
    $copy=$Alignment | ConvertTo-Json -Depth 20 | ConvertFrom-Json
    $byIndex=@{};foreach($cue in $copy.cues){$byIndex[[int]$cue.Index]=$cue}
    foreach($row in @($Boundaries | Where-Object Status -eq 'candidate')){
        $a=$byIndex[[int]$row.LeftCue];$b=$byIndex[[int]$row.RightCue];$cut=[double]$row.CutFrame/$FrameRate
        if($a.Chapter -ne $b.Chapter -or $cut -le $a.Start -or $cut -ge $b.End){throw 'TRIAL_BOUNDARY_INVALID'}
        $a.End=$cut;$b.Start=$cut
    }
    return $copy
}

function Assert-PvsTrialPlanConservation {
    param($Baseline,$Candidate)
    foreach($field in @('editedSourceMap','omittedReferenceCueIndices','manualReviewBlocks','manualReviewStatus','sourceGapReviewRanges','sourceGapBoundaries','pictureCueRevision','pictureCueBoundaries','pictureSegments','pictureCueSummary','manualCaptionTimingRevision','acousticEditBoundaryRevision','acousticEditBoundaryProofs','acousticEditReferenceCues','acousticEditQuiet')){
        if([bool]$Baseline.PSObject.Properties[$field] -ne [bool]$Candidate.PSObject.Properties[$field]){throw "TRIAL_PROTECTED_PLAN_FIELD_CHANGED:$field"}
    }
    foreach($plan in @($Baseline,$Candidate)){
        $previous=[int]$plan.segments[0].SourceStartFrame;$timeline=0
        foreach($segment in $plan.segments){
            if([int]$segment.SourceStartFrame -ne $previous -or $segment.SourceEndFrame -le $segment.SourceStartFrame){throw 'TRIAL_SOURCE_GAP_OR_OVERLAP'}
            if([int]$segment.NewStartFrame -ne $timeline -or $segment.NewEndFrame -le $segment.NewStartFrame){throw 'TRIAL_TIMELINE_GAP_OR_OVERLAP'}
            $previous=[int]$segment.SourceEndFrame;$timeline=[int]$segment.NewEndFrame
        }
        if($previous -ne $plan.mainVideoSourceEndFrame){throw 'TRIAL_SOURCE_TAIL_LOST'}
        $end=0.0
        foreach($caption in $plan.captions){if($caption.End -le $caption.Start -or $caption.Start -lt $end-0.000001 -or $caption.End -gt $plan.plannedMainVideoEnd+0.000001){throw 'TRIAL_CAPTION_RANGE_INVALID'};$end=$caption.End}
    }
    if($Baseline.frameRate -ne $Candidate.frameRate -or $Baseline.mainVideoSourceEndFrame -ne $Candidate.mainVideoSourceEndFrame -or $Baseline.segments[0].SourceStartFrame -ne $Candidate.segments[0].SourceStartFrame){throw 'TRIAL_SOURCE_COVERAGE_CHANGED'}
    if(($Baseline.captions.Text -join ' ') -cne ($Candidate.captions.Text -join ' ')){throw 'TRIAL_CAPTION_TEXT_CHANGED'}
    $before=@($Baseline.segments | Where-Object Kind -eq 'retime');$after=@($Candidate.segments | Where-Object Kind -eq 'retime')
    foreach($chapter in @($before.Chapter | Select-Object -Unique)){
        $a=@($before | Where-Object Chapter -eq $chapter);$b=@($after | Where-Object Chapter -eq $chapter)
        if(-not $b.Count -or $a[0].OriginalVoiceStartFrame -ne $b[0].OriginalVoiceStartFrame -or $a[-1].OriginalVoiceEndFrame -ne $b[-1].OriginalVoiceEndFrame){throw 'TRIAL_VOICE_EDGE_CHANGED'}
        foreach($items in @(@{Items=$a},@{Items=$b})){
            $edge=[int]$items.Items[0].OriginalVoiceStartFrame
            foreach($segment in $items.Items){if($segment.OriginalVoiceStartFrame -ne $edge -or $segment.OriginalVoiceEndFrame -le $edge){throw 'TRIAL_VOICE_LOST_OR_DUPLICATED'};$edge=[int]$segment.OriginalVoiceEndFrame}
        }
    }
    if((@($before.Chapter | Select-Object -Unique) -join ',') -cne (@($after.Chapter | Select-Object -Unique) -join ',')){throw 'TRIAL_VOICE_CHAPTER_CHANGED'}
    $a=@($Baseline.segments | Where-Object Kind -eq 'gap' | Select-Object SourceStartFrame,SourceEndFrame)
    $b=@($Candidate.segments | Where-Object Kind -eq 'gap' | Select-Object SourceStartFrame,SourceEndFrame)
    if(($a | ConvertTo-Json -Compress) -cne ($b | ConvertTo-Json -Compress)){throw 'TRIAL_ADDED_OR_CHANGED_PAUSE'}
    if($Baseline.plannedMainVideoEndFrame -ne $Candidate.plannedMainVideoEndFrame){throw 'TRIAL_TOTAL_DURATION_CHANGED'}
    foreach($field in @('sequenceId','mainVideoClip','linkedAudio','voiceTrackIndex','voiceClips','settings','speedWarningMinPercent','speedWarningMaxPercent','speedThresholdMode','minNoDialogueGapSeconds','editedSourceMap','omittedReferenceCueIndices','manualReviewBlocks','manualReviewStatus','referenceCueCount','sourceGapReviewRanges','sourceGapBoundaries','pictureCueRevision','pictureCueBoundaries','pictureSegments','pictureCueSummary','manualCaptionTimingRevision','acousticEditBoundaryRevision','acousticEditBoundaryProofs','acousticEditReferenceCues','acousticEditQuiet')){
        if($Baseline.PSObject.Properties[$field] -and (($Baseline.$field | ConvertTo-Json -Depth 20 -Compress) -cne ($Candidate.$field | ConvertTo-Json -Depth 20 -Compress))){throw "TRIAL_PROTECTED_PLAN_FIELD_CHANGED:$field"}
    }
    return $true
}

function Assert-PvsDtwTrialInput {
    param($Job)
    if(-not $Job.PSObject.Properties['editBoundaryTrial'] -or $Job.editBoundaryTrial -cne 'dtw-additive-v1' -or $Job.workflow -cnotin @('experimental-dtw-direct','one-click-dtw-direct')){throw 'TRIAL_EXPLICIT_OPT_IN_REQUIRED'}
    $fps=[double]$Job.sequence.frameRate
    if([double]::IsNaN($fps) -or [double]::IsInfinity($fps) -or $fps -lt 1 -or $fps -gt 240){throw 'TRIAL_FRAME_RATE_INVALID'}
    $gap=2.0
    if($Job.PSObject.Properties['algorithm'] -and $Job.algorithm.PSObject.Properties['voiceGroupGapSeconds']){$gap=[double]$Job.algorithm.voiceGroupGapSeconds}
    if([double]::IsNaN($gap) -or [double]::IsInfinity($gap) -or $gap -lt 0.2 -or $gap -gt 20){throw 'TRIAL_GROUP_GAP_INVALID'}
    $voices=@($Job.sequence.voices | Sort-Object start)
    if(-not $voices.Count){throw 'TRIAL_VOICE_MISSING'}
    for($i=0;$i -lt $voices.Count;$i++){
        if($i -gt 0 -and [double]$voices[$i].start-[double]$voices[$i-1].end -gt $gap){break}
        $voice=$voices[$i]
        if(-not $voice.PSObject.Properties['inPoint'] -or $null -eq $voice.inPoint -or -not $voice.PSObject.Properties['speedPercent'] -or $null -eq $voice.speedPercent){throw "TRIAL_VOICE_METADATA_REQUIRED:chapter-$($i+1)"}
        $inPoint=[double]$voice.inPoint;$speed=[double]$voice.speedPercent
        if([double]::IsNaN($inPoint) -or [double]::IsInfinity($inPoint) -or [double]::IsNaN($speed) -or [double]::IsInfinity($speed) -or $speed -lt 1){throw "TRIAL_VOICE_METADATA_INVALID:chapter-$($i+1)"}
        # DTW words, legacy words and source-file quiet intervals already use
        # 100/speed. Preserve that scale; do not normalize the voice to 100%.
        # A nonzero media In is different: existing recognition does not
        # subtract it, so it remains unsupported by this opt-in trial.
        if([Math]::Abs($inPoint) -gt 0.000001){throw ('TRIAL_VOICE_MEDIA_IN_NONZERO:chapter-{0};inPointSeconds={1};speedPercent={2}' -f ($i+1),$inPoint.ToString('R',[Globalization.CultureInfo]::InvariantCulture),$speed.ToString('R',[Globalization.CultureInfo]::InvariantCulture))}
    }
}

function Assert-PvsDtwTrialJob {
    param($Job,$Baseline)
    Assert-PvsDtwTrialInput $Job
    if(-not $Baseline.ok -or $Baseline.schemaVersion -ne 8 -or $Baseline.plannerRevision -ne 18){throw 'TRIAL_STABLE_PLAN_REQUIRED'}
    if(-not $Job.sequence.sequenceId -or $Baseline.sequenceId -cne $Job.sequence.sequenceId -or -not $Job.sequence.mainVideoClip.nodeId -or -not @($Job.sequence.linkedAudio).Count){throw 'TRIAL_LIVE_TEMPLATE_REQUIRED'}
    if(($Baseline.mainVideoClip | ConvertTo-Json -Depth 12 -Compress) -cne ($Job.sequence.mainVideoClip | ConvertTo-Json -Depth 12 -Compress) -or ($Baseline.linkedAudio | ConvertTo-Json -Depth 12 -Compress) -cne ($Job.sequence.linkedAudio | ConvertTo-Json -Depth 12 -Compress) -or $Baseline.frameRate -ne $Job.sequence.frameRate){throw 'TRIAL_BASELINE_JOB_MISMATCH'}
    $jobVoices=@($Job.sequence.voices | Sort-Object start | Select-Object -First @($Baseline.voiceClips).Count)
    if(($Baseline.voiceClips | ConvertTo-Json -Depth 12 -Compress) -cne ($jobVoices | ConvertTo-Json -Depth 12 -Compress)){throw 'TRIAL_BASELINE_VOICES_MISMATCH'}
}

function Assert-PvsDtwTrialCuts {
    param($Baseline,$Candidate,[object[]]$Rows)
    Assert-PvsTrialPlanConservation $Baseline $Candidate | Out-Null
    $old=@($Baseline.segments | Where-Object Kind -eq 'retime')
    $new=@($Candidate.segments | Where-Object Kind -eq 'retime')
    foreach($segment in $old){
        $matches=@($new | Where-Object { $_.Chapter -eq $segment.Chapter -and $_.OriginalVoiceEndFrame -eq $segment.OriginalVoiceEndFrame -and $_.SourceEndFrame -eq $segment.SourceEndFrame -and $_.LastTargetCue -eq $segment.LastTargetCue })
        if($matches.Count -ne 1){throw 'TRIAL_EXISTING_CUT_MOVED'}
    }
    $added=@($Rows | Where-Object Status -eq 'candidate')
    foreach($row in $added){
        $matches=@($new | Where-Object { $_.Chapter -eq $row.Chapter -and $_.OriginalVoiceEndFrame -eq $row.CutFrame -and $_.LastTargetCue -eq $row.LeftCue })
        if($matches.Count -ne 1){throw 'TRIAL_CANDIDATE_CUT_NOT_USED'}
    }
    if($new.Count -ne $old.Count+$added.Count){throw 'TRIAL_UNEXPECTED_CUT_COUNT'}
}
