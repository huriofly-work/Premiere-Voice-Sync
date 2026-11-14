Set-StrictMode -Version Latest
. "$PSScriptRoot\RecognitionBackend.ps1"
. "$PSScriptRoot\SubtitleTiming.ps1"
. "$PSScriptRoot\AutoEditAcousticPartitions.ps1"

function Get-PvsPcmWaveDuration {
    param([Parameter(Mandatory)][string]$Path)
    $stream=[IO.File]::OpenRead($Path)
    $reader=New-Object IO.BinaryReader($stream)
    try {
        if ([Text.Encoding]::ASCII.GetString($reader.ReadBytes(4)) -ne 'RIFF') { throw 'SUBTITLE_WAV_HEADER_INVALID' }
        [void]$reader.ReadUInt32()
        if ([Text.Encoding]::ASCII.GetString($reader.ReadBytes(4)) -ne 'WAVE') { throw 'SUBTITLE_WAV_FORMAT_INVALID' }
        $byteRate=0; $dataLength=0
        while ($stream.Position+8 -le $stream.Length) {
            $chunk=[Text.Encoding]::ASCII.GetString($reader.ReadBytes(4)); $size=$reader.ReadUInt32(); $next=$stream.Position+$size+($size%2)
            if ($next -gt $stream.Length) { throw 'SUBTITLE_WAV_TRUNCATED' }
            if ($chunk -eq 'fmt ' -and $size -ge 16) { [void]$reader.ReadUInt16();[void]$reader.ReadUInt16();[void]$reader.ReadUInt32();$byteRate=$reader.ReadUInt32() }
            if ($chunk -eq 'data') { $dataLength=$size }
            $stream.Position=$next
        }
        if ($byteRate -le 0 -or $dataLength -le 0) { throw 'SUBTITLE_AUDIO_EMPTY' }
        return $dataLength/[double]$byteRate
    } finally { $reader.Dispose(); $stream.Dispose() }
}



function Convert-PvsDtwJsonToWords {
    param($Json,[double]$Duration)
    $output=New-Object System.Collections.Generic.List[object]
    $lastAnchor=-1.0
    $previousTextAnchor=$null
    foreach($segment in $Json.transcription){
        if([string]$segment.text -match '^\s*\[(?:[_A-Z0-9]+|music|applause|laughter|silence|noise)\]\s*$'){continue}
        $lexical=@(ConvertTo-NormalizedWords ([string]$segment.text))
        $pieces=New-Object System.Collections.Generic.List[object];$joined=''
        foreach($token in $segment.tokens){
            if($token.id -ge 50257){continue}
            $begin=$joined.Length;$joined+=[string]$token.text
            $anchor=[double]$token.t_dtw/100.0
            $pieces.Add([pscustomobject]@{Start=$begin;End=$joined.Length;Text=[string]$token.text;Anchor=$anchor;Before=$previousTextAnchor})
            $previousTextAnchor=if($anchor -ge 0 -and $anchor -le $Duration){$anchor}else{$null}
        }
        $lexicalMatches=@([regex]::Matches($joined.ToLowerInvariant(),'[\p{L}\p{N}]+'))
        # Preserve character positions; do not assign one segment's entire
        # span to every normalized component of a hyphenated name.
        $textMatches=($joined -ceq $joined.Normalize([Text.NormalizationForm]::FormC)) -and $lexicalMatches.Count -eq $lexical.Count
        if($textMatches){for($i=0;$i -lt $lexical.Count;$i++){if($lexicalMatches[$i].Value -ne $lexical[$i]){$textMatches=$false;break}}}
        for($i=0;$i -lt $lexical.Count;$i++){
            $anchors=@()
            $wordPieces=@()
            if($textMatches){$m=$lexicalMatches[$i];$wordPieces=@($pieces | Where-Object {$_.Start -lt $m.Index+$m.Length -and $_.End -gt $m.Index -and $_.Text -match '[\p{L}\p{N}]'});$anchors=@($wordPieces | ForEach-Object {$_.Anchor})}
            $valid=$anchors.Count -gt 0
            if($valid){foreach($anchor in $anchors){if($anchor -lt $lastAnchor -or $anchor -lt 0 -or $anchor -gt $Duration){$valid=$false;break};$lastAnchor=$anchor}}
            $before=if($valid -and $null -ne $wordPieces[0].Before -and $wordPieces[0].Before -le $anchors[0]){$wordPieces[0].Before}else{$null}
            $word=[pscustomobject]@{Text=$lexical[$i];Chapter=0;Start=[double]$segment.offsets.from/1000.0;End=[double]$segment.offsets.to/1000.0;DtwFirst=if($valid){$anchors[0]}else{$null};DtwLast=if($valid){$anchors[-1]}else{$null};DtwBoundaryStart=$before}
            if([string]$segment.text -match '^\s*\d+[.,]\d{1,2}\s*$'){$word | Add-Member -NotePropertyName NumericSurfaceText -NotePropertyValue ([string]$segment.text).Trim()}
            $output.Add($word)
        }
    }
    return $output.ToArray()
}

