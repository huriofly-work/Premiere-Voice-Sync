. (Join-Path (Resolve-Path (Join-Path $PSScriptRoot '..\..')) 'installer\package-security.ps1')
function Update-PvsFixtureHashes {
    param([string]$Root)
    $lines=foreach ($relative in (Get-PvsPackageFiles)) {
        (Get-FileHash -LiteralPath (Join-Path $Root $relative)).Hash + '  ' + $relative
    }
    $lines | Set-Content -LiteralPath (Join-Path $Root 'SHA256SUMS.txt') -Encoding ASCII
}
function New-PvsPackageFixture {
    param([string]$Root,[string]$SourceRoot)
    foreach ($relative in (Get-PvsPackageFiles)) {
        $file=Join-Path $Root $relative
        New-Item -ItemType Directory -Path (Split-Path $file -Parent) -Force | Out-Null
        Set-Content -LiteralPath $file -Value ('OPEN_SOURCE_FIXTURE:'+$relative) -Encoding ASCII
    }
    foreach ($name in @('install.ps1','uninstall.ps1','package-security.ps1')) {
        Copy-Item -LiteralPath (Join-Path $SourceRoot "installer\$name") -Destination (Join-Path $Root "scripts\$name") -Force
    }
    foreach ($relative in @('CSXS\manifest.xml','engine\lib\Security.ps1','native\NotificationIdentity.cs')) {
        Copy-Item -LiteralPath (Join-Path $SourceRoot "extension\$relative") -Destination (Join-Path $Root "extension\$relative") -Force
    }
    Update-PvsFixtureHashes -Root $Root
}
