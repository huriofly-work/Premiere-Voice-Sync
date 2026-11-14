$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$root=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
. "$root\extension\engine\lib\SpeedMergeTrial.ps1"
. "$root\extension\engine\lib\Native.ps1"
function Make-Plan([int[]]$Sources,[int[]]$Outputs,[int[]]$Chapters=@(),[int]$GapIndex=-1,[double]$Fps=30) {
    $segments=@();$source=0;$output=0
    for($i=0;$i -lt $Sources.Count;$i++){
        $s=$Sources[$i];$d=$Outputs[$i];$chapter=if($Chapters.Count){$Chapters[$i]}else{0}
        $segments+= [pscustomobject]@{Kind=if($i -eq $GapIndex){'gap'}else{'retime'};Unit='sentence';SourceStartFrame=$source;SourceEndFrame=($source+$s);SourceDurationFrames=$s;SourceStart=[Math]::Round($source/$Fps,6);SourceEnd=[Math]::Round(($source+$s)/$Fps,6);SourceDuration=[Math]::Round($s/$Fps,6);EffectiveSourceDurationFrames=$s;EffectiveSourceDuration=[Math]::Round($s/$Fps,6);NewStartFrame=$output;NewEndFrame=($output+$d);NewStart=[Math]::Round($output/$Fps,6);NewEnd=[Math]::Round(($output+$d)/$Fps,6);OutputDurationFrames=$d;OutputDuration=[Math]::Round($d/$Fps,6);VisualDurationFrames=$d;OriginalVoiceStartFrame=$output;OriginalVoiceEndFrame=($output+$d);OriginalVoiceStart=[Math]::Round($output/$Fps,6);OriginalVoiceEnd=[Math]::Round(($output+$d)/$Fps,6);NewVoiceStartFrame=$output;NewVoiceEndFrame=($output+$d);NewVoiceStart=[Math]::Round($output/$Fps,6);NewVoiceEnd=[Math]::Round(($output+$d)/$Fps,6);AppliedSpeedPercent=(100.0*$s/$d);DesiredSpeedPercent=(100.0*$s/$d);SpeedOutsideWarningRange=$false;FirstTargetCue=($i+1);LastTargetCue=($i+1);Chapter=$chapter;Confidence=1;SafeVoiceCut=$true;BoundarySilenceDuration=0.2;Text="Sentence $i.";BorrowFrames=0;BorrowSeconds=0;TrimTailFrames=0;TrimTailSeconds=0}
        $source+=$s;$output+=$d
    }
    return [pscustomobject]@{ok=$true;schemaVersion=8;plannerRevision=18;sequenceId='fixture';frameRate=$Fps;mainVideoSourceEndFrame=$source;plannedMainVideoEndFrame=$output;speedWarningMinPercent=70;speedWarningMaxPercent=130;segments=$segments;captions=@([pscustomobject]@{Text='Exact text';Start=0.2;End=1});markers=@([pscustomobject]@{Owner='A2';SegmentIndex=0});voiceClips=@([pscustomobject]@{speedPercent=110;inPoint=0});settings=[pscustomobject]@{maxCoverageGapFrames=0}}
}
function Check([bool]$Value,[string]$Message){if(-not $Value){throw "SPEED_MERGE_TEST_FAILED:$Message"}}
function Reject([scriptblock]$Action,[string]$Message){try{& $Action}catch{if($_.Exception.Message -eq $Message){return};throw};throw "SPEED_MERGE_REJECTION_MISSING:$Message"}
$job=[pscustomobject]@{workflow='experimental-dtw-direct';speedMergeTrial='adjacent-speed-v2';speedWarningMinPercent=70;speedWarningMaxPercent=130}
Assert-PvsSpeedMergeInput $job
$defaultJob=$job | ConvertTo-Json | ConvertFrom-Json;$defaultJob.workflow='one-click-dtw-direct'
Assert-PvsSpeedMergeInput $defaultJob
$oldProtocol=$job | ConvertTo-Json | ConvertFrom-Json;$oldProtocol.speedMergeTrial='adjacent-speed-v1'
Reject {Assert-PvsSpeedMergeInput $oldProtocol} 'SPEED_MERGE_EXPLICIT_OPT_IN_REQUIRED'
$bad=$job | ConvertTo-Json | ConvertFrom-Json;$bad.workflow='one-click-direct'
Reject {Assert-PvsSpeedMergeInput $bad} 'SPEED_MERGE_EXPLICIT_OPT_IN_REQUIRED'
$bad.speedMergeTrial='wrong';Reject {Assert-PvsSpeedMergeInput $bad} 'SPEED_MERGE_EXPLICIT_OPT_IN_REQUIRED'
$bad=$job | ConvertTo-Json | ConvertFrom-Json;$bad.speedWarningMaxPercent=20
Reject {Assert-PvsSpeedMergeInput $bad} 'SPEED_MERGE_THRESHOLDS_INVALID'