function Convert-PvsDtwCaptionRecognition {
    param($Json,[object[]]$Quiet,[double]$Duration,[int]$Chapter=0)
    $speech=Convert-PvsDtwSpeechWords -Words (Convert-PvsDtwJsonToWords $Json $Duration) -Quiet $Quiet -Duration $Duration
    if($speech.MissingAnchors.Count){throw "CAPTION_DTW_ANCHORS_UNVERIFIED:$($speech.MissingAnchors -join ',')"}
    $surfaces=New-Object System.Collections.Generic.List[object];$cursor=0
    foreach($segment in $Json.transcription){
        $text=[regex]::Replace([string]$segment.text,'(?i)\[(?:[_A-Z0-9]+|music|applause|laughter|silence|noise)\]','').Trim()
        if(-not $text){continue}
        $count=@(ConvertTo-NormalizedWords $text).Count
        if($count -eq 0){if($surfaces.Count -and $text -match '^[,;:.!?\u2026]+$'){$surfaces[$surfaces.Count-1].Text+=$text};continue}
        if($cursor+$count -gt $speech.Words.Count){throw 'CAPTION_DTW_SURFACE_COVERAGE_INVALID'}
        # Zero-length SOW segments can still have valid DTW speech anchors.
        # Do not drop those spoken words, as the legacy parser did.
        $surfaces.Add([pscustomobject]@{Text=$text;Start=$speech.Words[$cursor].Start;End=$speech.Words[$cursor+$count-1].End;FirstWord=$cursor;LastWord=$cursor+$count-1})
        $cursor+=$count
    }
    if($cursor -ne $speech.Words.Count){throw 'CAPTION_DTW_SURFACE_COVERAGE_INVALID'}
    foreach($word in $speech.Words){$word.Chapter=$Chapter}
    [pscustomobject]@{Words=$speech.Words;Surfaces=$surfaces.ToArray()}
}

# Shared caption-only acoustic timing. Never replaces edit cue bounds or cuts.
# DTW points are not durations. Quiet intervals supply two-sided speech edges.
function Convert-PvsDtwSpeechWords {
    param([object[]]$Words,[object[]]$Quiet,[double]$Duration)
    # An empty parser result binds as $null in PS5. foreach enumerates no
    # elements; piping $null invokes the block once and calls Copy on null.
    $copy=@(foreach($sourceWord in $Words){$sourceWord.PSObject.Copy()})
    $review=New-Object System.Collections.Generic.List[int]
    for($i=0;$i -lt $copy.Count;$i++){
        $word=$copy[$i]
        if($null -eq $word.DtwFirst -or $null -eq $word.DtwLast){$review.Add($i);continue}
        $next=if($i+1 -lt $copy.Count){$copy[$i+1]}else{$null}
        $word.Start=[double]$word.DtwFirst
        $word.End=if($null -ne $next -and $null -ne $next.DtwFirst -and $next.DtwFirst -gt $word.Start){[double]$next.DtwFirst}else{[Math]::Min($Duration,[Math]::Max([double]$word.End,[double]$word.DtwLast+0.04))}
    }
    $matchedPauses=New-Object System.Collections.Generic.List[object]
    for($i=0;$i -lt $copy.Count-1;$i++){
        $left=$copy[$i];$right=$copy[$i+1]
        if($null -eq $left.DtwLast -or $null -eq $right.DtwFirst){continue}
        $pause=@($Quiet | Where-Object {$_.Duration -ge 0.12 -and $_.Start -ge $left.DtwLast-0.08 -and $_.End -le $right.DtwFirst+0.08})
        if($pause.Count -ne 1 -or $pause[0].Start -le $left.Start -or $pause[0].End -ge $right.End){continue}
        $left.End=[double]$pause[0].Start
        $right.Start=[double]$pause[0].End
        $matchedPauses.Add([pscustomobject]@{AfterWord=$i;BeforeWord=$i+1;Start=$left.End;End=$right.Start})
    }
    if($copy.Count -gt 0 -and $null -ne $copy[0].DtwFirst){
        $leading=@($Quiet | Where-Object {$_.End -le $copy[0].DtwFirst+0.02 -and $copy[0].DtwFirst-$_.End -le 0.25} | Sort-Object End -Descending | Select-Object -First 1)
        if($leading.Count){$copy[0].Start=$leading[0].End}
    }
    if($copy.Count -gt 0 -and $null -ne $copy[-1].DtwLast){
        $trailing=@($Quiet | Where-Object {$_.Start -ge $copy[-1].DtwLast-0.08 -and $_.Start-$copy[-1].DtwLast -le 0.5} | Sort-Object Start | Select-Object -First 1)
        if($trailing.Count -and $trailing[0].Start -gt $copy[-1].Start){$copy[-1].End=$trailing[0].Start}
    }
    for($i=0;$i -lt $copy.Count;$i++){
        if($copy[$i].Start -lt 0 -or $copy[$i].End -le $copy[$i].Start -or $copy[$i].End -gt $Duration -or ($i -gt 0 -and $copy[$i].Start -lt $copy[$i-1].End-0.000001)){

            throw "CAPTION_DTW_ANCHOR_SPAN_INVALID:word-$i"
        }
    }
    [pscustomobject]@{Words=$copy;MatchedPauses=$matchedPauses.ToArray();MissingAnchors=$review.ToArray();NeedsPlaybackAcceptance=$true}
}

function Add-PvsCaptionTokenBoundaryTimings {
    param([object[]]$Cues,[object[]]$Words,[double]$Offset=0.0)
    # Production alignment intentionally copies only ordinary word timings.
    # Attach provenance to experimental caption timings using exact text AND
    # both mapped edges. Ambiguous/missing matches never receive an estimate.
    $bySpan=@{}
    foreach($word in $Words){
        $key='{0}|{1:F6}|{2:F6}' -f $word.Text,($Offset+$word.Start),($Offset+$word.End)
        if(-not $bySpan.ContainsKey($key)){$bySpan[$key]=New-Object System.Collections.Generic.List[object]}
        $bySpan[$key].Add($word)
    }
    foreach($cue in $Cues){
        $timings=if($cue.PSObject.Properties['CaptionWordTimings']){$cue.CaptionWordTimings}else{$cue.WordTimings}
        foreach($timing in $timings){
            $key='{0}|{1:F6}|{2:F6}' -f $timing.Text,$timing.Start,$timing.End
            if(-not $bySpan.ContainsKey($key) -or $bySpan[$key].Count -ne 1){continue}
            $word=$bySpan[$key][0]
            if(-not $word.PSObject.Properties['DtwBoundaryStart'] -or $null -eq $word.DtwBoundaryStart){continue}
            $timing | Add-Member -NotePropertyName ContinuousTokenStart -NotePropertyValue ($Offset+[double]$word.DtwBoundaryStart) -Force
        }
    }
}

