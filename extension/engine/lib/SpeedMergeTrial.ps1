# Visual-only speed balancing. Voice/caption planning remains untouched.
Set-StrictMode -Version Latest

function Get-PvsSpeedDistance([double]$Speed,[double]$Minimum,[double]$Maximum) {
    if($Speed -lt $Minimum-0.000001){return $Minimum-$Speed}
    if($Speed -gt $Maximum+0.000001){return $Speed-$Maximum}
    return 0.0
}

function Assert-PvsSpeedMergeInput($Job) {
    if(-not $Job.PSObject.Properties['speedMergeTrial'] -or $Job.speedMergeTrial -cne 'adjacent-speed-v2' -or $Job.workflow -cnotin @('experimental-dtw-direct','one-click-dtw-direct')){throw 'SPEED_MERGE_EXPLICIT_OPT_IN_REQUIRED'}
    foreach($field in @('speedWarningMinPercent','speedWarningMaxPercent')){
        if(-not $Job.PSObject.Properties[$field]){throw 'SPEED_MERGE_THRESHOLDS_REQUIRED'}
        $value=[double]$Job.$field
        if([double]::IsNaN($value) -or [double]::IsInfinity($value) -or $value -le 0){throw 'SPEED_MERGE_THRESHOLDS_INVALID'}
    }
    if($Job.speedWarningMinPercent -gt $Job.speedWarningMaxPercent){throw 'SPEED_MERGE_THRESHOLDS_INVALID'}
}

function New-PvsVisualSpeedGroup($Plan,[int[]]$Indices) {
    $items=@(foreach($index in $Indices){$Plan.segments[$index]})
    $first=$items[0];$last=$items[-1]
    $visual=$first | ConvertTo-Json -Depth 20 | ConvertFrom-Json
    $visual | Add-Member MemberSegmentIndices @($Indices) -Force
    if($Indices.Count -eq 1){return $visual}
    $fps=[double]$Plan.frameRate
    $source=[int]$last.SourceEndFrame-[int]$first.SourceStartFrame
    $output=[int]$last.NewEndFrame-[int]$first.NewStartFrame
    $visual.Unit='speed-merged-sentences'
    foreach($field in @('SourceEndFrame','NewEndFrame','OriginalVoiceEndFrame','NewVoiceEndFrame','LastTargetCue','SafeVoiceCut','BoundarySilenceDuration')){$visual.$field=$last.$field}
    $visual.SourceDurationFrames=$source;$visual.EffectiveSourceDurationFrames=$source
    $visual.OutputDurationFrames=$output;$visual.VisualDurationFrames=$output
    $visual.SourceEnd=[Math]::Round($last.SourceEndFrame/$fps,6)
    $visual.NewEnd=[Math]::Round($last.NewEndFrame/$fps,6)
    $visual.SourceDuration=[Math]::Round($source/$fps,6);$visual.EffectiveSourceDuration=$visual.SourceDuration
    $visual.OutputDuration=[Math]::Round($output/$fps,6)
    $visual.OriginalVoiceEnd=[Math]::Round($last.OriginalVoiceEndFrame/$fps,6)
    $visual.NewVoiceEnd=[Math]::Round($last.NewVoiceEndFrame/$fps,6)
    $speed=100.0*$source/$output
    $visual.DesiredSpeedPercent=[Math]::Round($speed,6);$visual.AppliedSpeedPercent=[Math]::Round($speed,9)
    $visual.SpeedOutsideWarningRange=(Get-PvsSpeedDistance $speed $Plan.speedWarningMinPercent $Plan.speedWarningMaxPercent) -gt 0
    $visual.Confidence=($items | Measure-Object Confidence -Minimum).Minimum
    $visual.Text=($items.Text -join ' ')
    $visual | Add-Member Chapters @($items.Chapter | Select-Object -Unique) -Force
    return $visual
}

function Test-PvsSpeedMergeAdjacent($Left,$Right) {
    return $Left.Kind -eq 'retime' -and $Right.Kind -eq 'retime' -and
        $Left.SourceEndFrame -eq $Right.SourceStartFrame -and $Left.NewEndFrame -eq $Right.NewStartFrame -and
        $Left.OriginalVoiceEndFrame -eq $Right.OriginalVoiceStartFrame
}

