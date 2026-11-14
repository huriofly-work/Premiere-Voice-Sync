# Frozen Auto edit 2.20.40 alignment baseline, used only as a parity oracle.
# No runtime source imports this file. Keep the baseline independent of refactors.

function ConvertTo-NormalizedWords {
    param([AllowEmptyString()][string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return @() }
    $lower = $Text.ToLowerInvariant().Normalize([Text.NormalizationForm]::FormC)
    $matches = [regex]::Matches($lower, '[\p{L}\p{N}]+')
    $words = New-Object System.Collections.Generic.List[string]
    foreach ($match in $matches) { $words.Add($match.Value) }
    return $words.ToArray()
}

function Convert-WhisperJsonToWords {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][int]$ChapterIndex
    )
    $json = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
    $segments = if ($null -ne $json.transcription) { @($json.transcription) } elseif ($null -ne $json.segments) { @($json.segments) } else { @() }
    $result = New-Object System.Collections.Generic.List[object]
    foreach ($segment in $segments) {
        $start = 0.0
        $end = 0.0
        if ($null -ne $segment.offsets) {
            $start = [double]$segment.offsets.from / 1000.0
            $end = [double]$segment.offsets.to / 1000.0
        } elseif ($null -ne $segment.start) {
            $start = [double]$segment.start
            $end = [double]$segment.end
        } elseif ($null -ne $segment.timestamps) {
            . "$PSScriptRoot\Srt.ps1"
            $start = ConvertFrom-SrtTimestamp (($segment.timestamps.from -replace '\.', ','))
            $end = ConvertFrom-SrtTimestamp (($segment.timestamps.to -replace '\.', ','))
        }
        $words = @(ConvertTo-NormalizedWords ([string]$segment.text))
        if ($words.Count -eq 0) { continue }
        $slice = [Math]::Max(0.02, ($end - $start) / $words.Count)
        for ($i = 0; $i -lt $words.Count; $i++) {
            $result.Add([pscustomobject]@{
                Text = $words[$i]
                Start = $start + ($slice * $i)
                End = if ($i -eq $words.Count - 1) { $end } else { $start + ($slice * ($i + 1)) }
                Chapter = $ChapterIndex
            })
        }
    }
    return $result.ToArray()
}

function Get-SequentialWordMapping {
    param(
        [Parameter(Mandatory)][string[]]$TargetWords,
        [Parameter(Mandatory)][object[]]$RecognizedWords
    )
    # Compilation costs more than the reference for tiny recovery windows.
    # Keep those on the old mapper and accelerate only sizeable matrices.
    if([long]$TargetWords.Count*$RecognizedWords.Count -ge 100000 -and
        -not (Get-Variable PvsWordMapperDisabled -Scope Script -ErrorAction SilentlyContinue)){
        $stringsOnly=$true
        foreach($word in $RecognizedWords){if($word.Text -isnot [string]){$stringsOnly=$false;break}}
        if($stringsOnly){
            try{
                if(-not (Get-Command Invoke-PvsCompiledWordMapping -CommandType Function -ErrorAction SilentlyContinue)){
                    . $script:PvsWordMapperPath
                }
                return Invoke-PvsCompiledWordMapping $TargetWords $RecognizedWords
            }catch{
                # Compiler policy/runtime availability is not required to
                # operate. Do not retry repeatedly in the same process.
                $script:PvsWordMapperDisabled=$true
                Write-Verbose 'Compiled word mapper unavailable; using reference mapper.'
            }
        }
    }
    return Get-PvsReferenceWordMapping $TargetWords $RecognizedWords
}

function Get-PvsReferenceWordMapping {
    param(
        [Parameter(Mandatory)][string[]]$TargetWords,
        [Parameter(Mandatory)][object[]]$RecognizedWords
    )
    $n = $TargetWords.Count
    $m = $RecognizedWords.Count
    if ($n -eq 0 -or $m -eq 0) { return @() }
    $cost = New-Object 'int[,]' ($n + 1), ($m + 1)
    $back = New-Object 'byte[,]' ($n + 1), ($m + 1)
    for ($i = 1; $i -le $n; $i++) { $cost[$i,0] = $i; $back[$i,0] = 1 }
    for ($j = 1; $j -le $m; $j++) { $cost[0,$j] = $j; $back[0,$j] = 2 }
    for ($i = 1; $i -le $n; $i++) {
        for ($j = 1; $j -le $m; $j++) {
            $sub = $cost[($i - 1),($j - 1)] + $(if ($TargetWords[$i - 1] -eq $RecognizedWords[$j - 1].Text) { 0 } else { 1 })
            $del = $cost[($i - 1),$j] + 1
            $ins = $cost[$i,($j - 1)] + 1
            if ($sub -le $del -and $sub -le $ins) { $cost[$i,$j] = $sub; $back[$i,$j] = 0 }
            elseif ($del -le $ins) { $cost[$i,$j] = $del; $back[$i,$j] = 1 }
            else { $cost[$i,$j] = $ins; $back[$i,$j] = 2 }
        }
    }
    $mapping = New-Object 'int[]' $n
    for ($k = 0; $k -lt $n; $k++) { $mapping[$k] = -1 }
    $i = $n; $j = $m
    while ($i -gt 0 -or $j -gt 0) {
        $direction = $back[$i,$j]
        if ($i -gt 0 -and $j -gt 0 -and $direction -eq 0) {
            $mapping[$i - 1] = $j - 1
            $i--; $j--
        } elseif ($i -gt 0 -and ($j -eq 0 -or $direction -eq 1)) { $i-- }
        else { $j-- }
    }
    return $mapping
}

