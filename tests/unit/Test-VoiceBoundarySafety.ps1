$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$projectRoot = Resolve-Path (Join-Path $PSScriptRoot '..\..')
$sourceEngineRoot = Join-Path $projectRoot 'extension\engine'

function Invoke-BoundaryCase {
    param(
        [string]$Root,
        [string]$Name,
        [double]$FirstConfidence = 1.0,
        [double]$SecondConfidence = 1.0,
        [double]$FrameRate = 30,
        [double]$GapThreshold = 1,
        [double]$FirstSourceStart = 0,
        [double]$FirstSourceEnd = 1,
        [double]$SecondSourceStart = 1,
        [double]$SecondSourceEnd = 2,
        [double]$MainSourceEnd = 2,
        [object[]]$CustomCues = @(),
        [double]$VoiceEnd = 2
    )
    $caseRoot = Join-Path $Root $Name
    New-Item -ItemType Directory -Path $caseRoot -Force | Out-Null
    $wave = Join-Path $caseRoot 'voice.wav'
    Set-Content -LiteralPath $wave -Value '' -Encoding ASCII
    $alignment = [ordered]@{
        voiceChapterCount = 1
        cues = @(
            [ordered]@{Index=1;Text='Cau mot.';Start=0.0;End=1.0;OriginalStart=$FirstSourceStart;OriginalEnd=$FirstSourceEnd;Chapter=0;Confidence=$FirstConfidence},
            [ordered]@{Index=2;Text='Cau hai.';Start=1.0;End=2.0;OriginalStart=$SecondSourceStart;OriginalEnd=$SecondSourceEnd;Chapter=0;Confidence=$SecondConfidence}
        )
    }
    if ($CustomCues.Count) { $alignment.cues = $CustomCues }
    $alignment | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $caseRoot 'alignment-result.json') -Encoding UTF8
    $job = [ordered]@{
        algorithm=[ordered]@{useWhisperCache=$false;minNoDialogueGapSeconds=$GapThreshold}
        outputFolder=$caseRoot
        speedWarningMinPercent=70
        speedWarningMaxPercent=130
        sequence=[ordered]@{
            sequenceId=$Name;name=$Name;frameRate=$FrameRate
            mainVideoClip=[ordered]@{start=0;end=$MainSourceEnd}
            linkedAudio=@()
            voiceTrackIndex=1
            voices=@([ordered]@{name='voice.wav';path=$wave;start=0;end=$VoiceEnd;speedPercent=100})
        }
    }
    $jobPath = Join-Path $caseRoot 'job.json'
    $job | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $jobPath -Encoding UTF8
    & $planner -JobPath $jobPath | Out-Null
    return Get-Content -LiteralPath (Join-Path $caseRoot 'sentence-edit-plan.json') -Raw -Encoding UTF8 | ConvertFrom-Json
}

