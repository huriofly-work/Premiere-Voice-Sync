$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$candidateFractions = @(0.5, 0.4, 0.6, 0.3, 0.7, 0.25, 0.75, 0.2, 0.8)
$cases = @(
    @{
        Name = 'normal-100-percent'
        MainTimelineStart = 0.0
        MainSourceIn = 0.0
        MainSpeedFactor = 1.0
        Segments = @(
            @{ SourceStart = 0.0; SourceEnd = 120.0; OutputStart = 0.0; OutputEnd = 200.0 },
            @{ SourceStart = 120.0; SourceEnd = 360.0; OutputStart = 200.0; OutputEnd = 300.0 },
            @{ SourceStart = 360.0; SourceEnd = 450.0; OutputStart = 300.0; OutputEnd = 900.0 }
        )
    },
    @{
        Name = 'trimmed-source'
        MainTimelineStart = 300.0
        MainSourceIn = 900.0
        MainSpeedFactor = 1.0
        Segments = @(
            @{ SourceStart = 300.0; SourceEnd = 390.0; OutputStart = 1200.0; OutputEnd = 1300.0 },
            @{ SourceStart = 390.0; SourceEnd = 600.0; OutputStart = 1300.0; OutputEnd = 1450.0 }
        )
    },
    @{
        Name = 'pre-retimed-master'
        MainTimelineStart = 60.0
        MainSourceIn = 240.0
        MainSpeedFactor = 1.25
        Segments = @(
            @{ SourceStart = 60.0; SourceEnd = 180.0; OutputStart = 30.0; OutputEnd = 500.0 },
            @{ SourceStart = 180.0; SourceEnd = 181.0; OutputStart = 500.0; OutputEnd = 560.0 },
            @{ SourceStart = 181.0; SourceEnd = 480.0; OutputStart = 560.0; OutputEnd = 700.0 }
        )
    }
)

foreach ($case in $cases) {
    $mapped = @(
        foreach ($segment in $case.Segments) {
            [pscustomobject]@{
                SourceStart = [double]$case.MainSourceIn + ([double]$segment.SourceStart - [double]$case.MainTimelineStart) * [double]$case.MainSpeedFactor
                SourceEnd = [double]$case.MainSourceIn + ([double]$segment.SourceEnd - [double]$case.MainTimelineStart) * [double]$case.MainSpeedFactor
                OutputStart = [double]$segment.OutputStart
                OutputEnd = [double]$segment.OutputEnd
            }
        }
    )
    for ($segmentIndex = 0; $segmentIndex -lt $mapped.Count; $segmentIndex++) {
        $target = $mapped[$segmentIndex]
        foreach ($fraction in $candidateFractions) {
            $sourceFrame = $target.SourceStart + ($target.SourceEnd - $target.SourceStart) * $fraction
            $owners = @($mapped | Where-Object { $sourceFrame -gt $_.SourceStart -and $sourceFrame -lt $_.SourceEnd })
            if ($owners.Count -ne 1) { throw "MARKER_SOURCE_OWNER_FAILED:$($case.Name):${segmentIndex}:$fraction" }
            $projectedFrame = $target.OutputStart + $fraction * ($target.OutputEnd - $target.OutputStart)
            if ($projectedFrame -le $target.OutputStart -or $projectedFrame -ge $target.OutputEnd) {
                throw "MARKER_OUTPUT_PROJECTION_FAILED:$($case.Name):${segmentIndex}:$fraction"
            }
        }
    }
}

& node (Join-Path $PSScriptRoot 'marker-ownership.test.js')
if ($LASTEXITCODE -ne 0) { throw 'MARKER_OWNERSHIP_FAILED' }
Write-Host "MARKER_SOURCE_MAPPING_OK:$($cases.Count) cases"
