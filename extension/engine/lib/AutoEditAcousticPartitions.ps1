Set-StrictMode -Version Latest

function Get-PvsAcousticReferenceCuts {
    param([object[]]$References,[object[]]$Words,[object[]]$Voices,[object[]]$Quiet,[double]$FrameRate,[double]$MinimumSilence=0.12,[double]$SafetyMargin=0.04)
    if([double]::IsNaN($FrameRate) -or [double]::IsInfinity($FrameRate) -or $FrameRate -le 0){throw 'ACOUSTIC_PARTITION_FRAME_RATE_INVALID'}
    $raw=@{};$reference=@{};$layout=New-PvsReferenceWordLayout $References
    for($i=0;$i+3 -lt $Words.Count;$i++){
        if($Words[$i].Chapter -ne $Words[$i+3].Chapter){continue}
        $key=@($Words[$i..($i+3)].Text) -join ' '
        if(-not $raw.ContainsKey($key)){$raw[$key]=New-Object System.Collections.Generic.List[int]};$raw[$key].Add($i)
    }
    for($i=0;$i+3 -lt $layout.Words.Count;$i++){
        $key=@($layout.Words[$i..($i+3)]) -join ' '
        if(-not $reference.ContainsKey($key)){$reference[$key]=0};$reference[$key]++
    }
    $cuts=New-Object System.Collections.Generic.List[object]
    for($i=0;$i+1 -lt $References.Count;$i++){
        $left=@(ConvertTo-NormalizedWords $References[$i].Text);$right=@(ConvertTo-NormalizedWords $References[$i+1].Text)
        if($left.Count -lt 4 -or $right.Count -lt 4){continue}
        $aKey=@($left[($left.Count-4)..($left.Count-1)]) -join ' ';$bKey=@($right[0..3]) -join ' '
        if(-not $raw.ContainsKey($aKey) -or -not $raw.ContainsKey($bKey) -or $raw[$aKey].Count -ne 1 -or $raw[$bKey].Count -ne 1 -or $reference[$aKey] -ne 1 -or $reference[$bKey] -ne 1){continue}
        $a=$raw[$aKey][0];$b=$raw[$bKey][0]
        if($b -ne $a+4 -or $Words[$a].Chapter -ne $Words[$b+3].Chapter){continue}
        $chapter=[int]$Words[$a].Chapter
        if($chapter -lt 0 -or $chapter -ge $Voices.Count){continue}
        if($Voices[$chapter].PSObject.Properties['inPoint'] -and [double]$Voices[$chapter].inPoint -ne 0){continue}
        $context=@($Words[$a..($b+3)]);$offset=[double]$Voices[$chapter].start;$edge=0.0;$valid=$true
        foreach($word in $context){
            $start=[double]$word.Start;$end=[double]$word.End
            if(-not $word.PSObject.Properties['SubtitleTimingQuality'] -or $word.SubtitleTimingQuality -ne 'dtw' -or [double]::IsNaN($start) -or [double]::IsNaN($end) -or [double]::IsInfinity($start) -or [double]::IsInfinity($end) -or $start -lt $edge-0.000001 -or $end -le $start -or $offset+$end -gt $Voices[$chapter].end+0.000001){$valid=$false;break};$edge=$end
        }
        if(-not $valid){continue}
        $end=$offset+$context[3].End;$start=$offset+$context[4].Start
        $matches=@($Quiet | Where-Object {$_.Start -ge $end-0.08 -and $_.End -le $start+0.08 -and $_.Duration -ge $MinimumSilence-0.000001 -and $_.Start -ge $Voices[$chapter].start -and $_.End -le $Voices[$chapter].end})
        if($matches.Count -ne 1){continue}
        $q=$matches[0]
        $first=[int][Math]::Ceiling([Math]::Max($q.Start+$SafetyMargin,$end+$SafetyMargin)*$FrameRate-0.000001)
        $last=[int][Math]::Floor([Math]::Min($q.End-$SafetyMargin,$start-$SafetyMargin)*$FrameRate+0.000001)
        if($first -gt $last){continue}
        $frame=[Math]::Max($first,[Math]::Min($last,[int][Math]::Round(($q.Start+$q.End)*0.5*$FrameRate)))
        $cuts.Add([pscustomobject]@{revision='raw-dtw-quiet-partition-v1';leftCue=[int]$References[$i].Index;rightCue=[int]$References[$i+1].Index;chapter=$chapter;cutFrame=$frame;context=$context;quietStart=$q.Start;quietEnd=$q.End})
    }
    # A reordered reference cannot gain permission from isolated matching phrases.
    $bad=@{}
    for($i=1;$i -lt $cuts.Count;$i++){if($cuts[$i].chapter -lt $cuts[$i-1].chapter -or ($cuts[$i].chapter -eq $cuts[$i-1].chapter -and $cuts[$i].cutFrame -le $cuts[$i-1].cutFrame)){$bad[$i-1]=$true;$bad[$i]=$true}}
    for($i=0;$i -lt $cuts.Count;$i++){if(-not $bad.ContainsKey($i)){$cuts[$i]}}
}

