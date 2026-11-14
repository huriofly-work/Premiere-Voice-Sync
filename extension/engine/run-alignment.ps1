param([Parameter(Mandatory)][string]$JobPath)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. "$PSScriptRoot\lib\Srt.ps1"
. "$PSScriptRoot\lib\Alignment.ps1"
. "$PSScriptRoot\lib\Native.ps1"
. "$PSScriptRoot\lib\Paths.ps1"
. "$PSScriptRoot\lib\Security.ps1"
. "$PSScriptRoot\lib\CaptionOnly.ps1"
. "$PSScriptRoot\lib\AutoEditManualReview.ps1"
Assert-PvsRuntimeLock -EngineRoot $PSScriptRoot

$job = Get-Content -LiteralPath $JobPath -Raw -Encoding UTF8 | ConvertFrom-Json
$language = if ($job.PSObject.Properties['language']) { [string]$job.language } else { 'vi' }
if ($language -notmatch '^(vi|auto|en|zh|ja|ko|fr|de|es|pt|ru|it|id|hi|ar)$') { throw 'INVALID_SETTING:voice language is not supported.' }
Assert-PvsSafePath -Path $job.outputFolder -Tree
$algorithm = if ($job.PSObject.Properties['algorithm']) { $job.algorithm } else { $null }
$voiceGroupGapSeconds = if ($null -ne $algorithm -and $algorithm.PSObject.Properties['voiceGroupGapSeconds']) { [double]$algorithm.voiceGroupGapSeconds } else { 2.0 }
$useWhisperCache = if ($null -ne $algorithm -and $algorithm.PSObject.Properties['useWhisperCache']) { [bool]$algorithm.useWhisperCache } else { $true }
Initialize-PvsAudioCache -Enabled $useWhisperCache -RuntimeIdentity ((Get-PvsAudioFileDigest "$PSScriptRoot\runtime-lock.json")+'|'+(Get-PvsAudioFileDigest "$PSScriptRoot\cuda-lock.json"))
$lowConfidenceThreshold = if ($null -ne $algorithm -and $algorithm.PSObject.Properties['lowConfidenceThreshold']) { [double]$algorithm.lowConfidenceThreshold } else { 0.55 }
if ([double]::IsNaN($voiceGroupGapSeconds) -or [double]::IsInfinity($voiceGroupGapSeconds) -or $voiceGroupGapSeconds -lt 0.2 -or $voiceGroupGapSeconds -gt 20) { throw 'INVALID_SETTING:voiceGroupGapSeconds must be between 0.2 and 20.' }
if ([double]::IsNaN($lowConfidenceThreshold) -or [double]::IsInfinity($lowConfidenceThreshold) -or $lowConfidenceThreshold -lt 0 -or $lowConfidenceThreshold -gt 1) { throw 'INVALID_SETTING:lowConfidenceThreshold must be between 0 and 1.' }
$runtimeConfigPath = Join-Path $PSScriptRoot 'runtime\engine.json'
if (-not (Test-Path -LiteralPath $runtimeConfigPath)) { throw 'ENGINE_NOT_INSTALLED' }
$engine = Get-Content -LiteralPath $runtimeConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
$runtimeRoot = Split-Path $runtimeConfigPath -Parent
function Resolve-EnginePath([string]$Value) {
    if ([IO.Path]::IsPathRooted($Value)) { return $Value }
    return Join-Path $runtimeRoot $Value
}
$ffmpegPath = Resolve-EnginePath ([string]$engine.ffmpeg)
$cpuWhisperPath = Resolve-EnginePath ([string]$engine.whisper)
$modelPath = Resolve-EnginePath ([string]$engine.modelPath)
$backend = $null
try {
    $backendText = (& "$PSScriptRoot\resolve-backend.ps1" | Out-String).Trim()
    if ($backendText) { $backend = $backendText | ConvertFrom-Json }
} catch {
    $backend = [pscustomobject]@{
        ok=$true;backend='cpu';label='CPU';whisperPath=$cpuWhisperPath;arguments=@('--no-gpu')
        reason="Backend resolver that bai; dung CPU. $($_.Exception.Message)";statePath=''
    }
}
if ($null -eq $backend -or -not $backend.ok) { throw 'Khong khoi tao duoc Whisper backend.' }
$whisperPath = [string]$backend.whisperPath
$whisperArguments = @([string[]]$backend.arguments)
$recognitionBackend = [string]$backend.backend
$recognitionBackendLabel = [string]$backend.label
$gpuFallbackUsed = $false
$gpuFallbackReason = ''
$backendInvocationCount = 0
$appDataRoot = Join-Path $env:LOCALAPPDATA 'PremiereVoiceSync'
Assert-PvsSafePath -Path $appDataRoot -Tree
New-Item -ItemType Directory -Path $appDataRoot -Force | Out-Null
if ($modelPath -match '[^\x00-\x7F]') {
    $modelPath = Get-PvsVerifiedModelCopy -Source $modelPath -DataRoot $appDataRoot
}
$targetCues = Read-SrtFile $job.targetSrtPath
$allVoiceClips = @([object[]]$job.sequence.voices | Sort-Object start)
$voiceList = New-Object System.Collections.Generic.List[object]
for ($voiceIndex = 0; $voiceIndex -lt $allVoiceClips.Count; $voiceIndex++) {
    if ($voiceIndex -gt 0) {
        $previous = $allVoiceClips[$voiceIndex - 1]
        $gap = [double]$allVoiceClips[$voiceIndex].start - [double]$previous.end
        if ($gap -gt $voiceGroupGapSeconds) { break }
    }
    $voiceList.Add($allVoiceClips[$voiceIndex])
}
$voiceClips = $voiceList.ToArray()
if ($voiceClips.Count -eq 0) { throw 'Khong tim thay nhom voice dich lien tuc tren A2.' }

