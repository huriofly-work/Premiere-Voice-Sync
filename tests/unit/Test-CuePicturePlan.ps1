$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$root=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
. "$root\extension\engine\lib\CaptionOnly.ps1"
. "$root\extension\engine\lib\CaptionTiming.ps1"
function Check([bool]$Value,[string]$Message){if(-not $Value){throw "CUE_PICTURE_TEST_FAILED:$Message"}}
function Clone($Value){$copy=ConvertFrom-Json (ConvertTo-Json -InputObject $Value -Depth 30);foreach($item in $copy){$item}}
$refs=@();$words=@();$quiet=@()
for($i=0;$i -lt 3;$i++){
    $tokens=@(0..9|ForEach-Object {"cue$($i)word$_"})
    # Touching SRT cues without terminal punctuation must remain separate.
    $refs+=[pscustomobject]@{Index=$i+1;Start=$i*4.0;End=($i+1)*4.0;Text=($tokens -join ' ')+','}
    for($w=0;$w -lt 10;$w++){$words+=[pscustomobject]@{Text=$tokens[$w];Start=$i*4+0.2+$w*0.25;End=$i*4+0.4+$w*0.25;Chapter=0;SubtitleTimingQuality='dtw'}}
    if($i -lt 2){$quiet+=[pscustomobject]@{Start=$i*4+2.8;End=$i*4+4.1;Duration=1.3}}
}
$voices=@([pscustomobject]@{start=0.0;end=12.0;inPoint=0;speedPercent=100;path='';name='fixture'})
$heard=Clone $words;$heard[7].Text='substituted'
$evidence=@(Get-PvsReferenceCueEvidence $refs $heard @() $voices)
Check ($evidence.Count -eq 3) 'complete-cue-90-percent-exact-preserves-dtw-edges'
Check (-not @((Get-PvsAcousticReferenceCuts $refs $heard $voices $quiet 30)|Where-Object leftCue -eq 1).Count) 'old-eight-word-context-cannot-resolve-reproduction'
$cuts=@(Get-PvsWholeCueQuietCuts $evidence $heard $voices $quiet 30 @())
Check ($cuts.Count -eq 2) 'whole-cue-reuses-measured-dtw-and-quiet'
foreach($cut in $cuts){Check (Test-PvsAcousticReferenceCut $cut $refs $voices $quiet 30) 'whole-cue-proof-roundtrip'}
foreach($fault in @('estimated','edge-word','different-chapter','trimmed','duplicate')){
    $w=Clone $heard;$v=Clone $voices;$r=Clone $refs
    switch($fault){
        estimated {$w[2].SubtitleTimingQuality='estimated'}
        edge-word {$w[0].Text='wrong'}
        different-chapter {$w[2].Chapter=1}
        trimmed {$v[0].inPoint=1}
        duplicate {$r[2].Text=$r[0].Text}
    }
    Check (-not @((Get-PvsReferenceCueEvidence $r $w @() $v)|Where-Object Index -eq 1).Count) "whole-cue-rejects-$fault"
}
Check (-not @(Get-PvsWholeCueQuietCuts $evidence $heard $voices @() 30 @()).Count) 'no-quiet-never-cuts-voice'
$extra=[pscustomobject]@{Text='extra';Start=3.1;End=3.4;Chapter=0;SubtitleTimingQuality='dtw'}
Check (-not @((Get-PvsWholeCueQuietCuts $evidence (@($heard)+@($extra)) $voices $quiet 30 @())|Where-Object leftCue -eq 1).Count) 'extra-speech-prevents-new-voice-cut'
$parent=[pscustomobject]@{Kind='retime';Unit='sentence';Chapter=0;SourceStartFrame=0;SourceEndFrame=360;NewStartFrame=0;NewEndFrame=360;SourceDurationFrames=360;EffectiveSourceDurationFrames=360;OutputDurationFrames=360;VisualDurationFrames=360;SourceStart=0.0;SourceEnd=12.0;NewStart=0.0;NewEnd=12.0;SourceDuration=12.0;EffectiveSourceDuration=12.0;OutputDuration=12.0;AppliedSpeedPercent=100.0;DesiredSpeedPercent=100.0;SpeedOutsideWarningRange=$false;OriginalVoiceStartFrame=0;OriginalVoiceEndFrame=360;NewVoiceStartFrame=0;NewVoiceEndFrame=360;FirstTargetCue=1;LastTargetCue=3}
$plan=[pscustomobject]@{frameRate=30;segments=@($parent);minNoDialogueGapSeconds=0.5;speedWarningMinPercent=70;speedWarningMaxPercent=130}
$voiceBefore=$plan.segments|ConvertTo-Json -Depth 10 -Compress
Add-PvsCuePicturePlan $plan $refs $evidence
Check ($plan.pictureSegments.Count -eq 3 -and $plan.pictureCueBoundaries.Count -eq 2) 'per-srt-cue-picture-with-continuous-voice-and-no-quiet-required'
Check (($plan.segments|ConvertTo-Json -Depth 10 -Compress) -ceq $voiceBefore) 'a2-plan-byte-identical'
Check ($plan.pictureSegments[0].SourceEndFrame -eq 120 -and $plan.pictureSegments[1].SourceEndFrame -eq 240 -and $plan.pictureSegments[-1].SourceEndFrame -eq 360) 'source-cues-and-tail-complete'
Check ($plan.pictureSegments[0].NewEndFrame -eq [Math]::Round(($evidence[0].CaptionWordTimings[-1].End+$evidence[1].CaptionWordTimings[0].Start)*15)) 'picture-cut-at-measured-word-boundary'
$edgePlan=Clone $plan;foreach($field in @('pictureCueRevision','pictureCueBoundaries','pictureSegments','pictureCueSummary')){$edgePlan.PSObject.Properties.Remove($field)}
$edgeEvidence=Clone $evidence[0];$edgeEvidence.CaptionWordTimings[-1].End=12.0
Add-PvsCuePicturePlan $edgePlan $refs @($edgeEvidence)
Check (-not $edgePlan.PSObject.Properties['pictureSegments'] -and $edgePlan.segments.Count -eq 1) 'voice-tail-anchor-keeps-group-without-aborting-job'
foreach($fault in @('source-frame','output-frame','duration','speed','time','voice-anchor','anchor-chapter','anchor-cue','tail','anchor-lost','omission')){
    $bad=Clone $plan
    switch($fault){
        source-frame {$bad.pictureSegments[0].SourceEndFrame++}
        output-frame {$bad.pictureSegments[0].NewEndFrame++}
        duration {$bad.pictureSegments[0].SourceDurationFrames++}
        speed {$bad.pictureSegments[0].AppliedSpeedPercent++}
        time {$bad.pictureSegments[0].NewEnd+=0.1}
        voice-anchor {$bad.pictureCueBoundaries[0].VoiceFrame++}
        anchor-chapter {$bad.pictureCueBoundaries[0].Chapter=1}
        anchor-cue {$bad.pictureCueBoundaries[0].RightCue++}
        tail {$bad.pictureSegments=@($bad.pictureSegments[0..1])}
        anchor-lost {$bad.pictureCueBoundaries=@()}
        omission {$bad|Add-Member editedSourceMap @{} }
    }
    $rejected=$false;try{Assert-PvsCuePicturePlan $bad}catch{$rejected=$_.Exception.Message -like 'PICTURE_CUE_*'}
    Check $rejected "tamper-rejected-$fault"
}
$omission=Clone $plan;$omission|Add-Member editedSourceMap @{};$omission.PSObject.Properties.Remove('pictureCueRevision');$omission.PSObject.Properties.Remove('pictureSegments')
Add-PvsCuePicturePlan $omission $refs $evidence
Check (-not $omission.PSObject.Properties['pictureSegments']) 'strict-omission-workflow-remains-separate'
function RecoveryFixture {
    $r=Clone @($refs[0]);$w=Clone @($words[0..9]);$r.Text='alpha bravo charlie delta echo foxtrot golf hotel india 102,'
    $tokens=@(ConvertTo-NormalizedWords $r.Text);for($i=0;$i -lt $w.Count;$i++){$w[$i].Text=$tokens[$i]}
    $text=$r.Text.Replace('hotel','substituted')
    $cell=[pscustomobject]@{Text=$text;Start=0.2;End=2.65;ReferenceCueIndices=@()}
    $cue=[pscustomobject]@{Index=1;Chapter=0;Start=0.0;End=4.0;Text=$text;ManualEditBlock=$true;ManualReferenceCueIndices=@(1);ManualCaptionCues=@($cell)}
    [pscustomobject]@{References=@($r);Words=@($w);Cues=@($cue)}
}
$recovery=RecoveryFixture;$original=$recovery.Cues[0].Text
$recovered=@(Restore-PvsObservedManualReferenceCells $recovery.Cues $recovery.References $recovery.Words $voices)
Check ($recovered.Count -eq 1 -and $recovery.Cues[0].Text -ceq $recovery.References[0].Text) 'complete-independent-dtw-restores-canonical-srt'
Check ($recovery.Cues[0].ManualCaptionCues[0].RecognitionOriginalText -ceq $original) 'original-primary-text-recorded'
Check (Test-PvsManualAcousticCell $recovery.Cues[0].ManualCaptionCues[0] $voices[0]) 'recovery-uses-real-word-times'
foreach($fault in @('estimated','missing-suffix','extra-speech','numeric-conflict','wrong-chapter','duplicate','overlap')){
    $r=RecoveryFixture
    switch($fault){
        estimated {$r.Words[2].SubtitleTimingQuality='estimated'}
        missing-suffix {$r.Words=@($r.Words[0..8])}
        extra-speech {$r.Cues[0].ManualCaptionCues[0].Text+=' genuine extra speech'}
        numeric-conflict {$r.Cues[0].ManualCaptionCues[0].Text=$r.Cues[0].ManualCaptionCues[0].Text.Replace('102','103')}
        wrong-chapter {$r.Cues[0].Chapter=1}
        duplicate {$r.References=@($r.References)+@($r.References[0].PSObject.Copy());$r.Cues[0].ManualReferenceCueIndices=@(1,2)}
        overlap {$r.Cues[0].ManualCaptionCues+= [pscustomobject]@{Text='next';Start=2.5;End=4;ReferenceCueIndices=@(2)}}
    }
    $before=$r.Cues[0].ManualCaptionCues[0].Text
    Check (-not @(Restore-PvsObservedManualReferenceCells $r.Cues $r.References $r.Words $voices).Count) "recovery-rejects-$fault"
    Check ($r.Cues[0].ManualCaptionCues[0].Text -ceq $before) "primary-retained-$fault"
}
$r=RecoveryFixture;$copy=Clone $r.References[0];$copy.Index=2;$copy.Start+=6;$copy.End+=6;$r.References+=@($copy)
$copyWords=Clone $r.Words;foreach($w in $copyWords){$w.Start+=6;$w.End+=6};$r.Words+=@($copyWords)
Check (@(Restore-PvsObservedManualReferenceCells $r.Cues $r.References $r.Words $voices).Count -eq 1) 'duplicate-outside-owned-window-does-not-block-text-recovery'
Write-Host 'CUE_PICTURE_OK:touching-nonterminal-srt;independent-v1-a2;whole-cue-dtw;strict-quiet;conservation;tamper;real-reference-recovery;unsafe-recovery-rejected'
