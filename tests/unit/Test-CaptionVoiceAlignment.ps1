$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$projectRoot = Resolve-Path (Join-Path $PSScriptRoot '..\..')
. (Join-Path $projectRoot 'extension\engine\lib\Srt.ps1')
. (Join-Path $projectRoot 'extension\engine\lib\Alignment.ps1')

$text = "Mot hai ba bon nam,`nsau bay tam chin muoi."
$cues = @([pscustomobject]@{ Start=0.0; End=4.0; Text=$text })
$normalized = @(ConvertTo-NormalizedWords $text)
$recognized = New-Object System.Collections.Generic.List[object]
for ($index = 0; $index -lt $normalized.Count; $index++) {
    $start = if ($index -lt 5) { $index * 0.2 } else { 3.0 + (($index - 5) * 0.2) }
    $recognized.Add([pscustomobject]@{
        Text = $normalized[$index]
        Start = $start
        End = $start + 0.2
        Chapter = 0
    })
}
$voices = @([pscustomobject]@{ start=10.0; end=14.0 })
$aligned = @(Align-CuesToRecognizedWords -Cues $cues -RecognizedWords ($recognized.ToArray()) -VoiceClips $voices)
if ($aligned.Count -ne 1) { throw "ALIGNMENT_CUE_COUNT_FAILED:$($aligned.Count)" }
if (@($aligned[0].WordTimings).Count -ne $normalized.Count) { throw 'WORD_TIMING_COUNT_FAILED' }

$parts = @(Split-PvsVoiceAlignedCaptionCue -Cue $aligned[0] -MaxCharacters 24 -FrameRate 30)
if ($parts.Count -ne 2) { throw "CAPTION_SPLIT_COUNT_FAILED:$($parts.Count)" }
foreach ($part in $parts) {
    if ([string]$part.Text -match '[\r\n]') { throw 'CAPTION_CONTAINS_LINE_BREAK' }
    if (([string]$part.Text).Length -gt 24) { throw "CAPTION_TOO_LONG:$($part.Text)" }
    if ([int]$part.EndFrame -le [int]$part.StartFrame) { throw 'CAPTION_DURATION_INVALID' }
}
$joined = (($parts | ForEach-Object { [string]$_.Text }) -join ' ')
if ($joined -ne [regex]::Replace($text.Trim(), '\s+', ' ')) { throw 'CAPTION_TEXT_COVERAGE_FAILED' }

# Word 5 ends at absolute 11.0 s and word 6 begins at 13.0 s. The caption
# boundary must be their 12.0 s midpoint (frame 360), not a character-ratio cut.
if ([int]$parts[0].EndFrame -ne 360 -or [int]$parts[1].StartFrame -ne 360) {
    throw "CAPTION_NOT_VOICE_ALIGNED:$($parts[0].EndFrame)-$($parts[1].StartFrame)"
}
if (-not [bool]$parts[1].VoiceBoundaryAligned) { throw 'VOICE_BOUNDARY_FLAG_FAILED' }

$breathCue = [pscustomobject]@{
    Index=2; Text='Mot hai ba bon nam sau bay tam chin muoi'; Start=10.0; End=14.0
    WordTimings=$aligned[0].WordTimings
}
$measuredBreath = [pscustomobject]@{ Start=11.4; End=12.8; Center=12.1; Duration=1.4 }
$breathParts = @(Split-PvsVoiceAlignedCaptionCue -Cue $breathCue -MaxCharacters 24 -FrameRate 30 -VoiceSilences @($measuredBreath))
if ($breathParts.Count -lt 2 -or [string]$breathParts[0].Text -ne 'Mot hai ba bon nam') { throw 'MEASURED_BREATH_NOT_PREFERRED' }
if ([int]$breathParts[0].EndFrame -ne 363 -or [int]$breathParts[1].StartFrame -ne 363) { throw 'MEASURED_BREATH_FRAME_NOT_USED' }
$withoutMeasuredSilence = @(Split-PvsVoiceAlignedCaptionCue -Cue $breathCue -MaxCharacters 24 -FrameRate 30)
if ([int]$withoutMeasuredSilence[0].EndFrame -eq [int]$breathParts[0].EndFrame) { throw 'UNVERIFIED_WORD_GAP_USED_AS_BREATH' }
$unrelatedSilence = [pscustomobject]@{ Start=10.2; End=10.5; Center=10.35; Duration=0.3 }
$unrelatedParts = @(Split-PvsVoiceAlignedCaptionCue -Cue $breathCue -MaxCharacters 24 -FrameRate 30 -VoiceSilences @($unrelatedSilence))
if ([string]$unrelatedParts[0].Text -ne [string]$withoutMeasuredSilence[0].Text) { throw 'UNRELATED_SILENCE_USED_AS_BREATH' }
$uncertainCue = $breathCue.PSObject.Copy()
$uncertainTimings = @($aligned[0].WordTimings | ForEach-Object { $_.PSObject.Copy() })
$uncertainTimings[4].Exact = $false
$uncertainCue.WordTimings = $uncertainTimings
$uncertainParts = @(Split-PvsVoiceAlignedCaptionCue -Cue $uncertainCue -MaxCharacters 24 -FrameRate 30 -VoiceSilences @($measuredBreath))
if ([string]$uncertainParts[0].Text -ne [string]$breathParts[0].Text) { throw 'ACOUSTIC_BREATH_LOST_AT_UNCERTAIN_WORD' }
$punctuationCue = [pscustomobject]@{
    Index=3; Text='Mot hai ba bon, nam sau bay tam chin muoi'; Start=10.0; End=14.0
    WordTimings=$aligned[0].WordTimings
}
$punctuationParts = @(Split-PvsVoiceAlignedCaptionCue -Cue $punctuationCue -MaxCharacters 24 -FrameRate 30 -VoiceSilences @($measuredBreath))
if ([string]$punctuationParts[0].Text -ne 'Mot hai ba bon,') { throw 'PUNCTUATION_DID_NOT_PRECEDE_BREATH' }

