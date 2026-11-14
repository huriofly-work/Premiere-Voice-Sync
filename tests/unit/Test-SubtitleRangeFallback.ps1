$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$root=Resolve-Path (Join-Path $PSScriptRoot '..\..')
. "$root\extension\engine\lib\Srt.ps1"
. "$root\extension\engine\lib\Alignment.ps1"
. "$root\extension\engine\lib\CaptionOnly.ps1"
$cues=for($cue=0;$cue -lt 4;$cue++){
    [pscustomobject]@{Index=$cue+1;Text=((0..5 | ForEach-Object {"word$($cue*6+$_)"}) -join ' ')+'.';Start=900+$cue;End=901+$cue}
}
$sources=@([pscustomobject]@{start=10;end=13.6},[pscustomobject]@{start=30;end=33.6},[pscustomobject]@{start=50;end=53.6})
$words=foreach($chapter in 0..2){
    for($word=0;$word -lt 12;$word++){
        $text=if($chapter -eq 1){"different$word"}else{"word$($word+$(if($chapter -eq 2){12}else{0}))"}
        [pscustomobject]@{Text=$text;Start=$word*0.3;End=($word+1)*0.3;Chapter=$chapter}
    }
}
$selection=Select-PvsSubtitleReference $cues @($words) $sources -AllowUnmatchedRanges -SkipUnverifiedCues
if(($selection.Cues.Index -join ',') -ne '1,2,3,4' -or ($selection.Cues.Chapter -join ',') -ne '0,0,2,2' -or $selection.Ranges.Count -ne 2 -or $selection.FallbackRanges.Count -ne 1 -or $selection.FallbackRanges[0].sourceIndex -ne 1){throw 'ONE_BAD_RANGE_DISCARDED_GOOD_SRT'}
$script:retries=0
$complete=Complete-PvsSubtitleReference $selection @($words) $sources {
    param($source,$start,$end,$chapter)
    $script:retries++
    if($chapter -ne 1 -or $start -ne 30 -or $end -ne 33.6){throw 'GOOD_SOURCE_RECOGNIZED_AGAIN'}
    [pscustomobject]@{Index=1;Text='different speech';Start=$start;End=$end;Chapter=$chapter;WordTimings=@()}
}
if($script:retries -ne 1 -or $complete.Cues.Count -ne 5 -or ($complete.Cues | Where-Object {$_.PSObject.Properties['ReferenceCueIndex']} | ForEach-Object {$_.ReferenceCueIndex}) -join ',' -ne '1,2,3,4'){throw 'PARTIAL_FALLBACK_OUTPUT_WRONG'}

# A source with no initial words gets one explicit retry, including when every
# source is empty. No words from another source may fill its missing interval.
foreach($emptyAll in @($false,$true)){
    $heard=if($emptyAll){@()}else{@($words | Where-Object {$_.Chapter -ne 1})}
    $selection=Select-PvsSubtitleReference $cues $heard $sources -AllowUnmatchedRanges -SkipUnverifiedCues
    $expected=if($emptyAll){3}else{1}
    if($selection.FallbackRanges.Count -ne $expected -or @($selection.FallbackRanges | Where-Object {$_.reason -notmatch 'SCOPE_NO_SPEECH'}).Count){throw 'EMPTY_INITIAL_SOURCE_NOT_RETRYABLE'}
    $script:retries=0
    $complete=Complete-PvsSubtitleReference $selection $heard $sources {param($source,$start,$end,$chapter);$script:retries++}
    if($script:retries -ne $expected -or $complete.EmptyRanges.Count -ne $expected){throw 'EMPTY_SOURCE_NOT_RETRIED_AND_REPORTED'}
}

# All mismatches are retryable, while strict callers still get scope errors.
$wrong=@($words | Where-Object {$_.Chapter -eq 1} | ForEach-Object {$copy=$_.PSObject.Copy();$copy.Chapter=0;$copy})
$selection=Select-PvsSubtitleReference $cues $wrong @($sources[0]) -AllowUnmatchedRanges -SkipUnverifiedCues
if($selection.Cues.Count -ne 0 -or $selection.UnverifiedRanges.Count -ne 1){throw 'ALL_MISMATCH_FALLBACK_MISSING'}
$failed=$false
try{Select-PvsSubtitleReference $cues $wrong @($sources[0]) | Out-Null}catch{if($_.Exception.Message -match 'SCOPE_MISMATCH'){$failed=$true}else{throw}}
if(-not $failed){throw 'STRICT_SCOPE_POLICY_CHANGED'}
$repeat=Select-PvsSubtitleReference @($cues+$cues) @($words | Where-Object {$_.Chapter -eq 0}) @($sources[0]) -AllowUnmatchedRanges -SkipUnverifiedCues
if($repeat.FallbackRanges.Count -ne 1 -or $repeat.FallbackRanges[0].reason -notmatch 'SCOPE_AMBIGUOUS'){throw 'AMBIGUOUS_RANGE_ASSIGNED_REFERENCE_TEXT'}
$reversed=@($words | Where-Object {$_.Chapter -ne 1} | ForEach-Object {$copy=$_.PSObject.Copy();$copy.Chapter=if($_.Chapter -eq 0){1}else{0};$copy})
$order=Select-PvsSubtitleReference $cues $reversed @($sources[0],$sources[1]) -AllowUnmatchedRanges -SkipUnverifiedCues
if(($order.Cues.Index -join ',') -ne '3,4' -or $order.FallbackRanges.Count -ne 1 -or $order.FallbackRanges[0].reason -notmatch 'SCOPE_ORDER'){throw 'RANGE_ORDER_GUARD_LOST'}

