$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
. "$root\extension\engine\lib\CaptionOnly.ps1"
. "$root\extension\engine\lib\Srt.ps1"
. "$root\extension\engine\lib\AutoEditManualReview.ps1"
# Issue #26: synthetic wording, both manual text recovery entrypoints.
& {
    $cases=@(
        @{name='vowel';srt=@('Chú ếch nhún mình rất nhẹ.');asr='Chú ếch nhốn mình rất nhẹ.'},
        @{name='tone';srt=@('Các mô thoái hóa rất nhanh.');asr='Các mô thoai hóa rất nhanh.'},
        @{name='tone-other';srt=@('Chú ếch thờ ơ đứng đó.');asr='Chú ếch thở ơ đứng đó.'},
        @{name='tr-ch';srt=@('Chú ếch canh chừng đàn con.');asr='Chú ếch canh trừng đàn con.'},
        @{name='r-gi';srt=@('Chú ếch ăn giun mỗi ngày.');asr='Chú ếch ăn run mỗi ngày.'},
        @{name='tone-vat';srt=@('Đó là món ăn vặt ngon.');asr='Đó là món ăn vật ngon.'},
        @{name='d-r';srt=@('Chú ếch bò ra ngoài sân.');asr='Chú ếch bò da ngoài sân.'},
        @{name='two-cues';srt=@('Chú ếch đứng đó.','Nó canh chừng đàn con.');asr='Chú ếch đứng đó. Nó canh trừng đàn con.'},
        @{name='same-digits';srt=@('Có 12 con ăn giun hôm nay.');asr='Có 12 con ăn run hôm nay.'},
        @{name='distance-two';srt=@('Chú ếch abcd đứng đó.');asr='Chú ếch abxy đứng đó.'},
        @{name='dd-nfd';srt=@('Chú ếch đứng đây rất lâu.');asr="Chú ếch du$([char]0x031b)$([char]0x0301)ng đây rất lâu."},
        @{name='two-differences';srt=@('Chú ếch ăn giun mỗi ngày.');asr='Chú ếch ăn run mỗi ngài.';reject=$true},
        @{name='number';srt=@('Có 12 con ăn giun hôm nay.');asr='Có 13 con ăn giun hôm nay.';reject=$true},
        @{name='number-word';srt=@('Có a1 con ở ngoài sân.');asr='Có a2 con ở ngoài sân.';reject=$true},
        @{name='digit-in-different-word';srt=@('Có a1 con ở ngoài sân.');asr='Có b1 con ở ngoài sân.';reject=$true},
        @{name='two-cues-two-differences';srt=@('Chú ếch ăn vặt.','Nó thay da mỗi ngày.');asr='Chú ếch ăn vật. Nó thay ra mỗi ngày.';reject=$true},
        @{name='extra';srt=@('Chú ếch ăn giun mỗi ngày.');asr='Chú ếch ăn giun mỗi ngày nữa.';reject=$true},
        @{name='missing';srt=@('Chú ếch ăn giun mỗi ngày.');asr='Chú ếch ăn mỗi ngày.';reject=$true},
        @{name='short';srt=@('Ếch ăn giun.');asr='Ếch ăn run.';reject=$true},
        @{name='distance-three';srt=@('Chú ếch abcdef đứng đó.');asr='Chú ếch abcxzy đứng đó.';reject=$true},
        @{name='shorter-length';srt=@('Chú ếch a đứng đó.');asr='Chú ếch b đứng đó.';reject=$true},
        @{name='ambiguous';srt=@('Chú ếch ăn giun mỗi ngày.','Chú ếch ăn giun mỗi ngày.');asr='Chú ếch ăn run mỗi ngày.';reject=$true},
        @{name='ambiguous-different';srt=@('Chú ếch ăn giun mỗi ngày.','Chú ếch ăn dun mỗi ngày.');asr='Chú ếch ăn run mỗi ngày.';reject=$true},
        @{name='retained';srt=@('Chú ếch ăn giun mỗi ngày.');asr='Chú ếch ăn run mỗi ngày.';retained=@(1);reject=$true},
        @{name='ambiguous-retained';srt=@('Chú ếch ăn giun mỗi ngày.','Chú ếch ăn giun mỗi ngày.');asr='Chú ếch ăn run mỗi ngày.';retained=@(1);reject=$true},
        @{name='split-name';srt=@('Vùng Collao ở trên cao.');asr='Vùng Cô Lao ở trên cao.';reject=$true},
        @{name='outside';srt=@('Chú ếch ăn giun mỗi ngày.');asr='Chú ếch ăn run mỗi ngày.';outside=$true;reject=$true},
        @{name='outside-left';srt=@('Chú ếch ăn giun mỗi ngày.');asr='Chú ếch ăn run mỗi ngày.';outsideLeft=$true;reject=$true},
        @{name='not-owned';srt=@('Một câu hoàn toàn khác.');asr='Chú ếch ăn run mỗi ngày.';reject=$true},
        @{name='nonconsecutive';srt=@('Chú ếch đứng đó.','Nó canh chừng đàn con.');asr='Chú ếch đứng đó. Nó canh trừng đàn con.';gap=$true;reject=$true}
    )
    $failures=@();$checks=0
    foreach($path in @('manual','observed','observed-dtw')){foreach($case in $cases){
        $rs=@(for($i=0;$i -lt $case.srt.Count;$i++){[pscustomobject]@{Index=$i+1;Text=$case.srt[$i];Start=$i*3;End=($i+1)*3}})
        if($case.ContainsKey('gap')){$rs[1].Index=3}
        $kept=if($case.ContainsKey('retained')){@($case.retained)}else{@()}
        $cell=[pscustomobject]@{Text=$case.asr;Start=1.0;End=2.0;ReferenceCueIndices=@();CaptionTimingQuality='estimated';CaptionTimingRevision='fixture-estimated';WordTimings=@();RecognitionOriginalText='original recognition retained'}
        if($path -eq 'manual'){$cell.PSObject.Properties.Remove('RecognitionOriginalText')}
        if($case.ContainsKey('outside')){$cell.End=4.0}
        if($case.ContainsKey('outsideLeft')){$cell.Start=-1.0}
        $raw=@(ConvertTo-NormalizedWords $case.asr)
        $dtw=@(for($w=0;$w -lt $raw.Count;$w++){[pscustomobject]@{Text=$raw[$w];Start=1.0+$w*0.02;End=1.02+$w*0.02;Chapter=0;SubtitleTimingQuality='dtw';TargetWordIndex=$w;Exact=$true}})
        if($path -eq 'observed-dtw'){
            $cell|Add-Member CaptionWordTimings $dtw
            $cell.CaptionTimingQuality='dtw';$cell.CaptionTimingRevision='raw-dtw-cell-overlay-v1'
            $cell|Add-Member Chapter 0
        }
        $before=$cell|Select-Object Start,End,CaptionTimingQuality,CaptionTimingRevision,WordTimings,CaptionWordTimings|ConvertTo-Json -Depth 8 -Compress
        if($path -eq 'manual'){
            $ids=@(Restore-PvsManualReferenceCell $cell $rs $kept -BlockStart 0 -BlockEnd 3)
        }else{
            # An identical reference outside block ownership is harmless.
            $all=@($rs)+@([pscustomobject]@{Index=99;Text='Chú ếch ăn giun mỗi ngày.';Start=100;End=103})
            $others=@($kept|ForEach-Object {[pscustomobject]@{Index=$_}})
            $block=[pscustomobject]@{Index=1;ManualEditBlock=$true;ManualReferenceCueIndices=@($rs.Index);ManualCaptionCues=@($cell);Text=$cell.Text;Chapter=0;Start=0.0;End=3.0}
            $heard=@(if($path -eq 'observed-dtw'){$dtw})
            $ids=@(Restore-PvsObservedManualReferenceCells (@($block)+$others) $all $heard @([pscustomobject]@{start=0;end=3}))
        }
        $checks++
        if($case.ContainsKey('reject')){
            if($cell.Text -cne $case.asr -or $cell.ReferenceCueIndices.Count -or @($ids|Where-Object {$null -ne $_}).Count){$failures+="$path/$($case.name):rejected-cell-changed"}
        }else{
            if($cell.Text -cne ($case.srt -join ' ') -or ($cell.ReferenceCueIndices -join ',') -ne ($rs.Index -join ',') -or -not $cell.PSObject.Properties['ReferenceTextRecovery'] -or $cell.ReferenceTextRecovery -cne 'near-match-one-word'){$failures+="$path/$($case.name):SRT-or-provenance-missing"}
            $original=if($path -eq 'manual'){$case.asr}else{'original recognition retained'}
            if($cell.RecognitionOriginalText -cne $original){$failures+="$path/$($case.name):original-text-overwritten"}
        }
        if(($cell|Select-Object Start,End,CaptionTimingQuality,CaptionTimingRevision,WordTimings,CaptionWordTimings|ConvertTo-Json -Depth 8 -Compress) -cne $before){$failures+="$path/$($case.name):timing-changed"}
    }}
    if($failures.Count){throw ('NEAR_MATCH_REGRESSION_FAILED: '+($failures -join '; '))}
    Write-Host "NEAR_MATCH_OK:$checks cases across both restore paths; text-only recovery"
}
foreach($text in @('Đảo.','[music]','Tên Xkqz, mã 250.000 đang được đọc.')){
    $json=[pscustomobject]@{segments=@([pscustomobject]@{text=$text;start=0;end=2})}
    $plain=@((Convert-PvsReferenceRecognition $json 0).Words)
    $surface=@((Convert-PvsReferenceRecognition $json 0 -PreserveSurface).Words)
    if(($plain | ConvertTo-Json -Compress) -cne ($surface | Select-Object Text,Start,End,Chapter | ConvertTo-Json -Compress)){throw 'RECOGNITION_SURFACE_CHANGED_LEGACY_WORDS'}
    if((Join-PvsManualRecognitionSurface $surface) -cne $text){throw 'RECOGNITION_RAW_SURFACE_LOST'}
}
$texts=@('Mốc đầu có đủ ngữ cảnh.','Câu này trong SRT đã bị cắt một phần.','Mốc sau xác định đúng vị trí.','Câu thứ tư vẫn giữ nguyên.','Câu thứ năm vẫn giữ nguyên.','Câu thứ sáu vẫn giữ nguyên.','Câu cuối vẫn giữ nguyên.')
$cell=[pscustomobject]@{Text='những Engineer đến trái đất.';Start=1.0;End=2.0;ReferenceCueIndices=@()}
$cellRefs=@([pscustomobject]@{Index=49;Text='Những Engineer đến Trái Đất.'})
if((Restore-PvsManualReferenceCell $cell $cellRefs) -ne 49 -or $cell.Text -cne $cellRefs[0].Text -or $cell.Start -ne 1 -or $cell.End -ne 2 -or $cell.RecognitionOriginalText -cne 'những Engineer đến trái đất.'){throw 'COMPLETE_OBSERVED_CELL_TEXT_NOT_RETAINED_INDEPENDENTLY_OF_TIMING'}
foreach($fault in @('missing-prefix','missing-suffix','extra','different-number','ambiguous','already-retained')){
    $candidate=[pscustomobject]@{Text='những engineer đến trái đất.';Start=1.0;End=2.0;ReferenceCueIndices=@()};$candidates=$cellRefs;$retainedIndices=@()
    switch($fault){
        'missing-prefix' {$candidate.Text='Engineer đến Trái Đất.'}
        'missing-suffix' {$candidate.Text='Những Engineer đến.'}
        'extra' {$candidate.Text='Những Engineer đến Trái Đất rồi.'}
        'different-number' {$candidate.Text='Năm 2093.';$candidates=@([pscustomobject]@{Index=49;Text='Năm 2013.'})}
        'ambiguous' {$candidates=@($cellRefs[0],$cellRefs[0])}
        'already-retained' {$retainedIndices=@(49)}
    }
    if($null -ne (Restore-PvsManualReferenceCell $candidate $candidates $retainedIndices)){throw "UNPROVEN_CELL_TEXT_RESTORED:$fault"}
}
$refs=@(for($i=0;$i -lt $texts.Count;$i++){[pscustomobject]@{Index=$i+1;Text=$texts[$i];Start=$i*5.0;End=($i+1)*5.0}})
function New-ManualFixture([string]$Middle){
    $spoken=@($texts);$spoken[1]=$Middle
    $cursor=0.0
    $segments=@(foreach($text in $spoken){
        $count=@(ConvertTo-NormalizedWords $text).Count
        if($count){$end=$cursor+$count*0.2;[pscustomobject]@{text=$text;start=$cursor;end=$end};$cursor=$end}
    })
    $script:raw=[pscustomobject]@{segments=$segments}
    $script:words=@((Convert-PvsReferenceRecognition -Json $raw -Chapter 0 -PreserveSurface).Words)
    $script:sources=@([pscustomobject]@{start=10.0;end=10.0+$cursor})
    $script:aligned=@(Align-CuesToRecognizedWords $refs $words $sources)
    $script:edited=Resolve-PvsEditedReference $refs $words $sources {
        param($voice,$start,$end)
        foreach($w in $script:words){if($voice.start+$w.Start -ge $start-0.000001 -and $voice.start+$w.End -le $end+0.000001){$c=$w.PSObject.Copy();$c.Start+=$voice.start-$start;$c.End+=$voice.start-$start;$c}}
    }
    New-PvsAutoEditManualReview -Cues $refs -Aligned $aligned -Edited $edited -Sources $sources -MainVideo ([pscustomobject]@{start=0;end=35}) -FrameRate 30
}
# Separate -ml 1 packets retain text even when their timestamps cannot anchor
# a strict edit. The last lexical packet need not have the latest End.
& {
    $refs=@(for($i=0;$i -lt 3;$i++){[pscustomobject]@{Index=$i+1;Start=$i*5.0;End=($i+1)*5.0;Text=@('Opening anchor has enough unique words.','Middle window keeps its original words.','Closing anchor supplies different complete context.')[$i]}})
    $segments=@(for($i=0;$i -lt 3;$i++){
        $tokens=@($refs[$i].Text -split ' ')
        for($j=0;$j -lt $tokens.Count;$j++){
            $a=$i*5.0+$j*0.2;$b=$a+0.2
            if($i -eq 1){
                if($j -lt 3){$a=5.0;$b=if($j -lt 2){5.0}else{5.2}}
                if($j -ge 4){$a=5.8;$b=if($j -eq 4){6.6}else{5.8}}
            }
            [pscustomobject]@{text=$tokens[$j];offsets=[pscustomobject]@{from=$a*1000;to=$b*1000}}
        }
    })
    $words=@((Convert-PvsReferenceRecognition ([pscustomobject]@{transcription=$segments}) 0 -PreserveSurface).Words)
    $sources=@([pscustomobject]@{start=10;end=25})
    $aligned=@(Align-CuesToRecognizedWords $refs $words $sources)
    if([Math]::Abs($aligned[1].End-16.6) -gt 0.000001){throw "TIED_CUE_END_NOT_MAXIMUM:expected=16.6;actual=$($aligned[1].End)"}
    $edited=Resolve-PvsEditedReference $refs $words $sources {return}
    $manual=New-PvsAutoEditManualReview $refs $aligned $edited $sources ([pscustomobject]@{start=0;end=15}) 30
    if($null -eq $manual -or ($manual.Cues.Text -join ' ') -cne ($refs.Text -join ' ')){throw 'TIED_MANUAL_TEXT_ORDER_OR_SRT_RETENTION_LOST'}
    $middle=@($manual.Cues[0].ManualCaptionCues | Where-Object {$_.ReferenceCueIndices -contains 2})
    if($middle.Count -ne 1 -or [Math]::Abs($middle[0].End-16.6) -gt 0.000001){throw 'TIED_MANUAL_CELL_END_NOT_MAXIMUM'}
    if($edited.Resolved -or $edited.OmittedCueIndices.Count -or $manual.Cues[0].WordTimings.Count -or -not $manual.Cues[0].EditBoundaryReviewRequired){throw 'TIED_TEXT_RETENTION_PROMOTED_TIMING_OR_OMISSION'}
    $parts=@(Split-PvsManualReviewCaptionCue $manual.Cues[0] 42 30)
    $middleParts=@($parts | Where-Object ManualCaptionCellIndex -eq 1)
    if(($middleParts.Text -join ' ') -cne $refs[1].Text -or $middleParts[-1].EndFrame -ne 498 -or @($middleParts | Where-Object VoiceBoundaryAligned).Count){throw 'TIED_FINAL_CAPTION_LOST_TEXT_END_OR_ESTIMATED_STATUS'}
    Write-Host 'TIED_MANUAL_CAPTIONS_OK:SRT-exact-text;max-word-end;final-caption;estimated-only'
}
$actual='Tên Xkqz, mã 250.000 đang được đọc.'
$result=New-ManualFixture $actual
if($edited.Resolved -or $null -eq $result -or $result.Blocks.Count -ne 1 -or $result.Status -ne 'manual-review-pending'){throw 'BOUNDED_REVIEW_NOT_CREATED'}
$block=$result.Cues[0]
if(-not $block.ManualEditBlock -or -not $block.EditBoundaryReviewRequired -or $block.Confidence -ne 0 -or $block.WordTimings.Count -or ($block.ManualReferenceCueIndices -join ',') -ne '1,2,3'){throw 'MANUAL_BLOCK_AUTHORITY_INVALID'}
if($block.Text -cne ($texts[0]+' '+$actual+' '+$texts[2]) -or $block.Text.Contains($texts[1]) -or $result.PSObject.Properties['OmittedCueIndices']){throw 'MANUAL_BLOCK_LOST_RAW_TEXT_OR_RESTORED_REFERENCE'}
if($result.Blocks[0].pendingReferenceCueIndices -join ',' -ne '2' -or $result.Blocks[0].retainedReferenceCueIndices -join ',' -ne '1,3'){throw 'MANUAL_REVIEW_COVERAGE_METADATA_WRONG'}
$beforeWords=$words | ConvertTo-Json -Depth 12 -Compress
$beforeRefs=$refs | ConvertTo-Json -Depth 8 -Compress
$again=New-PvsAutoEditManualReview $refs $aligned $edited $sources ([pscustomobject]@{start=0;end=35}) 30
if(($words | ConvertTo-Json -Depth 12 -Compress) -cne $beforeWords -or ($refs | ConvertTo-Json -Depth 8 -Compress) -cne $beforeRefs){throw 'MANUAL_REVIEW_MUTATED_INPUT'}
$partial=New-ManualFixture 'Câu này trong SRT đã bị cắt.'
if($null -eq $partial -or $partial.Cues[0].Text.Contains('một phần')){throw 'PARTIAL_REFERENCE_SUFFIX_RESURRECTED'}
# Verified omissions still use the existing strict source-map route.
if($null -ne (New-ManualFixture '')){throw 'VERIFIED_OMISSION_ROUTED_THROUGH_MANUAL_REVIEW'}
$result=New-ManualFixture $actual
foreach($kind in @('source-overlap','source-outside','raw-nan','raw-backward','voice-outside','no-anchors','reordered','long-window','other-language')){
    $r=@($refs | ForEach-Object {$_.PSObject.Copy()});$e=$edited.PSObject.Copy();$e.Words=@($edited.Words | ForEach-Object {$_.PSObject.Copy()});$s=@($sources | ForEach-Object {$_.PSObject.Copy()});$lang='vi'
    switch($kind){
        'source-overlap' {$r[1].Start=2}
        'source-outside' {$r[-1].End=36}
        'raw-nan' {$e.Words[7].Start=[double]::NaN}
        'raw-backward' {$e.Words[7].Start=-1}
        'voice-outside' {$e.Words[7].End=500}
        'no-anchors' {foreach($w in $e.Words){$w.Text='khác'}}
        'reordered' {$first=@($e.Words | Where-Object {$_.Start -lt 1.2});$tail=@($e.Words | Where-Object {$_.Start -ge 1.2});$e.Words=@($tail+$first)}
        'long-window' {foreach($w in $e.Words){$w.Start*=20;$w.End*=20};$s[0].end=10+($s[0].end-10)*20}
        'other-language' {$lang='en'}
    }
    if($null -ne (New-PvsAutoEditManualReview -Cues $r -Aligned $aligned -Edited $e -Sources $s -MainVideo ([pscustomobject]@{start=0;end=35}) -FrameRate 30 -Language $lang)){throw "UNBOUNDED_OR_INVALID_MANUAL_REVIEW:$kind"}
}
# Execute the shipping planner, then both post-planning transformations. Native
# silence detection is the only stub; it deliberately offers cuts in the block.
. "$root\extension\engine\lib\DtwEditTrial.ps1"
. "$root\extension\engine\lib\SpeedMergeTrial.ps1"
$result=New-ManualFixture $actual
$testRoot=Join-Path $root '.tmp-manual-review-tests'
$temp=Join-Path $testRoot ([guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path "$temp\engine\lib","$temp\engine\runtime" -Force | Out-Null
try {
    $engine=Join-Path $temp 'engine'
    Copy-Item -LiteralPath "$root\extension\engine\build-sentence-plan.ps1" -Destination $engine
    Get-ChildItem -LiteralPath "$root\extension\engine\lib" -File | Copy-Item -Destination "$engine\lib"
    foreach($name in @('runtime-lock.json','cuda-lock.json')){Copy-Item -LiteralPath "$root\extension\engine\$name" -Destination $engine}
    Set-Content -LiteralPath "$engine\lib\Native.ps1" -Encoding ASCII -Value '. "$PSScriptRoot\Security.ps1"; . "$PSScriptRoot\AudioCache.ps1"; function Invoke-NativeCapture {param($FilePath,$Arguments);[pscustomobject]@{ExitCode=0;Output="silence_start: 1.1`nsilence_end: 1.3`nsilence_start: 3.1`nsilence_end: 3.3"}}'
    Set-Content -LiteralPath "$engine\runtime\engine.json" -Encoding ASCII -Value '{"ffmpeg":"fixture"}'
    $wav=Join-Path $temp 'voice.wav';Set-Content -LiteralPath $wav -Value '' -Encoding ASCII
    $voices=@([pscustomobject]@{start=$sources[0].start;end=$sources[0].end;path=$wav;speedPercent=100;name='fixture';inPoint=0})
    [ordered]@{voiceChapterCount=1;cues=$result.Cues;autoEditManualReviewBlocks=$result.Blocks;referenceCueCount=$refs.Count} | ConvertTo-Json -Depth 15 | Set-Content -LiteralPath "$temp\alignment-result.json" -Encoding UTF8
    $job=@{outputFolder=$temp;speedWarningMinPercent=70;speedWarningMaxPercent=130;algorithm=@{useWhisperCache=$false};sequence=@{frameRate=30;sequenceId='manual';name='manual';mainVideoClip=@{start=0;end=35};voices=$voices;linkedAudio=@();voiceTrackIndex=1}}
    $jobPath=Join-Path $temp 'job.json';$job | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $jobPath -Encoding UTF8
    & "$engine\build-sentence-plan.ps1" -JobPath $jobPath | Out-Null
    $plan=Get-Content "$temp\sentence-edit-plan.json" -Raw -Encoding UTF8 | ConvertFrom-Json
    if(@($plan.markers | Where-Object Owner -eq 'A2').Count){throw 'MANUAL_PROXY_CONFIDENCE_CREATED_FALSE_VOICE_MARKER'}
    Assert-PvsManualReviewPlan $plan
    $candidate=Get-PvsSpeedMergeTrial $plan
    Assert-PvsManualReviewPlan $candidate
    Assert-PvsTrialPlanConservation $plan $candidate | Out-Null
    $expected=$texts[0]+' '+$actual+' '+($texts[2..6] -join ' ')
    $srt=@(Read-SrtFile $plan.captionSrtPath)
    if(($srt.Text -join ' ') -cne $expected -or ($candidate.captions.Text -join ' ') -cne $expected){throw 'MANUAL_FINAL_CAPTION_LOSS_OR_REFERENCE_RESURRECTION'}
    $rows=@(Get-PvsDtwBoundaryTrial -Cues $result.Cues -Voices $voices -Silences @() -FrameRate 30 -LegacyFinder {return $null})
    if($rows[0].Status -ne 'rejected' -or $rows[0].Reason -ne 'reference-text-recovery-review'){throw 'MANUAL_BLOCK_EXPOSED_TO_DTW_CUT'}
    foreach($fault in @('picture','voice','text','timing','omission','metadata')){
        $bad=$plan | ConvertTo-Json -Depth 25 | ConvertFrom-Json
        switch($fault){
            picture {$bad.segments[0].SourceEndFrame=1}
            voice {$bad.segments[0].OriginalVoiceEndFrame=1}
            text {$bad.captions[0].Text='lost'}
            timing {$bad.captions[0].VoiceBoundaryAligned=$true}
            omission {$bad | Add-Member omittedReferenceCueIndices @(2)}
            metadata {$bad.manualReviewBlocks[0].status='complete'}
        }
        $failed=$false
        try{if($fault -eq 'metadata'){Assert-PvsTrialPlanConservation $plan $bad | Out-Null}else{Assert-PvsManualReviewPlan $bad}}catch{$failed=$true}
        if(-not $failed){throw "MANUAL_PLAN_TAMPER_ACCEPTED:$fault"}
    }
    $result.Cues[-1].Confidence=0.4
    [ordered]@{voiceChapterCount=1;cues=$result.Cues;autoEditManualReviewBlocks=$result.Blocks;referenceCueCount=$refs.Count} | ConvertTo-Json -Depth 15 | Set-Content -LiteralPath "$temp\alignment-result.json" -Encoding UTF8
    & "$engine\build-sentence-plan.ps1" -JobPath $jobPath | Out-Null
    $weakPlan=Get-Content "$temp\sentence-edit-plan.json" -Raw -Encoding UTF8 | ConvertFrom-Json
    if(-not @($weakPlan.markers | Where-Object Owner -eq 'A2').Count){throw 'REAL_LOW_CONFIDENCE_VOICE_MARKER_SUPPRESSED'}
    if(-not @($weakPlan.markers | Where-Object {$_.Owner -eq 'A2' -and $_.Comments -match 'confidence=0[.,]4'}).Count){throw 'MANUAL_PROXY_CONFIDENCE_LEAKED_INTO_REAL_RECOGNITION_MARKER'}
} finally {
    $full=[IO.Path]::GetFullPath($temp)
    if(-not $full.StartsWith(([IO.Path]::GetFullPath($testRoot).TrimEnd('\')+'\'),[StringComparison]::OrdinalIgnoreCase)){throw 'UNSAFE_TEST_CLEANUP'}
    Remove-Item -LiteralPath $full -Recurse -Force
}
Write-Host 'AUTO_EDIT_MANUAL_REVIEW_OK:bounded;raw-surface;matched-SRT;partial-cut-no-resurrection;strict-omission-unchanged;source-offset;immutable;invalid-bounds;final-SRT;DTW-speed-merge;tamper-rejected'