function Test-PvsAcousticReferenceCut {
    param($Proof,[object[]]$References,[object[]]$Voices,[object[]]$Quiet,[double]$FrameRate,[double]$MinimumSilence=0.12,[double]$SafetyMargin=0.04)
    if($Proof.revision -ceq 'whole-cue-dtw-quiet-v1'){return Test-PvsWholeCueQuietCut $Proof $References $Voices $Quiet $FrameRate $MinimumSilence $SafetyMargin}
    if([double]::IsNaN($FrameRate) -or [double]::IsInfinity($FrameRate) -or $FrameRate -le 0){return $false}
    if($Proof.revision -cne 'raw-dtw-quiet-partition-v1' -or $Proof.leftCue -lt 1 -or $Proof.rightCue -ne $Proof.leftCue+1 -or $Proof.rightCue -gt $References.Count -or $Proof.chapter -lt 0 -or $Proof.chapter -ge $Voices.Count -or @($Proof.context).Count -ne 8){return $false}
    $voice=$Voices[$Proof.chapter]
    if($voice.PSObject.Properties['inPoint'] -and [double]$voice.inPoint -ne 0){return $false}
    $left=@(ConvertTo-NormalizedWords $References[$Proof.leftCue-1].Text);$right=@(ConvertTo-NormalizedWords $References[$Proof.rightCue-1].Text)
    if($left.Count -lt 4 -or $right.Count -lt 4){return $false}
    $expected=@($left[($left.Count-4)..($left.Count-1)])+@($right[0..3]);$voice=$Voices[$Proof.chapter];$edge=0.0
    for($i=0;$i -lt 8;$i++){
        $w=$Proof.context[$i];$a=[double]$w.Start;$b=[double]$w.End
        if($w.Text -cne $expected[$i] -or $w.Chapter -ne $Proof.chapter -or $w.SubtitleTimingQuality -cne 'dtw' -or [double]::IsNaN($a) -or [double]::IsInfinity($a) -or [double]::IsNaN($b) -or [double]::IsInfinity($b) -or $a -lt $edge-0.000001 -or $b -le $a -or $voice.start+$b -gt $voice.end+0.000001){return $false};$edge=$b
    }
    $cut=[double]$Proof.cutFrame/$FrameRate;$end=[double]$voice.start+$Proof.context[3].End;$start=[double]$voice.start+$Proof.context[4].Start
    if([double]::IsNaN($cut) -or [double]::IsInfinity($cut) -or $Proof.cutFrame -ne [Math]::Floor($Proof.cutFrame) -or $cut -lt $end+$SafetyMargin-0.000001 -or $cut -gt $start-$SafetyMargin+0.000001){return $false}
    $matches=@($Quiet | Where-Object {$_.Duration -ge $MinimumSilence-0.000001 -and $_.Start -ge $end-0.08 -and $_.End -le $start+0.08 -and $cut -ge $_.Start+$SafetyMargin-0.000001 -and $cut -le $_.End-$SafetyMargin+0.000001})
    return $matches.Count -eq 1
}

function Get-PvsReferenceCueEvidence {
    param([object[]]$References,[object[]]$Words,[object[]]$Cues,[object[]]$Voices)
    $unique=@{};foreach($r in $References){$key=@(ConvertTo-NormalizedWords $r.Text) -join ' ';if(-not $unique.ContainsKey($key)){$unique[$key]=0};$unique[$key]++}
    $by=@{}
    if($Words.Count){
        foreach($m in @(Align-CuesToRecognizedWords $References $Words $Voices)){
            $m|Add-Member CaptionWordTimings @($m.WordTimings) -Force
            $m|Add-Member CaptionTimingRevision 'dtw-word-boundary-v1' -Force
            if($m.Chapter -ge 0 -and $m.Chapter -lt $Voices.Count -and (Test-PvsAcousticEditCue $m $Voices[$m.Chapter]) -and -not @($m.WordTimings|Where-Object {-not $_.PSObject.Properties['SubtitleTimingQuality'] -or $_.SubtitleTimingQuality -ne 'dtw'}).Count){$by[[int]$m.Index]=$m}
        }
    }
    foreach($cue in $Cues){
        if($cue.PSObject.Properties['ManualEditBlock'] -and $cue.ManualEditBlock){
            foreach($cell in $cue.ManualCaptionCues){
                if($cell.ReferenceCueIndices.Count -ne 1 -or -not (Test-PvsManualAcousticCell $cell $Voices[$cue.Chapter])){continue}
                $index=[int]$cell.ReferenceCueIndices[0]
                if($index -lt 1 -or $index -gt $References.Count -or $cell.Text -cne $References[$index-1].Text){continue}
                $by[$index]=[pscustomobject]@{Index=$index;Chapter=[int]$cue.Chapter;Text=$cell.Text;CaptionWordTimings=$cell.CaptionWordTimings;CaptionTimingRevision='dtw-word-boundary-v1'}
            }
        }elseif(Test-PvsAcousticEditCue $cue $Voices[$cue.Chapter]){$by[[int]$cue.Index]=$cue}
    }
    foreach($index in @($by.Keys|Sort-Object)){
        $e=$by[$index];$key=@(ConvertTo-NormalizedWords $e.Text) -join ' ';$voice=$Voices[$e.Chapter]
        if($unique[$key] -ne 1 -or ($voice.PSObject.Properties['inPoint'] -and $voice.inPoint -ne 0)){continue}
        if(@($e.CaptionWordTimings|Where-Object {-not $_.PSObject.Properties['SubtitleTimingQuality'] -or $_.SubtitleTimingQuality -cne 'dtw'}).Count){continue}
        [pscustomobject]@{Index=[int]$index;Chapter=[int]$e.Chapter;Text=$e.Text;CaptionTimingRevision='dtw-word-boundary-v1';CaptionWordTimings=$e.CaptionWordTimings}
    }
}

