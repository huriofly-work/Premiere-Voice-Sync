Set-StrictMode -Version Latest

# Shared lexical/timing core. Edit and subtitle workflows choose their own
# reference scope and failure policy; neither planner nor timeline APIs live here.
$script:PvsWordMapperPath=Join-Path $PSScriptRoot 'WordMapper.ps1'
# Pure lexical data only, bounded to this PowerShell process. Never cache
# reference uniqueness, timing, proof validity, or a mutable caption object.
$script:PvsNormalizedWordCache=New-Object 'System.Collections.Generic.Dictionary[string,string[]]' ([StringComparer]::Ordinal)

function Get-PvsReferenceLexicalWords {
    param([string]$Text,[bool]$CharacterMode=$false)
    if(-not $CharacterMode){return @(ConvertTo-NormalizedWords $Text)}
    return @([regex]::Matches($Text.ToLowerInvariant().Normalize([Text.NormalizationForm]::FormC),'[\u3400-\u9fff\u3040-\u30ff\uac00-\ud7af]|(?:(?![\u3400-\u9fff\u3040-\u30ff\uac00-\ud7af])[\p{L}\p{N}])+') | ForEach-Object {$_.Value})
}

function Convert-PvsReferenceRecognition {
    param($Json,[int]$Chapter,[double]$Duration=[double]::MaxValue,[ValidateSet('Edit','Subtitle')][string]$Mode='Edit',[bool]$CharacterMode=$false,[switch]$PreserveSurface)
    $words=New-Object System.Collections.Generic.List[object]
    $surfaces=New-Object System.Collections.Generic.List[object]
    $segments=if($Json.PSObject.Properties['transcription'] -and ($Mode -eq 'Subtitle' -or $null -ne $Json.transcription)){@($Json.transcription)}elseif($Json.PSObject.Properties['segments']){@($Json.segments)}else{@()}
    foreach($segment in $segments){
        $text=[string]$segment.text
        if($Mode -eq 'Subtitle'){
            $text=[regex]::Replace($text,'(?i)\[(?:[_A-Z0-9]+|music|applause|laughter|silence|noise)\]','').Trim()
            if(-not $text){continue}
        }
        $start=0.0;$end=0.0
        if($segment.PSObject.Properties['offsets'] -and $null -ne $segment.offsets){$start=[double]$segment.offsets.from/1000.0;$end=[double]$segment.offsets.to/1000.0}
        elseif($segment.PSObject.Properties['start'] -and $null -ne $segment.start){$start=[double]$segment.start;$end=[double]$segment.end}
        elseif($Mode -eq 'Edit' -and $segment.PSObject.Properties['timestamps'] -and $null -ne $segment.timestamps){
            . "$PSScriptRoot\Srt.ps1"
            $start=ConvertFrom-SrtTimestamp ($segment.timestamps.from -replace '\.',',')
            $end=ConvertFrom-SrtTimestamp ($segment.timestamps.to -replace '\.',',')
        }elseif($Mode -eq 'Subtitle'){throw 'SUBTITLE_RECOGNITION_TIMESTAMP_MISSING'}
        if($Mode -eq 'Subtitle'){
            $start=[Math]::Max(0.0,[Math]::Min($Duration,$start));$end=[Math]::Max($start,[Math]::Min($Duration,$end))
        }
        $tokens=@(Get-PvsReferenceLexicalWords $text $CharacterMode)
        if($tokens.Count -eq 0){
            if($Mode -eq 'Subtitle' -and $surfaces.Count -gt 0 -and $text -match '^[,;:.!?…，。！？；：、]+$'){$surfaces[$surfaces.Count-1].Text+=$text}
            continue
        }
        if($Mode -eq 'Subtitle' -and $end -le $start){continue}
        $firstWord=$words.Count
        $surfaceMatches=@(if($PreserveSurface){[regex]::Matches($text,'[\p{L}\p{N}]+')})
        $slice=[Math]::Max(0.02,($end-$start)/$tokens.Count)
        for($index=0;$index -lt $tokens.Count;$index++){
            # Edit keeps the established 20ms legacy distribution exactly.
            # Subtitle uses the bounded segment interval and drops zero spans.
            $wordStart=if($Mode -eq 'Edit'){$start+$slice*$index}else{$start+($end-$start)*$index/$tokens.Count}
            $wordEnd=if($Mode -eq 'Edit'){if($index -eq $tokens.Count-1){$end}else{$start+$slice*($index+1)}}else{$start+($end-$start)*($index+1)/$tokens.Count}
            $word=[pscustomobject]@{Text=$tokens[$index];Start=$wordStart;End=$wordEnd;Chapter=$Chapter}
            if($PreserveSurface -and $surfaceMatches.Count -eq $tokens.Count){
                $a=$surfaceMatches[$index];$sliceStart=if($index -eq 0){0}else{$a.Index}
                $sliceEnd=if($index+1 -lt $tokens.Count){$surfaceMatches[$index+1].Index}else{$text.Length}
                $word | Add-Member NoteProperty RecognitionSurfaceText $text
                $word | Add-Member NoteProperty RecognitionSurfaceTokenIndex $index
                $word | Add-Member NoteProperty RecognitionSurfaceSliceStart $sliceStart
                $word | Add-Member NoteProperty RecognitionSurfaceSliceEnd $sliceEnd
                $joinPrevious=$index -gt 0 -and $text.Substring($surfaceMatches[$index-1].Index+$surfaceMatches[$index-1].Length,$a.Index-$surfaceMatches[$index-1].Index-$surfaceMatches[$index-1].Length) -notmatch '\s'
                $joinNext=$index+1 -lt $tokens.Count -and $text.Substring($a.Index+$a.Length,$surfaceMatches[$index+1].Index-$a.Index-$a.Length) -notmatch '\s'
                $word | Add-Member NoteProperty RecognitionSurfaceJoinPrevious $joinPrevious
                $word | Add-Member NoteProperty RecognitionSurfaceJoinNext $joinNext
            }
            if($Mode -eq 'Subtitle' -and $text -match '^\s*\d+[.,]\d{1,2}\s*$'){$word | Add-Member -NotePropertyName NumericSurfaceText -NotePropertyValue $text.Trim()}
            $words.Add($word)
        }
        if($Mode -eq 'Subtitle'){$surfaces.Add([pscustomobject]@{Text=$text;Start=$start;End=$end;FirstWord=$firstWord;LastWord=$words.Count-1})}
    }
    return [pscustomobject]@{Words=$words.ToArray();Surfaces=$surfaces.ToArray()}
}

