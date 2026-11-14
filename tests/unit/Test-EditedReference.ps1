$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
. "$PSScriptRoot\..\..\extension\engine\lib\ReferenceAlignment.ps1"
$cues=@(for($i=0;$i -lt 7;$i++){[pscustomobject]@{Index=$i+1;Start=$i*3.0;End=($i+1)*3.0;Text="Cau$i giu nguyen chu nguon day."}})
function New-TestWords([int[]]$Indices,[double]$Offset=0){
    $position=0
    foreach($i in $Indices){foreach($text in @(ConvertTo-NormalizedWords $cues[$i].Text)){
        [pscustomobject]@{Text=$text;Start=$Offset+$position*0.1;End=$Offset+(++$position)*0.1;Chapter=0}
    }}
}
$sources=@([pscustomobject]@{start=10.0;end=11.8})
$words=@(New-TestWords @(0,3,6))
$script:calls=0
$retry={param($source,$start,$end);$script:calls++;foreach($w in $words){if(10+$w.Start -ge $start-0.000001 -and 10+$w.End -le $end+0.000001){[pscustomobject]@{Text=$w.Text;Start=10+$w.Start-$start;End=10+$w.End-$start;Chapter=0}}}}
$before=$cues | ConvertTo-Json -Depth 8 -Compress
$result=Resolve-PvsEditedReference $cues $words $sources $retry
if(-not $result.Resolved -or ($result.Cues.Index -join ',') -ne '1,4,7' -or ($result.OmittedCueIndices -join ',') -ne '2,3,5,6' -or $script:calls -ne 2){throw "EDITED_REFERENCE_MULTI_CUT_FAILED:$($result | ConvertTo-Json -Depth 4 -Compress)"}
if(($result.Cues.Text -join '|') -cne (($cues[0,3,6]).Text -join '|') -or $result.Cues[1].Start -ne 10.6){throw 'EDITED_REFERENCE_TEXT_OR_OFFSET_CHANGED'}
if(($cues | ConvertTo-Json -Depth 8 -Compress) -cne $before){throw 'REFERENCE_MUTATED'}
# Recognition omitted the middle cue, while the real recording still has it.
$sources=@([pscustomobject]@{start=10.0;end=11.8})
$all=@(New-TestWords @(0,1,2))
$miss=@($all[0..5]+$all[12..17])
$repair=Resolve-PvsEditedReference $cues[0..2] $miss $sources {param($source,$start,$end);$all}
if(-not $repair.Resolved -or $repair.OmittedCueIndices.Count -or $repair.Cues.Count -ne 3 -or ($repair.RecoveredCueIndices -join ',') -ne '2'){throw 'ASR_MISS_WRONGLY_DELETED'}
# Empty, changed and invalid retry data cannot authorize picture removal.
foreach($kind in @('empty','partial','badtime','error')){
    $failed=$false;$check=$null
    try{$check=Resolve-PvsEditedReference $cues[0..2] $miss $sources {
        param($source,$start,$end)
        switch($kind){empty {return}; partial {$all[0..8];return}; badtime {$w=$all[0].PSObject.Copy();$w.End=[double]::NaN;$w;return}; error {throw 'NATIVE_ASR_FAILED'}}
    }}catch{if($kind -in @('badtime','error')){$failed=$true}else{throw}}
    if($kind -in @('badtime','error')){if(-not $failed){throw "RETRY_FAILURE_HIDDEN:$kind"}}
    elseif($check.Resolved -or $check.OmittedCueIndices.Count){throw "UNVERIFIED_DELETION:$kind"}
}
Write-Host 'EDITED_REFERENCE_OK:multiple-deletions;source-text;timeline-offset;ASR-recovery;uncertainty;native-failure'
. "$PSScriptRoot\..\..\extension\engine\lib\CaptionOnly.ps1"
$sources=@([pscustomobject]@{start=10.0;end=11.8});$words=@(New-TestWords @(0,3,6))
$selection=Select-PvsSubtitleReference -Cues $cues -Words $words -Sources $sources -AllowEditedReference -AllowUnmatchedRanges -SkipUnverifiedCues -RecognizeReferenceWindow $retry
$captions=Complete-PvsSubtitleReference $selection $selection.RecognitionWords $sources {throw 'DELETED_CUES_MUST_NOT_GENERATE_SPEECH'}
if(($captions.Cues.Text -join '|') -cne ($cues[0,3,6].Text -join '|') -or $captions.SupplementRanges.Count){throw 'EDITED_SUBTITLE_OUTPUT_WRONG'}
foreach($fps in @(30.0,29.97)){
    $map=New-PvsEditedSourceMap $result $cues ([pscustomobject]@{start=0;end=21}) $fps
    if($map.kept.Count -ne 3 -or $map.omissions.Count -ne 2 -or $map.planEndFrame -ne [int][Math]::Round(9*$fps)){throw 'EDITED_SOURCE_MAP_WRONG'}
    if([Math]::Abs((ConvertTo-PvsEditedSourceTime 9 $map $fps)-([Math]::Round(3*$fps)/$fps)) -gt 0.000001){throw 'EDITED_SOURCE_COORDINATE_WRONG'}
}
# A partial cue stays ASR text; its absent suffix must never be resurrected.
$partialWords=@(New-TestWords @(0,1,2))
$partialWords=@($partialWords[0..8]+$partialWords[12..17])
for($i=0;$i -lt $partialWords.Count;$i++){$partialWords[$i].Start=$i*0.1;$partialWords[$i].End=($i+1)*0.1}
$partialSource=@([pscustomobject]@{start=10;end=11.5})
$partialRetry={param($source,$start,$end);foreach($w in $partialWords){if(10+$w.Start -ge $start-0.000001 -and 10+$w.End -le $end+0.000001){[pscustomobject]@{Text=$w.Text;Start=10+$w.Start-$start;End=10+$w.End-$start;Chapter=0}}}}
$partial=Select-PvsSubtitleReference -Cues $cues[0..2] -Words $partialWords -Sources $partialSource -AllowEditedReference -AllowUnmatchedRanges -SkipUnverifiedCues -RecognizeReferenceWindow $partialRetry
if(($partial.Cues.Index -join ',') -ne '1,3' -or $partial.EditedReference.Resolved -or $partial.EditedReference.OmittedCueIndices.Count){throw 'PARTIAL_CUE_WAS_ACCEPTED_OR_DELETED'}
$partialOutput=Complete-PvsSubtitleReference $partial $partial.RecognitionWords $partialSource {param($source,$start,$end,$chapter);[pscustomobject]@{Index=1;Text='Cau1 giu nguyen';Start=$start;End=$end;Chapter=$chapter;WordTimings=@()}}
if($partialOutput.Cues.Count -ne 3 -or $partialOutput.Cues[1].Text -cne 'Cau1 giu nguyen'){throw 'PARTIAL_CUE_SUFFIX_RESTORED'}
Write-Host 'EDITED_SUBTITLE_AND_SOURCE_MAP_OK:kept-text;no-phantom-subtitles;partial-ASR;30,29.97fps'
# Leading/trailing deletions have only one anchor, plus the real audio edge.
$words=@(New-TestWords @(2,4));$sources=@([pscustomobject]@{start=10;end=11.2})
$edges=Resolve-PvsEditedReference $cues $words $sources $retry
if(-not $edges.Resolved -or ($edges.Cues.Index -join ',') -ne '3,5' -or ($edges.OmittedCueIndices -join ',') -ne '1,2,4,6,7'){throw 'LEADING_OR_TRAILING_OMISSION_FAILED'}
# Duplicated text is ambiguous even when the retry also misses both copies.
$repeated=@($cues | ForEach-Object {$_.PSObject.Copy()});$repeated[3].Text=$repeated[1].Text
$words=@(New-TestWords @(0,6));$sources=@([pscustomobject]@{start=10;end=11.2})
$ambiguous=Resolve-PvsEditedReference $repeated $words $sources $retry
if($ambiguous.Resolved -or $ambiguous.OmittedCueIndices.Count){throw 'REPEATED_REFERENCE_AUTHORIZED_DELETION'}
# Inverted speech order never turns into an ordered omission map.
$words=@(New-TestWords @(6,0))
if($null -ne (Resolve-PvsEditedReference $cues $words $sources $retry)){throw 'REORDERED_SPEECH_ACCEPTED'}
Write-Host 'EDITED_REFERENCE_EDGE_GUARDS_OK:head;tail;repeated-reference;reordered-speech'
