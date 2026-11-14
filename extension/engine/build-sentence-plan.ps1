param([Parameter(Mandatory)][string]$JobPath)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. "$PSScriptRoot\lib\Srt.ps1"
. "$PSScriptRoot\lib\ReferenceAlignment.ps1"
. "$PSScriptRoot\lib\CaptionTiming.ps1"
. "$PSScriptRoot\lib\AutoEditManualReview.ps1"
. "$PSScriptRoot\lib\Paths.ps1"
. "$PSScriptRoot\lib\Native.ps1"

function Round6([double]$Value) { [Math]::Round($Value, 6) }
$minNoDialogueGapSeconds = 0.5
$silenceNoiseDb = -35.0
$minSilenceDurationSeconds = 0.12
$boundarySearchSeconds = 0.12
$boundarySafetyMarginSeconds = 0.04
$lowConfidenceThreshold = 0.55
$sentenceEndCharacters = '.?!;'
$maxCaptionCharacters = 42
function Get-VoiceSilences {
    param([string]$MediaPath,[double]$TimelineStart,[double]$SpeedPercent,[string]$FfmpegPath,[double]$NoiseDb,[double]$MinDuration)
    $items = New-Object System.Collections.Generic.List[object]
    if (-not (Test-Path -LiteralPath $MediaPath -PathType Leaf)) {
        throw "MEDIA_PATH_NOT_FOUND:Voice media for silence detection path does not exist: $MediaPath"
    }
    $silenceFilter = "silencedetect=noise=$($NoiseDb)dB:d=$MinDuration"
    $run=Invoke-NativeCapture -FilePath $FfmpegPath -Arguments @('-hide_banner','-i',$MediaPath,'-af',$silenceFilter,'-f','null','NUL')
    if($run.ExitCode -ne 0){throw "VOICE_SILENCE_ANALYSIS_FAILED:$($run.Output)"}
    $output=$run.Output -split '\r?\n'
    $pending = $null
    $scale = 100.0 / [Math]::Max(1.0,$SpeedPercent)
    foreach ($line in $output) {
        $text = [string]$line
        if ($text -match 'silence_start:\s*([0-9.]+)') { $pending = [double]$Matches[1]; continue }
        if ($null -ne $pending -and $text -match 'silence_end:\s*([0-9.]+)') {
            $rawEnd = [double]$Matches[1]
            $items.Add([pscustomobject]@{
                Start = $TimelineStart + ($pending * $scale)
                End = $TimelineStart + ($rawEnd * $scale)
                Center = $TimelineStart + ((($pending + $rawEnd) / 2.0) * $scale)
                Duration = ($rawEnd - $pending) * $scale
            })
            $pending = $null
        }
    }
    return $items.ToArray()
}
function Find-SafeVoiceBoundary {
    param(
        [double]$ApproximateSeconds,
        [object[]]$Silences,
        [double]$MinimumDurationSeconds,
        [double]$MaximumDistanceSeconds,
        [double]$SafetyMarginSeconds,
        [double]$FrameRate
    )
    $candidates = New-Object System.Collections.Generic.List[object]
    foreach ($silence in $Silences) {
        $start = [double]$silence.Start
        $end = [double]$silence.End
        $duration = [double]$silence.Duration
        if ($duration -lt $MinimumDurationSeconds) { continue }
        $distance = if ($ApproximateSeconds -lt $start) { $start - $ApproximateSeconds } elseif ($ApproximateSeconds -gt $end) { $ApproximateSeconds - $end } else { 0.0 }
        if ($distance -gt $MaximumDistanceSeconds) { continue }

        # FFmpeg reports the threshold crossings, not guaranteed speech-free
        # sample boundaries. Keep a guard on both sides and require a real
        # Premiere frame inside the guarded interval. Otherwise merging the
        # adjacent sentences is safer than cutting a phoneme.
        $safeStart = $start + $SafetyMarginSeconds
        $safeEnd = $end - $SafetyMarginSeconds
        $firstSafeFrame = [int][Math]::Ceiling(($safeStart * $FrameRate) - 0.0000001)
        $lastSafeFrame = [int][Math]::Floor(($safeEnd * $FrameRate) + 0.0000001)
        if ($lastSafeFrame -lt $firstSafeFrame) { continue }

        $centerFrame = [int][Math]::Round((($start + $end) / 2.0) * $FrameRate)
        $cutFrame = [Math]::Max($firstSafeFrame, [Math]::Min($lastSafeFrame, $centerFrame))
        $candidates.Add([pscustomobject]@{
            Silence = $silence
            Distance = $distance
            Duration = $duration
            CutFrame = $cutFrame
            CutSeconds = [double]$cutFrame / $FrameRate
        })
    }
    return $candidates | Sort-Object Distance,@{Expression='Duration';Descending=$true} | Select-Object -First 1
}
$job = Get-Content -LiteralPath $JobPath -Raw -Encoding UTF8 | ConvertFrom-Json
$algorithm = if ($job.PSObject.Properties['algorithm']) { $job.algorithm } else { $null }
$useAudioCache=if($algorithm -and $algorithm.PSObject.Properties['useWhisperCache']){[bool]$algorithm.useWhisperCache}else{$true}
Initialize-PvsAudioCache -Enabled $useAudioCache -RuntimeIdentity ((Get-PvsAudioFileDigest "$PSScriptRoot\runtime-lock.json")+'|'+(Get-PvsAudioFileDigest "$PSScriptRoot\cuda-lock.json"))
function Get-AlgorithmSetting([string]$Name, $Default) {
    if ($null -ne $algorithm -and $algorithm.PSObject.Properties[$Name]) { return $algorithm.$Name }
    return $Default
}
$minNoDialogueGapSeconds = [double](Get-AlgorithmSetting 'minNoDialogueGapSeconds' $minNoDialogueGapSeconds)
$silenceNoiseDb = [double](Get-AlgorithmSetting 'silenceNoiseDb' $silenceNoiseDb)
$minSilenceDurationSeconds = [double](Get-AlgorithmSetting 'minSilenceDurationSeconds' $minSilenceDurationSeconds)
$boundarySearchSeconds = [double](Get-AlgorithmSetting 'boundarySearchSeconds' $boundarySearchSeconds)
$lowConfidenceThreshold = [double](Get-AlgorithmSetting 'lowConfidenceThreshold' $lowConfidenceThreshold)
$sentenceEndCharacters = [string](Get-AlgorithmSetting 'sentenceEndCharacters' $sentenceEndCharacters)
$maxCaptionCharacters = [int](Get-AlgorithmSetting 'maxCaptionCharacters' $maxCaptionCharacters)
$voiceMappingToleranceFrames = [int](Get-AlgorithmSetting 'voiceMappingToleranceFrames' 2)
$validationToleranceFrames = [int](Get-AlgorithmSetting 'validationToleranceFrames' 1)
$maxCoverageGapFrames = [int](Get-AlgorithmSetting 'maxCoverageGapFrames' 0)
$speedWarningMinPercent = if ($job.PSObject.Properties['speedWarningMinPercent']) { [double]$job.speedWarningMinPercent } else { [double]$job.minSpeedPercent }
$speedWarningMaxPercent = if ($job.PSObject.Properties['speedWarningMaxPercent']) { [double]$job.speedWarningMaxPercent } else { [double]$job.maxSpeedPercent }
function Assert-Range([string]$Name,[double]$Value,[double]$Minimum,[double]$Maximum) {
    if ([double]::IsNaN($Value) -or [double]::IsInfinity($Value) -or $Value -lt $Minimum -or $Value -gt $Maximum) {
        throw "INVALID_SETTING:$Name must be between $Minimum and $Maximum."
    }
}
Assert-Range 'speedWarningMinPercent' $speedWarningMinPercent 10 100
Assert-Range 'speedWarningMaxPercent' $speedWarningMaxPercent 100 400
if ($speedWarningMinPercent -gt $speedWarningMaxPercent) { throw 'INVALID_SETTING:speedWarningMinPercent exceeds speedWarningMaxPercent.' }
Assert-Range 'minNoDialogueGapSeconds' $minNoDialogueGapSeconds 0.2 10
Assert-Range 'silenceNoiseDb' $silenceNoiseDb -80 -5
Assert-Range 'minSilenceDurationSeconds' $minSilenceDurationSeconds 0.01 1
Assert-Range 'boundarySearchSeconds' $boundarySearchSeconds 0.05 2
Assert-Range 'lowConfidenceThreshold' $lowConfidenceThreshold 0 1
Assert-Range 'voiceMappingToleranceFrames' $voiceMappingToleranceFrames 0 10
Assert-Range 'validationToleranceFrames' $validationToleranceFrames 0 5
Assert-Range 'maxCoverageGapFrames' $maxCoverageGapFrames 0 2
Assert-Range 'maxCaptionCharacters' $maxCaptionCharacters 20 80
if ([string]::IsNullOrWhiteSpace($sentenceEndCharacters) -or $sentenceEndCharacters.Length -gt 16) { throw 'INVALID_SETTING:sentenceEndCharacters must contain 1-16 characters.' }
$fps = if ($job.sequence.PSObject.Properties['frameRate']) { [double]$job.sequence.frameRate } else { 30.0 }
Assert-Range 'frameRate' $fps 1 240
function To-Frame([double]$Seconds) { [int][Math]::Round($Seconds * $fps) }
function From-Frame([int]$Frame) { [double]$Frame / $fps }
$alignmentPath = Join-Path $job.outputFolder 'alignment-result.json'
if (-not (Test-Path -LiteralPath $alignmentPath)) { throw 'ALIGNMENT_NOT_READY' }
$alignment = Get-Content -LiteralPath $alignmentPath -Raw -Encoding UTF8 | ConvertFrom-Json
$runtimeConfigPath = Join-Path $PSScriptRoot 'runtime\engine.json'
$engine = Get-Content -LiteralPath $runtimeConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
$runtimeRoot = Split-Path $runtimeConfigPath -Parent
$ffmpeg = if ([IO.Path]::IsPathRooted([string]$engine.ffmpeg)) { [string]$engine.ffmpeg } else { Join-Path $runtimeRoot ([string]$engine.ffmpeg) }
$cues = @([object[]]$alignment.cues | Sort-Object Index)
$editedSourceMap=$null
if($alignment.PSObject.Properties['editedSourceMap']){
    $editedSourceMap=$alignment.editedSourceMap
    # Work on a contiguous coordinate system of retained picture frames. The
    # native executor expands it to physical source spans before any mutation.
    $cues=@(foreach($cue in $cues){
        $copy=$cue.PSObject.Copy()
        $copy.OriginalStart=ConvertTo-PvsEditedSourceTime $cue.OriginalStart $editedSourceMap $fps
        $copy.OriginalEnd=ConvertTo-PvsEditedSourceTime $cue.OriginalEnd $editedSourceMap $fps
        $copy
    })
}
$voiceClips = @([object[]]$job.sequence.voices | Select-Object -First ([int]$alignment.voiceChapterCount))
$recoveredUnalignedCueCount=Repair-PvsUnalignedCueIntervals -Cues $cues -VoiceClips $voiceClips -FrameRate $fps
$silences = New-Object System.Collections.Generic.List[object]
foreach ($voice in $voiceClips) {
    $path = Resolve-PvsExistingPath -Path ([string]$voice.path) -Purpose 'Voice media for silence detection'
    $speed = if ($voice.PSObject.Properties['speedPercent']) { [double]$voice.speedPercent } else { 100.0 }
    foreach ($silence in (Get-VoiceSilences -MediaPath $path -TimelineStart ([double]$voice.start) -SpeedPercent $speed -FfmpegPath $ffmpeg -NoiseDb $silenceNoiseDb -MinDuration $minSilenceDurationSeconds)) { $silences.Add($silence) }
}
$voiceSilenceArray = $silences.ToArray()