# Whisper may report touching words even where the waveform has a real breath.
$touchingTimings = for ($index = 0; $index -lt 10; $index++) {
    [pscustomobject]@{ TargetWordIndex=$index; Start=(10.0 + $index * 0.4); End=(10.4 + $index * 0.4); Chapter=0; Exact=$true }
}
$touchingCue = [pscustomobject]@{
    Index=4; Text=$breathCue.Text; Start=10.0; End=14.0; WordTimings=@($touchingTimings)
}
$touchingSilence = [pscustomobject]@{ Start=11.8; End=12.2; Center=12.0; Duration=0.4 }
$touchingParts = @(Split-PvsVoiceAlignedCaptionCue -Cue $touchingCue -MaxCharacters 24 -FrameRate 30 -VoiceSilences @($touchingSilence))
if ([string]$touchingParts[0].Text -ne 'Mot hai ba bon nam' -or [int]$touchingParts[0].EndFrame -ne 360) {
    throw 'TOUCHING_WHISPER_WORDS_HID_REAL_BREATH'
}

# Actual subtitle text and Whisper word timings from the reported MP3, with
# two measured FFmpeg silences. Punctuation must survive the 42-character cap.
$reportedText = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('TmdoxKlhIGzDoCBzYW8/IE7hur91IGPDsyBlbGVjdHJvbiBtYW5nIMSRaeG7h24gw6JtLCB04bqhaSBzYW8ga2jDtG5nIHRo4buDIGPDsyBwb3NpdHJvbiBtYW5nIMSRaeG7h24gZMawxqFuZz8='))
$reportedWords = @([regex]::Matches($reportedText, '\S+') | ForEach-Object { $_.Value })
$reportedTimes = @(
    @(50.54,51.00),@(51.00,51.23),@(51.23,51.72),@(51.72,52.01),@(52.01,52.19),@(52.19,52.66),
    @(52.66,52.90),@(52.90,53.31),@(53.31,53.94),@(53.94,53.96),@(53.96,54.22),@(54.22,54.50),
    @(54.50,54.77),@(54.77,55.01),@(55.01,55.41),@(55.41,55.65),@(55.65,56.06),@(56.06,56.76)
)
$reportedTimings = for ($index = 0; $index -lt $reportedWords.Count; $index++) {
    [pscustomobject]@{
        TargetWordIndex=$index; Start=[double]$reportedTimes[$index][0]; End=[double]$reportedTimes[$index][1]
        Chapter=0; Exact=($index -ne 8)
    }
}
$reportedCue = [pscustomobject]@{
    Index=8; Text=$reportedText; Start=50.54; End=56.76; WordTimings=@($reportedTimings)
}
$reportedSilences = @(
    [pscustomobject]@{ Start=51.413447; End=51.962834; Duration=0.549387 },
    [pscustomobject]@{ Start=53.694671; End=54.078095; Duration=0.383424 }
)
$reportedParts = @(Split-PvsVoiceAlignedCaptionCue -Cue $reportedCue -MaxCharacters 42 -FrameRate 30 -VoiceSilences $reportedSilences)
$reportedExpected = @(
    ($reportedWords[0..2] -join ' '),
    ($reportedWords[3..8] -join ' '),
    ($reportedWords[9..12] -join ' '),
    ($reportedWords[13..17] -join ' ')
)
if ($reportedParts.Count -ne $reportedExpected.Count) { throw "REPORTED_SENTENCE_CAPTION_COUNT_FAILED:$($reportedParts.Count)" }
for ($index = 0; $index -lt $reportedParts.Count; $index++) {
    if ([string]$reportedParts[$index].Text -ne $reportedExpected[$index]) { throw "REPORTED_SENTENCE_PUNCTUATION_FAILED:$index" }
    if (([string]$reportedParts[$index].Text).Length -gt 42) { throw "REPORTED_SENTENCE_TOO_LONG:$index" }
}
$questionFrame = [int][Math]::Round(((51.413447 + 51.962834) / 2.0) * 30)
$commaFrame = [int][Math]::Round(((53.694671 + 54.078095) / 2.0) * 30)
if ([int]$reportedParts[0].EndFrame -ne $questionFrame -or [int]$reportedParts[1].EndFrame -ne $commaFrame) {
    throw 'REPORTED_SENTENCE_VOICE_BOUNDARY_FAILED'
}

