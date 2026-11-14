param(
    [Parameter(Mandatory)][string]$TemplateJob,
    [string]$OutputRoot = (Join-Path $env:TEMP 'PVS-Parameter-Matrix')
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$projectRoot = Resolve-Path (Join-Path $PSScriptRoot '..\..')
$engineRoot = Join-Path $projectRoot 'extension\engine'
$planner = Join-Path $engineRoot 'build-sentence-plan.ps1'
$templateFolder = Split-Path $TemplateJob -Parent
$alignmentSource = Join-Path $templateFolder 'alignment-result.json'
if (-not (Test-Path -LiteralPath $alignmentSource)) { throw 'Template job has no alignment-result.json.' }
$alignment = Get-Content -LiteralPath $alignmentSource -Raw -Encoding UTF8 | ConvertFrom-Json
$expectedRecoveredCueCount = @($alignment.cues | Where-Object { $null -eq $_.Start -or $null -eq $_.End -or [int]$_.Chapter -lt 0 }).Count

$cases = @(
    @{Name='default'},
    @{Name='speed-locked-100';Min=100;Max=100},
    @{Name='speed-max-115';Min=70;Max=115},
    @{Name='speed-max-120';Min=70;Max=120},
    @{Name='speed-min-80';Min=80;Max=115},
    @{Name='speed-wide';Min=10;Max=400},
    @{Name='dialogue-gap-low';Algorithm=@{minNoDialogueGapSeconds=0.2}},
    @{Name='dialogue-gap-high';Algorithm=@{minNoDialogueGapSeconds=10}},
    @{Name='silence-db-low';Algorithm=@{silenceNoiseDb=-80}},
    @{Name='silence-db-high';Algorithm=@{silenceNoiseDb=-5}},
    @{Name='silence-short';Algorithm=@{minSilenceDurationSeconds=0.01}},
    @{Name='silence-long';Algorithm=@{minSilenceDurationSeconds=1}},
    @{Name='boundary-small';Algorithm=@{boundarySearchSeconds=0.05}},
    @{Name='boundary-large';Algorithm=@{boundarySearchSeconds=2}},
    @{Name='confidence-zero';Algorithm=@{lowConfidenceThreshold=0}},
    @{Name='confidence-one';Algorithm=@{lowConfidenceThreshold=1}},
    @{Name='punctuation-custom';Algorithm=@{sentenceEndCharacters='.!?;'}},
    @{Name='voice-map-zero';Algorithm=@{voiceMappingToleranceFrames=0}},
    @{Name='voice-map-ten';Algorithm=@{voiceMappingToleranceFrames=10}},
    @{Name='validation-zero';Algorithm=@{validationToleranceFrames=0}},
    @{Name='validation-five';Algorithm=@{validationToleranceFrames=5}},
    @{Name='coverage-zero';Algorithm=@{maxCoverageGapFrames=0}},
    @{Name='coverage-two';Algorithm=@{maxCoverageGapFrames=2}}
)

if (Test-Path -LiteralPath $OutputRoot) { Remove-Item -LiteralPath $OutputRoot -Recurse -Force }
New-Item -ItemType Directory -Path $OutputRoot -Force | Out-Null
$results = New-Object System.Collections.Generic.List[object]
foreach ($case in $cases) {
    $caseFolder = Join-Path $OutputRoot ([string]$case.Name)
    New-Item -ItemType Directory -Path $caseFolder -Force | Out-Null
    Copy-Item -LiteralPath $alignmentSource -Destination (Join-Path $caseFolder 'alignment-result.json') -Force
    $job = Get-Content -LiteralPath $TemplateJob -Raw -Encoding UTF8 | ConvertFrom-Json
    $job.outputFolder = $caseFolder
    if ($case.ContainsKey('Min')) { $job | Add-Member -NotePropertyName speedWarningMinPercent -NotePropertyValue ([double]$case.Min) -Force }
    if ($case.ContainsKey('Max')) { $job | Add-Member -NotePropertyName speedWarningMaxPercent -NotePropertyValue ([double]$case.Max) -Force }
    if ($case.ContainsKey('Algorithm')) {
        foreach ($key in $case.Algorithm.Keys) { $job.algorithm.$key = $case.Algorithm[$key] }
    }
    $jobPath = Join-Path $caseFolder 'job.json'
    $job | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $jobPath -Encoding UTF8
    & $planner -JobPath $jobPath | Out-Null
    $plan = Get-Content -LiteralPath (Join-Path $caseFolder 'sentence-edit-plan.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $problems = New-Object System.Collections.Generic.List[string]
    if ([int]$plan.schemaVersion -ne 8) { $problems.Add('schema') }
    if ([int]$plan.plannerRevision -ne 18) { $problems.Add('planner-revision') }
    if ([int]$plan.summary.recoveredUnalignedCueCount -ne $expectedRecoveredCueCount) { $problems.Add('recovered-cue-count') }
    if (@($plan.captions).Count -ne [int]$plan.summary.captionCueCount -or @($plan.captions).Count -lt [int]$plan.summary.inputCueCount) { $problems.Add('captions') }
    $captions = @($plan.captions | Sort-Object Index)
    for ($i=0; $i -lt $captions.Count; $i++) {
        $captionStartFrame = [int][Math]::Round([double]$captions[$i].Start * [double]$plan.frameRate)
        $captionEndFrame = [int][Math]::Round([double]$captions[$i].End * [double]$plan.frameRate)
        if ($captionEndFrame -le $captionStartFrame) { $problems.Add("caption-duration-$i") }
        if ([string]$captions[$i].Text -match '[\r\n]' -or ([string]$captions[$i].Text).Length -gt [int]$plan.settings.maxCaptionCharacters) { $problems.Add("caption-line-$i") }
        if ($i -gt 0) {
            $previousCaptionEndFrame = [int][Math]::Round([double]$captions[$i-1].End * [double]$plan.frameRate)
            if ($captionStartFrame -lt $previousCaptionEndFrame) { $problems.Add("caption-overlap-$i") }
        }
    }
    if ($expectedRecoveredCueCount -gt 0 -and @($plan.markers | Where-Object { [string]$_.Owner -eq 'A2' -and [string]$_.Comments -match 'confidence=0(?:$|\D)' }).Count -eq 0) { $problems.Add('recovered-cue-marker') }
    $segments = @($plan.segments)
    for ($i=0; $i -lt $segments.Count; $i++) {
        $segment = $segments[$i]
        if ([int]$segment.SourceEndFrame -le [int]$segment.SourceStartFrame) { $problems.Add("source-duration-$i") }
        if ([int]$segment.NewEndFrame -le [int]$segment.NewStartFrame) { $problems.Add("output-duration-$i") }
        if ($i -gt 0 -and [int]$segment.SourceStartFrame -ne [int]$segments[$i-1].SourceEndFrame) { $problems.Add("source-gap-$i") }
        if ($i -gt 0 -and [int]$segment.NewStartFrame -ne [int]$segments[$i-1].NewEndFrame) { $problems.Add("timeline-gap-$i") }
        if ($segment.Kind -eq 'retime') {
            $speed = [double]$segment.AppliedSpeedPercent
            if ([double]::IsNaN($speed) -or [double]::IsInfinity($speed) -or $speed -le 0) { $problems.Add("invalid-speed-$i") }
            if ([int]$segment.Chapter -lt 0) { $problems.Add("invalid-chapter-$i") }
            $expectedSpeed = ([int]$segment.SourceDurationFrames / [double][int]$segment.VisualDurationFrames) * 100.0
            if ([Math]::Abs($speed - $expectedSpeed) -gt 0.000001) { $problems.Add("speed-formula-$i") }
            if ([int]$segment.EffectiveSourceDurationFrames -ne [int]$segment.SourceDurationFrames) { $problems.Add("source-trim-$i") }
            if ([int]$segment.TrimTailFrames -ne 0 -or [int]$segment.BorrowFrames -ne 0) { $problems.Add("legacy-fill-$i") }
            $voiceFrames = [int]$segment.OriginalVoiceEndFrame - [int]$segment.OriginalVoiceStartFrame
            if ([int]$segment.VisualDurationFrames -ne $voiceFrames) { $problems.Add("voice-duration-$i") }
            $outside = $speed -lt [double]$plan.speedWarningMinPercent - 0.000001 -or $speed -gt [double]$plan.speedWarningMaxPercent + 0.000001
            if ([bool]$segment.SpeedOutsideWarningRange -ne $outside) { $problems.Add("speed-warning-$i") }
        }
    }
    if ([int]$segments[0].SourceStartFrame -ne [int][Math]::Round([double]$plan.mainVideoClip.start * [double]$plan.frameRate)) { $problems.Add('source-start') }
    if ([int]$segments[-1].SourceEndFrame -ne [int]$plan.mainVideoSourceEndFrame) { $problems.Add('source-end') }
    if ([int]$segments[-1].NewEndFrame -ne [int]$plan.plannedMainVideoEndFrame) { $problems.Add('timeline-end') }
    if (@($segments | Where-Object Unit -eq 'source-tail-guard').Count -ne 0) { $problems.Add('legacy-tail-guard') }
    if (@($segments | Where-Object { $_.Kind -eq 'retime' -and $_.SpeedOutsideWarningRange }).Count -ne [int]$plan.summary.speedWarningCount) { $problems.Add('speed-warning-count') }
    $results.Add([pscustomobject]@{
        Case=[string]$case.Name
        Ok=($problems.Count -eq 0)
        Groups=[int]$plan.summary.safeSentenceGroupCount
        Segments=$segments.Count
        MinimumSpeed=[Math]::Round([double](($segments | Where-Object Kind -eq 'retime' | Measure-Object AppliedSpeedPercent -Minimum).Minimum),6)
        MaximumSpeed=[Math]::Round([double](($segments | Where-Object Kind -eq 'retime' | Measure-Object AppliedSpeedPercent -Maximum).Maximum),6)
        Problems=($problems -join ',')
    })
}

$results | Format-Table -AutoSize
if (@($results | Where-Object { -not $_.Ok }).Count -gt 0) { throw 'PARAMETER_MATRIX_FAILED' }
Write-Host "PARAMETER_MATRIX_OK:$($results.Count) cases"