# Protect source gaps before punctuation and safety grouping can hide them.
# SRT requests preservation; only separate measured voice evidence permits a cut.
$sourceGapCuts=@{}
for($i=0;$i+1 -lt $cues.Count;$i++){
    $left=$cues[$i];$right=$cues[$i+1]
    if($right.OriginalStart-$left.OriginalEnd -lt $minNoDialogueGapSeconds -or $left.Chapter -ne $right.Chapter){continue}
    if(@(@($left,$right) | Where-Object {$_.PSObject.Properties['ManualEditBlock'] -and $_.ManualEditBlock}).Count){continue}
    $review=@(@($left,$right) | Where-Object {$_.PSObject.Properties['EditBoundaryReviewRequired'] -and $_.EditBoundaryReviewRequired}).Count -gt 0
    $candidate=$null
    if(-not $review -and $left.Confidence -ge $lowConfidenceThreshold -and $right.Confidence -ge $lowConfidenceThreshold){
        $candidate=Find-SafeVoiceBoundary (($left.End+$right.Start)/2.0) $voiceSilenceArray $minSilenceDurationSeconds $boundarySearchSeconds $boundarySafetyMarginSeconds $fps
    }elseif($review -and $left.Confidence -ge $lowConfidenceThreshold -and $right.Confidence -ge $lowConfidenceThreshold -and $left.PSObject.Properties['SourceGapEndEvidence'] -and $right.PSObject.Properties['SourceGapStartEvidence']){
        $a=$left.SourceGapEndEvidence;$b=$right.SourceGapStartEvidence;$voice=$voiceClips[[int]$left.Chapter]
        $valid=$true
        foreach($p in @(@{Proof=$a;Cue=$left;Side='End'},@{Proof=$b;Cue=$right;Side='Start'})){
            $e=$p.Proof
            if($e.revision -ne 'raw-dtw-context-edge-v1' -or $e.cueIndex -ne $p.Cue.Index -or $e.chapter -ne $left.Chapter -or $e.side -ne $p.Side -or @($e.rawContext).Count -lt 4 -or $e.start -lt $voice.start -or $e.end -gt $voice.end -or $e.end -le $e.start){$valid=$false}
            foreach($value in @([double]$e.start,[double]$e.end)){if([double]::IsNaN($value) -or [double]::IsInfinity($value)){$valid=$false}}
        }
        if($valid -and $b.start -gt $a.end){
            $quiet=@($voiceSilenceArray | Where-Object {$_.Start -ge $a.end-0.08 -and $_.End -le $b.start+0.08 -and $_.Duration -ge $minSilenceDurationSeconds})
            if($quiet.Count -eq 1){
                $candidate=Find-SafeVoiceBoundary (($a.end+$b.start)/2.0) $quiet $minSilenceDurationSeconds $boundarySearchSeconds $boundarySafetyMarginSeconds $fps
                if($candidate -and ($candidate.CutSeconds -lt $a.end+$boundarySafetyMarginSeconds -or $candidate.CutSeconds -gt $b.start-$boundarySafetyMarginSeconds)){$candidate=$null}
            }
        }
    }
    if($candidate -and $candidate.CutFrame -gt (To-Frame $left.Start) -and $candidate.CutFrame -lt (To-Frame $right.End)){
        $sourceGapCuts[[int]$left.Index]=$candidate
    }
}