# Real cue: Whisper places "Hom nay" inside the measured silence before the
# utterance, and ends it before the measured pause after the comma.
$openingText = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('SMO0bSBuYXksIGNow7puZyB0YSBz4bq9IGdp4bqjaSBtw6MgxJFp4buBdSBj4bqlbSBr4bu1IHThu5FpIHRoxrDhu6NuZyBj4bunYSB24bqtdCBsw706IHBo4bqjbiB24bqtdCBjaOG6pXQu'))
$openingTimes = @(
    @(29.73,29.89),@(29.89,30.16),@(30.16,30.60),@(30.60,30.60),@(30.60,30.82),@(30.82,31.15),
    @(31.15,31.31),@(31.31,31.63),@(31.63,31.96),@(31.96,32.18),@(32.18,32.46),@(32.46,32.98),
    @(32.98,33.22),@(33.22,33.49),@(33.49,33.90),@(33.90,34.21),@(34.21,34.47),@(34.47,35.00)
)
$openingTimings = for ($index = 0; $index -lt $openingTimes.Count; $index++) {
    [pscustomobject]@{ TargetWordIndex=$index; Start=$openingTimes[$index][0]; End=$openingTimes[$index][1]; Chapter=0; Exact=$true }
}
$openingCue = [pscustomobject]@{ Index=5; Text=$openingText; Start=29.73; End=35.00; WordTimings=@($openingTimings) }
$openingSilences = @(
    [pscustomobject]@{ Start=29.383; End=29.951; Duration=0.568 },
    [pscustomobject]@{ Start=30.413; End=30.739; Duration=0.326 },
    [pscustomobject]@{ Start=33.617; End=34.023; Duration=0.406 },
    [pscustomobject]@{ Start=34.667; End=35.179; Duration=0.512 }
)
$openingParts = @(Split-PvsVoiceAlignedCaptionCue -Cue $openingCue -MaxCharacters 42 -FrameRate 30 -VoiceSilences $openingSilences)
if ([string]$openingParts[0].Text -notmatch '^Hôm nay, chúng ta' -or $openingParts[0].Text.Length -gt 42) { throw 'OPENING_SHORT_PAUSE_NOT_MERGED' }
if ([int]$openingParts[0].StartFrame -ne 899 -or [int]$openingParts[0].EndFrame -ne 965) { throw 'OPENING_CAPTION_ACOUSTIC_TIMING_FAILED' }
if ([int]$openingParts[-1].EndFrame -ne 1040) { throw 'ENDING_CAPTION_ACOUSTIC_TIMING_FAILED' }

# Real no-punctuation phrase: the breath after "cao" is just beyond 42
# characters, so an earlier balanced split is needed to retain that breath.
$breathPhrase = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('TmdoaeG7h20gw6JtIGLhuqV0IG5n4budIOG6pXkgZ2nhu5FuZyBuaMawIGLDrSBt4bqtdCB04buRaSBjYW8gbcOgIHbFqSB0cuG7pSB2w7QgdMOsbmggxJHhu4MgbOG7mS4='))
$phraseWords = @([regex]::Matches($breathPhrase, '\S+') | ForEach-Object { $_.Value })
$phraseTimes = @(
    @(76.36,76.85),@(76.85,77.05),@(77.05,77.36),@(77.36,77.78),@(77.78,77.94),@(77.94,78.60),
    @(78.60,78.63),@(78.63,78.86),@(78.86,79.14),@(79.14,79.43),@(79.43,79.66),@(79.66,79.81),
    @(79.81,79.99),@(79.99,80.31),@(80.31,80.51),@(80.51,80.80),@(80.80,81.12),@(81.12,81.68)
)
$phraseTimings = for ($index = 0; $index -lt $phraseTimes.Count; $index++) {
    [pscustomobject]@{ TargetWordIndex=$index; Start=$phraseTimes[$index][0]; End=$phraseTimes[$index][1]; Chapter=0; Exact=$true }
}
$phraseCue = [pscustomobject]@{ Index=10; Text=$breathPhrase; Start=76.36; End=81.68; WordTimings=@($phraseTimings) }
$phraseSilence = [pscustomobject]@{ Start=79.387; End=79.713; Duration=0.326 }
$phraseParts = @(Split-PvsVoiceAlignedCaptionCue -Cue $phraseCue -MaxCharacters 42 -FrameRate 30 -VoiceSilences @($phraseSilence))
$phraseExpected = @(($phraseWords[0..4] -join ' '), ($phraseWords[5..10] -join ' '), ($phraseWords[11..17] -join ' '))
if ($phraseParts.Count -ne 3) { throw 'BREATH_BEYOND_CHARACTER_LIMIT_COUNT_FAILED' }
for ($index = 0; $index -lt 3; $index++) {
    if ([string]$phraseParts[$index].Text -ne $phraseExpected[$index]) { throw "BREATH_BEYOND_CHARACTER_LIMIT_TEXT_FAILED:$index" }
    if (([string]$phraseParts[$index].Text).Length -gt 42) { throw "BREATH_BEYOND_CHARACTER_LIMIT_WIDTH_FAILED:$index" }
}
if ([int]$phraseParts[1].EndFrame -ne 2386) { throw 'BREATH_BEYOND_CHARACTER_LIMIT_TIMING_FAILED' }
$shortBreath = [pscustomobject]@{ Start=79.47; End=79.64; Duration=0.17 }
$shortBreathParts = @(Split-PvsVoiceAlignedCaptionCue -Cue $phraseCue -MaxCharacters 42 -FrameRate 30 -VoiceSilences @($shortBreath))
if ($shortBreathParts.Count -ne 3 -or [string]$shortBreathParts[1].Text -ne $phraseExpected[1]) { throw 'SHORT_ACOUSTIC_BREATH_NOT_USED' }