function New-PvsCaptionVoiceMap {
    param([object[]]$Segments)
    $items=@($Segments | Where-Object {$_.Kind -eq 'retime'} | Sort-Object OriginalVoiceStartFrame,@{Expression='OriginalVoiceEndFrame';Descending=$true})
    $map=New-Object System.Collections.Generic.List[object]
    $previous=$null
    foreach($segment in $items){
        if($segment.OriginalVoiceEndFrame -le $segment.OriginalVoiceStartFrame -or
            $segment.NewVoiceEndFrame-$segment.NewVoiceStartFrame -ne $segment.OriginalVoiceEndFrame-$segment.OriginalVoiceStartFrame){throw 'CAPTION_VOICE_MAP_INVALID:duration'}
        # The legacy planner can manufacture a one-frame slice for a collapsed
        # cue; that source frame is already present in the next complete slice.
        # Prefer the complete coverage for acoustic captions, leaving A2 and
        # its existing one-frame safety slice entirely unchanged.
        if($null -ne $previous -and $segment.OriginalVoiceEndFrame-$segment.OriginalVoiceStartFrame -eq 1 -and
            $segment.OriginalVoiceStartFrame -ge $previous.OriginalVoiceStartFrame -and $segment.OriginalVoiceEndFrame -le $previous.OriginalVoiceEndFrame){continue}
        if($null -ne $previous -and ($segment.OriginalVoiceStartFrame -lt $previous.OriginalVoiceEndFrame -or $segment.NewVoiceStartFrame -lt $previous.NewVoiceEndFrame)){
            $previousEnd=if($null -ne $previous){$previous.OriginalVoiceEndFrame}else{-1}
            throw "CAPTION_VOICE_MAP_INVALID:source-$($segment.OriginalVoiceStartFrame)-$($segment.OriginalVoiceEndFrame);output-$($segment.NewVoiceStartFrame)-$($segment.NewVoiceEndFrame);previous-source-end-$previousEnd"
        }
        $map.Add($segment)
        $previous=$segment
    }
    return $map.ToArray()
}

function Get-PvsMappedCaptionFrame {
    param([object[]]$VoiceMap,[int]$SourceFrame,[switch]$EndEdge)
    # Resolve from actual A2 source coverage, not the cue's legacy sentence
    # assignment. Start edges belong to the right slice at a touching seam;
    # end edges belong to the left slice, avoiding inserted no-dialogue gaps.
    $low=0;$high=$VoiceMap.Count-1
    while($low -le $high){
        $mid=[int][Math]::Floor(($low+$high)/2.0);$segment=$VoiceMap[$mid]
        if($SourceFrame -lt $segment.OriginalVoiceStartFrame -or ($EndEdge -and $SourceFrame -eq $segment.OriginalVoiceStartFrame)){$high=$mid-1;continue}
        if($SourceFrame -gt $segment.OriginalVoiceEndFrame -or (-not $EndEdge -and $SourceFrame -eq $segment.OriginalVoiceEndFrame)){$low=$mid+1;continue}
        return [int]($SourceFrame-$segment.OriginalVoiceStartFrame+$segment.NewVoiceStartFrame)
    }
    throw "CAPTION_OUTSIDE_VOICE_COVERAGE:frame-$SourceFrame"
}

function Resolve-PvsCaptionMappingConflicts {
    param([object[]]$Captions,[object[]]$LegacyFrames,[double]$FrameRate)
    if($Captions.Count -ne $LegacyFrames.Count){throw 'CAPTION_MAPPING_BASELINE_COUNT_INVALID'}
    $changed=@{};$review=@{}
    for($i=0;$i -lt $Captions.Count;$i++){
        if([int][Math]::Round($Captions[$i].Start*$FrameRate) -ne $LegacyFrames[$i].StartFrame -or [int][Math]::Round($Captions[$i].End*$FrameRate) -ne $LegacyFrames[$i].EndFrame){$changed[[int]$Captions[$i].SourceCueIndex]=$true}
    }
    while($true){
        $blocked=@{}
        for($i=0;$i+1 -lt $Captions.Count;$i++){
            if([int][Math]::Round($Captions[$i].End*$FrameRate)-[int][Math]::Round($Captions[$i+1].Start*$FrameRate) -le 1){continue}
            foreach($cueIndex in @([int]$Captions[$i].SourceCueIndex,[int]$Captions[$i+1].SourceCueIndex)){if($changed.ContainsKey($cueIndex)){$blocked[$cueIndex]=$true}}
        }
        if(-not $blocked.Count){break}
        # A validated speech edge can conflict with a neighboring legacy or
        # recovered cue. Do not invent a midpoint or discard words. Retain the
        # whole conflicting cue's old timing and explicitly request review.
        for($i=0;$i -lt $Captions.Count;$i++){
            $cueIndex=[int]$Captions[$i].SourceCueIndex
            if($blocked.ContainsKey($cueIndex)){
                $Captions[$i].Start=[Math]::Round($LegacyFrames[$i].StartFrame/$FrameRate,6)
                $Captions[$i].End=[Math]::Round($LegacyFrames[$i].EndFrame/$FrameRate,6)
            }
        }
        foreach($cueIndex in $blocked.Keys){$changed.Remove($cueIndex);$review[$cueIndex]=$true}
    }
    return @($review.Keys | Sort-Object)
}