$recognized = New-Object System.Collections.Generic.List[object]
$safeTempRoot = Join-Path $env:TEMP 'PremiereVoiceSync'
Assert-PvsSafePath -Path $safeTempRoot -Tree
$staleBefore = (Get-Date).AddHours(-24)
if (Test-Path -LiteralPath $safeTempRoot -PathType Container) {
    Get-ChildItem -LiteralPath $safeTempRoot -Directory -Filter 'job-*' -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -lt $staleBefore } | ForEach-Object {
        Remove-PvsSafeTree -Path $_.FullName -Root $safeTempRoot
    }
}
$analysisDir = Join-Path $safeTempRoot ("job-{0}-{1}" -f $PID, ([guid]::NewGuid().ToString('N')))

function Write-PvsAutoEditPreservationResult {
    param($Reason,[int[]]$UnresolvedCueIndices=@())
    if(-not $UnresolvedCueIndices.Count){$UnresolvedCueIndices=@($targetCues.Index)}
    $review=[ordered]@{ok=$true;stage='alignment';alignmentSchemaVersion=4;preserveTimeline=$true;manualReviewStatus='manual-review-pending';referenceCueCount=$targetCues.Count;unresolvedReferenceCueIndices=$UnresolvedCueIndices;reviewReason=$Reason;recognitionBackend=$recognitionBackend;recognitionBackendLabel=$recognitionBackendLabel;backendReason=[string]$backend.reason;gpuFallbackUsed=$gpuFallbackUsed;gpuFallbackReason=$gpuFallbackReason;audioCache=Get-PvsAudioCacheStats;recognitionReviewTasks=@(for($ch=0;$ch -lt $voiceClips.Count;$ch++){[pscustomobject]@{chapter=$ch;start=[double]$voiceClips[$ch].start;end=[double]$voiceClips[$ch].end;reason='Chưa xác định được vùng hình tương ứng chắc chắn; giữ nguyên timeline và cần dựng thủ công.';status='manual-review-pending'}})}
    $review | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $job.outputFolder 'alignment-result.json') -Encoding UTF8
    Write-Host 'ALIGNMENT_READY:manual-review-pending;timeline-preserved'
}

