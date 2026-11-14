param([switch]$FreshLocalData)
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$root=Resolve-Path (Join-Path $PSScriptRoot '..\..')
. "$root\extension\engine\lib\Srt.ps1"
. "$root\extension\engine\lib\CaptionOnly.ps1"
$folder=Join-Path $env:TEMP ('PVS-StandaloneSmoke-'+[guid]::NewGuid().ToString('N'))
$previousLocalData=$env:LOCALAPPDATA
try {
    New-Item -ItemType Directory -Path $folder -Force | Out-Null
    if ($FreshLocalData) { $env:LOCALAPPDATA=Join-Path $folder 'fresh-local-data' }
    Add-Type -AssemblyName System.Speech
    $synth=New-Object System.Speech.Synthesis.SpeechSynthesizer
    try {
        $voice=@($synth.GetInstalledVoices() | Where-Object {$_.VoiceInfo.Culture.Name -like 'en-*'} | Select-Object -First 1)
        if ($voice.Count -eq 0) { throw 'No offline English Windows voice for synthetic media test.' }
        $synth.SelectVoice($voice[0].VoiceInfo.Name)
        $synth.SetOutputToWaveFile((Join-Path $folder 'speech.wav'))
        $synth.Speak('Hello. This is a subtitle test. The video stays in place.')
    } finally { $synth.Dispose() }
    $duration=Get-PvsPcmWaveDuration -Path (Join-Path $folder 'speech.wav')
    $job=[ordered]@{schemaVersion=1;workflow='caption-only';sequenceId='synthetic';snapshot='unchanged';frameRate=30;language='en';maxCaptionCharacters=42;targetSrtPath='';outputFolder=$folder;sources=@([ordered]@{start=10.0;end=10.0+$duration;path=(Join-Path $folder 'speech.wav')})}
    $jobPath=Join-Path $folder 'job.json'
    $job | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $jobPath -Encoding UTF8
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$root\extension\engine\run-captions.ps1" -JobPath $jobPath
    if ($LASTEXITCODE -ne 0) { throw 'STANDALONE_NATIVE_PIPELINE_FAILED' }
    $result=Get-Content -LiteralPath (Join-Path $folder 'caption-result.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $captions=@(Read-SrtFile $result.captionSrtPath)
    if ($captions.Count -lt 2 -or $captions[0].Start -lt 10 -or $captions[$captions.Count-1].End -gt 10.0+$duration+0.001) { throw 'STANDALONE_NATIVE_OUTPUT_INVALID' }
    Write-Host ("STANDALONE_NATIVE_OK:backend={0};captions={1}" -f $result.recognitionBackendLabel,$captions.Count)
    $captions | Select-Object Start,End,Text | Format-Table -AutoSize
    $referencePath=Join-Path $folder 'reference.srt'
    $referenceText='Hello. This is a subtitle test. The video stays in place.'
    Write-SrtFile -Cues @([pscustomobject]@{Start=100;End=200;Text=$referenceText}) -Path $referencePath
    $job.targetSrtPath=$referencePath
    $job | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $jobPath -Encoding UTF8
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$root\extension\engine\run-captions.ps1" -JobPath $jobPath
    if ($LASTEXITCODE -ne 0) { throw 'STANDALONE_REFERENCE_PIPELINE_FAILED' }
    $result=Get-Content -LiteralPath (Join-Path $folder 'caption-result.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $captions=@(Read-SrtFile $result.captionSrtPath)
    if (($captions.Text -join ' ') -ne $referenceText -or $captions[0].Start -ge 100) { throw 'STANDALONE_REFERENCE_CONTENT_OR_TIMING_FAILED' }
    Write-Host 'STANDALONE_REFERENCE_NATIVE_OK:preserved-reference-text;retimed-from-audio'
    if ($FreshLocalData) {
        if ($result.recognitionBackend -ne 'cpu') { throw 'FRESH_DATA_UNEXPECTED_GPU' }
        if (Test-Path -LiteralPath (Join-Path $env:LOCALAPPDATA 'PremiereVoiceSync\downloads')) { throw 'FRESH_DATA_BACKGROUND_DOWNLOAD' }
        # A fake, invalid GPU executable must never be launched, and must fall back to CPU.
        $invalidRoot=Join-Path $env:LOCALAPPDATA 'PremiereVoiceSync\Backends\whisper-1.9.1-cuda-12.4.0'
        New-Item -ItemType Directory -Path $invalidRoot -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $invalidRoot 'whisper-cli.exe') -Value 'NOT_AN_EXECUTABLE'
        $backend=(& "$root\extension\engine\resolve-backend.ps1" | Out-String).Trim() | ConvertFrom-Json
        if ($backend.backend -ne 'cpu') { throw 'INVALID_GPU_EXECUTED' }
        if ($backend.gpuName -and $backend.reason -notmatch 'kiem tra toan ven') { throw 'INVALID_GPU_REASON_MISSING' }
        Write-Host 'FRESH_CPU_AND_INVALID_GPU_OK:no-download;invalid-binary-not-executed'
    }
} finally {
    $env:LOCALAPPDATA=$previousLocalData
    if (Test-Path -LiteralPath $folder) { Remove-Item -LiteralPath $folder -Recurse -Force }
}
