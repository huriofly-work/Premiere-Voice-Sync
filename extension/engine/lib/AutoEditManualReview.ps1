Set-StrictMode -Version Latest

function Join-PvsManualRecognitionSurface {
    param([object[]]$Words)
    $pieces=New-Object System.Collections.Generic.List[string]
    for($i=0;$i -lt $Words.Count;$i++){
        $first=$Words[$i]
        if(-not $first.PSObject.Properties['RecognitionSurfaceText']){return $null}
        $last=$first
        while($i+1 -lt $Words.Count -and $Words[$i+1].PSObject.Properties['RecognitionSurfaceText'] -and
            [string]$Words[$i+1].RecognitionSurfaceText -ceq [string]$last.RecognitionSurfaceText -and
            [int]$Words[$i+1].RecognitionSurfaceTokenIndex -eq [int]$last.RecognitionSurfaceTokenIndex+1){$i++;$last=$Words[$i]}
        $a=[int]$first.RecognitionSurfaceSliceStart;$b=[int]$last.RecognitionSurfaceSliceEnd
        if($a -lt 0 -or $b -le $a -or $b -gt $first.RecognitionSurfaceText.Length){return $null}
        $pieces.Add($first.RecognitionSurfaceText.Substring($a,$b-$a).Trim())
    }
    return $pieces.ToArray() -join ' '
}

function Restore-PvsManualReferenceCell {
    param($Cell,[object[]]$Cues,[int[]]$RetainedCueIndices=@())
    if(@($Cell.ReferenceCueIndices).Count){return $null}
    $key=@(ConvertTo-NormalizedWords $Cell.Text) -join ' '
    if(-not $key -or [string]$Cell.Text -match '\d'){return $null}
    # Complete observed display text can retain SRT punctuation/case even
    # when duplicate/overlapping token timestamps cannot prove word timing.
    # This never fills missing words, changes numbers, or authorizes a cut.
    $matches=@($Cues | Where-Object {[string]$_.Text -notmatch '\d' -and (@(ConvertTo-NormalizedWords $_.Text) -join ' ') -ceq $key})
    if($matches.Count -ne 1 -or $RetainedCueIndices -contains [int]$matches[0].Index){return $null}
    $Cell | Add-Member NoteProperty RecognitionOriginalText ([string]$Cell.Text)
    $Cell.Text=[string]$matches[0].Text
    $Cell.ReferenceCueIndices=@([int]$matches[0].Index)
    return [int]$matches[0].Index
}

