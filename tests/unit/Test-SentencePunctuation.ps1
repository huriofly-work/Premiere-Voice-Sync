$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$projectRoot = Resolve-Path (Join-Path $PSScriptRoot '..\..')
$sourceEngineRoot = Join-Path $projectRoot 'extension\engine'
$temp = Join-Path $env:TEMP ('PVS-Punctuation-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $temp -Force | Out-Null
try {
    $testEngineRoot = Join-Path $temp 'engine'
    New-Item -ItemType Directory -Path (Join-Path $testEngineRoot 'lib'),(Join-Path $testEngineRoot 'runtime') -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $sourceEngineRoot 'build-sentence-plan.ps1') -Destination $testEngineRoot
    Copy-Item -LiteralPath (Join-Path $sourceEngineRoot 'lib\Srt.ps1') -Destination (Join-Path $testEngineRoot 'lib')
    Copy-Item -LiteralPath (Join-Path $sourceEngineRoot 'lib\ReferenceAlignment.ps1') -Destination (Join-Path $testEngineRoot 'lib')
    Copy-Item -LiteralPath (Join-Path $sourceEngineRoot 'lib\CaptionTiming.ps1') -Destination (Join-Path $testEngineRoot 'lib')
    Copy-Item -LiteralPath (Join-Path $sourceEngineRoot 'lib\AutoEditAcousticPartitions.ps1') -Destination (Join-Path $testEngineRoot 'lib')
    Copy-Item -LiteralPath (Join-Path $sourceEngineRoot 'lib\AutoEditManualReview.ps1') -Destination (Join-Path $testEngineRoot 'lib')
    Copy-Item -LiteralPath (Join-Path $sourceEngineRoot 'lib\RecognitionBackend.ps1') -Destination (Join-Path $testEngineRoot 'lib')
    Copy-Item -LiteralPath (Join-Path $sourceEngineRoot 'lib\SubtitleTiming.ps1') -Destination (Join-Path $testEngineRoot 'lib')
    Copy-Item -LiteralPath (Join-Path $sourceEngineRoot 'lib\SubtitleEnergy.ps1') -Destination (Join-Path $testEngineRoot 'lib')
    Copy-Item -LiteralPath (Join-Path $sourceEngineRoot 'lib\vi-caption-phrases.txt') -Destination (Join-Path $testEngineRoot 'lib')
    Copy-Item -LiteralPath (Join-Path $sourceEngineRoot 'lib\vi-caption-overrides.txt') -Destination (Join-Path $testEngineRoot 'lib')
    Copy-Item -LiteralPath (Join-Path $sourceEngineRoot 'lib\Paths.ps1') -Destination (Join-Path $testEngineRoot 'lib')
    foreach($name in @('Security.ps1','AudioCache.ps1')){Copy-Item -LiteralPath (Join-Path $sourceEngineRoot "lib\$name") -Destination (Join-Path $testEngineRoot 'lib')}
    foreach($name in @('runtime-lock.json','cuda-lock.json')){Copy-Item -LiteralPath (Join-Path $sourceEngineRoot $name) -Destination $testEngineRoot}
    Set-Content -LiteralPath (Join-Path $testEngineRoot 'lib\Native.ps1') -Value '. "$PSScriptRoot\Security.ps1"; . "$PSScriptRoot\AudioCache.ps1"; function Invoke-NativeCapture {param($FilePath,$Arguments);[pscustomobject]@{ExitCode=0;Output=""}}' -Encoding ASCII
    Set-Content -LiteralPath (Join-Path $testEngineRoot 'runtime\fake-ffmpeg.ps1') -Value '# no detected silence' -Encoding ASCII
    '{"ffmpeg":"fake-ffmpeg.ps1"}' | Set-Content -LiteralPath (Join-Path $testEngineRoot 'runtime\engine.json') -Encoding ASCII
    $planner = Join-Path $testEngineRoot 'build-sentence-plan.ps1'
    Set-Content -LiteralPath (Join-Path $temp 'missing.wav') -Value '' -Encoding ASCII
    $alignment = [ordered]@{
        voiceChapterCount = 1
        cues = @(
            [ordered]@{ Index=1;Text='Cau mot;';Start=0.0;End=1.0;OriginalStart=0.0;OriginalEnd=1.0;Chapter=0;Confidence=1.0 },
            [ordered]@{ Index=2;Text='Cau hai,';Start=1.0;End=2.0;OriginalStart=1.0;OriginalEnd=2.0;Chapter=0;Confidence=1.0 },
            [ordered]@{ Index=3;Text='tiep tuc.';Start=2.0;End=3.0;OriginalStart=2.0;OriginalEnd=3.0;Chapter=0;Confidence=1.0 }
        )
    }
    $alignment | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $temp 'alignment-result.json') -Encoding UTF8
    $job = [ordered]@{
        algorithm=[ordered]@{useWhisperCache=$false}
        outputFolder = $temp
        speedWarningMinPercent = 80
        speedWarningMaxPercent = 120
        sequence = [ordered]@{
            sequenceId='punctuation-test';name='punctuation-test';frameRate=30
            mainVideoClip=[ordered]@{start=0;end=3}
            linkedAudio=@()
            voiceTrackIndex=1
            voices=@([ordered]@{name='missing.wav';path=(Join-Path $temp 'missing.wav');start=0;end=3;speedPercent=100})
        }
    }
    $jobPath = Join-Path $temp 'job.json'
    $job | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $jobPath -Encoding UTF8
    & $planner -JobPath $jobPath | Out-Null
    $plan = Get-Content -LiteralPath (Join-Path $temp 'sentence-edit-plan.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    if ([string]$plan.settings.sentenceEndCharacters -ne '.?!;') { throw 'DEFAULT_SENTENCE_END_CHARACTERS_FAILED' }
    if ([int]$plan.summary.punctuationSentenceCount -ne 2) { throw "SEMICOLON_SENTENCE_SPLIT_FAILED:$($plan.summary.punctuationSentenceCount)" }
    Write-Host 'SENTENCE_PUNCTUATION_OK'
}
finally {
    if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Recurse -Force }
}