function Assert-PvsSpeedMergePlan($Baseline,$Candidate) {
    if(-not $Baseline.ok -or $Baseline.schemaVersion -ne 8 -or $Baseline.plannerRevision -ne 18 -or
        $Candidate.speedMergeTrial -cne 'adjacent-speed-v2'){throw 'SPEED_MERGE_PLAN_INVALID'}
    # Only visual grouping and its own summary may change, including byte-equivalent
    # voice segments, clip speeds, captions, markers and protected template fields.
    $a=$Baseline | ConvertTo-Json -Depth 30 | ConvertFrom-Json
    $b=$Candidate | ConvertTo-Json -Depth 30 | ConvertFrom-Json
    foreach($field in @('speedMergeTrial','visualSegments','speedMergeSummary')){$b.PSObject.Properties.Remove($field)}
    if(($a | ConvertTo-Json -Depth 30 -Compress) -cne ($b | ConvertTo-Json -Depth 30 -Compress)){throw 'SPEED_MERGE_PROTECTED_PLAN_CHANGED'}
    $next=0
    foreach($visual in @($Candidate.visualSegments)){
        $indices=@($visual.MemberSegmentIndices)
        if(-not $indices.Count){throw 'SPEED_MERGE_MEMBER_MISSING'}
        if($indices.Count -gt 2){throw 'SPEED_MERGE_PAIR_LIMIT_EXCEEDED'}
        foreach($index in $indices){if($index -ne $next -or $next -ge @($Baseline.segments).Count){throw 'SPEED_MERGE_COVERAGE_CHANGED'};$next++}
        $expected=New-PvsVisualSpeedGroup $Baseline $indices
        if(-not (Test-PvsSpeedMergeAcousticAnchors $Baseline $expected)){throw 'SPEED_MERGE_ACOUSTIC_ANCHOR_MOVED'}
        if(($visual | ConvertTo-Json -Depth 20 -Compress) -cne ($expected | ConvertTo-Json -Depth 20 -Compress)){throw 'SPEED_MERGE_VISUAL_FIELDS_CHANGED'}
        for($i=1;$i -lt $indices.Count;$i++){
            if(-not (Test-PvsSpeedMergeAdjacent $Baseline.segments[$indices[$i-1]] $Baseline.segments[$indices[$i]])){throw 'SPEED_MERGE_CROSSED_PROTECTED_GAP'}
        }
    }
    if($next -ne @($Baseline.segments).Count){throw 'SPEED_MERGE_COVERAGE_CHANGED'}
    return $true
}

function Test-PvsSpeedMergeAcousticAnchors($Plan,$Visual) {
    if(-not $Plan.PSObject.Properties['acousticEditBoundaryRevision']){return $true}
    # Balancing picture speed must not undo a separately certified sync edge.
    $indices=@($Visual.MemberSegmentIndices)
    for($i=0;$i+1 -lt $indices.Count;$i++){
        $left=$Plan.segments[$indices[$i]]
        $mapped=$Visual.NewStartFrame+($left.SourceEndFrame-$Visual.SourceStartFrame)*[double]$Visual.OutputDurationFrames/$Visual.SourceDurationFrames
        if([Math]::Abs($mapped-$left.NewEndFrame) -gt 1.0+0.000001){return $false}
    }
    return $true
}

