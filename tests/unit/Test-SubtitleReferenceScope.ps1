$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$root=Resolve-Path (Join-Path $PSScriptRoot '..\..')
. "$root\extension\engine\lib\Srt.ps1"
. "$root\extension\engine\lib\Alignment.ps1"
. "$root\extension\engine\lib\CaptionOnly.ps1"
$texts=@('Alpha bravo charlie delta echo foxtrot.','Golf hotel india juliet kilo lima.','Mike november oscar papa quebec romeo.','Sierra tango uniform victor whiskey xray.')
$cues=for($i=0;$i -lt $texts.Count;$i++){[pscustomobject]@{Index=$i+1;Text=$texts[$i];Start=900-$i*100;End=950-$i*100}}
function New-Words {param([string]$Text,[int]$Chapter=0) $lex=@(ConvertTo-NormalizedWords $Text);for($i=0;$i -lt $lex.Count;$i++){[pscustomobject]@{Text=$lex[$i];Start=$i*0.3;End=($i+1)*0.3;Chapter=$Chapter}}}
function Expect-Rejection {param([object[]]$Reference,[object[]]$Words,[object[]]$Sources=@([pscustomobject]@{start=0;end=20})) $message='';try{Select-PvsSubtitleReference $Reference $Words $Sources | Out-Null}catch{$message=$_.Exception.Message};if($message -notmatch 'SUBTITLE_REFERENCE_(SCOPE_|WORD_UNALIGNED|MISMATCH)'){throw "EXPECTED_SCOPE_REJECTION:$message"}}
$before=$cues | ConvertTo-Json -Depth 5 -Compress
foreach($range in @(@(0,1),@(1,2),@(2,3),@(0,3))) {
    $words=@(New-Words ($texts[$range[0]..$range[1]] -join ' '))
    $result=Select-PvsSubtitleReference $cues $words @([pscustomobject]@{start=100;end=120})
    if($result.Ranges[0].firstCue -ne $range[0]+1 -or $result.Ranges[0].lastCue -ne $range[1]+1){throw 'SCOPE_RANGE_WRONG'}
    if(($result.Cues.Text -join ' ') -ne ($texts[$range[0]..$range[1]] -join ' ')){throw 'SCOPE_TEXT_CHANGED'}
    if($result.Cues[0].Start -ne 100 -or $result.Cues[0].WordTimings[0].TargetWordIndex -ne 0){throw 'SCOPE_USED_OLD_TIMECODES'}
    if($result.OutsideCueCount -ne 4-$result.SelectedCueCount){throw 'SCOPE_COUNTS_WRONG'}
}
if(($cues | ConvertTo-Json -Depth 5 -Compress) -ne $before){throw 'SCOPE_MUTATED_REFERENCE'}
Expect-Rejection $cues @(New-Words 'Completely unrelated speech cannot select these references at all.')
$duplicate=@($cues[1].PSObject.Copy(),$cues[2].PSObject.Copy(),$cues[1].PSObject.Copy(),$cues[2].PSObject.Copy())
Expect-Rejection $duplicate @(New-Words ($texts[1..2] -join ' '))
Expect-Rejection $cues @(New-Words 'hotel india juliet kilo lima. Mike november oscar papa quebec romeo.')
Expect-Rejection $cues @(New-Words 'Golf hotel india juliet kilo lima. Mike november oscar papa')
Expect-Rejection $cues @(New-Words ($texts[0]+' '+$texts[2]+' '+$texts[3]))
$multi=@((New-Words $texts[0] 0)) + @((New-Words $texts[3] 1))
$sources=@([pscustomobject]@{start=10;end=12},[pscustomobject]@{start=30;end=32})
$result=Select-PvsSubtitleReference $cues $multi $sources
if(($result.Cues.Index -join ',') -ne '1,4' -or $result.Cues[1].Start -ne 30 -or $result.OutsideCueCount -ne 2){throw 'DISJOINT_SCOPE_WRONG'}
Expect-Rejection $cues (@((New-Words $texts[3] 0))+@((New-Words $texts[0] 1))) $sources
$cjk=@([pscustomobject]@{Index=1;Text='第一句。';Start=0;End=1},[pscustomobject]@{Index=2;Text='第二段字幕测试。';Start=1;End=2})
$chars=@(Get-PvsSubtitleLexicalWords $cjk[1].Text $true)
$words=for($i=0;$i -lt $chars.Count;$i++){[pscustomobject]@{Text=$chars[$i];Start=$i*0.2;End=($i+1)*0.2;Chapter=0}}
$result=Select-PvsSubtitleReference $cjk $words @([pscustomobject]@{start=0;end=5}) -CharacterMode $true -Language zh
if($result.Ranges[0].firstCue -ne 2 -or $result.Cues[0].Text -ne $cjk[1].Text){throw 'CJK_SCOPE_WRONG'}
function New-EdgeJson {param([double]$End,[bool]$Overrun=$false)
    $items=@([pscustomobject]@{text='begin';offsets=[pscustomobject]@{from=1000;to=1500}},[pscustomobject]@{text='ending';offsets=[pscustomobject]@{from=($End-0.3)*1000;to=$End*1000}})
    if($Overrun){$items+= [pscustomobject]@{text='word';offsets=[pscustomobject]@{from=20100;to=20500}}}
    [pscustomobject]@{transcription=$items}
}
$quiet=@([pscustomobject]@{Start=10;End=10.3;Duration=0.3})
$edge=Repair-PvsSubtitleRecognitionEdge (New-EdgeJson 19.9) 20 $quiet {throw 'UNNECESSARY_EDGE_RETRY'}
if($edge.Retried){throw 'NORMAL_EDGE_RETRIED'}
$edge=Repair-PvsSubtitleRecognitionEdge (New-EdgeJson 19.9 $true) 20 $quiet {
    param($cut,$length)
    if([Math]::Abs($cut-10.15) -gt 0.000001 -or [Math]::Abs($length-9.85) -gt 0.000001){throw 'EDGE_WINDOW_WRONG'}
    New-EdgeJson 9.75
}
$words=@((Convert-PvsSubtitleRecognition $edge.Json 0 20).Words)
if(-not $edge.Retried -or $words[-1].End -gt 20 -or [Math]::Abs($words[-1].End-19.9) -gt 0.000001 -or $words[0].Start -ne 1){throw 'EDGE_RETRY_OFFSET_WRONG'}
$quiet=@([pscustomobject]@{Start=23.7;End=24.1;Duration=0.4},[pscustomobject]@{Start=38;End=40;Duration=2})
$edge=Repair-PvsSubtitleRecognitionEdge (New-EdgeJson 25) 40 $quiet {param($cut,$length) New-EdgeJson (37.9-$cut)} -RequireCompleteTail $true
if(-not $edge.Retried -or [Math]::Abs($edge.Json.transcription[-1].offsets.to/1000-37.9) -gt 0.000001){throw 'MISSING_TAIL_NOT_RECOVERED'}
Repair-PvsSubtitleRecognitionEdge (New-EdgeJson 25) 40 @([pscustomobject]@{Start=25;End=40;Duration=15}) {throw 'SILENT_TAIL_RETRIED'} -RequireCompleteTail $true | Out-Null
$failed=$false
try{Repair-PvsSubtitleRecognitionEdge (New-EdgeJson 25) 40 $quiet {param($cut,$length) New-EdgeJson (26-$cut)} -RequireCompleteTail $true | Out-Null}catch{if($_.Exception.Message -match 'SUBTITLE_RECOGNITION_TAIL_UNVERIFIED'){$failed=$true}else{throw}}
if(-not $failed){throw 'UNVERIFIED_TAIL_ACCEPTED'}
$failed=$false
try{Repair-PvsSubtitleRecognitionEdge (New-EdgeJson 25) 40 @() {throw 'UNSAFE_WINDOW_USED'} -RequireCompleteTail $true | Out-Null}catch{if($_.Exception.Message -match 'SUBTITLE_RECOGNITION_TAIL_UNVERIFIED'){$failed=$true}else{throw}}
if(-not $failed){throw 'UNSAFE_TAIL_WINDOW_ACCEPTED'}
Write-Host 'SUBTITLE_REFERENCE_SCOPE_OK:prefix,middle,suffix,full,offset,disjoint,CJK;ambiguous,partial,missing,mismatch,order rejected'
Write-Host 'SUBTITLE_RECOGNITION_EDGE_OK:normal,silent-tail,overrun,missing-tail,offset;unverified/unsafe rejected'