function Restore-PvsObservedManualReferenceCells {
    param([object[]]$Cues,[object[]]$References,[object[]]$Words,[object[]]$Voices)
    if(-not $Words.Count){return}
    $layout=New-PvsReferenceWordLayout $References
    $mapping=@(Get-SequentialWordMapping $layout.Words $Words)
    $exact=@{}
    for($i=0;$i -lt $References.Count;$i++){
        $first=$layout.CueStarts[$i];$last=$layout.CueEnds[$i]-1;$indices=@();$valid=$true
        for($at=$first;$at -le $last;$at++){
            $r=$mapping[$at]
            if($r -lt 0 -or $Words[$r].Text -cne $layout.Words[$at] -or $Words[$r].SubtitleTimingQuality -cne 'dtw' -or ($indices.Count -and $r -ne $indices[-1]+1)){$valid=$false;break};$indices+= [int]$r
        }
        if(-not $valid -or -not $indices.Count){continue}
        $raw=@($Words[$indices[0]..$indices[-1]]);$ch=[int]$raw[0].Chapter
        if(@($raw|Where-Object Chapter -ne $ch).Count -or $ch -lt 0 -or $ch -ge $Voices.Count){continue}
        $heard=@(Align-CuesToRecognizedWords @($References[$i]) $raw $Voices)[0]
        $heard.Index=$i+1;$heard.Chapter=$ch
        $heard|Add-Member CaptionWordTimings @($heard.WordTimings) -Force;$heard|Add-Member CaptionTimingRevision 'dtw-word-boundary-v1' -Force
        if(Test-PvsAcousticEditCue $heard $Voices[$ch]){$exact[$i+1]=[pscustomobject]@{Cue=$heard;RawStart=$indices[0];RawEnd=$indices[-1]}}
    }
    $retained=@{};foreach($cue in $Cues){if($cue.PSObject.Properties['ManualEditBlock'] -and $cue.ManualEditBlock){foreach($cell in $cue.ManualCaptionCues){foreach($id in $cell.ReferenceCueIndices){$retained[[int]$id]=$true}}}else{$retained[[int]$cue.Index]=$true}}
    foreach($cue in $Cues){
        if(-not $cue.PSObject.Properties['ManualEditBlock'] -or -not $cue.ManualEditBlock){continue}
        # Text recovery already has an owned source window and chapter. A
        # repeated sentence elsewhere is harmless; ambiguity inside this
        # window stays unresolved. Cut evidence retains global uniqueness.
        $unique=@{}
        foreach($id in $cue.ManualReferenceCueIndices){$key=@(ConvertTo-NormalizedWords $References[[int]$id-1].Text) -join ' ';if(-not $unique.ContainsKey($key)){$unique[$key]=0};$unique[$key]++}
        $cells=New-Object System.Collections.Generic.List[object]
        for($cellIndex=0;$cellIndex -lt $cue.ManualCaptionCues.Count;$cellIndex++){
            $cell=$cue.ManualCaptionCues[$cellIndex]
            if($cell.ReferenceCueIndices.Count){$cells.Add($cell);continue}
            $options=@($cue.ManualReferenceCueIndices|Where-Object {$exact.ContainsKey([int]$_) -and -not $retained.ContainsKey([int]$_)}|ForEach-Object {$exact[[int]$_]}|Where-Object {$unique[(@(ConvertTo-NormalizedWords $_.Cue.Text) -join ' ')] -eq 1 -and $_.Cue.Chapter -eq $cue.Chapter -and $_.Cue.Start -ge $cell.Start-0.4 -and $_.Cue.End -le $cell.End+0.4}|Sort-Object {$_.Cue.Index})
            if(-not $options.Count){$cells.Add($cell);continue}
            $valid=$true
            $previous=if($cells.Count){[double]$cells[-1].End}else{[double]$cue.Start}
            $next=if($cellIndex+1 -lt $cue.ManualCaptionCues.Count){[double]$cue.ManualCaptionCues[$cellIndex+1].Start}else{[double]$cue.End}
            if($options[0].Cue.Start -lt $previous-0.000001 -or $options[-1].Cue.End -gt $next+0.000001){$valid=$false}
            for($i=1;$i -lt $options.Count;$i++){if($options[$i].Cue.Index -ne $options[$i-1].Cue.Index+1 -or $options[$i].RawStart -ne $options[$i-1].RawEnd+1){$valid=$false}}
            $text=(@($options|ForEach-Object {$_.Cue.Text}) -join ' ');$source=@(ConvertTo-NormalizedWords $text);$primary=@(ConvertTo-NormalizedWords $cell.Text)
            $map=@(Get-SequentialWordMapping $source @($primary|ForEach-Object {[pscustomobject]@{Text=$_}}))
            $matched=0;for($i=0;$i -lt $map.Count;$i++){if($map[$i] -ge 0 -and $source[$i] -ceq $primary[$map[$i]]){$matched++}}
            # Full consecutive observed speech proves the selected SRT words.
            # Existing primary must identify the same utterance; conflicting
            # numeric values, surplus words or ambiguous candidates stay raw.
            $digitsA=@([regex]::Matches($cell.Text,'\d+')|ForEach-Object Value) -join ' ';$digitsB=@([regex]::Matches($text,'\d+')|ForEach-Object Value) -join ' '
            if(-not $valid -or $primary.Count -gt $source.Count -or $source.Count-$primary.Count -gt 2 -or -not $source.Count -or $matched/[double]$source.Count -lt 0.85 -or $digitsA -cne $digitsB){$cells.Add($cell);continue}
            $first=$true
            foreach($option in $options){
                $m=$option.Cue;$v=$Voices[$m.Chapter]
                $new=[pscustomobject]@{Text=$m.Text;Start=[double]$m.Start;End=[double]$m.End;ReferenceCueIndices=@([int]$m.Index);Chapter=[int]$m.Chapter;CaptionWordTimings=$m.CaptionWordTimings;CaptionTimingRevision='raw-dtw-cell-overlay-v1';TimingVoiceStart=[double]$v.start;TimingVoiceEnd=[double]$v.end;ReferenceRecoveryRevision='complete-observed-dtw-reference-v1'}
                if($first){$new|Add-Member RecognitionOriginalText $cell.Text;$first=$false}
                $cells.Add($new);$retained[[int]$m.Index]=$true;[int]$m.Index
            }
        }
        $cue.ManualCaptionCues=$cells.ToArray();$cue.Text=($cue.ManualCaptionCues.Text -join ' ')
    }
}

function Get-PvsWholeCueQuietCuts {
    param([object[]]$Evidence,[object[]]$Words,[object[]]$Voices,[object[]]$Quiet,[double]$FrameRate,[object[]]$Existing,[double]$MinimumSilence=0.12,[double]$SafetyMargin=0.04)
    $by=@{};$cuts=@{};foreach($e in $Evidence){$by[[int]$e.Index]=$e};foreach($cut in $Existing){$cuts[[int]$cut.leftCue]=$cut}
    foreach($index in @($by.Keys|Sort-Object)){
        if($cuts.ContainsKey($index) -or -not $by.ContainsKey($index+1)){continue}
        $left=$by[$index];$right=$by[$index+1];$ch=[int]$left.Chapter
        if($ch -ne $right.Chapter){continue}
        $end=[double]$left.CaptionWordTimings[-1].End;$start=[double]$right.CaptionWordTimings[0].Start
        if($start -le $end){continue}
        $extra=@($Words|Where-Object {$_.Chapter -eq $ch -and $Voices[$ch].start+$_.Start -ge $end+0.08 -and $Voices[$ch].start+$_.End -le $start-0.08})
        if($extra.Count){continue}
        $q=@($Quiet|Where-Object {$_.Start -ge $end-0.08 -and $_.End -le $start+0.08 -and $_.Duration -ge $MinimumSilence -and $_.Start -ge $Voices[$ch].start -and $_.End -le $Voices[$ch].end})
        if($q.Count -ne 1){continue}
        $first=[int][Math]::Ceiling([Math]::Max($q[0].Start+$SafetyMargin,$end+$SafetyMargin)*$FrameRate-0.000001)
        $last=[int][Math]::Floor([Math]::Min($q[0].End-$SafetyMargin,$start-$SafetyMargin)*$FrameRate+0.000001)
        if($first -gt $last){continue}
        $frame=[Math]::Max($first,[Math]::Min($last,[int][Math]::Round(($q[0].Start+$q[0].End)*0.5*$FrameRate)))
        $cuts[$index]=[pscustomobject]@{revision='whole-cue-dtw-quiet-v1';leftCue=$index;rightCue=$index+1;chapter=$ch;cutFrame=$frame;leftEvidence=$left;rightEvidence=$right;quietStart=$q[0].Start;quietEnd=$q[0].End}
    }
    $ordered=@($cuts.Values|Sort-Object leftCue);$bad=@{}
    for($i=1;$i -lt $ordered.Count;$i++){if($ordered[$i].chapter -lt $ordered[$i-1].chapter -or ($ordered[$i].chapter -eq $ordered[$i-1].chapter -and $ordered[$i].cutFrame -le $ordered[$i-1].cutFrame)){$bad[$i-1]=$true;$bad[$i]=$true}}
    for($i=0;$i -lt $ordered.Count;$i++){if(-not $bad.ContainsKey($i)){$ordered[$i]}}
}