function Get-PvsSpeedMergeTrial($Plan) {
    if(-not $Plan.ok -or $Plan.schemaVersion -ne 8 -or $Plan.plannerRevision -ne 18){throw 'SPEED_MERGE_STABLE_PLAN_REQUIRED'}
    if($Plan.PSObject.Properties['visualSegments'] -or $Plan.PSObject.Properties['speedMergeTrial']){throw 'SPEED_MERGE_ALREADY_APPLIED'}
    $minimum=[double]$Plan.speedWarningMinPercent;$maximum=[double]$Plan.speedWarningMaxPercent
    $validationJob=[pscustomobject]@{workflow='experimental-dtw-direct';speedMergeTrial='adjacent-speed-v2';speedWarningMinPercent=$minimum;speedWarningMaxPercent=$maximum}
    Assert-PvsSpeedMergeInput $validationJob
    $fps=[double]$Plan.frameRate
    if([double]::IsNaN($fps) -or [double]::IsInfinity($fps) -or $fps -le 0){throw 'SPEED_MERGE_FRAME_RATE_INVALID'}
    $groups=New-Object System.Collections.Generic.List[object]
    $sourceEnd=$null;$outputEnd=$null
    for($i=0;$i -lt @($Plan.segments).Count;$i++){
        $segment=$Plan.segments[$i]
        foreach($field in @('SourceStartFrame','SourceEndFrame','NewStartFrame','NewEndFrame')){
            $value=[double]$segment.$field
            if([double]::IsNaN($value) -or [double]::IsInfinity($value) -or $value -lt 0 -or $value -ne [Math]::Floor($value)){throw 'SPEED_MERGE_FRAME_INVALID'}
        }
        if($segment.SourceEndFrame -le $segment.SourceStartFrame -or $segment.NewEndFrame -le $segment.NewStartFrame -or
            ($null -ne $sourceEnd -and ($segment.SourceStartFrame -ne $sourceEnd -or $segment.NewStartFrame -ne $outputEnd))){throw 'SPEED_MERGE_PLAN_DISCONTINUOUS'}
        if($segment.Kind -notin @('gap','retime')){throw 'SPEED_MERGE_SEGMENT_KIND_INVALID'}
        if($segment.SourceDurationFrames -ne $segment.SourceEndFrame-$segment.SourceStartFrame -or $segment.OutputDurationFrames -ne $segment.NewEndFrame-$segment.NewStartFrame){throw 'SPEED_MERGE_DURATION_INVALID'}
        $sourceEnd=$segment.SourceEndFrame;$outputEnd=$segment.NewEndFrame
        # The per-cue picture plan already owns its acoustic anchors. Keep
        # the physical A2 plan intact instead of coalescing those cue units.
        $groups.Add([pscustomobject]@{Visual=(New-PvsVisualSpeedGroup $Plan @($i));Blocked=[bool]$Plan.PSObject.Properties['pictureCueRevision']})
    }
    if(-not $groups.Count -or $sourceEnd -ne $Plan.mainVideoSourceEndFrame -or $outputEnd -ne $Plan.plannedMainVideoEndFrame){throw 'SPEED_MERGE_TAIL_INVALID'}
    $steps=New-Object System.Collections.Generic.List[object]
    while($true){
        $at=-1;$distance=0.0
        # Process worst remaining outlier first; stable left-to-right tie break.
        for($i=0;$i -lt $groups.Count;$i++){
            if($groups[$i].Blocked -or $groups[$i].Visual.Kind -ne 'retime' -or @($groups[$i].Visual.MemberSegmentIndices).Count -ne 1){continue}
            $v=$groups[$i].Visual;$speed=100.0*$v.SourceDurationFrames/$v.OutputDurationFrames
            $d=Get-PvsSpeedDistance $speed $minimum $maximum
            if($d -gt $distance+0.000000001){$at=$i;$distance=$d}
        }
        if($at -lt 0){break}
        $target=$groups[$at].Visual;$best=$null
        foreach($neighbor in @(($at-1),($at+1))){
            if($neighbor -lt 0 -or $neighbor -ge $groups.Count){continue}
            # A consumed pair cannot be absorbed by any later outlier.
            if(@($groups[$neighbor].Visual.MemberSegmentIndices).Count -ne 1){continue}
            $left=[Math]::Min($at,$neighbor);$right=[Math]::Max($at,$neighbor)
            if(-not (Test-PvsSpeedMergeAdjacent $groups[$left].Visual $groups[$right].Visual)){continue}
            $indices=@($groups[$left].Visual.MemberSegmentIndices)+@($groups[$right].Visual.MemberSegmentIndices)
            $merged=New-PvsVisualSpeedGroup $Plan $indices
            if(-not (Test-PvsSpeedMergeAcousticAnchors $Plan $merged)){continue}
            $d=Get-PvsSpeedDistance $merged.AppliedSpeedPercent $minimum $maximum
            if($d -ge $distance-0.000000001){continue}
            $duration=$groups[$neighbor].Visual.OutputDurationFrames
            if($null -eq $best -or $d -lt $best.Distance-0.000000001 -or ([Math]::Abs($d-$best.Distance) -le 0.000000001 -and $duration -lt $best.NeighborDuration)){
                $best=[pscustomobject]@{Left=$left;Right=$right;Distance=$d;Visual=$merged;NeighborDuration=$duration;Direction=if($neighbor -lt $at){'previous'}else{'next'}}
            }
        }
        if($null -eq $best){$groups[$at].Blocked=$true;continue}
        $steps.Add([pscustomobject]@{TargetMembers=@($target.MemberSegmentIndices);Direction=$best.Direction;BeforeSpeed=$target.AppliedSpeedPercent;AfterSpeed=$best.Visual.AppliedSpeedPercent;Members=@($best.Visual.MemberSegmentIndices);DistanceBefore=$distance;DistanceAfter=$best.Distance})
        $groups[$best.Left]=[pscustomobject]@{Visual=$best.Visual;Blocked=$true}
        $groups.RemoveAt($best.Right)
        # Stop for this pair even when still outside the band. The host will
        # attach its ordinary speed warning marker to the merged V1 clip.
    }
    $candidate=$Plan | ConvertTo-Json -Depth 30 | ConvertFrom-Json
    $candidate | Add-Member speedMergeTrial 'adjacent-speed-v2'
    $candidate | Add-Member visualSegments @($groups | ForEach-Object {$_.Visual})
    $before=@($Plan.segments | Where-Object Kind -eq 'retime')
    $after=@($candidate.visualSegments | Where-Object Kind -eq 'retime')
    $warningsBefore=@($before | Where-Object {(Get-PvsSpeedDistance (100.0*$_.SourceDurationFrames/$_.OutputDurationFrames) $minimum $maximum) -gt 0}).Count
    $warningsAfter=@($after | Where-Object {(Get-PvsSpeedDistance (100.0*$_.SourceDurationFrames/$_.OutputDurationFrames) $minimum $maximum) -gt 0}).Count
    $candidate | Add-Member speedMergeSummary ([pscustomobject]@{mergePolicy='single-adjacent-pair';mergeCount=$steps.Count;visualGroupsBefore=$before.Count;visualGroupsAfter=$after.Count;warningsBefore=$warningsBefore;warningsAfter=$warningsAfter;voiceGroupsUnchanged=$before.Count;steps=$steps.ToArray()})
    $null=Assert-PvsSpeedMergePlan $Plan $candidate
    return $candidate
}
