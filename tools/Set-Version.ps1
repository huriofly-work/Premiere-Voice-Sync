param(
    [Parameter(Mandatory = $true)][string]$Version,
    [switch]$Check,
    [string]$Root
)

# Updates or checks every embedded version string that must match VERSION.
# CHANGELOG, release notes and docs/releases/<version>.json stay manual.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

if (-not $Root) { $Root = Join-Path $PSScriptRoot '..' }
$Root = (Resolve-Path -LiteralPath $Root).Path
if ($Version -notmatch '^\d+\.\d+\.\d+$') { throw "SET_VERSION_INVALID:$Version" }

$v = '(\d+\.\d+\.\d+)'
$targets = @(
    @{ Path = 'VERSION'; Pattern = '^' + $v + '(?=\s*$)' },
    @{ Path = 'extension\CSXS\manifest.xml'; Pattern = 'ExtensionBundleVersion="' + $v + '"' },
    @{ Path = 'extension\CSXS\manifest.xml'; Pattern = '<Extension Id="com\.premierevoicesync\.local\.panel" Version="' + $v + '"' },
    @{ Path = 'extension\index.html'; Pattern = '<span class="version">' + $v + '</span>' },
    @{ Path = 'extension\js\main.js'; Pattern = 'var toolVersion = "' + $v + '";' },
    @{ Path = 'installer\build-release.ps1'; Pattern = "param\(\[string\]\`$Version = '" + $v + "'\)" },
    @{ Path = 'tests\unit\Test-RepositoryLayout.ps1'; Pattern = "if \(\`$version -ne '" + $v + "'\)" },
    @{ Path = 'docs\ARCHITECTURE.md'; Pattern = '\(b' + [char]0x1EA3 + 'n m' + [char]0x1EDB + 'i nh' + [char]0x1EA5 + 't ' + $v + ',' },
    @{ Path = 'docs\MAINTAINER_BRIEFING.md'; Pattern = $v + ', last stable the user tested' },
    @{ Path = 'docs\USER_GUIDE.md'; Pattern = '(?m)^# H' + [char]0x01B0 + [char]0x1EDB + 'ng d' + [char]0x1EAB + 'n Premiere Voice Sync ' + $v }
)

$utf8 = New-Object Text.UTF8Encoding $false
$files = @{}
$problems = @()
$report = @()
foreach ($target in $targets) {
    $path = Join-Path $Root $target.Path
    if (-not $files.ContainsKey($path)) {
        if (-not (Test-Path -LiteralPath $path)) { $problems += "missing file $($target.Path)"; continue }
        $bytes = [IO.File]::ReadAllBytes($path)
        $bom = $bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF
        $offset = 0
        if ($bom) { $offset = 3 }
        $files[$path] = @{ Text = $utf8.GetString($bytes, $offset, $bytes.Length - $offset); Bom = $bom; Changed = $false; Relative = $target.Path }
    }
    $file = $files[$path]
    $found = [regex]::Matches($file.Text, $target.Pattern)
    if ($found.Count -ne 1) { $problems += "$($target.Path): expected 1 match, found $($found.Count)"; continue }
    $group = $found[0].Groups[1]
    $report += "$($target.Path)=$($group.Value)"
    if ($group.Value -ne $Version) {
        if ($Check) { $problems += "$($target.Path): $($group.Value) differs from $Version"; continue }
        $file.Text = $file.Text.Substring(0, $group.Index) + $Version + $file.Text.Substring($group.Index + $group.Length)
        $file.Changed = $true
    }
}

if (-not $Check -and -not $problems.Count) {
    $current = (($report | Where-Object { $_ -like 'VERSION=*' }) -replace '^VERSION=', '')
    if ([version]$Version -lt [version]$current) { $problems += "refusing to lower $current to $Version" }
}
if ($problems.Count) {
    foreach ($problem in $problems) { Write-Host "SET_VERSION_PROBLEM:$problem" }
    throw "SET_VERSION_FAILED:$($problems.Count)"
}
if ($Check) {
    Write-Host "SET_VERSION_CHECK_OK:version=$Version;targets=$($targets.Count)"
    return
}

# Every target matched before any write, so a missing pattern never leaves a half-updated tree.
$written = 0
foreach ($file in $files.Values) {
    if (-not $file.Changed) { continue }
    $body = $utf8.GetBytes($file.Text)
    if ($file.Bom) { $body = [byte[]](@(0xEF, 0xBB, 0xBF) + $body) }
    [IO.File]::WriteAllBytes((Join-Path $Root $file.Relative), $body)
    $written++
}
Write-Host "SET_VERSION_OK:version=$Version;targets=$($targets.Count);filesWritten=$written"
Write-Host 'SET_VERSION_MANUAL:CHANGELOG.md, docs/releases/<version>.json, release notes, README/docs status text'