function Test-PvsWholeCueQuietCut {
    param($Proof,[object[]]$References,[object[]]$Voices,[object[]]$Quiet,[double]$FrameRate,[double]$MinimumSilence,[double]$SafetyMargin)
    $counts=New-PvsAcousticReferenceTextCounts $References
    return Test-PvsWholeCueQuietCutIndexed $Proof $References $Voices $Quiet $FrameRate $MinimumSilence $SafetyMargin $counts
}

function New-PvsAcousticReferenceTextCounts {
    param([object[]]$References)
    # Match PowerShell's case-sensitive invariant-culture string equality.
    # Rebuild from current references for every batch; never deserialize or
    # persist this index as proof, or trust an index supplied by a plan.
    $counts=New-Object 'System.Collections.Generic.Dictionary[string,int]' ([StringComparer]::InvariantCulture)
    foreach($reference in $References){
        $key=@(ConvertTo-NormalizedWords $reference.Text) -join ' '
        if($counts.ContainsKey($key)){$counts[$key]++}else{$counts[$key]=1}
    }
    return ,$counts
}

function Test-PvsAcousticReferenceCuts {
    param([object[]]$Proofs,[object[]]$References,[object[]]$Voices,[object[]]$Quiet,[double]$FrameRate,[double]$MinimumSilence=0.12,[double]$SafetyMargin=0.04,[switch]$RequireAll)
    $counts=$null
    foreach($proof in $Proofs){
        if($proof.revision -ceq 'whole-cue-dtw-quiet-v1'){
            if($null -eq $counts){$counts=New-PvsAcousticReferenceTextCounts $References}
            $valid=Test-PvsWholeCueQuietCutIndexed $proof $References $Voices $Quiet $FrameRate $MinimumSilence $SafetyMargin $counts
        }else{$valid=Test-PvsAcousticReferenceCut $proof $References $Voices $Quiet $FrameRate $MinimumSilence $SafetyMargin}
        if($RequireAll){if(-not $valid){throw 'ACOUSTIC_PARTITION_PROOF_INVALID'}}else{$valid}
    }
}

function Test-PvsWholeCueQuietCutIndexed {
    param($Proof,[object[]]$References,[object[]]$Voices,[object[]]$Quiet,[double]$FrameRate,[double]$MinimumSilence,[double]$SafetyMargin,[System.Collections.Generic.Dictionary[string,int]]$ReferenceTextCounts)
    if($FrameRate -le 0 -or [double]::IsNaN($FrameRate) -or [double]::IsInfinity($FrameRate) -or $Proof.rightCue -ne $Proof.leftCue+1 -or $Proof.leftCue -lt 1 -or $Proof.rightCue -gt $References.Count -or $Proof.chapter -lt 0 -or $Proof.chapter -ge $Voices.Count){return $false}
    $v=$Voices[$Proof.chapter]
    foreach($item in @(@{Cue=$Proof.leftEvidence;Index=$Proof.leftCue},@{Cue=$Proof.rightEvidence;Index=$Proof.rightCue})){
        $e=$item.Cue
        if($e.Index -ne $item.Index -or $e.Chapter -ne $Proof.chapter -or $e.Text -cne $References[$item.Index-1].Text -or -not (Test-PvsAcousticEditCue $e $v)){return $false}
        if(@($e.CaptionWordTimings|Where-Object {-not $_.PSObject.Properties['SubtitleTimingQuality'] -or $_.SubtitleTimingQuality -ne 'dtw'}).Count){return $false}
        $key=@(ConvertTo-NormalizedWords $e.Text) -join ' '
        if(-not $ReferenceTextCounts.ContainsKey($key) -or $ReferenceTextCounts[$key] -ne 1){return $false}
    }
    if($v.PSObject.Properties['inPoint'] -and $v.inPoint -ne 0){return $false}
    $cut=[double]$Proof.cutFrame/$FrameRate;$end=[double]$Proof.leftEvidence.CaptionWordTimings[-1].End;$start=[double]$Proof.rightEvidence.CaptionWordTimings[0].Start
    if($Proof.cutFrame -ne [Math]::Floor($Proof.cutFrame) -or $cut -lt $end+$SafetyMargin-0.000001 -or $cut -gt $start-$SafetyMargin+0.000001){return $false}
    return @($Quiet|Where-Object {$_.Start -ge $end-0.08 -and $_.End -le $start+0.08 -and $_.Duration -ge $MinimumSilence-0.000001 -and $cut -ge $_.Start+$SafetyMargin-0.000001 -and $cut -le $_.End-$SafetyMargin+0.000001}).Count -eq 1
}