function New-PvsAutoEditManualReview {
    param([object[]]$Cues,[object[]]$Aligned,$Edited,[object[]]$Sources,$MainVideo,[double]$FrameRate=30,[string]$Language='vi',[ref]$Failure,[switch]$PreserveRecognitionFailures)
    # A separate no-omission path. Its coarse edit units do not assert that an
    # unresolved reference sentence was spoken or provide word-level timing.
    if($Language -ne 'vi' -or $null -eq $Edited -or $Edited.Resolved -or -not $Sources.Count -or $Cues.Count -lt 2 -or $FrameRate -lt 1 -or $FrameRate -gt 240 -or [double]::IsNaN($FrameRate)){return $null}
    $words=@($Edited.Words);$edge=[double]$MainVideo.start
    foreach($value in @([double]$MainVideo.start,[double]$MainVideo.end)){if([double]::IsNaN($value) -or [double]::IsInfinity($value)){return $null}}
    for($i=0;$i -lt $Cues.Count;$i++){
        $c=$Cues[$i]
        if([int]$c.Index -ne $i+1 -or [double]::IsNaN([double]$c.Start) -or [double]::IsNaN([double]$c.End) -or $c.Start -lt $edge-0.000001 -or $c.End -le $c.Start -or $c.End -gt $MainVideo.end+0.000001){return $null};$edge=[double]$c.End
    }
    $sourceEdge=0.0
    foreach($s in $Sources){foreach($v in @([double]$s.start,[double]$s.end)){if([double]::IsNaN($v) -or [double]::IsInfinity($v)){return $null}};if($s.start -lt $sourceEdge-0.000001 -or $s.end -le $s.start){return $null};$sourceEdge=[double]$s.end}
    $chapter=-1;$previous=0.0
    foreach($w in $words){
        $a=[double]$w.Start;$b=[double]$w.End;$ch=[int]$w.Chapter
        if($ch -lt $chapter -or $ch -lt 0 -or $ch -ge $Sources.Count -or [double]::IsNaN($a) -or [double]::IsNaN($b) -or [double]::IsInfinity($a) -or [double]::IsInfinity($b) -or $a -lt 0 -or $b -lt $a -or $b -gt $Sources[$ch].end-$Sources[$ch].start+0.000001 -or ($ch -eq $chapter -and $a -lt $previous-0.000001)){return $null}
        $chapter=$ch;$previous=$a
    }
    $found=Find-PvsEditedReferenceMatches $Cues $words $Sources -MinimumAnchorWords 4
    if(-not $found.Ordered -or $found.Matches.Count -lt 2){return $null}
    $known=@{};foreach($m in $found.Matches){$known[[int]$m.Cue]=$m}
    # Assign a chapter edge only when its final observed word belongs to a
    # unique complete sentence. An unknown suffix across files stays blocked.
    $chapters=New-Object System.Collections.Generic.List[object];$firstCue=0
    for($ch=0;$ch -lt $Sources.Count;$ch++){
        $matches=@($found.Matches | Where-Object Chapter -eq $ch)
        if(-not $matches.Count){return $null}
        $lastCue=$Cues.Count-1
        if($ch+1 -lt $Sources.Count){
            $lastWord=-1;for($w=0;$w -lt $words.Count;$w++){if($words[$w].Chapter -eq $ch){$lastWord=$w}}
            if($matches[-1].LastWord -ne $lastWord){
                if($Failure){$Failure.Value=[pscustomobject]@{reason='chapter-edge-unverified';cueIndices=@([int]$Cues[$matches[-1].Cue].Index);chapter=$ch}}
                return $null
            }
            $lastCue=[int]$matches[-1].Cue
        }
        if($firstCue -gt $lastCue -or @($matches | Where-Object {$_.Cue -lt $firstCue -or $_.Cue -gt $lastCue}).Count){return $null}
        $chapters.Add([pscustomobject]@{first=$firstCue;last=$lastCue;chapter=$ch})
        $firstCue=$lastCue+1
    }
    $requests=New-Object System.Collections.Generic.List[object]
    for($i=0;$i -lt $Cues.Count;$i++){
        if($known.ContainsKey($i)){continue}
        $partition=@($chapters | Where-Object {$_.first -le $i -and $_.last -ge $i})[0];$ch=[int]$partition.chapter
        $left=@($found.Matches | Where-Object {$_.Chapter -eq $ch -and $_.Cue -lt $i} | Select-Object -Last 1)
        $right=@($found.Matches | Where-Object {$_.Chapter -eq $ch -and $_.Cue -gt $i} | Select-Object -First 1)
        $first=if($left.Count){[int]$left[0].Cue}else{[int]$partition.first};$last=if($right.Count){[int]$right[0].Cue}else{[int]$partition.last}
        $requests.Add([pscustomobject]@{first=$first;last=$last;chapter=$ch;exclusiveLeft=-1})
    }
    $covered=@{};foreach($index in $found.Mapping){if($index -ge 0){$covered[[int]$index]=$true}}
    for($i=0;$i -lt $words.Count;$i++){
        if($covered.ContainsKey($i)){continue}
        $ch=[int]$words[$i].Chapter
        $left=@($found.Matches | Where-Object {$_.Chapter -eq $ch -and $_.LastWord -lt $i} | Select-Object -Last 1)
        $right=@($found.Matches | Where-Object {$_.Chapter -eq $ch -and $_.FirstWord -gt $i} | Select-Object -First 1)
        if(-not $left.Count -and -not $right.Count){return $null}
        $partition=$chapters[$ch]
        $requests.Add([pscustomobject]@{first=$(if($left.Count){[int]$left[0].Cue}else{[int]$partition.first});last=$(if($right.Count){[int]$right[0].Cue}else{[int]$partition.last});chapter=$ch;exclusiveLeft=-1})
    }
    if(-not $requests.Count){return $null}
    $merged=New-Object System.Collections.Generic.List[object]
    foreach($r in @($requests | Sort-Object first,last)){
        if($merged.Count -and $r.chapter -eq $merged[$merged.Count-1].chapter -and $r.first -le $merged[$merged.Count-1].last){$merged[$merged.Count-1].last=[Math]::Max($merged[$merged.Count-1].last,$r.last)}else{$merged.Add($r.PSObject.Copy())}
    }
    # Keep small historical blocks unchanged. Split an oversized connected
    # group only at the END of an exact whole-cue anchor, owning it once.
    $bounded=New-Object System.Collections.Generic.List[object]
    foreach($range in $merged){
        $first=[int]$range.first;$last=[int]$range.last;$ch=[int]$range.chapter;$exclusive=-1;$preserveWhole=$false
        $start=if($known.ContainsKey($first)){$found.Aligned[$first].Start}else{$Sources[$ch].start}
        $end=if($known.ContainsKey($last)){$found.Aligned[$last].End}else{$Sources[$ch].end}
        $chapterWords=@($words | Where-Object Chapter -eq $ch)
        if($first -eq $chapters[$ch].first -and $Sources[$ch].start+$chapterWords[0].Start -lt $start-0.000001){$start=$Sources[$ch].start}
        if($last -eq $chapters[$ch].last -and $Sources[$ch].start+$chapterWords[-1].End -gt $end+0.000001){$end=$Sources[$ch].end}
        while($end-$start -gt 30 -or $last-$first+1 -gt 40){
            $cuts=@($found.Matches | Where-Object {
                $_.Chapter -eq $ch -and $_.Cue -ge $first -and $_.Cue -lt $last -and
                $_.Cue-$first+1 -le 40 -and $found.Aligned[$_.Cue].End-$start -ge 0.2 -and
                $found.Aligned[$_.Cue].End-$start -le 30 -and
                ($_.LastWord+1 -ge $words.Count -or $words[$_.LastWord+1].Chapter -ne $ch -or $words[$_.LastWord+1].Start -ge $words[$_.LastWord].End-0.000001)
            } | Select-Object -Last 1)
            if(-not $cuts.Count){
                # Recognition uncertainty is not a fatal workflow error. Keep
                # the remaining anchored region intact, without new cuts or
                # omission authority. This is distinct from the bounded path.
                if($PreserveRecognitionFailures){$preserveWhole=$true;break}
                if($Failure){$Failure.Value=[pscustomobject]@{reason='manual-window-limit';cueIndices=@($Cues[$first..$last].Index);chapter=$ch;start=$start;end=$end;maximumSeconds=30}}
                return $null
            }
            $cut=[int]$cuts[0].Cue
            $bounded.Add([pscustomobject]@{first=$first;last=$cut;chapter=$ch;exclusiveLeft=$exclusive;preserveWhole=$false})
            $exclusive=$cut;$first=$cut+1;$start=$found.Aligned[$cut].End
        }
        $bounded.Add([pscustomobject]@{first=$first;last=$last;chapter=$ch;exclusiveLeft=$exclusive;preserveWhole=$preserveWhole})
    }
    $units=New-Object System.Collections.Generic.List[object];$tasks=New-Object System.Collections.Generic.List[object];$cursor=0
    foreach($range in $bounded){
        $first=[int]$range.first;$last=[int]$range.last
        $left=if($known.ContainsKey($first)){$found.Aligned[$first]}else{$null}
        $right=if($known.ContainsKey($last)){$found.Aligned[$last]}else{$null}
        $ch=[int]$range.chapter
        if($ch -lt 0 -or ($left -and $right -and $left.Chapter -ne $right.Chapter) -or (-not $range.preserveWhole -and $last-$first+1 -gt 40)){return $null}
        $start=if($left){[double]$left.Start}else{[double]$Sources[$ch].start};$end=if($right){[double]$right.End}else{[double]$Sources[$ch].end}
        $chapterWords=@($words | Where-Object Chapter -eq $ch)
        if($first -eq $chapters[$ch].first -and $Sources[$ch].start+$chapterWords[0].Start -lt $start-0.000001){$start=$Sources[$ch].start}
        if($last -eq $chapters[$ch].last -and $Sources[$ch].start+$chapterWords[-1].End -gt $end+0.000001){$end=$Sources[$ch].end}
        $sourceStart=[double]$Cues[$first].Start
        if($range.exclusiveLeft -ge 0){$start=[double]$found.Aligned[$range.exclusiveLeft].End;$sourceStart=[double]$Cues[$range.exclusiveLeft].End}
        elseif($first -eq $chapters[$ch].first -and $ch -gt 0){$sourceStart=[double]$Cues[$first-1].End}
        if($end-$start -lt 0.2 -or (-not $range.preserveWhole -and $end-$start -gt 30.0)){return $null}
        while($cursor -lt $first){if(-not $known.ContainsKey($cursor)){return $null};$units.Add($found.Aligned[$cursor].PSObject.Copy());$cursor++}
        $offset=[double]$Sources[$ch].start
        $heard=@($words | Where-Object {$_.Chapter -eq $ch -and $offset+$_.Start -ge $start-0.000001 -and $offset+$_.End -le $end+0.000001})
        if(-not $heard.Count -or (-not $PreserveRecognitionFailures -and $heard.Count -gt 800)){return $null}
        if($heard.Count -gt 800){$range.preserveWhole=$true}
        # Caption identity is independent of the exact anchors that bound the
        # coarse picture block. Sparse/partial reference cannot restore words.
        $captionKnown=New-Object System.Collections.Generic.List[object]
        for($index=$first;$index -le $last;$index++){
            $c=if($known.ContainsKey($index)){$found.Aligned[$index]}else{@($Aligned | Where-Object Index -eq $Cues[$index].Index)[0]}
            if($null -eq $c -or $c.Chapter -ne $ch -or $null -eq $c.Start -or $null -eq $c.End -or $c.Start -lt $start-0.000001 -or $c.End -gt $end+0.000001){continue}
            $coverage=Get-PvsAutoEditReferenceWordCoverage $c $words $Sources
            if($null -eq $coverage -or ($c.Confidence -lt 1 -and -not (Test-PvsSubtitleReferenceIdentity $c $words $Sources))){continue}
            $inside=@($heard | Where-Object {$offset+$_.Start -ge $c.Start-0.000001 -and $offset+$_.End -le $c.End+0.000001})
            if(-not $inside.Count -or -not $inside[0].PSObject.Properties['RecognitionSurfaceText'] -or $inside[0].RecognitionSurfaceJoinPrevious -or $inside[-1].RecognitionSurfaceJoinNext){continue}
            $captionKnown.Add($c)
        }
        $cells=New-Object System.Collections.Generic.List[object];$wordCursor=0;$retained=New-Object System.Collections.Generic.List[int]
        foreach($c in @($captionKnown | Sort-Object Start)){
            $before=New-Object System.Collections.Generic.List[object]
            while($wordCursor -lt $heard.Count -and $offset+$heard[$wordCursor].Start -lt $c.Start-0.000001){$before.Add($heard[$wordCursor]);$wordCursor++}
            if($before.Count){$text=Join-PvsManualRecognitionSurface $before.ToArray();if($null -eq $text){return $null};$cells.Add([pscustomobject]@{Text=$text;Start=$offset+$before[0].Start;End=$offset+$before[$before.Count-1].End;ReferenceCueIndices=@()})}
            if($wordCursor -ge $heard.Count -or [Math]::Abs($offset+$heard[$wordCursor].Start-$c.Start) -gt 0.000001){return $null}
            while($wordCursor -lt $heard.Count -and $offset+$heard[$wordCursor].End -le $c.End+0.000001){$wordCursor++}
            $cells.Add([pscustomobject]@{Text=[string]$c.Text;Start=[double]$c.Start;End=[double]$c.End;ReferenceCueIndices=@([int]$c.Index)});$retained.Add([int]$c.Index)
        }
        if($wordCursor -lt $heard.Count){$tail=@($heard[$wordCursor..($heard.Count-1)]);$text=Join-PvsManualRecognitionSurface $tail;if($null -eq $text){return $null};$cells.Add([pscustomobject]@{Text=$text;Start=$offset+$tail[0].Start;End=$offset+$tail[-1].End;ReferenceCueIndices=@()})}
        # A zero/overlapping native token is not a word boundary. Merge display
        # cells locally, preserving all text, and declare sentence estimates.
        $display=New-Object System.Collections.Generic.List[object]
        foreach($cell in $cells){
            $cell.Start=[Math]::Max($start,$cell.Start);$cell.End=[Math]::Min($end,$cell.End)
            if($display.Count -and ($cell.Start -lt $display[$display.Count-1].End-0.000001 -or [Math]::Round($cell.End*$FrameRate) -le [Math]::Round($cell.Start*$FrameRate) -or [Math]::Round($display[$display.Count-1].End*$FrameRate) -le [Math]::Round($display[$display.Count-1].Start*$FrameRate))){
                $prev=$display[$display.Count-1];$prev.Text+=' '+$cell.Text;$prev.End=[Math]::Max($prev.End,$cell.End);$prev.ReferenceCueIndices=@($prev.ReferenceCueIndices)+@($cell.ReferenceCueIndices)
            }else{$display.Add($cell)}
        }
        if(-not $display.Count -or @($display | Where-Object {[Math]::Round($_.End*$FrameRate) -le [Math]::Round($_.Start*$FrameRate)}).Count){return $null}
        foreach($cell in $display){
            $restored=Restore-PvsManualReferenceCell -Cell $cell -Cues @($Cues[$first..$last]) -RetainedCueIndices $retained.ToArray()
            if($null -ne $restored){$retained.Add($restored)}
        }
        $proxyIndex=[int]$Cues[$first].Index;$text=($display | ForEach-Object {$_.Text}) -join ' '
        $allIndices=@($Cues[$first..$last] | ForEach-Object {[int]$_.Index})
        $pending=@($allIndices | Where-Object {$retained -notcontains $_})
        $units.Add([pscustomobject]@{Index=$proxyIndex;OriginalStart=$sourceStart;OriginalEnd=[double]$Cues[$last].End;Start=$start;End=$end;Text=$text;Chapter=$ch;Confidence=0.0;WordTimings=@();ManualEditBlock=$true;EditBoundaryReviewRequired=$true;ManualReferenceCueIndices=$allIndices;ManualCaptionCues=$display.ToArray()})
        $tasks.Add([pscustomobject]@{cueIndex=$proxyIndex;cueIndices=$allIndices;pendingReferenceCueIndices=$pending;retainedReferenceCueIndices=$retained.ToArray();chapter=$ch;start=$start;end=$end;sourceStart=$sourceStart;sourceEnd=[double]$Cues[$last].End;status='manual-review-pending';recognitionFailurePreserved=[bool]$range.preserveWhole;reason='Chưa phân biệt được ASR sai và voice đã cắt; giữ toàn bộ hình/voice trong khối, rà chữ và timing';captionText=$text;captionTimingQuality='estimated';captionCells=$display.ToArray()})
        $cursor=$last+1
    }
    while($cursor -lt $Cues.Count){if(-not $known.ContainsKey($cursor)){return $null};$units.Add($found.Aligned[$cursor].PSObject.Copy());$cursor++}
    # Reject a proposed edge if any observed token crosses it or is covered
    # twice. Monotone starts alone do not rule out an earlier long token.
    foreach($w in $words){
        $offset=[double]$Sources[[int]$w.Chapter].start;$a=$offset+[double]$w.Start;$b=$offset+[double]$w.End
        $owners=@($units | Where-Object {$_.Chapter -eq $w.Chapter -and $_.Start -le $a+0.000001 -and $_.End -ge $b-0.000001})
        if($owners.Count -ne 1){
            if($Failure){$Failure.Value=[pscustomobject]@{reason='observed-word-partition-unverified';chapter=[int]$w.Chapter;start=$a;end=$b}}
            return $null
        }
    }
    return [pscustomobject]@{Status='manual-review-pending';Cues=$units.ToArray();Blocks=$tasks.ToArray();ReferenceCueCount=$Cues.Count}
}

