Set-StrictMode -Version Latest

. "$PSScriptRoot\SubtitleEnergy.ps1"

function Get-PvsSubtitleContextPlan {
    param([double]$Start,[double]$End,[double]$SourceStart,[double]$SourceEnd,[object[]]$Quiet=@())
    foreach($value in @($Start,$End,$SourceStart,$SourceEnd)){if([double]::IsNaN($value) -or [double]::IsInfinity($value)){throw 'SUBTITLE_CONTEXT_RANGE_INVALID'}}
    if($SourceStart -lt 0 -or $Start -lt $SourceStart -or $End -gt $SourceEnd+0.000001 -or $End -le $Start){throw 'SUBTITLE_CONTEXT_RANGE_INVALID'}
    $cursor=$Start
    while($cursor -lt $End-0.000001){
        $stop=[Math]::Min($End,$cursor+20.0)
        if($stop -lt $End){
            $pauses=@($Quiet | Where-Object {$_.Duration -ge 0.12 -and ($_.Start+$_.End)/2 -ge $cursor+12 -and ($_.Start+$_.End)/2 -le $stop} | Sort-Object Start)
            if($pauses.Count){$stop=($pauses[-1].Start+$pauses[-1].End)/2.0}
        }
        [pscustomobject]@{Start=$cursor;End=$stop;ReadStart=[Math]::Max($SourceStart,$cursor-2.5);ReadEnd=[Math]::Min($SourceEnd,$stop+2.5)}
        $cursor=$stop
    }
}

function Get-PvsSubtitleAudioSupport {
    param($Energy,[double]$Start,[double]$End)
    $low=[Math]::Max(0,[int][Math]::Floor($Start/0.005));$high=[Math]::Min($Energy.Rms.Length,[int][Math]::Ceiling($End/0.005))
    if($high -le $low){return [pscustomobject]@{ActiveSeconds=0.0;Fraction=0.0;Peak=0.0}}
    $peak=0.0;for($i=$low;$i -lt $high;$i++){$peak=[Math]::Max($peak,[double]$Energy.Rms[$i])}
    # Relative threshold admits quiet voice; the fixed floor only rejects
    # near-digital silence. Energy is a guard, not a speech classifier.
    $threshold=[Math]::Max(0.0003,$peak*0.1);$active=0
    for($i=$low;$i -lt $high;$i++){if($Energy.Rms[$i] -gt $threshold){$active++}}
    [pscustomobject]@{ActiveSeconds=$active*0.005;Fraction=$active/[double]($high-$low);Peak=$peak}
}

function Test-PvsSubtitleQuietGap {
    param([double]$Start,[double]$End,[object[]]$Quiet)
    # Only a short, measured breath can be classified here. Longer missing
    # passages and technical failures remain visible for content review.
    if($End-$Start -le 0 -or $End-$Start -gt 0.65){return $false}
    $covered=0.0;$edge=$Start
    foreach($q in @($Quiet | Sort-Object Start)){
        $a=[Math]::Max($edge,[double]$q.Start);$b=[Math]::Min($End,[double]$q.End)
        if($b -gt $a){$covered+=$b-$a;$edge=$b}
    }
    return $covered/($End-$Start) -ge 0.9
}

function Get-PvsUsedSubtitleEstimatedRanges {
    param([object[]]$Cues,[object[]]$Ranges)
    foreach($range in $Ranges){
        $used=@(foreach($cue in $Cues){
            $timings=if($cue.PSObject.Properties['CaptionWordTimings']){$cue.CaptionWordTimings}else{$cue.WordTimings}
            foreach($t in $timings){if($t.PSObject.Properties['SubtitleTimingQuality'] -and $t.SubtitleTimingQuality -eq 'estimated' -and $t.PSObject.Properties['SubtitleTimingOrigin'] -and $t.SubtitleTimingOrigin -ceq $range.origin -and $t.Start -lt $range.end -and $t.End -gt $range.start){$t}}
        })
        if(-not $used.Count){continue}
        [pscustomobject]@{sourceIndex=$range.sourceIndex;start=[Math]::Max([double]$range.start,($used.Start | Measure-Object -Minimum).Minimum);end=[Math]::Min([double]$range.end,($used.End | Measure-Object -Maximum).Maximum);reason=$range.reason}
    }
}

