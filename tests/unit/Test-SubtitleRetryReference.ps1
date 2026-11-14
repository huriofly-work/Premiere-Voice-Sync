$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$root=Resolve-Path (Join-Path $PSScriptRoot '..\..')
. "$root\extension\engine\lib\Srt.ps1"
. "$root\extension\engine\lib\Alignment.ps1"
. "$root\extension\engine\lib\CaptionOnly.ps1"
function New-RetryWords([string]$Text,[double]$Start,[double]$End){
    $tokens=@(ConvertTo-NormalizedWords $Text)
    for($i=0;$i -lt $tokens.Count;$i++){[pscustomobject]@{Text=$tokens[$i];Start=$Start+($End-$Start)*$i/$tokens.Count;End=$Start+($End-$Start)*($i+1)/$tokens.Count;Chapter=0;SubtitleTimingQuality='estimated';SubtitleTimingOrigin='retry-fixture'}}
}
function Test-RetryCase([string]$Expected,[string]$Initial,[string]$Fresh,[bool]$Accept,[string]$Fault='',[int]$Chapter=0){
    $texts=@('alpha bravo charlie delta echo foxtrot',$Expected,'golf hotel india juliet kilo lima')
    $refs=@(for($i=0;$i -lt 3;$i++){[pscustomobject]@{Index=$i+1;Text=$texts[$i];Start=900+$i*10;End=910+$i*10}})
    $before=$refs|ConvertTo-Json -Depth 8 -Compress
    $script:retryInitial=@(New-RetryWords $texts[0] 0 2)+@(New-RetryWords $Initial 2 6)+@(New-RetryWords $texts[2] 6 8)
    foreach($word in $script:retryInitial){$word.Chapter=$Chapter}
    $script:retryFresh=@(New-RetryWords $Fresh 0 4)
    $script:retryLocalCalls=0;$script:retryFault=$Fault
    $sources=@([pscustomobject]@{start=20.0;end=28.0})
    if($Chapter -eq 1){$sources=@([pscustomobject]@{start=0.0;end=1.0})+$sources}
    $selection=Select-PvsSubtitleReference $refs $script:retryInitial $sources -AllowEditedReference -AllowUnmatchedRanges -SkipUnverifiedCues -RecognizeReferenceWindow {
        param($source,$start,$end)
        if([Math]::Abs($start-22) -lt 0.000001 -and [Math]::Abs($end-26) -lt 0.000001){
            $script:retryLocalCalls++
            $fresh=@($script:retryFresh | ForEach-Object {$_.PSObject.Copy()})
            if($fresh.Count){switch($script:retryFault){nan {$fresh[0].Start=[double]::NaN};outside {$fresh[-1].End=5};overlap {$fresh[1].Start=$fresh[0].Start};chapter {$fresh[0].Chapter=1}}}
            return $fresh
        }
        foreach($word in $script:retryInitial){if($source.start+$word.Start -ge $start-0.000001 -and $source.start+$word.End -le $end+0.000001){$copy=$word.PSObject.Copy();$copy.Start+=$source.start-$start;$copy.End+=$source.start-$start;$copy.Chapter=0;$copy}}
    }
    $middle=@($selection.Cues|Where-Object Index -eq 2)
    if([bool]$middle.Count -ne $Accept -or $script:retryLocalCalls -ne 1){throw "LOCAL_RETRY_DECISION_WRONG:$Expected|$Fresh|$Accept|$script:retryLocalCalls"}
    if(($refs|ConvertTo-Json -Depth 8 -Compress) -cne $before){throw 'RETRY_MUTATED_REFERENCE_INPUT'}
    if($selection.EditedReference.Resolved -or @($selection.EditedReference.Cues|Where-Object Index -eq 2).Count){throw 'LOCAL_RETRY_CHANGED_AUTO_EDIT_PROOF'}
    if(-not $Accept){return}
    $cue=$middle[0]
    if($cue.Text -cne $Expected -or -not $cue.SubtitleReferenceLocalRetry -or $cue.Start -ne 22 -or $cue.End -ne 26 -or (Test-PvsSubtitleDtwCue $cue @{})){throw 'RETRY_TEXT_OFFSET_OR_DTW_PROOF_WRONG'}
    if(@($cue.WordTimings|Where-Object {$_.SubtitleTimingQuality -ne 'estimated' -or $_.SubtitleTimingOrigin -ne 'retry-fixture'}).Count){throw 'RETRY_LOST_TIMING_QUALITY_OR_ORIGIN'}
    $complete=Complete-PvsSubtitleReference $selection $selection.RecognitionWords $sources {throw 'RECOVERED_REFERENCE_SENT_TO_ASR'}
    $captions=@(New-PvsStandaloneCaptions $complete.Cues $sources @() 30 30)
    if((@(ConvertTo-NormalizedWords (($captions.Text) -join ' ')) -join '|') -cne (@(ConvertTo-NormalizedWords ($texts -join ' ')) -join '|')){throw 'LOCAL_RETRY_SRT_LOST_IN_FINAL_CAPTIONS'}
    if(@($captions|Where-Object {$_.PSObject.Properties['RecognitionSupplement'] -and $_.RecognitionSupplement}).Count){throw 'RECOVERED_SRT_REPORTED_AS_ASR'}
}
# Six omitted SRT cues from the Antarctica run; the original recovery window
# contains other ASR differences, but the new local sentence is identifiable.
$cases=@(
    @('nằm sâu khoảng 3 phẩy 7 đến 4 phẩy 1 kilomet dưới lớp băng.','năm sâu khoảng 3 7 4 1km dưới lớp bang','nằm sâu khoảng 3 phẩy 7 đến 4 phẩy 1 km dưới lớp bằng'),
    @('chịu được bức xạ mạnh,','giữ được bức sạ mạnh','chịu được bức xạ mạnh'),
    @('mực khổng lồ Nam Cực dài tới 10 mét.','mức khổng lồ được dài tới 10 m','mực khổng lồ nam cực dài tới 10 m'),
    @('Dãy núi này kéo dài khoảng 1200 kilomet,','dãy núi này kéo 1 200 km','dãy núi này kéo dài khoảng 1 200 km'),
    @('Toàn bộ dãy đang bị chôn vùi dưới lớp băng dày khoảng 2000 đến 4000 mét,','toàn bộ dãy đang trôn vui dưới lớp bang dày khoảng 2 000 4 000 m','toàn bộ dãy đang bị trôn vui dưới lớp bang dày khoảng 2 000 4 000 m'),
    @('tạo nên một tiếng ù địa chấn hầu như không ngừng nghỉ.','tạo nên 1 tiếng trấn hầu như không người nghỉ','tạo nên một tiếng ủ địa chấn hầu như không ngừng nghỉ')
)
foreach($case in $cases){Test-RetryCase $case[0] $case[1] $case[2] $true}
Test-RetryCase $cases[1][0] $cases[1][1] $cases[1][2] $true '' 1
Test-RetryCase $cases[1][0] $cases[1][1] '' $false
Test-RetryCase $cases[1][0] $cases[1][1] 'nhạc vang lên giữa cánh đồng' $false
Test-RetryCase $cases[1][0] $cases[1][1] 'lời thêm chịu được bức xạ mạnh' $false
Test-RetryCase $cases[1][0] $cases[1][1] 'chịu được bức xạ mạnh lời thêm' $false
foreach($fault in @('nan','outside','overlap','chapter')){
    $failed=$false
    try{Test-RetryCase $cases[1][0] $cases[1][1] $cases[1][2] $true $fault}catch{if($_.Exception.Message -eq 'SUBTITLE_REFERENCE_RETRY_TIMING_INVALID'){$failed=$true}else{throw}}
    if(-not $failed){throw "INVALID_LOCAL_RETRY_ACCEPTED:$fault"}
}
# Range-number identity preserves SRT values and marks a real/ambiguous value
# disagreement; it must not absorb ordinary text between separate quantities.
if($null -ne (Get-PvsSubtitleNumericSpan @('3','ngày','4') -RequireDigits)){throw 'ORDINARY_NUMERIC_CONTEXT_ABSORBED'}
$span=Get-PvsSubtitleNumericSpan @('3','phẩy','7','đến','4','phẩy','1') -RequireDigits
if($null -eq $span -or $span.Text -cne '3 phẩy 7 đến 4 phẩy 1'){throw 'NUMBER_RANGE_NOT_IDENTIFIED'}
# Long retained-neighbor context, including the foreign-name duplicate from
# caption 372. Preserve real extra words and reject repeats/numeric changes.
$left='còn ẩn giấu một dãy núi vô hình mang tên dãy núi Gamburtsev.'
$heard='giấu một dãi núi vô hình bằng tên dãi núi Gamberstheb'
$recognition=[pscustomobject]@{Words=@(New-RetryWords $heard 0 3);Surfaces=@()}
$inside=Get-PvsSubtitleContextInterior $recognition 2.5 4 $left ''
if(-not $inside.LeftMatched -or $inside.Start -ne 3){throw 'FOREIGN_NAME_TAIL_DUPLICATED'}
$extra=[pscustomobject]@{Words=@(New-RetryWords $heard 0 3)+@(New-RetryWords 'lời thêm thật' 3 3.9);Surfaces=@()}
$inside=Get-PvsSubtitleContextInterior $extra 2.5 3.9 $left ''
if(-not $inside.LeftMatched -or [Math]::Abs($inside.Start-3) -gt 0.000001){throw 'LONG_CONTEXT_SWALLOWED_REAL_EXTRA_SPEECH'}
$repeated=[pscustomobject]@{Words=@(New-RetryWords ($heard+' '+$heard) 0 6);Surfaces=@()}
if((Get-PvsSubtitleContextInterior $repeated 2.5 4 $left '').LeftMatched){throw 'LONG_REPEATED_CONTEXT_TRIMMED'}
$unrelated=[pscustomobject]@{Words=@(New-RetryWords ($heard -replace 'bằng','khác') 0 3);Surfaces=@()}
if((Get-PvsSubtitleContextInterior $unrelated 2.5 4 $left '').LeftMatched){throw 'LONG_UNRELATED_CONTEXT_TRIMMED'}
Write-Host 'SUBTITLE_RETRY_REFERENCE_OK:6 Antarctica cues;local retry before ASR;SRT-through-final-captions;range-numbers;unit-aliases;foreign-name-tail;real-extra-speech;empty;unrelated;repeat;bad-timing;offset;quality;shared-edit-proof'