function Align-CuesToRecognizedWords {
    param(
        [Parameter(Mandatory)][object[]]$Cues,
        [Parameter(Mandatory)][object[]]$RecognizedWords,
        [Parameter(Mandatory)][object[]]$VoiceClips
    )
    $targetWords = New-Object System.Collections.Generic.List[string]
    $cueStarts = New-Object 'int[]' $Cues.Count
    $cueEnds = New-Object 'int[]' $Cues.Count
    for ($cueIndex = 0; $cueIndex -lt $Cues.Count; $cueIndex++) {
        $cueStarts[$cueIndex]=$targetWords.Count
        foreach ($word in (ConvertTo-NormalizedWords $Cues[$cueIndex].Text)) {
            $targetWords.Add($word)
        }
        $cueEnds[$cueIndex]=$targetWords.Count
    }
    $mapping = Get-SequentialWordMapping -TargetWords ($targetWords.ToArray()) -RecognizedWords $RecognizedWords
    $output = New-Object System.Collections.Generic.List[object]
    for ($cueIndex = 0; $cueIndex -lt $Cues.Count; $cueIndex++) {
        $recognizedIndexes = New-Object System.Collections.Generic.List[int]
        $alignedWords = New-Object System.Collections.Generic.List[object]
        $cueWordIndex = 0
        $exact = 0
        $total = 0
        # Target words for each cue are contiguous. Visit that range once,
        # not every word twice for every cue. Mapping/tie rules are unchanged.
        for ($w = $cueStarts[$cueIndex]; $w -lt $cueEnds[$cueIndex]; $w++) {
            if ($mapping[$w] -ge 0) {
                $recognizedIndex = [int]$mapping[$w]
                $recognizedWord = $RecognizedWords[$recognizedIndex]
                $recognizedChapter = [int]$recognizedWord.Chapter
                $recognizedChapterStart = if ($recognizedChapter -ge 0 -and $recognizedChapter -lt $VoiceClips.Count) { [double]$VoiceClips[$recognizedChapter].start } else { 0.0 }
                $recognizedIndexes.Add($recognizedIndex)
                $total++
                if($targetWords[$w] -eq $recognizedWord.Text){$exact++}
                $alignedWords.Add([pscustomobject]@{
                    TargetWordIndex = $cueWordIndex
                    Text = [string]$targetWords[$w]
                    Start = $recognizedChapterStart + [double]$recognizedWord.Start
                    End = $recognizedChapterStart + [double]$recognizedWord.End
                    Chapter = $recognizedChapter
                    Exact = ([string]$targetWords[$w] -eq [string]$recognizedWord.Text)
                })
            }
            $cueWordIndex++
        }
        if ($recognizedIndexes.Count -eq 0) {
            $output.Add([pscustomobject]@{ Index=$cueIndex+1; OriginalStart=[double]$Cues[$cueIndex].Start; OriginalEnd=[double]$Cues[$cueIndex].End; Start=$null; End=$null; Text=$Cues[$cueIndex].Text; Chapter=-1; Confidence=0.0; WordTimings=@() })
            continue
        }
        $first = $RecognizedWords[($recognizedIndexes | Measure-Object -Minimum).Minimum]
        $last = $RecognizedWords[($recognizedIndexes | Measure-Object -Maximum).Maximum]
        $chapterGroups = $recognizedIndexes | ForEach-Object { $RecognizedWords[$_].Chapter } | Group-Object | Sort-Object Count -Descending
        $chapter = [int]$chapterGroups[0].Name
        $chapterStart = if ($chapter -lt $VoiceClips.Count) { [double]$VoiceClips[$chapter].start } else { 0.0 }
        $output.Add([pscustomobject]@{
            Index = $cueIndex + 1
            OriginalStart = [double]$Cues[$cueIndex].Start
            OriginalEnd = [double]$Cues[$cueIndex].End
            Start = $chapterStart + [double]$first.Start
            End = $chapterStart + [double]$last.End
            Text = $Cues[$cueIndex].Text
            Chapter = $chapter
            Confidence = if ($total -gt 0) { [Math]::Round($exact / [double]$total, 3) } else { 0.0 }
            WordTimings = $alignedWords.ToArray()
        })
    }
    return $output.ToArray()
}