try {
New-Item -ItemType Directory -Path $analysisDir -Force | Out-Null
for ($i = 0; $i -lt $voiceClips.Count; $i++) {
    $voice = $voiceClips[$i]
    $voiceMediaPath = Resolve-PvsExistingPath -Path ([string]$voice.path) -Purpose 'Voice media for alignment'
    $wav = Join-Path $analysisDir ("voice-{0:000}.wav" -f ($i + 1))
    $outBase = Join-Path $analysisDir ("voice-{0:000}" -f ($i + 1))
    $jsonPath = "$outBase.json"
    # Unified content-addressed cache also covers recovery/numeric windows.
    # PCM is temporary; timestamps remain source-relative until mapped below.
    $ffmpegRun = Invoke-NativeCapture -FilePath $ffmpegPath -Arguments @('-y','-hide_banner','-loglevel','error','-i',$voiceMediaPath,'-ar','16000','-ac','1','-c:a','pcm_s16le',$wav)
    if ($ffmpegRun.ExitCode -ne 0) { throw "FFmpeg that bai voi $($voice.name): $($ffmpegRun.Output)" }
    $recognitionArgs = @($whisperArguments) + @(Get-PvsWhisperRecognitionArguments -ModelPath $modelPath -WavPath $wav -Language $language -OutBase $outBase)
    $whisperRun = Invoke-PvsWhisperCapture -FilePath $whisperPath -Arguments $recognitionArgs -WorkingDirectory (Split-Path $whisperPath -Parent)
    if(-not $whisperRun.PSObject.Properties['CacheHit'] -or -not $whisperRun.CacheHit){$backendInvocationCount++}
    $gpuBackendLoaded = $recognitionBackend -eq 'cpu' -or [string]$whisperRun.Output -match '(?im)^load_backend:\s+loaded CUDA backend from .+ggml-cuda\.dll'
    if (($whisperRun.ExitCode -ne 0 -or -not $gpuBackendLoaded) -and $recognitionBackend -ne 'cpu') {
        $gpuFallbackUsed = $true
        $gpuFallbackReason = if ($whisperRun.ExitCode -eq 0 -and -not $gpuBackendLoaded) {
            'Whisper khong nap ggml-cuda.dll va da am tham chay CPU.'
        } else {
            (($whisperRun.Output -replace '\s+',' ').Trim())
        }
        if ($backend.PSObject.Properties['statePath'] -and [string]$backend.statePath -and (Test-Path -LiteralPath ([string]$backend.statePath))) {
            try {
                $backendState = Get-Content -LiteralPath ([string]$backend.statePath) -Raw -Encoding UTF8 | ConvertFrom-Json
                $backendState.probeVerified = $false
                $backendState.disabledUntil = (Get-Date).AddDays(1).ToString('o')
                $backendState | Add-Member -NotePropertyName runtimeFailure -NotePropertyValue $gpuFallbackReason -Force
                $backendState | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath ([string]$backend.statePath) -Encoding UTF8
            } catch {}
        }
        $recognitionBackend = 'cpu'
        $recognitionBackendLabel = 'CPU fallback'
        $whisperPath = $cpuWhisperPath
        $whisperArguments = @('--no-gpu')
        if (Test-Path -LiteralPath $jsonPath) { Remove-Item -LiteralPath $jsonPath -Force }
        $recognitionArgs = @($whisperArguments) + @(Get-PvsWhisperRecognitionArguments -ModelPath $modelPath -WavPath $wav -Language $language -OutBase $outBase)
        $whisperRun = Invoke-PvsWhisperCapture -FilePath $whisperPath -Arguments $recognitionArgs -WorkingDirectory (Split-Path $whisperPath -Parent)
        if(-not $whisperRun.PSObject.Properties['CacheHit'] -or -not $whisperRun.CacheHit){$backendInvocationCount++}
    }
    if ($whisperRun.ExitCode -ne 0) { throw "Whisper that bai voi $($voice.name) (exit code $($whisperRun.ExitCode)): $($whisperRun.Output)" }
    $speedPercent = 100.0
    if ($voice.PSObject.Properties['speedPercent']) { $speedPercent = [double]$voice.speedPercent }
    if ($speedPercent -le 0) { $speedPercent = 100.0 }
    $timeScale = 100.0 / $speedPercent
    foreach ($word in (ConvertTo-PvsBoundedEditWords -Words @(Convert-WhisperJsonToWords $jsonPath $i -PreserveSurface) -Duration ([double]$voice.end-[double]$voice.start) -Scale $timeScale)) {
        $recognized.Add($word)
    }
}

if(-not $recognized.Count){
    Write-PvsAutoEditPreservationResult ([pscustomobject]@{reason='recognition-empty'})
    return
}
$aligned = @(Align-CuesToRecognizedWords -Cues $targetCues -RecognizedWords ($recognized.ToArray()) -VoiceClips $voiceClips)
$recoveryInvocationCount = 0
$numericCaptionInvocationCount = 0
$recognizeWindow = {
    param($voice, [double]$windowStart, [double]$windowEnd, [string]$Prompt='')
    if($Prompt){$script:numericCaptionInvocationCount++}else{$script:recoveryInvocationCount++}
    $callNumber=$script:numericCaptionInvocationCount+$script:recoveryInvocationCount
    $speed = if ($voice.PSObject.Properties['speedPercent']) { [double]$voice.speedPercent } else { 100.0 }
    if ($speed -le 0) { $speed = 100.0 }
    $scale = 100.0 / $speed
    $sourceStart = ($windowStart - [double]$voice.start) / $scale
    $sourceDuration = ($windowEnd - $windowStart) / $scale
    $wav = Join-Path $analysisDir ("recovery-{0:000}.wav" -f $callNumber)
    $outBase = Join-Path $analysisDir ("recovery-{0:000}" -f $callNumber)
    $mediaPath = Resolve-PvsExistingPath -Path ([string]$voice.path) -Purpose 'Voice word timing recovery'
    $ffmpegRun = Invoke-NativeCapture -FilePath $ffmpegPath -Arguments @('-y','-hide_banner','-loglevel','error','-ss',$sourceStart.ToString('0.######',[Globalization.CultureInfo]::InvariantCulture),'-i',$mediaPath,'-t',$sourceDuration.ToString('0.######',[Globalization.CultureInfo]::InvariantCulture),'-ar','16000','-ac','1','-c:a','pcm_s16le',$wav)
    if ($ffmpegRun.ExitCode -ne 0) { throw "VOICE_TIMING_RECOVERY_FFMPEG_FAILED:$($ffmpegRun.Output)" }
    $recoveryArgs = @($script:whisperArguments) + @(Get-PvsWhisperRecognitionArguments -ModelPath $modelPath -WavPath $wav -Language $language -OutBase $outBase)
    if($Prompt){$recoveryArgs+=@('--prompt',$Prompt)}
    $run = Invoke-PvsWhisperCapture -FilePath $script:whisperPath -Arguments $recoveryArgs -WorkingDirectory (Split-Path $script:whisperPath -Parent)
    if(-not $run.PSObject.Properties['CacheHit'] -or -not $run.CacheHit){$script:backendInvocationCount++}
    $gpuLoaded = $script:recognitionBackend -eq 'cpu' -or [string]$run.Output -match '(?im)^load_backend:\s+loaded CUDA backend from .+ggml-cuda\.dll'
    if (($run.ExitCode -ne 0 -or -not $gpuLoaded) -and $script:recognitionBackend -ne 'cpu') {
        $script:gpuFallbackUsed = $true
        $script:gpuFallbackReason = if (-not $gpuLoaded -and $run.ExitCode -eq 0) { 'Whisper khong nap CUDA trong buoc phuc hoi timestamp.' } else { ($run.Output -replace '\s+',' ').Trim() }
        $script:recognitionBackend = 'cpu'
        $script:recognitionBackendLabel = 'CPU fallback'
        $script:whisperPath = $cpuWhisperPath
        $script:whisperArguments = @('--no-gpu')
        if (Test-Path -LiteralPath "$outBase.json") { Remove-Item -LiteralPath "$outBase.json" -Force }
        $recoveryArgs = @('--no-gpu') + @(Get-PvsWhisperRecognitionArguments -ModelPath $modelPath -WavPath $wav -Language $language -OutBase $outBase)
        if($Prompt){$recoveryArgs+=@('--prompt',$Prompt)}
        $run = Invoke-PvsWhisperCapture -FilePath $cpuWhisperPath -Arguments $recoveryArgs -WorkingDirectory (Split-Path $cpuWhisperPath -Parent)
        if(-not $run.PSObject.Properties['CacheHit'] -or -not $run.CacheHit){$script:backendInvocationCount++}
    }
    if ($run.ExitCode -ne 0) { throw "VOICE_TIMING_RECOVERY_WHISPER_FAILED:$($run.Output)" }
    foreach ($word in (ConvertTo-PvsBoundedEditWords -Words @(Convert-WhisperJsonToWords "$outBase.json" 0 -PreserveSurface) -Duration ($windowEnd-$windowStart) -Scale $scale)) {
        # Whisper's final token can extend beyond the cropped PCM file. The
        # physical chapter edge is authoritative, just as in the first pass.
        if ($word.End -gt $word.Start) { $word }
    }
}
$editedReference=$null
$referenceRecovery=[pscustomobject]@{Repaired=$false;RecoveredCueIndices=@();Recovery=@()}
$manualReview=[pscustomobject]@{Blocks=@();Status='complete'}
$incomplete=@($aligned | Where-Object {$_.Confidence -lt $lowConfidenceThreshold -or @($_.WordTimings).Count -ne @(ConvertTo-NormalizedWords $_.Text).Count})
if($incomplete.Count){
    $referenceRecovery=Repair-PvsAutoEditReferenceWords -Cues $targetCues -Aligned $aligned -Words $recognized.ToArray() -Sources $voiceClips -RecognizeWindow $recognizeWindow -Language $language -LowConfidenceThreshold $lowConfidenceThreshold
    if($referenceRecovery.RecoveredCueIndices.Count){$aligned=@($referenceRecovery.Cues)}
}
if($incomplete.Count -and -not $referenceRecovery.Repaired){
    $editedReference=Resolve-PvsEditedReference -Cues $targetCues -Words $recognized.ToArray() -Sources $voiceClips -RecognizeWindow $recognizeWindow
    if($null -eq $editedReference){
        $editedReference=[pscustomobject]@{Resolved=$false;Words=$recognized.ToArray();UnresolvedCueIndices=@($targetCues.Index)}
    }
    if($null -ne $editedReference){
        if(-not $editedReference.Resolved){
            $manualFailure=$null
            $manual=New-PvsAutoEditManualReview -Cues $targetCues -Aligned $aligned -Edited $editedReference -Sources $voiceClips -MainVideo $job.sequence.mainVideoClip -FrameRate ([double]$job.sequence.frameRate) -Language $language -Failure ([ref]$manualFailure) -PreserveRecognitionFailures
            if($null -eq $manual){
                # No reliable source/voice partition: finish with a review
                # result and keep the template untouched. Never fabricate a
                # chapter map or invoke the native editing executor here.
                Write-PvsAutoEditPreservationResult $manualFailure @($editedReference.UnresolvedCueIndices)
                return
            }
            $manualReview=$manual
            $aligned=@($manual.Cues)
        }else{$aligned=@($editedReference.Cues)}
        $recognized.Clear();foreach($word in $editedReference.Words){$recognized.Add($word)}
        # A manual block preserves every picture range, including any tentative
        # omission in the old report. It never carries an omission/source map.
        if($manualReview.Blocks.Count){$editedReference=$null}
    }
}
$wordTimingRecoveredCues = @(Repair-PvsMissingCueWordTimings -Cues $aligned -VoiceClips $voiceClips -RecognizeWindow $recognizeWindow)
# Recognition can extend a word a few milliseconds beyond its chapter file,
# especially after compensating for a Premiere speed change. Clamp every cue
# to the real chapter clip and make adjacent cue boundaries monotonic so QE
# razor never has to represent overlapping audio pieces on one track.
for ($alignedIndex = 0; $alignedIndex -lt $aligned.Count; $alignedIndex++) {
    $alignedCue = $aligned[$alignedIndex]
    if ($null -eq $alignedCue.Start -or $null -eq $alignedCue.End) { continue }
    $chapterIndex = [int]$alignedCue.Chapter
    if ($chapterIndex -ge 0 -and $chapterIndex -lt $voiceClips.Count) {
        $chapterClip = $voiceClips[$chapterIndex]
        $alignedCue.Start = [Math]::Max([double]$chapterClip.start, [double]$alignedCue.Start)
        $alignedCue.End = [Math]::Min([double]$chapterClip.end, [double]$alignedCue.End)
        if ([double]$alignedCue.End -le [double]$alignedCue.Start) {
            $alignedCue.End = [Math]::Min([double]$chapterClip.end, [double]$alignedCue.Start + 0.001)
        }
    }
}
for ($alignedIndex = 1; $alignedIndex -lt $aligned.Count; $alignedIndex++) {
    $previousCue = $aligned[$alignedIndex - 1]
    $currentCue = $aligned[$alignedIndex]
    if ($null -eq $previousCue.End -or $null -eq $currentCue.Start) { continue }
    if ([double]$currentCue.Start -lt [double]$previousCue.End) {
        if ([int]$previousCue.Chapter -ne [int]$currentCue.Chapter) {
            $previousChapter = $voiceClips[[int]$previousCue.Chapter]
            $currentChapter = $voiceClips[[int]$currentCue.Chapter]
            $previousCue.End = [Math]::Min([double]$previousCue.End, [double]$previousChapter.end)
            $currentCue.Start = [Math]::Max([double]$currentCue.Start, [double]$currentChapter.start)
        }
        if ([double]$currentCue.Start -lt [double]$previousCue.End) {
            $sharedBoundary = ([double]$currentCue.Start + [double]$previousCue.End) / 2.0
            $previousCue.End = $sharedBoundary
            $currentCue.Start = $sharedBoundary
        }
    }
}
$valid = @($aligned | Where-Object { $null -ne $_.Start -and $null -ne $_.End })
$numericCues=@($aligned | Where-Object {-not ($_.PSObject.Properties['ManualEditBlock'] -and $_.ManualEditBlock)})
$numericCaptions=if($numericCues.Count){Repair-PvsNumericCaptionTimings -Cues $numericCues -VoiceClips $voiceClips -RecognizeWindow $recognizeWindow -Language $language}else{[pscustomobject]@{Refined=@();Review=@()}}
$captionTiming=Prepare-PvsAutoCaptionTimings -ApplyEditTiming -FrameRate ([double]$job.sequence.frameRate) -Cues $aligned -TargetCues $targetCues -Voices $voiceClips -AnalysisDir $analysisDir -FfmpegPath $ffmpegPath -WhisperPath $whisperPath -CpuWhisperPath $cpuWhisperPath -ModelPath $modelPath -ModelName ([string]$engine.model) -Backend $recognitionBackend -BackendArguments $whisperArguments -Language $language -MaxCharacters $(if($algorithm -and $algorithm.PSObject.Properties['maxCaptionCharacters']){[int]$algorithm.maxCaptionCharacters}else{42})
$alignedSrt = Join-Path $job.outputFolder 'aligned.vi.srt'
foreach($block in $manualReview.Blocks){
    $owner=@($aligned|Where-Object Index -eq $block.cueIndex)[0]
    $block.captionCells=$owner.ManualCaptionCues
    $block.retainedReferenceCueIndices=@($owner.ManualCaptionCues.ReferenceCueIndices|Sort-Object -Unique)
    $block.pendingReferenceCueIndices=@($block.cueIndices|Where-Object {$block.retainedReferenceCueIndices -notcontains $_})
}
Write-SrtFile $valid $alignedSrt

$lowConfidence = @($aligned | Where-Object { $_.Confidence -lt $lowConfidenceThreshold -or $null -eq $_.Start })
$result = [ordered]@{
    ok = $true
    alignmentSchemaVersion = 4
    stage = 'alignment'
    alignedSrtPath = $alignedSrt
    cueCount = $aligned.Count
    recognizedWordCount = $recognized.Count
    language = $language
    voiceChapterCount = $voiceClips.Count
    usedWhisperCache = $useWhisperCache
    audioCache = Get-PvsAudioCacheStats
    recognitionBackend = $recognitionBackend
    recognitionBackendLabel = $recognitionBackendLabel
    backendReason = [string]$backend.reason
    backendInvocationCount = $backendInvocationCount
    gpuFallbackUsed = $gpuFallbackUsed
    gpuFallbackReason = $gpuFallbackReason
    lowConfidenceCueCount = $lowConfidence.Count
    wordTimingRecoveredCueCount = $wordTimingRecoveredCues.Count
    wordTimingRecoveredCues = $wordTimingRecoveredCues
    wordTimingRecoveryInvocationCount = $recoveryInvocationCount
    autoEditReferenceRecoveredCueIndices = $referenceRecovery.RecoveredCueIndices
    autoEditReferenceRecovery = $referenceRecovery.Recovery
    autoEditManualReviewBlocks = $manualReview.Blocks
    manualReviewStatus = $manualReview.Status
    referenceCueCount = $targetCues.Count
    sourceSubtitleGaps = @(for($i=0;$i+1 -lt $targetCues.Count;$i++){
        if($targetCues[$i+1].Start -gt $targetCues[$i].End){[pscustomobject]@{leftCue=[int]$targetCues[$i].Index;rightCue=[int]$targetCues[$i+1].Index;sourceStart=[double]$targetCues[$i].End;sourceEnd=[double]$targetCues[$i+1].Start}}
    })
    numericCaptionRefinedCues = $numericCaptions.Refined
    numericCaptionReviewCues = $numericCaptions.Review
    numericCaptionInvocationCount = $numericCaptionInvocationCount
    captionTimingMode = $captionTiming.Mode
    captionTimingBackend = $captionTiming.Backend
    captionTimingReviewCues = $captionTiming.ReviewCues
    captionTimingRefinedCues = $captionTiming.RefinedCues
    captionTimingReasons = $captionTiming.Reasons
    captionTimingInvocationCount = $captionTiming.InvocationCount
    captionTimingCacheHits = $captionTiming.CacheHits
    captionTimingRetryRanges = $captionTiming.RetryRanges
    captionTimingEstimatedRanges = $captionTiming.EstimatedRanges
    captionTimingAcousticBoundaryCount = $captionTiming.AcousticBoundaryCount
    captionBoundaryMode = $captionTiming.BoundaryMode
    acousticEditRefinedCues = $captionTiming.EditRefinedCues
    acousticEditTimingChanges = $captionTiming.EditChanges
    acousticEditReviewCues = $captionTiming.EditReviewCues
    acousticEditVoiceRanges = $captionTiming.EditVoiceRanges
    lowConfidenceCues = @($lowConfidence | Select-Object Index,Text,Chapter,Confidence)
    cues = $aligned
}
if($manualReview.Blocks.Count -and $captionTiming.AcousticWords.Count){
    $result.acousticEditBoundaryRevision='dtw-cue-quiet-partition-v2'
    $result.acousticEditWords=$captionTiming.AcousticWords
    $result.acousticEditReferenceCues=$targetCues
}
if($manualReview.Blocks.Count){
    $result.manualCaptionTimingRevision='raw-dtw-cell-overlay-v1'
    $result.manualCaptionRefinedCount=$captionTiming.ManualCaptionRefinedCount
    $result.manualCaptionRetryCount=$captionTiming.ManualCaptionRetryCount
    $result.manualCaptionRetryEstimatedRanges=$captionTiming.ManualEstimatedRanges
    $result.manualReferenceRecoveredCueIndices=$captionTiming.ManualReferenceRecoveredCues
}
if($null -ne $editedReference){
    $result.editedReferenceRanges=$editedReference.Ranges
    $result.omittedReferenceCueIndices=$editedReference.OmittedCueIndices
    $result.editedReferenceRecoveredCueIndices=$editedReference.RecoveredCueIndices
    if($editedReference.OmittedCueIndices.Count){$result.editedSourceMap=New-PvsEditedSourceMap -Edited $editedReference -Cues $targetCues -MainVideo $job.sequence.mainVideoClip -FrameRate ([double]$job.sequence.frameRate)}
}
$result | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $job.outputFolder 'alignment-result.json') -Encoding UTF8
Write-Host 'ALIGNMENT_READY'
} catch {
    if(Test-PvsRecognitionReviewError $_.Exception.Message){
        Write-PvsAutoEditPreservationResult ([pscustomobject]@{reason=$_.Exception.Message})
    }else{throw}
} finally {
    if (Test-Path -LiteralPath $analysisDir) { Remove-PvsSafeTree -Path $analysisDir -Root $safeTempRoot }
    if ((Test-Path -LiteralPath $safeTempRoot -PathType Container) -and @(Get-ChildItem -LiteralPath $safeTempRoot -Force).Count -eq 0) {
        Remove-Item -LiteralPath $safeTempRoot -Force -ErrorAction SilentlyContinue
    }
}