# First build punctuation-delimited Vietnamese sentences.
$sentences = New-Object System.Collections.Generic.List[object]
$sentenceStart = 0
for ($i=0; $i -lt $cues.Count; $i++) {
    $cueText = ([string]$cues[$i].Text).Trim()
    $endByPunctuation = $cueText.Length -gt 0 -and $sentenceEndCharacters.IndexOf($cueText[$cueText.Length - 1]) -ge 0
    $endByChapter = $i -eq ($cues.Count-1) -or [int]$cues[$i+1].Chapter -ne [int]$cues[$i].Chapter
    $endBySourceGap=$sourceGapCuts.ContainsKey([int]$cues[$i].Index)
    if (-not $endByPunctuation -and -not $endByChapter -and -not $endBySourceGap) { continue }
    $slice = @($cues[$sentenceStart..$i])
    $sentences.Add([pscustomobject]@{
        FirstCue = [int]$slice[0].Index
        LastCue = [int]$slice[-1].Index
        Chapter = [int]$slice[0].Chapter
        VoiceStart = [double]$slice[0].Start
        VoiceEnd = [double]$slice[-1].End
        SourceStart = [double](($slice | Measure-Object OriginalStart -Minimum).Minimum)
        SourceEnd = [double](($slice | Measure-Object OriginalEnd -Maximum).Maximum)
        Confidence = [double](($slice | Measure-Object Confidence -Minimum).Minimum)
        Text = (($slice | ForEach-Object { [string]$_.Text }) -join ' ')
        Cues = $slice
    })
    $sentenceStart = $i + 1
}

# More precise speech edges must not shave the existing chapter's voice
# coverage. Keep its outer extent (or extend it for newly verified speech),
# while internal sentence boundaries use the new acoustic timestamps.
if($alignment.PSObject.Properties['acousticEditVoiceRanges']){
    foreach($range in @($alignment.acousticEditVoiceRanges)){
        $chapter=[int]$range.chapter
        if($chapter -lt 0 -or $chapter -ge $voiceClips.Count){throw 'ACOUSTIC_VOICE_RANGE_CHAPTER_INVALID'}
        $a=[double]$range.start;$b=[double]$range.end
        if([double]::IsNaN($a) -or [double]::IsNaN($b) -or [double]::IsInfinity($a) -or [double]::IsInfinity($b) -or $a -lt $voiceClips[$chapter].start-0.000001 -or $b -gt $voiceClips[$chapter].end+0.000001 -or $b -le $a){throw 'ACOUSTIC_VOICE_RANGE_INVALID'}
        $items=@($sentences | Where-Object Chapter -eq $chapter)
        if($items.Count){$items[0].VoiceStart=[Math]::Min($items[0].VoiceStart,$a);$items[-1].VoiceEnd=[Math]::Max($items[-1].VoiceEnd,$b)}
    }
}

