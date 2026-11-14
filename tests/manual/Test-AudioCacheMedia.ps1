param([Parameter(Mandatory)][string]$MediaPath,[switch]$UseGpu)
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$root=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$engine=Join-Path $root 'extension\engine'
. "$engine\lib\Native.ps1"
. "$engine\lib\CaptionTiming.ps1"
Assert-PvsRuntimeLock -EngineRoot $engine
$temp=Join-Path $env:TEMP ('PVS-AudioCacheMedia-'+[guid]::NewGuid().ToString('N'))
try{
    New-Item -ItemType Directory -Path $temp | Out-Null
    $ffmpeg=Join-Path $engine 'runtime\bin\ffmpeg.exe'
    $whisper=Join-Path $engine 'runtime\bin\whisper-cli.exe'
    $model=Join-Path $engine 'runtime\models\ggml-large-v3-turbo.bin'
    $backend='cpu';$backendArgs=@('--no-gpu')
    if($UseGpu){
        $resolved=(& "$engine\resolve-backend.ps1" | Out-String).Trim() | ConvertFrom-Json
        if($resolved.backend -ne 'cuda'){throw 'TEST_CUDA_NOT_AVAILABLE'}
        $whisper=$resolved.whisperPath;$backend='cuda';$backendArgs=@([string[]]$resolved.arguments)
    }
    $wav=Join-Path $temp 'audio.wav'
    $conversion=Invoke-NativeCapture $ffmpeg @('-y','-hide_banner','-loglevel','error','-i',$MediaPath,'-t','8','-ar','16000','-ac','1','-c:a','pcm_s16le',$wav)
    if($conversion.ExitCode -ne 0){throw 'TEST_MEDIA_CONVERSION_FAILED'}
    Initialize-PvsAudioCache -Root (Join-Path $temp 'cache') -RuntimeIdentity media-fixture-v1
    $rows=New-Object System.Collections.Generic.List[object]
    foreach($dtw in @($false,$true)){
        foreach($prompt in @('','Test prompt')){
            $hash=''
            foreach($pass in @('cold','warm')){
                $base=Join-Path $temp ("$dtw-$($prompt.Length)-$pass")
                $watch=[Diagnostics.Stopwatch]::StartNew()
                $run=Invoke-PvsCaptionDtwRecognition -WhisperPath $whisper -CpuWhisperPath (Join-Path $engine 'runtime\bin\whisper-cli.exe') -ModelPath $model -ModelName small -WavPath $wav -OutBase $base -Language vi -Backend $backend -BackendArguments $backendArgs -UseDtw $dtw -Prompt $prompt
                $watch.Stop()
                if($run.Backend -ne $backend){throw 'TEST_UNEXPECTED_GPU_FALLBACK'}
                $actual=(Get-FileHash -LiteralPath ($base+'.json') -Algorithm SHA256).Hash
                if($pass -eq 'cold'){$hash=$actual}else{if($actual -ne $hash){throw 'TEST_MEDIA_RAW_TIMING_CHANGED'}}
                $rows.Add([pscustomobject]@{dtw=$dtw;prompt=([bool]$prompt);pass=$pass;milliseconds=$watch.ElapsedMilliseconds})
            }
        }
    }
    $first=@(Get-PvsCaptionQuiet $ffmpeg $wav) | ConvertTo-Json -Compress
    $second=@(Get-PvsCaptionQuiet $ffmpeg $wav) | ConvertTo-Json -Compress
    if($first -cne $second){throw 'TEST_MEDIA_QUIET_CHANGED'}
    $stats=Get-PvsAudioCacheStats
    if($stats.whisperHits -ne 4 -or $stats.whisperMisses -ne 4 -or $stats.quietHits -ne 1 -or $stats.quietMisses -ne 1 -or $stats.writeFailures -or $stats.invalidEntries){throw 'TEST_MEDIA_CACHE_COUNTS_INVALID'}
    [pscustomobject]@{ok=$true;backend=$backend;rawJsonByteIdentical=$true;quietIdentical=$true;stats=$stats;timings=$rows.ToArray()} | ConvertTo-Json -Depth 6
}finally{Remove-PvsSafeTree -Path $temp -Root $env:TEMP}
