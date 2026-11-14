Set-StrictMode -Version Latest

function ConvertFrom-SrtTimestamp {
    param([Parameter(Mandatory)][string]$Value)
    if ($Value -notmatch '^(\d+):(\d{2}):(\d{2})[,.](\d{3})$' -or [int]$Matches[2] -ge 60 -or [int]$Matches[3] -ge 60) {
        throw "Timecode SRT khong hop le: $Value"
    }
    return ([int]$Matches[1] * 3600) + ([int]$Matches[2] * 60) + [int]$Matches[3] + ([int]$Matches[4] / 1000.0)
}

function ConvertTo-SrtTimestamp {
    param([Parameter(Mandatory)][double]$Seconds)
    if ($Seconds -lt 0) { $Seconds = 0 }
    $totalMs = [long][Math]::Round($Seconds * 1000.0)
    $hours = [Math]::Floor($totalMs / 3600000)
    $totalMs %= 3600000
    $minutes = [Math]::Floor($totalMs / 60000)
    $totalMs %= 60000
    $secs = [Math]::Floor($totalMs / 1000)
    $ms = $totalMs % 1000
    return ('{0:00}:{1:00}:{2:00},{3:000}' -f $hours, $minutes, $secs, $ms)
}

function Read-SrtFile {
    param([Parameter(Mandatory)][string]$Path)
    $raw = [IO.File]::ReadAllText($Path, [Text.Encoding]::UTF8)
    $raw = $raw -replace "`r`n", "`n" -replace "`r", "`n"
    $blocks = [regex]::Split($raw.Trim(), "`n[ \t]*`n(?:[ \t]*`n)*")
    $items = New-Object System.Collections.Generic.List[object]
    foreach ($block in $blocks) {
        $lines = $block -split "`n"
        if ($lines.Count -lt 2) { throw "SRT_CUE_INVALID:block-$($items.Count+1)" }
        $timeLineIndex = 0
        if ($lines[0] -match '^\s*\d+\s*$') { $timeLineIndex = 1 }
        if ($timeLineIndex -ge $lines.Count -or $lines[$timeLineIndex] -notmatch '^\s*(\d+:\d{2}:\d{2}[,.]\d{3})\s*-->\s*(\d+:\d{2}:\d{2}[,.]\d{3})(?:\s.*)?$') { throw "SRT_TIMECODE_INVALID:block-$($items.Count+1)" }
        # Timestamp conversion also uses Matches; save both captures first.
        $startStamp=$Matches[1];$endStamp=$Matches[2]
        $start = ConvertFrom-SrtTimestamp $startStamp
        $end = ConvertFrom-SrtTimestamp $endStamp
        if($end -le $start){throw "SRT_DURATION_INVALID:cue-$($items.Count+1)"}
        $textStart = $timeLineIndex + 1
        $text = if ($textStart -lt $lines.Count) { ($lines[$textStart..($lines.Count - 1)] -join "`n").Trim() } else { '' }
        if([string]::IsNullOrWhiteSpace($text)){throw "SRT_TEXT_MISSING:cue-$($items.Count+1)"}
        $items.Add([pscustomobject]@{
            Index = $items.Count + 1
            Start = [double]$start
            End = [double]$end
            Text = $text
        })
    }
    return $items.ToArray()
}

function Write-SrtFile {
    param(
        [Parameter(Mandatory)][object[]]$Cues,
        [Parameter(Mandatory)][string]$Path
    )
    $builder = New-Object Text.StringBuilder
    for ($i = 0; $i -lt $Cues.Count; $i++) {
        $cue = $Cues[$i]
        [void]$builder.AppendLine([string]($i + 1))
        [void]$builder.AppendLine("$(ConvertTo-SrtTimestamp ([double]$cue.Start)) --> $(ConvertTo-SrtTimestamp ([double]$cue.End))")
        [void]$builder.AppendLine([string]$cue.Text)
        [void]$builder.AppendLine()
    }
    [IO.File]::WriteAllText($Path, $builder.ToString(), (New-Object Text.UTF8Encoding($false)))
}

