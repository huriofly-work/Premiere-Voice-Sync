$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$projectRoot = Resolve-Path (Join-Path $PSScriptRoot '..\..')
$releaseCommon = Join-Path $projectRoot 'installer\release-common.ps1'
$buildRelease = Join-Path $projectRoot 'installer\build-release.ps1'
$legacyProtector = Join-Path $projectRoot 'installer\protect-release.ps1'
if (Test-Path -LiteralPath $legacyProtector) { throw 'LEGACY_PROTECTOR_STILL_EXISTS' }

$buildSource = [IO.File]::ReadAllText($buildRelease,[Text.Encoding]::UTF8)
if ($buildSource.IndexOf('protect-release.ps1',[StringComparison]::OrdinalIgnoreCase) -ge 0) { throw 'BUILD_STILL_CALLS_PROTECTOR' }
foreach ($required in @(
    "`$commands = @('Setup-Panel.cmd','Remove-Panel.cmd')",
    'extension\engine\lib\Srt.ps1',
    'extension\engine\lib\Alignment.ps1',
    'extension\engine\lib\ReferenceAlignment.ps1',
    'extension\engine\lib\WordMapper.ps1',
    'extension\engine\lib\Native.ps1',
    'extension\engine\lib\Paths.ps1',
    'extension\engine\lib\vi-caption-phrases.txt',
    'extension\engine\lib\vi-caption-overrides.txt',
    'extension\engine\lib\vi-caption-phrases.NOTICE.txt',
    'extension\engine\lib\vi-caption-phrases.LICENSE.txt',
    'Release still contains protected payload',
    "Copy-Item -LiteralPath (Join-Path `$projectRoot 'THIRD_PARTY_NOTICES.md') -Destination `$staging -Force",
    "'THIRD_PARTY_NOTICES.md'"
)) {
    if ($buildSource.IndexOf($required,[StringComparison]::Ordinal) -lt 0) { throw "OPEN_SOURCE_BUILD_INVARIANT_MISSING:$required" }
}

# Every third-party runtime file that ships must be named in the notices the
# package carries (FFmpeg is GPL v3; whisper.cpp/ggml, SDL2 and the model need
# their copyright notices kept).
. (Join-Path $projectRoot 'installer\package-security.ps1')
$packageFiles = @(Get-PvsPackageFiles)
if ('THIRD_PARTY_NOTICES.md' -notin $packageFiles) { throw 'THIRD_PARTY_NOTICES_NOT_IN_PACKAGE_ALLOWLIST' }
$noticesPath = Join-Path $projectRoot 'THIRD_PARTY_NOTICES.md'
if (-not (Test-Path -LiteralPath $noticesPath -PathType Leaf)) { throw 'THIRD_PARTY_NOTICES_MISSING' }
$notices = [IO.File]::ReadAllText($noticesPath,[Text.Encoding]::UTF8)
foreach ($runtimeFile in @($packageFiles | Where-Object { $_ -like 'extension\engine\runtime\*' -and $_ -notlike '*\engine.json' })) {
    $leaf = Split-Path $runtimeFile -Leaf
    $covered = $notices.IndexOf($leaf,[StringComparison]::Ordinal) -ge 0
    if (-not $covered -and $leaf -like 'ggml-cpu-*.dll') { $covered = $notices.IndexOf('ggml-cpu-*.dll',[StringComparison]::Ordinal) -ge 0 }
    if (-not $covered) { throw "THIRD_PARTY_NOTICE_MISSING_FOR:$leaf" }
}
foreach ($phrase in @('GPL v3','https://ffmpeg.org/releases/ffmpeg-8.1.2.tar.xz','MIT','zlib','Apache 2.0')) {
    if ($notices.IndexOf($phrase,[StringComparison]::Ordinal) -lt 0) { throw "THIRD_PARTY_NOTICE_TERM_MISSING:$phrase" }
}