function Get-PvsUncoveredSubtitleRecognitionRanges {
    param([object[]]$Ranges,[object[]]$Cues,[object[]]$Quiet,[double]$FrameRate)
    $seen=@{}
    foreach($range in $Ranges){
        $cursor=[double]$range.start
        foreach($cue in @($Cues | Where-Object {$_.Start -lt $range.end -and $_.End -gt $range.start} | Sort-Object Start)){
            if($cue.Start-$cursor -ge 1.0/$FrameRate -and -not (Test-PvsSubtitleQuietGap $cursor $cue.Start $Quiet)){
                $key='{0:F3}|{1:F3}' -f $cursor,[double]$cue.Start
                if(-not $seen.ContainsKey($key)){$seen[$key]=$true;[pscustomobject]@{sourceIndex=$range.sourceIndex;start=$cursor;end=[double]$cue.Start;reason=$range.reason}}
            }
            $cursor=[Math]::Max($cursor,[double]$cue.End)
        }
        if($range.end-$cursor -ge 1.0/$FrameRate -and -not (Test-PvsSubtitleQuietGap $cursor $range.end $Quiet)){
            $key='{0:F3}|{1:F3}' -f $cursor,[double]$range.end
            if(-not $seen.ContainsKey($key)){$seen[$key]=$true;[pscustomobject]@{sourceIndex=$range.sourceIndex;start=$cursor;end=[double]$range.end;reason=$range.reason}}
        }
    }
}

function Select-PvsSubtitleRecognitionWindow {
    param($Recognition,[double]$Start,[double]$End)
    $words=New-Object System.Collections.Generic.List[object];$surfaces=New-Object System.Collections.Generic.List[object]
    foreach($surface in $Recognition.Surfaces){
        $selected=@(for($i=[int]$surface.FirstWord;$i -le [int]$surface.LastWord;$i++){
            $w=$Recognition.Words[$i];$center=([double]$w.Start+[double]$w.End)/2
            if($center -ge $Start -and $center -lt $End){$i}
        })
        if(-not $selected.Count){continue}
        $lex=[regex]::Matches([string]$surface.Text,'[\p{L}\p{N}]+')
        if($lex.Count -ne [int]$surface.LastWord-[int]$surface.FirstWord+1){throw 'SUBTITLE_CONTEXT_TEXT_MAPPING_INVALID'}
        $first=$selected[0]-[int]$surface.FirstWord;$last=$selected[-1]-[int]$surface.FirstWord
        $a=$lex[$first].Index;$b=if($last -eq $lex.Count-1){$surface.Text.Length}else{$lex[$last+1].Index}
        $text=$surface.Text.Substring($a,$b-$a).Trim();$firstWord=$words.Count
        foreach($index in $selected){
            $copy=$Recognition.Words[$index].PSObject.Copy()
            $copy.Start=[Math]::Max($Start,[double]$copy.Start)-$Start;$copy.End=[Math]::Min($End,[double]$copy.End)-$Start
            foreach($name in @('DtwFirst','DtwLast','DtwBoundaryStart')){if($copy.PSObject.Properties[$name] -and $null -ne $copy.$name){$copy.$name=[double]$copy.$name-$Start}}
            $words.Add($copy)
        }
        $surfaces.Add([pscustomobject]@{Text=$text;Start=$words[$firstWord].Start;End=$words[-1].End;FirstWord=$firstWord;LastWord=$words.Count-1})
    }
    [pscustomobject]@{Words=$words.ToArray();Surfaces=$surfaces.ToArray()}
}