# A voice cut is allowed only at a detected silence. Unsafe adjacent sentences
# are merged into one complete multi-sentence block.
if($alignment.PSObject.Properties['autoEditManualReviewBlocks'] -and @($alignment.autoEditManualReviewBlocks).Count){
    # Recognition-review jobs preserve complete physical chapter clips,
    # including uncertain/quiet outer edges. This grants no internal cut.
    for($chapter=0;$chapter -lt $voiceClips.Count;$chapter++){
        $items=@($sentences | Where-Object Chapter -eq $chapter)
        if(-not $items.Count){throw 'MANUAL_REVIEW_CHAPTER_NOT_REPRESENTED'}
        $items[0].VoiceStart=[double]$voiceClips[$chapter].start
        $items[-1].VoiceEnd=[double]$voiceClips[$chapter].end
    }
}
$groups = New-Object System.Collections.Generic.List[object]
$current = $null
$unsafeBoundaryMergeCount = 0
$lowConfidenceBoundaryMergeCount = 0
for ($i=0; $i -lt $sentences.Count; $i++) {
    $sentence = $sentences[$i]
    if ($null -eq $current) {
        $current = [pscustomobject]@{
            FirstCue=$sentence.FirstCue; LastCue=$sentence.LastCue; Chapter=$sentence.Chapter
            VoiceStart=$sentence.VoiceStart; VoiceEnd=$sentence.VoiceEnd
            SourceStart=$sentence.SourceStart; SourceEnd=$sentence.SourceEnd
            Confidence=$sentence.Confidence; Text=$sentence.Text; Cues=@($sentence.Cues)
            SafeEnd=$false; BoundarySilenceDuration=0.0
        }
    } else {
        $current.LastCue = $sentence.LastCue
        $current.VoiceEnd = $sentence.VoiceEnd
        $current.SourceEnd = [Math]::Max([double]$current.SourceEnd,[double]$sentence.SourceEnd)
        $current.Confidence = [Math]::Min([double]$current.Confidence,[double]$sentence.Confidence)
        $current.Text += ' ' + $sentence.Text
        $current.Cues = @($current.Cues) + @($sentence.Cues)
    }
    $isLast = $i -eq ($sentences.Count-1)
    if ($isLast) { $current.SafeEnd=$true; $groups.Add($current); $current=$null; continue }
    $next = $sentences[$i+1]
    if ([int]$sentence.Chapter -ne [int]$next.Chapter) {
        $boundary = [double]$voiceClips[[int]$sentence.Chapter].end
        $current.VoiceEnd = $boundary; $current.SafeEnd=$true; $groups.Add($current); $current=$null
        $next.VoiceStart = [double]$voiceClips[[int]$next.Chapter].start
        continue
    }
    $approx = (([double]$sentence.VoiceEnd) + ([double]$next.VoiceStart)) / 2.0
    # A weak word match makes Whisper's edge timestamp unsafe even when a
    # quiet spot happens to be nearby. Merge only around that boundary; later
    # high-confidence sentences can still be split normally.
    $boundaryConfidenceSafe = [double]$sentence.Confidence -ge $lowConfidenceThreshold -and [double]$next.Confidence -ge $lowConfidenceThreshold
    if(@(@($sentence.Cues)+@($next.Cues) | Where-Object {$_.PSObject.Properties['EditBoundaryReviewRequired'] -and $_.EditBoundaryReviewRequired}).Count){$boundaryConfidenceSafe=$false}
    $candidate = if ($sourceGapCuts.ContainsKey([int]$sentence.LastCue)) {
        $sourceGapCuts[[int]$sentence.LastCue]
    } elseif ($boundaryConfidenceSafe) {
        Find-SafeVoiceBoundary -ApproximateSeconds $approx -Silences $voiceSilenceArray -MinimumDurationSeconds $minSilenceDurationSeconds -MaximumDistanceSeconds $boundarySearchSeconds -SafetyMarginSeconds $boundarySafetyMarginSeconds -FrameRate $fps
    } else {
        $lowConfidenceBoundaryMergeCount++
        $null
    }
    if ($candidate) {
        # A short sentence can select the same quiet center as its left edge.
        # Reject on the frame grid before emitting a zero-length group: adding
        # an artificial frame later would duplicate that frame in the next slice.
        $currentStartFrame = To-Frame ([double]$current.VoiceStart)
        $nextEndFrame = To-Frame ([double]$next.VoiceEnd)
        if ([int]$candidate.CutFrame -le $currentStartFrame -or [int]$candidate.CutFrame -ge $nextEndFrame) { $candidate = $null }
    }
    if ($candidate) {
        $silence = $candidate.Silence
        $cutPoint = [double]$candidate.CutSeconds
        $current.VoiceEnd = $cutPoint
        $current.SafeEnd = $true
        $current.BoundarySilenceDuration = [double]$silence.Duration
        $groups.Add($current); $current=$null
        $next.VoiceStart = $cutPoint
    } else {
        $unsafeBoundaryMergeCount++
    }
}

$acousticPartitioned=$false;$acousticCuts=@();$cueEvidence=@();$pictureReferences=@()
if($alignment.PSObject.Properties['acousticEditBoundaryRevision'] -and $alignment.acousticEditBoundaryRevision -cin @('raw-dtw-quiet-partition-v1','dtw-cue-quiet-partition-v2')){
    # Recompute from the complete independent DTW stream and measured quiet;
    # manual caption estimates never grant picture/voice cut permission.
    $acousticCuts=@(Get-PvsAcousticReferenceCuts $alignment.acousticEditReferenceCues $alignment.acousticEditWords $voiceClips $voiceSilenceArray $fps $minSilenceDurationSeconds $boundarySafetyMarginSeconds)
    if($alignment.acousticEditBoundaryRevision -ceq 'dtw-cue-quiet-partition-v2'){
        $pictureReferences=@($alignment.acousticEditReferenceCues)
        $cueEvidence=@(Get-PvsReferenceCueEvidence $pictureReferences $alignment.acousticEditWords $cues $voiceClips)
        $acousticCuts=@(Get-PvsWholeCueQuietCuts $cueEvidence $alignment.acousticEditWords $voiceClips $voiceSilenceArray $fps $acousticCuts $minSilenceDurationSeconds $boundarySafetyMarginSeconds)
    }
    $partitions=@(New-PvsAcousticEditGroups $cues $alignment.acousticEditReferenceCues $voiceClips $acousticCuts $voiceSilenceArray $fps $minSilenceDurationSeconds $boundarySafetyMarginSeconds)
    if($partitions.Count){$groups.Clear();foreach($partition in $partitions){$groups.Add($partition)};$acousticPartitioned=$true}
}
$manualAcoustic=$acousticPartitioned -or ($alignment.PSObject.Properties['manualCaptionTimingRevision'] -and $alignment.manualCaptionTimingRevision -ceq 'raw-dtw-cell-overlay-v1')

# Make source spans continuous across short subtitle gaps. A gap reaching the
# configured threshold is meaningful in the translated SRT and is preserved as
# a no-dialogue segment; mixed music/SFX audio is intentionally not used.
for ($i=0; $i -lt $groups.Count-1; $i++) {
    $gap = [double]$groups[$i+1].SourceStart - [double]$groups[$i].SourceEnd
    if ($gap -lt $minNoDialogueGapSeconds) {
        $boundary = (([double]$groups[$i].SourceEnd) + ([double]$groups[$i+1].SourceStart)) / 2.0
        $groups[$i].SourceEnd = $boundary
        $groups[$i+1].SourceStart = $boundary
    }
}
$mainSourceStart = [double]$job.sequence.mainVideoClip.start
$mainSourceEnd = [double]$job.sequence.mainVideoClip.end
if($null -ne $editedSourceMap){$mainSourceEnd=[double]$editedSourceMap.planEndFrame/$fps}
if ([double]$groups[0].SourceStart - $mainSourceStart -lt $minNoDialogueGapSeconds) { $groups[0].SourceStart = $mainSourceStart }
if ($mainSourceEnd - [double]$groups[$groups.Count-1].SourceEnd -lt $minNoDialogueGapSeconds) { $groups[$groups.Count-1].SourceEnd = $mainSourceEnd }

