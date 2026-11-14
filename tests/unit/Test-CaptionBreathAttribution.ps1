$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$root=Resolve-Path (Join-Path $PSScriptRoot '..\..')
. "$root\extension\engine\lib\Srt.ps1"
. "$root\extension\engine\lib\Alignment.ps1"
$text='Hôm nay, chúng ta sẽ dựa vào các chi tiết trong loạt phim Alien để phân tích lại con tàu Engineer bí ẩn này.'
$times=@(@(63.4,63.65),@(63.65,63.96),@(63.96,64.08),@(64.08,64.19),@(64.19,64.71),@(64.71,65.02),@(65.02,65.27),@(65.27,65.71),@(65.71,65.83),@(65.83,66.08),@(66.08,66.4),@(66.4,66.79),@(66.79,67),@(67,67.53),@(67.53,67.62),@(67.62,67.89),@(67.89,68.16),@(68.16,68.44),@(68.44,68.6),@(68.6,68.86),@(68.86,69.48),@(69.48,69.71),@(69.71,69.91),@(69.91,70.3))
$tokens=@(ConvertTo-NormalizedWords $text)
$timings=for($i=0;$i -lt $tokens.Count;$i++){[pscustomobject]@{Text=$tokens[$i];TargetWordIndex=$i;Start=$times[$i][0];End=$times[$i][1];Chapter=0;Exact=$true}}
$cue=[pscustomobject]@{Index=16;Text=$text;Start=63.4;End=70.3;Chapter=0;WordTimings=@($timings)}
$before=$cue | ConvertTo-Json -Depth 6 -Compress
# Measured silence from the supplied voice. The exported caption ended at
# 64.264 (29.97 fps), its center. ASR puts "chung ta" early inside this pause.
$silences=@([pscustomobject]@{Start=63.084943;End=63.682472;Duration=0.597528},[pscustomobject]@{Start=64.102086;End=64.428073;Duration=0.325986})
$parts=@(Split-PvsVoiceAlignedCaptionCue $cue 42 (30000.0/1001) $silences)
if(($parts.Text -join ' ') -ne $text -or @($parts | Where-Object {$_.Text.Length -gt 42}).Count){throw 'OPENING_BREATH_TEXT_OR_LIMIT_FAILED'}
if($parts[0].Text -eq 'Hôm nay, chúng ta' -or $parts[0].End -le 65.0){throw 'PUNCTUATION_PAUSE_ASSIGNED_AFTER_FOLLOWING_WORDS'}
if(($cue | ConvertTo-Json -Depth 6 -Compress) -ne $before){throw 'BREATH_ATTRIBUTION_CHANGED_EDIT_TIMING'}
# Same supplied voice, cue 9. The 298 ms pause after Engineer is detected,
# but the word's ASR endpoint overshoots its center by 288 ms.
$engineerText='Đây là tàu của người Engineer về sau được gọi là Derelict, tức “con tàu bỏ hoang”.'
$engineerTimes=@(@(37.74,38.04),@(38.04,38.22),@(38.22,38.46),@(38.46,38.81),@(38.81,39.27),@(39.27,40.08),@(40.08,40.17),@(40.17,40.26),@(40.26,40.74),@(40.74,41.13),@(41.13,41.22),@(41.22,41.87),@(41.87,42.13),@(42.13,42.30),@(42.30,42.54),@(42.54,42.78),@(42.78,43.30))
$engineerWords=@(ConvertTo-NormalizedWords $engineerText)
$engineerTimings=for($i=0;$i -lt $engineerWords.Count;$i++){[pscustomobject]@{Text=$engineerWords[$i];TargetWordIndex=$i;Start=$engineerTimes[$i][0];End=$engineerTimes[$i][1];Chapter=0;Exact=$true}}
$engineerCue=[pscustomobject]@{Index=9;Text=$engineerText;Start=37.74;End=43.30;Chapter=0;WordTimings=@($engineerTimings)}
$engineerBefore=$engineerCue | ConvertTo-Json -Depth 6 -Compress
$engineerSilences=@([pscustomobject]@{Start=37.473311;End=38.020794;Duration=0.547483},[pscustomobject]@{Start=39.643061;End=39.941497;Duration=0.298435},[pscustomobject]@{Start=41.431678;End=41.848889;Duration=0.417211},[pscustomobject]@{Start=41.918639;End=42.094104;Duration=0.175465},[pscustomobject]@{Start=43.011519;End=43.883605;Duration=0.872086})
$expected=@('Đây là tàu của người Engineer','về sau được gọi là Derelict,','tức “con tàu bỏ hoang”.')
foreach($fps in @(30,(30000.0/1001))){
    $parts=@(Split-PvsVoiceAlignedCaptionCue $engineerCue 42 $fps $engineerSilences)
    if(($parts.Text -join '|') -ne ($expected -join '|')){throw "ENGINEER_MEASURED_BREATH_REJECTED:$($parts.Text -join '|')"}
    $pauseFrame=[int][Math]::Round(((39.643061+39.941497)/2)*$fps)
    if($parts[0].EndFrame -ne $pauseFrame -or $parts[1].StartFrame -ne $pauseFrame){throw 'ENGINEER_BREATH_NOT_USED_FOR_TIMESTAMP'}
}
if(($engineerCue | ConvertTo-Json -Depth 6 -Compress) -ne $engineerBefore){throw 'ENGINEER_BREATH_CHANGED_EDIT_TIMING'}
$baseline=@(Get-PvsCaptionTextChunks $engineerText 42 $engineerTimings @())
foreach($unrelated in @(
    [pscustomobject]@{Start=39.40;End=39.61;Duration=0.21}, # inside word, not at its edge
    [pscustomobject]@{Start=39.83;End=39.92;Duration=0.09}, # too short to verify as breath
    [pscustomobject]@{Start=30.0;End=30.5;Duration=0.5}    # unrelated timeline region
)){
    $negative=@(Get-PvsCaptionTextChunks $engineerText 42 $engineerTimings @($unrelated))
    if(($negative.Text -join '|') -ne ($baseline.Text -join '|')){throw 'UNVERIFIED_VALLEY_USED_AS_ENGINEER_BREATH'}
}
Write-Host 'CAPTION_BREATH_ATTRIBUTION_OK:short-prefix-pause-not-stolen;Engineer-pause-with-drift;30-and-29.97fps;edit-timing-preserved'