function Get-PvsSubtitleContextInterior {
    param($Recognition,[double]$Start,[double]$End,[string]$LeftText='',[string]$RightText='')
    $bounds=[pscustomobject]@{Start=$Start;End=$End;LeftMatched=$false;RightMatched=$false}
    $identityAvailable=$null -ne (Get-Command Get-PvsSubtitleWordIdentityWeight -ErrorAction SilentlyContinue)
    foreach($side in @('left','right')){
        $target=@(ConvertTo-NormalizedWords $(if($side -eq 'left'){$LeftText}else{$RightText}))
        for($length=[Math]::Min(8,$target.Count);$length -ge 4;$length--){
            $anchor=if($side -eq 'left'){@($target[($target.Count-$length)..($target.Count-1)])}else{@($target[0..($length-1)])}
            $hits=@(for($i=0;$i+$length -le $Recognition.Words.Count;$i++){
                # The neighboring SRT sentence is already identified. A single
                # spelling variant at its edge must not become new speech.
                # Require all other anchor words, and retain ambiguous repeats.
                $same=$true;$variants=0
                for($j=0;$j -lt $length;$j++){
                    $actual=[string]$Recognition.Words[$i+$j].Text
                    if($actual -ceq $anchor[$j]){continue}
                    $similar=$identityAvailable -and (Get-PvsSubtitleWordIdentityWeight $anchor[$j] $actual) -ge 0.75
                    # Five or more exact context words also identify a single
                    # ASR substitution such as SRT "lời giải" / ASR "lời dài".
                    # This trims an already retained neighbor, never adds SRT.
                    $boundedSubstitution=$length -ge 6 -and $identityAvailable -and (Get-PvsSubtitleWordIdentityWeight $anchor[$j] $actual -MinimumSimilarity 0.5) -ge 0.75
                    if(-not $similar -and -not $boundedSubstitution){$same=$false;break}
                    # Eight-word context may contain several close ASR
                    # spellings around a foreign name. Keep five other words,
                    # require each change to be similar, and keep the unique
                    # occurrence/time guards below. Short anchors stay strict.
                    $variants++;$limit=if($length -ge 8){3}else{1}
                    if($variants -gt $limit){$same=$false;break}
                }
                if($same){$i}
            })
            if($hits.Count -ne 1){continue}
            $at=$hits[0]
            $tolerance=[Math]::Min(2.5,$length*0.25)
            if($side -eq 'left'){$edge=[double]$Recognition.Words[$at+$length-1].End;if([Math]::Abs($edge-$Start) -le $tolerance){$bounds.Start=[Math]::Max($bounds.Start,$edge);$bounds.LeftMatched=$true}}
            else{$edge=[double]$Recognition.Words[$at].Start;if([Math]::Abs($edge-$End) -le $tolerance){$bounds.End=[Math]::Min($bounds.End,$edge);$bounds.RightMatched=$true}}
            break
        }
    }
    $bounds
}

function Select-PvsSupportedSubtitleRecognition {
    param($Recognition,$Energy,[double]$Offset=0.0)
    $words=New-Object System.Collections.Generic.List[object];$surfaces=New-Object System.Collections.Generic.List[object];$rejected=New-Object System.Collections.Generic.List[object]
    if($Recognition.Words.Count -ge 3 -and $Recognition.Surfaces.Count){
        $a=[double]$Recognition.Surfaces[0].Start;$b=[double]$Recognition.Surfaces[-1].End
        $support=Get-PvsSubtitleAudioSupport $Energy ($Offset+$a) ($Offset+$b)
        $chars=([string]($Recognition.Surfaces.Text -join ' ')).Length
        if($support.ActiveSeconds -lt 0.025 -or $Recognition.Words.Count/[Math]::Max(0.025,$support.ActiveSeconds) -gt 24 -or $chars/[Math]::Max(0.025,$support.ActiveSeconds) -gt 140 -or $chars/[Math]::Max(0.025,$b-$a) -gt 100){
            return [pscustomobject]@{Words=@();Surfaces=@();RejectedRanges=@([pscustomobject]@{start=$a;end=$b;reason='text-exceeds-audio-support'})}
        }
    }
    foreach($surface in $Recognition.Surfaces){
        $duration=[double]$surface.End-[double]$surface.Start
        $support=Get-PvsSubtitleAudioSupport $Energy ($Offset+$surface.Start) ($Offset+$surface.End)
        $count=[int]$surface.LastWord-[int]$surface.FirstWord+1
        $estimated=@($Recognition.Words[[int]$surface.FirstWord..[int]$surface.LastWord] | Where-Object {$_.PSObject.Properties['SubtitleTimingQuality'] -and $_.SubtitleTimingQuality -eq 'estimated'}).Count -gt 0
        # Generous upper bounds detect grossly compressed hypotheses, not a
        # readability target. Never blacklist real CTA text or channel names.
        $reason=if(($count -ge 3 -or $estimated) -and $support.ActiveSeconds -lt 0.01){'audio-near-silence'}elseif($duration -le 0 -or ($count -ge 3 -and ($surface.Text.Length/$duration -gt 100 -or $count/[Math]::Max(0.025,$support.ActiveSeconds) -gt 24 -or $surface.Text.Length/[Math]::Max(0.025,$support.ActiveSeconds) -gt 140))){'text-exceeds-audio-support'}else{''}
        if($reason){$rejected.Add([pscustomobject]@{start=$surface.Start;end=$surface.End;reason=$reason});continue}
        $first=$words.Count
        for($i=[int]$surface.FirstWord;$i -le [int]$surface.LastWord;$i++){$words.Add($Recognition.Words[$i])}
        $copy=$surface.PSObject.Copy();$copy.FirstWord=$first;$copy.LastWord=$words.Count-1;$surfaces.Add($copy)
    }
    [pscustomobject]@{Words=$words.ToArray();Surfaces=$surfaces.ToArray();RejectedRanges=$rejected.ToArray()}
}

