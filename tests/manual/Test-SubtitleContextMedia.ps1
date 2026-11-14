param([Parameter(Mandatory)][string]$AuditRoot,[Parameter(Mandatory)][string]$OutputRoot)
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$root=Resolve-Path (Join-Path $PSScriptRoot '..\..')
. "$root\extension\engine\lib\Srt.ps1"
. "$root\extension\engine\lib\Alignment.ps1"
. "$root\extension\engine\lib\CaptionOnly.ps1"
. "$root\extension\engine\lib\SubtitleTiming.ps1"
. "$root\extension\engine\lib\Native.ps1"
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $root 'extension\engine\run-captions.ps1'),[ref]$tokens,[ref]$errors)
if($errors.Count){throw 'PRODUCTION_SCRIPT_PARSE_FAILED'}
foreach($name in @('Invoke-CaptionRecognition','Convert-CaptionRecognitionWithTiming','Invoke-CaptionReferenceSlice','Invoke-CaptionReferenceWindow')){
    $node=$ast.Find({param($n);$n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name},$true)
    if(-not $node){throw "PRODUCTION_FUNCTION_MISSING:$name"}
    Invoke-Expression $node.Extent.Text
}
New-Item -ItemType Directory -Path $OutputRoot -Force | Out-Null
$ffmpeg=Join-Path $root 'extension\engine\runtime\bin\ffmpeg.exe'
$whisper=Join-Path $root 'extension\engine\runtime\bin\whisper-cli.exe';$cpuWhisper=$whisper
$model=Join-Path $root 'extension\engine\runtime\models\ggml-large-v3-turbo.bin'
$engine=[pscustomobject]@{model='small'};$backendName='cpu';$backendLabel='CPU';$backendArguments=@('--no-gpu');$detectedLanguage='vi';$characterMode=$false;$fps=30.0
$cases=@(
    [pscustomobject]@{N=32;Start=251.925;End=259.69;GapStart=254.925;GapEnd=256.69;Forbidden='ghiền mì gõ'},
    [pscustomobject]@{N=33;Start=392.006;End=398.549;GapStart=395.006;GapEnd=395.549;Forbidden='ghiền mì gõ'},
    [pscustomobject]@{N=34;Start=408.07;End=414.489;GapStart=411.07;GapEnd=411.489;Forbidden='ghiền mì gõ'},
    [pscustomobject]@{N=35;Start=96.897;End=103.247;GapStart=99.897;GapEnd=100.247;Forbidden='khi mà các bạn'},
    [pscustomobject]@{N=36;Start=169.087;End=175.597;GapStart=172.087;GapEnd=172.597;Forbidden='hẹn gặp lại'}
)
$results=New-Object System.Collections.Generic.List[object]
$referenceSelection=$null
$references=Get-Content (Join-Path $AuditRoot 'references.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$neighbors=@{32=@(73,74);33=@(115,116);34=@(118,119);35=@(29,30);36=@(52,53)}
foreach($case in $cases){
    $folder=Join-Path $OutputRoot ('case-'+$case.N);New-Item -ItemType Directory -Path $folder -Force | Out-Null
    $job=[pscustomobject]@{outputFolder=$folder}
    $source=[pscustomobject]@{start=$case.Start;end=$case.End;path=(Join-Path $AuditRoot ('voice-ranges\range-{0:000}.wav' -f $case.N))};$sources=@($source)
    $near=$neighbors[[int]$case.N]
    $rightText=$references[$near[1]-1].Text+' '+$references[$near[1]].Text
    $referenceSelection=[pscustomobject]@{Cues=@([pscustomobject]@{Text=$references[$near[0]-1].Text;Start=$case.Start;End=$case.GapStart},[pscustomobject]@{Text=$rightText;Start=$case.GapEnd;End=$case.End})}
    $referenceSupplementInvocationCount=0;$captionTimingWindowInvocationCount=0;$captionTimingAcousticBoundaries=0
    $captionTimingRetryRanges=New-Object System.Collections.Generic.List[object];$captionTimingEstimatedRanges=New-Object System.Collections.Generic.List[object];$recognitionRejectedRanges=New-Object System.Collections.Generic.List[object]
    $allSilences=New-Object System.Collections.Generic.List[object]
    foreach($q in @(Get-PvsCaptionQuiet $ffmpeg $source.path)){$allSilences.Add([pscustomobject]@{Start=$source.start+$q.Start;End=$source.start+$q.End;Duration=$q.Duration})}
    $recognition=Invoke-CaptionReferenceWindow $source $case.GapStart $case.GapEnd 0 supplement
    $text=@($recognition.Surfaces | ForEach-Object {$_.Text}) -join ' '
    if($text.ToLowerInvariant().Contains($case.Forbidden)){throw "HALLUCINATION_SURVIVED:$($case.N):$text"}
    $results.Add([pscustomobject]@{Case=$case.N;Start=$case.GapStart;End=$case.GapEnd;Text=$text;Words=$recognition.Words.Count;Rejected=$recognitionRejectedRanges.Count;Windows=$referenceSupplementInvocationCount})
    Write-Host ('REAL_CONTEXT_CASE_OK:'+ $case.N+';words='+$recognition.Words.Count+';text='+$text)
}
# Positive control: actual outro/thanks audio from the same saved project.
$voice=Get-Content (Join-Path $AuditRoot 'voice-map.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$cta=@($voice | Where-Object Name -like 'Xin cảm ơn*')[0]
if(-not $cta){throw 'REAL_CTA_SOURCE_NOT_FOUND'}
$folder=Join-Path $OutputRoot 'real-cta';New-Item -ItemType Directory -Path $folder -Force | Out-Null
$wave=Join-Path $folder 'input.wav'
& $ffmpeg -y -hide_banner -loglevel error -ss $cta.In.ToString('0.########',[Globalization.CultureInfo]::InvariantCulture) -i $cta.Path -t 8 -ar 16000 -ac 1 -c:a pcm_s16le $wave
if($LASTEXITCODE -ne 0){throw 'REAL_CTA_AUDIO_FAILED'}
$length=Get-PvsPcmWaveDuration $wave
$job=[pscustomobject]@{outputFolder=$folder};$source=[pscustomobject]@{start=0.0;end=$length;path=$wave};$sources=@($source)
$referenceSupplementInvocationCount=0;$allSilences.Clear()
$referenceSelection=$null
$recognition=Invoke-CaptionReferenceWindow $source 0 $length 0 supplement
$text=@($recognition.Surfaces | ForEach-Object {$_.Text}) -join ' '
if(-not $recognition.Words.Count -or $text -notmatch 'cảm ơn'){throw "REAL_CTA_LOST:$text"}
$results.Add([pscustomobject]@{Case='real-cta';Start=0;End=$length;Text=$text;Words=$recognition.Words.Count;Windows=$referenceSupplementInvocationCount})
$results.ToArray() | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $OutputRoot 'verified.json') -Encoding UTF8
Write-Host 'REAL_CONTEXT_MEDIA_OK:5 bad-gap regressions;actual thanks/CTA retained;production functions;CPU small;offline source-audio reconstruction;no Premiere actions'
