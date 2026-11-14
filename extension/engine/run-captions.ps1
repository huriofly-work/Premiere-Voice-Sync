param([Parameter(Mandatory)][string]$JobPath)

$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
. "$PSScriptRoot\lib\Srt.ps1"
. "$PSScriptRoot\lib\Alignment.ps1"
. "$PSScriptRoot\lib\Native.ps1"
. "$PSScriptRoot\lib\Paths.ps1"
. "$PSScriptRoot\lib\CaptionOnly.ps1"
. "$PSScriptRoot\lib\SubtitleTiming.ps1"
. "$PSScriptRoot\lib\SubtitleEnergy.ps1"
. "$PSScriptRoot\lib\Security.ps1"
Assert-PvsRuntimeLock -EngineRoot $PSScriptRoot

$job=Get-Content -LiteralPath $JobPath -Raw -Encoding UTF8 | ConvertFrom-Json
Initialize-PvsAudioCache -RuntimeIdentity ((Get-PvsAudioFileDigest "$PSScriptRoot\runtime-lock.json")+'|'+(Get-PvsAudioFileDigest "$PSScriptRoot\cuda-lock.json"))
Assert-PvsSafePath -Path $job.outputFolder -Tree
if ([string]$job.workflow -ne 'caption-only' -or [int]$job.schemaVersion -ne 1) { throw 'SUBTITLE_JOB_SCHEMA_INVALID' }
$fps=[double]$job.frameRate
$maxCharacters=[int]$job.maxCaptionCharacters
$language=[string]$job.language
$sources=@($job.sources)
$hasReference=$job.PSObject.Properties['targetSrtPath'] -and -not [string]::IsNullOrWhiteSpace([string]$job.targetSrtPath)
if ($fps -le 0 -or $fps -gt 240 -or [double]::IsNaN($fps)) { throw 'SUBTITLE_FRAME_RATE_INVALID' }
if ($maxCharacters -lt 20 -or $maxCharacters -gt 80) { throw 'SUBTITLE_CHARACTER_LIMIT_INVALID' }
if ($language -notmatch '^(auto|[a-z]{2,3})$') { throw 'SUBTITLE_LANGUAGE_INVALID' }
if ($sources.Count -eq 0) { throw 'SUBTITLE_AUDIO_MISSING' }
$previousEnd=-1.0
foreach ($source in $sources) {
    if ([double]$source.start -lt 0 -or [double]$source.end -le [double]$source.start -or [double]$source.start -lt $previousEnd) { throw 'SUBTITLE_SOURCE_RANGES_INVALID' }
    $previousEnd=[double]$source.end
}
$runtimeRoot=Join-Path $PSScriptRoot 'runtime'
$engine=Get-Content -LiteralPath (Join-Path $runtimeRoot 'engine.json') -Raw -Encoding UTF8 | ConvertFrom-Json
function Resolve-CaptionEnginePath([string]$Value) {
    if ([IO.Path]::IsPathRooted($Value)) { return $Value }
    return Join-Path $runtimeRoot $Value
}
$ffmpeg=Resolve-CaptionEnginePath ([string]$engine.ffmpeg)
$cpuWhisper=Resolve-CaptionEnginePath ([string]$engine.whisper)
$model=Resolve-CaptionEnginePath ([string]$engine.modelPath)
$backend=(& "$PSScriptRoot\resolve-backend.ps1" | Out-String).Trim() | ConvertFrom-Json
if (-not $backend.ok) { throw 'SUBTITLE_BACKEND_UNAVAILABLE' }
$whisper=[string]$backend.whisperPath
$backendArguments=@([string[]]$backend.arguments)
$backendName=[string]$backend.backend; $backendLabel=[string]$backend.label
$fallbackReason=''
$edgeRetryCount=0
$captionTimingChapters=@{}
$captionTimingReasons=New-Object System.Collections.Generic.List[string]
$captionTimingRetryRanges=New-Object System.Collections.Generic.List[object]
$captionTimingEstimatedRanges=New-Object System.Collections.Generic.List[object]
$captionTimingAcousticBoundaries=0
$captionTimingWindowInvocationCount=0
$recognitionRejectedRanges=New-Object System.Collections.Generic.List[object]
function Invoke-CaptionRecognition {
    param([string]$Wav,[string]$OutBase,[string]$Prompt='',[bool]$SentenceSegments=$false)
    $run=Invoke-PvsCaptionDtwRecognition -WhisperPath $script:whisper -CpuWhisperPath $cpuWhisper -ModelPath $model -ModelName ([string]$engine.model) -WavPath $Wav -OutBase $OutBase -Language $script:detectedLanguage -Backend $script:backendName -BackendArguments $script:backendArguments -Prompt $Prompt -UseDtw (-not $SentenceSegments -and $script:detectedLanguage -notin @('zh','ja')) -SplitOnWord (-not $SentenceSegments)
    if($run.FallbackReason){$script:fallbackReason=$run.FallbackReason;$script:backendName='cpu';$script:backendLabel='CPU fallback';$script:whisper=$cpuWhisper;$script:backendArguments=@('--no-gpu')}
    return $run.Json
}
function Invoke-CaptionTailRecognition {
    param([double]$Cut,[double]$Length,[bool]$SentenceSegments=$false)
    $tailWav="$outBase-edge.wav";$tailBase="$outBase-edge"
    $run=Invoke-NativeCapture -FilePath $ffmpeg -Arguments @('-y','-hide_banner','-loglevel','error','-ss',$Cut.ToString('0.########',[Globalization.CultureInfo]::InvariantCulture),'-i',$wav,'-t',$Length.ToString('0.########',[Globalization.CultureInfo]::InvariantCulture),'-ar','16000','-ac','1','-c:a','pcm_s16le',$tailWav)
    if($run.ExitCode -ne 0){throw 'SUBTITLE_EDGE_AUDIO_FAILED'}
    Invoke-CaptionRecognition -Wav $tailWav -OutBase $tailBase -SentenceSegments $SentenceSegments
}
function Convert-CaptionRecognitionWithTiming {
    param($Json,[string]$TimingWav,[string]$TimingBase,[double]$TimingDuration,[int]$TimingChapter,[object[]]$TimingQuiet,[double]$TimingOffset=0.0,[int]$TimingReportChapter=-1)
    $converted=Convert-PvsAcousticRecognition -Json $Json -WavPath $TimingWav -OutBase $TimingBase -Duration $TimingDuration -Chapter $TimingChapter -Quiet $TimingQuiet -FfmpegPath $ffmpeg -GuardRecognitionText -Recognize {
        param([string]$windowWav,[string]$windowBase,[bool]$sentences)
        Invoke-CaptionRecognition -Wav $windowWav -OutBase $windowBase -SentenceSegments $sentences
    }
    $script:captionTimingWindowInvocationCount+=$converted.WindowInvocationCount
    if($TimingReportChapter -lt 0){$TimingReportChapter=$TimingChapter}
    foreach($range in $converted.RetryRanges){$script:captionTimingRetryRanges.Add([pscustomobject]@{sourceIndex=$TimingReportChapter;start=$TimingOffset+$range.start;end=$TimingOffset+$range.end;reason=$range.reason;quality=$range.quality})}
    foreach($word in $converted.Words){$word | Add-Member -NotePropertyName SubtitleTimingOrigin -NotePropertyValue $TimingBase -Force}
    foreach($range in $converted.EstimatedRanges){$script:captionTimingEstimatedRanges.Add([pscustomobject]@{sourceIndex=$TimingReportChapter;start=$TimingOffset+$range.start;end=$TimingOffset+$range.end;reason=$range.reason;origin=$TimingBase})}
    foreach($range in $converted.RejectedRanges){$script:recognitionRejectedRanges.Add([pscustomobject]@{sourceIndex=$TimingReportChapter;start=$TimingOffset+$range.start;end=$TimingOffset+$range.end;reason=$range.reason;origin=$TimingBase})}
    $script:captionTimingAcousticBoundaries+=$converted.AcousticBoundaryCount
    return $converted
}
function Invoke-CaptionReferenceSlice {
    param($Source,[double]$Start,[double]$End,[int]$Chapter,[ValidateSet('recovery','supplement')][string]$Kind)
    if($Kind -eq 'recovery'){$script:referenceRecoveryInvocationCount++;$number=$script:referenceRecoveryInvocationCount}
    else{$script:referenceSupplementInvocationCount++;$number=$script:referenceSupplementInvocationCount}
    $base=Join-Path $job.outputFolder ('reference-{0}-{1:000}' -f $Kind,$number)
    $cut=$Start-[double]$Source.start;$length=$End-$Start
    $run=Invoke-NativeCapture -FilePath $ffmpeg -Arguments @('-y','-hide_banner','-loglevel','error','-ss',$cut.ToString('0.########',[Globalization.CultureInfo]::InvariantCulture),'-i',([string]$Source.path),'-t',$length.ToString('0.########',[Globalization.CultureInfo]::InvariantCulture),'-ar','16000','-ac','1','-c:a','pcm_s16le',($base+'.wav'))
    if($run.ExitCode -ne 0){throw 'SUBTITLE_REFERENCE_WINDOW_AUDIO_FAILED'}
    if((Get-PvsPcmWaveDuration ($base+'.wav')) -lt $length-1.0/$fps-0.000001){throw 'SUBTITLE_REFERENCE_WINDOW_AUDIO_TRUNCATED'}
    $json=Invoke-CaptionRecognition -Wav ($base+'.wav') -OutBase $base -SentenceSegments $characterMode
    if($characterMode){return Convert-PvsSubtitleRecognition -Json $json -Chapter $Chapter -Duration $length -CharacterMode $true}
    $localQuiet=@(Get-PvsCaptionQuiet $ffmpeg ($base+'.wav'))
    return Convert-CaptionRecognitionWithTiming -Json $json -TimingWav ($base+'.wav') -TimingBase $base -TimingDuration $length -TimingChapter $Chapter -TimingQuiet $localQuiet -TimingOffset $Start -TimingReportChapter ([Array]::IndexOf($sources,$Source))
}