# A pause after a linking word must not force a new split that strands a noun
# phrase, even when the pause is one word beyond the character limit.
$linkingText = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('bMSpbmggdOG6oWkgQ0VSTiBkw7luZyBjaGnhur9jIGLDrG5oIHRo4bqnbiBr4buzIG7DoG8gxJHhu4Mga2hp4bq/biBuw7MgbmdvYW4gbmdvw6NuIG7hurFtIHnDqm4gYsOqbiB0cm9uZz8='))
$linkingWords = @([regex]::Matches($linkingText, '\S+') | ForEach-Object { $_.Value })
$linkingTimings = for ($index = 0; $index -lt $linkingWords.Count; $index++) {
    [pscustomobject]@{ TargetWordIndex=$index; Start=(200.0 + $index * 0.25); End=(200.2 + $index * 0.25); Chapter=0; Exact=$true }
}
$linkingSilence = [pscustomobject]@{ Start=202.35; End=202.65; Duration=0.3 }
$linkingChunks = @(Get-PvsCaptionTextChunks -Text $linkingText -MaxCharacters 42 -WordTimings @($linkingTimings) -VoiceSilences @($linkingSilence))
if ([string]$linkingChunks[0].Text -ne ($linkingWords[0..8] -join ' ')) { throw 'LINKING_WORD_FALSE_BREATH_SPLIT' }

# The user's reported sentence was split between "pha tung" and "truc tiep".
# Word-based captions must keep these and other common two-syllable phrases
# together, even when a measured quiet interval falls between the syllables.
$atomicText = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('Qm9tIG5ndXnDqm4gdOG7rSB2w6AgYm9tIGh5ZHJvIGPDsyB0aOG7gyBzYW4gcGjhurNuZyBt4buZdCB0aMOgbmggcGjhu5EgdHJvbmcgY2jhu5twIG3huq90IHbDrCBjaMO6bmcgxJHDoyBkw7luZyBjw6FjaCBj4buxYyBr4buzIGThu68gZOG7mWkgxJHhu4MgcGjDoSB0dW5nIGPDoW5oIGPhu61hIGPhu6dhIGjhuqF0IG5ow6JuIG5ndXnDqm4gdOG7rSwgYmnhur9uIG3hu5l0IHBo4bqnbiBraOG7kWkgbMaw4bujbmcgY+G7p2EgduG6rXQgY2jhuqV0IHRy4buxYyB0aeG6v3AgdGjDoG5oIG7Eg25nIGzGsOG7o25nIHRodeG6p24gdMO6eS4='))
$atomicWords = @([regex]::Matches($atomicText, '\S+') | ForEach-Object { $_.Value })
$atomicTimings = for ($index = 0; $index -lt $atomicWords.Count; $index++) {
    [pscustomobject]@{ TargetWordIndex=$index; Start=(100.0 + $index * 0.25); End=(100.2 + $index * 0.25); Chapter=0; Exact=$true }
}
$atomicCue = [pscustomobject]@{ Index=11; Text=$atomicText; Start=100.0; End=(100.0 + ($atomicWords.Count - 1) * 0.25 + 0.2); WordTimings=@($atomicTimings) }
$atomicParts = @(Split-PvsVoiceAlignedCaptionCue -Cue $atomicCue -MaxCharacters 42 -FrameRate 30)
$atomicJoined = ($atomicParts | ForEach-Object { [string]$_.Text }) -join ' '
if ($atomicJoined -ne $atomicText) { throw 'ATOMIC_PHRASE_TEXT_COVERAGE_FAILED' }
foreach ($part in $atomicParts) {
    if (([string]$part.Text).Length -gt 42) { throw 'ATOMIC_PHRASE_CAPTION_TOO_LONG' }
}
$atomicDelimited = '|' + (($atomicParts | ForEach-Object { [string]$_.Text }) -join '|') + '|'
foreach ($phrase in @('ph' + [char]0x00E1 + ' tung', 'tr' + [char]0x1EF1 + 'c ti' + [char]0x1EBF + 'p', 'kh' + [char]0x1ED1 + 'i l' + [char]0x01B0 + [char]0x1EE3 + 'ng')) {
    if ($atomicDelimited.Contains(($phrase -replace ' ', '|'))) { throw "ATOMIC_PHRASE_SPLIT:$phrase" }
}
$phaIndex = [Array]::IndexOf($atomicWords, ([string]::Concat('ph', [char]0x00E1)))
if ($phaIndex -lt 0) { throw 'ATOMIC_PHRASE_FIXTURE_INVALID' }
$silenceCenter = ([double]$atomicTimings[$phaIndex].End + [double]$atomicTimings[$phaIndex + 1].Start) / 2.0
$forcedBreath = [pscustomobject]@{ Start=($silenceCenter - 0.1); End=($silenceCenter + 0.1); Duration=0.2 }
$breathAtomicParts = @(Split-PvsVoiceAlignedCaptionCue -Cue $atomicCue -MaxCharacters 42 -FrameRate 30 -VoiceSilences @($forcedBreath))
if ((($breathAtomicParts | ForEach-Object { [string]$_.Text }) -join '|').Contains(([string]::Concat('ph', [char]0x00E1, '|tung')))) { throw 'BREATH_SPLIT_ATOMIC_PHRASE' }