. $releaseCommon
# Exercise a noncanonical spelling as well as runners' TEMP aliases. Relative
# payload names must not depend on the textual length of an absolute path.
$temp = Join-Path (Join-Path $env:TEMP '.') ('PVS-OpenSourceRelease-' + [guid]::NewGuid().ToString('N'))
$source = Join-Path $temp 'source'
$destination = Join-Path $temp 'release'
try {
    foreach ($directory in @(
        'CSXS','css','js','jsx','native','ui','engine\lib','engine\runtime\bin','engine\runtime\models'
    )) {
        New-Item -ItemType Directory -Path (Join-Path $source $directory) -Force | Out-Null
    }
    Set-Content -LiteralPath (Join-Path $source 'CSXS\manifest.xml') -Value '<ExtensionManifest />' -Encoding ASCII
    Set-Content -LiteralPath (Join-Path $source 'css\styles.css') -Value 'OPEN_SOURCE_CSS' -Encoding ASCII
    Set-Content -LiteralPath (Join-Path $source 'index.html') -Value 'OPEN_SOURCE_HTML' -Encoding ASCII
    Set-Content -LiteralPath (Join-Path $source 'js\main.js') -Value 'OPEN_SOURCE_UI' -Encoding ASCII
    Set-Content -LiteralPath (Join-Path $source 'js\security.js') -Value 'OPEN_SOURCE_SECURITY' -Encoding ASCII
    Set-Content -LiteralPath (Join-Path $source 'js\caption-input.js') -Value 'OPEN_SOURCE_CAPTION_INPUT' -Encoding ASCII
    Set-Content -LiteralPath (Join-Path $source 'js\srt-join.js') -Value 'OPEN_SOURCE_SRT_JOIN' -Encoding ASCII
    foreach ($relative in @('js\notification-policy.js','js\native-notifications.js','native\PvsNotifications.exe','native\helper-lock.json','native\NotificationIdentity.cs','native\NotificationProtocol.cs','native\NotificationHost.cs','native\NotificationWindow.cs')) {
        Set-Content -LiteralPath (Join-Path $source $relative) -Value ('OPEN_SOURCE_NOTIFICATION:'+ $relative) -Encoding ASCII
    }
    Set-Content -LiteralPath (Join-Path $source 'jsx\host.jsx') -Value 'OPEN_SOURCE_HOST' -Encoding ASCII
    Set-Content -LiteralPath (Join-Path $source 'jsx\diagnostic-executor.jsx') -Value 'OPEN_SOURCE_DIAGNOSTIC' -Encoding ASCII
    foreach ($name in @('run-alignment.ps1','build-sentence-plan.ps1','build-dtw-trial-plan.ps1','build-speed-merge-trial-plan.ps1','resolve-backend.ps1','run-captions.ps1','run-workflow.ps1','request-attention.ps1')) {
        Set-Content -LiteralPath (Join-Path $source "engine\$name") -Value "OPEN_SOURCE_ENGINE:$name" -Encoding ASCII
    }
    foreach ($name in @('Srt.ps1','Alignment.ps1','ReferenceAlignment.ps1','WordMapper.ps1','Native.ps1','AudioCache.ps1','RecognitionBackend.ps1','Paths.ps1','CaptionOnly.ps1','CaptionTiming.ps1','AutoEditManualReview.ps1','AutoEditAcousticPartitions.ps1','SubtitleTiming.ps1','SubtitleEnergy.ps1','DtwEditTrial.ps1','SpeedMergeTrial.ps1','Security.ps1')) {
        Set-Content -LiteralPath (Join-Path $source "engine\lib\$name") -Value "OPEN_SOURCE_LIB:$name" -Encoding ASCII
    }
    Set-Content -LiteralPath (Join-Path $source 'engine\lib\vi-caption-phrases.txt') -Value 'fixture' -Encoding ASCII
    Set-Content -LiteralPath (Join-Path $source 'engine\lib\vi-caption-overrides.txt') -Value 'fixture' -Encoding ASCII
    Set-Content -LiteralPath (Join-Path $source 'engine\lib\vi-caption-phrases.NOTICE.txt') -Value 'fixture' -Encoding ASCII
    Set-Content -LiteralPath (Join-Path $source 'engine\lib\vi-caption-phrases.LICENSE.txt') -Value 'fixture' -Encoding ASCII
    Set-Content -LiteralPath (Join-Path $source 'engine\runtime\engine.json') -Value '{}' -Encoding ASCII
    Set-Content -LiteralPath (Join-Path $source 'engine\engine-config.json') -Value '{"model":"fixture"}' -Encoding ASCII
    foreach ($name in @('runtime-lock.json','cuda-lock.json')) { Set-Content -LiteralPath (Join-Path $source "engine\$name") -Value '{}' -Encoding ASCII }
    foreach ($name in @(
        'ffmpeg.exe','whisper-cli.exe','whisper.dll','ggml.dll','ggml-base.dll',
        'ggml-cpu-x64.dll','ggml-cpu-sse42.dll','ggml-cpu-sandybridge.dll','ggml-cpu-haswell.dll',
        'ggml-cpu-skylakex.dll','ggml-cpu-icelake.dll','ggml-cpu-cascadelake.dll',
        'ggml-cpu-cannonlake.dll','ggml-cpu-alderlake.dll','SDL2.dll','parakeet.dll'
    )) {
        Set-Content -LiteralPath (Join-Path $source "engine\runtime\bin\$name") -Value '' -Encoding ASCII
    }
    Set-Content -LiteralPath (Join-Path $source 'engine\runtime\models\ggml-large-v3-turbo.bin') -Value '' -Encoding ASCII
    # A leftover Small checkpoint in a developer runtime must not ship.
    Set-Content -LiteralPath (Join-Path $source 'engine\runtime\models\ggml-small.bin') -Value 'STALE_MODEL_MUST_NOT_SHIP' -Encoding ASCII
    foreach ($relative in @('js\.env','jsx\local-settings.json','engine\private-log.txt','engine\runtime\private-project.srt','ui\private-project.json')) {
        Set-Content -LiteralPath (Join-Path $source $relative) -Value 'PRIVATE_FIXTURE_MUST_NOT_SHIP' -Encoding ASCII
    }

    Copy-PvsReleaseExtension -Source $source -Destination $destination
    . (Join-Path $projectRoot 'installer\package-security.ps1')
    $allowed=@(Get-PvsPackageFiles)
    $pending=New-Object System.Collections.Generic.Queue[object]
    $pending.Enqueue(@{Path=$destination;Prefix='extension\'})
    while($pending.Count){
        $directory=$pending.Dequeue()
        foreach($item in (Get-ChildItem -LiteralPath $directory.Path)){
            $relative=$directory.Prefix+$item.Name
            if($item.PSIsContainer){$pending.Enqueue(@{Path=$item.FullName;Prefix=$relative+'\'})}
            elseif($relative -notin $allowed){throw "COPIED_RUNTIME_MISSING_FROM_PACKAGE_ALLOWLIST:$relative"}
        }
    }
    if ((Get-Content -LiteralPath (Join-Path $destination 'engine\runtime\engine.json') -Raw).Trim() -ne '{"model":"fixture"}') { throw 'RELEASE_COPIED_LOCAL_CONFIGURATION' }
    foreach ($relative in @(
        'js\main.js','js\caption-input.js','jsx\host.jsx',
        'engine\run-alignment.ps1','engine\build-sentence-plan.ps1','engine\resolve-backend.ps1',
        'engine\run-captions.ps1','engine\run-workflow.ps1','engine\request-attention.ps1','engine\lib\CaptionOnly.ps1','engine\lib\CaptionTiming.ps1','engine\lib\RecognitionBackend.ps1',
        'engine\lib\SubtitleTiming.ps1','engine\lib\SubtitleEnergy.ps1','engine\lib\AutoEditManualReview.ps1','engine\lib\AutoEditAcousticPartitions.ps1',
        'engine\build-dtw-trial-plan.ps1','engine\lib\DtwEditTrial.ps1',
        'engine\build-speed-merge-trial-plan.ps1','engine\lib\SpeedMergeTrial.ps1',
        'jsx\diagnostic-executor.jsx',
        'engine\lib\Srt.ps1','engine\lib\Alignment.ps1','engine\lib\Native.ps1','engine\lib\AudioCache.ps1','engine\lib\Paths.ps1',
        'engine\lib\WordMapper.ps1','engine\lib\ReferenceAlignment.ps1',
        'engine\lib\vi-caption-phrases.txt','engine\lib\vi-caption-overrides.txt',
        'engine\lib\vi-caption-phrases.NOTICE.txt',
        'engine\lib\vi-caption-phrases.LICENSE.txt'
    )) {
        $sourcePath = Join-Path $source $relative
        $releasePath = Join-Path $destination $relative
        if (-not (Test-Path -LiteralPath $releasePath -PathType Leaf)) { throw "OPEN_SOURCE_FILE_MISSING:$relative" }
        $sourceHash = (Get-FileHash -LiteralPath $sourcePath -Algorithm SHA256).Hash
        $releaseHash = (Get-FileHash -LiteralPath $releasePath -Algorithm SHA256).Hash
        if ($sourceHash -ne $releaseHash) { throw "OPEN_SOURCE_FILE_CHANGED:$relative" }
    }
    foreach ($payload in @('js\main.pvsbin','jsx\host.pvsbin','engine\engine.pvsbin')) {
        if (Test-Path -LiteralPath (Join-Path $destination $payload)) { throw "PROTECTED_PAYLOAD_COPIED:$payload" }
    }
    foreach ($relative in @('js\.env','jsx\local-settings.json','engine\private-log.txt','engine\runtime\private-project.srt','ui\private-project.json')) {
        if (Test-Path -LiteralPath (Join-Path $destination $relative)) { throw "PRIVATE_FIXTURE_COPIED:$relative" }
    }
    Write-Host 'OPEN_SOURCE_RELEASE_OK'
}
finally {
    if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Recurse -Force }
}
