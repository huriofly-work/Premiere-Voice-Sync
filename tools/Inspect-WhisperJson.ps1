param(
    [Parameter(Mandatory)][string]$JsonPath,
    [int]$ChapterIndex = 0
)

$ErrorActionPreference = 'Stop'
$projectRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
. (Join-Path $projectRoot 'extension\engine\lib\Srt.ps1')
. (Join-Path $projectRoot 'extension\engine\lib\Alignment.ps1')
$json = Get-Item -LiteralPath $JsonPath -ErrorAction Stop
$words = @(Convert-WhisperJsonToWords -Path $json.FullName -ChapterIndex $ChapterIndex)
Write-Host "WHISPER_JSON_OK words=$($words.Count)"