function Repair-PvsMissingCueWordTimings {
    param(
        [Parameter(Mandatory)][object[]]$Cues,
        [Parameter(Mandatory)][object[]]$VoiceClips,
        [Parameter(Mandatory)][scriptblock]$RecognizeWindow
    )
    # Retry only a small, wholly missing block between trusted anchors (or an
    # anchor and the chapter edge). Never remap already aligned cues or invent
    # word timestamps from character counts / the original SRT timecodes.
    $recovered = New-Object System.Collections.Generic.List[int]
    $cursor = 0
    while ($cursor -lt $Cues.Count) {
        if ($null -ne $Cues[$cursor].Start -and $null -ne $Cues[$cursor].End -and [int]$Cues[$cursor].Chapter -ge 0) { $cursor++; continue }
        $first = $cursor
        while ($cursor -lt $Cues.Count -and ($null -eq $Cues[$cursor].Start -or $null -eq $Cues[$cursor].End -or [int]$Cues[$cursor].Chapter -lt 0)) { $cursor++ }
        $last = $cursor - 1
        $previous = if ($first -gt 0) { $Cues[$first - 1] } else { $null }
        $next = if ($cursor -lt $Cues.Count) { $Cues[$cursor] } else { $null }
        if ($last - $first + 1 -gt 10 -or ($null -eq $previous -and $null -eq $next)) { continue }
        if (($null -ne $previous -and [double]$previous.Confidence -lt 0.8) -or ($null -ne $next -and [double]$next.Confidence -lt 0.8)) { continue }
        $chapter = if ($null -ne $previous) { [int]$previous.Chapter } else { [int]$next.Chapter }
        if ($chapter -lt 0 -or $chapter -ge $VoiceClips.Count -or ($null -ne $next -and [int]$next.Chapter -ne $chapter)) { continue }
        $voice = $VoiceClips[$chapter]
        $start = [Math]::Max([double]$voice.start, $(if ($null -ne $previous) { [double]$previous.End } else { [double]$voice.start }))
        $end = [Math]::Min([double]$voice.end, $(if ($null -ne $next) { [double]$next.Start } else { [double]$voice.end }))
        if ($end - $start -lt 0.2 -or $end - $start -gt 30) { continue }
        $reference = @($Cues[$first..$last])
        $targetCount = @($reference | ForEach-Object { ConvertTo-NormalizedWords $_.Text }).Count
        if ($targetCount -eq 0 -or $targetCount -gt 200) { continue }
        $words = @(& $RecognizeWindow $voice $start $end | Where-Object { $null -ne $_ -and [double]$_.End -gt [double]$_.Start })
        if ($words.Count -eq 0) { continue }
        $local = @(Align-CuesToRecognizedWords -Cues $reference -RecognizedWords $words -VoiceClips @([pscustomobject]@{start=$start;end=$end}))
        $valid = $local.Count -eq $reference.Count
        $exactCount = 0
        foreach ($cue in $local) {
            $expected = @(ConvertTo-NormalizedWords $cue.Text).Count
            $timings = @($cue.WordTimings)
            if ($null -eq $cue.Start -or $null -eq $cue.End -or $cue.Start -lt $start -or $cue.End -gt $end + 0.000001 -or $cue.End -le $cue.Start -or $timings.Count -ne $expected -or [double]$cue.Confidence -lt 0.7) { $valid=$false; break }
            $previousWordEnd = $start
            foreach ($timing in $timings) {
                if ([double]$timing.Start -lt $previousWordEnd - 0.000001 -or [double]$timing.End -gt $end + 0.000001 -or [double]$timing.End -le [double]$timing.Start -or [int]$timing.Chapter -ne 0) { $valid=$false; break }
                $previousWordEnd = [double]$timing.End
                if ([bool]$timing.Exact) { $exactCount++ }
            }
        }
        if (-not $valid -or $exactCount / [double]$targetCount -lt 0.8) { continue }
        for ($offset = 0; $offset -lt $local.Count; $offset++) {
            $cue = $Cues[$first + $offset]
            $cue.Start = [double]$local[$offset].Start
            $cue.End = [Math]::Min($end, [double]$local[$offset].End)
            $cue.Chapter = $chapter
            $cue.Confidence = $local[$offset].Confidence
            $cue.WordTimings = @($local[$offset].WordTimings)
            foreach ($timing in $cue.WordTimings) { $timing.Chapter = $chapter }
            $cue | Add-Member -NotePropertyName WordTimingRecovered -NotePropertyValue $true -Force
            $recovered.Add([int]$cue.Index)
        }
    }
    return $recovered.ToArray()
}

