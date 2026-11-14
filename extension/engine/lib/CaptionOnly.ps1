Set-StrictMode -Version Latest

# Subtitle scope/output policy over the shared reference-alignment core.
function Test-PvsRecognitionReviewError {
    param([string]$Message)
    return $Message -match '^(EDIT_RECOGNITION_TIMESTAMP_INVALID|EDITED_REFERENCE_RETRY_TIMING_INVALID|SUBTITLE_RECOGNITION_TIMESTAMP_MISSING|SUBTITLE_REFERENCE_RETRY_TIMING_INVALID|SUBTITLE_REFERENCE_WORD_UNALIGNED|SUBTITLE_REFERENCE_TIMING_INVALID|SUBTITLE_REFERENCE_CROSSES_SELECTION_GAP|SUBTITLE_REFERENCE_MISMATCH|SUBTITLE_RECOGNITION_TAIL_UNVERIFIED|SUBTITLE_EDGE_RETRY_INVALID)(:|$)'
}
. "$PSScriptRoot\ReferenceAlignment.ps1"
. "$PSScriptRoot\CaptionTiming.ps1"

function Get-PvsSubtitleLexicalWords {
    param([string]$Text,[bool]$CharacterMode=$false)
    return @(Get-PvsReferenceLexicalWords $Text $CharacterMode)
}

function Convert-PvsSubtitleRecognition {
    param([Parameter(Mandatory)]$Json,[int]$Chapter,[double]$Duration,[bool]$CharacterMode=$false)
    return Convert-PvsReferenceRecognition -Json $Json -Chapter $Chapter -Duration $Duration -Mode Subtitle -CharacterMode $CharacterMode
}

function New-PvsRecognizedSubtitleCues {
    param([object[]]$Surfaces, [object[]]$Words, [double]$Offset, [int]$Chapter, [bool]$CharacterMode = $false)
    $cues = New-Object System.Collections.Generic.List[object]
    $pieces = New-Object System.Collections.Generic.List[string]
    $timings = New-Object System.Collections.Generic.List[object]
    $cueStart = 0.0; $cueEnd = 0.0
    for ($index=0; $index -lt $Surfaces.Count; $index++) {
        $surface=$Surfaces[$index]
        if ($pieces.Count -eq 0) { $cueStart=[double]$surface.Start }
        $pieces.Add([string]$surface.Text)
        for ($wordIndex=[int]$surface.FirstWord; $wordIndex -le [int]$surface.LastWord; $wordIndex++) {
            $word=$Words[$wordIndex]
            $timing=[pscustomobject]@{ TargetWordIndex=$timings.Count; Text=$word.Text; Start=$Offset+[double]$word.Start; End=$Offset+[double]$word.End; Chapter=$Chapter; Exact=$true }
            foreach($name in @('SubtitleTimingQuality','SubtitleTimingOrigin','NumericSurfaceText')){if($word.PSObject.Properties[$name]){$timing | Add-Member -NotePropertyName $name -NotePropertyValue $word.$name}}
            $timings.Add($timing)
        }
        $cueEnd=[double]$surface.End
        $nextGap=if ($index+1 -lt $Surfaces.Count) { [double]$Surfaces[$index+1].Start-$cueEnd } else { 0.0 }
        $surfaceTokens=@([regex]::Matches([string]$surface.Text,'\S+') | ForEach-Object {$_.Value})
        $nextTokens=@(if($index+1 -lt $Surfaces.Count){[regex]::Matches([string]$Surfaces[$index+1].Text,'\S+') | ForEach-Object {$_.Value}})
        $initialContinuation=$surfaceTokens.Count -gt 0 -and $nextTokens.Count -gt 0 -and (Test-PvsCaptionInitialContinuation $surfaceTokens[-1] $nextTokens[0])
        if ($index -eq $Surfaces.Count-1 -or (-not $initialContinuation -and ([string]$surface.Text -match '[.!?;。！？；]$' -or $nextGap -ge 0.7 -or $cueEnd-$cueStart -ge 12.0))) {
            $joined = if ($CharacterMode) {
                $mixedText=''
                foreach ($piece in $pieces) {
                    if ($mixedText -match '[A-Za-z0-9]$' -and $piece -match '^[A-Za-z0-9]') { $mixedText+=' ' }
                    $mixedText+=$piece
                }
                $mixedText
            } else { $pieces.ToArray() -join ' ' }
            # 1 here describes self-mapping only, never acoustic certainty.
            $cues.Add([pscustomobject]@{ Index=$cues.Count+1; Text=$joined; Start=$Offset+$cueStart; End=$Offset+$cueEnd; Chapter=$Chapter; Confidence=1.0; ConfidenceKind='recognition-self-mapping'; WordTimings=$timings.ToArray() })
            $pieces.Clear(); $timings.Clear()
        }
    }
    return $cues.ToArray()
}

function Test-PvsVietnameseRecognitionVariant {
    param([string]$Expected,[string]$Recognized)
    if ($Expected -eq $Recognized) { return $true }
    # An isolated letter B is a common ASR spelling of the spoken "Be"/"Bê".
    if (($Expected -in @('be','bê') -and $Recognized -eq 'b') -or ($Recognized -in @('be','bê') -and $Expected -eq 'b')) { return $true }
    $plainExpected=[regex]::Replace($Expected.Normalize([Text.NormalizationForm]::FormD),'\p{Mn}','').Replace('đ','d')
    $plainRecognized=[regex]::Replace($Recognized.Normalize([Text.NormalizationForm]::FormD),'\p{Mn}','').Replace('đ','d')
    return $plainExpected -eq $plainRecognized
}

function Test-PvsSubtitleReferenceAnchor {
    param($Cue)
    $count=@(ConvertTo-NormalizedWords ([string]$Cue.Text)).Count
    return $null -ne $Cue.Start -and [double]$Cue.Confidence -ge 0.8 -and @($Cue.WordTimings).Count/[double][Math]::Max(1,$count) -ge 0.8 -and @($Cue.WordTimings | Select-Object -ExpandProperty Chapter -Unique).Count -eq 1
}

function Get-PvsSubtitleNumericSpan {
    param([string[]]$Tokens,[switch]$RequireDigits)
    $runs=New-Object System.Collections.Generic.List[object]
    $number='^(?:\d+|không|một|mốt|hai|ba|bốn|tư|năm|lăm|sáu|bảy|tám|chín|mười|mươi|trăm|nghìn|ngàn|triệu|tỷ|tỉ|linh|lẻ|phẩy)$'
    for($i=0;$i -lt $Tokens.Count;$i++){
        if($Tokens[$i] -notmatch $number){continue}
        $first=$i
        while($i+1 -lt $Tokens.Count){
            if($Tokens[$i+1] -match $number){$i++;continue}
            # A range/fraction is one numeric field for sentence identity.
            # The connector must occur directly between two numeric tokens.
            if($Tokens[$i+1] -in @('đến','phần') -and $i+2 -lt $Tokens.Count -and $Tokens[$i+2] -match $number){$i+=2;continue}
            break
        }
        $part=@($Tokens[$first..$i]);$hasDigits=@($part | Where-Object {$_ -match '^\d+$'}).Count -gt 0
        if($RequireDigits -and -not $hasDigits){continue}
        $runs.Add([pscustomobject]@{First=$first;Last=$i;Tokens=$part;Text=($part -join ' ')})
    }
    if($runs.Count -eq 1){return $runs[0]}
    return $null
}

function Get-PvsSubtitleNumberKey {
    param([string[]]$Tokens)
    $text=($Tokens -join ' ') -replace 'ngàn','nghìn' -replace 'tỉ','tỷ' -replace 'lẻ','linh'
    # Grouped thousands and unambiguous spoken decimal notation are formatting.
    # Malformed mixed grouping (e.g. 9,46.000) stays different, for review.
    $text=[regex]::Replace($text,'\b\d{1,3}(?: \d{3})+\b',{param($m);$m.Value.Replace(' ','')})
    $text=[regex]::Replace($text,'\b(\d+) phẩy (\d{1,2})\b','$1,$2')
    if($null -ne (Get-Command Get-PvsNumericCaptionPrompt -ErrorAction SilentlyContinue)){$text=Get-PvsNumericCaptionPrompt $text}
    return (@(ConvertTo-NormalizedWords $text) -join ' ')
}

function Expand-PvsSubtitleUnitWords {
    param([object[]]$Words)
    # Read-only lexical view. A compact ASR unit is not several measured words.
    $units=@{km='kilomet';km2='kilomet vuông';'km²'='kilomet vuông';m='met';m2='met vuông';'m²'='met vuông'}
    for($i=0;$i -lt $Words.Count;$i++){
        $text=[string]$Words[$i].Text;$tokens=@($text)
        if($text -match '^(\d*)(km2|km²|km|m2|m²|m)$'){
            $number=$Matches[1];$unit=$Matches[2]
            $tokens=@(if($number){$number})+@($units[$unit] -split ' ')
        }
        foreach($token in $tokens){
            $copy=$Words[$i].PSObject.Copy();$copy.Text=$token
            $copy | Add-Member NoteProperty UnitSourceWordIndex $i -Force
            $copy | Add-Member NoteProperty UnitExpanded ($tokens.Count -gt 1) -Force
            $copy
        }
    }
}

function New-PvsSubtitleUnitReferenceProjection {
    param($Reference,[object[]]$Heard,[object[]]$ValidationWords,[object[]]$Sources,[int]$Chapter)
    if([string]$Reference.Text -notmatch '\d' -or $Chapter -lt 0 -or $Chapter -ge $Sources.Count -or -not $Heard.Count -or $Heard.Count -gt 400){return $null}
    $layout=New-PvsReferenceWordLayout @($Reference)
    if($layout.Words.Count -lt 3 -or $layout.Words.Count -gt 200){return $null}
    $view=@(Expand-PvsSubtitleUnitWords $Heard)
    if(-not @($view|Where-Object UnitExpanded).Count){return $null}
    $fold={param([string]$value);[regex]::Replace($value.Normalize([Text.NormalizationForm]::FormD),'\p{Mn}','').Replace('đ','d')}
    $target=@($layout.Words|ForEach-Object {& $fold $_})
    $aliases=@($view|ForEach-Object {$copy=$_.PSObject.Copy();$copy.Text=& $fold ([string]$copy.Text);$copy})
    $mapping=@(Get-SequentialWordMapping $target $aliases)
    # Several lexical components may refer to one raw ASR span. Keep only its
    # last target anchor, never duplicate/split that span into fake word timing.
    $seen=@{};$expanded=@{}
    for($i=$mapping.Count-1;$i -ge 0;$i--){
        if($mapping[$i] -lt 0){continue}
        $word=$view[$mapping[$i]];$raw=[int]$word.UnitSourceWordIndex
        if($seen.ContainsKey($raw)){$mapping[$i]=-1;continue}
        $seen[$raw]=$true;$mapping[$i]=$raw
        if($word.UnitExpanded){$expanded[$i]=$true}
    }
    $cue=@(Convert-PvsReferenceMappingToCues @($Reference) $layout $mapping $Heard $Sources -PreserveReferenceIndices -FixedChapter $Chapter)[0]
    $cue | Add-Member NoteProperty SubtitleUnitProjection $true
    foreach($timing in $cue.WordTimings){
        if($expanded.ContainsKey([int]$timing.TargetWordIndex)){$timing | Add-Member NoteProperty SubtitleTimingQuality 'estimated' -Force}
    }
    if(-not (Test-PvsReferenceCueTiming $cue $Sources[$Chapter].start $Sources[$Chapter].end $Chapter)){return $null}
    # Verify the complete surrounding sentence AND unit dimension using the
    # original recognition. General fuzzy identity must not bypass this check.
    if(-not (Test-PvsSubtitleNumberReferenceIdentity $cue $ValidationWords $Sources)){return $null}
    return $cue
}

