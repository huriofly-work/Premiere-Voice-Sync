$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$root=Resolve-Path (Join-Path $PSScriptRoot '..\..')
. "$root\extension\engine\lib\Security.ps1"
$source=[IO.File]::ReadAllText("$root\extension\engine\resolve-backend.ps1")
$start=$source.IndexOf('$nvidia = Get-NvidiaInfo')
$end=$source.IndexOf('$result | ConvertTo-Json -Depth 6 | Set-Content',$start)
if($start -lt 0 -or $end -lt $start){throw 'BACKEND_STATE_TEST_SOURCE_MISSING'}
$select=[scriptblock]::Create($source.Substring($start,$end-$start))
$temp=Join-Path $env:TEMP ('PVS-BackendCooldown-'+[guid]::NewGuid().ToString('N'))
try{
    $backendRoot=Join-Path $temp 'backends';$whisperVersion='fixture'
    $backend=Join-Path $backendRoot 'whisper-fixture-cuda-fixture'
    New-Item -ItemType Directory -Path $backend -Force | Out-Null
    [IO.File]::WriteAllText((Join-Path $backend 'whisper-cli.exe'),'not executable')
    $cpuWhisper=Join-Path $temp 'cpu.exe';$modelPath='fixture';$ffmpegPath='fixture';$cudaLockPath='fixture';$statePath=Join-Path $temp 'state.json'
    $InstallIfNeeded=$false;$ForceProbe=$false;$script:probes=0
    function Get-NvidiaInfo { [pscustomobject]@{Name='Fixture GPU';Driver='fixture';ComputeCapability='fixture'} }
    function Get-CudaConfig { [pscustomobject]@{version='fixture'} }
    function Get-BackendFingerprint {param($WhisperPath,$NvidiaInfo,$BackendVersion);'fixture'}
    function Assert-PvsCudaLock {param($Root,$LockPath)}
    function Test-CudaBackend {param($WhisperPath,$ModelPath,$FfmpegPath);$script:probes++;[pscustomobject]@{Ok=$true;Detail='fixture'} }
    $until=(Get-Date).AddDays(1).ToString('o')
    $previousState=[pscustomobject]@{backendFingerprint='fixture';probeVerified=$false;disabledUntil=$until}
    for($i=0;$i -lt 2;$i++){
        . $select
        if($result.backend -ne 'cpu' -or $result.disabledUntil -cne $until -or $script:probes -ne 0){throw 'CUDA_RUNTIME_COOLDOWN_LOST'}
        $previousState=[pscustomobject]$result
    }
    $ForceProbe=$true
    . $select
    if($result.backend -ne 'cuda' -or $result.disabledUntil -ne '' -or $script:probes -ne 1){throw 'CUDA_FORCE_PROBE_NOT_RESET'}
    $ForceProbe=$false
    $previousState=[pscustomobject]@{backendFingerprint='fixture';probeVerified=$false;disabledUntil=(Get-Date).AddDays(-1).ToString('o')}
    . $select
    if($result.backend -ne 'cuda' -or $script:probes -ne 2){throw 'CUDA_EXPIRED_COOLDOWN_NOT_RETRIED'}
    # A cached CUDA pass belongs to the model it loaded; a model change re-probes.
    $fpStart=$source.IndexOf('function Get-BackendFingerprint');$fpEnd=$source.IndexOf('$nvidia = Get-NvidiaInfo',$fpStart)
    if($fpStart -lt 0 -or $fpEnd -lt $fpStart){throw 'BACKEND_FINGERPRINT_SOURCE_MISSING'}
    . ([scriptblock]::Create($source.Substring($fpStart,$fpEnd-$fpStart)))
    $gpu=[pscustomobject]@{Name='Fixture GPU';Driver='1';ComputeCapability='8.9'}
    $fingerprints=foreach($name in 'ggml-small.bin','ggml-large-v3-turbo.bin'){
        $modelPath=Join-Path $temp $name;[IO.File]::WriteAllText($modelPath,$name)
        Get-BackendFingerprint -WhisperPath (Join-Path $backend 'whisper-cli.exe') -NvidiaInfo $gpu -BackendVersion 'fixture'
    }
    if($fingerprints[0] -ceq $fingerprints[1]){throw 'CUDA_PROBE_CACHE_IGNORES_MODEL'}
    Write-Host 'BACKEND_COOLDOWN_OK:two-resolves-preserve-runtime-cooldown;force-probe;expiry;model-bound-probe-cache;no-native-GPU-execution'
}finally{Remove-PvsSafeTree -Path $temp -Root $env:TEMP}