# Premiere razors and clip edges are frame based. Normalize every source and
# voice boundary once, then keep all timeline arithmetic in integer frames.
# This prevents custom settings from accumulating millisecond rounding errors.
$mainSourceStartFrame = To-Frame $mainSourceStart
$mainSourceEndFrame = To-Frame $mainSourceEnd
for ($i=0; $i -lt $groups.Count; $i++) {
    $g = $groups[$i]
    $sourceStartFrame = [Math]::Max($mainSourceStartFrame, $(To-Frame ([double]$g.SourceStart)))
    $sourceEndFrame = [Math]::Min($mainSourceEndFrame, $(To-Frame ([double]$g.SourceEnd)))
    if ($sourceEndFrame -le $sourceStartFrame) { $sourceEndFrame = [Math]::Min($mainSourceEndFrame, $sourceStartFrame + 1) }
    $voiceStartFrame = To-Frame ([double]$g.VoiceStart)
    $voiceEndFrame = To-Frame ([double]$g.VoiceEnd)
    if ($voiceEndFrame -le $voiceStartFrame) { throw "PLAN_VOICE_RANGE_INVALID:cue-$($g.FirstCue)-$($g.LastCue):$voiceStartFrame-$voiceEndFrame" }
    if ($i -gt 0 -and [int]$groups[$i-1].Chapter -eq [int]$g.Chapter -and $voiceStartFrame -ne [int]$groups[$i-1].VoiceEndFrame) {
        throw "PLAN_VOICE_PARTITION_INVALID:cue-$($g.FirstCue):$($groups[$i-1].VoiceEndFrame)-$voiceStartFrame"
    }
    $g.SourceStart = From-Frame $sourceStartFrame
    $g.SourceEnd = From-Frame $sourceEndFrame
    $g.VoiceStart = From-Frame $voiceStartFrame
    $g.VoiceEnd = From-Frame $voiceEndFrame
    $g | Add-Member -NotePropertyName SourceStartFrame -NotePropertyValue $sourceStartFrame -Force
    $g | Add-Member -NotePropertyName SourceEndFrame -NotePropertyValue $sourceEndFrame -Force
    $g | Add-Member -NotePropertyName VoiceStartFrame -NotePropertyValue $voiceStartFrame -Force
    $g | Add-Member -NotePropertyName VoiceEndFrame -NotePropertyValue $voiceEndFrame -Force
}

$segments = New-Object System.Collections.Generic.List[object]
$captionCues = New-Object System.Collections.Generic.List[object]
$pendingCaptionCues = New-Object System.Collections.Generic.List[object]
$markers = New-Object System.Collections.Generic.List[object]
$cursorFrame = 0
$longGapTotalFrames = 0
function Add-GapSegment([int]$SourceStartFrame,[int]$SourceEndFrame) {
    $gapFrames = $SourceEndFrame - $SourceStartFrame
    # Short gaps were already absorbed in seconds before quantization. A
    # preserved gap can round one frame below ceil(threshold*fps); applying
    # the threshold again would drop that entire source span.
    if ($gapFrames -le 0) { return }
    $newStartFrame = $script:cursorFrame
    $newEndFrame = $newStartFrame + $gapFrames
    $segments.Add([pscustomobject]@{
        Kind='gap';Unit='subtitle-no-dialogue';SourceStartFrame=$SourceStartFrame;SourceEndFrame=$SourceEndFrame
        SourceStart=Round6 (From-Frame $SourceStartFrame);SourceEnd=Round6 (From-Frame $SourceEndFrame)
        SourceDurationFrames=$gapFrames;SourceDuration=Round6 (From-Frame $gapFrames);EffectiveSourceDuration=Round6 (From-Frame $gapFrames);OriginalVoiceGap=0
        NewStartFrame=$newStartFrame;NewEndFrame=$newEndFrame;NewStart=Round6 (From-Frame $newStartFrame);NewEnd=Round6 (From-Frame $newEndFrame)
        OutputDurationFrames=$gapFrames;OutputDuration=Round6 (From-Frame $gapFrames)
        VoicePauseAdded=Round6 (From-Frame $gapFrames);VisualExtension=0;GapDetection='subtitle-threshold'
    })
    $script:cursorFrame = $newEndFrame
    $script:longGapTotalFrames += $gapFrames
}
Add-GapSegment $mainSourceStartFrame ([int]$groups[0].SourceStartFrame)