function Split-PvsAcousticCaptionCue {
    param($Cue,[int]$MaxCharacters,[double]$FrameRate,[object[]]$VoiceSilences=@())
    $timings=if($Cue.PSObject.Properties['CaptionWordTimings']){$Cue.CaptionWordTimings}else{$Cue.WordTimings}
    $chunks=@(Get-PvsCaptionTextChunks -Text $Cue.Text -MaxCharacters $MaxCharacters -WordTimings $timings -VoiceSilences $VoiceSilences)
    $parts=New-Object System.Collections.Generic.List[object]
    for($i=0;$i -lt $chunks.Count;$i++){
        $chunk=$chunks[$i]
        $first=@($timings | Where-Object {$_.TargetWordIndex -eq $chunk.StartWordIndex})
        $last=@($timings | Where-Object {$_.TargetWordIndex -eq $chunk.EndWordIndex})
        if($first.Count -ne 1 -or $last.Count -ne 1){throw "CAPTION_DTW_EDGE_MISSING:cue-$($Cue.Index)"}
        $start=[int][Math]::Ceiling([double]$first[0].Start*$FrameRate-0.0000001)
        $end=[int][Math]::Floor([double]$last[0].End*$FrameRate+0.0000001)
        if($end -le $start){throw "CAPTION_DTW_INTERVAL_COLLAPSED:cue-$($Cue.Index)"}
        $kind='cue';$applied=$false
        if($i -gt 0){
            $previous=$parts[$parts.Count-1];$left=$chunks[$i-1]
            if($null -ne $left.PauseCenter -or $first[0].Start-$previous.End -gt 1.0/$FrameRate+0.000001){$kind='pause'}
            elseif($left.Text -match '[.!?;:,\u2026]["''\u201d\u2019\u00bb)\]]*\s*$'){$kind='punctuation'}
            else{$kind='character-limit'}
            if($kind -eq 'character-limit' -and $first[0].PSObject.Properties['ContinuousTokenStart'] -and $null -ne $first[0].ContinuousTokenStart -and [Math]::Abs($start-$previous.EndFrame) -le 1){
                # DTW token OUTPUT is not word onset. Use the observed boundary
                # before the first token, not any fixed frame subtraction.
                $boundary=[int][Math]::Ceiling([double]$first[0].ContinuousTokenStart*$FrameRate-0.0000001)
                if($boundary -lt $start -and $boundary-$previous.StartFrame -ge 2){
                    $previous.EndFrame=$boundary;$previous.End=$boundary/$FrameRate
                    $start=$boundary;$applied=$true
                }
            }
        }
        $parts.Add([pscustomobject]@{Text=$chunk.Text;Start=$start/$FrameRate;End=$end/$FrameRate;StartFrame=$start;EndFrame=$end;PartIndex=$i+1;PartCount=$chunks.Count;VoiceBoundaryAligned=$true;IndependentSpeechEdges=$true;StartBoundaryKind=$kind;TokenBoundaryApplied=$applied})
    }
    return $parts.ToArray()
}

function Repair-PvsDtwCaptionEdges {
    param([object[]]$Cues,[object[]]$Quiet,[double]$Duration,[scriptblock]$RecognizeWindow,[object[]]$Sources=@(),[int]$MaxCharacters=42,[string]$Language='vi')
    $refined=New-Object System.Collections.Generic.List[int];$unverified=New-Object System.Collections.Generic.List[int]
    for($i=0;$i -lt $Cues.Count;$i++){
        $cue=$Cues[$i]
        $chunks=@(Get-PvsCaptionTextChunks $cue.Text $MaxCharacters $cue.WordTimings $Quiet)
        $available=@{};foreach($t in $cue.WordTimings){$available[[int]$t.TargetWordIndex]=$true}
        if(-not @($chunks | Where-Object {-not $available.ContainsKey([int]$_.StartWordIndex) -or -not $available.ContainsKey([int]$_.EndWordIndex)}).Count){continue}
        $start=if($i -gt 0){[Math]::Max(0.0,[double]$Cues[$i-1].End-0.05)}else{0.0}
        $end=if($i+1 -lt $Cues.Count){[Math]::Min($Duration,[double]$Cues[$i+1].Start+0.05)}else{$Duration}
        if($Sources.Count){
            $chapter=[int]$cue.Chapter
            if($chapter -lt 0 -or $chapter -ge $Sources.Count){$unverified.Add([int]$cue.Index);continue}
            $source=$Sources[$chapter]
            if($i -eq 0 -or [int]$Cues[$i-1].Chapter -ne $chapter -or $null -eq $Cues[$i-1].End){$start=[double]$source.start}
            if($i+1 -ge $Cues.Count -or [int]$Cues[$i+1].Chapter -ne $chapter -or $null -eq $Cues[$i+1].Start){$end=[double]$source.end}
            $start=[Math]::Max($start,[double]$source.start);$end=[Math]::Min($end,[double]$source.end)
        }
        if($end-$start -le 0.2 -or $end-$start -gt 30){$unverified.Add([int]$cue.Index);continue}
        $target=@(ConvertTo-NormalizedWords $cue.Text)
        try {$recognized=@(& $RecognizeWindow $start $end $cue.Text $cue.Chapter)}
        catch {
            if($_.Exception.Message -match '^CAPTION_DTW_(ANCHOR|ANCHORS|SURFACE|DATA)'){$unverified.Add([int]$cue.Index);continue}
            throw
        }
        if($Language -eq 'vi'){$recognized=@(Join-PvsRecognizedNumericWords -TargetWords $target -Words $recognized)}
        $local=@(Align-CuesToRecognizedWords -Cues @($cue) -RecognizedWords $recognized -VoiceClips @([pscustomobject]@{start=$start;end=$end}))
        $valid=$local.Count -eq 1 -and $null -ne $local[0].Start -and $local[0].Confidence -ge 0.8 -and @($local[0].WordTimings).Count -eq $target.Count
        if($valid -and @($local[0].WordTimings | Where-Object {$_.PSObject.Properties['SubtitleTimingQuality'] -and $_.SubtitleTimingQuality -ne 'dtw'}).Count){$valid=$false}
        if($valid){
            $previous=$start
            foreach($t in $local[0].WordTimings){if($t.Start -lt $previous-0.000001 -or $t.End -le $t.Start -or $t.End -gt $end+0.000001){$valid=$false;break};$previous=$t.End}
        }
        if(-not $valid){$unverified.Add([int]$cue.Index);continue}
        Add-PvsCaptionTokenBoundaryTimings -Cues $local -Words $recognized -Offset $start
        foreach($timing in $local[0].WordTimings){$timing.Chapter=[int]$cue.Chapter}
        # Keep edit cue bounds and original timings untouched, even in this
        # isolated experiment. Only captions consume the recovered overlay.
        $cue | Add-Member -NotePropertyName CaptionWordTimings -NotePropertyValue @($local[0].WordTimings) -Force
        $refined.Add([int]$cue.Index)
    }
    [pscustomobject]@{Refined=$refined.ToArray();Unverified=$unverified.ToArray()}
}