function Test-PvsSubtitleNumberReferenceIdentity {
    param($Cue,[object[]]$Words,[object[]]$Sources)
    if([string]$Cue.Text -notmatch '\d'){return $false}
    $chapter=[int]$Cue.Chapter
    if($chapter -lt 0 -or $chapter -ge $Sources.Count -or $null -eq $Cue.Start -or $null -eq $Cue.End){return $false}
    $target=@(ConvertTo-NormalizedWords $Cue.Text)
    $heard=@($Words | Where-Object {[int]$_.Chapter -eq $chapter -and [double]$Sources[$chapter].start+[double]$_.Start -ge [double]$Cue.Start-0.000001 -and [double]$Sources[$chapter].start+[double]$_.End -le [double]$Cue.End+0.000001} | Sort-Object Start)
    if($Cue.PSObject.Properties['SubtitleUnitProjection'] -and $Cue.SubtitleUnitProjection){$heard=@(Expand-PvsSubtitleUnitWords $heard)}
    $expected=Get-PvsSubtitleNumericSpan $target -RequireDigits
    $actual=Get-PvsSubtitleNumericSpan @($heard.Text)
    if($null -eq $expected -or $null -eq $actual){return $false}
    $left=@($target | Select-Object -First $expected.First);$right=@($target | Select-Object -Skip ($expected.Last+1))
    $heardLeft=@($heard | Select-Object -First $actual.First | ForEach-Object {$_.Text});$heardRight=@($heard | Select-Object -Skip ($actual.Last+1) | ForEach-Object {$_.Text})
    # Identify the surrounding sentence independently of the number's value.
    # A value disagreement preserves SRT and creates a content comparison.
    $strong=0;$total=$left.Count+$right.Count;$weight=0.0
    if($total -lt 3 -or $left.Count -ne $heardLeft.Count -or $right.Count -ne $heardRight.Count){return $false}
    $expectedContext=@($left)+@($right);$heardContext=@($heardLeft)+@($heardRight)
    $units=@{km='kilomet';kilômét='kilomet';kilômétre='kilomet';kilometer='kilomet';m='met';mét='met';met='met'}
    for($i=0;$i -lt $total;$i++){
        $a=[string]$expectedContext[$i];$b=[string]$heardContext[$i]
        if($units.ContainsKey($a)){$a=$units[$a]};if($units.ContainsKey($b)){$b=$units[$b]}
        if($Cue.PSObject.Properties['SubtitleUnitProjection'] -and $Cue.SubtitleUnitProjection -and ($a -in @('kilomet','met','vuông') -or $b -in @('kilomet','met','vuông')) -and $a -cne $b){return $false}
        $w=Get-PvsSubtitleWordIdentityWeight $a $b
        $weight+=$w;if($w -eq 1.0){$strong++}
    }
    if($strong -lt 3 -or $weight/$total -lt 0.75){return $false}
    $actualTokens=New-Object System.Collections.Generic.List[string];$previousSurface=''
    for($i=$actual.First;$i -le $actual.Last;$i++){
        $word=$heard[$i];$surface=if($word.PSObject.Properties['NumericSurfaceText']){[string]$word.NumericSurfaceText}else{''}
        if($surface){if($surface -cne $previousSurface){$actualTokens.Add($surface)}}else{$actualTokens.Add([string]$word.Text)}
        $previousSurface=$surface
    }
    $different=(Get-PvsSubtitleNumberKey $expected.Tokens) -cne (Get-PvsSubtitleNumberKey $actualTokens.ToArray())
    $Cue | Add-Member -NotePropertyName SubtitleReferenceNumberMatch -NotePropertyValue $true -Force
    $Cue | Add-Member -NotePropertyName ReferenceNumberReviewRequired -NotePropertyValue $different -Force
    $Cue | Add-Member -NotePropertyName ReferenceNumberExpected -NotePropertyValue $expected.Text -Force
    $Cue | Add-Member -NotePropertyName ReferenceNumberRecognized -NotePropertyValue ($actualTokens.ToArray() -join ' ') -Force
    return $true
}

function Test-PvsSubtitlePartialReferenceCue {
    param($Cue,[object[]]$Words,[object[]]$Sources)
    # Subtitle text policy only. This must never authorize picture deletion.
    $chapter=[int]$Cue.Chapter
    if($chapter -lt 0 -or $chapter -ge $Sources.Count){return $false}
    if(-not (Test-PvsReferenceCueTiming $Cue $Sources[$chapter].start $Sources[$chapter].end $chapter)){return $false}
    if(Test-PvsSubtitleNumberReferenceIdentity $Cue $Words $Sources){return $true}
    $tokens=@(ConvertTo-NormalizedWords $Cue.Text);$timings=@($Cue.WordTimings)
    if($tokens.Count -lt 5 -or $tokens.Count -gt 200){return $false}
    $byIndex=@{};$spans=@{};$exact=0;$equivalent=@{}
    foreach($t in $timings){
        $index=[int]$t.TargetWordIndex
        if($index -lt 0 -or $index -ge $tokens.Count -or $byIndex.ContainsKey($index)){return $false}
        $byIndex[$index]=$t
        $key='{0:R}|{1:R}' -f [double]$t.Start,[double]$t.End
        if($spans.ContainsKey($key)){return $false};$spans[$key]=$t
        if($t.Exact){$exact++;$equivalent[$index]=$true}
    }
    # Both sentence edges must be observed; never restore a missing prefix/suffix.
    if(-not $byIndex.ContainsKey(0) -or -not $byIndex.ContainsKey($tokens.Count-1)){return $false}
    # Every heard word inside the sentence must be accounted for. Additional
    # speech cannot be hidden by accepting a mostly matching reference.
    $heard=@($Words | Where-Object {[int]$_.Chapter -eq $chapter -and [double]$Sources[$chapter].start+[double]$_.Start -lt $Cue.End-0.000001 -and [double]$Sources[$chapter].start+[double]$_.End -gt $Cue.Start+0.000001})
    if($heard.Count -ne $timings.Count){return $false}
    $seen=@{}
    foreach($word in $heard){
        $key='{0:R}|{1:R}' -f ([double]$Sources[$chapter].start+[double]$word.Start),([double]$Sources[$chapter].start+[double]$word.End)
        if(-not $spans.ContainsKey($key) -or $seen.ContainsKey($key)){return $false};$seen[$key]=$true
        $t=$spans[$key]
        if([bool]$t.Exact -ne ([string]$word.Text -ceq $tokens[[int]$t.TargetWordIndex])){return $false}
        $index=[int]$t.TargetWordIndex
        $levels=@{i='1';ii='2';iii='3';iv='4';v='5'}
        if(-not $t.Exact -and $index -ge 2 -and $tokens[$index-2] -eq 'cấp' -and $tokens[$index-1] -eq 'độ' -and $levels.ContainsKey($tokens[$index]) -and $levels[$tokens[$index]] -ceq [string]$word.Text){$equivalent[$index]=$true;$exact++}
    }
    $decimalConnectors=@{}
    for($i=1;$i -lt $tokens.Count-1;$i++){
        if($tokens[$i] -ne 'phẩy' -or $byIndex.ContainsKey($i) -or -not $byIndex.ContainsKey($i-1) -or -not $byIndex.ContainsKey($i+1)){continue}
        $left=$byIndex[$i-1];$right=$byIndex[$i+1]
        if($tokens[$i-1] -notmatch '^\d+$' -or $tokens[$i+1] -notmatch '^\d{1,2}$' -or -not $left.Exact -or -not $right.Exact){continue}
        $expected=$tokens[$i-1]+','+$tokens[$i+1]
        if($left.PSObject.Properties['NumericSurfaceText'] -and $right.PSObject.Properties['NumericSurfaceText'] -and $left.NumericSurfaceText.Replace('.',',') -ceq $expected -and $right.NumericSurfaceText.Replace('.',',') -ceq $expected){$decimalConnectors[$i]=$true;$exact++}
    }
    if(-not $equivalent.ContainsKey(0) -or -not $equivalent.ContainsKey($tokens.Count-1) -or $tokens.Count-$exact -gt 2 -or $exact/[double]$tokens.Count -lt 0.8){return $false}
    if($exact -eq $tokens.Count -and $timings.Count -eq $tokens.Count -and @($timings | Where-Object {-not $_.Exact}).Count -eq 0){return $false}
    for($index=0;$index -lt $tokens.Count;$index++){
        if($byIndex.ContainsKey($index) -or $decimalConnectors.ContainsKey($index)){continue}
        $first=$index
        while(-not $byIndex.ContainsKey($index)){$index++}
        # A compressed join with no room for the missing words is evidence
        # against restoration. This is a guard, not measured word timing.
        if([double]$byIndex[$index].Start-[double]$byIndex[$first-1].End -lt 0.06*($index-$first)){return $false}
    }
    if($exact -eq $tokens.Count -and $timings.Count -eq $tokens.Count){$Cue | Add-Member -NotePropertyName SubtitleReferenceFormatOnly -NotePropertyValue $true -Force}
    return $true
}

function Get-PvsSubtitleWordIdentityWeight {
    param([string]$Expected,[string]$Recognized,[double]$MinimumSimilarity=0.6)
    if($Expected -ceq $Recognized){return 1.0}
    $a=[regex]::Replace($Expected.Normalize([Text.NormalizationForm]::FormD),'\p{Mn}','').Replace('đ','d')
    $b=[regex]::Replace($Recognized.Normalize([Text.NormalizationForm]::FormD),'\p{Mn}','').Replace('đ','d')
    if($a -ceq $b){return 1.0}
    # Local spelling similarity contributes evidence of sentence identity;
    # it never rewrites the SRT, recognizes a number or verifies word timing.
    if($a -match '\d' -or $b -match '\d' -or [Math]::Min($a.Length,$b.Length) -lt 3 -or [Math]::Max($a.Length,$b.Length) -gt 40){return 0.0}
    $previous=New-Object 'int[]' ($b.Length+1)
    for($j=0;$j -le $b.Length;$j++){$previous[$j]=$j}
    for($i=1;$i -le $a.Length;$i++){
        $current=New-Object 'int[]' ($b.Length+1);$current[0]=$i
        for($j=1;$j -le $b.Length;$j++){
            $cost=if($a[$i-1] -ceq $b[$j-1]){0}else{1}
            $current[$j]=[Math]::Min($previous[$j]+1,[Math]::Min($current[$j-1]+1,$previous[$j-1]+$cost))
        }
        $previous=$current
    }
    if(1.0-$previous[$b.Length]/[double][Math]::Max($a.Length,$b.Length) -ge $MinimumSimilarity){return 0.75}
    return 0.0
}

function Convert-PvsSubtitleReferenceProjection {
    param([object[]]$Cues,$Layout,[object[]]$Heard,[object[]]$ValidationWords,[object[]]$Sources,[int]$Chapter,[string]$Language='vi')
    $mapping=@(Get-SequentialWordMapping $Layout.Words $Heard)
    $mapped=@(Convert-PvsReferenceMappingToCues $Cues $Layout $mapping $Heard $Sources -PreserveReferenceIndices -FixedChapter $Chapter)
    $alternative=$null
    foreach($cue in $mapped){
        if($Language -eq 'vi' -and -not ((Test-PvsSubtitlePartialReferenceCue $cue $ValidationWords $Sources) -or (Test-PvsSubtitleReferenceIdentity $cue $ValidationWords $Sources))){
            if($null -eq $alternative){
                # Align accent variants and unit spellings already accepted by
                # subtitle identity. Keep the original words/timestamps for all
                # acceptance checks; these aliases are never recognition proof.
                $fold={param([string]$token)
                    $value=[regex]::Replace($token.Normalize([Text.NormalizationForm]::FormD),'\p{Mn}','').Replace('đ','d')
                    if($value -eq 'm'){$value='met'}
                    $value
                }
                $target=@($Layout.Words | ForEach-Object {& $fold $_})
                $aliases=@($Heard | ForEach-Object {$copy=$_.PSObject.Copy();$copy.Text=& $fold ([string]$copy.Text);$copy})
                $alternativeMapping=@(Get-SequentialWordMapping $target $aliases)
                $alternative=@(Convert-PvsReferenceMappingToCues $Cues $Layout $alternativeMapping $Heard $Sources -PreserveReferenceIndices -FixedChapter $Chapter)
            }
            $candidate=@($alternative | Where-Object Index -eq $cue.Index)[0]
            if((Test-PvsSubtitlePartialReferenceCue $candidate $ValidationWords $Sources) -or (Test-PvsSubtitleReferenceIdentity $candidate $ValidationWords $Sources)){$cue=$candidate}
            else{
                $reference=@($Cues|Where-Object Index -eq $cue.Index)[0]
                $unit=New-PvsSubtitleUnitReferenceProjection $reference $Heard $ValidationWords $Sources $Chapter
                if($null -ne $unit){$cue=$unit}
            }
        }
        $cue
    }
}

