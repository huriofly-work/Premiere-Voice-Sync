param([Parameter(Mandatory)][string]$SampleRoot)

$ErrorActionPreference = 'Stop'
$projectRoot = Resolve-Path (Join-Path $PSScriptRoot '..\..')
$engineRoot = Join-Path $projectRoot 'extension\engine'
$sampleRoot = (Resolve-Path $SampleRoot).Path
$voiceFolder = Join-Path $sampleRoot 'Voice'
$scriptFolder = Join-Path $sampleRoot 'Script'
$output = Join-Path $sampleRoot 'PremiereVoiceSync-Engine-Test'
New-Item -ItemType Directory -Path $output -Force | Out-Null

$runtime = Get-Content -LiteralPath (Join-Path $engineRoot 'runtime\engine.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$ffprobe = Join-Path $engineRoot 'runtime\bin\ffprobe.exe'
if (-not (Test-Path -LiteralPath $ffprobe -PathType Leaf)) { throw 'Manual sample requires runtime\bin\ffprobe.exe. Run tools\setup-engine.ps1 first.' }
$voiceFiles = @(Get-ChildItem -LiteralPath $voiceFolder -Filter '*.mp3' | Sort-Object { if ($_.BaseName -match '(\d+)$') { [int]$Matches[1] } else { 0 } })
$voices = @()
$cursor = 0.0
for ($i = 0; $i -lt $voiceFiles.Count; $i++) {
    $durationText = & $ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 $voiceFiles[$i].FullName
    $duration = [double]::Parse($durationText.Trim(), [Globalization.CultureInfo]::InvariantCulture)
    $voices += [pscustomobject]@{ index=$i; name=$voiceFiles[$i].Name; path=$voiceFiles[$i].FullName; start=$cursor; end=$cursor+$duration; duration=$duration }
    $cursor += $duration
}

$sourceSrt = Get-ChildItem -LiteralPath $scriptFolder -Filter '*.srt' | Where-Object Name -NotMatch 'Vietnamese' | Select-Object -First 1
$targetSrt = Get-ChildItem -LiteralPath $scriptFolder -Filter '*.srt' | Where-Object Name -Match 'Vietnamese' | Select-Object -First 1
$job = [ordered]@{
    schemaVersion = 1
    sourceSrtPath = $sourceSrt.FullName
    targetSrtPath = $targetSrt.FullName
    outputFolder = $output
    minSpeedPercent = 70
    maxSpeedPercent = 130
    sequence = @{ name='Engine sample'; voices=$voices }
}
$jobPath = Join-Path $output 'job.json'
$job | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $jobPath -Encoding UTF8
& (Join-Path $engineRoot 'run-alignment.ps1') -JobPath $jobPath
