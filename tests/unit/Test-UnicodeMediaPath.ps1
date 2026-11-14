$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$projectRoot = Resolve-Path (Join-Path $PSScriptRoot '..\..')
. (Join-Path $projectRoot 'extension\engine\lib\Paths.ps1')

$root = Join-Path $env:TEMP ("PVS-UnicodePath-{0}" -f ([guid]::NewGuid().ToString('N')))
try {
    New-Item -ItemType Directory -Path $root -Force | Out-Null
    $unicodeName = 'Ki' + [char]0x1EBF + 'n th' + [char]0x1EE9 + 'c - N' + [char]0x1EBF + 'u Spinosaurus ' + [char]0x1EDF + ' ' + [char]0x0111 + [char]0x1EA7 + 'm l' + [char]0x1EA7 + 'y Florida.mp3'
    $unicodePath = Join-Path $root $unicodeName
    Set-Content -LiteralPath $unicodePath -Value 'test' -Encoding ASCII

    $resolvedUnicode = Resolve-PvsExistingPath -Path $unicodePath -Purpose 'Unicode test'
    if ($resolvedUnicode -ne (Resolve-Path -LiteralPath $unicodePath).Path) {
        throw 'UNICODE_EXISTING_PATH_WAS_CHANGED'
    }

    $mojibakePath = [Text.Encoding]::GetEncoding(1252).GetString(
        [Text.Encoding]::UTF8.GetBytes($unicodePath)
    )
    $resolvedMojibake = Resolve-PvsExistingPath -Path $mojibakePath -Purpose 'Mojibake test'
    if ($resolvedMojibake -ne (Resolve-Path -LiteralPath $unicodePath).Path) {
        throw 'MOJIBAKE_PATH_WAS_NOT_RECOVERED'
    }

    $missingFailed = $false
    try {
        Resolve-PvsExistingPath -Path (Join-Path $root 'missing.mp3') -Purpose 'Missing test' | Out-Null
    }
    catch {
        $missingFailed = $_.Exception.Message -like 'MEDIA_PATH_NOT_FOUND:*'
    }
    if (-not $missingFailed) { throw 'MISSING_PATH_DID_NOT_FAIL_FAST' }

    Write-Host 'UNICODE_MEDIA_PATH_OK'
}
finally {
    if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force }
}