function Test-PvsSubtitleReferenceIdentity {
    param($Cue,[object[]]$Words,[object[]]$Sources)
    # The user selected SRT as the text authority. Identify the sentence from
    # several observed words and its ordered source interval, rather than
    # requiring the recognizer to reproduce every word or both sentence edges.
    $chapter=[int]$Cue.Chapter
    if($chapter -lt 0 -or $chapter -ge $Sources.Count -or -not (Test-PvsReferenceCueTiming $Cue $Sources[$chapter].start $Sources[$chapter].end $chapter)){return $false}
    if(Test-PvsSubtitleNumberReferenceIdentity $Cue $Words $Sources){return $true}
    $tokens=@(ConvertTo-NormalizedWords $Cue.Text);$timings=@($Cue.WordTimings)
    if($tokens.Count -lt 3 -or $tokens.Count -gt 200 -or $timings.Count -lt 2){return $false}
    $heard=@($Words | Where-Object {[int]$_.Chapter -eq $chapter -and [double]$Sources[$chapter].start+[double]$_.Start -lt $Cue.End-0.000001 -and [double]$Sources[$chapter].start+[double]$_.End -gt $Cue.Start+0.000001})
    if($heard.Count-$timings.Count -gt [Math]::Max(1,[Math]::Floor($tokens.Count*0.15))){return $false}
    $spans=@{}
    foreach($word in $heard){
        $key='{0:R}|{1:R}' -f ([double]$Sources[$chapter].start+[double]$word.Start),([double]$Sources[$chapter].start+[double]$word.End)
        if($spans.ContainsKey($key)){return $false};$spans[$key]=$word
    }
    $seen=@{};$lastIndex=-1;$strong=0;$weight=0.0;$uncertain=$tokens.Count-$timings.Count
    foreach($timing in $timings){
        $index=[int]$timing.TargetWordIndex
        if($index -le $lastIndex -or $index -ge $tokens.Count){return $false};$lastIndex=$index
        $key='{0:R}|{1:R}' -f [double]$timing.Start,[double]$timing.End
        if(-not $spans.ContainsKey($key) -or $seen.ContainsKey($key)){return $false};$seen[$key]=$true
        $w=Get-PvsSubtitleWordIdentityWeight $tokens[$index] ([string]$spans[$key].Text)
        if($w -eq 1){$strong++}else{$uncertain++}
        $weight+=$w
    }
    $score=$weight/[double][Math]::Max($tokens.Count,$heard.Count)
    $threshold=if($tokens.Count -eq 3){2.0/3.0}else{0.7}
    if($strong -lt [Math]::Max(2,[Math]::Ceiling($tokens.Count*0.5)) -or $score+0.000001 -lt $threshold -or $uncertain -gt [Math]::Max(2,[Math]::Min(8,[Math]::Floor($tokens.Count*0.3)))){return $false}
    # Keep only actually observed timings. Missing prefix/suffix/interior words
    # are text retention, not newly measured DTW points or edit-omission proof.
    $Cue | Add-Member -NotePropertyName SubtitleReferenceIdentityScore -NotePropertyValue $score -Force
    return $true
}

function Set-PvsSubtitlePartialReferenceReview {
    param($Cue)
    $Cue | Add-Member -NotePropertyName SubtitleReferencePartialMatch -NotePropertyValue $true -Force
    $Cue | Add-Member -NotePropertyName ReferenceReviewRequired -NotePropertyValue $true -Force
    $Cue | Add-Member -NotePropertyName ReferenceReviewReason -NotePropertyValue 'Giữ chữ SRT khớp phần lớn; nhận diện thiếu/khác một vài từ, cần kiểm tra chữ và timing' -Force
    if($Cue.PSObject.Properties['SubtitleReferenceFormatOnly'] -and $Cue.SubtitleReferenceFormatOnly){
        $Cue.ReferenceReviewRequired=$false
        $Cue.ReferenceReviewReason='Giữ chữ SRT; chỉ khác cách viết cấp độ La Mã/chữ số'
    }
}

function New-PvsSubtitleLetterReferenceCue {
    param($Reference,$Left,$Right,[object[]]$Words,[object[]]$Sources)
    # A label has no sentence-sized lexical evidence of its own. Retain it
    # only between its immediate, identified SRT neighbors, using one observed
    # word with the same letter (including an ASR accent such as A -> À).
    # Never fill an empty gap or treat arbitrary one-word speech as a label.
    if([string]$Reference.Text -cnotmatch '^\s*[A-Z][.!?:;)]?\s*$' -or $null -eq $Left -or $null -eq $Right){return $null}
    $chapter=[int]$Left.Chapter
    if($chapter -lt 0 -or $chapter -ge $Sources.Count -or [int]$Right.Chapter -ne $chapter){return $null}
    foreach($anchor in @($Left,$Right)){
        if(@(ConvertTo-NormalizedWords $anchor.Text).Count -lt 4 -or -not (Test-PvsSubtitleReferenceAnchor $anchor) -or -not (Test-PvsReferenceCueTiming $anchor $Sources[$chapter].start $Sources[$chapter].end $chapter)){return $null}
    }
    $a=[double]$Left.End;$b=[double]$Right.Start;$offset=[double]$Sources[$chapter].start
    if($b -le $a -or $b-$a -gt 3.0){return $null}
    # Include touching/overlapping hypotheses in the check: an extra word or
    # an invalid span cannot be silently discarded to manufacture one match.
    $heard=@($Words | Where-Object {[int]$_.Chapter -eq $chapter -and [double]$_.Start+$offset -lt $b-0.000001 -and [double]$_.End+$offset -gt $a+0.000001})
    if($heard.Count -ne 1){return $null}
    $target=@(ConvertTo-NormalizedWords $Reference.Text)
    if(-not (Test-PvsVietnameseRecognitionVariant $target[0] ([string]$heard[0].Text))){return $null}
    $layout=New-PvsReferenceWordLayout @($Reference)
    $candidate=@(Convert-PvsReferenceMappingToCues @($Reference) $layout @(0) $heard $Sources -PreserveReferenceIndices -FixedChapter $chapter)[0]
    if(-not (Test-PvsReferenceCueTiming $candidate $a $b $chapter) -or $candidate.End-$candidate.Start -gt 2.0){return $null}
    $candidate | Add-Member NoteProperty SubtitleReferenceLetterMatch $true
    $candidate | Add-Member NoteProperty SubtitleReferenceFormatOnly $true
    Set-PvsSubtitlePartialReferenceReview $candidate
    $candidate.ReferenceReviewReason='Giữ nhãn chữ cái SRT đã khớp giữa hai câu lân cận'
    return $candidate
}

function Confirm-PvsSubtitleReferenceWords {
    param([object[]]$Aligned,[object[]]$Words,[object[]]$Sources,[string]$Language,[switch]$SkipUnverified,[System.Collections.Generic.List[object]]$SkippedCues,[switch]$RequireCompleteWords)
    $basic=New-Object 'bool[]' $Aligned.Count
    $variants=New-Object 'bool[]' $Aligned.Count
    $expectedCounts=New-Object 'int[]' $Aligned.Count
    $excluded=New-Object 'bool[]' $Aligned.Count
    $recognizedBySpan=@{}
    $referenceCounts=@{}
    if($RequireCompleteWords){foreach($cue in $Aligned){$key=@(ConvertTo-NormalizedWords $cue.Text) -join ' ';if(-not $referenceCounts.ContainsKey($key)){$referenceCounts[$key]=0};$referenceCounts[$key]++}}
    foreach ($word in $Words) {
        $chapter=[int]$word.Chapter
        if ($chapter -lt 0 -or $chapter -ge $Sources.Count) { throw 'SUBTITLE_RECOGNITION_CHAPTER_INVALID' }
        $offset=[double]$Sources[$chapter].start
        $key='{0}|{1:R}|{2:R}' -f $chapter,($offset+[double]$word.Start),($offset+[double]$word.End)
        if (-not $recognizedBySpan.ContainsKey($key)) { $recognizedBySpan[$key]=New-Object System.Collections.Generic.List[string] }
        $recognizedBySpan[$key].Add([string]$word.Text)
    }
    for ($index=0; $index -lt $Aligned.Count; $index++) {
        $cue=$Aligned[$index]
        $cue | Add-Member -NotePropertyName ReferenceReviewRequired -NotePropertyValue $false -Force
        $cue | Add-Member -NotePropertyName ReferenceReviewReason -NotePropertyValue '' -Force
        $expectedCounts[$index]=@(ConvertTo-NormalizedWords ([string]$cue.Text)).Count
        if ($null -eq $cue.Start -or @($cue.WordTimings).Count -eq 0) {
            if($SkipUnverified){continue}
            throw "SUBTITLE_REFERENCE_WORD_UNALIGNED:cue-$($cue.Index). Hay kiem tra SRT co dung noi dung cua vung dang chon khong."
        }
        if (@($cue.WordTimings | Select-Object -ExpandProperty Chapter -Unique).Count -ne 1) { throw "SUBTITLE_REFERENCE_CROSSES_SELECTION_GAP:cue-$($cue.Index)" }
        $chapter=[int]$cue.Chapter
        if($chapter -lt 0 -or $chapter -ge $Sources.Count){throw 'SUBTITLE_RECOGNITION_CHAPTER_INVALID'}
        if(-not (Test-PvsReferenceCueTiming $cue ([double]$Sources[$chapter].start) ([double]$Sources[$chapter].end) $chapter)){
            if($SkipUnverified){continue}
            throw "SUBTITLE_REFERENCE_TIMING_INVALID:cue-$($cue.Index)"
        }
        $expectedCounts[$index]=@(ConvertTo-NormalizedWords ([string]$cue.Text)).Count
        $coverage=@($cue.WordTimings).Count/[double][Math]::Max(1,$expectedCounts[$index])
        $basic[$index]=[double]$cue.Confidence -ge 0.55 -and $coverage -ge 0.55
        if($RequireCompleteWords -and ($coverage -ne 1.0 -or [double]$cue.Confidence -lt 1.0)){
            $basic[$index]=(Test-PvsSubtitlePartialReferenceCue $cue $Words $Sources) -or (Test-PvsSubtitleReferenceIdentity $cue $Words $Sources)
            $key=@(ConvertTo-NormalizedWords $cue.Text) -join ' '
            if($referenceCounts[$key] -ne 1){$basic[$index]=$false}
            if($basic[$index]){Set-PvsSubtitlePartialReferenceReview $cue}
        }
        if ($basic[$index] -or $Language -ne 'vi' -or $coverage -ne 1.0) { continue }
        $valid=$true; $position=0; $previousEnd=-1.0
        foreach ($timing in $cue.WordTimings) {
            if ([int]$timing.TargetWordIndex -ne $position -or [double]$timing.End -le [double]$timing.Start -or [double]$timing.Start -lt $previousEnd-0.000001) { $valid=$false; break }
            $key='{0}|{1:R}|{2:R}' -f [int]$timing.Chapter,[double]$timing.Start,[double]$timing.End
            if (-not $recognizedBySpan.ContainsKey($key) -or $recognizedBySpan[$key].Count -ne 1 -or -not (Test-PvsVietnameseRecognitionVariant -Expected ([string]$timing.Text) -Recognized $recognizedBySpan[$key][0])) { $valid=$false; break }
            $position++; $previousEnd=[double]$timing.End
        }
        $variants[$index]=$valid
    }
    # Only accept a short, fully timed variant block bounded by strong lexical anchors.
    # Never invent timestamps, use old SRT timestamps, or relax every mismatching cue.
    for ($index=0; $index -lt $Aligned.Count; $index++) {
        if ($basic[$index]) { continue }
        $first=$index; $wordCount=0; $allVariants=$true
        while ($index -lt $Aligned.Count -and -not $basic[$index]) {
            $wordCount+=$expectedCounts[$index]
            if (-not $variants[$index]) { $allVariants=$false }
            $index++
        }
        $last=$index-1
        $allowed=$allVariants -and $wordCount -le 12 -and $first -gt 0 -and $index -lt $Aligned.Count
        if ($allowed) {
            $left=$Aligned[$first-1]; $right=$Aligned[$index]; $chapter=[int]$Aligned[$first].Chapter
            $allowed=(Test-PvsSubtitleReferenceAnchor $left) -and (Test-PvsSubtitleReferenceAnchor $right) -and [int]$left.Chapter -eq $chapter -and [int]$right.Chapter -eq $chapter -and [double]$Aligned[$last].End-[double]$Aligned[$first].Start -le 6.0 -and [double]$left.End -le [double]$Aligned[$first].Start+0.000001 -and [double]$Aligned[$last].End -le [double]$right.Start+0.000001
            for ($check=$first; $allowed -and $check -le $last; $check++) { if ([int]$Aligned[$check].Chapter -ne $chapter) { $allowed=$false } }
        }
        if (-not $allowed) {
            if($SkipUnverified){
                for($check=$first;$check -le $last;$check++){
                    $excluded[$check]=$true;$cue=$Aligned[$check]
                    if($null -ne $SkippedCues){$SkippedCues.Add([pscustomobject]@{cueIndex=[int]$cue.Index;reason=$(if($null -eq $cue.Start -or @($cue.WordTimings).Count -eq 0){'word-unaligned'}else{'reference-mismatch'});confidence=[double]$cue.Confidence;wordCoverage=@($cue.WordTimings).Count/[double][Math]::Max(1,$expectedCounts[$check])})}
                }
                $index--;continue
            }
            $cue=$Aligned[$first]
            $coverage=@($cue.WordTimings).Count/[double][Math]::Max(1,$expectedCounts[$first])
            throw "SUBTITLE_REFERENCE_MISMATCH:cue-$($cue.Index). Khop tu $([Math]::Round(100*$cue.Confidence))%; co timestamp $([Math]::Round(100*$coverage))%. Khong du can cu can an toan; hay kiem tra SRT/audio va vung dang chon."
        }
        for ($check=$first; $check -le $last; $check++) {
            $Aligned[$check].ReferenceReviewRequired=$true
            $Aligned[$check].ReferenceReviewReason='asr-spelling-variant'
        }
        $index--
    }
    for($index=0;$index -lt $Aligned.Count;$index++){if(-not $excluded[$index]){$Aligned[$index]}}
}

