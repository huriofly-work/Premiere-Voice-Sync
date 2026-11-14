param([string]$Version = '2.20.90')

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. "$PSScriptRoot\release-common.ps1"
. "$PSScriptRoot\package-security.ps1"

$projectRoot = Split-Path $PSScriptRoot -Parent
if ($Version -ne (Get-Content -LiteralPath (Join-Path $projectRoot 'VERSION') -Raw).Trim()) { throw 'Build version does not match VERSION.' }
$source = Join-Path $projectRoot 'extension'
Assert-PvsRuntimeLock -EngineRoot (Join-Path $source 'engine')
$distRoot = Join-Path $projectRoot 'dist'
$packageName = "Premiere-Voice-Sync-$Version-Panel"
$staging = Join-Path $distRoot $packageName
$zipPath = Join-Path $distRoot "$packageName.zip"

$distFull = [IO.Path]::GetFullPath($distRoot).TrimEnd('\') + '\'
$stagingFull = [IO.Path]::GetFullPath($staging)
$zipFull = [IO.Path]::GetFullPath($zipPath)
if (-not $stagingFull.StartsWith($distFull, [StringComparison]::OrdinalIgnoreCase)) { throw 'Unsafe staging path.' }
if (-not $zipFull.StartsWith($distFull, [StringComparison]::OrdinalIgnoreCase)) { throw 'Unsafe zip path.' }
foreach ($path in @($distRoot,$staging,$zipPath)) {
    Assert-PvsSafePath -Path $path -Tree
    if ((Test-Path -LiteralPath $path) -and ((Get-Item -LiteralPath $path -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        throw "Unsafe linked build path: $path"
    }
}

New-Item -ItemType Directory -Path $distRoot -Force | Out-Null
if (Test-Path -LiteralPath $staging) { Remove-Item -LiteralPath $staging -Recurse -Force }
if (Test-Path -LiteralPath $zipPath) { Remove-Item -LiteralPath $zipPath -Force }
New-Item -ItemType Directory -Path $staging -Force | Out-Null

& (Join-Path $PSScriptRoot 'build-notifications.ps1')
Copy-PvsReleaseExtension -Source $source -Destination (Join-Path $staging 'extension')
New-Item -ItemType Directory -Path (Join-Path $staging 'scripts') -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'install.ps1') -Destination (Join-Path $staging 'scripts') -Force
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'uninstall.ps1') -Destination (Join-Path $staging 'scripts') -Force
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'package-security.ps1') -Destination (Join-Path $staging 'scripts') -Force
$commands = @('Setup-Panel.cmd','Remove-Panel.cmd')
foreach ($command in $commands) {
    Copy-Item -LiteralPath (Join-Path $projectRoot $command) -Destination $staging -Force
}
# Third-party runtime (FFmpeg GPL v3, whisper.cpp/ggml, SDL2, model) ships with its notices.
Copy-Item -LiteralPath (Join-Path $projectRoot 'THIRD_PARTY_NOTICES.md') -Destination $staging -Force
# GPL v3 requires its full text to accompany the FFmpeg binary.
New-Item -ItemType Directory -Path (Join-Path $staging 'licenses') -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $projectRoot 'licenses\GPL-3.0.txt') -Destination (Join-Path $staging 'licenses') -Force
$readme=[IO.File]::ReadAllText((Join-Path $projectRoot 'README.md'),[Text.Encoding]::UTF8)
$guide=[IO.File]::ReadAllText((Join-Path $projectRoot 'docs\USER_GUIDE.md'),[Text.Encoding]::UTF8)
# Keep the notification/test handoff readable inside the standalone ZIP.
[IO.File]::WriteAllText((Join-Path $staging 'README.md'),($readme -replace '\(docs/releases/notes/(?:ASR_TURBO_|AUTO_EDIT_ACOUSTIC_|NOTIFICATIONS_|SUBTITLE_TIMING_|REVIEW_MARKERS_|SRT_PRIORITY_|EDITED_VOICE_|SRT_JOIN_)\d+\.\d+\.\d+\.md\)','(THONG_BAO.md)'),(New-Object Text.UTF8Encoding($false)))
[IO.File]::WriteAllText((Join-Path $staging 'HUONG_DAN_SU_DUNG.md'),($guide -replace '\(releases/notes/(?:ASR_TURBO_|AUTO_EDIT_ACOUSTIC_|NOTIFICATIONS_|SUBTITLE_TIMING_|REVIEW_MARKERS_|SRT_PRIORITY_|EDITED_VOICE_|SRT_JOIN_)\d+\.\d+\.\d+\.md\)','(THONG_BAO.md)'),(New-Object Text.UTF8Encoding($false)))
$handoff=Join-Path $projectRoot "docs\releases\notes\AUTO_EDIT_ACOUSTIC_$Version.md"
if(-not (Test-Path -LiteralPath $handoff)){$handoff=Join-Path $projectRoot "docs\releases\notes\SRT_JOIN_$Version.md"}
if(-not (Test-Path -LiteralPath $handoff)){$handoff=Join-Path $projectRoot "docs\releases\notes\EDITED_VOICE_$Version.md"}
if(-not (Test-Path -LiteralPath $handoff)){$handoff=Join-Path $projectRoot "docs\releases\notes\SRT_PRIORITY_$Version.md"}
if(-not (Test-Path -LiteralPath $handoff)){$handoff=Join-Path $projectRoot "docs\releases\notes\REVIEW_MARKERS_$Version.md"}
if(-not (Test-Path -LiteralPath $handoff)){$handoff=Join-Path $projectRoot "docs\releases\notes\SUBTITLE_TIMING_$Version.md"}
if(-not (Test-Path -LiteralPath $handoff)){$handoff=Join-Path $projectRoot "docs\releases\notes\NOTIFICATIONS_$Version.md"}
if(-not (Test-Path -LiteralPath $handoff)){$handoff=Join-Path $projectRoot "docs\releases\notes\ASR_TURBO_$Version.md"}
Copy-Item -LiteralPath $handoff -Destination (Join-Path $staging 'THONG_BAO.md') -Force