function Get-PvsCaptionQuiet {
    param([string]$FfmpegPath,[string]$WavPath,[double]$MinimumDuration=0.12)
    $filter='silencedetect=noise=-35dB:d='+$MinimumDuration.ToString('0.########',[Globalization.CultureInfo]::InvariantCulture)
    $run=Invoke-NativeCapture $FfmpegPath @('-hide_banner','-i',$WavPath,'-af',$filter,'-f','null','NUL')
    if($run.ExitCode -ne 0){throw "CAPTION_SILENCE_ANALYSIS_FAILED:$($run.Output)"}
    $quiet=New-Object System.Collections.Generic.List[object];$pending=$null
    foreach($line in ($run.Output -split '\r?\n')){
        if($line -match 'silence_start:\s*([0-9.]+)'){$pending=[double]::Parse($Matches[1],[Globalization.CultureInfo]::InvariantCulture)}
        if($null -ne $pending -and $line -match 'silence_end:\s*([0-9.]+)'){
            $end=[double]::Parse($Matches[1],[Globalization.CultureInfo]::InvariantCulture)
            $quiet.Add([pscustomobject]@{Start=$pending;End=$end;Duration=$end-$pending});$pending=$null
        }
    }
    return $quiet.ToArray()
}

function Invoke-PvsCaptionDtwRecognition {
    param([string]$WhisperPath,[string]$CpuWhisperPath,[string]$ModelPath,[string]$ModelName,[string]$WavPath,[string]$OutBase,[string]$Language,[string]$Backend='cpu',[string[]]$BackendArguments=@(),[string]$Prompt='',[bool]$UseDtw=$true,[bool]$SplitOnWord=$true)
    $profile=New-PvsWhisperRecognitionProfile -ModelPath $ModelPath -ModelName $ModelName
    return Invoke-PvsRecognitionBackend -Profile $profile -WhisperPath $WhisperPath -CpuWhisperPath $CpuWhisperPath -WavPath $WavPath -OutBase $OutBase -Language $Language -Backend $Backend -BackendArguments $BackendArguments -Prompt $Prompt -UseDtw $UseDtw -SplitOnWord $SplitOnWord
}

function Set-PvsDtwCaptionOverlay {
    param([object[]]$Cues,[object[]]$CaptionCues,[int]$MaxCharacters=42,[object[]]$Quiet=@())
    $byIndex=@{};foreach($cue in $CaptionCues){$byIndex[[int]$cue.Index]=$cue}
    $review=New-Object System.Collections.Generic.List[int]
    foreach($cue in $Cues){
        if(-not $byIndex.ContainsKey([int]$cue.Index)){$review.Add([int]$cue.Index);continue}
        $candidate=$byIndex[[int]$cue.Index]
        $timings=if($candidate.PSObject.Properties['CaptionWordTimings']){$candidate.CaptionWordTimings}else{$candidate.WordTimings}
        $available=@{};foreach($t in $timings){$available[[int]$t.TargetWordIndex]=$t}
        $chunks=@(Get-PvsCaptionTextChunks $cue.Text $MaxCharacters $timings $Quiet)
        $valid=$candidate.Text -ceq $cue.Text -and @($timings).Count -gt 0 -and [int]$candidate.Chapter -eq [int]$cue.Chapter
        if(@($timings | Where-Object {$_.PSObject.Properties['SubtitleTimingQuality'] -and $_.SubtitleTimingQuality -ne 'dtw'}).Count){$valid=$false}
        foreach($chunk in $chunks){if(-not $available.ContainsKey([int]$chunk.StartWordIndex) -or -not $available.ContainsKey([int]$chunk.EndWordIndex)){$valid=$false;break}}
        if(-not $valid){$review.Add([int]$cue.Index);continue}
        $cue | Add-Member -NotePropertyName CaptionWordTimings -NotePropertyValue @($timings | ForEach-Object {$_.PSObject.Copy()}) -Force
        $cue | Add-Member -NotePropertyName CaptionStart -NotePropertyValue $timings[0].Start -Force
        $cue | Add-Member -NotePropertyName CaptionEnd -NotePropertyValue $timings[-1].End -Force
        $cue | Add-Member -NotePropertyName CaptionTimingRevision -NotePropertyValue 'dtw-word-boundary-v1' -Force
    }
    return $review.ToArray()
}