function Get-PvsCaptionProtectedPairSet {
    if (Get-Variable -Name PvsCaptionProtectedPairSet -Scope Script -ErrorAction SilentlyContinue) {
        return ,$script:PvsCaptionProtectedPairSet
    }
    $path = Join-Path $PSScriptRoot 'vi-caption-phrases.txt'
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "CAPTION_LEXICON_MISSING:$path" }
    $pairs = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($line in [IO.File]::ReadLines($path, [Text.Encoding]::UTF8)) {
        if (-not [string]::IsNullOrWhiteSpace($line)) {
            [void]$pairs.Add($line.Trim().Normalize([Text.NormalizationForm]::FormC))
        }
    }
    $overridePath = Join-Path $PSScriptRoot 'vi-caption-overrides.txt'
    if (-not (Test-Path -LiteralPath $overridePath -PathType Leaf)) { throw "CAPTION_LEXICON_MISSING:$overridePath" }
    foreach ($line in [IO.File]::ReadLines($overridePath, [Text.Encoding]::UTF8)) {
        $words = @([regex]::Split($line.Trim().Normalize([Text.NormalizationForm]::FormC), '\s+') | Where-Object { $_ })
        if ($words.Count -lt 2) { continue }
        for ($index = 0; $index -lt $words.Count - 1; $index++) {
            [void]$pairs.Add("$($words[$index]) $($words[$index + 1])")
        }
    }
    if ($pairs.Count -lt 10000) { throw "CAPTION_LEXICON_INVALID:$($pairs.Count)" }
    $script:PvsCaptionProtectedPairSet = $pairs
    return ,$pairs
}

function Test-PvsCaptionInitialContinuation {
    param([string]$Token,[string]$NextToken)
    # Initials in a person's name are not sentence stops. Protect the whole
    # initial chain and its surname, including compact forms such as H.R.
    return $Token -cmatch '^(?:[A-Z]\.)+$' -and ($NextToken -cmatch '^(?:[A-Z]\.)+$' -or $NextToken -cmatch '^[A-Z][a-zA-Z\x27\u2019-]+[,;:.!?…]?$')
}

function Get-PvsCaptionTokenMap {
    param(
        [AllowEmptyString()][string]$Text,
        [Parameter(Mandatory)][int]$MaxCharacters
    )
    if ($MaxCharacters -lt 10) { throw 'CAPTION_MAX_CHARACTERS_TOO_SMALL' }
    $flat = [regex]::Replace(([string]$Text).Trim().Normalize([Text.NormalizationForm]::FormC), '\s+', ' ')
    if ([string]::IsNullOrWhiteSpace($flat)) { return $null }

    $tokens = @([regex]::Matches($flat, '\S+') | ForEach-Object { $_.Value })
    $protectedPairs = Get-PvsCaptionProtectedPairSet
    $protectedBreaks = New-Object 'bool[]' $tokens.Count
    $titleColons = New-Object 'bool[]' $tokens.Count
    for ($tokenIndex = 0; $tokenIndex -lt $tokens.Count - 1; $tokenIndex++) {
        if(Test-PvsCaptionInitialContinuation $tokens[$tokenIndex] $tokens[$tokenIndex+1]){
            $titleColons[$tokenIndex]=$true
            $protectedBreaks[$tokenIndex]=$true
            continue
        }
        # A colon inside a Latin title/name is not a mandatory reading pause.
        if ($tokens[$tokenIndex] -cmatch '^[A-Z][A-Za-z0-9-]*:$' -and $tokens[$tokenIndex+1] -cmatch '^[A-Z][A-Za-z0-9-]*[,;:.!?]?$') {
            $titleColons[$tokenIndex]=$true
            $protectedBreaks[$tokenIndex]=$true
            continue
        }
        # A punctuation mark is always a stronger caption boundary than the
        # lexicon. Only uninterrupted syllables may form a protected phrase.
        if ($tokens[$tokenIndex] -match '[,;:.!?…]$') { continue }
        $left = [regex]::Replace($tokens[$tokenIndex], '^[^\p{L}\p{N}]+|[^\p{L}\p{N}]+$', '')
        $right = [regex]::Replace($tokens[$tokenIndex + 1], '^[^\p{L}\p{N}]+|[^\p{L}\p{N}]+$', '')
        if ($left -and $right -and $protectedPairs.Contains("$left $right")) { $protectedBreaks[$tokenIndex] = $true }
    }
    $wordStarts = New-Object 'int[]' $tokens.Count
    $wordEnds = New-Object 'int[]' $tokens.Count
    $wordCursor = 0
    for ($tokenIndex = 0; $tokenIndex -lt $tokens.Count; $tokenIndex++) {
        if ($tokens[$tokenIndex].Length -gt $MaxCharacters) {
            throw "CAPTION_WORD_TOO_LONG:$($tokens[$tokenIndex])"
        }
        $wordStarts[$tokenIndex] = $wordCursor
        $tokenWordCount = [regex]::Matches($tokens[$tokenIndex].ToLowerInvariant().Normalize([Text.NormalizationForm]::FormC), '[\p{L}\p{N}]+').Count
        $wordCursor += $tokenWordCount
        $wordEnds[$tokenIndex] = $wordCursor - 1
    }

    [pscustomobject]@{Text=$flat;Tokens=$tokens;ProtectedBreaks=$protectedBreaks;TitleColons=$titleColons;WordStarts=$wordStarts;WordEnds=$wordEnds;WordCount=$wordCursor}
}

