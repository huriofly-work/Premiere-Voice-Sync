$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$root=Resolve-Path (Join-Path $PSScriptRoot '..\..')
. (Join-Path $PSScriptRoot '..\helpers\PackageFixture.ps1')
$temp=Join-Path $env:TEMP ('PVS-Security-'+[guid]::NewGuid().ToString('N'))
$package=Join-Path $temp 'package'
$script:checks=0
function Expect-Rejection {
    param([scriptblock]$Action,[string]$Expected)
    $caught=$null
    try { & $Action | Out-Null } catch { $caught=$_.Exception.Message }
    if (-not $caught -or $caught -notlike "*$Expected*") { throw "SECURITY_TEST_EXPECTED:$Expected;actual:$caught" }
    $script:checks++
}
try {
    New-PvsPackageFixture -Root $package -SourceRoot $root
    Assert-PvsPackage -Root $package | Out-Null
    $hashes=Join-Path $package 'SHA256SUMS.txt'
    Remove-Item -LiteralPath $hashes
    Expect-Rejection { Assert-PvsPackage -Root $package } 'SECURITY_CHECKSUM_REQUIRED'
    Update-PvsFixtureHashes -Root $package
    Set-Content -LiteralPath (Join-Path $package 'extra.exe') -Value 'EXTRA'
    Expect-Rejection { Assert-PvsPackage -Root $package } 'SECURITY_UNLISTED_FILE'
    Remove-Item -LiteralPath (Join-Path $package 'extra.exe')
    Add-Content -LiteralPath (Join-Path $package 'extension\js\main.js') -Value 'TAMPER'
    Expect-Rejection { Assert-PvsPackage -Root $package } 'SECURITY_HASH_MISMATCH'
    Update-PvsFixtureHashes -Root $package
    Add-Content -LiteralPath $hashes -Value (Get-Content -LiteralPath $hashes | Select-Object -First 1)
    Expect-Rejection { Assert-PvsPackage -Root $package } 'SECURITY_CHECKSUM_DUPLICATE'
    foreach ($path in @('..\outside.txt','C:\outside.txt','extension\x:stream','extension\..\x')) {
        Set-Content -LiteralPath $hashes -Value (('0'*64)+'  '+$path)
        Expect-Rejection { Assert-PvsPackage -Root $package } 'SECURITY_CHECKSUM_PATH'
    }
    Set-Content -LiteralPath $hashes -Value ''
    Expect-Rejection { Assert-PvsPackage -Root $package } 'SECURITY_CHECKSUM_FORMAT'
    Update-PvsFixtureHashes -Root $package
    $outside=Join-Path $temp 'unrelated'; New-Item -ItemType Directory -Path $outside | Out-Null
    Set-Content -LiteralPath (Join-Path $outside 'keep.txt') -Value 'KEEP'
    $link=Join-Path $package 'linked'
    New-Item -ItemType Junction -Path $link -Target $outside | Out-Null
    Expect-Rejection { Assert-PvsPackage -Root $package } 'SECURITY_LINKED_PATH'
    Expect-Rejection { Assert-PvsSafePath -Path (Join-Path $link 'new.txt') } 'SECURITY_LINKED_PATH'
    # Ancestors are checked from the root down: the outer link is refused before anything below it
    # is probed (a probe there would already pass through it), so a second link inside its target
    # is never the one reported. Compare full paths: on the CI runner TEMP is an 8.3 short path
    # (RUNNER~1) and .NET Framework GetFullPath reports it expanded (runneradmin).
    $innerTarget=Join-Path $temp 'inner-target'; New-Item -ItemType Directory -Path $innerTarget | Out-Null
    $inner=Join-Path $outside 'deep'; New-Item -ItemType Junction -Path $inner -Target $innerTarget | Out-Null
    try {
        try { Assert-PvsSafePath -Path (Join-Path $link 'deep\new.txt'); throw 'SECURITY_LINK_ORDER_NOT_REJECTED' }
        catch { if ($_.Exception.Message -ne ("SECURITY_LINKED_PATH:"+[IO.Path]::GetFullPath($link))) { throw "SECURITY_LINK_ORDER:$($_.Exception.Message)" } }
    } finally { [IO.Directory]::Delete($inner) }
    Expect-Rejection { Remove-PvsSafeTree -Path $package -Root $temp } 'SECURITY_LINKED_PATH'
    # Remove the junction itself only, never recurse through its target.
    [IO.Directory]::Delete($link)
    Expect-Rejection { Remove-PvsSafeTree -Path $temp -Root $temp } 'SECURITY_CANNOT_REMOVE_ROOT'
    Expect-Rejection { Remove-PvsSafeTree -Path $outside -Root $package } 'SECURITY_PATH_OUTSIDE_ROOT'
    if ((Get-Content -LiteralPath (Join-Path $outside 'keep.txt') -Raw).Trim() -ne 'KEEP') { throw 'SECURITY_DELETED_UNRELATED_DATA' }
    & node (Join-Path $PSScriptRoot 'security.test.js')
    if ($LASTEXITCODE -ne 0) { throw 'SECURITY_NODE_FAILED' }
    $ui=Get-Content -LiteralPath (Join-Path $root 'extension\js\main.js') -Raw
    $backend=Get-Content -LiteralPath (Join-Path $root 'extension\engine\resolve-backend.ps1') -Raw
    $setup=Get-Content -LiteralPath (Join-Path $root 'tools\setup-engine.ps1') -Raw
    if ($backend -match 'Get-Command' -or $setup -match 'releases/latest|resolve/main|Invoke-WebRequest') { throw 'SECURITY_UNPINNED_EXECUTION_OR_DOWNLOAD' }
    if ($ui -notmatch 'byId\("allowGpuDownload"\)\.checked.*InstallIfNeeded') { throw 'SECURITY_GPU_CONSENT_MISSING' }
    foreach ($name in @('run-alignment.ps1','run-captions.ps1')) {
        $source=Get-Content -LiteralPath (Join-Path $root "extension\engine\$name") -Raw
        if ($source.Contains('-InstallIfNeeded')) { throw 'SECURITY_BACKGROUND_DOWNLOAD' }
    }
    Write-Host "SECURITY_PS_OK:checks=$script:checks"
} finally {
    if (Test-Path $temp) { Remove-PvsSafeTree -Path $temp -Root $env:TEMP }
}
