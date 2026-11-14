$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot '..\..\extension\engine\lib\CaptionTiming.ps1')
$map=@(New-PvsCaptionVoiceMap @(
    [pscustomobject]@{Kind='retime';OriginalVoiceStartFrame=0;OriginalVoiceEndFrame=100;NewVoiceStartFrame=30;NewVoiceEndFrame=130},
    [pscustomobject]@{Kind='gap'},
    [pscustomobject]@{Kind='retime';OriginalVoiceStartFrame=100;OriginalVoiceEndFrame=200;NewVoiceStartFrame=160;NewVoiceEndFrame=260}
))
foreach($case in @(@(50,$false,80),@(100,$false,160),@(100,$true,130),@(200,$true,260),@(0,$false,30))){
    if((Get-PvsMappedCaptionFrame $map $case[0] -EndEdge:([bool]$case[1])) -ne $case[2]){throw 'CAPTION_MAP_EDGE_OR_OFFSET'}
}
foreach($frame in @(-1,201)){
    $failed=$false
    try{Get-PvsMappedCaptionFrame $map $frame | Out-Null}catch{$failed=$_.Exception.Message -like 'CAPTION_OUTSIDE_VOICE_COVERAGE:*'}
    if(-not $failed){throw 'CAPTION_MAP_OUTSIDE_SILENTLY_CLAMPED'}
}
$gap=@($map | ForEach-Object {$_.PSObject.Copy()});$gap[1].OriginalVoiceStartFrame=120;$gap[1].OriginalVoiceEndFrame=220
$failed=$false;try{Get-PvsMappedCaptionFrame $gap 110 | Out-Null}catch{$failed=$_.Exception.Message -like 'CAPTION_OUTSIDE_VOICE_COVERAGE:*'}
if(-not $failed){throw 'CAPTION_MAP_SOURCE_GAP_ACCEPTED'}
$bad=@($map | ForEach-Object {$_.PSObject.Copy()});$bad[1].NewVoiceEndFrame++
$failed=$false;try{New-PvsCaptionVoiceMap $bad | Out-Null}catch{$failed=$_.Exception.Message -like 'CAPTION_VOICE_MAP_INVALID:*'}
if(-not $failed){throw 'CAPTION_MAP_DURATION_CHANGED'}
$duplicate=@($map)+@([pscustomobject]@{Kind='retime';OriginalVoiceStartFrame=100;OriginalVoiceEndFrame=101;NewVoiceStartFrame=159;NewVoiceEndFrame=160})
$complete=@(New-PvsCaptionVoiceMap $duplicate)
if($complete.Count -ne 2 -or (Get-PvsMappedCaptionFrame $complete 100) -ne 160){throw 'CAPTION_MAP_REDUNDANT_ONE_FRAME_SLICE_SELECTED'}
$conflict=@([pscustomobject]@{SourceCueIndex=1;Start=0.0;End=3.0},[pscustomobject]@{SourceCueIndex=2;Start=2.0;End=3.6})
$legacy=@([pscustomobject]@{StartFrame=0;EndFrame=90},[pscustomobject]@{StartFrame=90;EndFrame=120})
$review=@(Resolve-PvsCaptionMappingConflicts $conflict $legacy 30)
if($review.Count -ne 1 -or $review[0] -ne 2 -or $conflict[1].Start -ne 3 -or $conflict[1].End -ne 4){throw 'CAPTION_MAPPING_CONFLICT_NOT_REVIEWED_OR_RETAINED'}
$valid=@([pscustomobject]@{SourceCueIndex=1;Start=0.0;End=1.0},[pscustomobject]@{SourceCueIndex=2;Start=2.0;End=3.6})
if(@(Resolve-PvsCaptionMappingConflicts $valid $legacy 30).Count -or $valid[1].Start -ne 2.0){throw 'CAPTION_MAPPING_VALID_PROMOTION_REVERTED'}
Write-Host 'CAPTION_TIMELINE_MAPPING_OK:piecewise-voice-offset;start-right-end-left;inserted-gap;source-gap-rejected;no-estimate-or-clamp'