function Split-PvsManualReviewCaptionCue {
    param($Cue,[int]$MaxCharacters,[double]$FrameRate,[switch]$UseAcousticTiming)
    if(-not $Cue.PSObject.Properties['ManualEditBlock'] -or -not $Cue.ManualEditBlock){throw 'MANUAL_CAPTION_EXPLICIT_BLOCK_REQUIRED'}
    $cellIndex=0
    foreach($cell in $Cue.ManualCaptionCues){
        if($UseAcousticTiming -and $cell.PSObject.Properties['TimingVoiceStart'] -and (Test-PvsManualAcousticCell $cell ([pscustomobject]@{start=$cell.TimingVoiceStart;end=$cell.TimingVoiceEnd}))){
            $probe=[pscustomobject]@{Index=$Cue.Index;Text=$cell.Text;CaptionWordTimings=$cell.CaptionWordTimings}
            foreach($part in @(Split-PvsAcousticCaptionCue $probe $MaxCharacters $FrameRate)){
                $part | Add-Member ManualCaptionCellIndex $cellIndex
                $part | Add-Member ManualReferenceCueIndices @($cell.ReferenceCueIndices)
                $part | Add-Member CaptionTimingQuality 'dtw'
                $part
            }
            $cellIndex++;continue
        }
        $a=[int][Math]::Round($cell.Start*$FrameRate);$b=[int][Math]::Round($cell.End*$FrameRate)
        if($b -le $a){throw 'MANUAL_CAPTION_INTERVAL_INVALID'}
        $chunks=@(Get-PvsCaptionTextChunks -Text $cell.Text -MaxCharacters $MaxCharacters)
        if($chunks.Count -gt $b-$a){$chunks=@([pscustomobject]@{Text=$cell.Text})}
        for($i=0;$i -lt $chunks.Count;$i++){
            # Display estimates only. No WordTimings/IndependentSpeechEdges or
            # VoiceBoundaryAligned claim is produced from these subdivisions.
            [pscustomobject]@{Text=$chunks[$i].Text;StartFrame=$a+[int][Math]::Floor(($b-$a)*$i/[double]$chunks.Count);EndFrame=$a+[int][Math]::Floor(($b-$a)*($i+1)/[double]$chunks.Count);PartIndex=$i+1;PartCount=$chunks.Count;VoiceBoundaryAligned=$false;ManualCaptionCellIndex=$cellIndex;ManualReferenceCueIndices=@($cell.ReferenceCueIndices);CaptionTimingQuality='estimated'}
        }
        $cellIndex++
    }
}

