$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$root=Resolve-Path (Join-Path $PSScriptRoot '..\..')
. "$root\extension\engine\lib\Native.ps1"
. "$root\extension\engine\lib\Srt.ps1"
. "$root\extension\engine\lib\Alignment.ps1"
. "$root\extension\engine\lib\CaptionOnly.ps1"
foreach($emptyInput in @($null,@())){
    $empty=Convert-PvsDtwSpeechWords -Words $emptyInput -Quiet @() -Duration 2
    if($empty.Words.Count -ne 0 -or $empty.MissingAnchors.Count -ne 0 -or $empty.MatchedPauses.Count -ne 0 -or -not $empty.NeedsPlaybackAcceptance){throw 'DTW_EMPTY_INPUT_NOT_PRESERVED'}
}
$punctuationOnly=[pscustomobject]@{transcription=@([pscustomobject]@{text='.';offsets=[pscustomobject]@{from=0;to=0};tokens=@([pscustomobject]@{id=13;text='.';t_dtw=0})})}
$punctuationBefore=$punctuationOnly | ConvertTo-Json -Depth 10 -Compress
$emptyRecognition=Convert-PvsDtwCaptionRecognition -Json $punctuationOnly -Quiet @() -Duration 2
if($emptyRecognition.Words.Count -ne 0 -or $emptyRecognition.Surfaces.Count -ne 0 -or ($punctuationOnly | ConvertTo-Json -Depth 10 -Compress) -cne $punctuationBefore){throw 'DTW_PUNCTUATION_ONLY_INVENTED_SPEECH'}
$json=[pscustomobject]@{transcription=@(
    [pscustomobject]@{text=' loat';offsets=[pscustomobject]@{from=0;to=0};tokens=@([pscustomobject]@{id=1;text=' lo';t_dtw=54},[pscustomobject]@{id=2;text='at';t_dtw=62})},
    [pscustomobject]@{text=' video';offsets=[pscustomobject]@{from=800;to=1200};tokens=@([pscustomobject]@{id=3;text=' video';t_dtw=102})},
    [pscustomobject]@{text='.';offsets=[pscustomobject]@{from=1200;to=1200};tokens=@([pscustomobject]@{id=13;text='.';t_dtw=140})}
)}
$recognized=Convert-PvsDtwCaptionRecognition -Json $json -Quiet @() -Duration 2.0
if($recognized.Words.Count -ne 2 -or $recognized.Surfaces.Count -ne 2 -or $recognized.Surfaces[-1].Text -ne 'video.' -or $recognized.Words[1].DtwBoundaryStart -ne 0.62 -or $recognized.Words[1].DtwFirst -ne 1.02){throw 'DTW_ZERO_DURATION_WORD_OR_TOKEN_INDEX_LOST'}
$pairs=@(@(129.3,129.44,129.9,130.08,129.442,129.768812),@(169.22,169.30,169.86,170.06,169.418,169.70825),@(228.42,228.50,228.98,229.22,228.604375,228.817125),@(439.1,439.44,439.92,440.26,439.536375,439.79125))
foreach($p in $pairs){
    $words=@([pscustomobject]@{Text='left';Start=$p[0]-0.5;End=$p[1]-0.4;DtwFirst=$p[0];DtwLast=$p[1]},[pscustomobject]@{Text='right';Start=$p[2]-0.5;End=$p[3]+0.2;DtwFirst=$p[2];DtwLast=$p[3]})
    $before=$words | ConvertTo-Json -Compress
    $result=Convert-PvsDtwSpeechWords $words @([pscustomobject]@{Start=$p[4];End=$p[5];Duration=$p[5]-$p[4]}) ($p[3]+1)
    if($result.Words[0].End -ne $p[4] -or $result.Words[1].Start -ne $p[5] -or ($words | ConvertTo-Json -Compress) -cne $before){throw 'DTW_TWO_SIDED_PAUSE_OR_INPUT_PRESERVATION_FAILED'}
}
$text='alpha bravo charlie delta echo foxtrot golf hotel india juliet'
$tokens=@(ConvertTo-NormalizedWords $text)
$timings=@(for($i=0;$i -lt $tokens.Count;$i++){[pscustomobject]@{TargetWordIndex=$i;Text=$tokens[$i];Start=$i*0.2;End=($i+1)*0.2;Chapter=0;Exact=$true;ContinuousTokenStart=[Math]::Max(0,($i-1)*0.2)}})
$cue=[pscustomobject]@{Index=1;Text=$text;Start=0.0;End=2.0;Chapter=0;Confidence=1.0;WordTimings=$timings;CaptionTimingRevision='dtw-word-boundary-v1'}
$before=$cue | ConvertTo-Json -Depth 6 -Compress
foreach($fps in @(30.0,(30000.0/1001))){
    $parts=@(Split-PvsVoiceAlignedCaptionCue -Cue $cue -MaxCharacters 42 -FrameRate $fps)
    if($parts.Count -ne 2 -or -not $parts[1].TokenBoundaryApplied -or $parts[1].StartFrame -ne [int][Math]::Ceiling(1.0*$fps-0.0000001) -or $parts[0].EndFrame -ne $parts[1].StartFrame){throw 'DTW_SHARED_SPLITTER_NOT_USED'}
    $captions=@(New-PvsStandaloneCaptions @($cue) @([pscustomobject]@{start=0.0;end=2.0}) @() 42 $fps)
    if(($captions.Text -join ' ') -cne $text -or $captions[0].End -ne $captions[1].Start -or ($cue | ConvertTo-Json -Depth 6 -Compress) -cne $before){throw 'DTW_CAPTION_TEXT_TIMING_OR_INPUT_CHANGED'}
}
$variable=$cue.PSObject.Copy();$variable.WordTimings=@($timings | ForEach-Object {$t=$_.PSObject.Copy();$t.ContinuousTokenStart=$t.Start-0.05;$t})
$parts=@(Split-PvsVoiceAlignedCaptionCue $variable 42 30)
if($parts[1].StartFrame -ne 35){throw 'DTW_USED_FIXED_FRAME_OFFSET'}
$unsafe=$cue.PSObject.Copy();$unsafe.WordTimings=@($timings | ForEach-Object {$t=$_.PSObject.Copy();$t.ContinuousTokenStart=0.0;$t})
$parts=@(Split-PvsVoiceAlignedCaptionCue $unsafe 42 30)
if($parts[1].TokenBoundaryApplied -or $parts[1].StartFrame -ne 36){throw 'DTW_UNSAFE_BOUNDARY_GUESSED'}
$pauseTimings=@(for($i=0;$i -lt 6;$i++){$start=if($i -lt 3){$i*0.2}else{1.6+($i-3)*0.2};[pscustomobject]@{Text=@('alpha','bravo','charlie','delta','echo','foxtrot')[$i];TargetWordIndex=$i;Start=$start;End=$start+0.2;Chapter=0;Exact=$true;ContinuousTokenStart=[Math]::Max(0,$start-0.2)}})
$pauseCue=[pscustomobject]@{Index=2;Text='alpha bravo charlie, delta echo foxtrot.';Start=0.0;End=2.2;Chapter=0;Confidence=1.0;WordTimings=$pauseTimings;CaptionTimingRevision='dtw-word-boundary-v1'}
$captions=@(New-PvsStandaloneCaptions @($pauseCue) @([pscustomobject]@{start=0.0;end=2.2}) @([pscustomobject]@{Start=0.6;End=1.6;Duration=1.0}) 42 30)
if([Math]::Round($captions[0].End*30) -ne 18 -or [Math]::Round($captions[1].Start*30) -ne 48){throw 'DTW_PAUSE_EDGES_NOT_KEPT'}
$punct=$pauseCue.PSObject.Copy();$punct.WordTimings=@(for($i=0;$i -lt 6;$i++){[pscustomobject]@{Text=$pauseTimings[$i].Text;TargetWordIndex=$i;Start=$i*0.2;End=($i+1)*0.2;Chapter=0;Exact=$true;ContinuousTokenStart=[Math]::Max(0,($i-1)*0.2)}})
$parts=@(Split-PvsVoiceAlignedCaptionCue $punct 42 30)
if($parts[1].TokenBoundaryApplied -or $parts[1].StartBoundaryKind -ne 'punctuation'){throw 'DTW_CHANGED_PUNCTUATION_BOUNDARY'}
$legacy=$cue.PSObject.Copy();$legacy.PSObject.Properties.Remove('CaptionTimingRevision');$legacy.Start=0.1;$legacy.End=1.9
$editBefore=$legacy | Select-Object Start,End,WordTimings,Chapter,Confidence | ConvertTo-Json -Depth 6 -Compress
Set-PvsDtwCaptionOverlay @($legacy) @($cue) | Out-Null
if(($legacy | Select-Object Start,End,WordTimings,Chapter,Confidence | ConvertTo-Json -Depth 6 -Compress) -cne $editBefore -or $legacy.CaptionTimingRevision -ne 'dtw-word-boundary-v1'){throw 'DTW_OVERLAY_CHANGED_EDIT_ALIGNMENT'}
$missing=$cue.PSObject.Copy();$missing.WordTimings=@($timings | Where-Object {$_.TargetWordIndex -ne 0})
$retry=Repair-PvsDtwCaptionEdges -Cues @($missing) -Quiet @() -Duration 2 -RecognizeWindow {throw 'CAPTION_DTW_ANCHOR_SPAN_INVALID:word-1'}
if($retry.Refined.Count -ne 0 -or $retry.Unverified.Count -ne 1 -or $missing.PSObject.Properties['CaptionWordTimings']){throw 'DTW_AMBIGUOUS_RETRY_NOT_REPORTED'}
$folder=Join-Path $env:TEMP ('PVS-DtwNativeMock-'+[guid]::NewGuid().ToString('N'))
try {
    New-Item -ItemType Directory -Path $folder | Out-Null
    $script:captured=New-Object System.Collections.Generic.List[object]
    function Invoke-PvsWhisperCapture {
        param($FilePath,$Arguments,$WorkingDirectory)
        $script:captured.Add([pscustomobject]@{Path=$FilePath;Arguments=$Arguments})
        if($script:captured.Count -eq 1){return [pscustomobject]@{ExitCode=1;Output='CUDA fixture failure'}}
        $at=[Array]::IndexOf([string[]]$Arguments,'-of');$json | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath ($Arguments[$at+1]+'.json') -Encoding UTF8
        [pscustomobject]@{ExitCode=0;Output='CPU fixture'}
    }
    $run=Invoke-PvsCaptionDtwRecognition -WhisperPath 'C:\fixture\cuda.exe' -CpuWhisperPath 'C:\fixture\cpu.exe' -ModelPath 'fixture.bin' -ModelName small -WavPath 'fixture.wav' -OutBase (Join-Path $folder 'result') -Language vi -Backend cuda
    if($run.Backend -ne 'cpu' -or -not $run.FallbackReason -or $script:captured.Count -ne 2){throw 'DTW_GPU_FALLBACK_OR_REASON_LOST'}
    foreach($call in $script:captured){if('-dtw' -notin $call.Arguments -or '-nfa' -notin $call.Arguments){throw 'DTW_ARGUMENTS_LOST_ON_FALLBACK'}}
    $run=Invoke-PvsCaptionDtwRecognition -WhisperPath 'C:\fixture\cpu.exe' -CpuWhisperPath 'C:\fixture\cpu.exe' -ModelPath 'fixture.bin' -ModelName small -WavPath 'fixture.wav' -OutBase (Join-Path $folder 'sentences') -Language vi -Backend cpu -UseDtw $false -SplitOnWord $false
    $sentenceCall=$script:captured[$script:captured.Count-1]
    foreach($flag in @('-ml','-sow','-dtw','-nfa','--prompt')){if($flag -in $sentenceCall.Arguments){throw "SUPPLEMENT_SENTENCE_ARGUMENT_INVALID:$flag"}}
    if('-ojf' -notin $sentenceCall.Arguments -or '-np' -notin $sentenceCall.Arguments){throw 'SUPPLEMENT_OUTPUT_ARGUMENTS_MISSING'}
} finally {Remove-PvsSafeTree -Path $folder -Root $env:TEMP}
Write-Host 'CAPTION_DTW_TIMING_OK:zero-duration-words;token-index;four-pauses;shared-splitter;variable-not-fixed;frame-grid;independent-padding;punctuation-protected;edit-input-unchanged;GPU-CPU-fallback'
