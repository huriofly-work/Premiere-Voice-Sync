$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$root=Resolve-Path (Join-Path $PSScriptRoot '..\..')
. "$root\extension\engine\lib\Srt.ps1"
. "$root\extension\engine\lib\Alignment.ps1"
. "$root\extension\engine\lib\CaptionOnly.ps1"
$cues=for($i=0;$i -lt 4;$i++){
    [pscustomobject]@{Index=$i+1;Text=((0..5 | ForEach-Object {"reference$($i*6+$_)"}) -join ' ')+'.';Start=900+$i;End=901+$i}
}
$tokens=@(0..11 | ForEach-Object {"intro$_"})+@(0..23 | ForEach-Object {if($_ -ge 12 -and $_ -le 17){"different$_"}else{"reference$_"}})+@(0..11 | ForEach-Object {"subscribe$_"})
$words=for($i=0;$i -lt $tokens.Count;$i++){[pscustomobject]@{Text=$tokens[$i];Start=$i*0.3;End=($i+1)*0.3;Chapter=0}}
$sources=@([pscustomobject]@{start=10;end=10+$tokens.Count*0.3})
$selection=Select-PvsSubtitleReference $cues @($words) $sources -AllowAudioOutsideReference -SkipUnverifiedCues
if(($selection.Cues.Index -join ',') -ne '1,2,4' -or $selection.SkippedCueCount -ne 1 -or $selection.SkippedCues[0].cueIndex -ne 3 -or $selection.OutsideCueCount -ne 0){throw 'SUPPLEMENT_REFERENCE_SELECTION_WRONG'}
$before=$selection.Cues | ConvertTo-Json -Depth 8 -Compress
$script:windows=New-Object System.Collections.Generic.List[object]
function Recognize-FixtureWindow {
    param($source,[double]$start,[double]$end,[int]$chapter)
    $script:windows.Add([pscustomobject]@{start=$start;end=$end})
    $speech=@($words | Where-Object {10+$_.Start -ge $start-0.000001 -and 10+$_.End -le $end+0.000001})
    $json=[pscustomobject]@{segments=@([pscustomobject]@{text=($speech.Text -join ' ')+'.';start=0;end=$end-$start})}
    $recognized=Convert-PvsSubtitleRecognition $json $chapter ($end-$start)
    New-PvsRecognizedSubtitleCues $recognized.Surfaces $recognized.Words $start $chapter
}
$result=Complete-PvsSubtitleReference $selection @($words) $sources ${function:Recognize-FixtureWindow}
if($script:windows.Count -ne 3 -or $result.SupplementRanges.Count -ne 3 -or $result.EmptyRanges.Count -ne 0){throw 'INTRO_MISMATCH_CTA_NOT_SUPPLEMENTED'}
if(($result.Cues.Index -join ',') -ne '1,2,3,4,5,6' -or @($result.Cues | Where-Object {$_.PSObject.Properties['RecognitionSupplement']}).Count -ne 3){throw 'SUPPLEMENT_OUTPUT_INDICES_WRONG'}
if(($result.Cues | Where-Object {$_.PSObject.Properties['ReferenceCueIndex']} | ForEach-Object {$_.ReferenceCueIndex}) -join ',' -ne '1,2,4'){throw 'REFERENCE_PROVENANCE_LOST'}
if(($result.Cues.Text -join ' ') -notmatch 'subscribe11' -or ($result.Cues.Text -join ' ') -notmatch 'different17' -or ($result.Cues.Text -join ' ') -match 'reference12'){throw 'SUPPLEMENT_USED_WRONG_TEXT'}
if(($selection.Cues | ConvertTo-Json -Depth 8 -Compress) -cne $before){throw 'SUPPLEMENT_MUTATED_APPROVED_REFERENCE'}
if($result.SupplementRanges[1].referenceCueIndices[0] -ne 3){throw 'SUPPLEMENT_REPORT_LOST_REFERENCE_INDICES'}
foreach($cue in $result.Cues){if($cue.Start -lt 10 -or $cue.End -gt $sources[0].end){throw 'SUPPLEMENT_WRONG_TIMELINE_OFFSET'}}