function Add-PvsCuePicturePlan {
    param($Plan,[object[]]$References,[object[]]$Evidence)
    if($Plan.PSObject.Properties['editedSourceMap'] -or -not $Evidence.Count){return}
    $fps=[double]$Plan.frameRate;$map=@(New-PvsCaptionVoiceMap $Plan.segments);$by=@{}
    foreach($e in $Evidence){$by[[int]$e.Index]=$e}
    $anchors=New-Object System.Collections.Generic.List[object]
    for($i=1;$i -lt $References.Count;$i++){
        $left=$by[$i];$right=$by[$i+1]
        if($null -eq $left -and $null -eq $right){continue}
        if($null -ne $left -and $null -ne $right -and $left.Chapter -ne $right.Chapter){continue}
        # Source pauses already handled by the physical-voice planner stay
        # intact; picture-only refinement never inserts silence into A2.
        if($References[$i].Start-$References[$i-1].End -ge $Plan.minNoDialogueGapSeconds){continue}
        $ch=if($null -ne $left){[int]$left.Chapter}else{[int]$right.Chapter}
        $time=if($null -ne $left -and $null -ne $right){($left.CaptionWordTimings[-1].End+$right.CaptionWordTimings[0].Start)/2.0}elseif($null -ne $left){$left.CaptionWordTimings[-1].End}else{$right.CaptionWordTimings[0].Start}
        $sf=[int][Math]::Round(($References[$i-1].End+$References[$i].Start)*0.5*$fps);$vf=[int][Math]::Round($time*$fps)
        # A real word can end exactly at a chapter/clip tail. That endpoint
        # has no following physical voice frame to subdivide; retain the
        # existing group rather than treating unavailable refinement as IO.
        if(-not @($map|Where-Object {$_.Chapter -eq $ch -and $vf -ge $_.OriginalVoiceStartFrame -and $vf -lt $_.OriginalVoiceEndFrame}).Count){continue}
        $of=Get-PvsMappedCaptionFrame $map $vf
        for($p=0;$p -lt $Plan.segments.Count;$p++){
            $s=$Plan.segments[$p]
            if($s.Kind -eq 'retime' -and $s.Chapter -eq $ch -and $sf -gt $s.SourceStartFrame -and $sf -lt $s.SourceEndFrame -and $of -gt $s.NewStartFrame -and $of -lt $s.NewEndFrame){
                $anchors.Add([pscustomobject]@{ParentSegmentIndex=$p;LeftCue=$i;RightCue=$i+1;SourceFrame=$sf;OutputFrame=$of;VoiceFrame=$vf;Chapter=$ch;LeftEvidenceCue=$(if($null -ne $left){$i}else{0});RightEvidenceCue=$(if($null -ne $right){$i+1}else{0})});break
            }
        }
    }
    # Conflicting acoustic positions stay local; do not invent frames or move
    # a verified neighbor to force a cue with no usable position into the plan.
    $bad=@{}
    for($i=1;$i -lt $anchors.Count;$i++){if($anchors[$i].ParentSegmentIndex -eq $anchors[$i-1].ParentSegmentIndex -and ($anchors[$i].SourceFrame -le $anchors[$i-1].SourceFrame -or $anchors[$i].OutputFrame -le $anchors[$i-1].OutputFrame)){$bad[$i-1]=$true;$bad[$i]=$true}}
    $accepted=@(for($i=0;$i -lt $anchors.Count;$i++){if(-not $bad.ContainsKey($i)){$anchors[$i]}})
    if(-not $accepted.Count){return}
    $pictures=New-Object System.Collections.Generic.List[object]
    for($p=0;$p -lt $Plan.segments.Count;$p++){
        $parent=$Plan.segments[$p];$cuts=@($accepted|Where-Object ParentSegmentIndex -eq $p)
        $sf=[int]$parent.SourceStartFrame;$of=[int]$parent.NewStartFrame;$first=[int]$(if($parent.Kind -eq 'retime'){$parent.FirstTargetCue}else{0})
        foreach($cut in @($cuts)+@($null)){
            $ef=if($null -ne $cut){[int]$cut.SourceFrame}else{[int]$parent.SourceEndFrame};$oe=if($null -ne $cut){[int]$cut.OutputFrame}else{[int]$parent.NewEndFrame}
            $piece=$parent|ConvertTo-Json -Depth 18|ConvertFrom-Json
            $piece|Add-Member ParentSegmentIndex $p
            if($parent.Kind -eq 'retime'){
                $piece.Unit='srt-cue-picture';$piece.SourceStartFrame=$sf;$piece.SourceEndFrame=$ef;$piece.NewStartFrame=$of;$piece.NewEndFrame=$oe
                $piece.SourceDurationFrames=$ef-$sf;$piece.EffectiveSourceDurationFrames=$ef-$sf;$piece.OutputDurationFrames=$oe-$of;$piece.VisualDurationFrames=$oe-$of
                $piece.SourceStart=[Math]::Round($sf/$fps,6);$piece.SourceEnd=[Math]::Round($ef/$fps,6);$piece.NewStart=[Math]::Round($of/$fps,6);$piece.NewEnd=[Math]::Round($oe/$fps,6)
                $piece.SourceDuration=[Math]::Round(($ef-$sf)/$fps,6);$piece.EffectiveSourceDuration=$piece.SourceDuration;$piece.OutputDuration=[Math]::Round(($oe-$of)/$fps,6)
                $piece.AppliedSpeedPercent=[Math]::Round(100.0*($ef-$sf)/($oe-$of),9);$piece.DesiredSpeedPercent=$piece.AppliedSpeedPercent
                $piece.SpeedOutsideWarningRange=$piece.AppliedSpeedPercent -lt $Plan.speedWarningMinPercent -or $piece.AppliedSpeedPercent -gt $Plan.speedWarningMaxPercent
                $piece.FirstTargetCue=$first;$piece.LastTargetCue=if($null -ne $cut){$cut.LeftCue}else{$parent.LastTargetCue}
                $first=$piece.LastTargetCue+1
            }
            $pictures.Add($piece);$sf=$ef;$of=$oe
        }
    }
    $Plan|Add-Member pictureCueRevision 'srt-cue-picture-v1' -Force
    $Plan|Add-Member pictureCueBoundaries $accepted -Force
    $Plan|Add-Member pictureSegments $pictures.ToArray() -Force
    $Plan|Add-Member pictureCueSummary ([pscustomobject]@{sourceCueCount=$References.Count;pictureGroups=@($pictures|Where-Object Kind -eq 'retime').Count;voiceGroups=@($Plan.segments|Where-Object Kind -eq 'retime').Count;pictureOnlyCuts=$accepted.Count;voiceUnchanged=$true}) -Force
    Assert-PvsCuePicturePlan $Plan
}

