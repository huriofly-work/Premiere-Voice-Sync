param(
    [switch]$InstallIfNeeded,
    [switch]$ForceProbe
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. "$PSScriptRoot\lib\Native.ps1"
Assert-PvsRuntimeLock -EngineRoot $PSScriptRoot
$cudaLockPath = Join-Path $PSScriptRoot 'cuda-lock.json'

$runtimeConfigPath = Join-Path $PSScriptRoot 'runtime\engine.json'
if (-not (Test-Path -LiteralPath $runtimeConfigPath)) { throw 'ENGINE_NOT_INSTALLED' }
$engine = Get-Content -LiteralPath $runtimeConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
$runtimeRoot = Split-Path $runtimeConfigPath -Parent
$cpuWhisper = Join-Path $runtimeRoot ([string]$engine.whisper)
$ffmpegPath = Join-Path $runtimeRoot ([string]$engine.ffmpeg)
$modelPath = Join-Path $runtimeRoot ([string]$engine.modelPath)
if (-not (Test-Path -LiteralPath $cpuWhisper -PathType Leaf)) { throw 'CPU_WHISPER_NOT_INSTALLED' }

$whisperVersion = if ($engine.PSObject.Properties['whisperVersion']) { [string]$engine.whisperVersion } else { 'unknown' }
$backendRoot = Join-Path $env:LOCALAPPDATA 'PremiereVoiceSync\backends'
$stateRoot = Join-Path $env:LOCALAPPDATA 'PremiereVoiceSync'
$statePath = Join-Path $stateRoot 'backend-state.json'
Assert-PvsSafePath -Path $stateRoot -Tree
New-Item -ItemType Directory -Path $backendRoot,$stateRoot -Force | Out-Null
$legacyTempModels = Join-Path $env:TEMP 'PremiereVoiceSync\models'
if (Test-Path -LiteralPath $legacyTempModels -PathType Container) {
    Remove-PvsSafeTree -Path $legacyTempModels -Root (Join-Path $env:TEMP 'PremiereVoiceSync')
}
$previousState = $null
if (Test-Path -LiteralPath $statePath) {
    try { $previousState = Get-Content -LiteralPath $statePath -Raw -Encoding UTF8 | ConvertFrom-Json } catch {}
}

function Get-NvidiaInfo {
    $commandPath = Join-Path $env:WINDIR 'System32\nvidia-smi.exe'
    if (-not (Test-Path -LiteralPath $commandPath)) {
        $commandPath = Join-Path $env:ProgramW6432 'NVIDIA Corporation\NVSMI\nvidia-smi.exe'
    }
    if (-not (Test-Path -LiteralPath $commandPath)) { return $null }
    try {
        $probe = Invoke-NativeCapture -FilePath $commandPath -Arguments @('--query-gpu=name,driver_version,compute_cap','--format=csv,noheader')
        if ($probe.ExitCode -ne 0 -or -not $probe.StdOut.Trim()) { return $null }
        $first = ($probe.StdOut -split '\r?\n' | Where-Object { $_.Trim() } | Select-Object -First 1)
        $parts = @($first -split ',' | ForEach-Object { $_.Trim() })
        return [pscustomobject]@{
            Name = if ($parts.Count -gt 0) { $parts[0] } else { 'NVIDIA GPU' }
            Driver = if ($parts.Count -gt 1) { $parts[1] } else { '' }
            ComputeCapability = if ($parts.Count -gt 2) { $parts[2] } else { '' }
        }
    } catch { return $null }
}

function Get-CudaConfig {
    if (-not $engine.PSObject.Properties['backends']) { return $null }
    if (-not $engine.backends.PSObject.Properties['cuda']) { return $null }
    return $engine.backends.cuda
}

function Test-CudaBackend {
    param(
        [Parameter(Mandatory)][string]$WhisperPath,
        [Parameter(Mandatory)][string]$ModelPath,
        [Parameter(Mandatory)][string]$FfmpegPath
    )
    if (-not (Test-Path -LiteralPath $WhisperPath -PathType Leaf)) { return $null }
    $probeRoot = Join-Path $env:TEMP ("PremiereVoiceSync-backend-probe-{0}" -f ([guid]::NewGuid().ToString('N')))
    try {
        New-Item -ItemType Directory -Path $probeRoot -Force | Out-Null
        Assert-PvsSafePath -Path $probeRoot
        $asciiModel = Get-PvsVerifiedModelCopy -Source $ModelPath -DataRoot $stateRoot
        $wav = Join-Path $probeRoot 'probe.wav'
        $makeWav = Invoke-NativeCapture -FilePath $FfmpegPath -Arguments @('-y','-hide_banner','-loglevel','error','-f','lavfi','-i','anullsrc=r=16000:cl=mono','-t','0.25','-c:a','pcm_s16le',$wav)
        if ($makeWav.ExitCode -ne 0) { return [pscustomobject]@{ Ok=$false; Detail="Khong tao duoc probe WAV: $($makeWav.Output)" } }
        $probe = Invoke-NativeCapture -FilePath $WhisperPath -Arguments @('-m',$asciiModel,'-f',$wav,'-l','vi','-np','-nt','-otxt','-of',(Join-Path $probeRoot 'result')) -WorkingDirectory (Split-Path $WhisperPath -Parent)
        $output = [string]$probe.Output
        $cudaLine = ($output -split '\r?\n' | Where-Object { $_ -match '(?i)^load_backend:\s+loaded CUDA backend from .+ggml-cuda\.dll' } | Select-Object -First 1)
        if ($probe.ExitCode -eq 0 -and $cudaLine) {
            return [pscustomobject]@{ Ok=$true; Detail=[string]$cudaLine }
        }
        return [pscustomobject]@{ Ok=$false; Detail=("exit={0}; {1}" -f $probe.ExitCode, (($output -replace '\s+',' ').Trim())) }
    } catch {
        return [pscustomobject]@{ Ok=$false; Detail=$_.Exception.Message }
    } finally {
        if (Test-Path -LiteralPath $probeRoot) { Remove-PvsSafeTree -Path $probeRoot -Root $env:TEMP }
    }
}

function Install-CudaBackend {
    param([Parameter(Mandatory)]$CudaConfig)
    $backendVersion = [string]$CudaConfig.version
    $target = Join-Path $backendRoot ("whisper-{0}-cuda-{1}" -f $whisperVersion,$backendVersion)
    $targetCli = Join-Path $target 'whisper-cli.exe'
    if (Test-Path -LiteralPath $targetCli -PathType Leaf) { Assert-PvsCudaLock -Root $target -LockPath $cudaLockPath; return $targetCli }

    $downloadRoot = Join-Path $stateRoot 'downloads'
    Assert-PvsSafePath -Path $downloadRoot -Root $stateRoot -Tree
    New-Item -ItemType Directory -Path $downloadRoot -Force | Out-Null
    $assetName = [IO.Path]::GetFileName(([uri][string]$CudaConfig.url).AbsolutePath)
    $archive = Join-Path $downloadRoot $assetName
    if (Test-Path -LiteralPath $archive) {
        $actualHash = (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($actualHash -ne ([string]$CudaConfig.sha256).ToLowerInvariant()) { Remove-Item -LiteralPath $archive -Force }
    }
    if (-not (Test-Path -LiteralPath $archive)) {
        $curl = Join-Path $env:SystemRoot 'System32\curl.exe'
        if (-not (Test-Path -LiteralPath $curl)) { throw 'Khong tim thay curl.exe cua Windows de tai backend CUDA.' }
        $download = Invoke-NativeCapture -FilePath $curl -Arguments @('--proto','=https','--proto-redir','=https','--location','--fail','--retry','5','--retry-delay','3','--output',$archive,[string]$CudaConfig.url)
        if ($download.ExitCode -ne 0) { throw "Tai backend CUDA that bai: $($download.Output)" }
    }
    $hash = (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($hash -ne ([string]$CudaConfig.sha256).ToLowerInvariant()) { throw 'Backend CUDA sai SHA256.' }

    $staging = Join-Path $env:TEMP ("PremiereVoiceSync-cuda-{0}" -f ([guid]::NewGuid().ToString('N')))
    Assert-PvsSafePath -Path $staging
    New-Item -ItemType Directory -Path $staging -Force | Out-Null
    try {
        Expand-Archive -LiteralPath $archive -DestinationPath $staging -Force
        $cli = Get-ChildItem -LiteralPath $staging -Recurse -Filter 'whisper-cli.exe' -File | Select-Object -First 1
        if (-not $cli) { throw 'Goi CUDA khong co whisper-cli.exe.' }
        Assert-PvsCudaLock -Root $cli.DirectoryName -LockPath $cudaLockPath
        if (Test-Path -LiteralPath $target) { Remove-PvsSafeTree -Path $target -Root $backendRoot }
        New-Item -ItemType Directory -Path $target -Force | Out-Null
        $lock = Get-Content -LiteralPath $cudaLockPath -Raw -Encoding UTF8 | ConvertFrom-Json
        foreach ($entry in $lock.files) { Copy-Item -LiteralPath (Join-Path $cli.DirectoryName $entry.path) -Destination $target -Force }
        Assert-PvsCudaLock -Root $target -LockPath $cudaLockPath
    } finally {
        if (Test-Path -LiteralPath $staging) { Remove-PvsSafeTree -Path $staging -Root $env:TEMP }
    }
    if (-not (Test-Path -LiteralPath $targetCli -PathType Leaf)) { throw 'Khong cai duoc backend CUDA.' }
    if (Test-Path -LiteralPath $archive) { Remove-Item -LiteralPath $archive -Force -ErrorAction SilentlyContinue }
    if ((Test-Path -LiteralPath $downloadRoot -PathType Container) -and @(Get-ChildItem -LiteralPath $downloadRoot -Force).Count -eq 0) {
        Remove-Item -LiteralPath $downloadRoot -Force -ErrorAction SilentlyContinue
    }
    return $targetCli
}

function Get-BackendFingerprint {
    param(
        [Parameter(Mandatory)][string]$WhisperPath,
        [Parameter(Mandatory)]$NvidiaInfo,
        [Parameter(Mandatory)][string]$BackendVersion
    )
    $file = Get-Item -LiteralPath $WhisperPath
    # A probe proves CUDA for one model's memory footprint. Changing the model
    # (Small -> large-v3-turbo) must re-probe instead of reusing a cached pass.
    # The runtime lock has already verified this model file's hash.
    $model = Get-Item -LiteralPath $modelPath
    return '{0}|{1}|{2}|{3}|{4}|{5}|{6}|{7}' -f $NvidiaInfo.Name,$NvidiaInfo.Driver,$NvidiaInfo.ComputeCapability,$BackendVersion,$file.Length,$file.LastWriteTimeUtc.Ticks,$model.Name,$model.Length
}

$nvidia = Get-NvidiaInfo
$cudaConfig = Get-CudaConfig
$selected = 'cpu'
$label = 'CPU'
$whisperPath = $cpuWhisper
$arguments = @('--no-gpu')
$gpuName = if ($nvidia) { [string]$nvidia.Name } else { '' }
$reason = if ($nvidia) { 'Chua co backend CUDA hop le.' } else { 'Khong phat hien NVIDIA CUDA hoac nvidia-smi; ban hien tai dung CPU tren may nay.' }
$probeDetail = ''
$installedNow = $false
$probeCached = $false
$backendFingerprint = ''
$disabledByRuntimeFailure = $false

if ($nvidia -and $cudaConfig) {
    $cudaTarget = Join-Path $backendRoot ("whisper-{0}-cuda-{1}\whisper-cli.exe" -f $whisperVersion,[string]$cudaConfig.version)
    if (-not (Test-Path -LiteralPath $cudaTarget) -and -not $InstallIfNeeded) { $reason = 'Chua tai backend CUDA. Bat quyen tai GPU trong panel neu muon; CPU van dung offline.' }
    if (-not (Test-Path -LiteralPath $cudaTarget) -and $InstallIfNeeded) {
        try {
            $cudaTarget = Install-CudaBackend -CudaConfig $cudaConfig
            $installedNow = $true
        } catch {
            $reason = "Khong cai duoc CUDA: $($_.Exception.Message)"
        }
    }
    $cudaIntegrityOk = $false
    if (Test-Path -LiteralPath $cudaTarget -PathType Leaf) {
        try { Assert-PvsCudaLock -Root (Split-Path $cudaTarget -Parent) -LockPath $cudaLockPath; $cudaIntegrityOk = $true }
        catch { $reason = "Backend CUDA khong vuot qua kiem tra toan ven; khong thuc thi va dung CPU. $($_.Exception.Message)" }
    }
    if ($cudaIntegrityOk) {
        $backendFingerprint = Get-BackendFingerprint -WhisperPath $cudaTarget -NvidiaInfo $nvidia -BackendVersion ([string]$cudaConfig.version)
        if ($previousState -and $previousState.PSObject.Properties['backendFingerprint'] -and [string]$previousState.backendFingerprint -eq $backendFingerprint -and $previousState.PSObject.Properties['disabledUntil'] -and [string]$previousState.disabledUntil) {
            try { $disabledByRuntimeFailure = [datetime]$previousState.disabledUntil -gt (Get-Date) } catch {}
        }
        if ($ForceProbe) { $disabledByRuntimeFailure = $false }
        $cachedProbeValid = -not $ForceProbe -and -not $installedNow -and -not $disabledByRuntimeFailure -and $previousState -and $previousState.PSObject.Properties['backendFingerprint'] -and [string]$previousState.backendFingerprint -eq $backendFingerprint -and $previousState.PSObject.Properties['probeVerified'] -and [bool]$previousState.probeVerified
        if ($disabledByRuntimeFailure) {
            $reason = "CUDA dang tam tat sau loi runtime den $($previousState.disabledUntil); dung CPU de bao dam tac vu hoan tat."
        } elseif ($cachedProbeValid) {
            $probeCached = $true
            $probeDetail = [string]$previousState.probeDetail
            $selected = 'cuda'
            $label = "NVIDIA CUDA - $($nvidia.Name)"
            $whisperPath = $cudaTarget
            $arguments = @('--device','0')
            $reason = 'CUDA da duoc xac minh bang nhan dien thuc te cho GPU va driver hien tai.'
        } else {
            $probe = Test-CudaBackend -WhisperPath $cudaTarget -ModelPath $modelPath -FfmpegPath $ffmpegPath
            $probeDetail = [string]$probe.Detail
            if ($probe.Ok) {
                $selected = 'cuda'
                $label = "NVIDIA CUDA - $($nvidia.Name)"
                $whisperPath = $cudaTarget
                $arguments = @('--device','0')
                $reason = 'CUDA da vuot qua phep thu nhan dien thuc te.'
            } else {
                $reason = "Phep thu CUDA that bai nen chuyen sang CPU. $probeDetail"
            }
        }
    }
}

$result = [ordered]@{
    ok = $true
    backend = $selected
    label = $label
    whisperPath = $whisperPath
    arguments = $arguments
    gpuName = $gpuName
    driverVersion = if ($nvidia) { [string]$nvidia.Driver } else { '' }
    computeCapability = if ($nvidia) { [string]$nvidia.ComputeCapability } else { '' }
    whisperVersion = $whisperVersion
    installedNow = $installedNow
    probeVerified = ($selected -eq 'cuda')
    probeCached = $probeCached
    backendFingerprint = $backendFingerprint
    # Keep the cooldown across repeated panel/engine resolves. Clearing it on
    # the first CPU fallback would immediately retry the failed GPU next job.
    disabledUntil = if($disabledByRuntimeFailure){[string]$previousState.disabledUntil}else{''}
    reason = $reason
    probeDetail = $probeDetail
    statePath = $statePath
    checkedAt = (Get-Date).ToString('o')
}
$result | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $statePath -Encoding UTF8
$downloadCleanup = Join-Path $stateRoot 'downloads'
if (Test-Path -LiteralPath $downloadCleanup -PathType Container) {
    Remove-PvsSafeTree -Path $downloadCleanup -Root $stateRoot
}
$result | ConvertTo-Json -Depth 6 -Compress