function Set-PvsSourceGapSpeechEvidence {
    param([object[]]$Cues,[object[]]$ObservedCues,[object[]]$Words,[object[]]$Voices)
    # Edge evidence is a separate capability. Never expand a compact raw token
    # into invented word timings or relax the ordinary recovered-cue cut guard.
    if(-not (Get-Command Get-PvsAutoEditReferenceWordCoverage -ErrorAction SilentlyContinue)){return}
    $byIndex=@{};$needed=@{};foreach($c in $Cues){$byIndex[[int]$c.Index]=$c}
    for($i=0;$i -lt $Cues.Count;$i++){
        if(-not ($Cues[$i].PSObject.Properties['EditBoundaryReviewRequired'] -and $Cues[$i].EditBoundaryReviewRequired)){continue}
        foreach($j in @(($i-1),$i,($i+1))){if($j -ge 0 -and $j -lt $Cues.Count -and $Cues[$j].Chapter -eq $Cues[$i].Chapter){$needed[[int]$Cues[$j].Index]=$true}}
    }
    foreach($observed in $ObservedCues){
        if(-not $byIndex.ContainsKey([int]$observed.Index) -or -not $needed.ContainsKey([int]$observed.Index)){continue}
        $cue=$byIndex[[int]$observed.Index]
        if($cue.PSObject.Properties['ManualEditBlock'] -and $cue.ManualEditBlock){continue}
        $coverage=Get-PvsAutoEditReferenceWordCoverage $observed $Words $Voices
        if($null -eq $coverage){continue}
        $chapter=[int]$observed.Chapter;$offset=[double]$Voices[$chapter].start
        $heard=@($Words | Where-Object {$_.Chapter -eq $chapter -and $offset+$_.Start -ge $observed.Start-0.000001 -and $offset+$_.End -le $observed.End+0.000001})
        $timings=@($observed.WordTimings)
        if($heard.Count -lt 4 -or $heard.Count -ne $timings.Count){continue}
        foreach($side in @('Start','End')){
            $indices=if($side -eq 'Start'){@(0..3)}else{@(($heard.Count-4)..($heard.Count-1))}
            $valid=$true;$edge=0.0
            foreach($i in $indices){
                $w=$heard[$i];$a=[double]$w.Start;$b=[double]$w.End
                $digitGroup=@($coverage.groups | Where-Object timingIndex -eq $i).Count -eq 1
                if((-not $timings[$i].Exact -and -not $digitGroup) -or -not $w.PSObject.Properties['SubtitleTimingQuality'] -or $w.SubtitleTimingQuality -ne 'dtw' -or
                    [double]::IsNaN($a) -or [double]::IsNaN($b) -or [double]::IsInfinity($a) -or [double]::IsInfinity($b) -or $a -lt $edge-0.000001 -or $b -le $a -or $offset+$b -gt $Voices[$chapter].end+0.000001){$valid=$false;break}
                $edge=$b
            }
            if(-not $valid){continue}
            $tokens=@($indices | ForEach-Object {[string]$heard[$_].Text})
            $hits=0
            for($i=0;$i+3 -lt $Words.Count;$i++){
                if(@($Words[$i..($i+3)] | Where-Object Chapter -ne $chapter).Count){continue}
                if((@($Words[$i..($i+3)].Text) -join ' ') -ceq ($tokens -join ' ')){$hits++}
            }
            if($hits -ne 1){continue}
            $proof=[pscustomobject]@{revision='raw-dtw-context-edge-v1';cueIndex=[int]$cue.Index;chapter=$chapter;side=$side;start=$offset+$heard[$indices[0]].Start;end=$offset+$heard[$indices[-1]].End;rawContext=$tokens;coverage=$coverage.kind}
            $cue | Add-Member NoteProperty ('SourceGap'+$side+'Evidence') $proof -Force
        }
    }
}