function Assert-PvsCuePicturePlan {
    param($Plan)
    if(-not $Plan.PSObject.Properties['pictureCueRevision']){return}
    if($Plan.pictureCueRevision -cne 'srt-cue-picture-v1' -or $Plan.PSObject.Properties['editedSourceMap']){throw 'PICTURE_CUE_CAPABILITY_INVALID'}
    $fps=[double]$Plan.frameRate;$used=0
    if($fps -le 0 -or [double]::IsNaN($fps) -or [double]::IsInfinity($fps)){throw 'PICTURE_CUE_FRAME_RATE_INVALID'}
    $map=@(New-PvsCaptionVoiceMap $Plan.segments)
    foreach($anchor in $Plan.pictureCueBoundaries){
        foreach($name in @('ParentSegmentIndex','SourceFrame','OutputFrame','VoiceFrame','Chapter','LeftCue','RightCue')){
            $value=[double]$anchor.($name)
            if($value -lt 0 -or [double]::IsNaN($value) -or [double]::IsInfinity($value) -or $value -ne [Math]::Floor($value)){throw 'PICTURE_CUE_ANCHOR_INVALID'}
        }
        if($anchor.ParentSegmentIndex -ge $Plan.segments.Count -or $anchor.LeftCue -lt 1 -or $anchor.RightCue -ne $anchor.LeftCue+1){throw 'PICTURE_CUE_ANCHOR_INVALID'}
        $parent=$Plan.segments[$anchor.ParentSegmentIndex]
        if($parent.Kind -ne 'retime' -or $anchor.Chapter -ne $parent.Chapter -or $anchor.VoiceFrame -le $parent.OriginalVoiceStartFrame -or $anchor.VoiceFrame -ge $parent.OriginalVoiceEndFrame -or (Get-PvsMappedCaptionFrame $map $anchor.VoiceFrame) -ne $anchor.OutputFrame){throw 'PICTURE_CUE_VOICE_ANCHOR_CHANGED'}
    }
    for($p=0;$p -lt $Plan.segments.Count;$p++){
        $parent=$Plan.segments[$p];$parts=@($Plan.pictureSegments|Where-Object ParentSegmentIndex -eq $p)
        if(-not $parts.Count){throw 'PICTURE_CUE_PARENT_LOST'}
        $sf=$parent.SourceStartFrame;$of=$parent.NewStartFrame
        foreach($part in $parts){
            if($part.SourceStartFrame -ne $sf -or $part.NewStartFrame -ne $of -or $part.SourceEndFrame -le $sf -or $part.NewEndFrame -le $of -or $part.Kind -cne $parent.Kind){throw 'PICTURE_CUE_FRAME_LOST'}
            if($part.SourceDurationFrames -ne $part.SourceEndFrame-$sf -or $part.OutputDurationFrames -ne $part.NewEndFrame-$of){throw 'PICTURE_CUE_DURATION_INVALID'}
            foreach($item in @(@{Name='SourceStart';Frame=$sf},@{Name='SourceEnd';Frame=$part.SourceEndFrame},@{Name='NewStart';Frame=$of},@{Name='NewEnd';Frame=$part.NewEndFrame})){if([Math]::Abs($part.($item.Name)*$fps-$item.Frame) -gt 0.001){throw 'PICTURE_CUE_TIME_INVALID'}}
            if($parent.Kind -eq 'gap'){foreach($property in $parent.PSObject.Properties){if(($part.($property.Name)|ConvertTo-Json -Depth 15 -Compress) -cne ($property.Value|ConvertTo-Json -Depth 15 -Compress)){throw 'PICTURE_CUE_GAP_CHANGED'}}}
            elseif([Math]::Abs($part.AppliedSpeedPercent-100.0*$part.SourceDurationFrames/$part.OutputDurationFrames) -gt 0.000001){throw 'PICTURE_CUE_SPEED_INVALID'}
            if($part.SourceEndFrame -ne $parent.SourceEndFrame){
                $a=@($Plan.pictureCueBoundaries|Where-Object {$_.ParentSegmentIndex -eq $p -and $_.SourceFrame -eq $part.SourceEndFrame -and $_.OutputFrame -eq $part.NewEndFrame})
                if($a.Count -ne 1){throw 'PICTURE_CUE_ANCHOR_LOST'};$used++
            }
            $sf=$part.SourceEndFrame;$of=$part.NewEndFrame
        }
        if($sf -ne $parent.SourceEndFrame -or $of -ne $parent.NewEndFrame){throw 'PICTURE_CUE_PARENT_TAIL_LOST'}
    }
    if($used -ne $Plan.pictureCueBoundaries.Count -or @($Plan.pictureSegments|Where-Object {$_.ParentSegmentIndex -lt 0 -or $_.ParentSegmentIndex -ge $Plan.segments.Count}).Count){throw 'PICTURE_CUE_COVERAGE_INVALID'}
}

function New-PvsAcousticEditGroups {
    param([object[]]$Cues,[object[]]$References,[object[]]$Voices,[object[]]$Cuts,[object[]]$Quiet,[double]$FrameRate,[double]$MinimumSilence=0.12,[double]$SafetyMargin=0.04)
    $validity=@(Test-PvsAcousticReferenceCuts $Cuts $References $Voices $Quiet $FrameRate $MinimumSilence $SafetyMargin)
    $approved=@(for($i=0;$i -lt $validity.Count;$i++){if($validity[$i]){$Cuts[$i]}})
    if(-not $approved.Count){return}
    $owners=@{}
    foreach($cue in $Cues){
        $indices=if($cue.PSObject.Properties['ManualEditBlock'] -and $cue.ManualEditBlock){@($cue.ManualReferenceCueIndices)}else{@([int]$cue.Index)}
        foreach($index in $indices){if($owners.ContainsKey([int]$index)){throw 'ACOUSTIC_REFERENCE_OWNER_DUPLICATED'};$owners[[int]$index]=[int]$cue.Chapter}
    }
    if($owners.Count -ne $References.Count){throw 'ACOUSTIC_REFERENCE_COVERAGE_INCOMPLETE'}
    $lastSource=0.0
    for($i=0;$i -lt $References.Count;$i++){
        $r=$References[$i]
        if($r.Index -ne $i+1 -or -not $owners.ContainsKey($i+1) -or $r.Start -lt $lastSource-0.000001 -or $r.End -le $r.Start -or [double]::IsNaN($r.Start) -or [double]::IsNaN($r.End)){throw 'ACOUSTIC_REFERENCE_LAYOUT_INVALID'};$lastSource=$r.End
    }
    $lastIndex=0
    for($ch=0;$ch -lt $Voices.Count;$ch++){
        $indices=@(1..$References.Count | Where-Object {$owners[$_] -eq $ch})
        if(-not $indices.Count -or $indices[0] -ne $lastIndex+1 -or $indices[-1]-$indices[0]+1 -ne $indices.Count){throw 'ACOUSTIC_REFERENCE_CHAPTER_ORDER_INVALID'}
        $chapterCuts=@($approved | Where-Object {$_.chapter -eq $ch -and $_.leftCue -ge $indices[0] -and $_.rightCue -le $indices[-1]} | Sort-Object leftCue)
        $first=$indices[0];$start=[double]$Voices[$ch].start
        foreach($cut in @($chapterCuts)+@($null)){
            $last=if($null -ne $cut){[int]$cut.leftCue}else{[int]$indices[-1]};$end=if($null -ne $cut){[double]$cut.cutFrame/$FrameRate}else{[double]$Voices[$ch].end}
            if($last -lt $first -or $end -le $start){throw 'ACOUSTIC_PARTITION_ORDER_INVALID'}
            $overlap=@($Cues | Where-Object {$_.Chapter -eq $ch -and $_.Start -lt $end -and $_.End -gt $start})
            [pscustomobject]@{FirstCue=$first;LastCue=$last;Chapter=$ch;VoiceStart=$start;VoiceEnd=$end;SourceStart=[double]$References[$first-1].Start;SourceEnd=[double]$References[$last-1].End;Confidence=0.0;Text=(@($References[($first-1)..($last-1)].Text) -join ' ');Cues=$overlap;SafeEnd=$true;BoundarySilenceDuration=$(if($null -ne $cut){$cut.quietEnd-$cut.quietStart}else{0.0})}
            $first=$last+1;$start=$end
        }
        $lastIndex=$indices[-1]
    }
}

