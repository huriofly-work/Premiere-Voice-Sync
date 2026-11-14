$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$root=Resolve-Path (Join-Path $PSScriptRoot '..\..')
. "$root\extension\engine\lib\Native.ps1"
$temp=Join-Path $env:TEMP ('PVS-AudioCache-'+[guid]::NewGuid().ToString('N'))
$script:calls=0
try{
    New-Item -ItemType Directory -Path $temp | Out-Null
    $wav=Join-Path $temp 'audio.wav';$model=Join-Path $temp 'model.bin';$exe=Join-Path $temp 'whisper.exe';$cache=Join-Path $temp 'cache'
    [IO.File]::WriteAllText($wav,'audio-one');[IO.File]::WriteAllText($model,'model');[IO.File]::WriteAllText($exe,'runtime')
    $base=Join-Path $temp 'result'
    $arguments=@('--no-gpu','-m',$model,'-f',$wav,'-l','vi','-ojf','-of',$base,'--prompt','Một nghìn chín trăm.')
    $script:fixtureJson='{"transcription":[{"text":"test","offsets":{"from":10,"to":20},"tokens":[{"id":1,"t_dtw":1}]}]}'
    $execute={
        $script:calls++
        $output=$arguments[[Array]::IndexOf($arguments,'-of')+1]+'.json'
        [IO.File]::WriteAllText($output,$script:fixtureJson)
        [pscustomobject]@{ExitCode=0;StdOut='';StdErr='CPU';Output='CPU'}
    }
    Initialize-PvsAudioCache -Root $cache -RuntimeIdentity fixture
    $cold=Invoke-PvsAudioCachedNative whisper $exe $arguments $execute
    $arguments[[Array]::IndexOf($arguments,'-of')+1]=Join-Path $temp 'another-output'
    $warm=Invoke-PvsAudioCachedNative whisper $exe $arguments $execute
    if($cold.CacheHit -or -not $warm.CacheHit -or $script:calls -ne 1 -or [IO.File]::ReadAllText((Join-Path $temp 'another-output.json')) -cne $script:fixtureJson){throw "AUDIO_CACHE_COLD_WARM_PARITY_FAILED: cold=$($cold.CacheHit) warm=$($warm.CacheHit) calls=$script:calls stats=$((Get-PvsAudioCacheStats|ConvertTo-Json -Compress))"}
    # Same bytes in another path must share raw source-relative recognition.
    $copy=Join-Path $temp 'copy.wav';Copy-Item -LiteralPath $wav -Destination $copy
    $arguments[[Array]::IndexOf($arguments,'-f')+1]=$copy
    $warm=Invoke-PvsAudioCachedNative whisper $exe $arguments $execute
    if(-not $warm.CacheHit -or $script:calls -ne 1){throw 'AUDIO_CACHE_PATH_DEPENDENT'}
    # Content changes invalidate even when length/date are deliberately kept.
    $date=(Get-Item $copy).LastWriteTimeUtc
    [IO.File]::WriteAllText($copy,'audio-two');(Get-Item $copy).LastWriteTimeUtc=$date
    $changed=Invoke-PvsAudioCachedNative whisper $exe $arguments $execute
    if($changed.CacheHit -or $script:calls -ne 2){throw 'AUDIO_CACHE_METADATA_ONLY_IDENTITY'}
    foreach($change in @('prompt','language','dtw','model','runtime')){
        switch($change){
            prompt {$arguments[-1]='Khác prompt'}
            language {$arguments[[Array]::IndexOf($arguments,'-l')+1]='en'}
            dtw {$arguments+=@('-dtw','small','-nfa')}
            model {[IO.File]::WriteAllText($model,'new-model')}
            runtime {[IO.File]::WriteAllText($exe,'new-runtime')}
        }
        $result=Invoke-PvsAudioCachedNative whisper $exe $arguments $execute
        if($result.CacheHit){throw "AUDIO_CACHE_INVALIDATION_FAILED:$change"}
    }
    # Corrupt/incomplete entries are misses, not estimated timing or failures.
    foreach($file in Get-ChildItem -LiteralPath $cache -Filter '*.json'){[IO.File]::WriteAllText($file.FullName,'{"schema":1}')}
    $before=$script:calls
    $result=Invoke-PvsAudioCachedNative whisper $exe $arguments $execute
    if($result.CacheHit -or $script:calls -ne $before+1 -or (Get-PvsAudioCacheStats).invalidEntries -ne 1){throw 'AUDIO_CACHE_CORRUPTION_NOT_RECOVERED'}
    # SHA envelope catches a parseable payload alteration.
    $file=Get-ChildItem -LiteralPath $cache -Filter '*.json' | Where-Object {(Get-Content $_.FullName -Raw) -match 'payload'} | Select-Object -First 1
    $entry=Get-Content -LiteralPath $file.FullName -Raw | ConvertFrom-Json;$entry.payload+=' '
    [IO.File]::WriteAllText($file.FullName,($entry|ConvertTo-Json -Compress))
    $result=Invoke-PvsAudioCachedNative whisper $exe $arguments $execute
    if($result.CacheHit -or (Get-PvsAudioCacheStats).invalidEntries -ne 2){throw 'AUDIO_CACHE_CHECKSUM_NOT_CHECKED'}
    $quietArgs=@('-hide_banner','-i',$wav,'-af','silencedetect=noise=-35dB:d=0.12','-f','null','NUL')
    $quietExecute={$script:calls++;[pscustomobject]@{ExitCode=0;StdOut='';StdErr='silence_start: 1`nsilence_end: 2';Output='silence_start: 1`nsilence_end: 2'}}
    $q1=Invoke-PvsAudioCachedNative quiet $exe $quietArgs $quietExecute
    $q2=Invoke-PvsAudioCachedNative quiet $exe $quietArgs $quietExecute
    if($q1.CacheHit -or -not $q2.CacheHit -or $q1.Output -cne $q2.Output){throw 'AUDIO_CACHE_QUIET_PARITY_FAILED'}
    $quietArgs[4]='silencedetect=noise=-40dB:d=0.12'
    if((Invoke-PvsAudioCachedNative quiet $exe $quietArgs $quietExecute).CacheHit){throw 'AUDIO_CACHE_DETECTOR_PARAMETERS_IGNORED'}
    # A successful CPU fallback from a GPU attempt is not cached under GPU key.
    $gpuArgs=@($arguments | Where-Object {$_ -ne '--no-gpu'})
    foreach($n in 1..2){if((Invoke-PvsAudioCachedNative whisper $exe $gpuArgs $execute).CacheHit){throw 'AUDIO_CACHE_SILENT_CPU_CACHED_AS_GPU'}}
    $failed={ [pscustomobject]@{ExitCode=1;StdOut='';StdErr='failure';Output='failure'} }
    $failureArgs=@($arguments)+@('-t','3')
    foreach($n in 1..2){if((Invoke-PvsAudioCachedNative whisper $exe $failureArgs $failed).CacheHit){throw 'AUDIO_CACHE_FAILURE_CACHED'}}
    Initialize-PvsAudioCache -Enabled $false -Root $cache
    $before=$script:calls
    Invoke-PvsAudioCachedNative whisper $exe $arguments $execute | Out-Null
    Invoke-PvsAudioCachedNative whisper $exe $arguments $execute | Out-Null
    if($script:calls -ne $before+2){throw 'AUDIO_CACHE_DISABLE_IGNORED'}
    # Restarting a job retains cache; algorithm/runtime revision invalidates.
    Initialize-PvsAudioCache -Root $cache -RuntimeIdentity fixture
    if(-not (Invoke-PvsAudioCachedNative whisper $exe $arguments $execute).CacheHit){throw 'AUDIO_CACHE_NOT_PERSISTENT'}
    Initialize-PvsAudioCache -Root $cache -RuntimeIdentity changed
    if((Invoke-PvsAudioCachedNative whisper $exe $arguments $execute).CacheHit){throw 'AUDIO_CACHE_RUNTIME_REVISION_IGNORED'}
    if(@(Get-ChildItem -LiteralPath $cache -Filter '*.tmp').Count){throw 'AUDIO_CACHE_TEMP_LEAK'}
    foreach($file in Get-ChildItem -LiteralPath $cache -File){$file.LastWriteTime=(Get-Date).AddDays(-31)}
    Initialize-PvsAudioCache -Root $cache -RuntimeIdentity fixture
    if(@(Get-ChildItem -LiteralPath $cache -File).Count){throw 'AUDIO_CACHE_EXPIRY_FAILED'}
    # Publication and temporary cleanup can both fail after recognition has
    # succeeded. A directory collision plus an injected tmp lock reproduces
    # both storage failures without changing real permissions or cache.
    Initialize-PvsAudioCache -Root $cache -RuntimeIdentity fixture
    $normalized=[string[]]$quietArgs.Clone()
    $normalized[[Array]::IndexOf($quietArgs,'-i')+1]=Get-PvsAudioFileDigest $wav
    $identity=@('audio-native-v1','quiet','fixture',(Get-PvsAudioFileDigest $exe),$normalized)
    $collision=Join-Path $cache ((Get-PvsAudioDigest (ConvertTo-Json -InputObject $identity -Depth 5 -Compress))+'.json')
    New-Item -ItemType Directory -Path $collision | Out-Null
    function Remove-Item {
        param([string]$LiteralPath,[switch]$Force)
        if($LiteralPath.EndsWith('.tmp')){throw 'FIXTURE_TEMP_LOCKED'}
        Microsoft.PowerShell.Management\Remove-Item @PSBoundParameters
    }
    try{
        $before=$script:calls
        $result=Invoke-PvsAudioCachedNative quiet $exe $quietArgs $quietExecute
        if($result.ExitCode -ne 0 -or $script:calls -ne $before+1 -or (Get-PvsAudioCacheStats).writeFailures -lt 2 -or -not @(Get-ChildItem -LiteralPath $cache -Filter '*.tmp').Count){throw 'AUDIO_CACHE_TEMP_FAILURE_LOST_RECOGNITION'}
    }finally{Microsoft.PowerShell.Management\Remove-Item -LiteralPath Function:\Remove-Item -Force}
    Microsoft.PowerShell.Management\Remove-Item -LiteralPath $collision -Recurse -Force
    Get-ChildItem -LiteralPath $cache -Filter '*.tmp' | Microsoft.PowerShell.Management\Remove-Item -Force
    # An optional cache that cannot be initialized must not stop recognition.
    $blocked=Join-Path $temp 'cache-not-a-directory'
    [IO.File]::WriteAllText($blocked,'sentinel')
    Initialize-PvsAudioCache -Root $blocked -RuntimeIdentity fixture
    $before=$script:calls
    Invoke-PvsAudioCachedNative whisper $exe $arguments $execute | Out-Null
    if($script:calls -ne $before+1 -or (Get-PvsAudioCacheStats).enabled -or (Get-PvsAudioCacheStats).writeFailures -ne 1 -or [IO.File]::ReadAllText($blocked) -ne 'sentinel'){throw 'AUDIO_CACHE_INITIALIZATION_FAILURE_NOT_ISOLATED'}
    Write-Host 'AUDIO_CACHE_OK:raw-JSON-and-quiet-parity;content-not-path;all-parameter-invalidation;corruption;failure;GPU-fallback;disable;restart;expiry;temp-cleanup;unavailable-cache-fallback;locked-temp-fallback'
}finally{Remove-PvsSafeTree -Path $temp -Root $env:TEMP}