function Convert-WhisperJsonToWords {
    param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)][int]$ChapterIndex,[switch]$PreserveSurface)
    $json=Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
    return (Convert-PvsReferenceRecognition -Json $json -Chapter $ChapterIndex -Mode Edit -PreserveSurface:$PreserveSurface).Words
}

function ConvertTo-PvsBoundedEditWords {
    param([object[]]$Words,[double]$Duration,[double]$Scale=1.0)
    # Bounds are physical PCM/clip bounds, not inferred speech edges. Preserve
    # the original packets and the legacy zero spans inside the window.
    if([double]::IsNaN($Duration) -or [double]::IsInfinity($Duration) -or $Duration -le 0 -or
        [double]::IsNaN($Scale) -or [double]::IsInfinity($Scale) -or $Scale -le 0){throw 'EDIT_RECOGNITION_WINDOW_INVALID'}
    foreach($word in $Words){
        $a=[double]$word.Start*$Scale;$b=[double]$word.End*$Scale
        if([double]::IsNaN($a) -or [double]::IsNaN($b) -or [double]::IsInfinity($a) -or [double]::IsInfinity($b) -or $a -lt 0 -or $b -lt $a){throw 'EDIT_RECOGNITION_TIMESTAMP_INVALID'}
        if($a -ge $Duration){continue}
        $copy=$word.PSObject.Copy();$copy.Start=$a;$copy.End=[Math]::Min($Duration,$b)
        $copy
    }
}

function New-PvsReferenceWordLayout {
    param([object[]]$Cues,[bool]$CharacterMode=$false)
    $words=New-Object System.Collections.Generic.List[string]
    $wordCue=New-Object System.Collections.Generic.List[int]
    $starts=New-Object 'int[]' $Cues.Count;$ends=New-Object 'int[]' $Cues.Count
    for($index=0;$index -lt $Cues.Count;$index++){
        $starts[$index]=$words.Count
        foreach($word in (Get-PvsReferenceLexicalWords ([string]$Cues[$index].Text) $CharacterMode)){$words.Add($word);$wordCue.Add($index)}
        $ends[$index]=$words.Count
    }
    return [pscustomobject]@{Words=$words.ToArray();CueStarts=$starts;CueEnds=$ends;WordCue=$wordCue.ToArray()}
}