$speedWarningCount = 0
$captionIndex = 0
$voiceAlignedCaptionBoundaryCount = 0
for ($i=0; $i -lt $groups.Count; $i++) {
    $g = $groups[$i]
    $sourceFrames = [Math]::Max(1, [int]$g.SourceEndFrame - [int]$g.SourceStartFrame)
    $voiceFrames = [Math]::Max(1, [int]$g.VoiceEndFrame - [int]$g.VoiceStartFrame)
    $directSpeed = ($sourceFrames / [double]$voiceFrames) * 100.0
    $effectiveSourceFrames = $sourceFrames
    $visualFrames = $voiceFrames
    $borrowFrames = 0; $trimFrames = 0
    # Always use the complete source span and make picture duration exactly
    # equal to voice duration. Speed thresholds only create review markers.
    $speed = ($sourceFrames / [double]$visualFrames) * 100.0
    $speedWarning = $speed -lt $speedWarningMinPercent - 0.000001 -or $speed -gt $speedWarningMaxPercent + 0.000001
    if ($speedWarning) {
        $speedWarningCount++
    }
    $newStartFrame = $cursorFrame
    $newVoiceStartFrame = $cursorFrame
    $newVoiceEndFrame = $newVoiceStartFrame + $voiceFrames
    $newEndFrame = $cursorFrame + $visualFrames
    $segments.Add([pscustomobject]@{
        Kind='retime';Unit='sentence';SourceStartFrame=[int]$g.SourceStartFrame;SourceEndFrame=[int]$g.SourceEndFrame
        SourceStart=Round6 (From-Frame ([int]$g.SourceStartFrame));SourceEnd=Round6 (From-Frame ([int]$g.SourceEndFrame))
        SourceDurationFrames=$sourceFrames;SourceDuration=Round6 (From-Frame $sourceFrames)
        EffectiveSourceDurationFrames=$effectiveSourceFrames;EffectiveSourceDuration=Round6 (From-Frame $effectiveSourceFrames)
        TrimTailFrames=$trimFrames;TrimTailSeconds=Round6 (From-Frame $trimFrames)
        NewStartFrame=$newStartFrame;NewEndFrame=$newEndFrame;NewStart=Round6 (From-Frame $newStartFrame);NewEnd=Round6 (From-Frame $newEndFrame)
        OutputDurationFrames=($newEndFrame-$newStartFrame);OutputDuration=Round6 (From-Frame ($newEndFrame-$newStartFrame));VisualDurationFrames=$visualFrames
        OriginalVoiceStartFrame=[int]$g.VoiceStartFrame;OriginalVoiceEndFrame=[int]$g.VoiceEndFrame
        OriginalVoiceStart=Round6 (From-Frame ([int]$g.VoiceStartFrame));OriginalVoiceEnd=Round6 (From-Frame ([int]$g.VoiceEndFrame))
        NewVoiceStartFrame=$newVoiceStartFrame;NewVoiceEndFrame=$newVoiceEndFrame;NewVoiceStart=Round6 (From-Frame $newVoiceStartFrame);NewVoiceEnd=Round6 (From-Frame $newVoiceEndFrame)
        DesiredSpeedPercent=[Math]::Round($directSpeed,6);AppliedSpeedPercent=[Math]::Round($speed,9);SpeedOutsideWarningRange=[bool]$speedWarning
        BorrowFrames=0;BorrowSeconds=0
        FirstTargetCue=[int]$g.FirstCue;LastTargetCue=[int]$g.LastCue;Chapter=[int]$g.Chapter
        Confidence=[double]$g.Confidence;SafeVoiceCut=[bool]$g.SafeEnd;BoundarySilenceDuration=Round6 $g.BoundarySilenceDuration;Text=[string]$g.Text
    })
    $retimeSegmentIndex = $segments.Count - 1
    $voiceShiftFrames = $newVoiceStartFrame - [int]$g.VoiceStartFrame
    foreach ($cue in @($g.Cues | Where-Object {-not $acousticPartitioned})) {
        $manualCaption=[bool]($cue.PSObject.Properties['ManualEditBlock'] -and $cue.ManualEditBlock)
        $captionParts = @(if($manualCaption){Split-PvsManualReviewCaptionCue -Cue $cue -MaxCharacters $maxCaptionCharacters -FrameRate $fps -UseAcousticTiming:$manualAcoustic}else{Split-PvsVoiceAlignedCaptionCue -Cue $cue -MaxCharacters $maxCaptionCharacters -FrameRate $fps -VoiceSilences $voiceSilenceArray})
        foreach ($captionPart in $captionParts) {
            $captionIndex++
            if ([int]$captionPart.PartIndex -gt 1) {
                if (-not [bool]$captionPart.VoiceBoundaryAligned -and -not $manualCaption) { throw "CAPTION_WORD_TIMING_REQUIRED:$([int]$cue.Index):part-$([int]$captionPart.PartIndex)" }
                if($captionPart.VoiceBoundaryAligned){$voiceAlignedCaptionBoundaryCount++}
            }
            $pendingCaptionCues.Add([pscustomobject]@{Index=$captionIndex;Cue=$cue;Part=$captionPart;VoiceShiftFrames=$voiceShiftFrames;GroupStartFrame=$newVoiceStartFrame;GroupEndFrame=$newVoiceEndFrame})
        }
    }
    $hasRecoveredTiming = @($g.Cues | Where-Object { $_.PSObject.Properties['TimingRecovered'] -and [bool]$_.TimingRecovered }).Count -gt 0
    $recognitionCues=@($g.Cues | Where-Object {-not ($_.PSObject.Properties['ManualEditBlock'] -and $_.ManualEditBlock)})
    $hasLowRecognitionConfidence=@($recognitionCues | Where-Object {[double]$_.Confidence -lt $lowConfidenceThreshold}).Count -gt 0
    if ($hasRecoveredTiming -or $hasLowRecognitionConfidence) {
        $recognitionConfidence=if($recognitionCues.Count){($recognitionCues | Measure-Object Confidence -Minimum).Minimum}else{'not-applicable'}
        $markerReason = if ($hasRecoveredTiming) { "recovered timestamp; confidence=$recognitionConfidence" } else { "confidence=$recognitionConfidence" }
        $markers.Add([pscustomobject]@{Time=Round6 (From-Frame $newVoiceStartFrame);SegmentIndex=$retimeSegmentIndex;Owner='A2';Name='VOICE SYNC - Kiem tra can voice';Comments="Sentence cues $($g.FirstCue)-$($g.LastCue) $markerReason";ColorIndex=1})
    }
    $cursorFrame = $newEndFrame
    if ($i -lt $groups.Count-1) { Add-GapSegment ([int]$g.SourceEndFrame) ([int]$groups[$i+1].SourceStartFrame) }
}
Add-GapSegment ([int]$groups[$groups.Count-1].SourceEndFrame) $mainSourceEndFrame

if($acousticPartitioned){
    # Caption identity is independent of picture partition ownership. Queue
    # each display cell once, then map it through the complete physical voice.
    foreach($cue in $cues){
        $manualCaption=[bool]($cue.PSObject.Properties['ManualEditBlock'] -and $cue.ManualEditBlock)
        $parts=@(if($manualCaption){Split-PvsManualReviewCaptionCue $cue $maxCaptionCharacters $fps -UseAcousticTiming}else{Split-PvsVoiceAlignedCaptionCue -Cue $cue -MaxCharacters $maxCaptionCharacters -FrameRate $fps -VoiceSilences $voiceSilenceArray})
        foreach($part in $parts){
            $captionIndex++
            if($part.PartIndex -gt 1 -and $part.VoiceBoundaryAligned){$voiceAlignedCaptionBoundaryCount++}
            $pendingCaptionCues.Add([pscustomobject]@{Index=$captionIndex;Cue=$cue;Part=$part;VoiceShiftFrames=0;GroupStartFrame=0;GroupEndFrame=$cursorFrame})
        }
    }
}

