$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
. "$PSScriptRoot\Test-SubtitleProjection.ps1"
# Same quantities with a digit/unit in one ASR lexical token. The final SRT
# must retain its spelling; an expanded lexical view is not word timing.
Test-Projection @('băng mở rộng đến khoảng 19000000 kilomet vuông,') @('băng mở rộng đến khoảng 19 triệu km2')
Test-Projection @('với diện tích xấp xỉ 480000 kilomet vuông.') @('với diện tích sắp xỉ 480 000km2')
$reference=[pscustomobject]@{Index=1;Text='với diện tích xấp xỉ 480000 kilomet vuông.';Start=900;End=910}
$layout=New-PvsReferenceWordLayout @($reference)
$sources=@([pscustomobject]@{start=20;end=30})
$heard=@(New-ProjectionWords 'với diện tích sắp xỉ 480 000km2' 0 4)
$before=$heard|ConvertTo-Json -Depth 8 -Compress
$cue=@(Convert-PvsSubtitleReferenceProjection @($reference) $layout $heard $heard $sources 0 vi)[0]
if(-not (Test-PvsSubtitleNumberReferenceIdentity $cue $heard $sources)){throw 'UNIT_PROJECTION_NOT_IDENTIFIED'}
if($cue.Start -ne 20 -or $cue.End -ne 24 -or $cue.Text -cne $reference.Text){throw 'UNIT_PROJECTION_CHANGED_TEXT_OR_OFFSET'}
if(($heard|ConvertTo-Json -Depth 8 -Compress) -cne $before){throw 'UNIT_PROJECTION_MUTATED_ASR'}
if(Test-PvsSubtitleDtwCue $cue @{}){throw 'UNIT_EXPANSION_CLAIMED_WORD_DTW'}
$last=@($cue.WordTimings|Where-Object TargetWordIndex -eq 7)
if($last.Count -ne 1 -or $last[0].SubtitleTimingQuality -ne 'estimated' -or $last[0].SubtitleTimingOrigin -ne 'projection-fixture'){throw 'COMPACT_UNIT_LOST_TIMING_PROVENANCE'}
foreach($different in @('với diện tích sắp xỉ 480 000km','với diện tích sắp xỉ 480 000m2','với diện tích sắp xỉ lời thêm 480 000km2')){
    $words=@(New-ProjectionWords $different 0 4)
    if($null -ne (New-PvsSubtitleUnitReferenceProjection $reference $words $words $sources 0)){throw "UNIT_PROJECTION_SWALLOWED_DIFFERENT_CONTEXT:$different"}
}
$plain=@(Convert-PvsReferenceMappingToCues @($reference) $layout @(Get-SequentialWordMapping $layout.Words $heard) $heard $sources -PreserveReferenceIndices -FixedChapter 0)
$other=@(Convert-PvsSubtitleReferenceProjection @($reference) $layout $heard $heard $sources 0 en)
if(($plain|ConvertTo-Json -Depth 8 -Compress) -cne ($other|ConvertTo-Json -Depth 8 -Compress)){throw 'COMPACT_UNIT_MAPPING_CHANGED_OTHER_LANGUAGE'}
foreach($fault in @('nan','overlap','chapter','outside')){
    $bad=@($heard|ForEach-Object {$_.PSObject.Copy()})
    switch($fault){nan {$bad[-1].Start=[double]::NaN};overlap {$bad[-1].Start=$bad[-2].Start};chapter {$bad[-1].Chapter=1};outside {$bad[-1].End=11}}
    if($null -ne (New-PvsSubtitleUnitReferenceProjection $reference $bad $bad $sources 0)){throw "UNIT_PROJECTION_ACCEPTED_BAD_TIMING:$fault"}
}
Write-Host 'SUBTITLE_UNIT_PROJECTION_OK:digit-unit;grouped-thousands;million;final-SRT;unit-dimensions;extra-speech;raw-evidence;offset;timing-provenance;other-language;invalid-timing'
