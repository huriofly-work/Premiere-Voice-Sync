$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$projectRoot = Resolve-Path (Join-Path $PSScriptRoot '..\..')
$extensionRoot = Join-Path $projectRoot 'extension'
$hostSource = [IO.File]::ReadAllText((Join-Path $extensionRoot 'jsx\host.jsx'), [Text.Encoding]::UTF8)
$main = [IO.File]::ReadAllText((Join-Path $extensionRoot 'js\main.js'), [Text.Encoding]::UTF8)
$planner = [IO.File]::ReadAllText((Join-Path $extensionRoot 'engine\build-sentence-plan.ps1'), [Text.Encoding]::UTF8)
$alignment = [IO.File]::ReadAllText((Join-Path $extensionRoot 'engine\run-alignment.ps1'), [Text.Encoding]::UTF8)

function Assert-Contains([string]$Text,[string]$Needle,[string]$Name) {
    if ($Text.IndexOf($Needle, [StringComparison]::Ordinal) -lt 0) { throw "HOST_INVARIANT_MISSING:$Name" }
}

if ([regex]::Matches($hostSource, '\.setSpeed\(').Count -ne 1) { throw 'HOST_INVARIANT_FAILED:setSpeed-call-count' }
if ($hostSource -match 'item\.outPoint\s*=') { throw 'HOST_INVARIANT_FAILED:forced-outPoint' }
if ([regex]::Matches($hostSource, 'item\.end\s*=\s*forcedEnd').Count -ne 1) { throw 'HOST_INVARIANT_FAILED:terminal-end-fallback-count' }
Assert-Contains $hostSource 'firstError !== 0 && allowTerminalEndFallback' 'terminal-end-fallback-guard'
Assert-Contains $hostSource 'savedSourceTicks / (desiredFrames * ticksPerFrame)' 'exact-source-factor'
if ($hostSource -match 'sourceBoundaryFailureCount|maxSourceOutErrorFrames|originalVideoSourceRanges') { throw 'HOST_INVARIANT_FAILED:invalid-post-retime-source-audit' }
Assert-Contains $hostSource 'var candidateFractions = [0.5, 0.4, 0.6, 0.3, 0.7, 0.25, 0.75, 0.2, 0.8];' 'marker-interior-candidates'
Assert-Contains $hostSource 'actualSourceFrame > sourceStartFrame + sourceInteriorToleranceFrames' 'marker-source-range-check'
Assert-Contains $hostSource 'projectedTimelineFrame > actualTimelineStartFrame && projectedTimelineFrame < actualTimelineEndFrame' 'marker-projection-check'
Assert-Contains $hostSource 'originalMainSourceInFrame + (markerSourceTimelineStartFrame - originalMainTimelineStartFrame) * originalMainSpeedFactor' 'marker-original-source-map'
Assert-Contains $hostSource 'app.project.importFiles([plan.captionSrtPath], true, captionBin, false)' 'caption-temp-bin-import'
Assert-Contains $hostSource 'var deleteResult = captionBin.deleteBin();' 'caption-temp-bin-delete'
if ($hostSource.IndexOf('captionBin.deleteBin() === 0', [StringComparison]::Ordinal) -ge 0) { throw 'HOST_INVARIANT_FAILED:caption-delete-return-value' }
Assert-Contains $hostSource 'projectTreeContainsNodeId(app.project.rootItem, captionBinNodeId)' 'caption-bin-node-check'
Assert-Contains $hostSource '$.sleep(50)' 'caption-cleanup-probe-wait'
Assert-Contains $hostSource 'captionProjectItemCountAfter === captionProjectItemCountBefore' 'caption-project-delta-check'
Assert-Contains $hostSource 'plan.summary.captionCueCount' 'caption-split-count-contract'
Assert-Contains $hostSource 'markerPlacementMode: "clip-project-item-planned-source-range-verified"' 'marker-mode'
Assert-Contains $hostSource 'executorVersion: 25' 'executor-version'
Assert-Contains $main 'Number(result.executorVersion) !== 25' 'main-executor-version'
Assert-Contains $main 'sentenceEndChars: ".?!;"' 'main-semicolon'
Assert-Contains $planner '$sentenceEndCharacters = ''.?!;''' 'planner-semicolon'
Assert-Contains $planner '$minSilenceDurationSeconds = 0.12' 'planner-safe-silence-duration'
Assert-Contains $planner '$boundarySearchSeconds = 0.12' 'planner-safe-boundary-window'
Assert-Contains $planner '$boundarySafetyMarginSeconds = 0.04' 'planner-safe-boundary-margin'
Assert-Contains $planner 'Find-SafeVoiceBoundary' 'planner-safe-boundary-selector'
Assert-Contains $main 'minSilence: 0.12' 'main-safe-silence-duration'
Assert-Contains $main 'boundaryWindow: 0.12' 'main-safe-boundary-window'
Assert-Contains $planner '. "$PSScriptRoot\lib\Paths.ps1"' 'planner-path-resolver'
Assert-Contains $planner "Resolve-PvsExistingPath -Path ([string]`$voice.path)" 'planner-resolves-voice-path'
if ($planner -match 'function Repair-Text') { throw 'HOST_INVARIANT_FAILED:destructive-path-repair' }
Assert-Contains $alignment '. "$PSScriptRoot\lib\Paths.ps1"' 'alignment-path-resolver'
Assert-Contains $main 'plan.summary.punctuationSentenceCount' 'punctuation-sentence-label'
Assert-Contains $main 'plan.summary.safeSentenceGroupCount' 'safe-voice-group-label'
if ($planner -match 'source-tail-guard') { throw 'HOST_INVARIANT_FAILED:legacy-tail-guard' }
Write-Host 'HOST_INVARIANTS_OK'
