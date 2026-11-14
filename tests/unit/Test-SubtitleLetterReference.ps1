$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$root=Resolve-Path (Join-Path $PSScriptRoot '..\..')
. "$root\extension\engine\lib\Srt.ps1"
. "$root\extension\engine\lib\Alignment.ps1"
. "$root\extension\engine\lib\CaptionOnly.ps1"
. "$root\extension\engine\lib\SubtitleTiming.ps1"

function Test-LetterCase([string]$Expected,[string]$Actual,[bool]$Accepted,[double]$Offset=20.0){
    $texts=@('alpha bravo charlie delta echo foxtrot',$Expected,'golf hotel india juliet kilo lima')
    $refs=@(for($i=0;$i -lt 3;$i++){[pscustomobject]@{Index=$i+1;Text=$texts[$i];Start=900+$i*10;End=910+$i*10}})
    $before=$refs|ConvertTo-Json -Depth 8 -Compress
    $tokens=@(ConvertTo-NormalizedWords ($texts[0]+' '+$Actual+' '+$texts[2]))
    $script:letterWords=@(for($i=0;$i -lt $tokens.Count;$i++){[pscustomobject]@{Text=$tokens[$i];Start=$i*0.2;End=($i+1)*0.2;Chapter=0;SubtitleTimingQuality='dtw';SubtitleTimingOrigin='fixture'}})
    $sources=@([pscustomobject]@{start=$Offset;end=$Offset+$tokens.Count*0.2})
    $selection=Select-PvsSubtitleReference $refs $script:letterWords $sources -AllowEditedReference -AllowUnmatchedRanges -SkipUnverifiedCues -RecognizeReferenceWindow {
        param($source,$start,$end)
        foreach($word in $script:letterWords){if($source.start+$word.Start -ge $start-0.000001 -and $source.start+$word.End -le $end+0.000001){$copy=$word.PSObject.Copy();$copy.Start+=$source.start-$start;$copy.End+=$source.start-$start;$copy}}
    }
    $letter=@($selection.Cues | Where-Object Index -eq 2)
    if([bool]$letter.Count -ne $Accepted){throw "LETTER_DECISION_WRONG:$Expected|$Actual|$Accepted"}
    if(($refs|ConvertTo-Json -Depth 8 -Compress) -cne $before){throw 'LETTER_MUTATED_SOURCE_SRT'}
    if(-not $Accepted){return}
    $cue=$letter[0]
    if($cue.Text -cne $Expected -or -not $cue.SubtitleReferenceLetterMatch -or $cue.ReferenceReviewRequired -or (Test-PvsSubtitleDtwCue $cue @{})){throw 'LETTER_TEXT_REVIEW_OR_DTW_WRONG'}
    if([Math]::Abs($cue.Start-($Offset+1.2)) -gt 0.000001 -or [Math]::Abs($cue.End-($Offset+1.4)) -gt 0.000001 -or @($cue.WordTimings).Count -ne 1){throw 'LETTER_GUESSED_TIMING'}
    if(@($selection.EditedReference.Cues|Where-Object Index -eq 2).Count -or $selection.EditedReference.Resolved){throw 'LETTER_RELAXED_SHARED_EDIT_PROOF'}
    $completed=Complete-PvsSubtitleReference $selection $selection.RecognitionWords $sources {throw 'LETTER_SENT_TO_SUPPLEMENT_ASR'}
    $caps=@(New-PvsStandaloneCaptions $completed.Cues $sources @() 30 30)
    if((@(ConvertTo-NormalizedWords ($caps.Text -join ' ')) -join '|') -cne (@(ConvertTo-NormalizedWords ($texts -join ' ')) -join '|')){throw 'LETTER_LOST_IN_FINAL_CAPTIONS'}
    # Exercise span/anchor guards independently of retry validation.
    foreach($fault in @('missing-left','short-anchor','cross-chapter','outside','zero','nan','infinity','overlap','long','extra')){
        $left=$selection.Cues[0].PSObject.Copy();$right=$selection.Cues[2].PSObject.Copy()
        $words=@($selection.RecognitionWords | ForEach-Object {$_.PSObject.Copy()})
        switch($fault){
            'missing-left' {$left=$null}
            'short-anchor' {$left.Text='alpha'}
            'cross-chapter' {$right.Chapter=1}
            'outside' {$words[6].Start=-1}
            'zero' {$words[6].End=$words[6].Start}
            'nan' {$words[6].Start=[double]::NaN}
            'infinity' {$words[6].End=[double]::PositiveInfinity}
            'overlap' {$words[6].End=$words[7].End}
            'long' {$right.Start+=5}
            'extra' {$extra=$words[6].PSObject.Copy();$extra.Text='extra';$words+=@($extra)}
        }
        if($null -ne (New-PvsSubtitleLetterReferenceCue $refs[1] $left $right $words $sources)){throw "INVALID_LETTER_ACCEPTED:$fault"}
    }
}
Test-LetterCase 'A.' 'À,' $true
Test-LetterCase 'C.' 'C.' $true 0
Test-LetterCase 'X)' 'x' $true
Test-LetterCase 'B.' 'bê' $true
Test-LetterCase 'C.' 'x' $false
Test-LetterCase 'A.' 'ạ thêm' $false
Test-LetterCase 'A.' '' $false
Test-LetterCase 'Ừ.' 'ừ' $false
Test-LetterCase 'AB.' 'ab' $false

# Two labels in one unverified interval have no unique immediate neighbors.
$refs=@([pscustomobject]@{Index=1;Text='alpha bravo charlie delta';Start=900;End=910},[pscustomobject]@{Index=2;Text='A.';Start=910;End=911},[pscustomobject]@{Index=3;Text='A.';Start=911;End=912},[pscustomobject]@{Index=4;Text='golf hotel india juliet';Start=912;End=920})
$tokens=@(ConvertTo-NormalizedWords 'alpha bravo charlie delta à golf hotel india juliet')
$words=@(for($i=0;$i -lt $tokens.Count;$i++){[pscustomobject]@{Text=$tokens[$i];Start=$i*0.2;End=($i+1)*0.2;Chapter=0}})
$selection=Select-PvsSubtitleReference $refs $words @([pscustomobject]@{start=0;end=2}) -AllowEditedReference -SkipUnverifiedCues -AllowUnmatchedRanges
if(@($selection.Cues|Where-Object Index -in @(2,3)).Count){throw 'AMBIGUOUS_LETTER_INTERVAL_ACCEPTED'}
Write-Host 'SUBTITLE_LETTER_REFERENCE_OK:accent-and-exact-labels;offsets;observed-timing;final-SRT-text;no-false-ASR-review;omission-unrelated-extra-and-ambiguous-rejected;anchor-span-chapter-guards;shared-edit-proof-unchanged'
