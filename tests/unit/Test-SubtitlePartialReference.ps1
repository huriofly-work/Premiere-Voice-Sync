$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$root=Resolve-Path (Join-Path $PSScriptRoot '..\..')
. "$root\extension\engine\lib\Srt.ps1"
. "$root\extension\engine\lib\Alignment.ps1"
. "$root\extension\engine\lib\CaptionOnly.ps1"
. "$root\extension\engine\lib\SubtitleTiming.ps1"
$texts=@('alpha bravo charlie delta echo foxtrot.','golf hotel india juliet kilo lima sierra tango uniform victor.','mike november oscar papa quebec romeo.')
$reference=@(for($i=0;$i -lt 3;$i++){[pscustomobject]@{Index=$i+1;Text=$texts[$i];Start=900+$i*3;End=903+$i*3}})
$tokens=@(foreach($cue in $reference){ConvertTo-NormalizedWords $cue.Text})
$script:sampleSource=@([pscustomobject]@{start=10.0;end=14.4})
function New-SampleWords([int[]]$Missing=@(),[hashtable]$Changed=@{},[switch]$Compressed){
    $position=0
    for($i=0;$i -lt $tokens.Count;$i++){
        if($Missing -contains $i){continue}
        $slot=if($Compressed){$position}else{$i};$position++
        [pscustomobject]@{Text=$(if($Changed.ContainsKey($i)){$Changed[$i]}else{$tokens[$i]});Start=$slot*0.2;End=($slot+1)*0.2;Chapter=0}
    }
}
function Select-Sample([object[]]$Heard,[object[]]$Reference=$reference){
    $script:sampleHeard=$Heard
    Select-PvsSubtitleReference -Cues $Reference -Words $Heard -Sources $script:sampleSource -AllowAudioOutsideReference -SkipUnverifiedCues -AllowUnmatchedRanges -AllowEditedReference -RecognizeReferenceWindow {
        param($source,$start,$end)
        foreach($w in $script:sampleHeard){
            if($source.start+$w.Start -ge $start-0.000001 -and $source.start+$w.End -le $end+0.000001){[pscustomobject]@{Text=$w.Text;Start=$source.start+$w.Start-$start;End=$source.start+$w.End-$start;Chapter=0}}
        }
    }
}
$before=$reference | ConvertTo-Json -Depth 8 -Compress
foreach($missing in @(@(9),@(9,10))){
    $heard=@(New-SampleWords -Missing $missing)
    $selection=Select-Sample $heard
    if(($selection.Cues.Index -join ',') -ne '1,2,3' -or $selection.SkippedCueCount -or ($selection.PartialReferenceCueIndices -join ',') -ne '2'){throw 'SMALL_ASR_OMISSION_DISCARDED_SRT'}
    $middle=$selection.Cues[1]
    if($middle.Text -cne $texts[1] -or -not $middle.ReferenceReviewRequired -or $middle.WordTimings.Count -ne 10-$missing.Count){throw 'TEXT_OR_OBSERVED_TIMING_CHANGED'}
    if(Test-PvsSubtitleDtwCue $middle @{}){throw 'PARTIAL_TIMING_CLAIMED_AS_DTW_VERIFIED'}
    $completed=Complete-PvsSubtitleReference $selection $selection.RecognitionWords $script:sampleSource {throw 'MOSTLY_MATCHED_SENTENCE_SENT_TO_SUPPLEMENT'}
    if($completed.SupplementRanges.Count -or $completed.Cues[1].Text -cne $texts[1] -or $completed.Cues[1].ReferenceCueIndex -ne 2){throw 'SRT_REPLACED_AFTER_COMPLETION'}
    $captions=@(New-PvsStandaloneCaptions $completed.Cues $script:sampleSource @() 20 30)
    $captionTokens=@(foreach($caption in $captions){ConvertTo-NormalizedWords $caption.Text})
    if(($captionTokens -join '|') -cne ($tokens -join '|')){throw 'CAPTION_SPLITTING_LOST_RETAINED_WORDS'}
    # Shared proof must still refuse to authorize picture removal/restoration.
    if($selection.EditedReference.Resolved -or $selection.EditedReference.OmittedCueIndices.Count -or ($selection.EditedReference.Cues.Index -join ',') -ne '1,3'){throw 'SUBTITLE_POLICY_CHANGED_SHARED_EDIT_PROOF'}
}
$changed=Select-Sample @(New-SampleWords -Changed @{9='wrong'})
if(($changed.Cues.Index -join ',') -ne '1,2,3' -or -not $changed.Cues[1].ReferenceReviewRequired){throw 'SINGLE_ASR_SUBSTITUTION_DISCARDED_SRT'}
# Fully timed matches use no partial-review flag.
$exact=Select-Sample @(New-SampleWords)
if($exact.Cues.Count -ne 3 -or @($exact.Cues | Where-Object {$_.PSObject.Properties['SubtitleReferencePartialMatch']}).Count){throw 'EXACT_REFERENCE_REGRESSION'}
# Sentence identity now retains SRT through a few ASR omissions/insertions,
# including compressed timestamps and missing edges. Whole-cue omission still
# follows the unchanged shared edit proof and must never be restored.
foreach($case in @('compressed','prefix','suffix','many','omitted','additional')){
    $heard=switch($case){
        compressed {@(New-SampleWords -Missing @(9) -Compressed)}
        prefix {@(New-SampleWords -Missing @(6))}
        suffix {@(New-SampleWords -Missing @(15))}
        many {@(New-SampleWords -Missing @(8,9,10))}
        omitted {@(New-SampleWords -Missing @(6..15) -Compressed)}
        additional {
            $base=@(New-SampleWords -Changed @{9='wrong'})
            $base[9].End-=0.1
            @($base+[pscustomobject]@{Text='extra';Start=1.9;End=2.0;Chapter=0} | Sort-Object Start)
        }
    }
    $selection=Select-Sample $heard
    $middle=@($selection.Cues | Where-Object Index -eq 2)
    if($case -eq 'omitted'){
        if($middle.Count){throw 'WHOLE_OMITTED_CUE_RESTORED'}
    }elseif($middle.Count -ne 1 -or $middle[0].Text -cne $texts[1] -or -not $middle[0].SubtitleReferencePartialMatch){throw "IDENTIFIED_SENTENCE_REPLACED_BY_ASR:$case"}
}
# No exact island: the legacy selection path also permits bounded partial
# matches instead of demanding 100 percent word coverage.
$heard=@(New-SampleWords -Changed @{2='one';9='two';18='three'})
$legacy=Select-Sample $heard
if($legacy.Cues.Count -ne 3 -or @($legacy.Cues | Where-Object ReferenceReviewRequired).Count -ne 3){throw 'LEGACY_PATH_STILL_REQUIRES_EXACT_SENTENCES'}
# Same source text appearing twice is not a reliable partial-match candidate.
$duplicate=$reference[1].PSObject.Copy();$duplicate.Index=4
$repeated=Select-Sample @(New-SampleWords -Missing @(9)) @($reference[0],$reference[1],$duplicate,$reference[2])
if(@($repeated.Cues | Where-Object {$_.Index -in @(2,4)}).Count){throw 'REPEATED_TEXT_RESTORED_AMBIGUOUSLY'}
if(($reference | ConvertTo-Json -Depth 8 -Compress) -cne $before){throw 'SOURCE_SRT_MUTATED'}
$script:sampleSource=@([pscustomobject]@{start=20.0;end=24.4})
$shifted=Select-Sample @(New-SampleWords -Missing @(9))
if($shifted.Cues[1].Start -ne 21.2 -or $shifted.Cues[1].End -ne 23.2){throw 'PARTIAL_REFERENCE_OFFSET_APPLIED_INCORRECTLY'}
foreach($fault in @('nan','overlap','outside')){
    $bad=$shifted.Cues[1].PSObject.Copy()
    $bad.WordTimings=@($bad.WordTimings | ForEach-Object {$_.PSObject.Copy()})
    switch($fault){nan {$bad.WordTimings[0].Start=[double]::NaN};overlap {$bad.WordTimings[1].Start=$bad.WordTimings[0].Start};outside {$bad.End=25}}
    if(Test-PvsSubtitlePartialReferenceCue $bad $script:sampleHeard $script:sampleSource){throw "INVALID_PARTIAL_REFERENCE_TIMING_ACCEPTED:$fault"}
}
$script:sampleSource=@([pscustomobject]@{start=0.0;end=1.0},[pscustomobject]@{start=20.0;end=24.4})
$heard=@(New-SampleWords -Missing @(9));foreach($w in $heard){$w.Chapter=1}
$secondSource=Select-Sample $heard
if($secondSource.Cues[1].Chapter -ne 1 -or $secondSource.Cues[1].Start -ne 21.2){throw 'PARTIAL_REFERENCE_WRONG_SOURCE_CHAPTER'}
# Two adjacent unresolved sentences: retain only the mostly matching one and
# keep supplementation/reason metadata for the genuinely different neighbor.
$texts=@($texts[0],$texts[1],'whiskey xray yankee zulu azure beige coral denim emerald fuchsia.',$texts[2])
$reference=@(for($i=0;$i -lt 4;$i++){[pscustomobject]@{Index=$i+1;Text=$texts[$i];Start=900+$i*3;End=903+$i*3}})
$tokens=@(foreach($cue in $reference){ConvertTo-NormalizedWords $cue.Text})
$script:sampleSource=@([pscustomobject]@{start=20.0;end=26.4})
$mixed=Select-Sample @(New-SampleWords -Missing @(9) -Changed @{18='changeda';19='changedb';20='changedc';21='changedd'})
if(($mixed.Cues.Index -join ',') -ne '1,2,4' -or ($mixed.SkippedCues.cueIndex -join ',') -ne '3'){throw 'MIXED_UNRESOLVED_BLOCK_DISCARDED_GOOD_SRT'}
$completed=Complete-PvsSubtitleReference $mixed $mixed.RecognitionWords $script:sampleSource {
    param($source,$start,$end,$chapter)
    [pscustomobject]@{Index=1;Text='Actual different speech.';Start=$start;End=$end;Chapter=$chapter;WordTimings=@()}
}
if($completed.SupplementRanges.Count -ne 1 -or ($completed.SupplementRanges[0].referenceCueIndices -join ',') -ne '3' -or $completed.Cues[1].Text -cne $texts[1]){throw 'MIXED_SUPPLEMENT_METADATA_OR_RETAINED_TEXT_WRONG'}
Write-Host 'SUBTITLE_PARTIAL_REFERENCE_OK:one,two-missing;substitution;caption-text;review;no-fake-timing;exact;compressed-cut;edges;major-mismatch;omitted;additional;legacy;repeated;shared-edit-proof;offset;invalid-timing;chapters;mixed-block'
