Set-StrictMode -Version Latest

. "$PSScriptRoot\ReferenceAlignment.ps1"



function ConvertTo-PvsSpokenInteger {
    param([long]$Value)
    if($Value -lt 0 -or $Value -gt 999999999999){throw 'CAPTION_NUMBER_OUT_OF_RANGE'}
    $digits=@('không','một','hai','ba','bốn','năm','sáu','bảy','tám','chín')
    if($Value -eq 0){return $digits[0]}
    $readGroup={param([int]$n,[bool]$force)
        $parts=New-Object System.Collections.Generic.List[string]
        $hundreds=[int][Math]::Floor($n/100);$tens=[int][Math]::Floor(($n%100)/10);$ones=$n%10
        if($hundreds -gt 0 -or $force){$parts.Add($digits[$hundreds]);$parts.Add('trăm')}
        if($tens -gt 1){$parts.Add($digits[$tens]);$parts.Add('mươi')}elseif($tens -eq 1){$parts.Add('mười')}elseif(($hundreds -gt 0 -or $force) -and $ones -gt 0){$parts.Add('linh')}
        if($ones -gt 0){$parts.Add($(if($ones -eq 5 -and $tens -gt 0){'lăm'}elseif($ones -eq 1 -and $tens -gt 1){'mốt'}else{$digits[$ones]}))}
        $parts.ToArray() -join ' '
    }
    $output=New-Object System.Collections.Generic.List[string]
    foreach($group in @(@(1000000000,'tỷ'),@(1000000,'triệu'),@(1000,'nghìn'),@(1,''))){
        $n=[int][Math]::Floor($Value/[double]$group[0]);$Value=$Value%[long]$group[0]
        if($n -eq 0){continue}
        $output.Add((& $readGroup $n ($output.Count -gt 0 -and $n -lt 100)))
        if($group[1]){$output.Add([string]$group[1])}
    }
    return $output.ToArray() -join ' '
}

function Get-PvsNumericCaptionPrompt {
    param([string]$Text)
    # Only prompt normalization: caption text itself is never rewritten. Keep
    # ambiguous separators/leading zeros and alphanumeric identifiers intact.
    return [regex]::Replace(($Text -replace '\s+',' '),'(?<![\p{L}\p{N}.,/:])(?:0|[1-9]\d{0,11})(?:[.,]\d{1,2})?%?(?![\p{L}\p{N}]|[.,/:]\d)',{
        param($match)
        $value=$match.Value;$percent=$value.EndsWith('%');$value=$value.TrimEnd('%')
        $parts=$value -split '[.,]';$spoken=ConvertTo-PvsSpokenInteger ([long]$parts[0])
        if($parts.Count -eq 2){$spoken+=' phẩy '+(@($parts[1].ToCharArray() | ForEach-Object {ConvertTo-PvsSpokenInteger ([int]::Parse([string]$_))}) -join ' ')}
        if($percent){$spoken+=' phần trăm'}
        $spoken
    })
}

function Join-PvsRecognizedNumericWords {
    param([string[]]$TargetWords,[object[]]$Words)
    $output=New-Object System.Collections.Generic.List[object]
    foreach($word in $Words){$output.Add($word)}
    for($t=0;$t -lt $TargetWords.Count;$t++){
        $target=$TargetWords[$t]
        if($target -notmatch '^(0|[1-9]\d{0,11})$'){continue}
        $spoken=ConvertTo-PvsSpokenInteger ([long]$target)
        $variants=@($spoken,($spoken -replace 'nghìn','ngàn' -replace 'linh','lẻ'),(@($target.ToCharArray() | ForEach-Object {ConvertTo-PvsSpokenInteger ([int]::Parse([string]$_))}) -join ' ')) | Select-Object -Unique
        $hits=New-Object System.Collections.Generic.List[object]
        for($i=0;$i -lt $output.Count;$i++){
            for($length=1;$length -le [Math]::Min(18,$output.Count-$i);$length++){
                $tokens=@($output.GetRange($i,$length).ToArray().Text)
                $digitsMatch=@($tokens | Where-Object {$_ -notmatch '^\d+$'}).Count -eq 0 -and ($tokens -join '') -eq $target
                if($length -gt 1 -and @($output.GetRange($i,$length).ToArray() | Where-Object {$_.PSObject.Properties['NumericSurfaceText'] -and $_.NumericSurfaceText -match '\d[.,]\d{1,2}$'}).Count){$digitsMatch=$false}
                $matches=($tokens -join ' ') -in $variants -or $digitsMatch
                if(-not $matches){continue}
                $left=$t -eq 0 -or ($i -gt 0 -and $output[$i-1].Text -eq $TargetWords[$t-1])
                $right=$t -eq $TargetWords.Count-1 -or ($i+$length -lt $output.Count -and $output[$i+$length].Text -eq $TargetWords[$t+1])
                if($left -and $right){$hits.Add([pscustomobject]@{Start=$i;Length=$length})}
            }
        }
        # Ambiguous repeats or missing context keep the original evidence.
        if($hits.Count -ne 1){continue}
        $hit=$hits[0];$first=$output[$hit.Start];$last=$output[$hit.Start+$hit.Length-1]
        $ordered=$true
        for($i=$hit.Start;$i -lt $hit.Start+$hit.Length;$i++){
            if($output[$i].End -le $output[$i].Start -or ($i -gt $hit.Start -and $output[$i].Start -lt $output[$i-1].End-0.000001)){$ordered=$false;break}
        }
        if(-not $ordered){continue}
        $merged=$first.PSObject.Copy();$merged.Text=$target;$merged.Start=[double]$first.Start;$merged.End=[double]$last.End
        if($merged.PSObject.Properties['DtwLast'] -and $last.PSObject.Properties['DtwLast']){$merged.DtwLast=$last.DtwLast}
        $members=@($output.GetRange($hit.Start,$hit.Length).ToArray())
        if(@($members | Where-Object {$_.PSObject.Properties['SubtitleTimingQuality'] -and $_.SubtitleTimingQuality -ne 'dtw'}).Count){$merged | Add-Member -NotePropertyName SubtitleTimingQuality -NotePropertyValue 'estimated' -Force}
        $output.RemoveRange($hit.Start,$hit.Length);$output.Insert($hit.Start,$merged)
    }
    return $output.ToArray()
}

