$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$root=Resolve-Path (Join-Path $PSScriptRoot '..\..')
. "$root\extension\engine\lib\Srt.ps1"
. "$root\extension\engine\lib\Alignment.ps1"
function New-Case {
    @(
        [pscustomobject]@{Index=302;OriginalStart=0;OriginalEnd=1;Text='Anchor';Start=100;End=101;Chapter=1;Confidence=1;WordTimings=@()},
        [pscustomobject]@{Index=303;OriginalStart=1;OriginalEnd=3;Text='Mot hai ba bon nam sau bay tam chin muoi.';Start=$null;End=$null;Chapter=-1;Confidence=0;WordTimings=@()},
        [pscustomobject]@{Index=304;OriginalStart=3;OriginalEnd=4;Text='Chuc moi nguoi ngu ngon.';Start=$null;End=$null;Chapter=-1;Confidence=0;WordTimings=@()}
    )
}
$voices=@([pscustomobject]@{start=0;end=90},[pscustomobject]@{start=100;end=106})
$cues=New-Case
$anchor=$cues[0] | ConvertTo-Json -Depth 5 -Compress
$script:calls=0
$callback={
    param($voice,$start,$end)
    $script:calls++
    if ($start -ne 101 -or $end -ne 106 -or $voice.start -ne 100) {throw 'RECOVERY_WINDOW_WRONG'}
    $words=@(ConvertTo-NormalizedWords ($cues[1].Text+' '+$cues[2].Text))
    for($i=0;$i -lt $words.Count;$i++) {[pscustomobject]@{Text=$words[$i];Start=$i*0.3;End=($i+1)*0.3;Chapter=0}}
}
$repaired=@(Repair-PvsMissingCueWordTimings -Cues $cues -VoiceClips $voices -RecognizeWindow $callback)
if (($repaired -join ',') -ne '303,304' -or $script:calls -ne 1) {throw 'RECOVERY_NOT_SINGLE_BOUNDED_RETRY'}
if (($cues[0] | ConvertTo-Json -Depth 5 -Compress) -ne $anchor) {throw 'RECOVERY_CHANGED_TRUSTED_ANCHOR'}
if ($cues[1].Chapter -ne 1 -or $cues[1].WordTimings[0].Chapter -ne 1 -or $cues[1].Start -ne 101) {throw 'RECOVERY_CHAPTER_OFFSET_WRONG'}
$parts=@(Split-PvsVoiceAlignedCaptionCue -Cue $cues[1] -MaxCharacters 24 -FrameRate 30)
if ($parts.Count -lt 2 -or -not $parts[1].VoiceBoundaryAligned) {throw 'RECOVERY_CAPTION_STILL_MISSING_TIMINGS'}
if (($parts.Text -join ' ') -ne $cues[1].Text) {throw 'RECOVERY_DROPPED_CAPTION_TEXT'}
foreach($mode in @('mismatch','empty','outside','partial','invalid-time','backwards','weak-anchor','cross-chapter','long-window','no-anchor')) {
    $case=New-Case
    $localVoices=@($voices | ForEach-Object {$_.PSObject.Copy()})
    if ($mode -eq 'weak-anchor') {$case[0].Confidence=0.5}
    if ($mode -eq 'cross-chapter') {$case[2].Start=104;$case[2].End=105;$case[2].Chapter=0;$case[2].Confidence=1}
    if ($mode -eq 'long-window') {$localVoices[1].end=140}
    if ($mode -eq 'no-anchor') {$case=@($case[1],$case[2])}
    $before=$case | ConvertTo-Json -Depth 7 -Compress
    $count=0
    $found=@(Repair-PvsMissingCueWordTimings -Cues $case -VoiceClips $localVoices -RecognizeWindow {
        param($voice,$start,$end)
        $words=@(ConvertTo-NormalizedWords ($case[1].Text+' '+$case[2].Text))
        if ($mode -eq 'empty') {return}
        if ($mode -eq 'partial') {$words=@($words[0..5])}
        for($i=0;$i -lt $words.Count;$i++) {
            $from=$i*0.3
            if ($mode -eq 'outside') {$from+=20}
            if ($mode -eq 'backwards' -and $i -eq 4) {$from=0.1}
            [pscustomobject]@{Text=$(if ($mode -eq 'mismatch') {'wrong'} else {$words[$i]});Start=$from;End=$(if($mode -eq 'invalid-time'){$from}else{$from+0.3});Chapter=0}
        }
    })
    if ($found.Count -or ($case | ConvertTo-Json -Depth 7 -Compress) -ne $before) {throw "UNSAFE_RECOVERY_ACCEPTED:$mode"}
}
Write-Host 'MISSING_WORD_TIMING_RECOVERY_OK:tail;caption;chapter-offset;preserved-anchor;10-negative-cases'

$oneFrameOverlap=@(
    [pscustomobject]@{Start=1;End=(31/30.0);PartIndex=1;PartCount=2},
    [pscustomobject]@{Start=1;End=2;PartIndex=2;PartCount=2}
)
Add-PvsCaptionEdgePadding -Captions $oneFrameOverlap -FrameRate 30 -TimelineEndFrame 60
if($oneFrameOverlap[0].End -ne $oneFrameOverlap[1].Start -or $oneFrameOverlap[0].End -le $oneFrameOverlap[0].Start){throw 'ROUNDING_CAPTION_OVERLAP_NOT_RESOLVED'}
$largeOverlap=@(
    [pscustomobject]@{Start=1;End=1.2;PartIndex=1;PartCount=2},
    [pscustomobject]@{Start=1;End=2;PartIndex=2;PartCount=2}
)
$rejected=$false
try {Add-PvsCaptionEdgePadding -Captions $largeOverlap -FrameRate 30 -TimelineEndFrame 60} catch {if($_.Exception.Message -like 'CAPTION_OVERLAP_TIMING_UNSAFE:*'){$rejected=$true}else{throw}}
if(-not $rejected){throw 'LARGE_CAPTION_OVERLAP_WAS_HIDDEN'}
Write-Host 'CAPTION_ROUNDING_OVERLAP_OK:one-frame-only;larger-overlap-rejected'
