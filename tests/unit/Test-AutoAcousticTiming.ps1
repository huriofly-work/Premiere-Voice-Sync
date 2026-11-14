$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$root=Resolve-Path (Join-Path $PSScriptRoot '..\..')
. "$root\extension\engine\lib\Native.ps1"
. "$root\extension\engine\lib\Paths.ps1"
. "$root\extension\engine\lib\Srt.ps1"
. "$root\extension\engine\lib\Alignment.ps1"
. "$root\extension\engine\lib\CaptionTiming.ps1"
. "$root\extension\engine\lib\DtwEditTrial.ps1"
$plannerAst=[Management.Automation.Language.Parser]::ParseFile("$root\extension\engine\build-sentence-plan.ps1",[ref]$null,[ref]$null)
$finder=$plannerAst.Find({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Find-SafeVoiceBoundary'},$true)
. ([scriptblock]::Create($finder.Extent.Text))
function Clone($Value){$Value | ConvertTo-Json -Depth 15 | ConvertFrom-Json}
function Make-Json([string[]]$Words,[bool]$Bad=$false,[bool]$Sentence=$false){
    if($Sentence){return [pscustomobject]@{transcription=@([pscustomobject]@{text=($Words -join ' ');offsets=[pscustomobject]@{from=100;to=3600};tokens=@()})}}
    $segments=@(for($i=0;$i -lt 4;$i++){
        $start=@(0.1,0.6,2.4,3.0)[$i];$end=@(0.6,1.4,3.0,3.6)[$i];$point=@(0.3,0.9,2.7,3.3)[$i]
        if($Bad -and $i -eq 1){$point=0.3}
        [pscustomobject]@{text=$Words[$i];offsets=[pscustomobject]@{from=$start*1000;to=$end*1000};tokens=@([pscustomobject]@{id=10;text=$Words[$i];t_dtw=$point*100})}
    })
    [pscustomobject]@{transcription=$segments}
}
$folder=Join-Path $env:TEMP ('PVS-AutoAcoustic-'+[guid]::NewGuid().ToString('N'))
try {
    New-Item -ItemType Directory -Path $folder | Out-Null
    foreach($number in @(1,2)){
        $writer=New-Object IO.BinaryWriter([IO.File]::Create((Join-Path $folder ('voice-{0:000}.wav' -f $number))))
        try {
            $writer.Write([Text.Encoding]::ASCII.GetBytes('RIFF'));$writer.Write([uint32]128036);$writer.Write([Text.Encoding]::ASCII.GetBytes('WAVEfmt '));$writer.Write([uint32]16)
            $writer.Write([uint16]1);$writer.Write([uint16]1);$writer.Write([uint32]16000);$writer.Write([uint32]32000);$writer.Write([uint16]2);$writer.Write([uint16]16);$writer.Write([Text.Encoding]::ASCII.GetBytes('data'));$writer.Write([uint32]128000)
            for($i=0;$i -lt 64000;$i++){$time=$i/16000.0;$amp=if($time -ge 1.4 -and $time -lt 2.4){0}else{10000};$writer.Write([int16]($amp*[Math]::Sin(2*[Math]::PI*250*$time)))}
        }finally{$writer.Dispose()}
    }
    function Invoke-NativeCapture {
        param($FilePath,$Arguments)
        if($script:failNative){throw 'FIXTURE_NATIVE_FAILURE'}
        if('-ss' -in $Arguments){$at=[Array]::IndexOf([string[]]$Arguments,'-i');Copy-Item -LiteralPath $Arguments[$at+1] -Destination $Arguments[-1] -Force;return [pscustomobject]@{ExitCode=0;Output=''}}
        if('-af' -notin $Arguments){throw 'UNEXPECTED_FIXTURE_NATIVE_CALL'}
        [pscustomobject]@{ExitCode=0;Output="silence_start: 1.4`nsilence_end: 2.4"}
    }
    function Invoke-PvsCaptionDtwRecognition {
        param($WhisperPath,$CpuWhisperPath,$ModelPath,$ModelName,$WavPath,$OutBase,$Language,$Backend,$BackendArguments,$UseDtw=$true,$SplitOnWord=$true,$Prompt)
        if($script:expectedLanguage -and $Language -cne $script:expectedLanguage){throw "AUTO_CAPTION_WRONG_LANGUAGE:$Language"}
        if($script:expectedLanguage -and $script:expectedLanguage -ne 'vi' -and $Prompt -match 'phẩy|phần trăm'){throw 'VIETNAMESE_PROMPT_IN_OTHER_LANGUAGE'}
        $second=$OutBase -match 'caption-001'
        $tokens=if($second){@('echo','foxtrot.','golf','hotel.')}else{@('alpha','bravo.','charlie','delta.')}
        $bad=$second -and $script:estimateSecond
        [pscustomobject]@{Json=(Make-Json $tokens $bad (-not $UseDtw));InvocationCount=1;Backend='cpu';FallbackReason=''}
    }
    $script:failNative=$false;$script:estimateSecond=$false;$script:expectedLanguage=''
    $target=@(for($i=0;$i -lt 4;$i++){[pscustomobject]@{Index=$i+1;Text=@('alpha bravo.','charlie delta.','echo foxtrot.','golf hotel.')[$i];Start=200+$i*2;End=202+$i*2}})
    foreach($speed in @(50.0,90.0,100.0,125.0,150.0)){
        $scale=100.0/$speed
        $voices=@([pscustomobject]@{path=(Join-Path $folder 'voice-001.wav');start=10.0;end=10+4*$scale;speedPercent=$speed},[pscustomobject]@{path=(Join-Path $folder 'voice-002.wav');start=100.0;end=100+4*$scale;speedPercent=$speed})
        $cues=@(for($i=0;$i -lt 4;$i++){$chapter=[int][Math]::Floor($i/2);$offset=$voices[$chapter].start;[pscustomobject]@{Index=$i+1;Text=$target[$i].Text;Start=$offset+($i%2)*2*$scale;End=$offset+(($i%2)+1)*2*$scale;OriginalStart=$target[$i].Start;OriginalEnd=$target[$i].End;Chapter=$chapter;Confidence=0.9;WordTimings=@()}})
        $textBefore=$cues.Text -join '|';$originalBefore=$cues | Select-Object OriginalStart,OriginalEnd | ConvertTo-Json -Compress
        $result=Prepare-PvsAutoCaptionTimings -Cues $cues -TargetCues $target -Voices $voices -AnalysisDir $folder -FfmpegPath 'C:\fixture\ffmpeg.exe' -WhisperPath 'C:\fixture\whisper.exe' -CpuWhisperPath 'C:\fixture\whisper.exe' -ModelPath 'fixture.bin' -ModelName small -Backend cpu -ApplyEditTiming
        if($result.EditRefinedCues.Count -ne 4 -or $result.EstimatedRanges.Count -or $result.ReviewCues.Count){throw "AUTO_ACOUSTIC_COVERAGE_FAILED:speed=$speed"}
        if($result.EditVoiceRanges.Count -ne 2 -or $result.EditVoiceRanges[0].start -ne 10 -or [Math]::Abs($result.EditVoiceRanges[0].end-(10+4*$scale)) -gt 0.000001){throw 'ACOUSTIC_EDGES_SHAVED_CHAPTER_VOICE_COVERAGE'}
        if([Math]::Abs($cues[0].Start-(10+0.3*$scale)) -gt 0.000001 -or [Math]::Abs($cues[0].End-(10+1.4*$scale)) -gt 0.000001 -or [Math]::Abs($cues[2].End-(100+1.4*$scale)) -gt 0.000001){throw 'SOURCE_SPEED_OFFSET_APPLIED_INCORRECTLY'}
        if(($cues.Text -join '|') -cne $textBefore -or ($cues | Select-Object OriginalStart,OriginalEnd | ConvertTo-Json -Compress) -cne $originalBefore){throw 'SOURCE_TEXT_OR_VIDEO_REFERENCE_CHANGED'}
        if(-not (Test-PvsTrialCueEvidence $cues[0] $voices[0])){throw 'VERIFIED_NEW_TIMING_NOT_AVAILABLE_TO_EDIT_CUTS'}
        foreach($fps in @(30.0,(30000.0/1001))){
            $parts=@(Split-PvsVoiceAlignedCaptionCue $cues[0] 42 $fps);if($parts.Count -ne 1 -or $parts[0].End -le $parts[0].Start){throw 'REFINED_TIMING_FRAME_GRID_FAILED'}
            $silence=@([pscustomobject]@{Start=10+1.4*$scale;End=10+2.4*$scale;Duration=$scale})
            $oldCut=Find-SafeVoiceBoundary (10+0.8*$scale) $silence 0.12 0.12 0.04 $fps
            $newCut=Find-SafeVoiceBoundary (($cues[0].End+$cues[1].Start)/2.0) $silence 0.12 0.12 0.04 $fps
            if($null -ne $oldCut -or $null -eq $newCut -or $newCut.CutSeconds -lt $silence[0].Start+0.04 -or $newCut.CutSeconds -gt $silence[0].End-0.04){throw 'IMPROVED_EDIT_EDGES_DID_NOT_ENABLE_CORRECT_CUT'}
        }
        $script:estimateSecond=$true
        $fallbackCues=@(for($i=0;$i -lt 4;$i++){$copy=$cues[$i].PSObject.Copy();foreach($name in @('CaptionTimingRevision','CaptionWordTimings','AcousticTimingQuality','EditTimingRevision')){$copy.PSObject.Properties.Remove($name)};$copy})
        $before=$fallbackCues[2].Start
        $fallback=Prepare-PvsAutoCaptionTimings -Cues $fallbackCues -TargetCues $target -Voices $voices -AnalysisDir $folder -FfmpegPath 'C:\fixture\ffmpeg.exe' -WhisperPath 'C:\fixture\whisper.exe' -CpuWhisperPath 'C:\fixture\whisper.exe' -ModelPath 'fixture.bin' -ModelName small -Backend cpu -ApplyEditTiming
        if($fallback.EstimatedRanges.Count -ne 1 -or $fallback.EditRefinedCues.Count -ne 2 -or $fallbackCues[2].Start -ne $before -or (Test-PvsTrialCueEvidence $fallbackCues[2] $voices[1])){throw 'ESTIMATED_CHAPTER_USED_TO_MOVE_EDIT_CUTS'}
        if([Math]::Abs($fallback.EstimatedRanges[0].start-100) -gt 0.000001 -or [Math]::Abs($fallback.EstimatedRanges[0].end-(100+4*$scale)) -gt 0.000001){throw 'ESTIMATED_RANGE_WRONG_TIMELINE_COORDINATES'}
        $script:estimateSecond=$false
    }
    foreach($voiceLanguage in @('en','auto','zh','vi')){
        $script:expectedLanguage=$voiceLanguage
        $languageResult=Prepare-PvsAutoCaptionTimings -Cues $cues -TargetCues $target -Voices $voices -AnalysisDir $folder -FfmpegPath 'C:\fixture\ffmpeg.exe' -WhisperPath 'C:\fixture\whisper.exe' -CpuWhisperPath 'C:\fixture\whisper.exe' -ModelPath 'fixture.bin' -ModelName small -Backend cpu -Language $voiceLanguage
        if($languageResult.InvocationCount -lt 2){throw 'LANGUAGE_TEST_DID_NOT_RECOGNIZE_BOTH_CHAPTERS'}
    }
    $script:expectedLanguage=''
    $script:failNative=$true;$caught=$false
    try{Prepare-PvsAutoCaptionTimings -Cues $cues -TargetCues $target -Voices $voices -AnalysisDir $folder -FfmpegPath 'C:\fixture\ffmpeg.exe' -WhisperPath 'C:\fixture\whisper.exe' -CpuWhisperPath 'C:\fixture\whisper.exe' -ModelPath 'fixture.bin' -ModelName small -Backend cpu | Out-Null}catch{if($_.Exception.Message -eq 'FIXTURE_NATIVE_FAILURE'){$caught=$true}else{throw}}
    if(-not $caught){throw 'AUTO_ACOUSTIC_NATIVE_FAILURE_SWALLOWED'}
    $conflict=Clone @($cues[0],$cues[1]);$conflict[0].Start=10;$conflict[0].End=11;$conflict[1].Start=11;$conflict[1].End=14
    $conflict[0].CaptionWordTimings=@([pscustomobject]@{Text='alpha';TargetWordIndex=0;Start=10.1;End=10.6;Chapter=0;Exact=$true},[pscustomobject]@{Text='bravo';TargetWordIndex=1;Start=10.6;End=11.4;Chapter=0;Exact=$true})
    $conflict[1] | Add-Member -NotePropertyName AcousticTimingQuality -NotePropertyValue 'estimated' -Force
    $changed=Set-PvsAcousticEditTimings $conflict @([pscustomobject]@{start=10;end=14})
    if($changed.RefinedCues.Count -or $changed.ReviewCues.Count -ne 1 -or $conflict[0].End -ne 11 -or (Test-PvsTrialCueEvidence $conflict[1] ([pscustomobject]@{start=10;end=14}))){throw 'CONFLICTING_OR_ESTIMATED_EVIDENCE_MOVED_UNVERIFIED_NEIGHBOR'}
    Write-Host 'AUTO_ACOUSTIC_TIMING_OK:shared-RMS;2-chapters;5-speeds;offset;frame-grid;updated-edit-edges;source-text-preserved;estimated-not-cut-evidence;fatal-propagation'
} finally {Remove-PvsSafeTree -Path $folder -Root $env:TEMP}