function Select-PvsPrimarySubtitleTail {
    param($Primary,$Source,[double]$Start,[double]$End,[int]$Chapter,[string]$LeftText)
    # Empty or wholly estimated local re-recognition must not erase an already
    # bounded primary tail. This is not a transcript vote: only a complete DTW-supported tail
    # outside retained SRT qualifies, after a unique retained left neighbor.
    if($null -eq $Primary -or $End -ne [double]$Source.end -or $Start -le [double]$Source.start -or -not $LeftText){return $null}
    if($Primary.SourceStart -ne [double]$Source.start -or $Primary.SourceEnd -ne [double]$Source.end -or $Primary.Chapter -ne $Chapter){return $null}
    $recognition=$Primary.Recognition;$duration=[double]$Source.end-[double]$Source.start
    $previous=0.0
    foreach($word in $recognition.Words){
        $a=[double]$word.Start;$b=[double]$word.End
        if([double]::IsNaN($a) -or [double]::IsInfinity($a) -or [double]::IsNaN($b) -or [double]::IsInfinity($b) -or $a -lt $previous-0.000001 -or $b -le $a -or $b -gt $duration+0.000001 -or [int]$word.Chapter -ne $Chapter){return $null}
        $previous=$b
    }
    $bounds=Get-PvsSubtitleContextInterior $recognition ($Start-[double]$Source.start) ($End-[double]$Source.start) $LeftText ''
    if(-not $bounds.LeftMatched -or $bounds.End -le $bounds.Start){return $null}
    foreach($word in $recognition.Words){
        if(($word.Start -lt $bounds.Start-0.000001 -and $word.End -gt $bounds.Start+0.000001) -or ($word.Start -lt $bounds.End-0.000001 -and $word.End -gt $bounds.End+0.000001)){return $null}
        if($word.Start -lt $bounds.Start -or $word.End -gt $bounds.End){continue}
        if(-not $word.PSObject.Properties['SubtitleTimingQuality'] -or $word.SubtitleTimingQuality -ne 'dtw' -or -not $word.PSObject.Properties['SubtitleTimingOrigin'] -or -not $word.SubtitleTimingOrigin){return $null}
        foreach($name in @('DtwFirst','DtwLast')){
            if(-not $word.PSObject.Properties[$name] -or $null -eq $word.$name){return $null}
            $anchor=[double]$word.$name
            if([double]::IsNaN($anchor) -or [double]::IsInfinity($anchor) -or $anchor -lt $bounds.Start-0.000001 -or $anchor -gt $bounds.End+0.000001){return $null}
        }
        if($word.DtwLast -lt $word.DtwFirst){return $null}
    }
    $cropped=Select-PvsSubtitleRecognitionWindow $recognition $bounds.Start $bounds.End
    if($cropped.Words.Count -lt 4){return $null}
    $supported=Select-PvsSupportedSubtitleRecognition $cropped $Primary.Energy $bounds.Start
    if($supported.RejectedRanges.Count -or $supported.Words.Count -ne $cropped.Words.Count){return $null}
    $offset=[double]$Source.start+$bounds.Start-$Start
    foreach($word in $supported.Words){
        $word.Start+=$offset;$word.End+=$offset
        foreach($name in @('DtwFirst','DtwLast','DtwBoundaryStart')){if($word.PSObject.Properties[$name] -and $null -ne $word.$name){$word.$name+=$offset}}
    }
    foreach($surface in $supported.Surfaces){$surface.Start+=$offset;$surface.End+=$offset}
    return [pscustomobject]@{Words=$supported.Words;Surfaces=$supported.Surfaces;CoveredByReferenceContext=$false;PrimaryRecognitionReused=$true}
}

