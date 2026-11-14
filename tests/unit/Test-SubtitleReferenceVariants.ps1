$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$root=Resolve-Path (Join-Path $PSScriptRoot '..\..')
. "$root\extension\engine\lib\Srt.ps1"
. "$root\extension\engine\lib\Alignment.ps1"
. "$root\extension\engine\lib\CaptionOnly.ps1"
$script:checks=0
function New-Case {
    param([string[]]$Texts,[string[]]$Heard)
    $cues=for ($i=0;$i -lt $Texts.Count;$i++) { [pscustomobject]@{Index=$i+1;Text=$Texts[$i];Start=100+$i;End=101+$i} }
    $words=for ($i=0;$i -lt $Heard.Count;$i++) { [pscustomobject]@{Text=$Heard[$i];Start=$i*0.3;End=$i*0.3+0.2;Chapter=0} }
    return [pscustomobject]@{Cues=@($cues);Words=@($words);Sources=@([pscustomobject]@{start=10.0;end=40.0})}
}
function Expect-Failure {
    param($Case,[string]$Language='vi')
    $errorText=''
    try { Align-PvsSubtitleReference -Cues $Case.Cues -Words $Case.Words -Sources $Case.Sources -Language $Language | Out-Null } catch { $errorText=$_.Exception.Message }
    if ($errorText -notmatch '^SUBTITLE_REFERENCE_(MISMATCH|WORD_UNALIGNED|CROSSES_SELECTION_GAP)') { throw "EXPECTED_REFERENCE_REJECTION:$errorText" }
    $script:checks++
}
$texts=@('Mà tiếng kêu khó nghe.','Be…','Be…','Be…','Nghe nhiều khó chịu.')
$heard=@('mà','tiếng','kêu','khó','nghe','b','b','b','nghe','nhiều','khó','chịu')
$case=New-Case -Texts $texts -Heard $heard
$before=@(Align-CuesToRecognizedWords -Cues $case.Cues -RecognizedWords $case.Words -VoiceClips $case.Sources)
$aligned=@(Align-PvsSubtitleReference -Cues $case.Cues -Words $case.Words -Sources $case.Sources)
if (@($aligned | Where-Object ReferenceReviewRequired).Count -ne 3) { throw 'B_VARIANT_NOT_REVIEWED' }; $script:checks++
if (($aligned.Text -join ' ') -ne ($texts -join ' ')) { throw 'REFERENCE_TEXT_CHANGED' }; $script:checks++
for ($i=0;$i -lt $aligned.Count;$i++) {
    if ($aligned[$i].Start -ne $before[$i].Start -or $aligned[$i].End -ne $before[$i].End -or $aligned[$i].Confidence -ne $before[$i].Confidence) { throw 'VARIANT_INVENTED_TIMING_OR_CONFIDENCE' }
}; $script:checks++
$caption=@(New-PvsStandaloneCaptions -Cues $aligned -Sources $case.Sources -Silences @() -MaxCharacters 42 -FrameRate 30)
if (($caption.Text -join ' ') -ne ($texts -join ' ')) { throw 'VARIANT_CAPTION_CHANGED_TEXT' }; $script:checks++
$accentCase=New-Case -Texts @('Vậy mà vẫn thích à?','Đừng đùa!','Nuôi lợn còn hơn!') -Heard @('vậy','mà','vẫn','thích','à','đừng','đua','nuôi','lợn','còn','hơn')
$accent=@(Align-PvsSubtitleReference -Cues $accentCase.Cues -Words $accentCase.Words -Sources $accentCase.Sources)
if (-not $accent[1].ReferenceReviewRequired -or $accent[1].Text -ne 'Đừng đùa!' -or $accent[1].Confidence -ne 0.5) { throw 'ACCENT_VARIANT_FAILED' }; $script:checks++
Expect-Failure -Case $case -Language 'en'
$wrong=New-Case -Texts $texts -Heard @('mà','tiếng','kêu','khó','nghe','ngựa','ngựa','ngựa','nghe','nhiều','khó','chịu')
Expect-Failure $wrong
$missing=New-Case -Texts $texts -Heard @('mà','tiếng','kêu','khó','nghe','b','b','nghe','nhiều','khó','chịu')
Expect-Failure $missing
$weak=New-Case -Texts @('Mà tiếng kêu nghe.','Be…','Nghe nhiều khó chịu.') -Heard @('và','tiếng','kêu','nghe','b','nghe','nhiều','khó','chịu')
Expect-Failure $weak
Expect-Failure (New-Case -Texts @('Be…','Nghe nhiều khó chịu.') -Heard @('b','nghe','nhiều','khó','chịu'))
Expect-Failure (New-Case -Texts @('Mà tiếng kêu nghe.','Be…') -Heard @('mà','tiếng','kêu','nghe','b'))
$long=New-Case -Texts $texts -Heard $heard
for ($i=6;$i -lt $long.Words.Count;$i++) { $long.Words[$i].Start+=7.0; $long.Words[$i].End+=7.0 }
Expect-Failure $long
$gap=New-Case -Texts $texts -Heard $heard
$gap.Sources+=@([pscustomobject]@{start=50.0;end=70.0})
for ($i=7;$i -lt $gap.Words.Count;$i++) { $gap.Words[$i].Chapter=1 }
Expect-Failure $gap
$ambiguous=New-Case -Texts $texts -Heard $heard
$ambiguous.Words[6].Start=$ambiguous.Words[5].Start; $ambiguous.Words[6].End=$ambiguous.Words[5].End
Expect-Failure $ambiguous
Write-Host "SUBTITLE_REFERENCE_VARIANTS_OK:checks=$script:checks;text/timing-preserved;wrong-SRT-rejected"