function Invoke-CaptionReferenceWindow {
    param($Source,[double]$Start,[double]$End,[int]$Chapter,[ValidateSet('recovery','supplement')][string]$Kind,$PrimaryRecognition=$null)
    if($characterMode -or $Kind -eq 'recovery'){return Invoke-CaptionReferenceSlice $Source $Start $End $Chapter $Kind}
    $words=New-Object System.Collections.Generic.List[object];$surfaces=New-Object System.Collections.Generic.List[object]
    $contextOnly=$true;$contextWindows=0
    foreach($window in @(Get-PvsSubtitleContextPlan $Start $End $Source.start $Source.end $allSilences.ToArray())){
        $contextWindows++
        $recognized=Invoke-CaptionReferenceSlice $Source $window.ReadStart $window.ReadEnd $Chapter $Kind
        $leftText='';$rightText=''
        if($null -ne $referenceSelection){
            $leftText=(@($referenceSelection.Cues | Where-Object {
                $edge=if($_.PSObject.Properties['CaptionEnd']){[double]$_.CaptionEnd}else{[double]$_.End}
                [int]$_.Chapter -eq $Chapter -and $edge -le $Start+0.000001 -and $edge -ge $window.ReadStart
            } | Sort-Object Start | Select-Object -Last 2 | ForEach-Object {$_.Text}) -join ' ')
            $rightText=(@($referenceSelection.Cues | Where-Object {
                $edge=if($_.PSObject.Properties['CaptionStart']){[double]$_.CaptionStart}else{[double]$_.Start}
                [int]$_.Chapter -eq $Chapter -and $edge -ge $End-0.000001 -and $edge -le $window.ReadEnd
            } | Sort-Object Start | Select-Object -First 2 | ForEach-Object {$_.Text}) -join ' ')
        }
        $inside=Get-PvsSubtitleContextInterior $recognized ($window.Start-$window.ReadStart) ($window.End-$window.ReadStart) $leftText $rightText
        if($inside.End -le $inside.Start){continue}
        $cropped=Select-PvsSubtitleRecognitionWindow $recognized $inside.Start $inside.End
        # Slightly different DTW edges can leave a breath between two proven
        # neighbors. No novel word remains; do not report their tail as missing.
        if(-not $cropped.Words.Count -and $inside.LeftMatched -and $inside.RightMatched){continue}
        $contextOnly=$false
        $base=Join-Path $job.outputFolder ('reference-supplement-{0:000}' -f $script:referenceSupplementInvocationCount)
        $supported=Select-PvsSupportedSubtitleRecognition $cropped (Get-PvsSubtitleEnergy ($base+'.wav')) $inside.Start
        $actualStart=$window.ReadStart+$inside.Start
        foreach($r in $supported.RejectedRanges){$script:recognitionRejectedRanges.Add([pscustomobject]@{sourceIndex=[Array]::IndexOf($sources,$Source);start=$actualStart+$r.start;end=$actualStart+$r.end;reason=$r.reason})}
        $offset=$actualStart-$Start;$first=$words.Count
        foreach($word in $supported.Words){$copy=$word.PSObject.Copy();$copy.Start+=$offset;$copy.End+=$offset;foreach($name in @('DtwFirst','DtwLast','DtwBoundaryStart')){if($copy.PSObject.Properties[$name] -and $null -ne $copy.$name){$copy.$name+=$offset}};$words.Add($copy)}
        foreach($surface in $supported.Surfaces){$copy=$surface.PSObject.Copy();$copy.Start+=$offset;$copy.End+=$offset;$copy.FirstWord+=$first;$copy.LastWord+=$first;$surfaces.Add($copy)}
    }
    $estimatedOnly=$words.Count -gt 0 -and @($words | Where-Object {-not $_.PSObject.Properties['SubtitleTimingQuality'] -or $_.SubtitleTimingQuality -ne 'estimated'}).Count -eq 0
    if((-not $words.Count -or $estimatedOnly) -and $null -ne $PrimaryRecognition -and $null -ne $referenceSelection){
        $unresolved=@($referenceSelection.UnverifiedRanges | Where-Object {$_.sourceIndex -eq $Chapter -and $_.start -lt $End -and $_.end -gt $Start -and @($_.cueIndices).Count})
        $left=@($referenceSelection.Cues | Where-Object {
            $edge=if($_.PSObject.Properties['CaptionEnd']){[double]$_.CaptionEnd}else{[double]$_.End}
            [int]$_.Chapter -eq $Chapter -and $edge -le $Start+0.000001
        } | Sort-Object Start | Select-Object -Last 1)
        if(-not $unresolved.Count -and $left.Count){
            $primaryTail=Select-PvsPrimarySubtitleTail $PrimaryRecognition $Source $Start $End $Chapter ([string]$left[0].Text)
            if($null -ne $primaryTail){
                $primaryTail | Add-Member -NotePropertyName PrimaryReuseReason -NotePropertyValue $(if($estimatedOnly){'estimated-context-rerecognition'}else{'empty-context-rerecognition'})
                return $primaryTail
            }
        }
    }
    [pscustomobject]@{Words=$words.ToArray();Surfaces=$surfaces.ToArray();CoveredByReferenceContext=($contextWindows -gt 0 -and $contextOnly)}
}
$allWords=New-Object System.Collections.Generic.List[object]
$allCues=New-Object System.Collections.Generic.List[object]
$allSilences=New-Object System.Collections.Generic.List[object]
$primaryRecognitions=@{}
$detectedLanguage=$language
$characterMode=$language -in @('zh','ja')
function Write-PvsCaptionPreservationResult {
    param([string]$Reason)
    $result=[ordered]@{ok=$true;workflow='caption-only';schemaVersion=1;sequenceId=$job.sequenceId;snapshot=$job.snapshot;preserveTimeline=$true;captionCueCount=0;manualReviewStatus='manual-review-pending';recognitionBackend=$backendName;recognitionBackendLabel=$backendLabel;backendReason=[string]$backend.reason;reviewReason=$Reason;recognitionReviewTasks=@(for($ch=0;$ch -lt $sources.Count;$ch++){[pscustomobject]@{chapter=$ch;start=[double]$sources[$ch].start;end=[double]$sources[$ch].end;status='manual-review-pending'}})}
    $result | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $job.outputFolder 'caption-result.json') -Encoding UTF8
    Write-Host 'CAPTIONS_READY:manual-review-pending;no-caption-import'
}
try {
for ($sourceIndex=0; $sourceIndex -lt $sources.Count; $sourceIndex++) {
    $source=$sources[$sourceIndex]
    $duration=[double]$source.end-[double]$source.start
    $inputPath=Resolve-PvsExistingPath -Path ([string]$source.path) -Purpose 'Exported timeline audio'
    $wav=Join-Path $job.outputFolder ("recognition-{0:000}.wav" -f $sourceIndex)
    $outBase=Join-Path $job.outputFolder ("recognition-{0:000}" -f $sourceIndex)
    $run=Invoke-NativeCapture -FilePath $ffmpeg -Arguments @('-y','-hide_banner','-loglevel','error','-i',$inputPath,'-t',$duration.ToString('0.########',[Globalization.CultureInfo]::InvariantCulture),'-ar','16000','-ac','1','-c:a','pcm_s16le',$wav)
    if ($run.ExitCode -ne 0) { throw "SUBTITLE_AUDIO_CONVERSION_FAILED:$($run.Output)" }
    $actualDuration=Get-PvsPcmWaveDuration -Path $wav
    if ($actualDuration -lt $duration-(1.0/$fps)-0.000001) { throw 'Audio xuat tu Premiere ngan hon vung dang chon. Hay thu xuat WAV cua sequence de kiem tra.' }
    $recognitionDuration=[Math]::Min($duration,$actualDuration)
    $json=Invoke-CaptionRecognition -Wav $wav -OutBase $outBase
    if ($detectedLanguage -eq 'auto' -and $json.PSObject.Properties['result'] -and $json.result.PSObject.Properties['language']) {
        $detectedLanguage=[string]$json.result.language
        $characterMode=$detectedLanguage -in @('zh','ja')
    }
    $silenceRun=Invoke-NativeCapture -FilePath $ffmpeg -Arguments @('-hide_banner','-i',$wav,'-af','silencedetect=noise=-35dB:d=0.12','-f','null','NUL')
    if ($silenceRun.ExitCode -ne 0) { throw "SUBTITLE_SILENCE_ANALYSIS_FAILED:$($silenceRun.Output)" }
    $pending=$null
    $sourceSilences=New-Object System.Collections.Generic.List[object]
    foreach ($line in ($silenceRun.Output -split '\r?\n')) {
        if ($line -match 'silence_start:\s*([0-9.]+)') { $pending=[double]::Parse($Matches[1],[Globalization.CultureInfo]::InvariantCulture) }
        if ($null -ne $pending -and $line -match 'silence_end:\s*([0-9.]+)') {
            $end=[double]::Parse($Matches[1],[Globalization.CultureInfo]::InvariantCulture)
            $allSilences.Add([pscustomobject]@{Start=[double]$source.start+$pending;End=[double]$source.start+$end;Duration=$end-$pending})
            $sourceSilences.Add([pscustomobject]@{Start=$pending;End=$end;Duration=$end-$pending})
            $pending=$null
        }
    }
    $primaryBeforeEdge=$json | ConvertTo-Json -Depth 100 | ConvertFrom-Json
    try {
        $edge=Repair-PvsSubtitleRecognitionEdge -Json $json -Duration $recognitionDuration -Silences $sourceSilences.ToArray() -RequireCompleteTail ([bool]$hasReference) -RecognizeTail {
            param([double]$cut,[double]$length)
            Invoke-CaptionTailRecognition $cut $length
        }
    }catch{
        if(-not (Test-PvsRecognitionReviewError $_.Exception.Message)){throw}
        # Keep useful primary captions and mark the unverified tail. Failed
        # retry hypotheses cannot replace primary text or fabricate SRT words.
        $json=$primaryBeforeEdge;$edge=[pscustomobject]@{Json=$json;Retried=$false}
        $recognitionRejectedRanges.Add([pscustomobject]@{sourceIndex=$sourceIndex;start=[double]$source.start;end=[double]$source.end;reason='recognition-edge-unverified';origin=$outBase})
    }
    if($edge.Retried){$edgeRetryCount++}
    $recognition=Convert-PvsSubtitleRecognition -Json $edge.Json -Chapter $sourceIndex -Duration $recognitionDuration -CharacterMode $characterMode
    if(-not $characterMode){
        $recognition=Convert-CaptionRecognitionWithTiming -Json $edge.Json -TimingWav $wav -TimingBase $outBase -TimingDuration $recognitionDuration -TimingChapter $sourceIndex -TimingQuiet $sourceSilences.ToArray() -TimingOffset ([double]$source.start)
        $captionTimingChapters[$sourceIndex]=$true
    } else {$captionTimingReasons.Add("Source $($sourceIndex+1): character-based language retains legacy timing.")}
    if($hasReference -and -not $characterMode){
        $primaryRecognitions[$sourceIndex]=[pscustomobject]@{
            Recognition=[pscustomobject]@{Words=@($recognition.Words | ForEach-Object {$_.PSObject.Copy()});Surfaces=@($recognition.Surfaces | ForEach-Object {$_.PSObject.Copy()})}
            Energy=(Get-PvsSubtitleEnergy $wav);SourceStart=[double]$source.start;SourceEnd=[double]$source.end;Chapter=$sourceIndex
        }
    }
    foreach($word in $recognition.Words){$allWords.Add($word)}
    foreach($cue in (New-PvsRecognizedSubtitleCues -Surfaces $recognition.Surfaces -Words $recognition.Words -Offset ([double]$source.start) -Chapter $sourceIndex -CharacterMode $characterMode)){$allCues.Add($cue)}
}
if ($allWords.Count -eq 0 -and -not $hasReference) { Write-PvsCaptionPreservationResult 'recognition-empty'; return }
$referenceSelection=$null
$referenceSupplement=$null
$referenceSupplementInvocationCount=0
$primarySupplementReuseRanges=New-Object System.Collections.Generic.List[object]
$referenceRecoveryInvocationCount=0
[object[]]$cues=@()
if ($hasReference) {
    $referencePath=Resolve-PvsExistingPath -Path ([string]$job.targetSrtPath) -Purpose 'Subtitle reference SRT'
    $referenceCues=@(Read-SrtFile $referencePath)
    $referenceSelection=Select-PvsSubtitleReference -Cues $referenceCues -Words $allWords.ToArray() -Sources $sources -CharacterMode $characterMode -Language $detectedLanguage -AllowAudioOutsideReference -SkipUnverifiedCues -AllowUnmatchedRanges -AllowEditedReference -RecognizeReferenceWindow {
        param($source,[double]$start,[double]$end)
        # The shared Auto edit recovery expects source-window-relative
        # words in chapter zero, then remaps them to the actual chapter.
        (Invoke-CaptionReferenceWindow $source $start $end 0 recovery).Words
    }
    $cues=@($referenceSelection.Cues)
    if($referenceSelection.PSObject.Properties['RecognitionWords']){
        $allWords.Clear();foreach($word in $referenceSelection.RecognitionWords){$allWords.Add($word)}
    }
} else {
    $cues=@($allCues.ToArray())
    # Source-local cue numbers repeat across disjoint exports. Diagnostics and
    # review markers require unique indices before the timing passes run.
    for($cueIndex=0;$cueIndex -lt $cues.Count;$cueIndex++){$cues[$cueIndex].Index=$cueIndex+1}
}
$numericCaptionInvocationCount=0
$dtwCaptionRetryCount=0
$dtwCaptionReviews=@()
$dtwCaptionRefined=@()
$estimatedWordSpans=@{}
foreach($word in $allWords){
    if($word.PSObject.Properties['SubtitleTimingQuality'] -and $word.SubtitleTimingQuality -eq 'estimated'){
        $offset=[double]$sources[[int]$word.Chapter].start
        $estimatedWordSpans[('{0}|{1:R}|{2:R}' -f [int]$word.Chapter,($offset+[double]$word.Start),($offset+[double]$word.End))]=$true
    }
}
$dtwCues=@($cues | Where-Object {$captionTimingChapters.ContainsKey([int]$_.Chapter) -and (Test-PvsSubtitleDtwCue $_ $estimatedWordSpans)})
if($dtwCues.Count){
    foreach($sourceIndex in $captionTimingChapters.Keys){Add-PvsCaptionTokenBoundaryTimings -Cues @($dtwCues | Where-Object {$_.Chapter -eq $sourceIndex}) -Words @($allWords | Where-Object {$_.Chapter -eq $sourceIndex}) -Offset ([double]$sources[$sourceIndex].start)}
    $retry=Repair-PvsDtwCaptionEdges -Cues $dtwCues -Quiet $allSilences.ToArray() -Duration ([double]$sources[-1].end) -Sources $sources -MaxCharacters $maxCharacters -RecognizeWindow {
        param([double]$start,[double]$end,[string]$text,[int]$chapter)
        $script:dtwCaptionRetryCount++
        $base=Join-Path $job.outputFolder ('dtw-caption-{0:000}' -f $script:dtwCaptionRetryCount)
        $cut=$start-[double]$sources[$chapter].start;$length=$end-$start
        $run=Invoke-NativeCapture $ffmpeg @('-y','-hide_banner','-loglevel','error','-ss',$cut.ToString('0.########',[Globalization.CultureInfo]::InvariantCulture),'-i',([string]$sources[$chapter].path),'-t',$length.ToString('0.########',[Globalization.CultureInfo]::InvariantCulture),'-ar','16000','-ac','1','-c:a','pcm_s16le',($base+'.wav'))
        if($run.ExitCode -ne 0){throw 'SUBTITLE_DTW_RETRY_AUDIO_FAILED'}
        $prompt=if($script:detectedLanguage -eq 'vi'){Get-PvsNumericCaptionPrompt $text}else{$text}
        $json=Invoke-CaptionRecognition -Wav ($base+'.wav') -OutBase $base -Prompt $prompt
        $localQuiet=@($allSilences | Where-Object {$_.Start -ge $start -and $_.End -le $end} | ForEach-Object {[pscustomobject]@{Start=$_.Start-$start;End=$_.End-$start;Duration=$_.Duration}})
        (Convert-CaptionRecognitionWithTiming -Json $json -TimingWav ($base+'.wav') -TimingBase $base -TimingDuration $length -TimingChapter 0 -TimingQuiet $localQuiet -TimingOffset $start -TimingReportChapter $chapter).Words
    }
    $dtwCaptionRefined=$retry.Refined
    $dtwCaptionReviews=@(Set-PvsDtwCaptionOverlay -Cues $dtwCues -CaptionCues $dtwCues -MaxCharacters $maxCharacters -Quiet $allSilences.ToArray())
}
if($hasReference){
    # Recover reference word edges BEFORE looking for uncovered speech. A
    # repaired last word can occupy what initially appeared to be a gap.
    $referenceSupplement=Complete-PvsSubtitleReference -Selection $referenceSelection -Words $allWords.ToArray() -Sources $sources -TestQuietWindow {
        param($source,[double]$start,[double]$end)
        Test-PvsSubtitleQuietGap $start $end $allSilences.ToArray()
    } -RecognizeWindow {
        param($source,[double]$start,[double]$end,[int]$chapter)
        $primary=if($primaryRecognitions.ContainsKey($chapter)){$primaryRecognitions[$chapter]}else{$null}
        $recognized=Invoke-CaptionReferenceWindow $source $start $end $chapter supplement -PrimaryRecognition $primary
        if($recognized.PSObject.Properties['CoveredByReferenceContext'] -and $recognized.CoveredByReferenceContext){return [pscustomobject]@{Cues=@();CoveredByReferenceContext=$true}}
        if($recognized.PSObject.Properties['PrimaryRecognitionReused'] -and $recognized.PrimaryRecognitionReused){
            $primarySupplementReuseRanges.Add([pscustomobject]@{sourceIndex=$chapter;start=$start+[double]$recognized.Words[0].Start;end=$start+[double]$recognized.Words[-1].End;reason=$recognized.PrimaryReuseReason;wordCount=$recognized.Words.Count})
        }
        New-PvsRecognizedSubtitleCues -Surfaces $recognized.Surfaces -Words $recognized.Words -Offset $start -Chapter $chapter -CharacterMode $characterMode
    }
    $cues=@($referenceSupplement.Cues)
    # Supplement insertion renumbers cues; diagnostics must use final indices.
    $finalReferenceIndices=@{}
    foreach($cue in $cues){if($cue.PSObject.Properties['ReferenceCueIndex']){$finalReferenceIndices[[int]$cue.ReferenceCueIndex]=[int]$cue.Index}}
    $dtwCaptionReviews=@($dtwCaptionReviews | Where-Object {$finalReferenceIndices.ContainsKey([int]$_)} | ForEach-Object {$finalReferenceIndices[[int]$_]})
    $dtwCaptionRefined=@($dtwCaptionRefined | Where-Object {$finalReferenceIndices.ContainsKey([int]$_)} | ForEach-Object {$finalReferenceIndices[[int]$_]})
}
$legacyCues=@($cues | Where-Object {-not $_.PSObject.Properties['CaptionTimingRevision']})
$numericCaptions=Repair-PvsNumericCaptionTimings -Cues $legacyCues -VoiceClips $sources -Language $detectedLanguage -RecognizeWindow {
    param($voice,[double]$start,[double]$end,[string]$Prompt)
    $script:numericCaptionInvocationCount++
    $base=Join-Path $job.outputFolder ('numeric-caption-{0:000}' -f $script:numericCaptionInvocationCount)
    $input=Resolve-PvsExistingPath -Path ([string]$voice.path) -Purpose 'Caption numeric timing audio'
    $cut=$start-[double]$voice.start;$length=$end-$start
    $run=Invoke-NativeCapture -FilePath $ffmpeg -Arguments @('-y','-hide_banner','-loglevel','error','-ss',$cut.ToString('0.########',[Globalization.CultureInfo]::InvariantCulture),'-i',$input,'-t',$length.ToString('0.########',[Globalization.CultureInfo]::InvariantCulture),'-ar','16000','-ac','1','-c:a','pcm_s16le',"$base.wav")
    if($run.ExitCode -ne 0){throw 'SUBTITLE_NUMERIC_AUDIO_FAILED'}
    $json=Invoke-CaptionRecognition -Wav "$base.wav" -OutBase $base -Prompt $Prompt
    $quiet=@(Get-PvsCaptionQuiet $ffmpeg ($base+'.wav'))
    (Convert-CaptionRecognitionWithTiming -Json $json -TimingWav ($base+'.wav') -TimingBase $base -TimingDuration $length -TimingChapter 0 -TimingQuiet $quiet -TimingOffset $start -TimingReportChapter ([Array]::IndexOf($sources,$voice))).Words
}
# Reconcile minor overlapping recognition edges without moving any timeline media.
$captionOverlapReviewCues=New-Object System.Collections.Generic.List[int]
for ($index=1; $index -lt $cues.Count; $index++) {
    if ([double]$cues[$index].Start -lt [double]$cues[$index-1].End) {
        $boundary=([double]$cues[$index].Start+[double]$cues[$index-1].End)/2.0
        $cues[$index-1].End=$boundary; $cues[$index].Start=$boundary
        $captionOverlapReviewCues.Add([int]$cues[$index-1].Index)
        $captionOverlapReviewCues.Add([int]$cues[$index].Index)
    }
}
$captions=@(New-PvsStandaloneCaptions -Cues $cues -Sources $sources -Silences $allSilences.ToArray() -MaxCharacters $maxCharacters -FrameRate $fps -CharacterMode $characterMode)
if ($captions.Count -eq 0) { Write-PvsCaptionPreservationResult 'recognition-no-usable-captions'; return }
$srtPath=Join-Path $job.outputFolder 'captions.srt'
Write-SrtFile -Cues $captions -Path $srtPath
$referenceReviews=@($cues | Where-Object {$_.PSObject.Properties['ReferenceReviewRequired'] -and $_.ReferenceReviewRequired} | ForEach-Object {[ordered]@{cueIndex=$(if($_.PSObject.Properties['ReferenceCueIndex']){$_.ReferenceCueIndex}else{$_.Index});start=$_.Start;end=$_.End;reason=$_.ReferenceReviewReason}})
$result=[ordered]@{ok=$true;workflow='caption-only';schemaVersion=1;sequenceId=$job.sequenceId;snapshot=$job.snapshot;captionSrtPath=$srtPath;captionCueCount=$captions.Count;language=$detectedLanguage;usedReferenceSrt=[bool]$hasReference;referenceReviewCues=$referenceReviews;recognitionBackend=$backendName;recognitionBackendLabel=$backendLabel;backendReason=[string]$backend.reason;gpuFallbackReason=$fallbackReason}
if($null -ne $referenceSelection -and $referenceSelection.PSObject.Properties['EditedReference']){
    $result.editedReferenceRanges=$referenceSelection.EditedReference.Ranges
    $result.omittedReferenceCueIndices=$referenceSelection.EditedReference.OmittedCueIndices
    $result.unresolvedReferenceCueIndices=@($referenceSelection.SkippedCues | ForEach-Object {$_.cueIndex})
}
$result.recognitionEdgeRetryCount=$edgeRetryCount
$result.primarySupplementReuseRanges=$primarySupplementReuseRanges.ToArray()
$referenceCoverage=@($cues | Where-Object {$_.PSObject.Properties['ReferenceCueIndex'] -and -not $_.PSObject.Properties['RecognitionSupplement']})
$result.recognitionRejectedRanges=@(Get-PvsUncoveredSubtitleRecognitionRanges $recognitionRejectedRanges.ToArray() $referenceCoverage $allSilences.ToArray() $fps)
$result.recognitionSuppressedRangeCount=$recognitionRejectedRanges.Count
$result.referenceInformationCues=@($cues | Where-Object {$_.PSObject.Properties['SubtitleReferenceFormatOnly'] -and $_.SubtitleReferenceFormatOnly} | ForEach-Object {[int]$_.Index})
$result.audioCache=Get-PvsAudioCacheStats
$result.numericCaptionRefinedCues=$numericCaptions.Refined
$result.numericCaptionReviewCues=$numericCaptions.Review
$result.referenceNumberReviewCues=@($cues | Where-Object {$_.PSObject.Properties['ReferenceNumberReviewRequired'] -and $_.ReferenceNumberReviewRequired} | ForEach-Object {[pscustomobject]@{cueIndex=$_.Index;start=$_.Start;end=$_.End;expected=$_.ReferenceNumberExpected;recognized=$_.ReferenceNumberRecognized}})
$result.reviewCueRanges=@($cues | Select-Object Index,ReferenceCueIndex,Start,End,Confidence,Text,RecognitionSupplement)
$result.reviewCaptionRanges=@($captions | Select-Object Index,SourceCueIndex,Start,End,Text)
$result.captionOverlapReviewCues=@($captionOverlapReviewCues | Sort-Object -Unique)
$result.numericCaptionInvocationCount=$numericCaptionInvocationCount
$result.captionTimingMode=if($dtwCues.Count){'dtw-word-boundary-v1'}else{'legacy'}
$result.captionTimingReasons=$captionTimingReasons.ToArray()
$result.captionTimingReviewCues=$dtwCaptionReviews
$result.captionTimingRefinedCues=$dtwCaptionRefined
$result.captionTimingRetryCount=$dtwCaptionRetryCount
$result.captionTimingRetryRanges=$captionTimingRetryRanges.ToArray()
$result.captionTimingEstimatedRanges=@(Get-PvsUsedSubtitleEstimatedRanges $cues $captionTimingEstimatedRanges.ToArray())
$result.captionTimingLegacyRanges=@(for($sourceIndex=0;$sourceIndex -lt $sources.Count;$sourceIndex++){
    if(-not $captionTimingChapters.ContainsKey($sourceIndex)){[pscustomobject]@{sourceIndex=$sourceIndex;start=[double]$sources[$sourceIndex].start;end=[double]$sources[$sourceIndex].end}}
})
$result.captionTimingAcousticBoundaryCount=$captionTimingAcousticBoundaries
$result.captionBoundaryMode='waveform-valley-v1'
if($null -ne $referenceSelection){
    $result.referenceScopeRanges=$referenceSelection.Ranges;$result.referenceCueCount=$referenceSelection.ReferenceCueCount;$result.referenceSelectedCueCount=$referenceSelection.SelectedCueCount;$result.referenceOutsideCueCount=$referenceSelection.OutsideCueCount;$result.referenceSupplementRanges=$referenceSupplement.SupplementRanges
    $emptyFinal=@($referenceSupplement.EmptyRanges | ForEach-Object {[pscustomobject]@{sourceIndex=$_.sourceIndex;start=$_.start;end=$_.end;reason='recognition-unverified'}})
    $result.referenceSupplementEmptyRanges=@(Get-PvsUncoveredSubtitleRecognitionRanges $emptyFinal $captions $allSilences.ToArray() $fps)
    $result.referenceQuietRanges=$referenceSupplement.QuietRanges;$result.referenceContextCoveredRanges=$referenceSupplement.ContextCoveredRanges;$result.referenceSupplementInvocationCount=$referenceSupplementInvocationCount
}
if($null -ne $referenceSelection){$result.referenceRecoveredCueIndices=$referenceSelection.RecoveredCueIndices;$result.referenceRecoveryInvocationCount=$referenceRecoveryInvocationCount;$result.referenceFallbackRanges=$referenceSelection.FallbackRanges}

$result | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $job.outputFolder 'caption-result.json') -Encoding UTF8
Write-Host 'CAPTIONS_READY'
} catch {
    if(Test-PvsRecognitionReviewError $_.Exception.Message){Write-PvsCaptionPreservationResult $_.Exception.Message}else{throw}
}
