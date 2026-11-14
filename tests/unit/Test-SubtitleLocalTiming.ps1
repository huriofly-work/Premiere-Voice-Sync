$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$root=Resolve-Path (Join-Path $PSScriptRoot '..\..')
. "$root\extension\engine\lib\Srt.ps1"
. "$root\extension\engine\lib\Alignment.ps1"
. "$root\extension\engine\lib\CaptionOnly.ps1"
. "$root\extension\engine\lib\SubtitleTiming.ps1"
. "$root\extension\engine\lib\SubtitleEnergy.ps1"
function Segment([string]$Text,[double]$Start,[double]$End,[double]$Anchor){
    [pscustomobject]@{text=$Text;offsets=[pscustomobject]@{from=$Start*1000;to=$End*1000};tokens=@([pscustomobject]@{id=1;text=$Text;t_dtw=$Anchor*100})}
}
$json=[pscustomobject]@{transcription=@((Segment 'alpha' 1 2 1.2),(Segment 'bravo' 20 21 20.2),(Segment 'charlie' 40 41 40.2),(Segment 'delta' 41 42 40.2),(Segment 'echo' 50 51 50.2),(Segment '.' 51 51 50.5))}
$before=$json | ConvertTo-Json -Depth 8 -Compress
$quiet=@([pscustomobject]@{Start=23.8;End=24.2;Duration=0.4},[pscustomobject]@{Start=47.8;End=48.2;Duration=0.4})
$script:calls=New-Object System.Collections.Generic.List[object]
$r=Convert-PvsSubtitleDtwWindows $json $quiet @() 60 0 {
    param($start,$end,$sentences)
    $script:calls.Add([pscustomobject]@{start=$start;end=$end;sentences=$sentences})
    [pscustomobject]@{transcription=@((Segment 'charlie' 16 17 16.2),(Segment 'delta' 17 18 17.2))}
}
if($script:calls.Count -ne 1 -or $script:calls[0].start -ne 24 -or $script:calls[0].end -ne 48 -or $script:calls[0].sentences){throw 'LOCAL_DTW_RETRY_SCOPE_INVALID'}
if($r.Words.Count -ne 5 -or $r.Words[0].Start -ne 1.2 -or $r.Words[-1].Start -ne 50.2 -or $r.Words[2].Start -ne 40.2 -or $r.Surfaces[-1].Text -ne 'echo.' -or $r.EstimatedRanges.Count -ne 0){throw 'GOOD_DTW_OR_LOCAL_RETRY_WORDS_LOST'}
if(($json | ConvertTo-Json -Depth 8 -Compress) -cne $before){throw 'INITIAL_RECOGNITION_MUTATED'}
$script:tries=0
$estimated=Convert-PvsSubtitleDtwWindows $json $quiet @() 60 0 {
    param($start,$end,$sentences)
    $script:tries++
    if(-not $sentences){return [pscustomobject]@{transcription=@((Segment 'charlie' 16 17 16.2),(Segment 'delta' 17 18 16.2))}}
    [pscustomobject]@{transcription=@((Segment 'charlie delta' 16 18 -0.01))}
}
if($script:tries -ne 2 -or $estimated.EstimatedRanges.Count -ne 1 -or $estimated.EstimatedRanges[0].start -ne 24 -or $estimated.EstimatedRanges[0].end -ne 48 -or $estimated.Words[0].SubtitleTimingQuality -ne 'dtw' -or $estimated.Words[2].SubtitleTimingQuality -ne 'estimated' -or $estimated.Words[-1].SubtitleTimingQuality -ne 'dtw'){throw 'ESTIMATED_TIMING_ESCAPED_LOCAL_RANGE_OR_PROVENANCE_LOST'}
$failed=$false
try{Convert-PvsSubtitleDtwWindows $json $quiet @() 60 0 {throw 'NATIVE_FAILURE'} | Out-Null}catch{if($_.Exception.Message -eq 'NATIVE_FAILURE'){$failed=$true}else{throw}}
if(-not $failed){throw 'NATIVE_FAILURE_SWALLOWED_AS_TIMING_FALLBACK'}
$words=@(
    [pscustomobject]@{Text='before';Chapter=0;Start=1.0;End=1.8;DtwFirst=1.0;DtwLast=1.2;DtwBoundaryStart=0.8;SubtitleTimingQuality='dtw'},
    [pscustomobject]@{Text='13';Chapter=0;Start=1.8;End=2.2;DtwFirst=1.8;DtwLast=1.8;DtwBoundaryStart=1.2;SubtitleTimingQuality='dtw'}
)
$count=Set-PvsSubtitleWordBoundaries $words @([pscustomobject]@{Start=1.3;End=1.4;Duration=0.1})
if($count -ne 1 -or [Math]::Abs($words[0].End-1.35) -gt 0.000001 -or $words[0].End -ne $words[1].Start -or $words[1].DtwBoundaryStart -ne $words[1].Start){throw 'NUMERIC_BOUNDARY_DID_NOT_USE_PREVIOUS_WORD_AND_MEASURED_DIP'}
$noDip=@($words | ForEach-Object {$_.PSObject.Copy()})
$copyBefore=$noDip | ConvertTo-Json -Compress
if((Set-PvsSubtitleWordBoundaries $noDip @([pscustomobject]@{Start=0.2;End=0.3;Duration=0.1})) -ne 0 -or ($noDip | ConvertTo-Json -Compress) -cne $copyBefore){throw 'UNRELATED_QUIET_MOVED_WORD_BOUNDARY'}
$ambiguous=@([pscustomobject]@{Start=1.3;End=1.4;Duration=0.1},[pscustomobject]@{Start=1.5;End=1.6;Duration=0.1})
if((Set-PvsSubtitleWordBoundaries $noDip $ambiguous) -ne 0){throw 'AMBIGUOUS_MULTIPLE_DIPS_GUESSED'}
$cue=[pscustomobject]@{WordTimings=@([pscustomobject]@{Chapter=0;Start=40.0;End=41.0})}
if((Test-PvsSubtitleDtwCue $cue @{'0|40|41'=$true}) -or -not (Test-PvsSubtitleDtwCue $cue @{})){throw 'ESTIMATED_TIMING_PROMOTED_TO_DTW'}
$temp=Join-Path $env:TEMP ('PVS-SubtitleEnergy-'+[guid]::NewGuid().ToString('N'))
try {
    New-Item -ItemType Directory -Path $temp | Out-Null
    $wav=Join-Path $temp 'dips.wav'
    $writer=New-Object IO.BinaryWriter([IO.File]::Create($wav))
    try {
        $writer.Write([Text.Encoding]::ASCII.GetBytes('RIFF'));$writer.Write([uint32](36+64000));$writer.Write([Text.Encoding]::ASCII.GetBytes('WAVEfmt '));$writer.Write([uint32]16)
        $writer.Write([uint16]1);$writer.Write([uint16]1);$writer.Write([uint32]16000);$writer.Write([uint32]32000);$writer.Write([uint16]2);$writer.Write([uint16]16)
        $writer.Write([Text.Encoding]::ASCII.GetBytes('data'));$writer.Write([uint32]64000)
        for($i=0;$i -lt 32000;$i++){
            $time=$i/16000.0
            # First dip remains above the fixed -35 dB detector threshold.
            $amplitude=if($time -ge 0.9 -and $time -lt 0.94){900}elseif($time -ge 1.1 -and $time -lt 1.14){40}else{12000}
            $writer.Write([int16]($amplitude*[Math]::Sin(2*[Math]::PI*200*$time)))
        }
    } finally {$writer.Dispose()}
    $energy=Get-PvsSubtitleEnergy $wav
    $boundary=$energy.FindBoundary(0.92,0.82,1.02)
    if([double]::IsNaN($boundary) -or $boundary -lt 0.90 -or $boundary -gt 0.94){throw 'RELATIVE_WAVEFORM_VALLEY_NOT_DETECTED'}
    # A deeper dip inside the following number cannot win over the boundary
    # anchored at the end of the ordinary word before that number.
    if($boundary -ge 1.1){throw 'NUMBER_INTERNAL_SYLLABLE_USED_AS_PRE_NUMBER_BOUNDARY'}
    if(-not [double]::IsNaN($energy.FindBoundary(0.5,0.4,0.6))){throw 'FLAT_TONE_MANUFACTURED_A_WORD_BOUNDARY'}
    [IO.File]::WriteAllText((Join-Path $temp 'invalid.wav'),'invalid')
    $invalid=$false;try{Get-PvsSubtitleEnergy (Join-Path $temp 'invalid.wav') | Out-Null}catch{$invalid=$_.Exception.Message -like '*SUBTITLE_ENERGY_WAV_INVALID*'}
    if(-not $invalid){throw 'INVALID_PCM_ACCEPTED_AS_ACOUSTIC_EVIDENCE'}
} finally {
    $resolvedTemp=[IO.Path]::GetFullPath($temp)
    $allowedTemp=[IO.Path]::GetFullPath($env:TEMP).TrimEnd('\')+'\'
    if(-not $resolvedTemp.StartsWith($allowedTemp,[StringComparison]::OrdinalIgnoreCase)){throw 'SUBTITLE_TEST_CLEANUP_OUTSIDE_TEMP'}
    if(Test-Path $resolvedTemp){Remove-Item -LiteralPath $resolvedTemp -Recurse -Force}
}
Write-Host 'SUBTITLE_LOCAL_TIMING_OK:good-regions-retained;bounded-retry;local-estimate-only;fatal-propagation;punctuation;number-left-anchor;measured-dip-center;no-global-offset'
