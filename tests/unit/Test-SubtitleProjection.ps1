$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$root=Resolve-Path (Join-Path $PSScriptRoot '..\..')
. "$root\extension\engine\lib\Srt.ps1"
. "$root\extension\engine\lib\Alignment.ps1"
. "$root\extension\engine\lib\CaptionOnly.ps1"
function New-ProjectionWords([string]$Text,[double]$Start,[double]$End){
    $tokens=@(ConvertTo-NormalizedWords $Text)
    for($i=0;$i -lt $tokens.Count;$i++){
        [pscustomobject]@{Text=$tokens[$i];Start=$Start+($End-$Start)*$i/$tokens.Count;End=$Start+($End-$Start)*($i+1)/$tokens.Count;Chapter=0;SubtitleTimingQuality='estimated';SubtitleTimingOrigin='projection-fixture'}
    }
}
function Test-Projection([string[]]$Expected,[string[]]$Heard){
    $texts=@('alpha bravo charlie delta echo foxtrot')+@($Expected)+@('golf hotel india juliet kilo lima')
    $refs=@(for($i=0;$i -lt $texts.Count;$i++){[pscustomobject]@{Index=$i+1;Text=$texts[$i];Start=900+$i*10;End=910+$i*10}})
    $words=@(New-ProjectionWords $texts[0] 0 2)
    for($i=0;$i -lt $Heard.Count;$i++){$words+=@(New-ProjectionWords $Heard[$i] (2+$i*3) (5+$i*3))}
    $last=2+$Heard.Count*3;$words+=@(New-ProjectionWords $texts[-1] $last ($last+2))
    $before=$words|ConvertTo-Json -Depth 8 -Compress
    $sources=@([pscustomobject]@{start=0.0;end=$last+2})
    $selection=Select-PvsSubtitleReference $refs $words $sources -AllowEditedReference -AllowUnmatchedRanges -SkipUnverifiedCues -RecognizeReferenceWindow { @() }
    if($selection.SelectedCueCount -ne $refs.Count){throw "PROJECTION_LOST_SRT:$($Expected -join '|'):$($selection.SkippedCues|ConvertTo-Json -Compress)"}
    if(($words|ConvertTo-Json -Depth 8 -Compress) -cne $before){throw 'PROJECTION_MUTATED_RECOGNITION'}
    foreach($cue in $selection.Cues){if(-not (Test-PvsReferenceCueTiming $cue 0 ($last+2) 0)){throw 'PROJECTION_TIMING_INVALID'}}
    $complete=Complete-PvsSubtitleReference $selection $selection.RecognitionWords $sources {throw 'PROJECTION_REQUESTED_ASR_SUPPLEMENT'}
    $captions=@(New-PvsStandaloneCaptions $complete.Cues $sources @() 30 30)
    if((@(ConvertTo-NormalizedWords ($captions.Text -join ' ')) -join '|') -cne (@(ConvertTo-NormalizedWords ($texts -join ' ')) -join '|')){throw 'PROJECTION_CHANGED_FINAL_SRT'}
    if(@($captions|Where-Object {$_.PSObject.Properties['RecognitionSupplement'] -and $_.RecognitionSupplement}).Count){throw 'PROJECTION_MARKED_SRT_AS_ASR'}
}
# These failures came from the full Antarctica replay. Exact-only alignment
# shifted thụ onto ô, and mét onto 000, despite the identity policy accepting
# their accent/unit variants. The two adjacent number cues must both survive.
Test-Projection @('Chúng hấp thụ ô xy trực tiếp qua da để tồn tại.') @('chung hấp thu oc trực tiếp qua ra để tồn tại')
Test-Projection @('đỉnh cao nhất gần 3000 mét,','xấp xỉ 1 phần 3 chiều cao của Everest.') @('đỉnh cao nhất gần 3 000 m','sắp xì 1 3 triều cao của everest')
# The alternative must keep raw ASR evidence and the ordinary language path.
$refs=@([pscustomobject]@{Index=1;Text='thụ ô xy trực tiếp qua da';Start=0;End=3})
$heard=@(New-ProjectionWords 'thu oc trực tiếp qua ra' 0 3);$sources=@([pscustomobject]@{start=0;end=3})
$layout=New-PvsReferenceWordLayout $refs
$plain=@(Convert-PvsReferenceMappingToCues $refs $layout @(Get-SequentialWordMapping $layout.Words $heard) $heard $sources -PreserveReferenceIndices -FixedChapter 0)
$other=@(Convert-PvsSubtitleReferenceProjection $refs $layout $heard $heard $sources 0 en)
if(($plain|ConvertTo-Json -Depth 8 -Compress) -cne ($other|ConvertTo-Json -Depth 8 -Compress)){throw 'VIETNAMESE_MAPPING_LEAKED_TO_OTHER_LANGUAGE'}
foreach($text in @('3 ngày 4','3 phần việc 4','phần 3 ngày 4')){
    if($null -ne (Get-PvsSubtitleNumericSpan @(ConvertTo-NormalizedWords $text) -RequireDigits)){throw 'FRACTION_ABSORBED_ORDINARY_CONTEXT'}
}
$fraction=Get-PvsSubtitleNumericSpan @('1','phần','3') -RequireDigits
if($null -eq $fraction -or $fraction.Text -cne '1 phần 3'){throw 'FRACTION_FIELD_NOT_IDENTIFIED'}
Write-Host 'SUBTITLE_PROJECTION_OK:accent-alignment;unit-alignment;adjacent-number-cues;fraction-context;raw-evidence-unchanged;other-language-unchanged;final-SRT'