# No usable SRT match: automatic recognition covers the entire selected audio.
$none=[pscustomobject]@{Cues=@();UnverifiedRanges=@()}
$script:windows.Clear()
$full=Complete-PvsSubtitleReference $none @($words) $sources ${function:Recognize-FixtureWindow}
if($script:windows.Count -ne 1 -or $full.Cues.Count -ne 1 -or $full.Cues[0].Text -notmatch 'intro0.*subscribe11'){throw 'FULL_ASR_FALLBACK_INCOMPLETE'}
$collapsed=$selection.PSObject.Copy();$collapsed.UnverifiedRanges=@([pscustomobject]@{sourceIndex=0;start=17;end=17;cueIndices=@(3)})
$script:windows.Clear()
$retry=Complete-PvsSubtitleReference $collapsed @($words) $sources ${function:Recognize-FixtureWindow}
if($script:windows.Count -ne 1 -or $retry.Cues.Count -ne 1 -or $retry.Cues[0].Text -notmatch 'subscribe11'){throw 'COLLAPSED_GAP_NOT_RERECOGNIZED'}

# Empty recognition is reported; errors and invalid/out-of-window timings stop.
$empty=Complete-PvsSubtitleReference $selection @($words) $sources {param($source,$start,$end,$chapter)}
if($empty.EmptyRanges.Count -ne 3 -or $empty.Cues.Count -ne 3){throw 'EMPTY_SUPPLEMENT_NOT_REPORTED'}
foreach($mode in @('outside','overlap','nan','chapter')){
    $failed=$false
    try{Complete-PvsSubtitleReference $selection @($words) $sources {
        param($source,$start,$end,$chapter)
        $cue=[pscustomobject]@{Index=1;Text='spoken';Chapter=$chapter;Start=$start;End=$end}
        if($mode -eq 'outside'){$cue.End=$end+1}
        if($mode -eq 'nan'){$cue.Start=[double]::NaN}
        if($mode -eq 'chapter'){$cue.Chapter=1}
        $cue
        if($mode -eq 'overlap'){$cue.PSObject.Copy()}
    } | Out-Null}catch{if($_.Exception.Message -match 'SUBTITLE_SUPPLEMENT_RESULT_INVALID'){$failed=$true}else{throw}}
    if(-not $failed){throw "INVALID_SUPPLEMENT_ACCEPTED:$mode"}
}

# Extra words are not required to hallucinate speech in an ordinary quiet gap.
$cleanWords=for($i=0;$i -lt 24;$i++){$pause=if($i -ge 12){0.6}else{0};[pscustomobject]@{Text="reference$i";Start=$i*0.3+$pause;End=($i+1)*0.3+$pause;Chapter=0}}
$cleanSource=@([pscustomobject]@{start=10;end=17.8})
$clean=Select-PvsSubtitleReference $cues @($cleanWords) $cleanSource
$quiet=Complete-PvsSubtitleReference $clean @($cleanWords) $cleanSource {throw 'QUIET_GAP_TRIGGERED_ASR'}
if($quiet.Cues.Count -ne 4 -or $quiet.SupplementRanges.Count){throw 'QUIET_GAP_NOT_PRESERVED'}
# Selected-range boundaries are respected for multiple disjoint chapters.
$twoSources=@([pscustomobject]@{start=10;end=11},[pscustomobject]@{start=30;end=31})
$twoWords=@([pscustomobject]@{Text='one';Start=0;End=1;Chapter=0},[pscustomobject]@{Text='two';Start=0;End=1;Chapter=1})
$multi=Complete-PvsSubtitleReference $none $twoWords $twoSources {
    param($source,$start,$end,$chapter)
    [pscustomobject]@{Index=1;Text="chapter$chapter";Start=$start;End=$end;Chapter=$chapter;WordTimings=@()}
}
if(($multi.Cues.Start -join ',') -ne '10,30' -or ($multi.Cues.Chapter -join ',') -ne '0,1'){throw 'DISJOINT_SUPPLEMENT_OFFSET_WRONG'}

