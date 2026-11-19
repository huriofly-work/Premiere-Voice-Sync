$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$script = Join-Path $projectRoot 'tools\Set-Version.ps1'
$current = (Get-Content -LiteralPath (Join-Path $projectRoot 'VERSION') -Raw -Encoding UTF8).Trim()
$relative = @('VERSION', 'extension\CSXS\manifest.xml', 'extension\index.html', 'extension\js\main.js',
    'installer\build-release.ps1', 'tests\unit\Test-RepositoryLayout.ps1', 'docs\ARCHITECTURE.md',
    'docs\MAINTAINER_BRIEFING.md', 'docs\USER_GUIDE.md')

function Invoke-SetVersion([string[]]$Arguments) {
    # Expected failures write to stderr; keep them as output instead of stopping the test.
    $ErrorActionPreference = 'Continue'
    $output =& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $script @Arguments 2>&1 | Out-String
    return @{ Code = $LASTEXITCODE; Output = $output }
}
function New-Fixture {
    $root = Join-Path ([IO.Path]::GetTempPath()) ('pvs-set-version-' + [guid]::NewGuid().ToString('N'))
    foreach ($path in $relative) {
        $target = Join-Path $root $path
        New-Item -ItemType Directory -Force -Path (Split-Path $target) | Out-Null
        [IO.File]::WriteAllBytes($target, [IO.File]::ReadAllBytes((Join-Path $projectRoot $path)))
    }
    return $root
}
function Get-Hashes([string]$Root) {
    $result = @{}
    foreach ($path in $relative) { $result[$path] = (Get-FileHash -LiteralPath (Join-Path $Root $path) -Algorithm SHA256).Hash }
    return $result
}

# The real tree keeps every embedded version in step with VERSION.
$real = Invoke-SetVersion @('-Version', $current, '-Check')
if ($real.Code -ne 0 -or $real.Output -notmatch 'SET_VERSION_CHECK_OK') { throw "SET_VERSION_REAL_TREE_MISMATCH:$($real.Output)" }

$parts = $current.Split('.')
$next = $parts[0] + '.' + $parts[1] + '.' + ([int]$parts[2] + 1)
$fixture = New-Fixture
try {
    $layout = Join-Path $fixture 'tests\unit\Test-RepositoryLayout.ps1'
    $buildScript = Join-Path $fixture 'installer\build-release.ps1'
    $layoutBom = [IO.File]::ReadAllBytes($layout)[0] -eq 0xEF
    $buildCrlf = [IO.File]::ReadAllText($buildScript).Contains("`r`n")

    $wrong = Invoke-SetVersion @('-Version', $next, '-Check', '-Root', $fixture)
    if ($wrong.Code -eq 0 -or $wrong.Output -notmatch 'differs from') { throw 'SET_VERSION_CHECK_MISSED_MISMATCH' }

    $lower = Invoke-SetVersion @('-Version', '0.0.1', '-Root', $fixture)
    if ($lower.Code -eq 0 -or $lower.Output -notmatch 'refusing to lower') { throw 'SET_VERSION_ALLOWED_DOWNGRADE' }

    $set = Invoke-SetVersion @('-Version', $next, '-Root', $fixture)
    if ($set.Code -ne 0 -or $set.Output -notmatch 'SET_VERSION_OK') { throw "SET_VERSION_FAILED:$($set.Output)" }
    $after = Invoke-SetVersion @('-Version', $next, '-Check', '-Root', $fixture)
    if ($after.Code -ne 0) { throw "SET_VERSION_NOT_APPLIED:$($after.Output)" }
    foreach ($path in $relative) {
        $text = [IO.File]::ReadAllText((Join-Path $fixture $path), [Text.Encoding]::UTF8)
        if ($text.Contains($current) -and $path -ne 'docs\MAINTAINER_BRIEFING.md' -and $path -ne 'docs\USER_GUIDE.md') { throw "SET_VERSION_LEFT_OLD:$path" }
    }
    if (([IO.File]::ReadAllBytes($layout)[0] -eq 0xEF) -ne $layoutBom) { throw 'SET_VERSION_BOM_CHANGED' }
    if ([IO.File]::ReadAllText($buildScript).Contains("`r`n") -ne $buildCrlf) { throw 'SET_VERSION_LINE_ENDINGS_CHANGED' }

    # A target that no longer matches stops the run before any file is written.
    [IO.File]::WriteAllText((Join-Path $fixture 'extension\index.html'), '<html></html>')
    $before = Get-Hashes $fixture
    $broken = Invoke-SetVersion @('-Version', ($parts[0] + '.' + $parts[1] + '.' + ([int]$parts[2] + 2)), '-Root', $fixture)
    if ($broken.Code -eq 0 -or $broken.Output -notmatch 'extension\\index.html: expected 1 match, found 0') { throw "SET_VERSION_MISSED_TARGET:$($broken.Output)" }
    $unchanged = Get-Hashes $fixture
    foreach ($path in $relative) { if ($before[$path] -ne $unchanged[$path]) { throw "SET_VERSION_PARTIAL_WRITE:$path" } }
} finally {
    Remove-Item -LiteralPath $fixture -Recurse -Force -ErrorAction SilentlyContinue
}
Write-Host 'SET_VERSION_OK:real-tree-check;bump;check-mismatch;no-downgrade;bom-and-line-endings;all-or-nothing'
