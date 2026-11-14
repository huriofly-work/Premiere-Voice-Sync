$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$root=Resolve-Path (Join-Path $PSScriptRoot '..\..')
. "$root\extension\engine\lib\Alignment.ps1"
. "$root\extension\engine\lib\Srt.ps1"
foreach($case in @(@(0,'không'),@(5,'năm'),@(15,'mười lăm'),@(21,'hai mươi mốt'),@(105,'một trăm linh năm'),@(1979,'một nghìn chín trăm bảy mươi chín'),@(2000,'hai nghìn'),@(2026,'hai nghìn không trăm hai mươi sáu'),@(2500000,'hai triệu năm trăm nghìn'))){if((ConvertTo-PvsSpokenInteger $case[0]) -ne $case[1]){throw "NUMBER_SPEECH_WRONG:$($case[0])"}}
$prompt=Get-PvsNumericCaptionPrompt 'Năm 1979, có 90%, 1,5 kg và 3.14 m; mã 007, 1080p, 1.000, 12/10.'
if($prompt -notmatch 'một nghìn chín trăm bảy mươi chín' -or $prompt -notmatch 'chín mươi phần trăm' -or $prompt -notmatch 'một phẩy năm' -or $prompt -notmatch 'ba phẩy một bốn' -or $prompt -notmatch '007, 1080p, 1.000, 12/10'){throw 'NUMERIC_PROMPT_NOT_SAFE'}
$text='Năm 1979, Alien mở đường.'
$words=@(ConvertTo-NormalizedWords $text)
$old=for($i=0;$i -lt $words.Count;$i++){[pscustomobject]@{Text=$words[$i];TargetWordIndex=$i;Start=100+$i*0.3;End=100+($i+1)*0.3;Chapter=0;Exact=$true}}
$cue=[pscustomobject]@{Index=34;Text=$text;Start=100;End=106;Chapter=0;WordTimings=@($old);Confidence=1.0}
$before=$cue | ConvertTo-Json -Depth 6 -Compress
$voice=@([pscustomobject]@{start=90;end=120})
$recognize={param($voice,$start,$end,$prompt)
    if($prompt -notmatch 'một nghìn chín trăm bảy mươi chín'){throw 'NUMERIC_PROMPT_MISSING'}
    $offset=0.6
    foreach($word in $words){$length=if($word -eq '1979'){2.0}else{0.3};[pscustomobject]@{Text=$word;Start=$offset;End=$offset+$length;Chapter=0};$offset+=$length}
}
$result=Repair-PvsNumericCaptionTimings @($cue) $voice $recognize
if(($result.Refined -join ',') -ne '34' -or $result.Review.Count -ne 0 -or [Math]::Abs($cue.CaptionWordTimings[1].End-$cue.CaptionWordTimings[1].Start-2) -gt 0.000001){throw 'NUMERIC_CAPTION_NOT_REFINED'}
$original=$cue | Select-Object Index,Text,Start,End,Chapter,WordTimings,Confidence | ConvertTo-Json -Depth 6 -Compress
if($original -ne $before){throw 'NUMERIC_REFINEMENT_CHANGED_EDIT_TIMING'}
$parts=@(Split-PvsVoiceAlignedCaptionCue $cue 20 30)
if(($parts.Text -join ' ') -ne $text -or $parts[-1].EndFrame -ne [Math]::Round($cue.CaptionEnd*30)){throw 'CAPTION_REFINED_TIMING_NOT_USED'}
$bad=$cue.PSObject.Copy();$bad.PSObject.Properties.Remove('CaptionStart');$bad.PSObject.Properties.Remove('CaptionEnd');$bad.PSObject.Properties.Remove('CaptionWordTimings')
$result=Repair-PvsNumericCaptionTimings @($bad) $voice {param($voice,$start,$end,$prompt) [pscustomobject]@{Text='wrong';Start=0;End=1;Chapter=0}}
if(($result.Review -join ',') -ne '34' -or $bad.PSObject.Properties['CaptionWordTimings']){throw 'UNVERIFIED_NUMBER_TIMING_ACCEPTED'}
$result=Repair-PvsNumericCaptionTimings @($bad) $voice {throw 'WRONG_LANGUAGE_RECOGNIZED'} -Language en
if($result.Refined.Count -ne 0){throw 'WRONG_LANGUAGE_NUMERIC_REFINEMENT'}
Write-Host 'NUMERIC_CAPTION_TIMING_OK:integer,decimal,percent;ambiguous-text-preserved;caption-only-fields;invalid-recognition-rejected'
$spokenWords=@('năm','một','nghìn','chín','trăm','bảy','mươi','chín','alien')
$evidence=for($i=0;$i -lt $spokenWords.Count;$i++){[pscustomobject]@{Text=$spokenWords[$i];Start=$i*0.2;End=($i+1)*0.2;Chapter=0}}
$joined=@(Join-PvsRecognizedNumericWords @('năm','1979','alien') $evidence)
if(($joined.Text -join ' ') -ne 'năm 1979 alien' -or $joined[1].Start -ne 0.2 -or $joined[1].End -ne 1.6){throw 'SPOKEN_NUMBER_SPAN_LOST'}
$evidence=@([pscustomobject]@{Text='năm';Start=0;End=0.2;Chapter=0},[pscustomobject]@{Text='2';Start=0.2;End=0.4;Chapter=0},[pscustomobject]@{Text='122';Start=0.4;End=0.9;Chapter=0},[pscustomobject]@{Text='một';Start=0.9;End=1.1;Chapter=0})
if((@(Join-PvsRecognizedNumericWords @('năm','2122','một') $evidence).Text -join ' ') -ne 'năm 2122 một'){throw 'SPLIT_NUMBER_NOT_JOINED'}
$evidence[2].Text='123'
if(@(Join-PvsRecognizedNumericWords @('năm','2122','một') $evidence).Count -ne 4){throw 'WRONG_NUMBER_JOINED'}
$joined=@(Join-PvsRecognizedNumericWords @('năm','1979','khác') @(for($i=0;$i -lt $spokenWords.Count;$i++){[pscustomobject]@{Text=$spokenWords[$i];Start=$i*0.2;End=($i+1)*0.2;Chapter=0}}))
if($joined.Count -ne 9){throw 'UNANCHORED_NUMBER_JOINED'}
Write-Host 'NUMERIC_SPOKEN_MAPPING_OK:spoken-and-split-digits;measured-span-preserved;wrong-number-and-context-rejected'