function Get-PvsCaptionTextChunks {
    param(
        [AllowEmptyString()][string]$Text,
        [Parameter(Mandatory)][int]$MaxCharacters,
        [object[]]$WordTimings = @(),
        [object[]]$VoiceSilences = @()
    )
    # Same H01 tokenization/protection rules for the legacy splitter and the
    # research boundary search. No default split or timing policy is changed.
    $tokenMap=Get-PvsCaptionTokenMap -Text $Text -MaxCharacters $MaxCharacters
    if($null -eq $tokenMap){return @()}
    $flat=$tokenMap.Text;$tokens=$tokenMap.Tokens
    $protectedBreaks=$tokenMap.ProtectedBreaks;$titleColons=$tokenMap.TitleColons
    $wordStarts=$tokenMap.WordStarts;$wordEnds=$tokenMap.WordEnds

    # Whisper can make adjacent word timestamps touch even across real breaths.
    # Associate measured intervals with plausible mapped word boundaries, not
    # merely character counts. ASR word edges can extend into a real pause.
    $timingsByWord = @{}
    foreach ($timing in $WordTimings) {
        if ($null -ne $timing -and $timing.PSObject.Properties['TargetWordIndex']) {
            $timingsByWord[[int]$timing.TargetWordIndex] = $timing
        }
    }
    $breathsByTokenEnd = @{}
    $wordBoundaries = New-Object System.Collections.Generic.List[object]
    for ($tokenIndex = 0; $tokenIndex -lt $tokens.Count - 1; $tokenIndex++) {
        if ($protectedBreaks[$tokenIndex]) { continue }
        $leftWordIndex = $wordEnds[$tokenIndex]
        $rightWordIndex = $wordStarts[$tokenIndex + 1]
        if (-not $timingsByWord.ContainsKey($leftWordIndex) -or -not $timingsByWord.ContainsKey($rightWordIndex)) { continue }
        $leftTiming = $timingsByWord[$leftWordIndex]
        $rightTiming = $timingsByWord[$rightWordIndex]
        if ([int]$leftTiming.Chapter -ne [int]$rightTiming.Chapter) { continue }
        $wordBoundaries.Add([pscustomobject]@{
            TokenIndex = $tokenIndex
            Seconds = ([double]$leftTiming.End + [double]$rightTiming.Start) / 2.0
            Punctuation = $tokens[$tokenIndex] -match '[,;:.!?…]$'
            LeftStart = [double]$leftTiming.Start
            LeftEnd = [double]$leftTiming.End
            RightStart = [double]$rightTiming.Start
            RightEnd = [double]$rightTiming.End
        })
    }
    foreach ($silence in $VoiceSilences) {
        if ([double]$silence.Duration -lt 0.16) { continue }
        $center = ([double]$silence.Start + [double]$silence.End) / 2.0
        $nearest = $null
        $nearestDistance = [double]::PositiveInfinity
        # Resolve punctuation pauses before nearest-word breaths. ASR can put
        # following words inside a comma pause; snapping it to those words
        # makes their caption vanish before they are actually spoken.
        foreach ($boundary in $wordBoundaries) {
            if (-not $boundary.Punctuation) { continue }
            $distance = [Math]::Abs([double]$boundary.Seconds - $center)
            if ($distance -gt 0.5 -or [double]$silence.End -le $boundary.LeftStart -or [double]$silence.Start -ge $boundary.RightEnd + 0.2) { continue }
            if ($distance -lt $nearestDistance) { $nearest=$boundary; $nearestDistance=$distance }
        }
        if ($null -ne $nearest) {
            $key=[int]$nearest.TokenIndex
            if (-not $breathsByTokenEnd.ContainsKey($key) -or [double]$silence.Duration -gt [double]$breathsByTokenEnd[$key].Duration) {
                $breathsByTokenEnd[$key]=[pscustomobject]@{Center=$center;Duration=[double]$silence.Duration}
            }
            continue
        }
        foreach ($boundary in $wordBoundaries) {
            $distance = [Math]::Abs([double]$boundary.Seconds - $center)
            # Keep the narrow match for normal timestamps. A longer measured
            # pause may also occupy the trailing edge of an ASR word.
            # Recover only that bounded edge drift, never any distant valley
            # or a brief low-energy dip in the middle of a spoken word.
            $trailingPause = [double]$silence.Start -ge $boundary.LeftStart + 0.08 -and [double]$silence.End -le $boundary.LeftEnd -and $boundary.LeftEnd - [double]$silence.End -le 0.2 -and $boundary.RightStart -ge [double]$silence.End
            $edgeDrift = [double]$silence.Duration -ge 0.2 -and $distance -le 0.5 -and $trailingPause
            if ($distance -gt 0.16 -and -not $edgeDrift) { continue }
            if ($distance -lt $nearestDistance) { $nearest = $boundary; $nearestDistance = $distance }
        }
        if ($null -eq $nearest) { continue }
        $key = [int]$nearest.TokenIndex
        if (-not $breathsByTokenEnd.ContainsKey($key) -or [double]$silence.Duration -gt [double]$breathsByTokenEnd[$key].Duration) {
            $breathsByTokenEnd[$key] = [pscustomobject]@{ Center=$center; Duration=[double]$silence.Duration }
        }
    }

    $ranges = New-Object System.Collections.Generic.List[object]
    $clauseStart = 0
    while ($clauseStart -lt $tokens.Count) {
        # Strong sentence endings remain natural boundaries. A weak pause is
        # preferred only after a readable phrase, not a one/two-word fragment.
        $clauseEnd = $tokens.Count - 1
        for ($tokenIndex = $clauseStart; $tokenIndex -lt $tokens.Count - 1; $tokenIndex++) {
            if ($titleColons[$tokenIndex] -or $tokens[$tokenIndex] -notmatch '[,;:.!?…]$') { continue }
            $strong=$tokens[$tokenIndex] -match '[.!?…]$'
            $phraseLength=($tokens[$clauseStart..$tokenIndex] -join ' ').Length
            if (-not $strong -and ($tokenIndex-$clauseStart+1 -lt 3 -or $phraseLength -lt [Math]::Min(12,[int][Math]::Floor($MaxCharacters*0.4)))) { continue }
            $clauseEnd=$tokenIndex; break
        }
        $clauseRanges = New-Object System.Collections.Generic.List[object]
        $cursor = $clauseStart
        while ($cursor -le $clauseEnd) {
            $first = $cursor
            $length = 0
            for ($candidate = $first; $candidate -le $clauseEnd; $candidate++) {
                $candidateLength = $length + $(if ($candidate -gt $first) { 1 } else { 0 }) + $tokens[$candidate].Length
                if ($candidateLength -gt $MaxCharacters) { break }
                $length = $candidateLength
                $cursor = $candidate + 1
            }
            $chosenEnd = $cursor - 1
            if ($chosenEnd -lt $clauseEnd) {
                while ($chosenEnd -ge $first -and $protectedBreaks[$chosenEnd]) { $chosenEnd-- }
                if ($chosenEnd -lt $first) { throw "CAPTION_NO_SAFE_LEXICAL_BOUNDARY:$first-$clauseEnd" }
                $cursor = $chosenEnd + 1
                $minimumNaturalLength = [Math]::Min(18, [Math]::Max(8, [int][Math]::Floor($MaxCharacters * 0.4)))
                $bestPauseEnd = -1
                $bestPauseDuration = 0.0
                for ($pauseIndex = $first; $pauseIndex -le $chosenEnd; $pauseIndex++) {
                    if (-not $breathsByTokenEnd.ContainsKey($pauseIndex) -or $clauseEnd - $pauseIndex -lt 3) { continue }
                    $candidateText = ($tokens[$first..$pauseIndex] -join ' ')
                    if ($candidateText.Length -lt $minimumNaturalLength) { continue }
                    $duration = [double]$breathsByTokenEnd[$pauseIndex].Duration
                    if ($duration -gt $bestPauseDuration -or ($duration -eq $bestPauseDuration -and $pauseIndex -gt $bestPauseEnd)) {
                        $bestPauseDuration = $duration
                        $bestPauseEnd = $pauseIndex
                    }
                }
                if ($bestPauseEnd -ge 0) {
                    $chosenEnd = $bestPauseEnd
                    $cursor = $chosenEnd + 1
                } else {
                    # Look a few characters beyond the limit for a measured
                    # breath; split the preceding phrase once so it still fits.
                    $lookaheadPause = -1
                    $lookaheadDuration = 0.0
                    for ($pauseIndex = $chosenEnd + 1; $pauseIndex -lt $clauseEnd - 2 -and $pauseIndex -le $chosenEnd + 2; $pauseIndex++) {
                        if ($protectedBreaks[$pauseIndex]) { continue }
                        if (-not $breathsByTokenEnd.ContainsKey($pauseIndex)) { continue }
                        if ($tokens[$pauseIndex] -match '^(?i:\u0111\u1EC3|v\u00E0|c\u1EE7a|m\u1ED9t|nh\u1EEFng|c\u00E1c|m\u00E0|v\u1EDBi|c\u00F3|l\u00E0|s\u1EBD|\u0111ang|\u0111\u01B0\u1EE3c|b\u1ECB)$') { continue }
                        $spanLength = ($tokens[$first..$pauseIndex] -join ' ').Length
                        if ($spanLength -gt $MaxCharacters + 6) { break }
                        $duration = [double]$breathsByTokenEnd[$pauseIndex].Duration
                        if ($duration -gt $lookaheadDuration) { $lookaheadPause = $pauseIndex; $lookaheadDuration = $duration }
                    }
                    if ($lookaheadPause -ge 0) {
                        $bestMid = -1
                        $bestMidScore = [double]::PositiveInfinity
                        for ($mid = $first + 1; $mid -le $lookaheadPause - 2; $mid++) {
                            if ($protectedBreaks[$mid]) { continue }
                            $leftText = ($tokens[$first..$mid] -join ' ')
                            $rightText = ($tokens[($mid + 1)..$lookaheadPause] -join ' ')
                            if ($leftText.Length -gt $MaxCharacters -or $rightText.Length -gt $MaxCharacters) { continue }
                            $score = [Math]::Abs($leftText.Length - $rightText.Length)
                            if ($mid - $first + 1 -lt 3 -or $lookaheadPause - $mid -lt 3) { $score += 1000 }
                            if ($tokens[$mid] -match '^(?i:c\u00F3|l\u00E0|v\u00E0|c\u1EE7a|nh\u1EEFng|c\u00E1c|m\u1ED9t|\u0111\u00E3|\u0111ang|s\u1EBD|b\u1ECB|\u0111\u01B0\u1EE3c|v\u1EDBi|trong|cho|t\u1EEB|v\u1EC1|\u0111\u1EBFn|r\u1EA5t|qu\u00E1|c\u0169ng)$') { $score += 10 }
                            if ($tokens[$mid + 1] -match '^(?i:\u1EA5y|\u0111\u00F3|m\u00E0|n\u00EAn|th\u00EC)$') { $score += 30 }
                            if ($breathsByTokenEnd.ContainsKey($mid)) { $score -= 100 }
                            if ($score -lt $bestMidScore) { $bestMidScore = $score; $bestMid = $mid }
                        }
                        if ($bestMid -ge 0) {
                            $clauseRanges.Add([pscustomobject]@{ Start=$first; End=$bestMid })
                            $clauseRanges.Add([pscustomobject]@{ Start=$bestMid + 1; End=$lookaheadPause })
                            $cursor = $lookaheadPause + 1
                            continue
                        }
                    }
                }
            }
            $clauseRanges.Add([pscustomobject]@{ Start=$first; End=$chosenEnd })
        }

        # Preserve the previous orphan-tail balancing when no new breath is needed.
        if ($clauseRanges.Count -gt 1) {
            $lastRange = $clauseRanges[$clauseRanges.Count - 1]
            $previousRange = $clauseRanges[$clauseRanges.Count - 2]
            $lastText = ($tokens[$lastRange.Start..$lastRange.End] -join ' ')
            if ($lastRange.End - $lastRange.Start -lt 2 -or $lastText.Length -lt [Math]::Floor($MaxCharacters * 0.4)) {
                $bestScore = [double]::PositiveInfinity
                $bestEnd = $previousRange.End
                $pairWordCount = $lastRange.End - $previousRange.Start + 1
                $minimumWords = if ($pairWordCount -ge 6) { 3 } elseif ($pairWordCount -ge 4) { 2 } else { 1 }
                for ($candidate = $previousRange.Start; $candidate -lt $lastRange.End; $candidate++) {
                    if ($protectedBreaks[$candidate]) { continue }
                    $leftText = ($tokens[$previousRange.Start..$candidate] -join ' ')
                    $rightText = ($tokens[($candidate + 1)..$lastRange.End] -join ' ')
                    if ($leftText.Length -gt $MaxCharacters -or $rightText.Length -gt $MaxCharacters) { continue }
                    $leftWords = $candidate - $previousRange.Start + 1
                    $rightWords = $lastRange.End - $candidate
                    $score = [Math]::Abs($leftText.Length - $rightText.Length)
                    if ($leftWords -lt $minimumWords -or $rightWords -lt $minimumWords) { $score += 10000 }
                    if ($tokens[$candidate] -match '^(?i:c\u00F3|l\u00E0|v\u00E0|c\u1EE7a|nh\u1EEFng|c\u00E1c|m\u1ED9t|\u0111\u00E3|\u0111ang|s\u1EBD|b\u1ECB|\u0111\u01B0\u1EE3c|v\u1EDBi|trong|cho|t\u1EEB|v\u1EC1|\u0111\u1EBFn|r\u1EA5t|qu\u00E1|c\u0169ng)$') { $score += 10 }
                    if ($breathsByTokenEnd.ContainsKey($candidate)) { $score -= 1000 }
                    if ($score -lt $bestScore) { $bestScore = $score; $bestEnd = $candidate }
                }
                if (-not $protectedBreaks[$bestEnd]) {
                    $previousRange.End = $bestEnd
                    $lastRange.Start = $bestEnd + 1
                }
            }
        }
        foreach ($range in $clauseRanges) { $ranges.Add($range) }
        $clauseStart = $clauseEnd + 1
    }

    $chunks = New-Object System.Collections.Generic.List[object]
    foreach ($range in $ranges) {
        if ($range.End -lt $tokens.Count - 1 -and $protectedBreaks[$range.End]) {
            throw "CAPTION_PROTECTED_PHRASE_SPLIT:$($tokens[$range.End]) $($tokens[$range.End + 1])"
        }
        $chunkText = ($tokens[$range.Start..$range.End] -join ' ')
        $chunks.Add([pscustomobject]@{
            Text = $chunkText
            CharacterCount = $chunkText.Length
            StartWordIndex = $wordStarts[$range.Start]
            EndWordIndex = $wordEnds[$range.End]
            PauseCenter = if ($breathsByTokenEnd.ContainsKey([int]$range.End)) { [double]$breathsByTokenEnd[[int]$range.End].Center } else { $null }
        })
    }
    return $chunks.ToArray()
}