$temp = Join-Path $env:TEMP ('PVS-VoiceBoundary-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $temp -Force | Out-Null
try {
    # Run the real planner with a deterministic FFmpeg stand-in. Keeping the
    # test self-contained lets it run in clean GitHub checkouts where the
    # large ignored runtime bundle is intentionally absent.
    $testEngineRoot = Join-Path $temp 'engine'
    New-Item -ItemType Directory -Path (Join-Path $testEngineRoot 'lib'),(Join-Path $testEngineRoot 'runtime') -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $sourceEngineRoot 'build-sentence-plan.ps1') -Destination $testEngineRoot
    Copy-Item -LiteralPath (Join-Path $sourceEngineRoot 'lib\Srt.ps1') -Destination (Join-Path $testEngineRoot 'lib')
    Copy-Item -LiteralPath (Join-Path $sourceEngineRoot 'lib\ReferenceAlignment.ps1') -Destination (Join-Path $testEngineRoot 'lib')
    Copy-Item -LiteralPath (Join-Path $sourceEngineRoot 'lib\CaptionTiming.ps1') -Destination (Join-Path $testEngineRoot 'lib')
    Copy-Item -LiteralPath (Join-Path $sourceEngineRoot 'lib\AutoEditAcousticPartitions.ps1') -Destination (Join-Path $testEngineRoot 'lib')
    Copy-Item -LiteralPath (Join-Path $sourceEngineRoot 'lib\AutoEditManualReview.ps1') -Destination (Join-Path $testEngineRoot 'lib')
    Copy-Item -LiteralPath (Join-Path $sourceEngineRoot 'lib\RecognitionBackend.ps1') -Destination (Join-Path $testEngineRoot 'lib')
    Copy-Item -LiteralPath (Join-Path $sourceEngineRoot 'lib\SubtitleTiming.ps1') -Destination (Join-Path $testEngineRoot 'lib')
    Copy-Item -LiteralPath (Join-Path $sourceEngineRoot 'lib\SubtitleEnergy.ps1') -Destination (Join-Path $testEngineRoot 'lib')
    foreach($name in @('Security.ps1','AudioCache.ps1')){Copy-Item -LiteralPath (Join-Path $sourceEngineRoot "lib\$name") -Destination (Join-Path $testEngineRoot 'lib')}
    foreach($name in @('runtime-lock.json','cuda-lock.json')){Copy-Item -LiteralPath (Join-Path $sourceEngineRoot $name) -Destination $testEngineRoot}
    Set-Content -LiteralPath (Join-Path $testEngineRoot 'lib\Native.ps1') -Value '. "$PSScriptRoot\Security.ps1"; . "$PSScriptRoot\AudioCache.ps1"; function Invoke-NativeCapture {param($FilePath,$Arguments);[pscustomobject]@{ExitCode=0;Output=((& $FilePath @Arguments)|Out-String)}}' -Encoding ASCII
    Copy-Item -LiteralPath (Join-Path $sourceEngineRoot 'lib\vi-caption-phrases.txt') -Destination (Join-Path $testEngineRoot 'lib')
    Copy-Item -LiteralPath (Join-Path $sourceEngineRoot 'lib\vi-caption-overrides.txt') -Destination (Join-Path $testEngineRoot 'lib')
    Copy-Item -LiteralPath (Join-Path $sourceEngineRoot 'lib\Paths.ps1') -Destination (Join-Path $testEngineRoot 'lib')
    $planner = Join-Path $testEngineRoot 'build-sentence-plan.ps1'
    @'
$joined = $args -join ' '
if ($joined -match '[\\/]reused-quiet[\\/]') {
    'silence_start: 0.8'
    'silence_end: 1.2'
} elseif ($joined -match '[\\/]right-collapse[\\/]') {
    'silence_start: 0.94'
    'silence_end: 1.34'
} elseif ($joined -match '[\\/]unsafe[\\/]') {
    'silence_start: 0.98'
    'silence_end: 1.03'
    'silence_start: 1.25'
    'silence_end: 1.55'
} else {
    'silence_start: 0.88'
    'silence_end: 1.22'
}
'@ | Set-Content -LiteralPath (Join-Path $testEngineRoot 'runtime\fake-ffmpeg.ps1') -Encoding ASCII
    '{"ffmpeg":"fake-ffmpeg.ps1"}' | Set-Content -LiteralPath (Join-Path $testEngineRoot 'runtime\engine.json') -Encoding ASCII

    # A 50 ms dip at the expected timestamp is an intra-word false silence.
    # A longer pause 250 ms away is also too far to trust. Both cues must stay
    # together rather than cutting either speech region.
    $unsafe = Invoke-BoundaryCase -Root $temp -Name 'unsafe'
    if ([int]$unsafe.summary.safeSentenceGroupCount -ne 1) { throw 'UNSAFE_BOUNDARY_WAS_CUT' }

    # A real pause straddling the recognized sentence boundary must create one
    # frame-aligned cut inside the guarded center of the silence.
    $safe = Invoke-BoundaryCase -Root $temp -Name 'safe'
    if ([int]$safe.summary.safeSentenceGroupCount -ne 2) { throw 'SAFE_BOUNDARY_WAS_NOT_CUT' }
    $retime = @($safe.segments | Where-Object {$_.Kind -eq 'retime'})
    if ($retime.Count -ne 2) { throw "SAFE_RETIME_COUNT_FAILED:$($retime.Count)" }
    if ([int]$retime[0].OriginalVoiceEndFrame -ne 32 -or [int]$retime[1].OriginalVoiceStartFrame -ne 32) { throw "SAFE_FRAME_CENTER_FAILED:$($retime[0].OriginalVoiceEndFrame)-$($retime[1].OriginalVoiceStartFrame)" }

    # Even a clean pause is not trusted when either neighboring sentence has
    # weak text alignment; merging preserves every spoken word.
    $weak = Invoke-BoundaryCase -Root $temp -Name 'weak' -SecondConfidence 0.2
    if ([int]$weak.summary.safeSentenceGroupCount -ne 1) { throw 'LOW_CONFIDENCE_BOUNDARY_WAS_CUT' }
    if ([int]$weak.summary.lowConfidenceBoundaryMergeCount -ne 1) { throw 'LOW_CONFIDENCE_MERGE_NOT_REPORTED' }

    # Both sentence boundaries land in the same silence. The middle sentence
    # must not become a synthetic one-frame clip overlapping the next slice.
    foreach ($frameRate in @(30.0,(30000.0/1001))) {
        $reused = Invoke-BoundaryCase -Root $temp -Name 'reused-quiet' -FrameRate $frameRate -MainSourceEnd 3 -VoiceEnd 3 -CustomCues @(
            [ordered]@{Index=1;Text='First sentence.';Start=0;End=0.98;OriginalStart=0;OriginalEnd=1;Chapter=0;Confidence=1},
            [ordered]@{Index=2;Text='Ha ha!';Start=0.98;End=1.08;OriginalStart=1;OriginalEnd=1.2;Chapter=0;Confidence=1},
            [ordered]@{Index=3;Text='Next sentence.';Start=1.08;End=3;OriginalStart=1.2;OriginalEnd=3;Chapter=0;Confidence=1}
        )
        $slices=@($reused.segments | Where-Object Kind -eq 'retime')
        if ($slices.Count -ne 2 -or $slices[1].FirstTargetCue -ne 2 -or $slices[1].LastTargetCue -ne 3) { throw 'REUSED_QUIET_NOT_MERGED' }
        if ($slices[0].OriginalVoiceEndFrame -ne $slices[1].OriginalVoiceStartFrame -or $slices[1].OriginalVoiceEndFrame -ne [Math]::Round(3*$frameRate)) { throw 'REUSED_QUIET_VOICE_NOT_CONSERVED' }
        if (@($slices | Where-Object { $_.OriginalVoiceEndFrame -le $_.OriginalVoiceStartFrame }).Count) { throw 'REUSED_QUIET_COLLAPSED' }
        if ($reused.summary.unsafeBoundaryMergeCount -ne 1) { throw 'REUSED_QUIET_MERGE_NOT_REPORTED' }
    }
    # A quiet center after the next sentence's final frame cannot be a cut.
    $rightCollapsed = Invoke-BoundaryCase -Root $temp -Name 'right-collapse' -MainSourceEnd 1.1 -VoiceEnd 1.1 -CustomCues @(
        [ordered]@{Index=1;Text='First sentence.';Start=0;End=1.05;OriginalStart=0;OriginalEnd=1;Chapter=0;Confidence=1},
        [ordered]@{Index=2;Text='Short ending.';Start=1.05;End=1.1;OriginalStart=1;OriginalEnd=1.1;Chapter=0;Confidence=1}
    )
    if ($rightCollapsed.summary.safeSentenceGroupCount -ne 1 -or $rightCollapsed.segments[0].OriginalVoiceEndFrame -ne 33) { throw 'RIGHT_COLLAPSE_CUT_ACCEPTED' }
    $invalidRejected=$false
    try {
        $null=Invoke-BoundaryCase -Root $temp -Name 'invalid-voice-range' -MainSourceEnd 1 -CustomCues @(
            [ordered]@{Index=1;Text='Collapsed.';Start=0.01;End=0.015;OriginalStart=0;OriginalEnd=1;Chapter=0;Confidence=1}
        )
    } catch {
        if ($_.Exception.Message -ne 'PLAN_VOICE_RANGE_INVALID:cue-1-1:0-0') { throw }
        $invalidRejected=$true
    }
    if (-not $invalidRejected) { throw 'COLLAPSED_VOICE_PADDED_WITH_SYNTHETIC_FRAME' }

    if ([int]$safe.plannerRevision -ne 18) { throw 'PLANNER_REVISION_FAILED' }
    if ([double]$safe.settings.minSilenceDurationSeconds -ne 0.12) { throw 'MIN_SILENCE_DEFAULT_FAILED' }
    if ([double]$safe.settings.boundarySearchSeconds -ne 0.12) { throw 'BOUNDARY_WINDOW_DEFAULT_FAILED' }
    if ([double]$safe.settings.boundarySafetyMarginSeconds -ne 0.04) { throw 'BOUNDARY_MARGIN_FAILED' }
    # Threshold decisions are made in seconds before quantization. Rounding
    # a preserved gap below ceil(threshold*fps) must never discard its video.
    $gapCases=@(
        (Invoke-BoundaryCase -Root $temp -Name 'gap-middle' -FrameRate 29.97 -GapThreshold 1.1 -FirstSourceEnd (20.51/29.97) -SecondSourceStart (20.51/29.97+1.1005) -SecondSourceEnd 3 -MainSourceEnd 3),
        (Invoke-BoundaryCase -Root $temp -Name 'gap-leading' -GapThreshold 1.01 -FirstSourceStart 1.011 -FirstSourceEnd 2 -SecondSourceStart 2 -SecondSourceEnd 3 -MainSourceEnd 3),
        (Invoke-BoundaryCase -Root $temp -Name 'gap-trailing' -GapThreshold 1.01 -FirstSourceEnd 2 -SecondSourceStart 2 -SecondSourceEnd 3.989 -MainSourceEnd 5)
    )
    foreach($plan in $gapCases){
        $cursor=0
        foreach($segment in $plan.segments){
            if($segment.SourceStartFrame -ne $cursor){throw "SOURCE_GAP_DROPPED:$($plan.sequenceName):$cursor-$($segment.SourceStartFrame)"}
            $cursor=$segment.SourceEndFrame
        }
        if($cursor -ne $plan.mainVideoSourceEndFrame){throw "SOURCE_TAIL_DROPPED:$($plan.sequenceName)"}
        if($plan.summary.longNoDialogueGapCount -ne 1){throw "PRESERVED_GAP_COUNT:$($plan.sequenceName)"}
    }
    Write-Host 'VOICE_BOUNDARY_SAFETY_OK:weak-and-safe;reused-quiet-and-right-collapse-merged;30-and-29.97fps;quantized-middle-leading-trailing-gap-conservation'
}
finally {
    if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Recurse -Force }
}