function Repair-PvsNumericCaptionTimings {
    param([object[]]$Cues,[object[]]$VoiceClips,[scriptblock]$RecognizeWindow,[string]$Language='vi')
    $refined=New-Object System.Collections.Generic.List[int]
    $review=New-Object System.Collections.Generic.List[int]
    if($Language -ne 'vi'){return [pscustomobject]@{Refined=@();Review=@()}}
    foreach($cue in $Cues){
        if([string]$cue.Text -notmatch '\d'){continue}
        if($null -eq $cue.Start -or $null -eq $cue.End -or [int]$cue.Chapter -lt 0 -or [int]$cue.Chapter -ge $VoiceClips.Count){$review.Add([int]$cue.Index);continue}
        $voice=$VoiceClips[[int]$cue.Chapter];$start=[Math]::Max([double]$voice.start,[double]$cue.Start-0.2);$end=[Math]::Min([double]$voice.end,[double]$cue.End+0.6)
        $targets=@(ConvertTo-NormalizedWords ([string]$cue.Text))
        if($end-$start -gt 25 -or $end-$start -lt 0.2 -or $targets.Count -gt 160){$review.Add([int]$cue.Index);continue}
        $prompt=Get-PvsNumericCaptionPrompt ([string]$cue.Text)
        Write-Verbose "NUMERIC_CAPTION_WINDOW:cue-$($cue.Index);start=$start;end=$end"
        $words=@(& $RecognizeWindow $voice $start $end $prompt)
        if($words.Count -eq 0){$review.Add([int]$cue.Index);continue}
        $words=@(Join-PvsRecognizedNumericWords -TargetWords $targets -Words $words)
        $mapping=@(Get-SequentialWordMapping -TargetWords $targets -RecognizedWords $words)
        $timings=New-Object System.Collections.Generic.List[object];$valid=$true;$exact=0;$lastEnd=$start
        for($i=0;$i -lt $targets.Count;$i++){
            if($mapping[$i] -lt 0){$valid=$false;break}
            $word=$words[$mapping[$i]];$wordStart=$start+[double]$word.Start;$wordEnd=$start+[double]$word.End;$same=$targets[$i] -eq [string]$word.Text
            if($wordStart -lt $lastEnd-0.000001 -or $wordEnd -gt $end+0.000001 -or $wordEnd -le $wordStart -or ($targets[$i] -match '\d' -and -not $same)){$valid=$false;break}
            if($same){$exact++}
            $timing=[pscustomobject]@{TargetWordIndex=$i;Text=$targets[$i];Start=$wordStart;End=$wordEnd;Chapter=[int]$cue.Chapter;Exact=$same}
            foreach($name in @('SubtitleTimingQuality','SubtitleTimingOrigin')){if($word.PSObject.Properties[$name]){$timing | Add-Member -NotePropertyName $name -NotePropertyValue $word.$name}}
            $timings.Add($timing)
            $lastEnd=$wordEnd
        }
        if(-not $valid -or $exact/[double][Math]::Max(1,$targets.Count) -lt 0.85){$review.Add([int]$cue.Index);Write-Verbose "NUMERIC_CAPTION_UNVERIFIED:cue-$($cue.Index);valid=$valid;exact=$exact/$($targets.Count);heard=$($words.Text -join ' ')";continue}
        $anchor=[Math]::Min(3,$timings.Count)
        if(@($timings.ToArray()[0..($anchor-1)] | Where-Object {$_.Exact}).Count -lt [Math]::Ceiling($anchor*0.66) -or @($timings.ToArray()[($timings.Count-$anchor)..($timings.Count-1)] | Where-Object {$_.Exact}).Count -lt [Math]::Ceiling($anchor*0.66)){$review.Add([int]$cue.Index);continue}
        $captionStart=[Math]::Max([double]$cue.Start,[double]$timings[0].Start)
        $captionEnd=[Math]::Min([double]$cue.End,[double]$timings[$timings.Count-1].End)
        if($captionEnd -le $captionStart){$review.Add([int]$cue.Index);continue}
        # Separate caption-only timing fields: edit cue bounds, word mapping,
        # grouping, razor points and video/audio retiming remain untouched.
        $cue | Add-Member -NotePropertyName CaptionWordTimings -NotePropertyValue $timings.ToArray() -Force
        $cue | Add-Member -NotePropertyName CaptionStart -NotePropertyValue $captionStart -Force
        $cue | Add-Member -NotePropertyName CaptionEnd -NotePropertyValue $captionEnd -Force
        $refined.Add([int]$cue.Index)
    }
    return [pscustomobject]@{Refined=$refined.ToArray();Review=$review.ToArray()}
}