function Split-PvsVoiceAlignedCaptionCue {
    param(
        [Parameter(Mandatory)]$Cue,
        [Parameter(Mandatory)][int]$MaxCharacters,
        [Parameter(Mandatory)][double]$FrameRate,
        [object[]]$VoiceSilences = @()
    )
    if($Cue.PSObject.Properties['CaptionTimingRevision'] -and $Cue.CaptionTimingRevision -eq 'dtw-word-boundary-v1'){
        return @(Split-PvsAcousticCaptionCue -Cue $Cue -MaxCharacters $MaxCharacters -FrameRate $FrameRate -VoiceSilences $VoiceSilences)
    }
    $wordTimings = @()
    $captionStart=if($Cue.PSObject.Properties['CaptionStart']){[double]$Cue.CaptionStart}else{[double]$Cue.Start}
    $captionEnd=if($Cue.PSObject.Properties['CaptionEnd']){[double]$Cue.CaptionEnd}else{[double]$Cue.End}
    $availableTimings=if($Cue.PSObject.Properties['CaptionWordTimings']){$Cue.CaptionWordTimings}elseif($Cue.PSObject.Properties['WordTimings']){$Cue.WordTimings}else{@()}
    if (@($availableTimings).Count) {
        $wordTimings = @($availableTimings | Where-Object {
            $null -ne $_.Start -and $null -ne $_.End -and [double]$_.End -gt [double]$_.Start
        } | Sort-Object TargetWordIndex)
    }
    $relevantSilences = @($VoiceSilences | Where-Object {
        [double]$_.End -ge $captionStart - 0.1 -and [double]$_.Start -le $captionEnd + 0.1
    })
    $chunks = @(Get-PvsCaptionTextChunks -Text ([string]$Cue.Text) -MaxCharacters $MaxCharacters -WordTimings $wordTimings -VoiceSilences $relevantSilences)
    if ($chunks.Count -eq 0) { return @() }

    $cueStartFrame = [int][Math]::Round($captionStart * $FrameRate)
    $cueEndFrame = [int][Math]::Round($captionEnd * $FrameRate)
    # Whisper's first/last word may extend into measured silence. Keep the
    # edit-plan cue untouched; only tighten the corresponding caption edges.
    if ($wordTimings.Count -gt 0) {
        $firstWord = $wordTimings[0]
        $lastWord = $wordTimings[$wordTimings.Count - 1]
        foreach ($silence in $relevantSilences) {
            if ([double]$silence.Duration -lt 0.18) { continue }
            if ([double]$silence.Start -le $captionStart -and [double]$silence.End -gt $captionStart) {
                $speechStartFrame = [int][Math]::Ceiling(([double]$silence.End * $FrameRate) - 0.0000001)
                if ([double]$silence.End -le [double]$firstWord.End + 0.15 -and $speechStartFrame -gt $cueStartFrame -and $cueEndFrame - $speechStartFrame -ge $chunks.Count * 9) {
                    $cueStartFrame = $speechStartFrame
                }
            }
            if ([double]$silence.Start -lt $captionEnd -and [double]$silence.End -ge $captionEnd) {
                $speechEndFrame = [int][Math]::Floor(([double]$silence.Start * $FrameRate) + 0.0000001)
                if ([double]$silence.Start -ge [double]$lastWord.Start + 0.08 -and $speechEndFrame -lt $cueEndFrame -and $speechEndFrame - $cueStartFrame -ge $chunks.Count * 9) {
                    $cueEndFrame = $speechEndFrame
                }
            }
        }
    }
    if ($cueEndFrame - $cueStartFrame -lt $chunks.Count) {
        throw "CAPTION_INTERVAL_TOO_SHORT:$($Cue.Index):$cueStartFrame-$($cueEndFrame):$($chunks.Count)"
    }
    $boundaries = New-Object 'int[]' ($chunks.Count + 1)
    $voiceBoundaries = New-Object 'bool[]' ($chunks.Count + 1)
    $boundaries[0] = $cueStartFrame
    $boundaries[$chunks.Count] = $cueEndFrame

    for ($boundaryIndex = 1; $boundaryIndex -lt $chunks.Count; $boundaryIndex++) {
        $leftTiming = @($wordTimings | Where-Object { [int]$_.TargetWordIndex -le [int]$chunks[$boundaryIndex - 1].EndWordIndex } | Select-Object -Last 1)
        $rightTiming = @($wordTimings | Where-Object { [int]$_.TargetWordIndex -ge [int]$chunks[$boundaryIndex].StartWordIndex } | Select-Object -First 1)
        if ($leftTiming.Count -ne 1 -or $rightTiming.Count -ne 1 -or [int]$leftTiming[0].Chapter -ne [int]$rightTiming[0].Chapter) {
            throw "CAPTION_WORD_TIMING_REQUIRED:$($Cue.Index):boundary-$boundaryIndex"
        }
        $boundarySeconds = if ($null -ne $chunks[$boundaryIndex - 1].PauseCenter) {
            [double]$chunks[$boundaryIndex - 1].PauseCenter
        } else {
            ([double]$leftTiming[0].End + [double]$rightTiming[0].Start) / 2.0
        }
        # A punctuation pause may be farther from its Whisper boundary than an
        # adjacent word is. Prefer the actual quiet interval for that boundary.
        if ([string]$chunks[$boundaryIndex - 1].Text -match '[,;:.!?…]$') {
            $bestSilenceDistance = 0.5
            foreach ($silence in $relevantSilences) {
                if ([double]$silence.Duration -lt 0.18) { continue }
                $center = ([double]$silence.Start + [double]$silence.End) / 2.0
                $distance = [Math]::Abs($center - [double]$leftTiming[0].End)
                if ($distance -ge $bestSilenceDistance -or [double]$silence.End -le [double]$leftTiming[0].Start -or [double]$silence.Start -ge [double]$rightTiming[0].End + 0.2) { continue }
                $bestSilenceDistance = $distance
                $boundarySeconds = $center
            }
        }
        $idealFrame = [int][Math]::Round($boundarySeconds * $FrameRate)
        $voiceBoundaries[$boundaryIndex] = $true
        $minimumFrame = $boundaries[$boundaryIndex - 1] + 1
        $maximumFrame = $cueEndFrame - ($chunks.Count - $boundaryIndex)
        $boundaries[$boundaryIndex] = [Math]::Max($minimumFrame, [Math]::Min($maximumFrame, $idealFrame))
    }

    $parts = New-Object System.Collections.Generic.List[object]
    for ($partIndex = 0; $partIndex -lt $chunks.Count; $partIndex++) {
        $parts.Add([pscustomobject]@{
            Text = [string]$chunks[$partIndex].Text
            Start = [double]$boundaries[$partIndex] / $FrameRate
            End = [double]$boundaries[$partIndex + 1] / $FrameRate
            StartFrame = [int]$boundaries[$partIndex]
            EndFrame = [int]$boundaries[$partIndex + 1]
            PartIndex = $partIndex + 1
            PartCount = $chunks.Count
            VoiceBoundaryAligned = ($chunks.Count -eq 1 -or ($partIndex -gt 0 -and $voiceBoundaries[$partIndex]))
        })
    }
    return $parts.ToArray()
}

