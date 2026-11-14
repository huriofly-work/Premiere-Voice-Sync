$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$root=Resolve-Path (Join-Path $PSScriptRoot '..\..')
. "$root\extension\engine\lib\Srt.ps1"
. "$root\extension\engine\lib\Alignment.ps1"
. "$root\extension\engine\lib\CaptionOnly.ps1"

$json=[pscustomobject]@{transcription=@(
    [pscustomobject]@{text='Xin';offsets=[pscustomobject]@{from=100;to=300}},
    [pscustomobject]@{text='chào,';offsets=[pscustomobject]@{from=300;to=500}},
    [pscustomobject]@{text='bình';offsets=[pscustomobject]@{from=600;to=800}},
    [pscustomobject]@{text='thường';offsets=[pscustomobject]@{from=800;to=1100}},
    [pscustomobject]@{text='.';offsets=[pscustomobject]@{from=1100;to=1100}},
    [pscustomobject]@{text='[_BEG_]';offsets=[pscustomobject]@{from=1100;to=1100}}
)}
$recognition=Convert-PvsSubtitleRecognition -Json $json -Chapter 0 -Duration 2
if ($recognition.Words.Count -ne 4) { throw "ASR_WORD_PARSING_FAILED:$($recognition.Words.Count):$($recognition.Words.Text -join '|')" }
$cues=@(New-PvsRecognizedSubtitleCues -Surfaces $recognition.Surfaces -Words $recognition.Words -Offset 10 -Chapter 0)
if ($cues.Count -ne 1 -or $cues[0].Text -ne 'Xin chào, bình thường.') { throw 'ASR_TEXT_PUNCTUATION_LOST' }
$sources=@([pscustomobject]@{start=10.0;end=12.0},[pscustomobject]@{start=20.0;end=22.0})
$second=$cues[0].PSObject.Copy(); $second.Index=2; $second.Start+=10; $second.End+=10; $second.Chapter=1
$second.WordTimings=@($cues[0].WordTimings | ForEach-Object { $copy=$_.PSObject.Copy();$copy.Start+=10;$copy.End+=10;$copy.Chapter=1;$copy })
$captions=@(New-PvsStandaloneCaptions -Cues @($cues[0],$second) -Sources $sources -Silences @() -MaxCharacters 20 -FrameRate 30)
if (($captions.Text -join ' ') -ne 'Xin chào, bình thường. Xin chào, bình thường.') { throw 'SUBTITLE_TEXT_COVERAGE_FAILED' }
if ($captions.Count -ne 4) { throw 'SUBTITLE_PUNCTUATION_SPLIT_FAILED' }
if(($captions.SourceCueIndex -join ',') -ne '1,1,2,2'){throw 'SUBTITLE_ANALYSIS_TO_OUTPUT_CAPTION_MAP_LOST'}
if ($captions[0].Start -lt 10 -or $captions[1].End -gt 12 -or $captions[2].Start -lt 20 -or $captions[3].End -gt 22) { throw 'SUBTITLE_SELECTED_RANGE_LEAK' }
# S6 decision: captions keep their aligned edges (frames 303 and 333), no 5-frame padding.
if ([Math]::Abs($captions[0].Start*30-303) -gt 0.001 -or [Math]::Abs($captions[1].End*30-333) -gt 0.001) { throw 'SUBTITLE_EDGE_PADDING_APPLIED' }
$sampleCaptions=@(New-PvsStandaloneCaptions -Cues @($cues[0]) -Sources @([pscustomobject]@{start=10.01;end=11.0999}) -Silences @() -MaxCharacters 20 -FrameRate 30)
foreach($caption in $sampleCaptions){if($caption.Start -lt 10.01 -or $caption.End -gt 11.0999 -or [Math]::Abs($caption.Start*30-[Math]::Round($caption.Start*30)) -gt 0.0001 -or [Math]::Abs($caption.End*30-[Math]::Round($caption.End*30)) -gt 0.0001){throw 'SAMPLE_BASED_EDGE_FRAME_LEAK'}}
$reference=@([pscustomobject]@{Text='Xin chào, bình thường.';Start=100;End=200})
$aligned=@(Align-PvsSubtitleReference -Cues $reference -Words $recognition.Words -Sources @($sources[0]))
if ($aligned[0].Text -ne $reference[0].Text -or [Math]::Abs($aligned[0].Start-10.1) -gt 0.000001) { throw 'REFERENCE_SRT_USED_OLD_TIMESTAMP' }
$failed=$false
try { Align-PvsSubtitleReference -Cues @([pscustomobject]@{Text='Nội dung hoàn toàn khác với lời nói.'}) -Words $recognition.Words -Sources @($sources[0]) | Out-Null } catch { $failed=$true }
if (-not $failed) { throw 'REFERENCE_MISMATCH_ACCEPTED' }

$cjkText='这是中文测试。字幕需要保留标点。'
$cjkWords=@(Get-PvsSubtitleLexicalWords -Text $cjkText -CharacterMode $true)
$timings=for ($index=0;$index -lt $cjkWords.Count;$index++) { [pscustomobject]@{Text=$cjkWords[$index];TargetWordIndex=$index;Start=$index*0.3;End=($index+1)*0.3;Chapter=0;Exact=$true} }
$cjkCue=[pscustomobject]@{Text=$cjkText;Start=0;End=$cjkWords.Count*0.3;WordTimings=@($timings);Chapter=0}
$cjkParts=@(Split-PvsCharacterCaptionCue -Cue $cjkCue -MaxCharacters 8 -FrameRate 30)
if (($cjkParts.Text -join '') -ne $cjkText -or @($cjkParts | Where-Object {$_.Text.Length -gt 8}).Count) { throw 'CJK_TEXT_OR_LIMIT_FAILED' }
if ((@(Get-PvsSubtitleLexicalWords -Text 'OpenAI公司' -CharacterMode $true) -join '|') -ne 'openai|公|司') { throw 'MIXED_CJK_LATIN_WORDS_FAILED' }

foreach ($file in @('caption-input.test.js','caption-input-host.test.js','caption-recovery-ui.test.js')) {
    & node (Join-Path $root "tests\unit\$file")
    if ($LASTEXITCODE -ne 0) { throw "CAPTION_INPUT_TEST_FAILED:$file" }
}
& node (Join-Path $root 'tests\unit\caption-only-host.test.js')
if ($LASTEXITCODE -ne 0) { throw 'CAPTION_ONLY_HOST_TEST_FAILED' }
& node (Join-Path $root 'tests\unit\caption-audio-ui.test.js')
if ($LASTEXITCODE -ne 0) { throw 'CAPTION_AUDIO_UI_TEST_FAILED' }
& node (Join-Path $root 'tests\unit\caption-export-ui.test.js')
if ($LASTEXITCODE -ne 0) { throw 'CAPTION_EXPORT_UI_TEST_FAILED' }
Write-Host 'CAPTION_ONLY_OK'