# Shared acoustic timing for standalone subtitles and Auto edit. Coordinates
# remain in PCM source seconds here; adapters apply speed and timeline offsets.
function Convert-PvsAcousticRecognition {
    param($Json,[string]$WavPath,[string]$OutBase,[double]$Duration,[int]$Chapter,
        [object[]]$Quiet,[string]$FfmpegPath,[Parameter(Mandatory)][scriptblock]$Recognize,[switch]$GuardRecognitionText)
    $boundaryQuiet=@(Get-PvsCaptionQuiet -FfmpegPath $FfmpegPath -WavPath $WavPath -MinimumDuration 0.015)
    $energy=Get-PvsSubtitleEnergy -Path $WavPath
    $state=[pscustomobject]@{Calls=0}
    $converted=Convert-PvsSubtitleDtwWindows -Json $Json -Quiet $Quiet -BoundaryQuiet $boundaryQuiet -Duration $Duration -Chapter $Chapter -Energy $energy -RecognizeWindow {
        param([double]$start,[double]$end,[bool]$sentences)
        $state.Calls++
        $base=$OutBase+'-timing-'+$state.Calls
        $cut=Invoke-NativeCapture -FilePath $FfmpegPath -Arguments @('-y','-hide_banner','-loglevel','error','-ss',$start.ToString('0.########',[Globalization.CultureInfo]::InvariantCulture),'-i',$WavPath,'-t',($end-$start).ToString('0.########',[Globalization.CultureInfo]::InvariantCulture),'-ar','16000','-ac','1','-c:a','pcm_s16le',($base+'.wav'))
        if($cut.ExitCode -ne 0){throw 'ACOUSTIC_TIMING_WINDOW_AUDIO_FAILED'}
        & $Recognize ($base+'.wav') $base $sentences
    }
    $converted | Add-Member -NotePropertyName WindowInvocationCount -NotePropertyValue $state.Calls
    if($GuardRecognitionText){
        $supported=Select-PvsSupportedSubtitleRecognition $converted $energy
        $converted.Words=$supported.Words;$converted.Surfaces=$supported.Surfaces
        $converted | Add-Member -NotePropertyName RejectedRanges -NotePropertyValue $supported.RejectedRanges
    }
    return $converted
}