$required = @(
    'extension\js\srt-join.js',
    'extension\CSXS\manifest.xml', 'extension\index.html', 'extension\js\main.js', 'extension\js\caption-input.js',
    'extension\jsx\host.jsx', 'extension\jsx\diagnostic-executor.jsx',
    'extension\engine\run-alignment.ps1', 'extension\engine\build-sentence-plan.ps1', 'extension\engine\resolve-backend.ps1',
    'extension\engine\run-captions.ps1', 'extension\engine\run-workflow.ps1', 'extension\engine\request-attention.ps1', 'extension\engine\lib\CaptionOnly.ps1',
    'extension\engine\build-dtw-trial-plan.ps1', 'extension\engine\lib\DtwEditTrial.ps1',
    'extension\engine\build-speed-merge-trial-plan.ps1', 'extension\engine\lib\SpeedMergeTrial.ps1',
    'extension\engine\lib\CaptionTiming.ps1',
    'extension\engine\lib\AutoEditManualReview.ps1',
    'extension\engine\lib\AutoEditAcousticPartitions.ps1',
    'extension\engine\lib\RecognitionBackend.ps1',
    'extension\engine\lib\SubtitleTiming.ps1',
    'extension\engine\lib\SubtitleEnergy.ps1',
    'extension\engine\lib\Srt.ps1', 'extension\engine\lib\Alignment.ps1',
    'extension\engine\lib\ReferenceAlignment.ps1',
    'extension\engine\lib\WordMapper.ps1',
    'extension\engine\lib\Native.ps1', 'extension\engine\lib\Paths.ps1',
    'extension\engine\lib\AudioCache.ps1',
    'extension\engine\lib\vi-caption-phrases.txt', 'extension\engine\lib\vi-caption-overrides.txt',
    'extension\engine\lib\vi-caption-phrases.NOTICE.txt',
    'extension\engine\lib\vi-caption-phrases.LICENSE.txt',
    'extension\engine\runtime\bin\ffmpeg.exe', 'extension\engine\runtime\bin\whisper-cli.exe',
    'extension\engine\runtime\models\ggml-large-v3-turbo.bin',
    'scripts\install.ps1', 'scripts\uninstall.ps1',
    'THIRD_PARTY_NOTICES.md', 'licenses\GPL-3.0.txt'
)
$required += $commands
foreach ($relative in $required) {
    if (-not (Test-Path -LiteralPath (Join-Path $staging $relative) -PathType Leaf)) { throw "Release missing: $relative" }
}

foreach ($forbiddenPayload in @(
    'extension\js\main.pvsbin',
    'extension\jsx\host.pvsbin',
    'extension\engine\engine.pvsbin'
)) {
    if (Test-Path -LiteralPath (Join-Path $staging $forbiddenPayload)) { throw "Release still contains protected payload: $forbiddenPayload" }
}

$hashLines = Get-ChildItem -LiteralPath $staging -File -Recurse | Sort-Object FullName | ForEach-Object {
    $relative = $_.FullName.Substring($staging.Length + 1)
    $hash = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash
    "$hash  $relative"
}
$hashLines | Set-Content -LiteralPath (Join-Path $staging 'SHA256SUMS.txt') -Encoding ASCII
Assert-PvsPackage -Root $staging | Out-Null

Compress-Archive -Path $staging -DestinationPath $zipPath -CompressionLevel Optimal
$zipHash = (Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash
$zipSumPath = "$zipPath.sha256"
"$zipHash  $([IO.Path]::GetFileName($zipPath))" | Set-Content -LiteralPath $zipSumPath -Encoding ASCII
$sizeMb = [Math]::Round((Get-Item -LiteralPath $zipPath).Length / 1MB, 2)
Write-Host "RELEASE_READY:$zipPath"
Write-Host "SIZE_MB:$sizeMb"
Write-Host "SHA256:$zipHash"
