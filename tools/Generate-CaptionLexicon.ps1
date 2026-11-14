param([Parameter(Mandatory)][string]$VnVocabPath)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

# VnVocab is the Java-serialized UTF-8 vocabulary distributed by RDRsegmenter.
# The pinned source is https://github.com/datquocnguyen/RDRsegmenter (Apache-2.0).
$expectedHash = '0A47C5B55BBCE163029D37730A67B9479740388695C29C106C112B815613EAA5'
if ((Get-FileHash -LiteralPath $VnVocabPath -Algorithm SHA256).Hash -ne $expectedHash) {
    throw 'CAPTION_VOCAB_SOURCE_HASH_CHANGED'
}
$bytes = [IO.File]::ReadAllBytes($VnVocabPath)
$pairs = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
for ($index = 0; $index -lt $bytes.Length - 3; $index++) {
    if ($bytes[$index] -ne 0x74) { continue }
    $length = ([int]$bytes[$index + 1] * 256) + [int]$bytes[$index + 2]
    if ($length -lt 2 -or $length -gt 120 -or $index + 3 + $length -gt $bytes.Length) { continue }
    $entry = [Text.Encoding]::UTF8.GetString($bytes, $index + 3, $length)
    if ($entry -notmatch '^[\p{L}\p{M}\p{N}]+ [\p{L}\p{M}\p{N}]+$') { continue }
    [void]$pairs.Add($entry.ToLowerInvariant().Normalize([Text.NormalizationForm]::FormC))
    $index += $length + 2
}
$destination = Join-Path (Split-Path $PSScriptRoot -Parent) 'extension\engine\lib\vi-caption-phrases.txt'
$ordered = @($pairs | Sort-Object -Culture 'vi-VN')
[IO.File]::WriteAllLines($destination, $ordered, [Text.UTF8Encoding]::new($false))
Write-Host "CAPTION_LEXICON_READY:$($ordered.Count):$destination"