# A bad attention anchor must not downgrade an entire chapter or timeline
# export to uniformly spaced words from sentence timestamps.
function Convert-PvsSubtitleDtwWindows {
    param($Json,[object[]]$Quiet,[object[]]$BoundaryQuiet,[double]$Duration,[int]$Chapter,
        [Parameter(Mandatory)][scriptblock]$RecognizeWindow,$Energy=$null)
    $edges=New-Object System.Collections.Generic.List[double]
    $edges.Add(0.0)
    while($Duration-$edges[$edges.Count-1] -gt 26.0){
        $start=$edges[$edges.Count-1]
        $pauses=@($Quiet | Where-Object {$_.Duration -ge 0.12 -and ($_.Start+$_.End)/2 -ge $start+12 -and ($_.Start+$_.End)/2 -le $start+24} | Sort-Object Start)
        # Without a measured pause, retry the bounded window from audio; do
        # not cut the old token stream across a word and call it verified.
        $edge=if($pauses.Count){($pauses[-1].Start+$pauses[-1].End)/2.0}else{$start+24.0}
        $edges.Add($edge)
    }
    $edges.Add($Duration)
    $buckets=@{};for($i=0;$i -lt $edges.Count-1;$i++){$buckets[$i]=New-Object System.Collections.Generic.List[object]}
    $previousWindow=0
    foreach($segment in $Json.transcription){
        if([string]$segment.text -match '^\s*\[.*\]\s*$'){continue}
        if(@(ConvertTo-NormalizedWords ([string]$segment.text)).Count -eq 0){
            if([string]$segment.text -match '^\s*[,;:.!?\u2026]+\s*$'){$buckets[$previousWindow].Add($segment)}
            continue
        }
        $anchors=@($segment.tokens | Where-Object {$_.id -lt 50257 -and $_.t_dtw -ge 0 -and [string]$_.text -match '[\p{L}\p{N}]'} | ForEach-Object {[double]$_.t_dtw/100.0})
        $center=if($anchors.Count){($anchors[0]+$anchors[-1])/2.0}else{([double]$segment.offsets.from+[double]$segment.offsets.to)/2000.0}
        $window=0;while($window+1 -lt $edges.Count-1 -and $center -ge $edges[$window+1]){$window++}
        $buckets[$window].Add($segment)
        $previousWindow=$window
    }
    $words=New-Object System.Collections.Generic.List[object]
    $surfaces=New-Object System.Collections.Generic.List[object]
    $retries=New-Object System.Collections.Generic.List[object]
    $estimated=New-Object System.Collections.Generic.List[object]
    for($window=0;$window -lt $edges.Count-1;$window++){
        if(-not $buckets[$window].Count){continue}
        $start=$edges[$window];$end=$edges[$window+1];$length=$end-$start
        if(@($Quiet | Where-Object {$_.Start -le $start+0.000001 -and $_.End -ge $end-0.000001}).Count){continue}
        $reason='';$offset=0.0;$quality='dtw'
        $windowQuiet=@($Quiet | Where-Object {$_.End -ge $start -and $_.Start -le $end})
        try {
            $recognition=Convert-PvsDtwCaptionRecognition -Json ([pscustomobject]@{transcription=$buckets[$window].ToArray()}) -Quiet $windowQuiet -Duration $Duration -Chapter $Chapter
            if($recognition.Words.Count -and ($recognition.Words[0].Start -lt $start-0.000001 -or $recognition.Words[-1].End -gt $end+0.000001)){throw 'CAPTION_DTW_WINDOW_EDGE_INVALID'}
        } catch {
            if($_.Exception.Message -notmatch '^CAPTION_DTW_'){throw}
            $reason=$_.Exception.Message;$offset=$start
            $localQuiet=@($Quiet | Where-Object {$_.Start -ge $start -and $_.End -le $end} | ForEach-Object {[pscustomobject]@{Start=$_.Start-$start;End=$_.End-$start;Duration=$_.Duration}})
            $retryJson=& $RecognizeWindow $start $end $false
            try {
                $recognition=Convert-PvsDtwCaptionRecognition -Json $retryJson -Quiet $localQuiet -Duration $length -Chapter $Chapter
            } catch {
                if($_.Exception.Message -notmatch '^CAPTION_DTW_'){throw}
                $reason+='; retry: '+$_.Exception.Message
                $sentenceJson=& $RecognizeWindow $start $end $true
                $recognition=Convert-PvsReferenceRecognition -Json $sentenceJson -Chapter $Chapter -Duration $length -Mode Subtitle
                $quality='estimated'
                $estimated.Add([pscustomobject]@{chapter=$Chapter;start=$start;end=$end;reason=$reason})
            }
            $retries.Add([pscustomobject]@{chapter=$Chapter;start=$start;end=$end;reason=$reason;quality=$quality})
        }
        $firstWord=$words.Count
        foreach($word in $recognition.Words){
            $copy=$word.PSObject.Copy();$copy.Start+=$offset;$copy.End+=$offset
            foreach($name in @('DtwFirst','DtwLast','DtwBoundaryStart')){if($copy.PSObject.Properties[$name] -and $null -ne $copy.$name){$copy.$name+=$offset}}
            $copy | Add-Member -NotePropertyName SubtitleTimingQuality -NotePropertyValue $quality -Force
            $words.Add($copy)
        }
        foreach($surface in $recognition.Surfaces){
            $copy=$surface.PSObject.Copy();$copy.Start+=$offset;$copy.End+=$offset;$copy.FirstWord+=$firstWord;$copy.LastWord+=$firstWord
            $surfaces.Add($copy)
        }
    }
    $refined=Set-PvsSubtitleWordBoundaries -Words $words.ToArray() -Quiet $BoundaryQuiet -Energy $Energy
    # Surface times follow their words after the acoustic refinement.
    foreach($surface in $surfaces){$surface.Start=$words[$surface.FirstWord].Start;$surface.End=$words[$surface.LastWord].End}
    [pscustomobject]@{Words=$words.ToArray();Surfaces=$surfaces.ToArray();RetryRanges=$retries.ToArray();EstimatedRanges=$estimated.ToArray();AcousticBoundaryCount=$refined}
}