function Prepare-PvsAutoCaptionTimings {
    param([object[]]$Cues,[object[]]$TargetCues,[object[]]$Voices,[string]$AnalysisDir,[string]$FfmpegPath,[string]$WhisperPath,[string]$CpuWhisperPath,[string]$ModelPath,[string]$ModelName,[string]$Backend,[string[]]$BackendArguments=@(),[int]$MaxCharacters=42,[switch]$ApplyEditTiming,[string]$Language='vi',[double]$FrameRate=30)
    $words=New-Object System.Collections.Generic.List[object]
    $quiet=New-Object System.Collections.Generic.List[object]
    $available=@{};$reasons=New-Object System.Collections.Generic.List[string]
    $retryRanges=New-Object System.Collections.Generic.List[object]
    $estimatedRanges=New-Object System.Collections.Generic.List[object]
    $manualEstimatedRanges=New-Object System.Collections.Generic.List[object]
    $autoAcousticState=[pscustomobject]@{Calls=0;Backend=$Backend;Whisper=$WhisperPath;Arguments=$BackendArguments;AcousticBoundaries=0}
    $cacheBefore=Get-PvsAudioCacheStats
    function Invoke-AutoCaptionRecognition {
        param([string]$Wav,[string]$Base,[bool]$Sentences=$false,[string]$Prompt='')
        $r=Invoke-PvsCaptionDtwRecognition -WhisperPath $autoAcousticState.Whisper -CpuWhisperPath $CpuWhisperPath -ModelPath $ModelPath -ModelName $ModelName -WavPath $Wav -OutBase $Base -Language $Language -Backend $autoAcousticState.Backend -BackendArguments $autoAcousticState.Arguments -UseDtw (-not $Sentences) -SplitOnWord (-not $Sentences) -Prompt $Prompt
        $autoAcousticState.Calls+=$r.InvocationCount;$autoAcousticState.Backend=$r.Backend
        if($r.FallbackReason){$reasons.Add("Caption CUDA fallback: $($r.FallbackReason)");$autoAcousticState.Whisper=$CpuWhisperPath;$autoAcousticState.Arguments=@('--no-gpu')}
        return $r.Json
    }
    function Add-AutoTimingReport {
        param($Recognition,[double]$Offset,[double]$Scale,[int]$Chapter,[bool]$ManualOnly=$false)
        foreach($r in $Recognition.RetryRanges){$retryRanges.Add([pscustomobject]@{sourceIndex=$Chapter;start=$Offset+$r.start*$Scale;end=$Offset+$r.end*$Scale;reason=$r.reason;quality=$r.quality})}
        foreach($r in $Recognition.EstimatedRanges){
            $item=[pscustomobject]@{sourceIndex=$Chapter;start=$Offset+$r.start*$Scale;end=$Offset+$r.end*$Scale;reason=$r.reason}
            if($ManualOnly){$manualEstimatedRanges.Add($item)}else{$estimatedRanges.Add($item)}
        }
        $autoAcousticState.AcousticBoundaries+=$Recognition.AcousticBoundaryCount
    }
    for($chapter=0;$chapter -lt $Voices.Count;$chapter++){
        $voice=$Voices[$chapter]
        $path=Resolve-PvsExistingPath -Path ([string]$voice.path) -Purpose 'Caption timing voice'
        $speed=if($voice.PSObject.Properties['speedPercent']){[double]$voice.speedPercent}else{100.0}
        if($speed -le 0 -or [double]::IsNaN($speed) -or [double]::IsInfinity($speed)){throw 'ACOUSTIC_VOICE_SPEED_INVALID'}
        $scale=100.0/$speed
        $wav=Join-Path $AnalysisDir ('voice-{0:000}.wav' -f ($chapter+1))
        if(-not (Test-Path -LiteralPath $wav)){
            $run=Invoke-NativeCapture $FfmpegPath @('-y','-hide_banner','-loglevel','error','-i',$path,'-ar','16000','-ac','1','-c:a','pcm_s16le',$wav)
            if($run.ExitCode -ne 0){throw 'CAPTION_DTW_AUDIO_CONVERSION_FAILED'}
        }
        $duration=Get-PvsPcmWaveDuration $wav
        $localQuiet=@(Get-PvsCaptionQuiet $FfmpegPath $wav)
        $base=Join-Path $AnalysisDir ('caption-{0:000}' -f $chapter)
        $json=Invoke-AutoCaptionRecognition $wav $base
        $speech=Convert-PvsAcousticRecognition -Json $json -WavPath $wav -OutBase $base -Duration $duration -Chapter $chapter -Quiet $localQuiet -FfmpegPath $FfmpegPath -Recognize {
            param($windowWav,$windowBase,$sentences)
            Invoke-AutoCaptionRecognition $windowWav $windowBase $sentences
        }
        Add-AutoTimingReport $speech ([double]$voice.start) $scale $chapter
        $clipDuration=[double]$voice.end-[double]$voice.start
        foreach($word in $speech.Words){
            $word.Start*=$scale;$word.End=[Math]::Min($clipDuration,$word.End*$scale)
            foreach($name in @('DtwFirst','DtwLast','DtwBoundaryStart')){if($word.PSObject.Properties[$name] -and $null -ne $word.$name){$word.$name*=$scale}}
            if($word.End -le $word.Start -or $word.Start -ge $clipDuration){continue}
            $word.Chapter=$chapter;$words.Add($word)
        }
        foreach($q in $localQuiet){
            $a=[double]$voice.start+$q.Start*$scale;$b=[Math]::Min([double]$voice.end,[double]$voice.start+$q.End*$scale)
            if($b -gt $a){$quiet.Add([pscustomobject]@{Start=$a;End=$b;Duration=$b-$a})}
        }
        $available[$chapter]=$true
    }
    $manualCaptionRefined=0;$independentCuts=@()
    if($ApplyEditTiming -and @($Cues | Where-Object {$_.PSObject.Properties['ManualEditBlock'] -and $_.ManualEditBlock}).Count){
        $independentCuts=@(Get-PvsAcousticReferenceCuts $TargetCues $words.ToArray() $Voices $quiet.ToArray() $FrameRate)
    }
    $estimatedSpans=@{}
    foreach($word in $words){
        if($word.SubtitleTimingQuality -ne 'estimated'){continue}
        $offset=[double]$Voices[[int]$word.Chapter].start
        $estimatedSpans[('{0}|{1:R}|{2:R}' -f $word.Chapter,($offset+$word.Start),($offset+$word.End))]=$true
    }
    $captionCues=@(foreach($chapter in ($available.Keys | Sort-Object)){
        $manualBlocks=@($Cues | Where-Object {[int]$_.Chapter -eq $chapter -and $_.PSObject.Properties['ManualEditBlock'] -and $_.ManualEditBlock})
        $chapterCues=@($Cues | Where-Object {[int]$_.Chapter -eq $chapter -and -not ($_.PSObject.Properties['ManualEditBlock'] -and $_.ManualEditBlock)})
        if(-not $chapterCues.Count){continue}
        $chapterWords=@($words | Where-Object {
            if($_.Chapter -ne $chapter){return $false}
            $a=[double]$Voices[$chapter].start+$_.Start;$b=[double]$Voices[$chapter].start+$_.End
            -not @($manualBlocks | Where-Object {$_.Start -lt $b-0.000001 -and $_.End -gt $a+0.000001}).Count
        })
        if(-not $chapterWords.Count){continue}
        $chapterTargets=@(foreach($cue in $chapterCues){$TargetCues[[int]$cue.Index-1]})
        $mapped=@(Align-CuesToRecognizedWords -Cues $chapterTargets -RecognizedWords $chapterWords -VoiceClips $Voices)
        for($i=0;$i -lt $mapped.Count;$i++){$mapped[$i].Index=[int]$chapterCues[$i].Index;$mapped[$i].Chapter=[int]$chapter}
        Set-PvsSourceGapSpeechEvidence -Cues $chapterCues -ObservedCues $mapped -Words $chapterWords -Voices $Voices
        for($i=0;$i -lt $mapped.Count;$i++){
            $mapped[$i].Index=[int]$chapterCues[$i].Index;$mapped[$i].Chapter=[int]$chapter
            $quality=if(Test-PvsSubtitleDtwCue $mapped[$i] $estimatedSpans){'dtw'}else{'estimated'}
            $mapped[$i] | Add-Member -NotePropertyName AcousticTimingQuality -NotePropertyValue $quality
            $mapped[$i]
        }
    })
    $eligible=@($captionCues | Where-Object AcousticTimingQuality -eq 'dtw')
    foreach($chapter in $available.Keys){Add-PvsCaptionTokenBoundaryTimings -Cues @($eligible | Where-Object {$_.Chapter -eq $chapter}) -Words @($words | Where-Object {$_.Chapter -eq $chapter}) -Offset ([double]$Voices[$chapter].start)}
    $recognizeCaptionWindow={
        param([double]$start,[double]$end,[string]$text,[int]$chapter,[bool]$ManualCellRetry=$false)
        $voice=$Voices[$chapter];$speed=if($voice.PSObject.Properties['speedPercent']){[double]$voice.speedPercent}else{100.0};$scale=100.0/$speed
        $cut=($start-[double]$voice.start)/$scale;$length=($end-$start)/$scale
        $base=Join-Path $AnalysisDir ('caption-retry-'+[guid]::NewGuid().ToString('N'))
        $run=Invoke-NativeCapture $FfmpegPath @('-y','-hide_banner','-loglevel','error','-ss',$cut.ToString('0.########',[Globalization.CultureInfo]::InvariantCulture),'-i',([string]$voice.path),'-t',$length.ToString('0.########',[Globalization.CultureInfo]::InvariantCulture),'-ar','16000','-ac','1','-c:a','pcm_s16le',($base+'.wav'))
        if($run.ExitCode -ne 0){throw 'CAPTION_DTW_RETRY_AUDIO_FAILED'}
        $retryPrompt=if($Language -eq 'vi'){Get-PvsNumericCaptionPrompt $text}else{$text}
        $json=Invoke-AutoCaptionRecognition ($base+'.wav') $base $false $retryPrompt
        $localQuiet=@(Get-PvsCaptionQuiet $FfmpegPath ($base+'.wav'))
        $speech=Convert-PvsAcousticRecognition -Json $json -WavPath ($base+'.wav') -OutBase $base -Duration $length -Chapter 0 -Quiet $localQuiet -FfmpegPath $FfmpegPath -Recognize {
            param($windowWav,$windowBase,$sentences)
            Invoke-AutoCaptionRecognition $windowWav $windowBase $sentences $retryPrompt
        }
        Add-AutoTimingReport $speech $start $scale $chapter $ManualCellRetry
        foreach($word in $speech.Words){
            if($word.SubtitleTimingQuality -ne 'dtw'){continue}
            $word.Start*=$scale;$word.End*=$scale
            foreach($name in @('DtwFirst','DtwLast','DtwBoundaryStart')){if($word.PSObject.Properties[$name] -and $null -ne $word.$name){$word.$name*=$scale}}
            $word
        }
    }
    $retry=Repair-PvsDtwCaptionEdges -Cues $eligible -Quiet $quiet.ToArray() -Duration ([double]$Voices[-1].end) -Sources $Voices -MaxCharacters $MaxCharacters -Language $Language -RecognizeWindow $recognizeCaptionWindow
    $review=@(Set-PvsDtwCaptionOverlay -Cues $Cues -CaptionCues $eligible -MaxCharacters $MaxCharacters -Quiet $quiet.ToArray())
    $reviewSet=@{};foreach($index in $review){$reviewSet[[int]$index]=$true}
    foreach($cue in $Cues){if(-not $reviewSet.ContainsKey([int]$cue.Index)){$cue | Add-Member -NotePropertyName AcousticTimingQuality -NotePropertyValue 'dtw' -Force}}
    $edit=[pscustomobject]@{RefinedCues=@();Changes=@();ReviewCues=@();VoiceRanges=@()}
    if($ApplyEditTiming){$edit=Set-PvsAcousticEditTimings -Cues $Cues -Voices $Voices}
    $manualRetry=[pscustomobject]@{Calls=0}
    $manualReferences=@()
    if($ApplyEditTiming -and @($Cues | Where-Object {$_.PSObject.Properties['ManualEditBlock'] -and $_.ManualEditBlock}).Count){
        $manualReferences=@(Restore-PvsObservedManualReferenceCells $Cues $TargetCues $words.ToArray() $Voices)
        $manualCaptionRefined=Set-PvsManualAcousticCaptionTimings $Cues $words.ToArray() $Voices $recognizeCaptionWindow $manualRetry $TargetCues
    }
    $cacheAfter=Get-PvsAudioCacheStats;$hits=0
    if($null -ne $cacheBefore -and $null -ne $cacheAfter){$hits=$cacheAfter.whisperHits-$cacheBefore.whisperHits}
    [pscustomobject]@{Mode=$(if($eligible.Count){'dtw-word-boundary-v1'}else{'legacy'});ReviewCues=$review;RefinedCues=$retry.Refined;Reasons=$reasons.ToArray();Backend=$autoAcousticState.Backend;InvocationCount=$autoAcousticState.Calls;CacheHits=$hits;RetryRanges=$retryRanges.ToArray();EstimatedRanges=$estimatedRanges.ToArray();AcousticBoundaryCount=$autoAcousticState.AcousticBoundaries;BoundaryMode='waveform-valley-v1';EditRefinedCues=$edit.RefinedCues;EditChanges=$edit.Changes;EditReviewCues=$edit.ReviewCues;EditVoiceRanges=$edit.VoiceRanges;AcousticWords=$words.ToArray();IndependentCuts=$independentCuts;ManualCaptionRefinedCount=$manualCaptionRefined;ManualCaptionRetryCount=$manualRetry.Calls;ManualEstimatedRanges=$manualEstimatedRanges.ToArray();ManualReferenceRecoveredCues=$manualReferences}
}
