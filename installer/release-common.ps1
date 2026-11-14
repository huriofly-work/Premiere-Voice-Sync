$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Copy-PvsReleaseExtension {
    param(
        [Parameter(Mandatory)][string]$Source,
        [Parameter(Mandatory)][string]$Destination
    )

    if (-not (Test-Path -LiteralPath $Source -PathType Container)) {
        throw "Khong tim thay extension source: $Source"
    }

    New-Item -ItemType Directory -Path $Destination -Force | Out-Null
    # Copy only reviewed runtime files, excluding local configuration and secrets.
    foreach ($relative in @('CSXS\manifest.xml','css\styles.css','js\main.js','js\security.js','js\notification-policy.js','js\native-notifications.js','native\PvsNotifications.exe','native\helper-lock.json','native\NotificationIdentity.cs','native\NotificationProtocol.cs','native\NotificationHost.cs','native\NotificationWindow.cs','jsx\host.jsx','jsx\diagnostic-executor.jsx')) {
        $targetFile = Join-Path $Destination $relative
        New-Item -ItemType Directory -Path (Split-Path $targetFile -Parent) -Force | Out-Null
        Copy-Item -LiteralPath (Join-Path $Source $relative) -Destination $targetFile -Force
    }
    Copy-Item -LiteralPath (Join-Path $Source 'js\caption-input.js') -Destination (Join-Path $Destination 'js\caption-input.js') -Force
    Copy-Item -LiteralPath (Join-Path $Source 'js\srt-join.js') -Destination (Join-Path $Destination 'js\srt-join.js') -Force
    Copy-Item -LiteralPath (Join-Path $Source 'index.html') -Destination $Destination -Force

    $sourceEngine = Join-Path $Source 'engine'
    $targetEngine = Join-Path $Destination 'engine'
    $targetLib = Join-Path $targetEngine 'lib'
    $targetRuntime = Join-Path $targetEngine 'runtime'
    $targetBin = Join-Path $targetRuntime 'bin'
    $targetModels = Join-Path $targetRuntime 'models'
    New-Item -ItemType Directory -Path $targetLib, $targetBin, $targetModels -Force | Out-Null

    foreach ($file in @('run-alignment.ps1', 'build-sentence-plan.ps1', 'build-dtw-trial-plan.ps1', 'build-speed-merge-trial-plan.ps1', 'resolve-backend.ps1', 'run-captions.ps1', 'run-workflow.ps1', 'request-attention.ps1')) {
        Copy-Item -LiteralPath (Join-Path $sourceEngine $file) -Destination $targetEngine -Force
    }
    foreach ($file in @('Srt.ps1', 'Alignment.ps1', 'ReferenceAlignment.ps1', 'WordMapper.ps1', 'Native.ps1', 'RecognitionBackend.ps1', 'AudioCache.ps1', 'Paths.ps1', 'CaptionOnly.ps1', 'CaptionTiming.ps1', 'AutoEditManualReview.ps1','AutoEditAcousticPartitions.ps1', 'SubtitleTiming.ps1', 'SubtitleEnergy.ps1', 'DtwEditTrial.ps1', 'SpeedMergeTrial.ps1', 'Security.ps1')) {
        Copy-Item -LiteralPath (Join-Path $sourceEngine "lib\$file") -Destination $targetLib -Force
    }
    Copy-Item -LiteralPath (Join-Path $sourceEngine 'lib\vi-caption-phrases.txt') -Destination $targetLib -Force
    Copy-Item -LiteralPath (Join-Path $sourceEngine 'lib\vi-caption-overrides.txt') -Destination $targetLib -Force
    Copy-Item -LiteralPath (Join-Path $sourceEngine 'lib\vi-caption-phrases.NOTICE.txt') -Destination $targetLib -Force
    Copy-Item -LiteralPath (Join-Path $sourceEngine 'lib\vi-caption-phrases.LICENSE.txt') -Destination $targetLib -Force
    Copy-Item -LiteralPath (Join-Path $sourceEngine 'engine-config.json') -Destination (Join-Path $targetRuntime 'engine.json') -Force
    foreach ($file in @('runtime-lock.json','cuda-lock.json')) {
        Copy-Item -LiteralPath (Join-Path $sourceEngine $file) -Destination $targetEngine -Force
    }

    $runtimeFiles = @(
        'ffmpeg.exe',
        'whisper-cli.exe',
        'whisper.dll', 'ggml.dll', 'ggml-base.dll',
        'ggml-cpu-x64.dll', 'ggml-cpu-sse42.dll', 'ggml-cpu-sandybridge.dll',
        'ggml-cpu-haswell.dll', 'ggml-cpu-skylakex.dll', 'ggml-cpu-icelake.dll',
        'ggml-cpu-cascadelake.dll', 'ggml-cpu-cannonlake.dll', 'ggml-cpu-alderlake.dll',
        'SDL2.dll', 'parakeet.dll'
    )
    foreach ($file in $runtimeFiles) {
        $sourceFile = Join-Path $sourceEngine "runtime\bin\$file"
        if (-not (Test-Path -LiteralPath $sourceFile -PathType Leaf)) { throw "Runtime file missing: $file" }
        Copy-Item -LiteralPath $sourceFile -Destination $targetBin -Force
    }
    foreach ($model in @('ggml-large-v3-turbo.bin')) {
        $sourceModel = Join-Path $sourceEngine "runtime\models\$model"
        if (-not (Test-Path -LiteralPath $sourceModel -PathType Leaf)) { throw "Model missing: $model" }
        Copy-Item -LiteralPath $sourceModel -Destination $targetModels -Force
    }
}
