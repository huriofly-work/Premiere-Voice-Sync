param([Parameter(Mandatory)][string]$MediaPath,[Parameter(Mandatory)][string]$SrtPath,[Parameter(Mandatory)][int]$CueIndex,[Parameter(Mandatory)][double]$CueStart,[Parameter(Mandatory)][double]$CueEnd,[Parameter(Mandatory)][string]$NumericToken,[double]$ExpectedEndMin=[double]::NaN,[double]$ExpectedEndMax=[double]::NaN,[string]$WhisperPath='')
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$root=Resolve-Path (Join-Path $PSScriptRoot '..\..')
. "$root\extension\engine\lib\Native.ps1"
. "$root\extension\engine\lib\Alignment.ps1"
. "$root\extension\engine\lib\Srt.ps1"
$folder=Join-Path $env:TEMP ('PVS-NumericMedia-'+[guid]::NewGuid().ToString('N'))
Assert-PvsSafePath -Path $folder
$cpu=[string]::IsNullOrEmpty($WhisperPath)
if($cpu){$WhisperPath=Join-Path $root 'extension\engine\runtime\bin\whisper-cli.exe'}
try{
    New-Item -ItemType Directory -Path $folder | Out-Null
    $reference=@(Read-SrtFile $SrtPath | Where-Object {$_.Index -eq $CueIndex})
    if($reference.Count -ne 1){throw 'NUMERIC_FIXTURE_CUE_MISSING'}
    $cue=[pscustomobject]@{Index=$CueIndex;Text=$reference[0].Text;Start=$CueStart;End=$CueEnd;Chapter=0;WordTimings=@()}
    $before=$cue | ConvertTo-Json -Depth 8 -Compress
    $result=Repair-PvsNumericCaptionTimings @($cue) @([pscustomobject]@{start=0;end=$CueEnd+1}) {
        param($voice,$start,$end,$prompt)
        $wav=Join-Path $folder 'window.wav';$out=Join-Path $folder 'result'
        $run=Invoke-NativeCapture -FilePath (Join-Path $root 'extension\engine\runtime\bin\ffmpeg.exe') -Arguments @('-y','-hide_banner','-loglevel','error','-ss',$start.ToString('0.######',[Globalization.CultureInfo]::InvariantCulture),'-i',$MediaPath,'-t',($end-$start).ToString('0.######',[Globalization.CultureInfo]::InvariantCulture),'-ar','16000','-ac','1','-c:a','pcm_s16le',$wav)
        if($run.ExitCode -ne 0){throw 'NUMERIC_FIXTURE_AUDIO_FAILED'}
        $args=@('-m',(Join-Path $root 'extension\engine\runtime\models\ggml-large-v3-turbo.bin'),'-f',$wav,'-l','vi','-ojf','-ml','1','-sow','-np','-of',$out,'--prompt',$prompt)
        if($cpu){$args=@('--no-gpu')+$args}
        $run=Invoke-PvsWhisperCapture -FilePath $WhisperPath -Arguments $args -WorkingDirectory (Split-Path $WhisperPath -Parent)
        if($run.ExitCode -ne 0 -or (-not $cpu -and $run.Output -notmatch 'loaded CUDA backend')){throw 'NUMERIC_FIXTURE_RECOGNITION_FAILED'}
        $words=@(Convert-WhisperJsonToWords "$out.json" 0)
        Write-Verbose "NUMERIC_MEDIA_HEARD:$($words | ConvertTo-Json -Compress)"
        $words
    }
    if(($result.Refined -join ',') -ne [string]$CueIndex){throw 'NUMERIC_FIXTURE_NOT_REFINED'}
    $numeric=@($cue.CaptionWordTimings | Where-Object {$_.Text -eq $NumericToken})
    Write-Host "NUMERIC_MEDIA_MEASURED:$($numeric | ConvertTo-Json -Compress)"
    if($numeric.Count -ne 1){throw 'NUMERIC_FIXTURE_TOKEN_MISSING'}
    # Optional ground-truth bounds must come from listening/annotation, not
    # from a silence interval guessed to belong to this particular word.
    if(-not [double]::IsNaN($ExpectedEndMin) -and -not [double]::IsNaN($ExpectedEndMax)){
        if($ExpectedEndMin -ge $ExpectedEndMax){throw 'NUMERIC_FIXTURE_EXPECTED_RANGE_INVALID'}
        if($numeric[0].End -lt $ExpectedEndMin -or $numeric[0].End -gt $ExpectedEndMax){throw 'NUMERIC_FIXTURE_ACOUSTIC_BOUNDARY_MISMATCH'}
    }
    if(($cue | Select-Object Index,Text,Start,End,Chapter,WordTimings | ConvertTo-Json -Depth 8 -Compress) -ne $before){throw 'NUMERIC_FIXTURE_EDIT_TIMING_CHANGED'}
    Write-Host "NUMERIC_MEDIA_PIPELINE_OK:cue=$CueIndex;token=$NumericToken;start=$($numeric[0].Start);end=$($numeric[0].End);cpu=$cpu;edit-timing-preserved;listening-not-performed"
}finally{Remove-PvsSafeTree -Path $folder -Root $env:TEMP}
