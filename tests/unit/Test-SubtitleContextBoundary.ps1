$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$root=Resolve-Path (Join-Path $PSScriptRoot '..\..')
. "$root\extension\engine\lib\CaptionOnly.ps1"
. "$root\extension\engine\lib\SubtitleTiming.ps1"

function New-ContextWords([string]$Text){
    $texts=@(ConvertTo-NormalizedWords $Text)
    [pscustomobject]@{Words=@(for($i=0;$i -lt $texts.Count;$i++){[pscustomobject]@{Text=$texts[$i];Start=$i*0.2;End=($i+1)*0.2;Chapter=0}});Surfaces=@()}
}
$left='một giấc mộng dài giữa vũ trụ vô tận';$right='Vậy còn bạn bạn tin vào giả thuyết nào hơn'
$raw=New-ContextWords 'một giấc mộng dài giữa vũ trụ vô tật Vậy con bạn bạn tin vào giả thuyết nào hơn'
$inside=Get-PvsSubtitleContextInterior $raw 1.7 1.9 $left $right
if($inside.Start -ne 1.8 -or $inside.End -ne 1.8){throw 'NEIGHBOR_SPELLING_TAIL_WOULD_BECOME_SUPPLEMENT'}
$positive=New-ContextWords 'một giấc mộng dài giữa vũ trụ vô tận tật Vậy còn bạn bạn tin vào giả thuyết nào hơn'
$inside=Get-PvsSubtitleContextInterior $positive 1.7 2.1 $left $right
if([Math]::Abs($inside.Start-1.8) -gt 0.000001 -or [Math]::Abs($inside.End-2.0) -gt 0.000001){throw 'REAL_ADDITIONAL_WORD_SWALLOWED'}
$different=New-ContextWords 'một giấc mộng dài giữa vũ trụ vô khác Vậy còn bạn bạn tin vào giả thuyết nào hơn'
$inside=Get-PvsSubtitleContextInterior $different 1.7 1.9 $left $right
if($inside.Start -ne 1.7){throw 'UNRELATED_WORD_MATCHED_AS_NEIGHBOR_VARIANT'}
$repeat=New-ContextWords 'một giấc mộng dài giữa vũ trụ vô tật một giấc mộng dài giữa vũ trụ vô tận'
$inside=Get-PvsSubtitleContextInterior $repeat 1.7 2.1 $left ''
if($inside.Start -ne 1.7){throw 'AMBIGUOUS_NEIGHBOR_REPEAT_TRIMMED'}

$selection=[pscustomobject]@{Cues=@([pscustomobject]@{Index=287;Text=$left;Start=10;End=11;Chapter=0},[pscustomobject]@{Index=291;Text=$right;Start=11.6;End=13;Chapter=0});UnverifiedRanges=@([pscustomobject]@{sourceIndex=0;start=11;end=13.5;cueIndices=@(288,289,290,292)})}
$sources=@([pscustomobject]@{start=10;end=13.5})
$words=@([pscustomobject]@{Text='tật';Start=1.0;End=1.4;Chapter=0},[pscustomobject]@{Text='thanks';Start=3.1;End=3.4;Chapter=0})
$result=Complete-PvsSubtitleReference $selection $words $sources {
    param($source,$start,$end,$chapter)
    if($start -eq 11){return [pscustomobject]@{Cues=@();CoveredByReferenceContext=$true}}
    [pscustomobject]@{Index=1;Text='Xin cảm ơn.';Start=13.1;End=13.4;Chapter=0;WordTimings=@()}
}
if($result.Cues.Count -ne 3 -or @($result.Cues | Where-Object Text -eq 'tật').Count -or $result.EmptyRanges.Count -or $result.ContextCoveredRanges.Count -ne 1){throw 'CONTEXT_ONLY_GAP_REPORTED_AS_MISSING_SPEECH'}
if($result.SupplementRanges.Count -ne 1 -or $result.SupplementRanges[0].start -ne 13.1 -or $result.SupplementRanges[0].end -ne 13.4){throw 'SUPPLEMENT_MARKER_NOT_BOUNDED_TO_GENERATED_SPEECH'}
if(($selection.Cues.Text -join '|') -cne ($left+'|'+$right)){throw 'NEIGHBOR_REFERENCE_TEXT_MUTATED'}
# Production adapter must use the overlay edges that created the gap, and
# mark a fully consumed neighbor context without invoking audio rejection.
$parseTokens=$null;$parseErrors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile("$root\extension\engine\run-captions.ps1",[ref]$parseTokens,[ref]$parseErrors)
$node=$ast.Find({param($n);$n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Invoke-CaptionReferenceWindow'},$true)
Invoke-Expression $node.Extent.Text
$script:characterMode=$false;$script:allSilences=New-Object System.Collections.Generic.List[object];$script:referenceSupplementInvocationCount=0
$script:rawBoundary=$raw
function Invoke-CaptionReferenceSlice {param($source,$start,$end,$chapter,$kind);$script:rawBoundary}
$script:referenceSelection=[pscustomobject]@{Cues=@([pscustomobject]@{Index=1;Text=$left;Start=0;End=1.9;CaptionEnd=1.7;Chapter=0},[pscustomobject]@{Index=2;Text=$right;Start=1.8;CaptionStart=1.9;End=4;Chapter=0})}
$source=[pscustomobject]@{start=0;end=4};$script:sources=@($source)
$recognized=Invoke-CaptionReferenceWindow $source 1.7 1.9 0 supplement
if(-not $recognized.CoveredByReferenceContext -or $recognized.Words.Count){throw 'PRODUCTION_ADAPTER_DUPLICATES_REPAIRED_REFERENCE_EDGE'}
$shifted=$raw | ConvertTo-Json -Depth 5|ConvertFrom-Json
for($i=9;$i -lt $shifted.Words.Count;$i++){$shifted.Words[$i].Start+=0.2;$shifted.Words[$i].End+=0.2}
$script:rawBoundary=$shifted
$recognized=Invoke-CaptionReferenceWindow $source 1.7 1.9 0 supplement
if(-not $recognized.CoveredByReferenceContext -or $recognized.Words.Count){throw 'EMPTY_SPACE_BETWEEN_CONFIRMED_NEIGHBORS_FLAGGED'}
Write-Host 'SUBTITLE_CONTEXT_BOUNDARY_OK:one-spelling-edge;unique-context;genuine-extra-word;unrelated-word;repeat-ambiguity;context-only-no-false-marker;outro-kept;actual-supplement-bounds'