function Repair-PvsSubtitleRecognitionEdge {
    param($Json,[double]$Duration,[object[]]$Silences,[scriptblock]$RecognizeTail,[bool]$RequireCompleteTail=$false)
    if(-not $Json.PSObject.Properties['transcription']){return [pscustomobject]@{Json=$Json;Retried=$false}}
    $spoken=@($Json.transcription | Where-Object {$_.PSObject.Properties['offsets'] -and [string]$_.text -notmatch '^\s*\[.*\]\s*$' -and @(ConvertTo-NormalizedWords ([string]$_.text)).Count -gt 0})
    if($spoken.Count -eq 0){return [pscustomobject]@{Json=$Json;Retried=$false}}
    $invalid=@($spoken | Where-Object {[double]$_.offsets.from -ge $Duration*1000})
    $lastEnd=0.0
    foreach($segment in $spoken){$lastEnd=[Math]::Max($lastEnd,[double]$segment.offsets.to/1000.0)}
    $audibleEnd=$Duration
    foreach($quiet in $Silences){if([double]$quiet.End -ge $Duration-0.05){$audibleEnd=[Math]::Min($audibleEnd,[double]$quiet.Start)}}
    $missingTail=$RequireCompleteTail -and $audibleEnd-$lastEnd -gt 1.0
    if($invalid.Count -eq 0 -and -not $missingTail){return [pscustomobject]@{Json=$Json;Retried=$false}}
    # A token wholly past the physical WAV edge has no usable timing. Retry a
    # short tail from an acoustic silence; never shift the token by guessing.
    $cut=0.0
    $target=if($missingTail){$lastEnd-0.25}else{$Duration-12}
    $quiet=@($Silences | Where-Object {$_.Duration -ge 0.18 -and $_.Start -ge [Math]::Max(0,$Duration-30) -and $_.End -le $Duration-2 -and (-not $missingTail -or $_.End -le $lastEnd)} | Sort-Object @{Expression={[Math]::Abs(($_.Start+$_.End)/2.0-$target)}} | Select-Object -First 1)
    if($quiet.Count){$cut=([double]$quiet[0].Start+[double]$quiet[0].End)/2.0}
    elseif($Duration -gt 30){if($missingTail){throw 'SUBTITLE_RECOGNITION_TAIL_UNVERIFIED:Khong co moc nghi an toan de nhan dien lai duoi audio.'};return [pscustomobject]@{Json=$Json;Retried=$false}}
    $retry=& $RecognizeTail $cut ($Duration-$cut)
    if($null -eq $retry -or -not $retry.PSObject.Properties['transcription']){throw 'SUBTITLE_EDGE_RETRY_INVALID'}
    $joined=New-Object System.Collections.Generic.List[object]
    foreach($segment in $Json.transcription){
        if([double]$segment.offsets.from -ge $cut*1000){continue}
        $segment.offsets.to=[Math]::Min([double]$segment.offsets.to,$cut*1000)
        $joined.Add($segment)
    }
    foreach($segment in $retry.transcription){
        $segment.offsets.from=[double]$segment.offsets.from+$cut*1000;$segment.offsets.to=[double]$segment.offsets.to+$cut*1000
        if($segment.PSObject.Properties['tokens']){foreach($token in $segment.tokens){if($token.PSObject.Properties['t_dtw'] -and $token.t_dtw -ge 0){$token.t_dtw=[double]$token.t_dtw+$cut*100}}}
        $joined.Add($segment)
    }
    if($missingTail){
        $retrySpoken=@($retry.transcription | Where-Object {[string]$_.text -notmatch '^\s*\[.*\]\s*$' -and @(ConvertTo-NormalizedWords ([string]$_.text)).Count -gt 0})
        $retryEnd=0.0
        foreach($segment in $retrySpoken){$retryEnd=[Math]::Max($retryEnd,[double]$segment.offsets.to/1000.0)}
        if($audibleEnd-$retryEnd -gt 1.0){throw "SUBTITLE_RECOGNITION_TAIL_UNVERIFIED:ASR ket thuc tai $([Math]::Round($retryEnd,2))s, audio con tin hieu den $([Math]::Round($audibleEnd,2))s; hay kiem tra loi noi/nhac nen va vung duoc chon."}
    }
    $Json.transcription=$joined.ToArray()
    return [pscustomobject]@{Json=$Json;Retried=$true}
}