function Convert-PvsReferenceMappingToCues {
    param([object[]]$Cues,$Layout,[int[]]$Mapping,[object[]]$RecognizedWords,[object[]]$VoiceClips,[switch]$PreserveReferenceIndices,[int]$FixedChapter=-1)
    if($Mapping.Count -ne $Layout.Words.Count){throw 'REFERENCE_MAPPING_LENGTH_INVALID'}
    $output=New-Object System.Collections.Generic.List[object]
    for($cueIndex=0;$cueIndex -lt $Cues.Count;$cueIndex++){
        $indexes=New-Object System.Collections.Generic.List[int]
        $timings=New-Object System.Collections.Generic.List[object]
        $exact=0;$position=0
        for($word=$Layout.CueStarts[$cueIndex];$word -lt $Layout.CueEnds[$cueIndex];$word++){
            $mapped=$Mapping[$word]
            if($mapped -ge 0){
                if($mapped -ge $RecognizedWords.Count){throw 'REFERENCE_MAPPING_INDEX_INVALID'}
                $heard=$RecognizedWords[$mapped];$chapter=[int]$heard.Chapter
                $offset=if($chapter -ge 0 -and $chapter -lt $VoiceClips.Count){[double]$VoiceClips[$chapter].start}else{0.0}
                $same=$Layout.Words[$word] -eq $heard.Text
                if($same){$exact++}
                $indexes.Add($mapped)
                $timing=[pscustomobject]@{TargetWordIndex=$position;Text=[string]$Layout.Words[$word];Start=$offset+[double]$heard.Start;End=$offset+[double]$heard.End;Chapter=$chapter;Exact=([string]$Layout.Words[$word] -eq [string]$heard.Text)}
                foreach($name in @('SubtitleTimingQuality','SubtitleTimingOrigin','NumericSurfaceText')){if($heard.PSObject.Properties[$name]){$timing | Add-Member -NotePropertyName $name -NotePropertyValue $heard.$name}}
                $timings.Add($timing)
            }
            $position++
        }
        $index=if($PreserveReferenceIndices -and $Cues[$cueIndex].PSObject.Properties['Index']){[int]$Cues[$cueIndex].Index}else{$cueIndex+1}
        $originalStart=if($Cues[$cueIndex].PSObject.Properties['Start']){[double]$Cues[$cueIndex].Start}else{0.0}
        $originalEnd=if($Cues[$cueIndex].PSObject.Properties['End']){[double]$Cues[$cueIndex].End}else{0.0}
        if($indexes.Count -eq 0){
            $output.Add([pscustomobject]@{Index=$index;OriginalStart=$originalStart;OriginalEnd=$originalEnd;Start=$null;End=$null;Text=$Cues[$cueIndex].Text;Chapter=$FixedChapter;Confidence=0.0;WordTimings=@()})
            continue
        }
        $first=$RecognizedWords[($indexes | Measure-Object -Minimum).Minimum]
        $last=$RecognizedWords[($indexes | Measure-Object -Maximum).Maximum]
        $groups=$indexes | ForEach-Object {$RecognizedWords[$_].Chapter} | Group-Object | Sort-Object Count -Descending
        $chapter=if($FixedChapter -ge 0){$FixedChapter}else{[int]$groups[0].Name}
        $offset=if($chapter -ge 0 -and $chapter -lt $VoiceClips.Count){[double]$VoiceClips[$chapter].start}else{0.0}
        $output.Add([pscustomobject]@{Index=$index;OriginalStart=$originalStart;OriginalEnd=$originalEnd;Start=$offset+[double]$first.Start;End=$offset+[double]$last.End;Text=$Cues[$cueIndex].Text;Chapter=$chapter;Confidence=[Math]::Round($exact/[double]$indexes.Count,3);WordTimings=$timings.ToArray()})
    }
    return $output.ToArray()
}

function Align-CuesToRecognizedWords {
    param([Parameter(Mandatory)][object[]]$Cues,[Parameter(Mandatory)][object[]]$RecognizedWords,[Parameter(Mandatory)][object[]]$VoiceClips)
    $layout=New-PvsReferenceWordLayout $Cues
    $mapping=@(Get-SequentialWordMapping -TargetWords $layout.Words -RecognizedWords $RecognizedWords)
    return Convert-PvsReferenceMappingToCues -Cues $Cues -Layout $layout -Mapping $mapping -RecognizedWords $RecognizedWords -VoiceClips $VoiceClips
}