function Set-PvsManualAcousticCaptionTimings {
    param([object[]]$Cues,[object[]]$Words,[object[]]$Voices,[scriptblock]$RecognizeWindow=$null,$RetryStats=$null,[object[]]$References=@())
    $count=0
    $referenceEvidence=@{}
    if($References.Count){foreach($e in @(Get-PvsReferenceCueEvidence $References $Words $Cues $Voices)){$referenceEvidence[[int]$e.Index]=$e}}
    for($ch=0;$ch -lt $Voices.Count;$ch++){
        if($Voices[$ch].PSObject.Properties['inPoint'] -and [double]$Voices[$ch].inPoint -ne 0){continue}
        $targets=New-Object System.Collections.Generic.List[object];$links=New-Object System.Collections.Generic.List[object]
        foreach($cue in $Cues){
            if($cue.Chapter -ne $ch){continue}
            $items=if($cue.PSObject.Properties['ManualEditBlock'] -and $cue.ManualEditBlock){@($cue.ManualCaptionCues)}else{@($cue)}
            foreach($cell in $items){$targets.Add([pscustomobject]@{Index=$targets.Count+1;Text=$cell.Text;Start=$cell.Start;End=$cell.End});$links.Add($(if($cue.PSObject.Properties['ManualEditBlock'] -and $cue.ManualEditBlock){$cell}else{$null}))}
        }
        $heard=@($Words | Where-Object Chapter -eq $ch)
        if(-not $targets.Count -or -not $heard.Count){continue}
        $mapped=@(Align-CuesToRecognizedWords $targets.ToArray() $heard $Voices)
        $proposals=@{}
        for($i=0;$i -lt $mapped.Count;$i++){
            $cell=$links[$i];if($null -eq $cell){continue};$m=$mapped[$i];$m.Chapter=$ch
            $m | Add-Member CaptionWordTimings @($m.WordTimings) -Force
            $m | Add-Member CaptionTimingRevision 'dtw-word-boundary-v1' -Force
            $valid=-not @($m.WordTimings | Where-Object {-not $_.PSObject.Properties['SubtitleTimingQuality'] -or $_.SubtitleTimingQuality -ne 'dtw'}).Count -and (Test-PvsAcousticEditCue $m $Voices[$ch])
            if(-not $valid -and $cell.ReferenceCueIndices.Count -eq 1 -and $referenceEvidence.ContainsKey([int]$cell.ReferenceCueIndices[0])){
                $e=$referenceEvidence[[int]$cell.ReferenceCueIndices[0]]
                if($e.Text -ceq $cell.Text -and $e.Chapter -eq $ch -and $e.CaptionWordTimings[0].Start -ge $cell.Start-0.4 -and $e.CaptionWordTimings[-1].End -le $cell.End+0.4){
                    $m=[pscustomobject]@{WordTimings=$e.CaptionWordTimings};$valid=$true
                }
            }
            if(-not $valid -and $null -ne $RecognizeWindow){
                # Retry only this display cell. The independent picture-cut
                # stream stays untouched, and every recovered word must pass
                # the same complete/85%-exact/physical DTW guards as before.
                $start=[Math]::Max([double]$Voices[$ch].start,[double]$cell.Start-0.4)
                $end=[Math]::Min([double]$Voices[$ch].end,[double]$cell.End+0.4)
                if($end-$start -gt 0.2 -and $end-$start -le 30){
                    if($null -ne $RetryStats){$RetryStats.Calls++}
                    try {$retryWords=@(& $RecognizeWindow $start $end $cell.Text $ch $true)}
                    catch {if($_.Exception.Message -match '^CAPTION_DTW_(ANCHOR|ANCHORS|SURFACE|DATA)'){$retryWords=@()}else{throw}}
                    if($retryWords.Count){
                        $local=@(Align-CuesToRecognizedWords @($targets[$i]) $retryWords @([pscustomobject]@{start=$start;end=$end}))
                        if($local.Count -eq 1){
                            $candidate=$local[0];$candidate.Chapter=$ch
                            foreach($t in $candidate.WordTimings){$t.Chapter=$ch}
                            $candidate|Add-Member CaptionWordTimings @($candidate.WordTimings) -Force
                            $candidate|Add-Member CaptionTimingRevision 'dtw-word-boundary-v1' -Force
                            if(-not @($candidate.WordTimings|Where-Object {-not $_.PSObject.Properties['SubtitleTimingQuality'] -or $_.SubtitleTimingQuality -ne 'dtw'}).Count -and (Test-PvsAcousticEditCue $candidate $Voices[$ch])){$m=$candidate;$valid=$true}
                        }
                    }
                }
            }
            if(-not $valid){continue}
            $proposals[$i]=$m
        }
        do {
            $blocked=@{}
            for($i=1;$i -lt $targets.Count;$i++){
                $left=if($proposals.ContainsKey($i-1)){$proposals[$i-1].WordTimings[-1].End}else{$targets[$i-1].End}
                $right=if($proposals.ContainsKey($i)){$proposals[$i].WordTimings[0].Start}else{$targets[$i].Start}
                if($right -ge $left-0.000001){continue}
                foreach($at in @(($i-1),$i)){if($proposals.ContainsKey($at)){$blocked[$at]=$true}}
            }
            foreach($at in $blocked.Keys){$proposals.Remove($at)}
        } while($blocked.Count)
        foreach($i in $proposals.Keys){
            $cell=$links[$i];$m=$proposals[$i]
            $cell | Add-Member CaptionWordTimings @($m.WordTimings | ForEach-Object {$_.PSObject.Copy()}) -Force
            $cell | Add-Member CaptionTimingRevision 'raw-dtw-cell-overlay-v1' -Force
            $cell | Add-Member Chapter $ch -Force
            $cell | Add-Member TimingVoiceStart ([double]$Voices[$ch].start) -Force
            $cell | Add-Member TimingVoiceEnd ([double]$Voices[$ch].end) -Force
            $count++
        }
    }
    return $count
}

