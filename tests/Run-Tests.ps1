param([switch]$SkipInstallerTests,[switch]$NoWindowsIntegration)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$projectRoot = Resolve-Path (Join-Path $PSScriptRoot '..')

$parseRoots = @('extension','installer','tests','tools') | ForEach-Object { Join-Path $projectRoot $_ }
$powerShellFiles = @(Get-ChildItem -LiteralPath $parseRoots -File -Recurse | Where-Object { $_.Extension -eq '.ps1' })
foreach ($file in $powerShellFiles) {
    $tokens = $null
    $errors = $null
    [Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$errors) | Out-Null
    if ($errors.Count) { throw "POWERSHELL_PARSE_FAILED:$($file.FullName):$($errors[0].Message)" }
}
[xml](Get-Content -LiteralPath (Join-Path $projectRoot 'extension\CSXS\manifest.xml') -Raw -Encoding UTF8) | Out-Null

$tests = @(Get-ChildItem -LiteralPath (Join-Path $PSScriptRoot 'unit') -File -Filter 'Test-*.ps1' | Sort-Object Name)
if ($SkipInstallerTests) { $tests = @($tests | Where-Object { $_.Name -notin @('Test-InstallerLifecycle.ps1','Test-InstallRollback.ps1','Test-PanelRegistry.ps1','Test-OpenSourceRelease.ps1') }) }
if ($NoWindowsIntegration) {
    $excluded=@('Test-InstallerLifecycle.ps1','Test-InstallRollback.ps1','Test-PanelRegistry.ps1','Test-NotificationShortcut.ps1','Test-NativeNotifications.ps1','Test-IncidentNotifications.ps1')
    Write-Host ('WINDOWS_INTEGRATION_SKIPPED:'+($excluded -join ','))
    $tests=@($tests | Where-Object { $_.Name -notin $excluded })
}
$passed = 0
foreach ($test in $tests) {
    Write-Host "RUN $($test.Name)"
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $test.FullName
    if ($LASTEXITCODE -ne 0) { throw "TEST_FAILED:$($test.Name):$LASTEXITCODE" }
    $passed++
}

Write-Host "TEST_SUITE_OK:passed=$passed;parsed=$($powerShellFiles.Count);noWindowsIntegration=$([bool]$NoWindowsIntegration)"
