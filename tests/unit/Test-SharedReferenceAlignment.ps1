$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$root=Resolve-Path (Join-Path $PSScriptRoot '..\..')
. "$root\extension\engine\lib\Srt.ps1"
. "$root\extension\engine\lib\Alignment.ps1"
. "$root\extension\engine\lib\CaptionOnly.ps1"
$oracle=Join-Path $root 'tests\helpers\ReferenceAlignmentBaseline.ps1'
function Get-BaselineAlignment {
    param($Cues,$Words,$Voices)
    & {param($Baseline,$Target,$Heard,$Sources);. $Baseline;Align-CuesToRecognizedWords $Target $Heard $Sources} $oracle $Cues $Words $Voices
}
$random=New-Object Random 271828
$voices=@([pscustomobject]@{start=10;end=90},[pscustomobject]@{start=100;end=180})
for($case=0;$case -lt 100;$case++){
    $reference=for($cue=0;$cue -lt (2+$random.Next(6));$cue++){
        $tokens=for($word=0;$word -lt (1+$random.Next(8));$word++){"token$($random.Next(12))"}
        [pscustomobject]@{Index=50+$cue;Text=($tokens -join ' ')+'.';Start=900+$cue*3;End=902+$cue*3}
    }
    $words=for($word=0;$word -lt (1+$random.Next(55));$word++){
        $chapter=if($word -ge 25){1}else{0};$local=$word%25
        [pscustomobject]@{Text="token$($random.Next(12))";Start=$local*0.31;End=($local+1)*0.31;Chapter=$chapter}
    }
    $before=$reference | ConvertTo-Json -Depth 4 -Compress
    $expected=@(Get-BaselineAlignment @($reference) @($words) $voices)
    $actual=@(Align-CuesToRecognizedWords @($reference) @($words) $voices)
    if(($expected | ConvertTo-Json -Depth 9 -Compress) -cne ($actual | ConvertTo-Json -Depth 9 -Compress)){throw "AUTO_EDIT_ALIGNMENT_PARITY_FAILED:case-$case"}
    if(($reference | ConvertTo-Json -Depth 4 -Compress) -cne $before){throw 'SHARED_CORE_MUTATED_SRT'}
}

$folder=Join-Path $env:TEMP ('PVS-SharedReference-'+[guid]::NewGuid().ToString('N'))
try{
    New-Item -ItemType Directory -Path $folder | Out-Null
    $path=Join-Path $folder 'recognition.json'
    $json=[pscustomobject]@{transcription=@(
        [pscustomobject]@{text='ALPHA beta';offsets=[pscustomobject]@{from=100;to=500};start=$null;end=$null;timestamps=$null},
        [pscustomobject]@{text='zero short spans';offsets=[pscustomobject]@{from=700;to=700};start=$null;end=$null;timestamps=$null},
        [pscustomobject]@{text='[_BEG_]';offsets=[pscustomobject]@{from=800;to=900};start=$null;end=$null;timestamps=$null},
        [pscustomobject]@{text='clip edge';offsets=[pscustomobject]@{from=950;to=1200};start=$null;end=$null;timestamps=$null}
    );segments=@()}
    $json | ConvertTo-Json -Depth 7 | Set-Content -LiteralPath $path -Encoding UTF8
    $expected=@(& {param($Baseline,$Path);. $Baseline;Convert-WhisperJsonToWords $Path 1} $oracle $path)
    $actual=@(Convert-WhisperJsonToWords $path 1)
    if(($expected | ConvertTo-Json -Depth 6 -Compress) -cne ($actual | ConvertTo-Json -Depth 6 -Compress)){throw 'AUTO_EDIT_RECOGNITION_PARITY_FAILED'}
    $subtitle=Convert-PvsSubtitleRecognition $json 1 1.0
    if(($subtitle.Words.Text -join '|') -ne 'alpha|beta|clip|edge' -or $subtitle.Words[-1].End -ne 1.0){throw 'SUBTITLE_RECOGNITION_POLICY_CHANGED'}
}finally{Remove-Item -LiteralPath $folder -Recurse -Force}

# The two workflows use exactly the same cue projection for a complete range.
$reference=for($cue=0;$cue -lt 5;$cue++){
    [pscustomobject]@{Index=$cue+1;Text=((0..7 | ForEach-Object {"word$($cue*8+$_)"}) -join ' ')+'.';Start=900+$cue*4;End=903+$cue*4}
}
$words=for($word=0;$word -lt 40;$word++){[pscustomobject]@{Text="word$word";Start=$word*0.3;End=($word+1)*0.3;Chapter=0}}
$source=@([pscustomobject]@{start=10;end=22})
$edit=@(Align-CuesToRecognizedWords $reference @($words) $source)
$subtitle=Select-PvsSubtitleReference $reference @($words) $source
if(($edit | ConvertTo-Json -Depth 9 -Compress) -cne ($subtitle.Cues | Select-Object Index,OriginalStart,OriginalEnd,Start,End,Text,Chapter,Confidence,WordTimings | ConvertTo-Json -Depth 9 -Compress)){throw 'EDIT_SUBTITLE_PROJECTION_DIFFERS'}