function Add-PvsCaptionEdgePadding {
    param(
        [Parameter(Mandatory)][object[]]$Captions,
        [Parameter(Mandatory)][double]$FrameRate,
        [Parameter(Mandatory)][int]$TimelineEndFrame,
        [ValidateRange(0, 30)][int]$PaddingFrames = 0
    )
    # Big update S6 decision (2026-10-25): keep caption timing as aligned, no
    # edge padding by default. The pass still runs with 0 frames because it also
    # resolves the planner's one-frame overlap and rejects unsafe overlaps.
    if ($Captions.Count -eq 0) { return }
    $startFrames = New-Object 'int[]' $Captions.Count
    $endFrames = New-Object 'int[]' $Captions.Count
    for ($index = 0; $index -lt $Captions.Count; $index++) {
        $startFrames[$index] = [int][Math]::Round([double]$Captions[$index].Start * $FrameRate)
        $endFrames[$index] = [int][Math]::Round([double]$Captions[$index].End * $FrameRate)
        if ($endFrames[$index] -le $startFrames[$index]) { throw "CAPTION_PADDING_INVALID_INTERVAL:$index" }
    }
    if ([int]$Captions[0].PartIndex -eq 1) {
        $startFrames[0] -= [Math]::Min($PaddingFrames, [Math]::Max(0, $startFrames[0]))
    }
    for ($index = 0; $index -lt $Captions.Count - 1; $index++) {
        $gap = $startFrames[$index + 1] - $endFrames[$index]
        if ($gap -lt 0) {
            # The planner's one-frame minimum for a caption clipped at a safe
            # voice cut can overlap its next part by one frame. Resolve only
            # that rounding-sized overlap, without touching video/audio cuts.
            if ($gap -lt -1) { throw "CAPTION_OVERLAP_TIMING_UNSAFE:${index}:$(-$gap)" }
            $minimumBoundary = $startFrames[$index] + 1
            $maximumBoundary = $endFrames[$index + 1] - 1
            if ($minimumBoundary -gt $maximumBoundary) { throw "CAPTION_OVERLAP_INTERVAL_TOO_SMALL:$index" }
            $shared = [int][Math]::Ceiling(($endFrames[$index] + $startFrames[$index + 1]) / 2.0)
            $shared = [Math]::Max($minimumBoundary, [Math]::Min($maximumBoundary, $shared))
            $endFrames[$index] = $shared
            $startFrames[$index + 1] = $shared
            continue
        }
        if ($gap -le 0) { continue }
        $extendEnd = [int]$Captions[$index].PartIndex -eq [int]$Captions[$index].PartCount -or ($Captions[$index].PSObject.Properties['IndependentSpeechEdges'] -and $Captions[$index].IndependentSpeechEdges)
        $advanceStart = [int]$Captions[$index + 1].PartIndex -eq 1 -or ($Captions[$index+1].PSObject.Properties['IndependentSpeechEdges'] -and $Captions[$index+1].IndependentSpeechEdges)
        $endPadding = 0
        $startPadding = 0
        if ($extendEnd -and $advanceStart) {
            $endPadding = [Math]::Min($PaddingFrames, [int][Math]::Ceiling($gap / 2.0))
            $startPadding = [Math]::Min($PaddingFrames, $gap - $endPadding)
        } elseif ($extendEnd) {
            $endPadding = [Math]::Min($PaddingFrames, $gap)
        } elseif ($advanceStart) {
            $startPadding = [Math]::Min($PaddingFrames, $gap)
        }
        $endFrames[$index] += $endPadding
        $startFrames[$index + 1] -= $startPadding
    }
    $lastIndex = $Captions.Count - 1
    if ([int]$Captions[$lastIndex].PartIndex -eq [int]$Captions[$lastIndex].PartCount) {
        $endFrames[$lastIndex] += [Math]::Min($PaddingFrames, [Math]::Max(0, $TimelineEndFrame - $endFrames[$lastIndex]))
    }
    for ($index = 0; $index -lt $Captions.Count; $index++) {
        $Captions[$index].Start = [Math]::Round($startFrames[$index] / $FrameRate, 6)
        $Captions[$index].End = [Math]::Round($endFrames[$index] / $FrameRate, 6)
    }
}
