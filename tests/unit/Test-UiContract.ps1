$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$projectRoot = Resolve-Path (Join-Path $PSScriptRoot '..\..')
$main = [IO.File]::ReadAllText((Join-Path $projectRoot 'extension\js\main.js'), [Text.Encoding]::UTF8)
$html = [IO.File]::ReadAllText((Join-Path $projectRoot 'extension\index.html'), [Text.Encoding]::UTF8)
$planner = [IO.File]::ReadAllText((Join-Path $projectRoot 'extension\engine\build-sentence-plan.ps1'), [Text.Encoding]::UTF8)

foreach ($required in @(
    'minSpeed: 70, maxSpeed: 130, minDialogueGap: 0.5, voiceGroupGap: 2, maxCaptionCharacters: 42',
    'settingsSchemaVersion = "3"',
    'Number(migrated.maxSpeed) === 110',
    'migrated.maxSpeed = settingDefaults.maxSpeed',
    'function runDiagnostics()',
    'function inspectSrt(filePath)',
    'function setWorkflowBusy(busy)',
    'byId("runDiagnostics").addEventListener("click", runDiagnostics)'
)) {
    if ($main.IndexOf($required, [StringComparison]::Ordinal) -lt 0) { throw "UI_CONTRACT_MISSING:$required" }
}
foreach ($required in @(
    'id="maxSpeed" type="number" min="100" max="400" value="130"',
    'id="minDialogueGap" type="number" min="0.2" max="10" step="0.1" value="0.5"',
    'id="maxCaptionCharacters" type="number" min="20" max="80" step="1" value="42"',
    'id="runDiagnostics"',
    'id="editUsageHelp" class="card usage-help edit-only"',
    'id="captionUsageHelp" class="card usage-help caption-only"',
    'role="status" aria-live="polite"'
)) {
    if ($html.IndexOf($required, [StringComparison]::Ordinal) -lt 0) { throw "UI_HTML_CONTRACT_MISSING:$required" }
}

if ($html -notmatch '<details id="editUsageHelp" class="card usage-help edit-only">') { throw 'EDIT_USAGE_HELP_NOT_IN_EDIT_MODE' }
if ($html -notmatch '<details id="captionUsageHelp" class="card usage-help caption-only" hidden>') { throw 'CAPTION_USAGE_HELP_NOT_IN_CAPTION_MODE' }
if ($html -match 'id="scanCaptionRange"') { throw 'DUPLICATE_RANGE_REFRESH_CONTROL' }
if ($html -notmatch '<section class="card input-card">[\s\S]*?id="scanSequence"') { throw 'COMMON_INPUT_REFRESH_MISSING' }
if ($html -notmatch '<details id="supportTools"[\s\S]*?id="runDiagnostics"') { throw 'DIAGNOSTICS_NOT_IN_SUPPORT' }
if ($html -match '<details id="(?:supportTools|backendOptions)"[^>]*\sopen(?:\s|>)') { throw 'SUPPORT_OPTIONS_NOT_COLLAPSED' }
if ($html.Contains('id="generalUsageHelp"')) { throw 'GENERAL_USAGE_HELP_BELONGS_IN_PACKAGE_DOCUMENTATION' }

$diagnosticStart = $main.IndexOf('async function runDiagnostics()', [StringComparison]::Ordinal)
$runStart = $main.IndexOf('async function runSync()', $diagnosticStart, [StringComparison]::Ordinal)
if ($diagnosticStart -lt 0 -or $runStart -le $diagnosticStart) { throw 'UI_DIAGNOSTIC_BOUNDARY_INVALID' }
$diagnosticSource = $main.Substring($diagnosticStart, $runStart - $diagnosticStart)
foreach ($forbidden in @('executePlan(', 'run-alignment.ps1', 'build-sentence-plan.ps1', 'fs.writeFileSync')) {
    if ($diagnosticSource.IndexOf($forbidden, [StringComparison]::Ordinal) -ge 0) { throw "UI_DIAGNOSTIC_IS_NOT_READ_ONLY:$forbidden" }
}

if ($planner.IndexOf("speedThresholdMode='marker-only'", [StringComparison]::Ordinal) -lt 0) { throw 'PLANNER_WARNING_MODE_CHANGED' }
if ($planner.IndexOf('$speed = ($sourceFrames / [double]$visualFrames) * 100.0', [StringComparison]::Ordinal) -lt 0) { throw 'PLANNER_UNRESTRICTED_SPEED_FORMULA_CHANGED' }

& node (Join-Path $PSScriptRoot 'workflow-notice-ui.test.js')
if ($LASTEXITCODE -ne 0) { throw 'WORKFLOW_NOTICE_UI_FAILED' }
& node (Join-Path $PSScriptRoot 'workflow-metrics.test.js')
if ($LASTEXITCODE -ne 0) { throw 'WORKFLOW_METRICS_FAILED' }
Write-Host 'UI_CONTRACT_OK'