function ConvertTo-NormalizedWords {
    param([AllowEmptyString()][string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return @() }
    if($script:PvsNormalizedWordCache.ContainsKey($Text)){return $script:PvsNormalizedWordCache[$Text]}
    $lower = $Text.ToLowerInvariant().Normalize([Text.NormalizationForm]::FormC)
    $matches = [regex]::Matches($lower, '[\p{L}\p{N}]+')
    $words = New-Object System.Collections.Generic.List[string]
    foreach ($match in $matches) { $words.Add($match.Value) }
    $result=$words.ToArray()
    if($Text.Length -le 4096){
        if($script:PvsNormalizedWordCache.Count -ge 2048){$script:PvsNormalizedWordCache.Clear()}
        $script:PvsNormalizedWordCache[$Text]=$result
    }
    # Normal pipeline enumeration returns immutable strings, not the cached
    # array container; callers may safely edit their own collected word list.
    return $result
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

function Test-PvsReferenceCueTiming {
    param($Cue,[double]$Start,[double]$End,[int]$Chapter)
    # Lexical confidence cannot establish that a timestamp is usable. Keep
    # this check independent of the workflow's text acceptance policy.
    if($null -eq $Cue.Start -or $null -eq $Cue.End -or [int]$Cue.Chapter -ne $Chapter -or @($Cue.WordTimings).Count -eq 0){return $false}
    foreach($value in @($Start,$End,[double]$Cue.Start,[double]$Cue.End)){
        if([double]::IsNaN($value) -or [double]::IsInfinity($value)){return $false}
    }
    if($Cue.Start -lt $Start-0.000001 -or $Cue.End -gt $End+0.000001 -or $Cue.End -le $Cue.Start){return $false}
    $previousEnd=[double]$Cue.Start
    foreach($timing in $Cue.WordTimings){
        if($null -eq $timing.Start -or $null -eq $timing.End){return $false}
        $wordStart=[double]$timing.Start;$wordEnd=[double]$timing.End
        if([double]::IsNaN($wordStart) -or [double]::IsNaN($wordEnd) -or [double]::IsInfinity($wordStart) -or [double]::IsInfinity($wordEnd) -or $wordStart -lt $previousEnd-0.000001 -or $wordEnd -gt [double]$Cue.End+0.000001 -or $wordEnd -le $wordStart -or [int]$timing.Chapter -ne $Chapter){return $false}
        $previousEnd=$wordEnd
    }
    return $true
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
            if (-not (Test-PvsReferenceCueTiming $cue $start $end 0) -or $timings.Count -ne $expected -or [double]$cue.Confidence -lt 0.7) { $valid=$false; break }
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

function Repair-PvsUnalignedCueIntervals {
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

# Whole-cue edit detection is deliberately stricter than ordinary ASR alignment.
# A missing word match is not evidence that the editor deleted its picture.
function Find-PvsEditedReferenceMatches {
    param([object[]]$Cues,[object[]]$Words,[object[]]$Sources,[bool]$CharacterMode=$false,[int]$MinimumAnchorWords=0)
    $layout=New-PvsReferenceWordLayout $Cues $CharacterMode
    $duplicates=@{};$positions=@{}
    for($i=0;$i -lt $Cues.Count;$i++){
        $key=(@(Get-PvsReferenceLexicalWords $Cues[$i].Text $CharacterMode) -join ' ')
        if(-not $duplicates.ContainsKey($key)){$duplicates[$key]=0};$duplicates[$key]++
    }
    for($i=0;$i -lt $Words.Count;$i++){
        $key=[string]$Words[$i].Text
        if(-not $positions.ContainsKey($key)){$positions[$key]=New-Object System.Collections.Generic.List[int]}
        $positions[$key].Add($i)
    }
    $duplicateCues=@{}
    for($i=0;$i -lt $Cues.Count;$i++){if($duplicates[(@(Get-PvsReferenceLexicalWords $Cues[$i].Text $CharacterMode) -join ' ')] -gt 1){$duplicateCues[$i]=$true}}
    $mapping=New-Object 'int[]' $layout.Words.Count
    for($i=0;$i -lt $mapping.Length;$i++){$mapping[$i]=-1}
    $matches=New-Object System.Collections.Generic.List[object];$last=-1;$ordered=$true
    for($cue=0;$cue -lt $Cues.Count;$cue++){
        $tokens=@(Get-PvsReferenceLexicalWords $Cues[$cue].Text $CharacterMode)
        $key=$tokens -join ' '
        if(-not $tokens.Count -or $tokens.Count -lt $MinimumAnchorWords -or $duplicates[$key] -gt 1 -or -not $positions.ContainsKey($tokens[0])){continue}
        $hits=New-Object System.Collections.Generic.List[int]
        foreach($start in $positions[$tokens[0]]){
            if($start+$tokens.Count -gt $Words.Count){continue}
            $chapter=[int]$Words[$start].Chapter
            if($chapter -lt 0 -or $chapter -ge $Sources.Count){continue}
            $valid=$true;$edge=0.0
            for($word=0;$word -lt $tokens.Count;$word++){
                $w=$Words[$start+$word];$a=[double]$w.Start;$b=[double]$w.End
                if($w.Text -cne $tokens[$word] -or [int]$w.Chapter -ne $chapter -or [double]::IsNaN($a) -or [double]::IsNaN($b) -or [double]::IsInfinity($a) -or [double]::IsInfinity($b) -or $a -lt $edge-0.000001 -or $b -le $a -or $b -gt [double]$Sources[$chapter].end-[double]$Sources[$chapter].start+0.000001){$valid=$false;break}
                $edge=$b
            }
            if($valid){$hits.Add($start);if($hits.Count -gt 1){break}}
        }
        if($hits.Count -ne 1){continue}
        $start=$hits[0]
        if($start -le $last){$ordered=$false;continue}
        for($word=0;$word -lt $tokens.Count;$word++){$mapping[$layout.CueStarts[$cue]+$word]=$start+$word}
        $last=$start+$tokens.Count-1
        $matches.Add([pscustomobject]@{Cue=$cue;FirstWord=$start;LastWord=$last;Chapter=[int]$Words[$start].Chapter})
    }
    $aligned=@(Convert-PvsReferenceMappingToCues -Cues $Cues -Layout $layout -Mapping $mapping -RecognizedWords $Words -VoiceClips $Sources -PreserveReferenceIndices)
    return [pscustomobject]@{Matches=$matches.ToArray();Aligned=$aligned;Ordered=$ordered;Mapping=$mapping;DuplicateCues=$duplicateCues}
}

function Resolve-PvsEditedReference {
    param([object[]]$Cues,[object[]]$Words,[object[]]$Sources,[scriptblock]$RecognizeWindow,[bool]$CharacterMode=$false,[int]$MinimumAnchorWords=0)
    $heard=@($Words | Sort-Object Chapter,Start)
    $initial=Find-PvsEditedReferenceMatches $Cues $heard $Sources $CharacterMode $MinimumAnchorWords
    # Without a reliable island there is no evidence of an edited script.
    if(-not $initial.Ordered -or -not $initial.Matches.Count -or $initial.Matches.Count -eq $Cues.Count){return $null}
    $anchorWords=0
    foreach($match in $initial.Matches){if($match.LastWord-$match.FirstWord+1 -ge 4){$anchorWords+=$match.LastWord-$match.FirstWord+1}}
    if($anchorWords -lt 8){return $null}
    $known=@{};foreach($match in $initial.Matches){$known[$match.Cue]=$match}
    $reports=New-Object System.Collections.Generic.List[object]
    $omitted=New-Object System.Collections.Generic.List[int]
    $unresolved=New-Object System.Collections.Generic.List[int]
    $recovered=New-Object System.Collections.Generic.List[int]
    for($i=0;$i -lt $Cues.Count;$i++){
        if($known.ContainsKey($i)){continue}
        $first=$i
        while($i+1 -lt $Cues.Count -and -not $known.ContainsKey($i+1)){$i++}
        $last=$i
        $left=if($first -gt 0){$initial.Aligned[$first-1]}else{$null}
        $right=if($last+1 -lt $Cues.Count){$initial.Aligned[$last+1]}else{$null}
        $chapter=if($null -ne $left){[int]$left.Chapter}else{[int]$right.Chapter}
        $safe=$chapter -ge 0 -and $chapter -lt $Sources.Count -and $null -ne $RecognizeWindow
        if($left -and $right -and $left.Chapter -ne $right.Chapter){$safe=$false}
        # A one/two-word coincidence must not authorize deletion of picture.
        foreach($anchor in @($left,$right)){
            if($null -ne $anchor -and @(Get-PvsReferenceLexicalWords $anchor.Text $CharacterMode).Count -lt 4){$safe=$false}
        }
        $source=if($safe){$Sources[$chapter]}else{$null}
        $start=if($safe){if($left){[double]$left.Start}else{[double]$source.start}}else{0.0}
        $end=if($safe){if($right){[double]$right.End}else{[double]$source.end}}else{0.0}
        if($end-$start -lt 0.2 -or $end-$start -gt 30){$safe=$false}
        $indices=@($Cues[$first..$last] | ForEach-Object {[int]$_.Index})
        $status='unresolved';$reason='anchor-or-window-unverified'
        if($safe){
            # No SRT prompt. Re-read the actual join, including both retained
            # anchors; an empty retry never proves that content was removed.
            $retry=@(& $RecognizeWindow $source $start $end)
            $valid=$true;$edge=0.0
            foreach($w in $retry){
                $a=[double]$w.Start;$b=[double]$w.End
                if([string]::IsNullOrWhiteSpace([string]$w.Text) -or [double]::IsNaN($a) -or [double]::IsNaN($b) -or [double]::IsInfinity($a) -or [double]::IsInfinity($b) -or $a -lt $edge-0.000001 -or $b -le $a -or $b -gt $end-$start+0.000001){$valid=$false;break};$edge=$b
            }
            if(-not $valid){throw 'EDITED_REFERENCE_RETRY_TIMING_INVALID'}
            $expected=@(foreach($anchor in @($left,$right)){if($anchor){Get-PvsReferenceLexicalWords $anchor.Text $CharacterMode}})
            $complete=@(foreach($cue in @($(if($left){$Cues[$first-1]})) + @($Cues[$first..$last]) + @($(if($right){$Cues[$last+1]}))){if($cue){Get-PvsReferenceLexicalWords $cue.Text $CharacterMode}})
            $text=@($retry | ForEach-Object {[string]$_.Text}) -join ' '
            $ambiguous=$false
            for($missing=$first;$missing -le $last;$missing++){if($initial.DuplicateCues.ContainsKey($missing)){$ambiguous=$true}}
            if($retry.Count -and $text -ceq ($complete -join ' ')){
                $status='recovered';$reason='initial-ASR-miss'
                foreach($index in $indices){$recovered.Add($index)}
            }elseif($retry.Count -and $text -ceq ($expected -join ' ') -and -not $ambiguous){
                $status='omitted';$reason='join-rerecognized-with-retained-anchors'
                foreach($index in $indices){$omitted.Add($index)}
            }else{$reason=if($ambiguous){'repeated-reference-ambiguous'}else{'retry-content-differs'}}
            if($status -eq 'recovered'){
                # Replace this window only; preserve other chapters and islands.
                $replacement=@(foreach($w in $retry){
                    $copy=$w.PSObject.Copy();$shift=$start-[double]$source.start
                    $copy.Start=$shift+[double]$w.Start;$copy.End=$shift+[double]$w.End;$copy.Chapter=$chapter
                    foreach($name in @('DtwFirst','DtwLast','DtwBoundaryStart')){if($copy.PSObject.Properties[$name] -and $null -ne $copy.$name){$copy.$name=$shift+[double]$copy.$name}}
                    $copy
                })
                $heard=@(@($heard | Where-Object {[int]$_.Chapter -ne $chapter -or [double]$source.start+[double]$_.End -le $start+0.000001 -or [double]$source.start+[double]$_.Start -ge $end-0.000001})+$replacement | Sort-Object Chapter,Start)
            }
        }
        if($status -eq 'unresolved'){foreach($index in $indices){$unresolved.Add($index)}}
        $reports.Add([pscustomobject]@{cueIndices=$indices;status=$status;reason=$reason;chapter=$chapter;start=$start;end=$end;audioStart=$(if($left){[double]$left.End}else{if($source){[double]$source.start}else{0.0}});audioEnd=$(if($right){[double]$right.Start}else{if($source){[double]$source.end}else{0.0}});sourceStart=[double]$Cues[$first].Start;sourceEnd=[double]$Cues[$last].End})
    }
    $final=Find-PvsEditedReferenceMatches $Cues $heard $Sources $CharacterMode $MinimumAnchorWords
    $retained=@($final.Aligned | Where-Object {$null -ne $_.Start})
    $covered=@($final.Mapping | Where-Object {$_ -ge 0} | Select-Object -Unique).Count
    $resolved=$final.Ordered -and $unresolved.Count -eq 0 -and $covered -eq $heard.Count -and $retained.Count+$omitted.Count -eq $Cues.Count
    return [pscustomobject]@{Cues=$retained;Words=$heard;OmittedCueIndices=$omitted.ToArray();UnresolvedCueIndices=$unresolved.ToArray();RecoveredCueIndices=$recovered.ToArray();Ranges=$reports.ToArray();Resolved=$resolved;AudioFullyCovered=($covered -eq $heard.Count);ReferenceCueCount=$Cues.Count}
}

function New-PvsEditedSourceMap {
    param($Edited,[object[]]$Cues,$MainVideo,[double]$FrameRate)
    if(-not $Edited.Resolved -or -not $Edited.OmittedCueIndices.Count){throw 'EDITED_SOURCE_UNRESOLVED'}
    if([double]::IsNaN($FrameRate) -or [double]::IsInfinity($FrameRate) -or $FrameRate -le 0){throw 'EDITED_SOURCE_FPS_INVALID'}
    $a=[int][Math]::Round([double]$MainVideo.start*$FrameRate);$b=[int][Math]::Round([double]$MainVideo.end*$FrameRate)
    $edge=[double]$MainVideo.start
    foreach($cue in $Cues){
        if($cue.Start -lt $edge-0.000001 -or $cue.End -le $cue.Start -or $cue.End -gt [double]$MainVideo.end+0.000001){throw 'EDITED_SOURCE_SRT_RANGE_INVALID'}
        $edge=[double]$cue.End
    }
    $removed=@(foreach($range in $Edited.Ranges){
        if($range.status -ne 'omitted'){continue}
        if($range.reason -cne 'join-rerecognized-with-retained-anchors'){throw 'EDITED_SOURCE_PROOF_INVALID'}
        $first=[int]$range.cueIndices[0];$last=[int]$range.cueIndices[-1]
        if($first -lt 1 -or $last -gt $Cues.Count -or $range.sourceStart -ne $Cues[$first-1].Start -or $range.sourceEnd -ne $Cues[$last-1].End){throw 'EDITED_SOURCE_PROOF_MISMATCH'}
        [pscustomobject]@{SourceStartFrame=[int][Math]::Round($range.sourceStart*$FrameRate);SourceEndFrame=[int][Math]::Round($range.sourceEnd*$FrameRate);CueIndices=@($range.cueIndices);Reason=$range.reason}
    })
    $kept=New-Object System.Collections.Generic.List[object];$physical=$a;$virtual=$a
    foreach($range in $removed){
        $start=[int]$range.SourceStartFrame;$end=[int]$range.SourceEndFrame
        if($start -lt $physical -or $end -le $start -or $end -gt $b){throw 'EDITED_SOURCE_OMISSION_RANGE_INVALID'}
        if($start -gt $physical){$kept.Add([pscustomobject]@{SourceStartFrame=$physical;SourceEndFrame=$start;PlanStartFrame=$virtual;PlanEndFrame=($virtual+$start-$physical)});$virtual+=$start-$physical}
        $physical=$end
    }
    if($physical -lt $b){$kept.Add([pscustomobject]@{SourceStartFrame=$physical;SourceEndFrame=$b;PlanStartFrame=$virtual;PlanEndFrame=($virtual+$b-$physical)});$virtual+=$b-$physical}
    if(-not $kept.Count){throw 'EDITED_SOURCE_NO_PICTURE_REMAINS'}
    return [pscustomobject]@{revision='srt-omissions-v1';physicalStartFrame=$a;physicalEndFrame=$b;planStartFrame=$a;planEndFrame=$virtual;kept=$kept.ToArray();omissions=$removed}
}

function ConvertTo-PvsEditedSourceTime {
    param([double]$Seconds,$Map,[double]$FrameRate)
    $frame=[int][Math]::Round($Seconds*$FrameRate);$removed=0
    foreach($range in $Map.omissions){
        if($frame -gt $range.SourceStartFrame -and $frame -lt $range.SourceEndFrame){throw 'EDITED_SOURCE_RETAINED_CUE_INSIDE_OMISSION'}
        if($frame -ge $range.SourceEndFrame){$removed+=$range.SourceEndFrame-$range.SourceStartFrame}
    }
    return ($frame-$removed)/$FrameRate
}