function Select-PvsSubtitleReference {
    param([object[]]$Cues,[object[]]$Words,[object[]]$Sources,[bool]$CharacterMode=$false,[string]$Language='vi',[switch]$AllowAudioOutsideReference,[switch]$SkipUnverifiedCues,[scriptblock]$RecognizeReferenceWindow,[switch]$AllowUnmatchedRanges,[switch]$AllowEditedReference)
    $Words=@($Words | Where-Object {$null -ne $_})
    if($AllowEditedReference){
        # Short phrases elsewhere in a long SRT can coincide with words inside
        # the Short. They are not strong anchors and must not invalidate every
        # ordered sentence. Auto edit keeps its original, stricter default.
        $minimumAnchorWords=if($CharacterMode){0}else{4}
        $edited=Resolve-PvsEditedReference -Cues $Cues -Words $Words -Sources $Sources -RecognizeWindow $RecognizeReferenceWindow -CharacterMode $CharacterMode -MinimumAnchorWords $minimumAnchorWords
        if($null -ne $edited){
            # Keep the shared omission proof unchanged. Only the subtitle
            # adapter may retain a mostly matched, bounded reference sentence.
            $partial=New-Object System.Collections.Generic.List[object]
            if(-not $CharacterMode){
                $duplicates=@{};foreach($cue in $Cues){$key=@(ConvertTo-NormalizedWords $cue.Text) -join ' ';if(-not $duplicates.ContainsKey($key)){$duplicates[$key]=0};$duplicates[$key]++}
                $retainedIndices=@($edited.Cues | ForEach-Object {[int]$_.Index})
                foreach($range in @($edited.Ranges | Where-Object {$_.status -in @('unresolved','recovered')})){
                    if($range.audioEnd-$range.audioStart -le 0){continue}
                    $reference=@($Cues | Where-Object {$range.cueIndices -contains [int]$_.Index})
                    $heard=@($edited.Words | Where-Object {[int]$_.Chapter -eq [int]$range.chapter -and [double]$Sources[$range.chapter].start+[double]$_.Start -ge $range.audioStart-0.000001 -and [double]$Sources[$range.chapter].start+[double]$_.End -le $range.audioEnd+0.000001})
                    # This is lexical projection only, not another ASR call or
                    # permission to omit content. Longer blocks keep good cues.
                    if(-not $heard.Count -or $reference.Count -gt 40 -or @(foreach($cue in $reference){ConvertTo-NormalizedWords $cue.Text}).Count -gt 800 -or [long]$heard.Count*800 -gt 2000000){continue}
                    $layout=New-PvsReferenceWordLayout $reference
                    $mapped=@(Convert-PvsSubtitleReferenceProjection $reference $layout $heard $edited.Words $Sources $range.chapter $Language)
                    foreach($cue in $mapped){
                        if($retainedIndices -contains [int]$cue.Index){continue}
                        $key=@(ConvertTo-NormalizedWords $cue.Text) -join ' '
                        if($duplicates[$key] -ne 1){
                            # Repeated text can still identify one sentence when
                            # distinct retained neighbors bound this occurrence.
                            # Multiple copies in the SAME unresolved interval
                            # remain ambiguous and must not be fabricated.
                            $localCopies=@($reference | Where-Object {(@(ConvertTo-NormalizedWords $_.Text) -join ' ') -ceq $key}).Count
                            if($localCopies -ne 1 -or $range.audioStart -le [double]$Sources[$range.chapter].start+0.000001 -or $range.audioEnd -ge [double]$Sources[$range.chapter].end-0.000001){continue}
                        }
                        if(-not ((Test-PvsSubtitlePartialReferenceCue $cue $edited.Words $Sources) -or (Test-PvsSubtitleReferenceIdentity $cue $edited.Words $Sources))){continue}
                        Set-PvsSubtitlePartialReferenceReview $cue
                        $partial.Add($cue)
                    }
                }
            }
            # A Short can finish halfway through a long SRT. The unresolved
            # suffix then includes many future cues and fails the block budget.
            # Recover individual sentences inside observed, neighbor-bounded
            # audio instead of sending the last valid sentence to outro ASR.
            if(-not $CharacterMode){
            $projectionBudget=0
            foreach($range in @($edited.Ranges | Where-Object {$_.status -in @('unresolved','recovered')})){
                $rangeReferences=@($Cues | Where-Object {$range.cueIndices -contains [int]$_.Index})
                for($pass=0;$pass -lt 2;$pass++){
                $passReferences=if($pass -eq 0){$rangeReferences}else{@($rangeReferences | Sort-Object Index -Descending)}
                foreach($referenceCue in $passReferences){
                    $known=@(@($edited.Cues)+@($partial.ToArray()))
                    if(@($known | Where-Object Index -eq $referenceCue.Index).Count){continue}
                    $key=@(ConvertTo-NormalizedWords $referenceCue.Text) -join ' '
                    $left=@($known | Where-Object {[int]$_.Chapter -eq [int]$range.chapter -and [int]$_.Index -lt [int]$referenceCue.Index} | Sort-Object Index | Select-Object -Last 1)
                    $right=@($known | Where-Object {[int]$_.Chapter -eq [int]$range.chapter -and [int]$_.Index -gt [int]$referenceCue.Index} | Sort-Object Index | Select-Object -First 1)
                    if(-not $left.Count -and -not $right.Count){continue}
                    # A later recovered sentence can bound a failed earlier
                    # projection. Revisit only those now bounded on BOTH sides;
                    # never spend another pass searching future SRT in the CTA.
                    if($pass -eq 1 -and (-not $left.Count -or -not $right.Count)){continue}
                    if($duplicates[$key] -ne 1){
                        $localCopies=@($Cues | Where-Object {$range.cueIndices -contains [int]$_.Index -and (@(ConvertTo-NormalizedWords $_.Text) -join ' ') -ceq $key}).Count
                        if($localCopies -ne 1 -or -not $left.Count -or -not $right.Count){continue}
                    }
                    $a=[double]$range.audioStart;$b=[double]$range.audioEnd
                    if($left.Count){$a=[Math]::Max($a,[double]$left[0].End)}
                    if($right.Count){$b=[Math]::Min($b,[double]$right[0].Start)}
                    if($b -le $a -or $b-$a -gt 30){continue}
                    $referencePosition=[array]::IndexOf($Cues,$referenceCue)
                    if($referencePosition -gt 0 -and $referencePosition+1 -lt $Cues.Count -and $left.Count -and $right.Count -and [int]$left[0].Index -eq [int]$Cues[$referencePosition-1].Index -and [int]$right[0].Index -eq [int]$Cues[$referencePosition+1].Index){
                        $letter=New-PvsSubtitleLetterReferenceCue $referenceCue $left[0] $right[0] $edited.Words $Sources
                        if($null -ne $letter){$partial.Add($letter);continue}
                    }
                    $heard=@($edited.Words | Where-Object {[int]$_.Chapter -eq [int]$range.chapter -and [double]$Sources[$range.chapter].start+[double]$_.Start -ge $a-0.000001 -and [double]$Sources[$range.chapter].start+[double]$_.End -le $b+0.000001})
                    $layout=New-PvsReferenceWordLayout @($referenceCue)
                    if($layout.Words.Count -lt 3 -or $layout.Words.Count -gt 200 -or -not $heard.Count -or $heard.Count -gt 400){continue}
                    $projectionBudget+=[long]$layout.Words.Count*$heard.Count
                    if($projectionBudget -gt 2000000){break}
                    $candidate=@(Convert-PvsSubtitleReferenceProjection @($referenceCue) $layout $heard $edited.Words $Sources $range.chapter $Language)[0]
                    if(-not ((Test-PvsSubtitlePartialReferenceCue $candidate $edited.Words $Sources) -or (Test-PvsSubtitleReferenceIdentity $candidate $edited.Words $Sources))){continue}
                    if($candidate.Start -lt $a-0.000001 -or $candidate.End -gt $b+0.000001){continue}
                    Set-PvsSubtitlePartialReferenceReview $candidate
                    $partial.Add($candidate)
                }
                }
            }
            }
            # A whole recovery window can differ at either retained neighbor,
            # so the shared edit proof correctly rejects it. Subtitle policy
            # still needs a fresh, local sentence attempt before ASR fallback.
            # Never retry an omitted cue, a future suffix, or ambiguous copies.
            $retrySeconds=0.0;$retryCount=0
            if(-not $CharacterMode -and $null -ne $RecognizeReferenceWindow){
                foreach($referenceCue in $Cues){
                    $known=@(@($edited.Cues)+@($partial.ToArray()))
                    if(@($known | Where-Object Index -eq $referenceCue.Index).Count -or $edited.UnresolvedCueIndices -notcontains [int]$referenceCue.Index){continue}
                    $position=[array]::IndexOf($Cues,$referenceCue)
                    if($position -le 0 -or $position+1 -ge $Cues.Count){continue}
                    $key=@(ConvertTo-NormalizedWords $referenceCue.Text) -join ' '
                    if($duplicates[$key] -ne 1){continue}
                    $left=@($known | Where-Object Index -eq $Cues[$position-1].Index)
                    $right=@($known | Where-Object Index -eq $Cues[$position+1].Index)
                    if($left.Count -ne 1 -or $right.Count -ne 1 -or $left[0].Chapter -ne $right[0].Chapter){continue}
                    $chapter=[int]$left[0].Chapter
                    if($chapter -lt 0 -or $chapter -ge $Sources.Count){continue}
                    $valid=$true
                    $leftText=[string]$left[0].Text;$rightText=[string]$right[0].Text
                    foreach($side in @('left','right')){
                        $anchor=if($side -eq 'left'){$left[0]}else{$right[0]}
                        if(-not (Test-PvsReferenceCueTiming $anchor $Sources[$chapter].start $Sources[$chapter].end $chapter)){$valid=$false;continue}
                        if(@(ConvertTo-NormalizedWords $anchor.Text).Count -ge 4){continue}
                        # A short retained connector (e.g. "Quan trọng hơn")
                        # is not a strong anchor alone. Extend its TEXT only
                        # with the next immediate, strongly verified neighbor;
                        # keep the original physical gap unchanged.
                        $supportPosition=if($side -eq 'left'){$position-2}else{$position+2}
                        if($Language -ne 'vi' -or $supportPosition -lt 0 -or $supportPosition -ge $Cues.Count){$valid=$false;continue}
                        $support=@($known|Where-Object Index -eq $Cues[$supportPosition].Index)
                        if($support.Count -ne 1 -or $support[0].Chapter -ne $chapter -or -not (Test-PvsSubtitleReferenceAnchor $support[0]) -or -not (Test-PvsReferenceCueTiming $support[0] $Sources[$chapter].start $Sources[$chapter].end $chapter)){$valid=$false;continue}
                        if($side -eq 'left'){
                            if($support[0].End -gt $anchor.Start+0.000001){$valid=$false;continue}
                            $leftText=$support[0].Text+' '+$leftText
                        }else{
                            if($support[0].Start -lt $anchor.End-0.000001){$valid=$false;continue}
                            $rightText+=' '+$support[0].Text
                        }
                    }
                    $a=[double]$left[0].End;$b=[double]$right[0].Start
                    if(-not $valid -or $b-$a -lt 0.2 -or $b-$a -gt 30 -or $retryCount -ge 32 -or $retrySeconds+$b-$a -gt 180){continue}
                    $layout=New-PvsReferenceWordLayout @($referenceCue)
                    if($layout.Words.Count -lt 3 -or $layout.Words.Count -gt 200){continue}
                    for($attempt=0;$attempt -lt 2;$attempt++){
                        $readStart=$a;$readEnd=$b
                        if($attempt -eq 1){
                            if($Language -ne 'vi'){break}
                            # A very short isolated crop can change spelling or
                            # split a name. Read real neighboring audio, never
                            # an SRT prompt, after the ordinary retry failed.
                            $readStart=[Math]::Max([double]$Sources[$chapter].start,$a-2.5)
                            $readEnd=[Math]::Min([double]$Sources[$chapter].end,$b+2.5)
                            if($readStart -ge $a -or $readEnd -le $b){break}
                        }
                        if($retryCount -ge 32 -or $retrySeconds+$readEnd-$readStart -gt 180){break}
                        $retryCount++;$retrySeconds+=$readEnd-$readStart
                        $retry=@(& $RecognizeReferenceWindow $Sources[$chapter] $readStart $readEnd)
                        $edge=0.0
                        foreach($word in $retry){
                            $start=[double]$word.Start;$end=[double]$word.End
                            if([string]::IsNullOrWhiteSpace([string]$word.Text) -or [int]$word.Chapter -ne 0 -or [double]::IsNaN($start) -or [double]::IsNaN($end) -or [double]::IsInfinity($start) -or [double]::IsInfinity($end) -or $start -lt $edge-0.000001 -or $end -le $start -or $end -gt $readEnd-$readStart+0.000001){throw 'SUBTITLE_REFERENCE_RETRY_TIMING_INVALID'}
                            $edge=$end
                        }
                        if(-not $retry.Count -or $retry.Count -gt 400){continue}
                        if($attempt -eq 1){
                            $inside=Get-PvsSubtitleContextInterior ([pscustomobject]@{Words=$retry}) ($a-$readStart) ($b-$readStart) $leftText $rightText
                            # Both already-retained neighbors must be observed
                            # uniquely. Context never expands the original gap.
                            if(-not $inside.LeftMatched -or -not $inside.RightMatched -or $inside.End -le $inside.Start){continue}
                            $retry=@($retry|Where-Object {$_.Start -lt $inside.End-0.000001 -and $_.End -gt $inside.Start+0.000001})
                            if(-not $retry.Count -or $retry[0].Start -lt $inside.Start-0.000001 -or $retry[-1].End -gt $inside.End+0.000001){continue}
                        }
                        $fresh=@($retry|ForEach-Object {$copy=$_.PSObject.Copy();$copy.Start+=$readStart-[double]$Sources[$chapter].start;$copy.End+=$readStart-[double]$Sources[$chapter].start;$copy.Chapter=$chapter;$copy})
                        $candidate=@(Convert-PvsSubtitleReferenceProjection @($referenceCue) $layout $fresh $fresh $Sources $chapter $Language)[0]
                        if(-not ((Test-PvsSubtitlePartialReferenceCue $candidate $fresh $Sources) -or (Test-PvsSubtitleReferenceIdentity $candidate $fresh $Sources))){continue}
                        # All remaining speech must belong to this sentence;
                        # neither retry may discard genuine extra edge words.
                        if($candidate.Start -gt $readStart+$retry[0].Start+0.000001 -or $candidate.End -lt $readStart+$retry[-1].End-0.000001){continue}
                        Set-PvsSubtitlePartialReferenceReview $candidate
                        $candidate | Add-Member NoteProperty SubtitleReferenceLocalRetry $true
                        if($attempt -eq 1){$candidate | Add-Member NoteProperty SubtitleReferenceContextRetry $true}
                        $partial.Add($candidate);break
                    }
                }
            }
            $partialIndices=@($partial | ForEach-Object {[int]$_.Index})
            $skipped=@($edited.UnresolvedCueIndices | Where-Object {$partialIndices -notcontains $_})
            $unverified=@($edited.Ranges | Where-Object status -eq 'unresolved' | ForEach-Object {
                $remaining=@($_.cueIndices | Where-Object {$skipped -contains $_})
                if($remaining.Count){[pscustomobject]@{sourceIndex=$_.chapter;start=$_.audioStart;end=$_.audioEnd;cueIndices=$remaining}}
            })
            $retained=@(@($edited.Cues)+@($partial.ToArray()) | Sort-Object Start,End)
            return [pscustomobject]@{Cues=$retained;Ranges=@();FallbackRanges=@();ReferenceCueCount=$Cues.Count;SelectedCueCount=$retained.Count;OutsideCueCount=0;OutsideAudioWordCount=0;SkippedCues=@($skipped | ForEach-Object {[pscustomobject]@{cueIndex=$_;reason='edited-reference-unresolved'}});SkippedCueCount=$skipped.Count;UnverifiedRanges=$unverified;RecoveredCueIndices=$edited.RecoveredCueIndices;EditedReference=$edited;RecognitionWords=$edited.Words;PartialReferenceCueIndices=$partialIndices}
        }
    }
    if (-not ('PvsSubtitleScopeV2' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
public sealed class PvsSubtitleScopeMatch {
    public int Cost, Exact, First, Last;
    public int[] Mapping;
}
public static class PvsSubtitleScopeV2 {
    private sealed class Cursor {
        public int I, J;
        public PvsSubtitleScopeMatch Match;
    }
    // Reference prefix/suffix is free; every recognized word must be consumed.
    // Save cost checkpoints, then recompute one traceback block at a time.
    // Exact recurrence/tie order and every near-best endpoint are preserved;
    // memory grows as O(m*sqrt(n)), rather than rejecting long SRTs at 25M cells.
    public static PvsSubtitleScopeMatch[] Find(string[] reference, string[] audio) {
        int n=reference.Length, m=audio.Length;
        if(n==0 || m==0) throw new ArgumentException("SUBTITLE_REFERENCE_SCOPE_SIZE");
        int block=Math.Max(1,(int)Math.Ceiling(2*Math.Sqrt(n)));
        long width=(long)m+1;
        long workingBytes=4L*(n+1L)+width*(4L*(n/block+1)+8L+block+1L);
        const long memoryBudget=128L*1024*1024;
        if(workingBytes>memoryBudget || width*(block+1L)>Int32.MaxValue)
            throw new ArgumentException("SUBTITLE_REFERENCE_SCOPE_MEMORY_LIMIT: Hay chon tung vung/clip va SRT tuong ung.");
        int[][] checkpoints=new int[n/block+1][];
        int[] previous=new int[m+1], current=new int[m+1], scores=new int[n+1];
        for(int j=0;j<=m;j++) previous[j]=j;
        checkpoints[0]=(int[])previous.Clone();
        scores[0]=m; int best=m;
        for(int i=1;i<=n;i++) {
            current[0]=0;
            for(int j=1;j<=m;j++) {
                int sub=previous[j-1]+(reference[i-1]==audio[j-1]?0:1);
                int del=previous[j]+1, ins=current[j-1]+1;
                current[j]=Math.Min(sub,Math.Min(del,ins));
            }
            scores[i]=current[m]; if(scores[i]<best)best=scores[i];
            int[] swap=previous;previous=current;current=swap;
            if(i%block==0) checkpoints[i/block]=(int[])previous.Clone();
        }
        int tolerance=Math.Max(1,(int)Math.Floor(m*0.005));
        var cursors=new List<Cursor>();
        for(int end=1;end<=n;end++) {
            if(scores[end]>best+tolerance)continue;
            // Each nonempty endpoint consumes at least one diagonal (ties prefer
            // substitution), so the original 512-candidate ambiguity guard applies.
            if(cursors.Count==512)throw new ArgumentException("SUBTITLE_REFERENCE_SCOPE_AMBIGUOUS");
            if(workingBytes+4L*n*(cursors.Count+1)>memoryBudget)
                throw new ArgumentException("SUBTITLE_REFERENCE_SCOPE_MEMORY_LIMIT: Hay chon tung vung/clip va SRT tuong ung.");
            int[] map=new int[n];for(int k=0;k<n;k++)map[k]=-1;
            cursors.Add(new Cursor{I=end,J=m,Match=new PvsSubtitleScopeMatch{Cost=scores[end],First=n,Last=-1,Mapping=map}});
        }
        byte[,] back=new byte[Math.Min(block,n)+1,m+1];
        for(int start=((n-1)/block)*block;start>=0;start-=block) {
            int stop=Math.Min(n,start+block); bool needed=false;
            foreach(var cursor in cursors) if(cursor.J>0 && cursor.I>start && cursor.I<=stop){needed=true;break;}
            if(!needed)continue;
            Array.Copy(checkpoints[start/block],previous,m+1);
            for(int i=start+1;i<=stop;i++) {
                int row=i-start;current[0]=0;
                for(int j=1;j<=m;j++) {
                    int sub=previous[j-1]+(reference[i-1]==audio[j-1]?0:1);
                    int del=previous[j]+1, ins=current[j-1]+1;
                    if(sub<=del && sub<=ins){current[j]=sub;back[row,j]=0;}
                    else if(del<=ins){current[j]=del;back[row,j]=1;}
                    else{current[j]=ins;back[row,j]=2;}
                }
                int[] swap=previous;previous=current;current=swap;
            }
            foreach(var cursor in cursors) {
                if(cursor.I>stop)continue;
                while(cursor.J>0 && cursor.I>start) {
                    int i=cursor.I,j=cursor.J;var match=cursor.Match;
                    byte direction=back[i-start,j];
                    if(direction==0){match.Mapping[i-1]=j-1;match.First=i-1;if(match.Last<0)match.Last=i-1;if(reference[i-1]==audio[j-1])match.Exact++;cursor.I--;cursor.J--;}
                    else if(direction==1)cursor.I--;
                    else cursor.J--;
                }
            }
        }
        var output=new List<PvsSubtitleScopeMatch>();
        foreach(var cursor in cursors) if(cursor.Match.Last>=0) output.Add(cursor.Match);
        return output.ToArray();
    }
}
'@
    }
    $layout=New-PvsReferenceWordLayout -Cues $Cues -CharacterMode $CharacterMode
    $targets=New-Object System.Collections.Generic.List[string]
    $targets.AddRange([string[]]$layout.Words)
    $wordCue=$layout.WordCue
    $starts=$layout.CueStarts
    $ends=New-Object 'int[]' $Cues.Count
    for($i=0;$i -lt $Cues.Count;$i++) {
        $ends[$i]=$layout.CueEnds[$i]-1
    }
    if($targets.Count -eq 0){throw 'SUBTITLE_NO_SPEECH_OR_TEXT'}
    $aligned=New-Object System.Collections.Generic.List[object]
    $ranges=New-Object System.Collections.Generic.List[object]
    $fallbackRanges=New-Object System.Collections.Generic.List[object]
    $previousLastCue=-1
    $outsideAudioWords=0
    for($chapter=0;$chapter -lt $Sources.Count;$chapter++) {
        try {
            $audio=@($Words | Where-Object {[int]$_.Chapter -eq $chapter})
            if($audio.Count -eq 0){throw "SUBTITLE_REFERENCE_SCOPE_NO_SPEECH:range-$($chapter+1)"}
            $matches=@([PvsSubtitleScopeV2]::Find($targets.ToArray(),[string[]]$audio.Text))
            $candidates=@{}
            $partial=$false
            foreach($match in $matches) {
                if($match.Exact/[double]$audio.Count -lt 0.7 -or $match.Cost -gt [Math]::Max(2,$audio.Count*0.3)){continue}
                $anchorLength=[Math]::Min(8,$audio.Count)
                $firstExact=0;$lastExact=0
                for($word=$match.First;$word -le $match.Last;$word++) {
                    $mapped=$match.Mapping[$word]
                    if($mapped -lt 0 -or $targets[$word] -ne $audio[$mapped].Text){continue}
                    if($mapped -lt $anchorLength){$firstExact++}
                    if($mapped -ge $audio.Count-$anchorLength){$lastExact++}
                }
                if($firstExact/[double]$anchorLength -lt 0.75 -or $lastExact/[double]$anchorLength -lt 0.75){continue}
                $firstCue=$wordCue[$match.First];$lastCue=$wordCue[$match.Last]
                if($match.First -ne $starts[$firstCue] -or $match.Last -ne $ends[$lastCue]){$partial=$true;continue}
                $key="$firstCue-$lastCue"
                if(-not $candidates.ContainsKey($key) -or $match.Cost -lt $candidates[$key].Match.Cost){$candidates[$key]=[pscustomobject]@{First=$firstCue;Last=$lastCue;Match=$match}}
            }
            if($candidates.Count -gt 1){throw "SUBTITLE_REFERENCE_SCOPE_AMBIGUOUS:range-$($chapter+1). Noi dung lap hoac nhieu pham vi SRT gan giong nhau; hay chon SRT rieng cho vung nay."}
            # For one continuous audio range, the entire reference may be inside
            # extra intro/outro speech. Reverse the same exact scope matcher, then
            # invert its mapping. Require the complete SRT, exact endpoint words
            # and strong 8-word anchors; never skip reference cues or internal audio.
            if($candidates.Count -eq 0 -and $AllowAudioOutsideReference -and $Sources.Count -eq 1){
                $spans=@{}
                foreach($reverse in @([PvsSubtitleScopeV2]::Find([string[]]$audio.Text,$targets.ToArray()))){
                    if($reverse.Exact/[double]$targets.Count -lt 0.7 -or $reverse.Cost -gt [Math]::Max(2,$targets.Count*0.3)){continue}
                    $mapping=New-Object 'int[]' $targets.Count
                    for($word=0;$word -lt $mapping.Length;$word++){$mapping[$word]=-1}
                    for($heard=$reverse.First;$heard -le $reverse.Last;$heard++){
                        $target=$reverse.Mapping[$heard]
                        if($target -ge 0){$mapping[$target]=$heard}
                    }
                    $first=$mapping[0];$last=$mapping[$mapping.Length-1]
                    if($first -lt 0 -or $last -lt $first -or $audio[$first].Text -ne $targets[0] -or $audio[$last].Text -ne $targets[$targets.Count-1]){continue}
                    $anchorLength=[Math]::Min(8,$targets.Count);$firstExact=0;$lastExact=0
                    for($word=0;$word -lt $anchorLength;$word++){
                        $mapped=$mapping[$word]
                        if($mapped -ge 0 -and $targets[$word] -eq $audio[$mapped].Text){$firstExact++}
                        $tail=$targets.Count-1-$word;$mapped=$mapping[$tail]
                        if($mapped -ge 0 -and $targets[$tail] -eq $audio[$mapped].Text){$lastExact++}
                    }
                    if($firstExact/[double]$anchorLength -lt 0.75 -or $lastExact/[double]$anchorLength -lt 0.75){continue}
                    $key="$first-$last"
                    if(-not $spans.ContainsKey($key) -or $reverse.Cost -lt $spans[$key].Cost){
                        $spans[$key]=[pscustomobject]@{Cost=$reverse.Cost;Exact=$reverse.Exact;First=0;Last=$targets.Count-1;Mapping=$mapping;AudioFirst=$first;AudioLast=$last}
                    }
                }
                if($spans.Count -gt 1){throw 'SUBTITLE_REFERENCE_SCOPE_AMBIGUOUS:Nhieu doan audio khop SRT; hay chon rieng vung can tao subtitle.'}
                if($spans.Count -eq 1){
                    $match=@($spans.Values)[0]
                    $outsideAudioWords=$audio.Count-($match.AudioLast-$match.AudioFirst+1)
                    $candidates['full-reference']=[pscustomobject]@{First=0;Last=$Cues.Count-1;Match=$match}
                }
            }
            if($candidates.Count -eq 0){
                if($partial){throw "SUBTITLE_REFERENCE_SCOPE_PARTIAL_CUE:range-$($chapter+1). Audio cat giua cue hoac ASR thieu tu o mep; hay chon tron cau/clip hoac SRT tuong ung."}
                throw "SUBTITLE_REFERENCE_SCOPE_MISMATCH:range-$($chapter+1). Khong tim thay phan SRT khop du loi noi voi moc neo ro o ca hai mep."
            }
            $candidate=@($candidates.Values)[0]
            if($candidate.First -le $previousLastCue){throw 'SUBTITLE_REFERENCE_SCOPE_ORDER:Thu tu noi dung SRT cua cac vung audio bi lap/chong hoac dao nguoc.'}
            $previousLastCue=$candidate.Last
            $selectedCues=@($Cues[$candidate.First..$candidate.Last])
            $selectedLayout=New-PvsReferenceWordLayout -Cues $selectedCues -CharacterMode $CharacterMode
            $selectedMapping=New-Object 'int[]' $selectedLayout.Words.Count
            [Array]::Copy($candidate.Match.Mapping,$starts[$candidate.First],$selectedMapping,0,$selectedMapping.Length)
            foreach($cue in (Convert-PvsReferenceMappingToCues -Cues $selectedCues -Layout $selectedLayout -Mapping $selectedMapping -RecognizedWords $audio -VoiceClips $Sources -PreserveReferenceIndices -FixedChapter $chapter)){$aligned.Add($cue)}
            $ranges.Add([pscustomobject]@{sourceIndex=$chapter;firstCue=$aligned[$aligned.Count-($candidate.Last-$candidate.First+1)].Index;lastCue=$aligned[$aligned.Count-1].Index;start=[double]$Sources[$chapter].start;end=[double]$Sources[$chapter].end})
        } catch {
            # One unsafe scope must not discard good SRT from other sources.
            # Resource/compiler/native failures are never text mismatches.
            if(-not $AllowUnmatchedRanges -or $_.Exception.Message -notmatch 'SUBTITLE_REFERENCE_SCOPE_(MISMATCH|PARTIAL_CUE|AMBIGUOUS|ORDER|NO_SPEECH)(:|$)'){throw}
            $fallbackRanges.Add([pscustomobject]@{sourceIndex=$chapter;start=[double]$Sources[$chapter].start;end=[double]$Sources[$chapter].end;cueIndices=@();reason=$_.Exception.Message})
        }
    }
    # Scope validation stays strict. Within that scope the caller can request
    # partial output, with an explicit list of every unverified cue omitted.
    $recovered=@()
    if($aligned.Count -gt 0 -and -not $CharacterMode -and $null -ne $RecognizeReferenceWindow){
        $recovered=@(Repair-PvsMissingCueWordTimings -Cues $aligned.ToArray() -VoiceClips $Sources -RecognizeWindow $RecognizeReferenceWindow)
    }
    $skipped=New-Object System.Collections.Generic.List[object]
    $confirmed=if(-not $CharacterMode){@(Confirm-PvsSubtitleReferenceWords -Aligned $aligned.ToArray() -Words $Words -Sources $Sources -Language $Language -SkipUnverified:$SkipUnverifiedCues -SkippedCues $skipped -RequireCompleteWords:$AllowEditedReference)}else{
        foreach($cue in $aligned){
            $chapter=[int]$cue.Chapter
            if(-not (Test-PvsReferenceCueTiming $cue ([double]$Sources[$chapter].start) ([double]$Sources[$chapter].end) $chapter) -or @($cue.WordTimings).Count -ne @(Get-PvsSubtitleLexicalWords $cue.Text $true).Count -or $cue.Confidence -lt 0.55){
                if(-not $SkipUnverifiedCues){throw "SUBTITLE_REFERENCE_MISMATCH:cue-$($cue.Index)"}
                $skipped.Add([pscustomobject]@{cueIndex=[int]$cue.Index;reason='reference-mismatch';confidence=[double]$cue.Confidence;wordCoverage=@($cue.WordTimings).Count/[double][Math]::Max(1,@(Get-PvsSubtitleLexicalWords $cue.Text $true).Count)})
            }else{$cue}
        }
    }
    $confirmed=@($confirmed | Where-Object {$null -ne $_})
    if($confirmed.Count -eq 0 -and -not ($AllowUnmatchedRanges -and $SkipUnverifiedCues)){throw 'SUBTITLE_REFERENCE_NO_VERIFIED_CUES:Khong co cue nao du can cu tao subtitle.'}
    $unverifiedRanges=New-Object System.Collections.Generic.List[object]
    foreach($range in $fallbackRanges){$unverifiedRanges.Add($range)}
    $badIndices=@{};foreach($item in $skipped){$badIndices[[int]$item.cueIndex]=$true}
    for($index=0;$index -lt $aligned.Count;$index++){
        if(-not $badIndices.ContainsKey([int]$aligned[$index].Index)){continue}
        $first=$index;$chapter=[int]$aligned[$index].Chapter
        while($index+1 -lt $aligned.Count -and [int]$aligned[$index+1].Chapter -eq $chapter -and $badIndices.ContainsKey([int]$aligned[$index+1].Index)){$index++}
        $last=$index;$source=$Sources[$chapter]
        $start=if($first -gt 0 -and [int]$aligned[$first-1].Chapter -eq $chapter){[double]$aligned[$first-1].End}else{[double]$source.start}
        $end=if($last+1 -lt $aligned.Count -and [int]$aligned[$last+1].Chapter -eq $chapter){[double]$aligned[$last+1].Start}else{[double]$source.end}
        $unverifiedRanges.Add([pscustomobject]@{sourceIndex=$chapter;start=$start;end=$end;cueIndices=@($aligned.ToArray()[$first..$last] | ForEach-Object {$_.Index})})
    }
    return [pscustomobject]@{Cues=@($confirmed);Ranges=$ranges.ToArray();FallbackRanges=$fallbackRanges.ToArray();ReferenceCueCount=$Cues.Count;SelectedCueCount=@($confirmed).Count;OutsideCueCount=$Cues.Count-$aligned.Count;OutsideAudioWordCount=$outsideAudioWords;SkippedCues=$skipped.ToArray();SkippedCueCount=$skipped.Count;UnverifiedRanges=$unverifiedRanges.ToArray();RecoveredCueIndices=$recovered}
}

function Get-PvsAutoEditReferenceWordCoverage {
    param($Cue,[object[]]$Words,[object[]]$Sources)
    # Text identity alone is insufficient for Auto edit: a missing prefix,
    # suffix or interior word must still go to the strict omission resolver.
    $chapter=[int]$Cue.Chapter
    if($chapter -lt 0 -or $chapter -ge $Sources.Count -or -not (Test-PvsReferenceCueTiming $Cue $Sources[$chapter].start $Sources[$chapter].end $chapter)){return $null}
    $tokens=@(ConvertTo-NormalizedWords $Cue.Text);$timings=@($Cue.WordTimings)
    $offset=[double]$Sources[$chapter].start
    $heard=@($Words | Where-Object {[int]$_.Chapter -eq $chapter -and $offset+[double]$_.Start -lt $Cue.End-0.000001 -and $offset+[double]$_.End -gt $Cue.Start+0.000001} | Sort-Object Start)
    if(-not $tokens.Count -or $heard.Count -ne $timings.Count -or -not $heard.Count){return $null}
    $previousIndex=-1
    for($i=0;$i -lt $heard.Count;$i++){
        $t=$timings[$i];$w=$heard[$i];$index=[int]$t.TargetWordIndex
        if($index -le $previousIndex -or $index -ge $tokens.Count -or [string]$t.Text -cne $tokens[$index] -or
            [double]::IsNaN([double]$w.Start) -or [double]::IsNaN([double]$w.End) -or
            [Math]::Abs([double]$t.Start-$offset-[double]$w.Start) -gt 0.000001 -or
            [Math]::Abs([double]$t.End-$offset-[double]$w.End) -gt 0.000001 -or
            [bool]$t.Exact -ne ([string]$w.Text -ceq $tokens[$index])){return $null}
        $previousIndex=$index
    }
    if($tokens.Count -eq $timings.Count -and $timings[0].TargetWordIndex -eq 0 -and $timings[-1].TargetWordIndex -eq $tokens.Count-1){return [pscustomobject]@{kind='complete-word-coverage';groups=@()}}
    # One literal digit token may represent a spoken digit sequence. Require
    # EXACT complete context and digits, not fuzzy number/value agreement.
    # Keep the single observed span; never divide it into invented word times.
    $expected=Get-PvsSubtitleNumericSpan $tokens
    $actual=Get-PvsSubtitleNumericSpan @($heard.Text) -RequireDigits
    if($null -eq $expected -or $null -eq $actual -or $actual.First -ne $actual.Last -or $actual.Text -notmatch '^\d{2,12}$' -or $expected.Tokens.Count -ne $actual.Text.Length){return $null}
    $digits=@{'không'='0';'một'='1';'hai'='2';'ba'='3';'bốn'='4';'năm'='5';'sáu'='6';'bảy'='7';'tám'='8';'chín'='9'}
    $spelled=''
    foreach($token in $expected.Tokens){if(-not $digits.ContainsKey($token)){return $null};$spelled+=$digits[$token]}
    if($spelled -cne $actual.Text -or $expected.First -ne $actual.First -or $tokens.Count-$expected.Tokens.Count -lt 4 -or $tokens.Count-$expected.Tokens.Count -ne $heard.Count-1){return $null}
    for($i=0;$i -lt $heard.Count;$i++){
        $target=if($i -lt $actual.First){$i}elseif($i -eq $actual.First){$expected.Last}else{$i+$expected.Tokens.Count-1}
        if([int]$timings[$i].TargetWordIndex -ne $target){return $null}
        if($i -ne $actual.First -and [string]$heard[$i].Text -cne $tokens[$target]){return $null}
    }
    return [pscustomobject]@{kind='spoken-digit-group';groups=@([pscustomobject]@{firstTargetWord=$expected.First;lastTargetWord=$expected.Last;timingIndex=$actual.First;recognized=$actual.Text;start=$timings[$actual.First].Start;end=$timings[$actual.First].End})}
}

function Repair-PvsAutoEditReferenceWords {
    param([object[]]$Cues,[object[]]$Aligned,[object[]]$Words,[object[]]$Sources,[scriptblock]$RecognizeWindow,[string]$Language='vi',[double]$LowConfidenceThreshold=0.55)
    $pending=@($Aligned | Where-Object {$_.Confidence -lt $LowConfidenceThreshold -or @($_.WordTimings).Count -ne @(ConvertTo-NormalizedWords $_.Text).Count})
    $none=[pscustomobject]@{Repaired=$false;Cues=$Aligned;RecoveredCueIndices=@();Recovery=@()}
    if($Language -ne 'vi' -or -not $pending.Count -or $null -eq $RecognizeWindow){return $none}
    # Reuse subtitle projection/context/local retry without changing its text
    # thresholds, nor the shared resolver's stricter permission to omit picture.
    $selection=Select-PvsSubtitleReference -Cues $Cues -Words $Words -Sources $Sources -Language $Language -AllowEditedReference -SkipUnverifiedCues -AllowUnmatchedRanges -RecognizeReferenceWindow $RecognizeWindow
    if($selection.PSObject.Properties['EditedReference'] -and $selection.EditedReference.OmittedCueIndices.Count){return $none}
    $validationWords=if($selection.PSObject.Properties['RecognitionWords']){$selection.RecognitionWords}else{$Words}
    $copies=[object[]]$Aligned.Clone();$reports=New-Object System.Collections.Generic.List[object]
    foreach($old in $pending){
        $candidates=@($selection.Cues | Where-Object Index -eq $old.Index)
        if($candidates.Count -ne 1){continue}
        $candidate=$candidates[0]
        if([string]$candidate.Text -cne [string]$old.Text -or $candidate.Confidence -lt $LowConfidenceThreshold -or
            @($Cues | Where-Object {(@(ConvertTo-NormalizedWords $_.Text) -join ' ') -ceq (@(ConvertTo-NormalizedWords $candidate.Text) -join ' ')}).Count -ne 1){continue}
        $coverage=Get-PvsAutoEditReferenceWordCoverage $candidate $validationWords $Sources
        if($null -eq $coverage){continue}
        $position=-1
        for($i=0;$i -lt $Aligned.Count;$i++){if($Aligned[$i].Index -eq $old.Index){$position=$i;break}}
        if($position -lt 0){continue}
        $safeNeighbors=$true
        foreach($neighbor in @($(if($position -gt 0){$Aligned[$position-1]}),$(if($position+1 -lt $Aligned.Count){$Aligned[$position+1]}))){
            if($null -eq $neighbor -or $neighbor.Chapter -ne $candidate.Chapter){continue}
            if($null -eq $neighbor.Start -or $null -eq $neighbor.End -or
                ($neighbor.Index -lt $candidate.Index -and $neighbor.End -gt $candidate.Start+0.000001) -or
                ($neighbor.Index -gt $candidate.Index -and $neighbor.Start -lt $candidate.End-0.000001)){$safeNeighbors=$false;break}
        }
        if(-not $safeNeighbors){continue}
        $copy=$candidate.PSObject.Copy();$copy.WordTimings=@($candidate.WordTimings | ForEach-Object {$_.PSObject.Copy()})
        foreach($group in $coverage.groups){$copy.WordTimings[$group.timingIndex] | Add-Member NoteProperty SubtitleTimingQuality 'estimated' -Force}
        # Text recovery is reviewable. Neither legacy silence cuts nor DTW
        # trials may split at the edges of this cue using sparse word evidence.
        $copy | Add-Member NoteProperty EditBoundaryReviewRequired $true -Force
        $copy | Add-Member NoteProperty ReferenceReviewRequired $true -Force
        $copy | Add-Member NoteProperty AutoEditReferenceRecovery $coverage.kind -Force
        $copies[$position]=$copy
        $reports.Add([pscustomobject]@{cueIndex=[int]$copy.Index;kind=$coverage.kind;groups=$coverage.groups;start=$copy.Start;end=$copy.End})
    }
    return [pscustomobject]@{Repaired=($reports.Count -eq $pending.Count);Cues=$copies;RecoveredCueIndices=@($reports | ForEach-Object {$_.cueIndex});Recovery=$reports.ToArray()}
}

function Complete-PvsSubtitleReference {
    param($Selection,[object[]]$Words,[object[]]$Sources,[Parameter(Mandatory)][scriptblock]$RecognizeWindow,[scriptblock]$TestQuietWindow)
    $Words=@($Words | Where-Object {$null -ne $_})
    $output=New-Object System.Collections.Generic.List[object]
    $supplements=New-Object System.Collections.Generic.List[object]
    $empty=New-Object System.Collections.Generic.List[object]
    $quietRanges=New-Object System.Collections.Generic.List[object]
    $contextCovered=New-Object System.Collections.Generic.List[object]
    foreach($cue in $Selection.Cues){
        $copy=$cue.PSObject.Copy()
        if($cue.PSObject.Properties['CaptionTimingRevision'] -and $cue.CaptionTimingRevision -eq 'dtw-word-boundary-v1'){
            # The subtitle splitter consumes the recovered overlay, not the
            # original incomplete alignment. Use those same edges for gaps.
            $chapter=[int]$cue.Chapter
            if($chapter -lt 0 -or $chapter -ge $Sources.Count -or -not $cue.PSObject.Properties['CaptionStart'] -or -not $cue.PSObject.Properties['CaptionEnd']){throw 'SUBTITLE_REFERENCE_CAPTION_BOUNDS_INVALID'}
            $start=[double]$cue.CaptionStart;$end=[double]$cue.CaptionEnd
            if([double]::IsNaN($start) -or [double]::IsNaN($end) -or [double]::IsInfinity($start) -or [double]::IsInfinity($end) -or $start -lt [double]$Sources[$chapter].start-0.000001 -or $end -gt [double]$Sources[$chapter].end+0.000001 -or $end -le $start){throw 'SUBTITLE_REFERENCE_CAPTION_BOUNDS_INVALID'}
            $copy.Start=$start;$copy.End=$end
        }
        $output.Add($copy)
    }
    for($chapter=0;$chapter -lt $Sources.Count;$chapter++){
        $source=$Sources[$chapter]
        $known=@($output | Where-Object {[int]$_.Chapter -eq $chapter} | Sort-Object Start)
        for($index=1;$index -lt $known.Count;$index++){
            if($known[$index].Start -lt $known[$index-1].End-0.000001){throw 'SUBTITLE_REFERENCE_CAPTION_BOUNDS_OVERLAP'}
        }
        if(@($Selection.UnverifiedRanges | Where-Object {$_.sourceIndex -eq $chapter -and $_.end -le $_.start}).Count){
            # Collapsed timestamps cannot bound a local retry. Re-recognize
            # this source rather than invent a gap or silently lose speech.
            $known=@()
            for($index=$output.Count-1;$index -ge 0;$index--){if([int]$output[$index].Chapter -eq $chapter){$output.RemoveAt($index)}}
        }
        $heard=@($Words | Where-Object {[int]$_.Chapter -eq $chapter} | Sort-Object Start)
        $wordCursor=0
        $gaps=New-Object System.Collections.Generic.List[object]
        $cursor=[double]$source.start
        foreach($cue in $known){
            if([double]$cue.Start -gt $cursor){$gaps.Add([pscustomobject]@{Start=$cursor;End=[double]$cue.Start})}
            $cursor=[Math]::Max($cursor,[double]$cue.End)
        }
        if($cursor -lt [double]$source.end){$gaps.Add([pscustomobject]@{Start=$cursor;End=[double]$source.end})}
        foreach($gap in $gaps){
            $hints=@($Selection.UnverifiedRanges | Where-Object {$_.sourceIndex -eq $chapter -and $_.start -lt $gap.End-0.000001 -and $_.end -gt $gap.Start+0.000001})
            while($wordCursor -lt $heard.Count -and [double]$source.start+[double]$heard[$wordCursor].Start -lt $gap.Start-0.000001){$wordCursor++}
            $hasSpeech=$false
            for($word=$wordCursor;$word -lt $heard.Count;$word++){
                $item=$heard[$word]
                if([double]$source.start+[double]$item.Start -ge $gap.End){break}
                if([double]$source.start+[double]$item.End -le $gap.End+0.000001 -and [double]$item.End -gt [double]$item.Start){$hasSpeech=$true;break}
            }
            if($hints.Count -eq 0 -and -not $hasSpeech){continue}
            $indices=@($hints | ForEach-Object {$_.cueIndices})
            $report=[pscustomobject]@{sourceIndex=$chapter;start=$gap.Start;end=$gap.End;referenceCueIndices=$indices;captionCueCount=0}
            if($null -ne $TestQuietWindow -and (& $TestQuietWindow $source ([double]$gap.Start) ([double]$gap.End))){$quietRanges.Add($report);continue}
            $generated=@(& $RecognizeWindow $source ([double]$gap.Start) ([double]$gap.End) $chapter)
            if($generated.Count -eq 1 -and $generated[0].PSObject.Properties['CoveredByReferenceContext'] -and $generated[0].CoveredByReferenceContext){
                if(@($generated[0].Cues).Count){throw 'SUBTITLE_CONTEXT_COVERAGE_INVALID'}
                $contextCovered.Add($report);continue
            }
            $lastEnd=[double]$gap.Start
            foreach($cue in $generated){
                if([string]::IsNullOrWhiteSpace([string]$cue.Text) -or [int]$cue.Chapter -ne $chapter -or [double]::IsNaN([double]$cue.Start) -or [double]::IsNaN([double]$cue.End) -or [double]::IsInfinity([double]$cue.Start) -or [double]::IsInfinity([double]$cue.End) -or $cue.Start -lt $lastEnd-0.000001 -or $cue.End -gt $gap.End+0.000001 -or $cue.End -le $cue.Start){throw 'SUBTITLE_SUPPLEMENT_RESULT_INVALID'}
                $copy=$cue.PSObject.Copy()
                $copy | Add-Member -NotePropertyName RecognitionSupplement -NotePropertyValue $true -Force
                $output.Add($copy);$lastEnd=[double]$cue.End
            }
            $report.captionCueCount=$generated.Count
            if($generated.Count){$report.start=[double]$generated[0].Start;$report.end=[double]$generated[-1].End;$supplements.Add($report)}else{$empty.Add($report)}
        }
    }
    # Generated cue indices are independent of the original reference indices.
    # Unique indices are needed by subsequent DTW/numeric caption review stages.
    $ordered=@($output | Sort-Object Start,End)
    for($index=0;$index -lt $ordered.Count;$index++){
        $copy=$ordered[$index].PSObject.Copy()
        if(-not ($copy.PSObject.Properties['RecognitionSupplement'])){$copy | Add-Member -NotePropertyName ReferenceCueIndex -NotePropertyValue ([int]$copy.Index) -Force}
        $copy.Index=$index+1;$ordered[$index]=$copy
    }
    return [pscustomobject]@{Cues=$ordered;SupplementRanges=$supplements.ToArray();EmptyRanges=$empty.ToArray();QuietRanges=$quietRanges.ToArray();ContextCoveredRanges=$contextCovered.ToArray()}
}

function Align-PvsSubtitleReference {
    param([object[]]$Cues, [object[]]$Words, [object[]]$Sources, [bool]$CharacterMode = $false,[string]$Language='vi')
    $wordCount=0
    foreach ($cue in $Cues) { $wordCount+=@(Get-PvsSubtitleLexicalWords -Text ([string]$cue.Text) -CharacterMode $CharacterMode).Count }
    if ([long]$wordCount*[long]$Words.Count -gt 25000000) { throw 'SRT qua dai de can an toan trong mot lan. Hay chon tung vung/clip va SRT tuong ung, hoac dung che do tu nhan dien.' }
    if (-not $CharacterMode) {
        $aligned=@(Align-CuesToRecognizedWords -Cues $Cues -RecognizedWords $Words -VoiceClips $Sources)
        return @(Confirm-PvsSubtitleReferenceWords -Aligned $aligned -Words $Words -Sources $Sources -Language $Language)
    }
    $targets=New-Object System.Collections.Generic.List[string]
    $cueWordCounts=New-Object System.Collections.Generic.List[int]
    foreach ($cue in $Cues) {
        $tokens=@(Get-PvsSubtitleLexicalWords -Text ([string]$cue.Text) -CharacterMode $CharacterMode)
        $cueWordCounts.Add($tokens.Count)
        foreach ($token in $tokens) { $targets.Add($token) }
    }
    if ($targets.Count -eq 0 -or $Words.Count -eq 0) { throw 'SUBTITLE_NO_SPEECH_OR_TEXT' }
    $mapping=@(Get-SequentialWordMapping -TargetWords $targets.ToArray() -RecognizedWords $Words)
    $result=New-Object System.Collections.Generic.List[object]
    $cursor=0
    for ($cueIndex=0; $cueIndex -lt $Cues.Count; $cueIndex++) {
        $timings=New-Object System.Collections.Generic.List[object]
        $exact=0; $chapter=-1
        for ($wordIndex=0; $wordIndex -lt $cueWordCounts[$cueIndex]; $wordIndex++) {
            $mapped=[int]$mapping[$cursor+$wordIndex]
            if ($mapped -lt 0) { throw "SUBTITLE_REFERENCE_WORD_UNALIGNED:cue-$($cueIndex+1). Hay kiem tra SRT co dung noi dung cua vung dang chon khong." }
            $word=$Words[$mapped]
            if ($chapter -lt 0) { $chapter=[int]$word.Chapter }
            if ($chapter -ne [int]$word.Chapter) { throw "SUBTITLE_REFERENCE_CROSSES_SELECTION_GAP:cue-$($cueIndex+1)" }
            $offset=[double]$Sources[$chapter].start
            $matched=[string]$targets[$cursor+$wordIndex] -eq [string]$word.Text
            if ($matched) { $exact++ }
            $timings.Add([pscustomobject]@{ TargetWordIndex=$wordIndex; Text=$targets[$cursor+$wordIndex]; Start=$offset+[double]$word.Start; End=$offset+[double]$word.End; Chapter=$chapter; Exact=$matched })
        }
        $cursor+=$cueWordCounts[$cueIndex]
        if ($timings.Count -eq 0) { continue }
        $confidence=$exact/[double]$timings.Count
        if ($confidence -lt 0.55) { throw "SUBTITLE_REFERENCE_MISMATCH:cue-$($cueIndex+1). SRT khong khop du loi noi trong vung duoc chon." }
        $result.Add([pscustomobject]@{ Index=$cueIndex+1; Text=[string]$Cues[$cueIndex].Text; Start=$timings[0].Start; End=$timings[$timings.Count-1].End; Chapter=$chapter; Confidence=$confidence; WordTimings=$timings.ToArray() })
    }
    return $result.ToArray()
}

function Split-PvsCharacterCaptionCue {
    param($Cue, [int]$MaxCharacters, [double]$FrameRate)
    # Preserve the original punctuation and spacing; split CJK on character boundaries.
    $text=([string]$Cue.Text).Trim()
    $textUnits=@([regex]::Matches($text, '[\u3400-\u9fff\u3040-\u30ff\uac00-\ud7af][,;:.!?，。！？；：、]*|[^\s\u3400-\u9fff\u3040-\u30ff\uac00-\ud7af]+'))
    $ranges=New-Object System.Collections.Generic.List[object]
    $begin=0; $lastBoundary=0
    for ($index=0; $index -lt $textUnits.Count; $index++) {
        $match=$textUnits[$index]
        $candidateEnd=$match.Index+$match.Length
        if ($candidateEnd-$begin -gt $MaxCharacters -and $lastBoundary -gt $begin) {
            $ranges.Add([pscustomobject]@{ Start=$begin; End=$lastBoundary })
            $begin=$lastBoundary
        }
        if ($candidateEnd-$begin -gt $MaxCharacters) { throw 'SUBTITLE_WORD_EXCEEDS_CHARACTER_LIMIT' }
        $lastBoundary=$candidateEnd
        if ($match.Value -match '[,;:.!?，。！？；：、]$') { $ranges.Add([pscustomobject]@{Start=$begin;End=$candidateEnd}); $begin=$candidateEnd }
    }
    if ($begin -lt $text.Length) { $ranges.Add([pscustomobject]@{ Start=$begin; End=$text.Length }) }
    $parts=New-Object System.Collections.Generic.List[object]
    $wordCursor=0
    foreach ($range in $ranges) {
        $partText=$text.Substring($range.Start,$range.End-$range.Start).Trim()
        if (-not $partText) { continue }
        $count=@(Get-PvsSubtitleLexicalWords -Text $partText -CharacterMode $true).Count
        if ($count -eq 0) { continue }
        $start=if ($parts.Count -eq 0) { [double]$Cue.Start } else { ([double]$Cue.WordTimings[$wordCursor-1].End+[double]$Cue.WordTimings[$wordCursor].Start)/2.0 }
        $wordCursor+=$count
        $end=if ($wordCursor -ge $Cue.WordTimings.Count) { [double]$Cue.End } else { ([double]$Cue.WordTimings[$wordCursor-1].End+[double]$Cue.WordTimings[$wordCursor].Start)/2.0 }
        $startFrame=[int][Math]::Round($start*$FrameRate); $endFrame=[int][Math]::Round($end*$FrameRate)
        if ($endFrame -le $startFrame) { throw 'SUBTITLE_CHARACTER_INTERVAL_TOO_SHORT' }
        $parts.Add([pscustomobject]@{ Text=$partText; Start=$startFrame/$FrameRate; End=$endFrame/$FrameRate; PartIndex=$parts.Count+1; PartCount=0 })
    }
    foreach ($part in $parts) { $part.PartCount=$parts.Count }
    return $parts.ToArray()
}

function New-PvsStandaloneCaptions {
    param([object[]]$Cues, [object[]]$Sources, [object[]]$Silences, [int]$MaxCharacters, [double]$FrameRate, [bool]$CharacterMode = $false)
    $captions=New-Object System.Collections.Generic.List[object]
    foreach ($cue in $Cues) {
        $parts=if ($CharacterMode) { @(Split-PvsCharacterCaptionCue -Cue $cue -MaxCharacters $MaxCharacters -FrameRate $FrameRate) } else { @(Split-PvsVoiceAlignedCaptionCue -Cue $cue -MaxCharacters $MaxCharacters -FrameRate $FrameRate -VoiceSilences $Silences) }
        $source=$Sources[[int]$cue.Chapter]
        # Audio-only clip edges can be sample based. Caption edges must stay on
        # legal sequence frames INSIDE the selected range, not round beyond it.
        $firstFrame=[int][Math]::Ceiling([double]$source.start*$FrameRate-0.0000001)
        $lastFrame=[int][Math]::Floor([double]$source.end*$FrameRate+0.0000001)
        foreach ($part in $parts) { $captions.Add([pscustomobject]@{ Index=$captions.Count+1; SourceCueIndex=$(if($cue.PSObject.Properties['Index']){[int]$cue.Index}else{0}); Text=$part.Text; Start=[Math]::Max($firstFrame/$FrameRate,[double]$part.Start); End=[Math]::Min($lastFrame/$FrameRate,[double]$part.End); PartIndex=$part.PartIndex; PartCount=$part.PartCount; Chapter=$cue.Chapter;IndependentSpeechEdges=[bool]($part.PSObject.Properties['IndependentSpeechEdges'] -and $part.IndependentSpeechEdges) }) }
    }
    foreach ($sourceIndex in 0..($Sources.Count-1)) {
        $source=$Sources[$sourceIndex]
        $chapterCaptions=@($captions | Where-Object { $_.Chapter -eq $sourceIndex })
        if ($chapterCaptions.Count -eq 0) { continue }
        Add-PvsCaptionEdgePadding -Captions $chapterCaptions -FrameRate $FrameRate -TimelineEndFrame ([int][Math]::Floor([double]$source.end*$FrameRate+0.0000001))
        $chapterCaptions[0].Start=[Math]::Max([Math]::Ceiling([double]$source.start*$FrameRate-0.0000001)/$FrameRate,[double]$chapterCaptions[0].Start)
    }
    $previousEnd=-1.0
    foreach ($caption in $captions) {
        if ($caption.Text.Length -gt $MaxCharacters -or $caption.Text -match '[\r\n]' -or $caption.End -le $caption.Start -or $caption.Start -lt $previousEnd-0.000001) { throw 'SUBTITLE_OUTPUT_VALIDATION_FAILED' }
        $source=$Sources[[int]$caption.Chapter]
        if ($caption.Start -lt [double]$source.start-0.000001 -or $caption.End -gt [double]$source.end+0.000001) { throw 'SUBTITLE_OUTSIDE_SELECTED_RANGE' }
        $previousEnd=$caption.End
    }
    return $captions.ToArray()
}