# A late reference-word repair fills an apparent gap. Do not recognize that
# same speech again, but keep real speech outside the repaired reference.
$repaired=[pscustomobject]@{Index=7;Text='alpha bravo.';Start=10.0;End=11.0;Chapter=0;WordTimings=@(
    [pscustomobject]@{TargetWordIndex=0;Text='alpha';Start=10.0;End=11.0;Chapter=0;Exact=$true}
)}
$overlay=$repaired.PSObject.Copy()
$overlay.WordTimings=@($repaired.WordTimings)+@([pscustomobject]@{TargetWordIndex=1;Text='bravo';Start=11.0;End=11.6;Chapter=0;Exact=$true})
Set-PvsDtwCaptionOverlay @($repaired) @($overlay) | Out-Null
$repairedBefore=$repaired | ConvertTo-Json -Depth 8 -Compress
$repairSelection=[pscustomobject]@{Cues=@($repaired);UnverifiedRanges=@()}
$repairWords=@([pscustomobject]@{Text='bravo';Start=1.0;End=1.6;Chapter=0},[pscustomobject]@{Text='subscribe';Start=2.0;End=2.8;Chapter=0})
$repairSources=@([pscustomobject]@{start=10.0;end=13.0})
$script:repairWindows=0
$repairResult=Complete-PvsSubtitleReference $repairSelection $repairWords $repairSources {
    param($source,$start,$end,$chapter)
    $script:repairWindows++
    if([Math]::Abs($start-11.6) -gt 0.000001 -or $end -ne 13){throw 'REPAIRED_SPEECH_SENT_TO_SUPPLEMENT'}
    [pscustomobject]@{Index=1;Text='subscribe.';Start=12.0;End=12.8;Chapter=0;WordTimings=@()}
}
if($script:repairWindows -ne 1 -or $repairResult.Cues.Count -ne 2 -or $repairResult.Cues[0].End -ne 11.6 -or $repairResult.Cues[0].ReferenceCueIndex -ne 7){throw 'REPAIRED_REFERENCE_OR_CTA_LOST'}
if(($repaired | ConvertTo-Json -Depth 8 -Compress) -cne $repairedBefore){throw 'REPAIRED_REFERENCE_INPUT_MUTATED'}
$noExtra=Complete-PvsSubtitleReference $repairSelection @($repairWords[0]) $repairSources {throw 'REPAIRED_TAIL_TRIGGERED_DUPLICATE_ASR'}
if($noExtra.Cues.Count -ne 1 -or $noExtra.SupplementRanges.Count){throw 'REPAIRED_TAIL_NOT_COVERED'}
foreach($invalidEdge in @([double]::NaN,[double]::PositiveInfinity,14.0,9.0)){
    $bad=$repaired.PSObject.Copy();$bad.CaptionEnd=$invalidEdge;$failed=$false
    try{Complete-PvsSubtitleReference ([pscustomobject]@{Cues=@($bad);UnverifiedRanges=@()}) $repairWords $repairSources {throw 'INVALID_OVERLAY_REACHED_RECOGNITION'} | Out-Null}
    catch{if($_.Exception.Message -eq 'SUBTITLE_REFERENCE_CAPTION_BOUNDS_INVALID'){$failed=$true}else{throw}}
    if(-not $failed){throw 'INVALID_REPAIRED_EDGE_ACCEPTED'}
}
$neighbor=[pscustomobject]@{Index=8;Text='overlap';Start=11.3;End=12.0;Chapter=0}
$failed=$false
try{Complete-PvsSubtitleReference ([pscustomobject]@{Cues=@($repaired,$neighbor);UnverifiedRanges=@()}) $repairWords $repairSources {throw 'OVERLAP_REACHED_RECOGNITION'} | Out-Null}
catch{if($_.Exception.Message -eq 'SUBTITLE_REFERENCE_CAPTION_BOUNDS_OVERLAP'){$failed=$true}else{throw}}
if(-not $failed){throw 'REPAIRED_OVERLAP_SILENTLY_ACCEPTED'}
Write-Host 'SUBTITLE_SUPPLEMENT_OK:matched-SRT-preserved;intro,mismatch,CTA,full-ASR,empty,multiple-ranges;invalid-timing-rejected'