# Missing cue: both workflows recover it with the same bounded algorithm,
# retain the original reference text and apply the selected source offset once.
$missing=@($words | Where-Object {$_.Text -notmatch '^word(?:16|17|18|19|20|21|22|23)$'})
$script:retries=0
$recover={
    param($voice,$start,$end)
    $script:retries++
    if([Math]::Abs($start-14.8) -gt 0.000001 -or [Math]::Abs($end-17.2) -gt 0.000001){throw 'SHARED_RECOVERY_WINDOW_WRONG'}
    for($word=0;$word -lt 8;$word++){[pscustomobject]@{Text="word$($word+16)";Start=$word*0.3;End=($word+1)*0.3;Chapter=0}}
}
$editMissing=@(Align-CuesToRecognizedWords $reference $missing $source)
$editRecovered=@(Repair-PvsMissingCueWordTimings $editMissing $source $recover)
$subtitleRecovered=Select-PvsSubtitleReference $reference $missing $source -SkipUnverifiedCues -RecognizeReferenceWindow $recover
if($script:retries -ne 2 -or ($editRecovered -join ',') -ne '3' -or ($subtitleRecovered.RecoveredCueIndices -join ',') -ne '3' -or $subtitleRecovered.SkippedCueCount -ne 0){throw 'SHARED_RECOVERY_NOT_USED_BY_BOTH_WORKFLOWS'}
if(($editMissing[2] | ConvertTo-Json -Depth 9 -Compress) -cne ($subtitleRecovered.Cues[2] | Select-Object Index,OriginalStart,OriginalEnd,Start,End,Text,Chapter,Confidence,WordTimings,WordTimingRecovered | ConvertTo-Json -Depth 9 -Compress)){throw 'SHARED_RECOVERY_OUTPUT_DIFFERS'}
$wrong=Select-PvsSubtitleReference $reference $missing $source -SkipUnverifiedCues -RecognizeReferenceWindow {
    param($voice,$start,$end)
    for($word=0;$word -lt 8;$word++){[pscustomobject]@{Text='unrelated';Start=$word*0.3;End=($word+1)*0.3;Chapter=0}}
}
if($wrong.RecoveredCueIndices.Count -ne 0 -or $wrong.SkippedCueCount -ne 1){throw 'UNMATCHED_RECOVERY_REPLACED_SRT'}
$script:intervalCase=@(
    [pscustomobject]@{Index=1;OriginalStart=0;OriginalEnd=1;Text='left';Start=10;End=11;Chapter=0;Confidence=1;WordTimings=@()},
    [pscustomobject]@{Index=2;OriginalStart=1;OriginalEnd=3;Text='missing one';Start=$null;End=$null;Chapter=-1;Confidence=0;WordTimings=@()},
    [pscustomobject]@{Index=3;OriginalStart=3;OriginalEnd=6;Text='missing two';Start=$null;End=$null;Chapter=-1;Confidence=0;WordTimings=@()},
    [pscustomobject]@{Index=4;OriginalStart=6;OriginalEnd=7;Text='right';Start=20;End=21;Chapter=0;Confidence=1;WordTimings=@()}
)
foreach($frameRate in @(30,29.97)){
    $baselineCase=@($script:intervalCase | ForEach-Object {$_.PSObject.Copy()})
    $currentCase=@($script:intervalCase | ForEach-Object {$_.PSObject.Copy()})
    $oldCount=& {param($Baseline,$Cues,$Voices,$Fps);. $Baseline;Repair-PvsBaselineCueIntervals $Cues $Voices $Fps} $oracle $baselineCase $source $frameRate
    $newCount=Repair-PvsUnalignedCueIntervals $currentCase $source $frameRate
    if($oldCount -ne 2 -or $newCount -ne $oldCount -or ($baselineCase | ConvertTo-Json -Depth 6 -Compress) -cne ($currentCase | ConvertTo-Json -Depth 6 -Compress)){throw 'AUTO_EDIT_INTERPOLATION_PARITY_FAILED'}
}
# Subtitle does not inherit planner interpolation. Failed ASR leaves a report,
# with no original SRT text emitted at invented timestamps.
$incomplete=Complete-PvsSubtitleReference $wrong $missing $source {param($voice,$start,$end,$chapter)}
if($incomplete.EmptyRanges.Count -ne 1 -or @($incomplete.Cues | Where-Object {$_.PSObject.Properties['TimingRecovered']}).Count -ne 0 -or @($incomplete.Cues | Where-Object {$_.Text -eq $reference[2].Text}).Count -ne 0){throw 'SUBTITLE_USED_REJECTED_INTERPOLATION_POLICY'}
$subtitleRuntime=[IO.File]::ReadAllText((Join-Path $root 'extension\engine\run-captions.ps1'))+[IO.File]::ReadAllText((Join-Path $root 'extension\engine\lib\CaptionOnly.ps1'))
if($subtitleRuntime.Contains('Repair-PvsUnalignedCueIntervals') -or $subtitleRuntime.Contains('InterpolateUnresolved') -or $subtitleRuntime.Contains('InterpolatedCaptionTiming')){throw 'SUBTITLE_HAS_INTERPOLATION_ENTRYPOINT'}
Write-Host 'SHARED_REFERENCE_CORE_OK:100 Auto edit baseline cases;recognition policy parity;common cue projection;bounded recovery in both workflows;failed recovery stays eligible for ASR supplementation'