# One adjacent pair only, even if the pair is still outside the band.
$base=Make-Plan @(40,60,100,100,100) @(100,100,100,100,100)
$original=$base | ConvertTo-Json -Depth 30 -Compress
$candidate=Get-PvsSpeedMergeTrial $base
Check ($candidate.speedMergeSummary.mergeCount -eq 1) 'one-merge-only'
Check ($candidate.visualSegments.Count -eq 4 -and $candidate.visualSegments[0].AppliedSpeedPercent -eq 50 -and $candidate.visualSegments[0].SpeedOutsideWarningRange) 'still-low-marker-no-expansion'
Check (($base | ConvertTo-Json -Depth 30 -Compress) -ceq $original) 'baseline-untouched'
# Faster raw neighbor is not necessarily the best combined speed (duration weight).
$anchored=Make-Plan @(40,100) @(100,100)
$anchored|Add-Member acousticEditBoundaryRevision 'raw-dtw-quiet-partition-v1'
Check ((Get-PvsSpeedMergeTrial $anchored).speedMergeSummary.mergeCount -eq 0) 'speed-balancing-cannot-move-sync-anchor'
$unchangedAnchor=Make-Plan @(68,69) @(100,100)
$unchangedAnchor|Add-Member acousticEditBoundaryRevision 'raw-dtw-quiet-partition-v1'
Check ((Get-PvsSpeedMergeTrial $unchangedAnchor).speedMergeSummary.mergeCount -eq 1) 'anchor-preserving-merge-still-allowed'
$candidate=Get-PvsSpeedMergeTrial (Make-Plan @(130,3500,11000) @(100,10000,10000))
Check ($candidate.speedMergeSummary.steps[0].Direction -eq 'next') 'evaluate-both-weighted'
Check ($candidate.visualSegments[1].AppliedSpeedPercent -eq 72.5) 'weighted-not-average-of-percentages'
# Too-fast segment balances against slower neighbor; exact bounds are accepted.
$candidate=Get-PvsSpeedMergeTrial (Make-Plan @(160,100) @(100,100))
Check ($candidate.visualSegments.Count -eq 1 -and $candidate.visualSegments[0].AppliedSpeedPercent -eq 130) 'upper-bound'
$candidate=Get-PvsSpeedMergeTrial (Make-Plan @(40,100) @(100,100))
Check ($candidate.visualSegments.Count -eq 1 -and $candidate.visualSegments[0].AppliedSpeedPercent -eq 70) 'lower-bound'
# Chapters may be crossed, including different user voice speeds (untouched).
$candidate=Get-PvsSpeedMergeTrial (Make-Plan @(40,100) @(100,100) @(0,1))
Check ($candidate.visualSegments.Count -eq 1 -and $candidate.visualSegments[0].Chapters.Count -eq 2) 'cross-chapter'
# Never bridge no-dialogue or a discontinuity in original voice, even across chapter.
$candidate=Get-PvsSpeedMergeTrial (Make-Plan @(40,100,100) @(100,100,100) @(0,0,1) 1)
Check ($candidate.speedMergeSummary.mergeCount -eq 0 -and $candidate.speedMergeSummary.warningsAfter -eq 1) 'protected-gap'
$base=Make-Plan @(40,100) @(100,100) @(0,1)
$base.segments[1].OriginalVoiceStartFrame=110;$base.segments[1].OriginalVoiceEndFrame=210
$candidate=Get-PvsSpeedMergeTrial $base
Check ($candidate.speedMergeSummary.mergeCount -eq 0) 'voice-gap'
# No improving neighbor: retain best state and warning instead of endless merging.
$candidate=Get-PvsSpeedMergeTrial (Make-Plan @(40,30) @(100,100))
Check ($candidate.visualSegments.Count -eq 1 -and $candidate.speedMergeSummary.warningsAfter -eq 1) 'partial-best-and-marker'
$candidate=Get-PvsSpeedMergeTrial (Make-Plan @(100,100) @(100,100))
Check ($candidate.speedMergeSummary.mergeCount -eq 0) 'in-band-no-op'
$candidate=Get-PvsSpeedMergeTrial (Make-Plan @(50,50,100) @(100,100,100))
Check ($candidate.speedMergeSummary.mergeCount -eq 1 -and $candidate.visualSegments.Count -eq 2) 'consumed-pair-not-absorbed'
$candidate=Get-PvsSpeedMergeTrial (Make-Plan @(200,180,100) @(100,100,100))
Check ($candidate.speedMergeSummary.mergeCount -eq 1 -and $candidate.visualSegments[0].AppliedSpeedPercent -eq 190 -and $candidate.visualSegments[0].SpeedOutsideWarningRange) 'still-high-marker-no-expansion'
$candidate=Get-PvsSpeedMergeTrial (Make-Plan @(40,100,40) @(100,100,100))
Check ($candidate.speedMergeSummary.mergeCount -eq 1 -and $candidate.visualSegments.Count -eq 2) 'neighbor-cannot-reuse-successful-pair'
$base=Make-Plan @(40,100) @(100,100)
$candidate=Get-PvsSpeedMergeTrial $base
$candidate.captions[0].Start=0
Reject {Assert-PvsSpeedMergePlan $base $candidate} 'SPEED_MERGE_PROTECTED_PLAN_CHANGED'
$candidate=Get-PvsSpeedMergeTrial $base;$candidate.visualSegments[0].AppliedSpeedPercent=71
Reject {Assert-PvsSpeedMergePlan $base $candidate} 'SPEED_MERGE_VISUAL_FIELDS_CHANGED'
$candidate=Get-PvsSpeedMergeTrial $base;$candidate.visualSegments[0].MemberSegmentIndices=@(0,0)
Reject {Assert-PvsSpeedMergePlan $base $candidate} 'SPEED_MERGE_COVERAGE_CHANGED'
$base=Make-Plan @(40,60,100) @(100,100,100)
$candidate=Get-PvsSpeedMergeTrial $base
$candidate.visualSegments=@(New-PvsVisualSpeedGroup $base @(0,1,2))
Reject {Assert-PvsSpeedMergePlan $base $candidate} 'SPEED_MERGE_PAIR_LIMIT_EXCEEDED'
$base=Make-Plan @(40,100) @(100,100);$base.segments[1].NewStartFrame++
Reject {Get-PvsSpeedMergeTrial $base} 'SPEED_MERGE_PLAN_DISCONTINUOUS'
# Property/regression tests: frame coverage and protected data at both frame rates.
$random=New-Object Random(12345)
foreach($fps in @(30.0,(30000.0/1001))){
    for($case=0;$case -lt 40;$case++){
        $sources=@();$outputs=@();$chapters=@()
        for($i=0;$i -lt 8;$i++){$sources+=$random.Next(10,180);$outputs+=$random.Next(30,150);$chapters+=[int][Math]::Floor($i/3)}
        $base=Make-Plan $sources $outputs $chapters -Fps $fps
        $candidate=Get-PvsSpeedMergeTrial $base
        $null=Assert-PvsSpeedMergePlan $base $candidate
        Check ($candidate.speedMergeSummary.warningsAfter -le $candidate.speedMergeSummary.warningsBefore) 'warning-count-monotonic'
        foreach($step in $candidate.speedMergeSummary.steps){Check ($step.DistanceAfter -lt $step.DistanceBefore) 'strict-progress'}
        Check ($candidate.speedMergeSummary.mergeCount -le 4) 'pair-budget'
        foreach($visual in $candidate.visualSegments){Check (@($visual.MemberSegmentIndices).Count -le 2) 'no-chained-merge'}
    }
}
foreach($name in @('run-alignment.ps1','build-sentence-plan.ps1','run-captions.ps1')){
    Check (-not [IO.File]::ReadAllText("$root\extension\engine\$name").Contains('SpeedMergeTrial.ps1')) 'stable-isolation'
}
$temporary=Join-Path $env:TEMP ('PVS-SpeedMergeInput-'+[guid]::NewGuid().ToString('N'))
Assert-PvsSafePath -Path $temporary -Root $env:TEMP
try {
    New-Item -ItemType Directory -Path $temporary | Out-Null
    $job | Add-Member outputFolder $temporary
    $jobPath=Join-Path $temporary 'job.json'
    [IO.File]::WriteAllText($jobPath,($job | ConvertTo-Json),(New-Object Text.UTF8Encoding($false)))
    $run=Invoke-NativeCapture (Join-Path $PSHOME 'powershell.exe') @('-NoProfile','-ExecutionPolicy','Bypass','-File',"$root\extension\engine\build-speed-merge-trial-plan.ps1",'-JobPath',$jobPath,'-ValidateOnly')
    Check ($run.ExitCode -eq 0 -and $run.Output -match 'SPEED_MERGE_INPUT_OK') "wrapper-preflight:$($run.Output)"
    Check (-not (Test-Path -LiteralPath (Join-Path $temporary 'speed-merge-trial'))) 'preflight-no-plan-or-ASR'
} finally {Remove-PvsSafeTree -Path $temporary -Root $env:TEMP}
Check (-not [IO.File]::ReadAllText("$root\extension\index.html").Contains('id="allowSpeedMerge"')) 'default-no-opt-in'
Write-Host 'SPEED_MERGE_TRIAL_OK:weighted-neighbors;single-pair-only;no-reuse;bounds;cross-chapter;protected-gap;voice-caption-unchanged;markers;80-frame-property-cases'