function Repair-PvsBaselineCueIntervals {
    param([object[]]$Cues,[object[]]$VoiceClips,[double]$FrameRate)
    $fps=$FrameRate
    function To-Frame([double]$Seconds){[int][Math]::Round($Seconds*$fps)}
    function From-Frame([int]$Frame){[double]$Frame/$fps}
$recoveredUnalignedCueCount = 0
$cueCursor = 0
while ($cueCursor -lt $cues.Count) {
    $cueIsAligned = $null -ne $cues[$cueCursor].Start -and $null -ne $cues[$cueCursor].End -and [int]$cues[$cueCursor].Chapter -ge 0
    if ($cueIsAligned) { $cueCursor++; continue }
    $runStart = $cueCursor
    while ($cueCursor -lt $cues.Count -and ($null -eq $cues[$cueCursor].Start -or $null -eq $cues[$cueCursor].End -or [int]$cues[$cueCursor].Chapter -lt 0)) { $cueCursor++ }
    $runEnd = $cueCursor - 1
    $previousCue = if ($runStart -gt 0) { $cues[$runStart - 1] } else { $null }
    $nextCue = if ($cueCursor -lt $cues.Count) { $cues[$cueCursor] } else { $null }
    $previousChapter = if ($null -ne $previousCue -and [int]$previousCue.Chapter -ge 0) { [int]$previousCue.Chapter } else { -1 }
    $nextChapter = if ($null -ne $nextCue -and [int]$nextCue.Chapter -ge 0) { [int]$nextCue.Chapter } else { -1 }
    if ($previousChapter -ge 0 -and $nextChapter -ge 0 -and $previousChapter -ne $nextChapter) {
        throw "UNALIGNED_CUE_CROSSES_CHAPTER:$([int]$cues[$runStart].Index)-$([int]$cues[$runEnd].Index)"
    }
    $chapter = if ($previousChapter -ge 0) { $previousChapter } else { $nextChapter }
    if ($chapter -lt 0 -or $chapter -ge $voiceClips.Count) {
        throw "UNALIGNED_CUE_HAS_NO_CHAPTER:$([int]$cues[$runStart].Index)-$([int]$cues[$runEnd].Index)"
    }
    $leftSeconds = if ($null -ne $previousCue -and [int]$previousCue.Chapter -eq $chapter) { [double]$previousCue.End } else { [double]$voiceClips[$chapter].start }
    $rightSeconds = if ($null -ne $nextCue -and [int]$nextCue.Chapter -eq $chapter) { [double]$nextCue.Start } else { [double]$voiceClips[$chapter].end }
    $leftFrame = To-Frame $leftSeconds
    $rightFrame = To-Frame $rightSeconds
    $runCount = $runEnd - $runStart + 1
    if ($rightFrame - $leftFrame -lt $runCount) {
        throw "UNALIGNED_CUE_INTERVAL_TOO_SMALL:$([int]$cues[$runStart].Index)-$([int]$cues[$runEnd].Index):$leftFrame-$rightFrame"
    }
    $weights = @()
    $totalWeight = 0.0
    for ($repairIndex = $runStart; $repairIndex -le $runEnd; $repairIndex++) {
        $weight = [Math]::Max(1.0, [double]$cues[$repairIndex].OriginalEnd - [double]$cues[$repairIndex].OriginalStart)
        $weights += $weight
        $totalWeight += $weight
    }
    $repairCursorFrame = $leftFrame
    $cumulativeWeight = 0.0
    for ($repairOffset = 0; $repairOffset -lt $runCount; $repairOffset++) {
        $repairCue = $cues[$runStart + $repairOffset]
        $cumulativeWeight += [double]$weights[$repairOffset]
        $remainingCueCount = $runCount - $repairOffset - 1
        $idealEndFrame = if ($repairOffset -eq $runCount - 1) { $rightFrame } else { $leftFrame + [int][Math]::Round(($rightFrame - $leftFrame) * ($cumulativeWeight / $totalWeight)) }
        $repairEndFrame = [Math]::Max($repairCursorFrame + 1, [Math]::Min($rightFrame - $remainingCueCount, $idealEndFrame))
        $repairCue.Start = From-Frame $repairCursorFrame
        $repairCue.End = From-Frame $repairEndFrame
        $repairCue.Chapter = $chapter
        $repairCue.Confidence = 0.0
        $repairCue | Add-Member -NotePropertyName TimingRecovered -NotePropertyValue $true -Force
        $repairCursorFrame = $repairEndFrame
        $recoveredUnalignedCueCount++
    }
}
    return $recoveredUnalignedCueCount
}