# These phrases were split in the user's real antimatter voice. The third
# override spans three syllables, so both internal boundaries must be guarded.
$reportedPhrases = @(
    [pscustomobject]@{ Prefix='alpha beta gamma'; Phrase=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('Y+G6pW0ga+G7tQ==')) },
    [pscustomobject]@{ Prefix='alpha beta gamma'; Phrase=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('bMO6YyBuw6B5')) },
    [pscustomobject]@{ Prefix='alpha beta'; Phrase=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('dOG7lW5nIGto4buRaSBsxrDhu6NuZw==')) }
)
foreach ($example in $reportedPhrases) {
    $sample = "$($example.Prefix) $($example.Phrase) epsilon zeta"
    $words = @([regex]::Matches($sample, '\S+') | ForEach-Object { $_.Value })
    $timings = for ($index = 0; $index -lt $words.Count; $index++) {
        [pscustomobject]@{ TargetWordIndex=$index; Start=($index * 0.25); End=($index * 0.25 + 0.2); Chapter=0; Exact=$true }
    }
    $phraseWords = @($example.Phrase -split ' ')
    $phraseStart = [Array]::IndexOf($words, $phraseWords[0])
    if ($phraseStart -lt 0) { throw 'REPORTED_PHRASE_FIXTURE_INVALID' }
    $quiet = [pscustomobject]@{ Start=($phraseStart * 0.25 + 0.17); End=($phraseStart * 0.25 + 0.37); Duration=0.2 }
    $chunks = @(Get-PvsCaptionTextChunks -Text $sample -MaxCharacters 21 -WordTimings @($timings) -VoiceSilences @($quiet))
    $delimited = '|' + (($chunks | ForEach-Object { [string]$_.Text }) -join '|') + '|'
    if (($chunks | ForEach-Object { [string]$_.Text }) -join ' ' -ne $sample) { throw "REPORTED_PHRASE_COVERAGE_FAILED:$($example.Phrase)" }
    for ($index = 0; $index -lt $phraseWords.Count - 1; $index++) {
        if ($delimited.Contains("$($phraseWords[$index])|$($phraseWords[$index + 1])")) {
            throw "REPORTED_PHRASE_SPLIT:$($example.Phrase)"
        }
    }
}