function Assert-PvsManualReviewPlan {
    param($Plan)
    if(-not $Plan.PSObject.Properties['manualReviewBlocks'] -or -not @($Plan.manualReviewBlocks).Count){return}
    if($Plan.PSObject.Properties['editedSourceMap'] -or $Plan.PSObject.Properties['omittedReferenceCueIndices']){throw 'MANUAL_REVIEW_CANNOT_AUTHORIZE_OMISSIONS'}
    $fps=[double]$Plan.frameRate
    $partitioned=[bool]($Plan.PSObject.Properties['acousticEditBoundaryRevision'] -and $Plan.acousticEditBoundaryRevision -cin @('raw-dtw-quiet-partition-v1','dtw-cue-quiet-partition-v2'))
    $captionAcoustic=$partitioned -or ($Plan.PSObject.Properties['manualCaptionTimingRevision'] -and $Plan.manualCaptionTimingRevision -ceq 'raw-dtw-cell-overlay-v1')
    if($partitioned){Assert-PvsAcousticPartitionPlan $Plan}
    if($Plan.PSObject.Properties['pictureCueRevision']){Assert-PvsCuePicturePlan $Plan}
    foreach($task in $Plan.manualReviewBlocks){
        $a=[int][Math]::Round($task.sourceStart*$fps);$b=[int][Math]::Round($task.sourceEnd*$fps)
        $va=[int][Math]::Round($task.start*$fps);$vb=[int][Math]::Round($task.end*$fps)
        $owner=@($Plan.segments | Where-Object {$_.Kind -eq 'retime' -and $_.Chapter -eq $task.chapter -and $_.SourceStartFrame -le $a -and $_.SourceEndFrame -ge $b -and $_.OriginalVoiceStartFrame -le $va -and $_.OriginalVoiceEndFrame -ge $vb})
        if($a -ge $b -or $va -ge $vb -or (-not $partitioned -and $owner.Count -ne 1)){throw 'MANUAL_REVIEW_BLOCK_WAS_CUT_OR_LOST'}
        for($cell=0;$cell -lt $task.captionCells.Count;$cell++){
            $parts=@($Plan.captions | Where-Object {$_.SourceCueIndex -eq $task.cueIndex -and $_.PSObject.Properties['ManualCaptionCellIndex'] -and $_.ManualCaptionCellIndex -eq $cell})
            if(($parts.Text -join ' ') -cne [regex]::Replace($task.captionCells[$cell].Text.Trim(),'\s+',' ')){throw 'MANUAL_REVIEW_CAPTION_TEXT_LOST'}
            $measured=$captionAcoustic -and (Test-PvsManualAcousticCell $task.captionCells[$cell] $Plan.voiceClips[$task.chapter])
            foreach($part in $parts){
                if($measured){if(-not $part.VoiceBoundaryAligned -or -not $part.IndependentSpeechEdges -or $part.CaptionTimingQuality -ne 'dtw'){throw 'MANUAL_REVIEW_DTW_CELL_EVIDENCE_LOST'}}
                elseif($part.VoiceBoundaryAligned -or $part.IndependentSpeechEdges -or $part.CaptionTimingQuality -ne 'estimated'){throw 'MANUAL_REVIEW_CAPTION_TIMING_PROMOTED'}
            }
        }
    }
}