# Fail before Premiere mutation if malformed cue ranges cannot partition the
# complete source. Every positive source frame must appear exactly once.
$sourceCursor=$mainSourceStartFrame;$outputCursor=0
foreach($segment in $segments){
    if($segment.SourceStartFrame -ne $sourceCursor -or $segment.NewStartFrame -ne $outputCursor -or
        $segment.SourceEndFrame -le $segment.SourceStartFrame -or $segment.NewEndFrame -le $segment.NewStartFrame){throw 'PLAN_FRAME_PARTITION_INVALID'}
    $sourceCursor=$segment.SourceEndFrame;$outputCursor=$segment.NewEndFrame
}
if($sourceCursor -ne $mainSourceEndFrame -or $outputCursor -ne $cursorFrame){throw 'PLAN_FRAME_TAIL_INVALID'}

$captionVoiceMap=@()
if($acousticPartitioned -or @($pendingCaptionCues | Where-Object {$_.Part.PSObject.Properties['IndependentSpeechEdges'] -and $_.Part.IndependentSpeechEdges}).Count){$captionVoiceMap=@(New-PvsCaptionVoiceMap -Segments $segments.ToArray())}
$legacyCaptionFrames=New-Object System.Collections.Generic.List[object]
foreach($pending in $pendingCaptionCues){
    $cue=$pending.Cue;$captionPart=$pending.Part
    $legacyStartFrame=[Math]::Max($pending.GroupStartFrame,[int]$captionPart.StartFrame+$pending.VoiceShiftFrames)
    $legacyEndFrame=[Math]::Min($pending.GroupEndFrame,[int]$captionPart.EndFrame+$pending.VoiceShiftFrames)
    if($acousticPartitioned){
        $legacyStartFrame=Get-PvsMappedCaptionFrame $captionVoiceMap ([int]$captionPart.StartFrame)
        $legacyEndFrame=Get-PvsMappedCaptionFrame $captionVoiceMap ([int]$captionPart.EndFrame) -EndEdge
    }
    if($legacyEndFrame -le $legacyStartFrame){$legacyEndFrame=[Math]::Min($pending.GroupEndFrame,$legacyStartFrame+1)}
    $legacyCaptionFrames.Add([pscustomobject]@{StartFrame=$legacyStartFrame;EndFrame=$legacyEndFrame})
    $independent=[bool]($captionPart.PSObject.Properties['IndependentSpeechEdges'] -and $captionPart.IndependentSpeechEdges)
    if($independent){
        $captionStartFrame=Get-PvsMappedCaptionFrame -VoiceMap $captionVoiceMap -SourceFrame ([int]$captionPart.StartFrame)
        $captionEndFrame=Get-PvsMappedCaptionFrame -VoiceMap $captionVoiceMap -SourceFrame ([int]$captionPart.EndFrame) -EndEdge
        if($captionEndFrame -le $captionStartFrame){throw "CAPTION_MAPPED_INTERVAL_INVALID:cue-$($cue.Index)"}
    }else{
        # Legacy/fallback evidence retains the previous conservative clamp.
        $captionStartFrame=$legacyStartFrame;$captionEndFrame=$legacyEndFrame
    }
    $caption=[pscustomobject]@{Index=$pending.Index;SourceCueIndex=[int]$cue.Index;PartIndex=[int]$captionPart.PartIndex;PartCount=[int]$captionPart.PartCount;Start=Round6 (From-Frame $captionStartFrame);End=Round6 (From-Frame $captionEndFrame);Text=[string]$captionPart.Text;Chapter=[int]$cue.Chapter;Confidence=[double]$cue.Confidence;VoiceBoundaryAligned=[bool]$captionPart.VoiceBoundaryAligned;IndependentSpeechEdges=$independent}
    if($captionPart.PSObject.Properties['ManualCaptionCellIndex']){
        $caption | Add-Member NoteProperty ManualCaptionCellIndex ([int]$captionPart.ManualCaptionCellIndex)
        $caption | Add-Member NoteProperty ManualReferenceCueIndices @($captionPart.ManualReferenceCueIndices)
        $caption | Add-Member NoteProperty CaptionTimingQuality ([string]$captionPart.CaptionTimingQuality)
    }
    $captionCues.Add($caption)
}
$captionArray = $captionCues.ToArray()
$captionMappingReviewCues=@(Resolve-PvsCaptionMappingConflicts -Captions $captionArray -LegacyFrames $legacyCaptionFrames.ToArray() -FrameRate $fps)
Add-PvsCaptionEdgePadding -Captions $captionArray -FrameRate $fps -TimelineEndFrame $cursorFrame
$captionPath=Join-Path $job.outputFolder 'sentence-plan.vi.srt'
Write-SrtFile $captionArray $captionPath
$linkedAudioForPlan=@();if($job.sequence.PSObject.Properties['linkedAudio']){$linkedAudioForPlan=@([object[]]$job.sequence.linkedAudio)}
$result=[ordered]@{
    audioCache=Get-PvsAudioCacheStats
    ok=$true;schemaVersion=8;plannerRevision=18;planner='sentence-frame-safe-silence-v2';createdAt=(Get-Date).ToString('o')
    sequenceId=[string]$job.sequence.sequenceId;sequenceName=[string]$job.sequence.name
    frameRate=$fps
    captionMappingReviewCues=$captionMappingReviewCues
    mainVideoClip=$job.sequence.mainVideoClip;linkedAudio=$linkedAudioForPlan;voiceTrackIndex=[int]$job.sequence.voiceTrackIndex;voiceClips=$voiceClips
    captionSrtPath=$captionPath;mainVideoSourceEnd=Round6 (From-Frame $mainSourceEndFrame);mainVideoSourceEndFrame=$mainSourceEndFrame;plannedMainVideoEnd=Round6 (From-Frame $cursorFrame);plannedMainVideoEndFrame=$cursorFrame
    speedWarningMinPercent=$speedWarningMinPercent;speedWarningMaxPercent=$speedWarningMaxPercent;speedThresholdMode='marker-only';minNoDialogueGapSeconds=$minNoDialogueGapSeconds
    settings=[ordered]@{silenceNoiseDb=$silenceNoiseDb;minSilenceDurationSeconds=$minSilenceDurationSeconds;boundarySearchSeconds=$boundarySearchSeconds;boundarySafetyMarginSeconds=$boundarySafetyMarginSeconds;lowConfidenceThreshold=$lowConfidenceThreshold;sentenceEndCharacters=$sentenceEndCharacters;maxCaptionCharacters=$maxCaptionCharacters;voiceMappingToleranceFrames=$voiceMappingToleranceFrames;validationToleranceFrames=$validationToleranceFrames;maxCoverageGapFrames=$maxCoverageGapFrames}
    summary=[ordered]@{inputCueCount=$cues.Count;recoveredUnalignedCueCount=$recoveredUnalignedCueCount;punctuationSentenceCount=$sentences.Count;safeSentenceGroupCount=$groups.Count;unsafeBoundaryMergeCount=$unsafeBoundaryMergeCount;lowConfidenceBoundaryMergeCount=$lowConfidenceBoundaryMergeCount;segmentCount=$segments.Count;longNoDialogueGapCount=@($segments|Where-Object Unit -eq 'subtitle-no-dialogue').Count;longNoDialogueGapSeconds=Round6 (From-Frame $longGapTotalFrames);speedWarningCount=$speedWarningCount;captionCueCount=$captionCues.Count;captionSplitCount=($captionCues.Count-$cues.Count);voiceAlignedCaptionBoundaryCount=$voiceAlignedCaptionBoundaryCount;markerCount=$markers.Count}
    segments=$segments.ToArray();captions=$captionCues.ToArray();markers=$markers.ToArray()
}
$outputPath=Join-Path $job.outputFolder 'sentence-edit-plan.json'
if($manualAcoustic){$result.manualCaptionTimingRevision='raw-dtw-cell-overlay-v1'}
if($acousticPartitioned){
    $result.acousticEditBoundaryRevision=$alignment.acousticEditBoundaryRevision
    $result.acousticEditBoundaryProofs=$acousticCuts
    $result.acousticEditReferenceCues=$alignment.acousticEditReferenceCues
    $result.acousticEditQuiet=$voiceSilenceArray
    $result.summary.independentAcousticCutCount=$acousticCuts.Count
}
$physicalGapCoordinates=[bool]$alignment.PSObject.Properties['sourceSubtitleGaps']
$sourceGaps=@(if($alignment.PSObject.Properties['sourceSubtitleGaps']){$alignment.sourceSubtitleGaps}else{
    for($i=0;$i+1 -lt $cues.Count;$i++){if($cues[$i+1].OriginalStart -gt $cues[$i].OriginalEnd){[pscustomobject]@{leftCue=[int]$cues[$i].Index;rightCue=[int]$cues[$i+1].Index;sourceStart=$cues[$i].OriginalEnd;sourceEnd=$cues[$i+1].OriginalStart}}}
})
$gapReview=New-Object System.Collections.Generic.List[object]
$gapBoundaries=New-Object System.Collections.Generic.List[object]
foreach($gap in $sourceGaps){
    if($gap.sourceEnd-$gap.sourceStart -lt $minNoDialogueGapSeconds){continue}
    $a=[double]$gap.sourceStart;$b=[double]$gap.sourceEnd
    if($null -ne $editedSourceMap){
        if(@($cues | Where-Object Index -eq $gap.leftCue).Count -ne 1 -or @($cues | Where-Object Index -eq $gap.rightCue).Count -ne 1){continue}
        if($physicalGapCoordinates){$a=ConvertTo-PvsEditedSourceTime $a $editedSourceMap $fps;$b=ConvertTo-PvsEditedSourceTime $b $editedSourceMap $fps}
    }
    $af=To-Frame $a;$bf=To-Frame $b
    if($af -lt $mainSourceStartFrame -or $bf -gt $mainSourceEndFrame -or $bf -le $af){continue}
    $item=[pscustomobject]@{leftCue=[int]$gap.leftCue;rightCue=[int]$gap.rightCue;sourceStartFrame=$af;sourceEndFrame=$bf;sourceStart=$a;sourceEnd=$b}
    $preserved=@($segments | Where-Object {$_.Kind -eq 'gap' -and $_.SourceStartFrame -le $af -and $_.SourceEndFrame -ge $bf})
    if($preserved.Count -eq 1){$gapBoundaries.Add($item)}else{$gapReview.Add($item)}
}
$result.sourceGapReviewRanges=$gapReview.ToArray()
$result.sourceGapBoundaries=$gapBoundaries.ToArray()
$result.summary.sourceGapReviewCount=$gapReview.Count
$result.settings.voiceGroupGapSeconds=[double](Get-AlgorithmSetting 'voiceGroupGapSeconds' 2.0)
if($null -eq $editedSourceMap){
    if(-not $pictureReferences.Count -and -not @($cues|Where-Object {$_.PSObject.Properties['ManualEditBlock'] -and $_.ManualEditBlock}).Count){
        $pictureReferences=@($cues|ForEach-Object {[pscustomobject]@{Index=$_.Index;Text=$_.Text;Start=$_.OriginalStart;End=$_.OriginalEnd}})
        $cueEvidence=@(Get-PvsReferenceCueEvidence $pictureReferences @() $cues $voiceClips)
    }
    if($cueEvidence.Count){
        $picturePlan=[pscustomobject]$result
        Add-PvsCuePicturePlan $picturePlan $pictureReferences $cueEvidence
        if($picturePlan.PSObject.Properties['pictureCueRevision']){
            foreach($field in @('pictureCueRevision','pictureCueBoundaries','pictureSegments','pictureCueSummary')){$result[$field]=$picturePlan.$field}
            $result.summary.pictureCueGroupCount=$picturePlan.pictureCueSummary.pictureGroups
        }
    }
}
if($alignment.PSObject.Properties['autoEditManualReviewBlocks'] -and @($alignment.autoEditManualReviewBlocks).Count){
    $result.manualReviewBlocks=$alignment.autoEditManualReviewBlocks
    $result.manualReviewStatus='manual-review-pending'
    $result.referenceCueCount=[int]$alignment.referenceCueCount
    $result.summary.manualReviewBlockCount=@($alignment.autoEditManualReviewBlocks).Count
    Assert-PvsManualReviewPlan ([pscustomobject]$result)
}
if($null -ne $editedSourceMap){
    $result.editedSourceMap=$editedSourceMap
    $result.omittedReferenceCueIndices=$alignment.omittedReferenceCueIndices
    $result.summary.omittedReferenceCueCount=@($alignment.omittedReferenceCueIndices).Count
    $result.summary.omittedSourceFrameCount=[int]$editedSourceMap.physicalEndFrame-[int]$editedSourceMap.planEndFrame
}
$result|ConvertTo-Json -Depth 12|Set-Content -LiteralPath $outputPath -Encoding UTF8
Write-Host "SENTENCE_PLAN_READY:$outputPath"