$paddingCaptions = @(
    [pscustomobject]@{ Start=1.0; End=2.0; PartIndex=1; PartCount=1 },
    [pscustomobject]@{ Start=2.2; End=3.0; PartIndex=1; PartCount=1 },
    [pscustomobject]@{ Start=3.1; End=4.0; PartIndex=1; PartCount=1 },
    [pscustomobject]@{ Start=4.0; End=5.0; PartIndex=1; PartCount=1 }
)
$unpadded = @($paddingCaptions | ForEach-Object { $_.PSObject.Copy() })
Add-PvsCaptionEdgePadding -Captions $unpadded -FrameRate 30 -TimelineEndFrame 153
if ((@($unpadded | ForEach-Object { '{0}-{1}' -f [Math]::Round($_.Start*30),[Math]::Round($_.End*30) }) -join ',') -ne '30-60,66-90,93-120,120-150') {
    throw 'CAPTION_DEFAULT_PADDING_NOT_ZERO'
}
Add-PvsCaptionEdgePadding -Captions $paddingCaptions -FrameRate 30 -TimelineEndFrame 153 -PaddingFrames 5
$starts = @($paddingCaptions | ForEach-Object { [int][Math]::Round([double]$_.Start * 30) })
$ends = @($paddingCaptions | ForEach-Object { [int][Math]::Round([double]$_.End * 30) })
if ($starts[0] -ne 25 -or $ends[0] -ne 63 -or $starts[1] -ne 63 -or $ends[1] -ne 92 -or
    $starts[2] -ne 92 -or $ends[2] -ne 120 -or $starts[3] -ne 120 -or $ends[3] -ne 153) {
    throw 'CAPTION_FIVE_FRAME_PADDING_FAILED'
}

$title='Trong Alien: Covenant, ta thấy David lái tàu Engineer để thả bom.'
$titleParts=@(Get-PvsCaptionTextChunks -Text $title -MaxCharacters 42)
if($titleParts.Count -ne 2 -or $titleParts[0].Text -ne 'Trong Alien: Covenant,' -or $titleParts[1].Text -ne 'ta thấy David lái tàu Engineer để thả bom.'){throw 'SHORT_TITLE_PUNCTUATION_SPLIT'}
foreach($sample in @('Hôm nay, chúng ta cùng tìm hiểu thế giới.','Vậy là, trong Alien: Covenant, ta thấy David.','Năm 1979, Alien đã mở đường cho điện ảnh.')){
    $chunks=@(Get-PvsCaptionTextChunks -Text $sample -MaxCharacters 42)
    if(($chunks.Text -join ' ') -ne $sample -or $chunks[0].Text -match '^(Hôm nay,|Vậy là,|Năm 1979,)$'){throw 'SHORT_WEAK_PAUSE_NOT_MERGED'}
}

$longText = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('Y2jhu4kgY+G6p24gY2jhuqFtIHbDoG8gduG6rXQgY2jhuqV0IHRow7RuZyB0aMaw4budbmcgbMOgIGfDonkgcmEgduG7pSBu4buVIGjhu6d5IGPhurdwIGPDsyBz4bupYyB0w6BuIHBow6Ega2jhu6duZyBraGnhur9w'))
$longWords = @([regex]::Matches($longText, '\S+') | ForEach-Object { $_.Value })
$longWordTimings = for ($index = 0; $index -lt $longWords.Count; $index++) {
    [pscustomobject]@{
        TargetWordIndex=$index; Text=$longWords[$index]; Start=(20.0 + $index * 0.25)
        End=(20.2 + $index * 0.25); Chapter=0; Exact=$true
    }
}
$longCue = [pscustomobject]@{
    Index=2; Text=$longText; Start=20.0; End=25.25; Chapter=0; Confidence=1.0
    WordTimings=@($longWordTimings)
}
$balanced = @(Split-PvsVoiceAlignedCaptionCue -Cue $longCue -MaxCharacters 42 -FrameRate 30)
$expectedText = @(
    ($longWords[0..8] -join ' '),
    ($longWords[9..14] -join ' '),
    ($longWords[15..20] -join ' ')
)
if ($balanced.Count -ne $expectedText.Count) { throw "ORPHAN_REGRESSION_COUNT_FAILED:$($balanced.Count)" }
for ($index = 0; $index -lt $balanced.Count; $index++) {
    if ([string]$balanced[$index].Text -ne $expectedText[$index]) { throw "ORPHAN_REGRESSION_TEXT_FAILED:$($index):$($balanced[$index].Text)" }
    if (([string]$balanced[$index].Text).Length -gt 42 -or [string]$balanced[$index].Text -match '[\r\n]') { throw "ORPHAN_REGRESSION_LINE_FAILED:$index" }
    if ($index -gt 0) {
        if ([int]$balanced[$index - 1].EndFrame -ne [int]$balanced[$index].StartFrame) { throw "ORPHAN_REGRESSION_GAP_FAILED:$index" }
        if (-not [bool]$balanced[$index].VoiceBoundaryAligned) { throw "ORPHAN_REGRESSION_VOICE_FLAG_FAILED:$index" }
    }
}
$expectedFirstBoundary = [int][Math]::Round((([double]$longWordTimings[8].End + [double]$longWordTimings[9].Start) / 2.0) * 30)
$expectedSecondBoundary = [int][Math]::Round((([double]$longWordTimings[14].End + [double]$longWordTimings[15].Start) / 2.0) * 30)
if ([int]$balanced[0].EndFrame -ne $expectedFirstBoundary -or [int]$balanced[1].EndFrame -ne $expectedSecondBoundary) {
    throw 'ORPHAN_REGRESSION_NOT_VOICE_ALIGNED'
}