function Set-PvsSubtitleWordBoundaries {
    param([object[]]$Words,[object[]]$Quiet,$Energy=$null)
    $refined=0;$cursor=0
    for($i=1;$i -lt $Words.Count;$i++){
        $left=$Words[$i-1];$right=$Words[$i]
        if($left.SubtitleTimingQuality -ne 'dtw' -or $right.SubtitleTimingQuality -ne 'dtw' -or $left.Chapter -ne $right.Chapter){continue}
        while($cursor -lt $Quiet.Count -and $Quiet[$cursor].End -lt $left.DtwLast-0.08){$cursor++}
        # Keep independent speech edges across a measured breath. At a
        # continuous seam, the previous token's output is the useful anchor;
        # the next word's attention point can already be inside its vowel.
        if($null -ne $Energy -and $null -ne $right.DtwBoundaryStart){
            $pauses=@(for($j=$cursor;$j -lt $Quiet.Count -and $Quiet[$j].Start -le $right.DtwFirst+0.08;$j++){
                $q=$Quiet[$j]
                if($q.Duration -ge 0.12 -and $q.Start -ge $left.DtwLast-0.08 -and $q.End -le $right.DtwFirst+0.08 -and $q.Start -gt $left.Start -and $q.End -lt $right.End){$q}
            })
            if($pauses.Count -eq 1){$left.End=$pauses[0].Start;$right.Start=$pauses[0].End;$right.DtwBoundaryStart=$right.Start;continue}
            $anchor=[double]$right.DtwBoundaryStart
            $boundary=$Energy.FindBoundary($anchor,[double]$left.Start+0.025,[Math]::Min([double]$right.DtwFirst,[double]$right.End-0.025))
            if(-not [double]::IsNaN($boundary)){
                $left.End=$boundary;$right.Start=$boundary;$right.DtwBoundaryStart=$boundary;$refined++;continue
            }
            # An unmeasurable seam keeps its original evidence; never apply a
            # fixed global shift or manufacture a silence from the waveform.
        }
        $low=[double]$left.DtwLast-0.04;$high=[double]$right.DtwFirst+0.02
        while($cursor -lt $Quiet.Count -and $Quiet[$cursor].End -lt $low){$cursor++}
        $hits=@(for($j=$cursor;$j -lt $Quiet.Count -and $Quiet[$j].Start -le $high;$j++){
            $q=$Quiet[$j];$center=($q.Start+$q.End)/2.0
            if($q.Duration -ge 0.015 -and $q.Duration -le 0.35 -and $q.Start -ge $low -and $q.End -le $high -and $center -gt $left.Start -and $center -lt $right.End){$q}
        })
        if($hits.Count -ne 1){continue}
        $boundary=($hits[0].Start+$hits[0].End)/2.0
        $left.End=$boundary;$right.Start=$boundary;$right.DtwBoundaryStart=$boundary;$refined++
    }
    return $refined
}

function Test-PvsSubtitleDtwCue {
    param($Cue,[hashtable]$EstimatedWordSpans)
    if($Cue.PSObject.Properties['RecognitionSupplement'] -or $Cue.PSObject.Properties['WordTimingRecovered'] -or $Cue.PSObject.Properties['SubtitleReferencePartialMatch']){return $false}
    foreach($timing in $Cue.WordTimings){
        if($timing.PSObject.Properties['SubtitleTimingQuality'] -and $timing.SubtitleTimingQuality -ne 'dtw'){return $false}
        $key='{0}|{1:R}|{2:R}' -f [int]$timing.Chapter,[double]$timing.Start,[double]$timing.End
        if($EstimatedWordSpans.ContainsKey($key)){return $false}
    }
    return $true
}

function Test-PvsAcousticEditCue {
    param($Cue,$Voice,[double]$MinimumExactRatio=0.85)
    if($Cue.PSObject.Properties['EditBoundaryReviewRequired'] -and $Cue.EditBoundaryReviewRequired){return $false}
    if(-not $Cue.PSObject.Properties['CaptionTimingRevision'] -or $Cue.CaptionTimingRevision -ne 'dtw-word-boundary-v1' -or -not $Cue.PSObject.Properties['CaptionWordTimings']){return $false}
    if($Cue.PSObject.Properties['AcousticTimingQuality'] -and $Cue.AcousticTimingQuality -ne 'dtw'){return $false}
    $tokens=@(ConvertTo-NormalizedWords $Cue.Text);$timings=@($Cue.CaptionWordTimings)
    if(-not $tokens.Count -or $tokens.Count -ne $timings.Count){return $false}
    $previous=[double]$Voice.start;$exact=0
    for($i=0;$i -lt $timings.Count;$i++){
        $t=$timings[$i]
        if([int]$t.TargetWordIndex -ne $i -or [int]$t.Chapter -ne [int]$Cue.Chapter -or [string]$t.Text -cne $tokens[$i]){return $false}
        foreach($value in @([double]$t.Start,[double]$t.End)){if([double]::IsNaN($value) -or [double]::IsInfinity($value)){return $false}}
        if($t.Start -lt $previous-0.000001 -or $t.End -le $t.Start -or $t.End -gt [double]$Voice.end+0.000001){return $false}
        if($t.Exact){$exact++};$previous=[double]$t.End
    }
    return $timings[0].Exact -and $timings[-1].Exact -and $exact/[double]$tokens.Count -ge $MinimumExactRatio
}

