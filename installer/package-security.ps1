Set-StrictMode -Version Latest
. (Join-Path (Split-Path $PSScriptRoot -Parent) 'extension\engine\lib\Security.ps1')

function Get-PvsPackageFiles {
    param([string]$Root)
    $files = @(
        'Setup-Panel.cmd','Remove-Panel.cmd','README.md','HUONG_DAN_SU_DUNG.md','THONG_BAO.md','THIRD_PARTY_NOTICES.md','licenses\GPL-3.0.txt',
        'scripts\install.ps1','scripts\uninstall.ps1','scripts\package-security.ps1',
        'extension\CSXS\manifest.xml','extension\index.html','extension\css\styles.css',
        'extension\js\main.js','extension\js\security.js','extension\jsx\host.jsx','extension\jsx\diagnostic-executor.jsx',
        'extension\js\notification-policy.js','extension\js\native-notifications.js','extension\js\caption-input.js',
        'extension\native\PvsNotifications.exe','extension\native\helper-lock.json','extension\native\NotificationIdentity.cs','extension\native\NotificationProtocol.cs','extension\native\NotificationHost.cs','extension\native\NotificationWindow.cs',
        'extension\engine\runtime-lock.json','extension\engine\cuda-lock.json','extension\engine\runtime\engine.json',
        'extension\js\srt-join.js'
    )
    foreach ($name in @('run-alignment.ps1','build-sentence-plan.ps1','build-dtw-trial-plan.ps1','build-speed-merge-trial-plan.ps1','resolve-backend.ps1','run-captions.ps1','run-workflow.ps1','request-attention.ps1')) { $files += "extension\engine\$name" }
    foreach ($name in @('Srt.ps1','Alignment.ps1','ReferenceAlignment.ps1','WordMapper.ps1','Native.ps1','AudioCache.ps1','RecognitionBackend.ps1','Paths.ps1','CaptionOnly.ps1','CaptionTiming.ps1','AutoEditManualReview.ps1','AutoEditAcousticPartitions.ps1','SubtitleTiming.ps1','SubtitleEnergy.ps1','DtwEditTrial.ps1','SpeedMergeTrial.ps1','Security.ps1','vi-caption-phrases.txt','vi-caption-overrides.txt','vi-caption-phrases.NOTICE.txt','vi-caption-phrases.LICENSE.txt')) { $files += "extension\engine\lib\$name" }
    foreach ($name in @('ffmpeg.exe','whisper-cli.exe','whisper.dll','ggml.dll','ggml-base.dll','ggml-cpu-x64.dll','ggml-cpu-sse42.dll','ggml-cpu-sandybridge.dll','ggml-cpu-haswell.dll','ggml-cpu-skylakex.dll','ggml-cpu-icelake.dll','ggml-cpu-cascadelake.dll','ggml-cpu-cannonlake.dll','ggml-cpu-alderlake.dll','SDL2.dll','parakeet.dll')) { $files += "extension\engine\runtime\bin\$name" }
    $files += 'extension\engine\runtime\models\ggml-large-v3-turbo.bin'
    return $files
}

function Assert-PvsPackage {
    param([string]$Root)
    return Assert-PvsHashManifest -Root $Root -Manifest (Join-Path $Root 'SHA256SUMS.txt') -ExpectedFiles (Get-PvsPackageFiles -Root $Root)
}

function Assert-PvsPanelIdentity {
    param([string]$Path)
    Assert-PvsSafePath -Path $Path -Tree
    $manifestPath = Join-Path $Path 'CSXS\manifest.xml'
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) { throw 'SECURITY_PANEL_IDENTITY_MISSING' }
    [xml]$manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8
    if ([string]$manifest.ExtensionManifest.ExtensionBundleId -ne 'com.premierevoicesync.local') { throw 'SECURITY_PANEL_IDENTITY_MISMATCH' }
}