$fallbackCue = [pscustomobject]@{ Index=1; Text=$text; Start=10.0; End=14.0 }
$missingTimingRejected = $false
try { Split-PvsVoiceAlignedCaptionCue -Cue $fallbackCue -MaxCharacters 24 -FrameRate 30 | Out-Null }
catch { if ($_.Exception.Message -like 'CAPTION_WORD_TIMING_REQUIRED:*') { $missingTimingRejected = $true } else { throw } }
if (-not $missingTimingRejected) { throw 'MISSING_WORD_TIMING_WAS_ACCEPTED' }

$temp = Join-Path $env:TEMP ('PVS-CaptionVoice-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $temp -Force | Out-Null
try {
    $engineRoot = Join-Path $temp 'engine'
    New-Item -ItemType Directory -Path (Join-Path $engineRoot 'lib'),(Join-Path $engineRoot 'runtime') -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $projectRoot 'extension\engine\build-sentence-plan.ps1') -Destination $engineRoot
    Copy-Item -LiteralPath (Join-Path $projectRoot 'extension\engine\lib\Srt.ps1') -Destination (Join-Path $engineRoot 'lib')
    Copy-Item -LiteralPath (Join-Path $projectRoot 'extension\engine\lib\ReferenceAlignment.ps1') -Destination (Join-Path $engineRoot 'lib')
    Copy-Item -LiteralPath (Join-Path $projectRoot 'extension\engine\lib\CaptionTiming.ps1') -Destination (Join-Path $engineRoot 'lib')
    Copy-Item -LiteralPath (Join-Path $projectRoot 'extension\engine\lib\AutoEditAcousticPartitions.ps1') -Destination (Join-Path $engineRoot 'lib')
    Copy-Item -LiteralPath (Join-Path $projectRoot 'extension\engine\lib\AutoEditManualReview.ps1') -Destination (Join-Path $engineRoot 'lib')
    Copy-Item -LiteralPath (Join-Path $projectRoot 'extension\engine\lib\RecognitionBackend.ps1') -Destination (Join-Path $engineRoot 'lib')
    Copy-Item -LiteralPath (Join-Path $projectRoot 'extension\engine\lib\SubtitleTiming.ps1') -Destination (Join-Path $engineRoot 'lib')
    Copy-Item -LiteralPath (Join-Path $projectRoot 'extension\engine\lib\SubtitleEnergy.ps1') -Destination (Join-Path $engineRoot 'lib')
    Copy-Item -LiteralPath (Join-Path $projectRoot 'extension\engine\lib\vi-caption-phrases.txt') -Destination (Join-Path $engineRoot 'lib')
    Copy-Item -LiteralPath (Join-Path $projectRoot 'extension\engine\lib\vi-caption-overrides.txt') -Destination (Join-Path $engineRoot 'lib')
    Copy-Item -LiteralPath (Join-Path $projectRoot 'extension\engine\lib\Paths.ps1') -Destination (Join-Path $engineRoot 'lib')
    foreach($name in @('Security.ps1','AudioCache.ps1')){Copy-Item -LiteralPath (Join-Path $projectRoot "extension\engine\lib\$name") -Destination (Join-Path $engineRoot 'lib')}
    foreach($name in @('runtime-lock.json','cuda-lock.json')){Copy-Item -LiteralPath (Join-Path $projectRoot "extension\engine\$name") -Destination $engineRoot}
    Set-Content -LiteralPath (Join-Path $engineRoot 'lib\Native.ps1') -Value '. "$PSScriptRoot\Security.ps1"; . "$PSScriptRoot\AudioCache.ps1"; function Invoke-NativeCapture {param($FilePath,$Arguments);[pscustomobject]@{ExitCode=0;Output=((& $FilePath @Arguments)|Out-String)}}' -Encoding ASCII
    Set-Content -LiteralPath (Join-Path $engineRoot 'runtime\fake-ffmpeg.ps1') -Value '# no detected silence' -Encoding ASCII
    '{"ffmpeg":"fake-ffmpeg.ps1"}' | Set-Content -LiteralPath (Join-Path $engineRoot 'runtime\engine.json') -Encoding ASCII
    $wave = Join-Path $temp 'voice.wav'
    Set-Content -LiteralPath $wave -Value '' -Encoding ASCII
    [ordered]@{voiceChapterCount=1;cues=$aligned} | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $temp 'alignment-result.json') -Encoding UTF8
    $job = [ordered]@{
        outputFolder=$temp;speedWarningMinPercent=70;speedWarningMaxPercent=130
        algorithm=[ordered]@{maxCaptionCharacters=24;useWhisperCache=$false}
        sequence=[ordered]@{
            sequenceId='caption-voice';name='caption-voice';frameRate=30
            mainVideoClip=[ordered]@{start=0;end=4};linkedAudio=@();voiceTrackIndex=1
            voices=@([ordered]@{name='voice.wav';path=$wave;start=10;end=14;speedPercent=100})
        }
    }
    $jobPath = Join-Path $temp 'job.json'
    $job | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $jobPath -Encoding UTF8
    & (Join-Path $engineRoot 'build-sentence-plan.ps1') -JobPath $jobPath | Out-Null
    $plan = Get-Content -LiteralPath (Join-Path $temp 'sentence-edit-plan.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    if (@($plan.captions).Count -ne 2) { throw 'PLANNER_CAPTION_SPLIT_COUNT_FAILED' }
    if ([double]$plan.captions[0].End -ne 2.0 -or [double]$plan.captions[1].Start -ne 2.0) { throw 'PLANNER_CAPTION_VOICE_BOUNDARY_FAILED' }
    if ([int]$plan.summary.voiceAlignedCaptionBoundaryCount -ne 1) { throw 'PLANNER_CAPTION_BOUNDARY_SUMMARY_FAILED' }
    if ([int]$plan.settings.maxCaptionCharacters -ne 24) { throw 'PLANNER_CAPTION_SETTING_FAILED' }
    if ([int]$plan.plannerRevision -ne 18) { throw 'PLANNER_CAPTION_REVISION_FAILED' }

    $breathAlignedCue = $aligned[0].PSObject.Copy()
    $breathAlignedCue.Text = $breathCue.Text
    [ordered]@{voiceChapterCount=1;cues=@($breathAlignedCue)} | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $temp 'alignment-result.json') -Encoding UTF8
    @("Write-Output 'silence_start: 1.4'", "Write-Output 'silence_end: 2.8'") | Set-Content -LiteralPath (Join-Path $engineRoot 'runtime\fake-ffmpeg.ps1') -Encoding ASCII
    & (Join-Path $engineRoot 'build-sentence-plan.ps1') -JobPath $jobPath | Out-Null
    $breathPlan = Get-Content -LiteralPath (Join-Path $temp 'sentence-edit-plan.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    if (@($breathPlan.captions).Count -ne 2 -or [double]$breathPlan.captions[0].End -ne 2.1) { throw 'PLANNER_DID_NOT_USE_MEASURED_BREATH' }

    # Acoustic cue 2 is spoken in the preceding legacy A2 slice. Clamping to
    # cue 2's assigned slice used to collapse both captions into its silence.
    $displaced=@(for($i=0;$i -lt 2;$i++){
        $begin=if($i -eq 0){0.1}else{2.1};$words=if($i -eq 0){@('alpha','beta')}else{@('gamma','delta')}
        $timings=@(for($w=0;$w -lt 2;$w++){[pscustomobject]@{TargetWordIndex=$w;Text=$words[$w];Start=$begin+$w*0.5;End=$begin+($w+1)*0.5;Chapter=0;Exact=$true}})
        [pscustomobject]@{Index=$i+1;Start=$(if($i -eq 0){0.0}else{5.0});End=$(if($i -eq 0){5.0}else{7.0});OriginalStart=$(if($i -eq 0){0.0}else{4.0});OriginalEnd=$(if($i -eq 0){4.0}else{7.0});Text=($words -join ' ')+'.';Chapter=0;Confidence=1.0;WordTimings=$timings;CaptionWordTimings=$timings;CaptionStart=$begin;CaptionEnd=$begin+1.0;CaptionTimingRevision='dtw-word-boundary-v1'}
    })
    $job.sequence.mainVideoClip.end=7;$job.sequence.voices[0].start=0;$job.sequence.voices[0].end=7
    $job | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $jobPath -Encoding UTF8
    [ordered]@{voiceChapterCount=1;cues=$displaced} | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $temp 'alignment-result.json') -Encoding UTF8
    @("Write-Output 'silence_start: 4.8'", "Write-Output 'silence_end: 5.2'") | Set-Content -LiteralPath (Join-Path $engineRoot 'runtime\fake-ffmpeg.ps1') -Encoding ASCII
    & (Join-Path $engineRoot 'build-sentence-plan.ps1') -JobPath $jobPath | Out-Null
    $displacedPlan=Get-Content -LiteralPath (Join-Path $temp 'sentence-edit-plan.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    if($displacedPlan.summary.safeSentenceGroupCount -ne 2 -or $displacedPlan.captions[1].Start -ne 2.1 -or $displacedPlan.captions[1].End -ne 3.1){throw 'PLANNER_ACOUSTIC_CAPTION_CLAMPED_TO_WRONG_SENTENCE'}
    if($displacedPlan.segments[1].OriginalVoiceStartFrame -ne 150 -or $displacedPlan.segments[1].NewVoiceStartFrame -ne 150 -or $displacedPlan.plannedMainVideoEndFrame -ne 210){throw 'CAPTION_FIX_CHANGED_EDIT_CUTS_OR_DURATION'}
}
finally {
    if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Recurse -Force }
}

Write-Host 'CAPTION_VOICE_ALIGNMENT_OK:punctuation-breath-space; orphan regression; planner integration'