function Set-PvsAcousticEditTimings {
    param([object[]]$Cues,[object[]]$Voices)
    $proposals=@{};$review=@{}
    for($i=0;$i -lt $Cues.Count;$i++){
        $cue=$Cues[$i];$chapter=[int]$cue.Chapter
        if($chapter -lt 0 -or $chapter -ge $Voices.Count -or -not (Test-PvsAcousticEditCue $cue $Voices[$chapter])){continue}
        $timings=@($cue.CaptionWordTimings)
        $proposals[$i]=[pscustomobject]@{Start=[double]$timings[0].Start;End=[double]$timings[-1].End;Timings=$timings}
    }
    # Do not move an unverified neighbor to accommodate a better cue. Reject
    # only conflicting proposals; the rest of the chapter can still improve.
    do {
        $blocked=@{}
        for($i=1;$i -lt $Cues.Count;$i++){
            if($Cues[$i].Chapter -ne $Cues[$i-1].Chapter){continue}
            $left=if($proposals.ContainsKey($i-1)){$proposals[$i-1].End}else{$Cues[$i-1].End}
            $right=if($proposals.ContainsKey($i)){$proposals[$i].Start}else{$Cues[$i].Start}
            if($null -eq $left -or $null -eq $right -or $right -ge $left-0.000001){continue}
            foreach($at in @(($i-1),$i)){if($proposals.ContainsKey($at)){$blocked[$at]=$true}}
        }
        foreach($at in $blocked.Keys){$proposals.Remove($at);$review[[int]$Cues[$at].Index]=$true}
    } while($blocked.Count)
    $voiceRanges=New-Object System.Collections.Generic.List[object]
    foreach($chapter in @($Cues.Chapter | Where-Object {$_ -ge 0 -and $_ -lt $Voices.Count} | Select-Object -Unique)){
        $starts=New-Object System.Collections.Generic.List[double];$ends=New-Object System.Collections.Generic.List[double]
        for($i=0;$i -lt $Cues.Count;$i++){
            if([int]$Cues[$i].Chapter -ne [int]$chapter){continue}
            if($null -ne $Cues[$i].Start){$starts.Add([double]$Cues[$i].Start)}
            if($null -ne $Cues[$i].End){$ends.Add([double]$Cues[$i].End)}
            if($proposals.ContainsKey($i)){$starts.Add($proposals[$i].Start);$ends.Add($proposals[$i].End)}
        }
        if($starts.Count -and $ends.Count){$voiceRanges.Add([pscustomobject]@{chapter=[int]$chapter;start=[Math]::Max([double]$Voices[$chapter].start,($starts | Measure-Object -Minimum).Minimum);end=[Math]::Min([double]$Voices[$chapter].end,($ends | Measure-Object -Maximum).Maximum)})}
    }
    $changes=New-Object System.Collections.Generic.List[object]
    foreach($at in @($proposals.Keys | Sort-Object)){
        $cue=$Cues[$at];$p=$proposals[$at]
        $changes.Add([pscustomobject]@{cueIndex=[int]$cue.Index;chapter=[int]$cue.Chapter;oldStart=$cue.Start;oldEnd=$cue.End;start=$p.Start;end=$p.End})
        $cue.Start=$p.Start;$cue.End=$p.End
        $cue.WordTimings=@($p.Timings | ForEach-Object {$_.PSObject.Copy()})
        $cue.Confidence=@($p.Timings | Where-Object Exact).Count/[double]$p.Timings.Count
        $cue | Add-Member -NotePropertyName EditTimingRevision -NotePropertyValue 'waveform-valley-v1' -Force
    }
    [pscustomobject]@{RefinedCues=@($changes | ForEach-Object {$_.cueIndex});Changes=$changes.ToArray();ReviewCues=@($review.Keys | Sort-Object);VoiceRanges=$voiceRanges.ToArray()}
}