function Test-PvsManualAcousticCell {
    param($Cell,$Voice)
    if(-not $Cell.PSObject.Properties['CaptionTimingRevision'] -or $Cell.CaptionTimingRevision -cne 'raw-dtw-cell-overlay-v1' -or -not $Cell.PSObject.Properties['CaptionWordTimings']){return $false}
    if(@($Cell.CaptionWordTimings | Where-Object {-not $_.PSObject.Properties['SubtitleTimingQuality'] -or $_.SubtitleTimingQuality -cne 'dtw'}).Count){return $false}
    $probe=[pscustomobject]@{Text=$Cell.Text;Chapter=$Cell.Chapter;CaptionWordTimings=$Cell.CaptionWordTimings;CaptionTimingRevision='dtw-word-boundary-v1'}
    return Test-PvsAcousticEditCue $probe $Voice
}

function Assert-PvsAcousticPartitionPlan {
    param($Plan)
    $references=@($Plan.acousticEditReferenceCues);$voices=@($Plan.voiceClips);$fps=[double]$Plan.frameRate
    $proofs=@($Plan.acousticEditBoundaryProofs);$quiet=@($Plan.acousticEditQuiet)
    $settings=$Plan.settings;$used=0;$next=1;$previous=$null
    Test-PvsAcousticReferenceCuts $proofs $references $voices $quiet $fps $settings.minSilenceDurationSeconds $settings.boundarySafetyMarginSeconds -RequireAll
    $retimes=@($Plan.segments | Where-Object Kind -eq 'retime')
    for($i=0;$i -lt $retimes.Count;$i++){
        $s=$retimes[$i];$first=[int]$s.FirstTargetCue;$last=[int]$s.LastTargetCue;$ch=[int]$s.Chapter
        if($first -ne $next -or $last -lt $first -or $last -gt $references.Count -or $ch -lt 0 -or $ch -ge $voices.Count){throw 'ACOUSTIC_PARTITION_REFERENCE_LOST'}
        $sourceStart=[double]$references[$first-1].Start;$sourceEnd=[double]$references[$last-1].End
        if($i -eq 0){if($sourceStart-$Plan.mainVideoClip.start -lt $Plan.minNoDialogueGapSeconds){$sourceStart=[double]$Plan.mainVideoClip.start}}
        elseif($sourceStart-$references[$first-2].End -lt $Plan.minNoDialogueGapSeconds){$sourceStart=($sourceStart+$references[$first-2].End)/2.0}
        if($i -eq $retimes.Count-1){if($Plan.mainVideoSourceEnd-$sourceEnd -lt $Plan.minNoDialogueGapSeconds){$sourceEnd=[double]$Plan.mainVideoSourceEnd}}
        elseif($references[$last].Start-$sourceEnd -lt $Plan.minNoDialogueGapSeconds){$sourceEnd=($sourceEnd+$references[$last].Start)/2.0}
        if($s.SourceStartFrame -ne [int][Math]::Round($sourceStart*$fps) -or $s.SourceEndFrame -ne [int][Math]::Round($sourceEnd*$fps)){throw 'ACOUSTIC_PARTITION_SOURCE_BOUNDARY_CHANGED'}
        if($null -eq $previous -or $previous.Chapter -ne $ch){
            if(($null -eq $previous -and $ch -ne 0) -or $s.OriginalVoiceStartFrame -ne [int][Math]::Round($voices[$ch].start*$fps) -or ($null -ne $previous -and ($ch -ne $previous.Chapter+1 -or $previous.OriginalVoiceEndFrame -ne [int][Math]::Round($voices[$previous.Chapter].end*$fps)))){throw 'ACOUSTIC_PARTITION_VOICE_EDGE_CHANGED'}
        }else{
            $proof=@($proofs | Where-Object {$_.leftCue -eq $first-1 -and $_.rightCue -eq $first -and $_.chapter -eq $ch -and $_.cutFrame -eq $s.OriginalVoiceStartFrame})
            if($proof.Count -ne 1 -or $previous.OriginalVoiceEndFrame -ne $s.OriginalVoiceStartFrame){throw 'ACOUSTIC_PARTITION_UNPROVEN_CUT'};$used++
        }
        $next=$last+1;$previous=$s
    }
    if($next -ne $references.Count+1 -or $used -ne $proofs.Count -or $null -eq $previous -or $previous.Chapter -ne $voices.Count-1 -or $previous.OriginalVoiceEndFrame -ne [int][Math]::Round($voices[-1].end*$fps)){throw 'ACOUSTIC_PARTITION_TAIL_LOST'}
    $source=[int][Math]::Round($Plan.mainVideoClip.start*$fps);$output=0
    foreach($s in $Plan.segments){if($s.SourceStartFrame -ne $source -or $s.NewStartFrame -ne $output -or $s.SourceEndFrame -le $source -or $s.NewEndFrame -le $output){throw 'ACOUSTIC_PARTITION_FRAME_LOST'};$source=$s.SourceEndFrame;$output=$s.NewEndFrame}
    if($source -ne $Plan.mainVideoSourceEndFrame -or $output -ne $Plan.plannedMainVideoEndFrame){throw 'ACOUSTIC_PARTITION_FRAME_TAIL_LOST'}
}