# Exact text is insufficient when its timestamps are corrupt. Subtitle must
# re-recognize it instead of emitting SRT text at invalid or invented times.
$clean=@($words | Where-Object {$_.Chapter -eq 0})
foreach($mode in @('nan','infinity','zero','overlap','outside')){
    $invalid=@($clean | ForEach-Object {$_.PSObject.Copy()})
    switch($mode){
        nan {$invalid[3].Start=[double]::NaN}
        infinity {$invalid[3].End=[double]::PositiveInfinity}
        zero {$invalid[3].End=$invalid[3].Start}
        overlap {$invalid[3].Start=$invalid[2].Start}
        outside {$invalid[0].Start=-1}
    }
    $check=Select-PvsSubtitleReference $cues $invalid @($sources[0]) -AllowUnmatchedRanges -SkipUnverifiedCues
    if(($check.Cues.Index -join ',') -ne '2' -or ($check.SkippedCues.cueIndex -join ',') -ne '1'){throw "INVALID_TIMING_PASSED_REFERENCE_CHECK:$mode"}
}

# Shared recovery rejects an otherwise exact ASR result containing infinity.
$reference=@($cues[0..2])
$heard=for($word=0;$word -lt 18;$word++){
    if($word -ge 6 -and $word -lt 12){continue}
    [pscustomobject]@{Text="word$word";Start=$word*0.3;End=($word+1)*0.3;Chapter=0}
}
$source=@([pscustomobject]@{start=10;end=15.4})
$aligned=@(Align-CuesToRecognizedWords $reference @($heard) $source)
$recovered=@(Repair-PvsMissingCueWordTimings $aligned $source {
    param($voice,$start,$end)
    for($word=0;$word -lt 6;$word++){
        [pscustomobject]@{Text="word$($word+6)";Start=$word*0.3;End=$(if($word -eq 2){[double]::PositiveInfinity}else{($word+1)*0.3});Chapter=0}
    }
})
if($recovered.Count -ne 0 -or $null -ne $aligned[1].Start){throw 'SHARED_RECOVERY_ACCEPTED_INVALID_TIMING'}
# Character mode follows the same empty-output and invalid-time contracts.
$cjk=@([pscustomobject]@{Index=1;Text='\u7532\u4e59\u4e19\u4e01\u620a\u5df1\u5e9a\u8f9b\u58ec\u7678';Start=90;End=91})
$cjk[0].Text=[regex]::Unescape($cjk[0].Text)
$characters=@(Get-PvsSubtitleLexicalWords $cjk[0].Text $true)
$cjkWords=for($word=0;$word -lt $characters.Count;$word++){[pscustomobject]@{Text=$characters[$word];Start=$word*0.3;End=($word+1)*0.3;Chapter=0}}
$cjkWords[4].End=[double]::NaN
$invalidCjk=Select-PvsSubtitleReference $cjk @($cjkWords) @($sources[0]) -CharacterMode $true -AllowUnmatchedRanges -SkipUnverifiedCues
$emptyCjk=Select-PvsSubtitleReference $cjk @() @($sources[0]) -CharacterMode $true -AllowUnmatchedRanges -SkipUnverifiedCues
if($invalidCjk.Cues.Count -ne 0 -or $invalidCjk.SkippedCueCount -ne 1 -or $emptyCjk.Cues.Count -ne 0 -or $emptyCjk.FallbackRanges.Count -ne 1){throw 'CHARACTER_MODE_INVALID_OR_EMPTY_SCOPE_NOT_RETRYABLE'}
Write-Host 'SUBTITLE_RANGE_FALLBACK_OK:good-SRT-preserved;mismatch,empty,ambiguous,order isolated;strict-errors-preserved;invalid-timing-rejected'
