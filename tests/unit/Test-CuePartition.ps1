$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$root=Resolve-Path (Join-Path $PSScriptRoot '..\..')
. "$root\extension\engine\lib\Alignment.ps1"
# Isolate cue partitioning; lexical DP has separate reference tests.
function Get-SequentialWordMapping {param($TargetWords,$RecognizedWords);return @(0,-1,1,2,3,4)}
$cues=@(
    [pscustomobject]@{Text='Xin chao, ban.';Start=0;End=1},
    [pscustomobject]@{Text='';Start=1;End=2},
    [pscustomobject]@{Text='Tiep theo.';Start=2;End=3},
    [pscustomobject]@{Text='Het.';Start=3;End=4}
)
$words=@(
    [pscustomobject]@{Text='xin';Chapter=0;Start=0.1;End=0.2},
    [pscustomobject]@{Text='khac';Chapter=0;Start=0.3;End=0.4},
    [pscustomobject]@{Text='tiep';Chapter=1;Start=0.1;End=0.2},
    [pscustomobject]@{Text='theo';Chapter=1;Start=0.3;End=0.4},
    [pscustomobject]@{Text='het';Chapter=1;Start=0.5;End=0.6}
)
$voices=@([pscustomobject]@{start=10},[pscustomobject]@{start=20})
$result=@(Align-CuesToRecognizedWords -Cues $cues -RecognizedWords $words -VoiceClips $voices)
if($result.Count -ne 4){throw 'CUE_PARTITION_COUNT'}
if($result[0].Text -cne $cues[0].Text -or $result[0].Confidence -ne 0.5 -or $result[0].Start -ne 10.1 -or $result[0].End -ne 10.4){throw 'CUE_PARTITION_MISSING_SUBSTITUTED_WORD'}
if(($result[0].WordTimings.TargetWordIndex -join ',') -ne '0,2' -or ($result[0].WordTimings.Text -join ',') -ne 'xin,ban'){throw 'CUE_PARTITION_LOCAL_WORD_INDEX'}
if($null -ne $result[1].Start -or $result[1].Chapter -ne -1 -or $result[1].WordTimings.Count -ne 0 -or $result[1].Confidence -ne 0){throw 'CUE_PARTITION_EMPTY_CUE'}
if($result[2].Chapter -ne 1 -or $result[2].Confidence -ne 1 -or $result[2].Start -ne 20.1 -or $result[2].End -ne 20.4 -or ($result[2].WordTimings.TargetWordIndex -join ',') -ne '0,1'){throw 'CUE_PARTITION_NEXT_CHAPTER'}
if($result[3].Start -ne 20.5 -or $result[3].End -ne 20.6 -or $result[3].WordTimings[0].TargetWordIndex -ne 0){throw 'CUE_PARTITION_LAST_CUE'}
foreach($i in 0..3){if($result[$i].Index -ne $i+1 -or $result[$i].OriginalStart -ne $cues[$i].Start -or $result[$i].OriginalEnd -ne $cues[$i].End){throw 'CUE_PARTITION_ORIGINAL_FIELDS_CHANGED'}}
Write-Host 'CUE_PARTITION_OK:deleted-word;substitution-confidence;empty-cue;local-word-indices;chapter-offset;last-cue;original-fields'
