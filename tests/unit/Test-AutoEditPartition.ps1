$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
. "$root\extension\engine\lib\CaptionOnly.ps1"
. "$root\extension\engine\lib\Srt.ps1"
. "$root\extension\engine\lib\AutoEditManualReview.ps1"
. "$root\extension\engine\lib\DtwEditTrial.ps1"
. "$root\extension\engine\lib\SpeedMergeTrial.ps1"
$raw=@([pscustomobject]@{Text='one';Start=0.1;End=1.2;Chapter=0;RecognitionSurfaceText='One.'})
$bounded=@(ConvertTo-PvsBoundedEditWords $raw 1.0 0.9)
if($bounded.Count -ne 1 -or [Math]::Abs($bounded[0].Start-0.09) -gt 0.000001 -or $bounded[0].End -ne 1 -or $raw[0].End -ne 1.2 -or $bounded[0].RecognitionSurfaceText -cne 'One.'){throw 'PHYSICAL_BOUND_MUTATED_PACKET_OR_LOST_SURFACE'}
foreach($bad in @([double]::NaN,[double]::PositiveInfinity,-1)){
    $w=$raw[0].PSObject.Copy();$w.Start=$bad;$failed=$false
    try{ConvertTo-PvsBoundedEditWords @($w) 1 | Out-Null}catch{$failed=$true}
    if(-not $failed){throw 'INVALID_PRIMARY_TIMESTAMP_ACCEPTED'}
}
function New-PartitionFixture([switch]$Multi,[switch]$Unbounded,[switch]$Preserve){
    $script:refs=@(for($i=0;$i -lt 9;$i++){[pscustomobject]@{Index=$i+1;Start=$i*4.0;End=($i+1)*4.0;Text=('Anchor token'+[char](97+$i)+' provides unique context here.')}})
    $script:spoken=@(for($i=0;$i -lt 9;$i++){if($i%2 -or ($Unbounded -and $i -gt 0 -and $i -lt 8)){'Different surface'+[char](97+$i)+' remains present here.'}else{$refs[$i].Text}})
    $script:sources=@(if($Multi){@([pscustomobject]@{start=10.0;end=22.0},[pscustomobject]@{start=22.0;end=46.0})}else{@([pscustomobject]@{start=10.0;end=46.0})})
    $script:words=@(for($ch=0;$ch -lt $sources.Count;$ch++){
        $indices=if($Multi){if($ch -eq 0){0..2}else{3..8}}else{0..8}
        $segments=@(for($j=0;$j -lt $indices.Count;$j++){[pscustomobject]@{text=$spoken[$indices[$j]];start=$j*4.0;end=($j+1)*4.0}})
        (Convert-PvsReferenceRecognition ([pscustomobject]@{segments=$segments}) $ch -PreserveSurface).Words
    })
    $script:aligned=@(Align-CuesToRecognizedWords $refs $words $sources)
    $script:edited=[pscustomobject]@{Resolved=$false;Words=$words}
    New-PvsAutoEditManualReview $refs $aligned $edited $sources ([pscustomobject]@{start=0;end=36}) 30 -PreserveRecognitionFailures:$Preserve
}
$single=New-PartitionFixture
if($null -eq $single -or $single.Blocks.Count -ne 2){throw 'CONNECTED_WINDOWS_NOT_BOUNDED'}
if(($single.Cues.ManualReferenceCueIndices -join ',') -ne '1,2,3,4,5,6,7,8,9'){throw 'SHARED_ANCHOR_DUPLICATED_OR_LOST'}
if($single.Blocks[0].end -ne $single.Blocks[1].start -or $single.Blocks[0].sourceEnd -ne $single.Blocks[1].sourceStart){throw 'PARTITION_GAP_OR_OVERLAP'}
foreach($block in $single.Blocks){if($block.end-$block.start -gt 30 -or $block.cueIndices.Count -gt 40){throw 'PARTITION_WEAKENED_LIMIT'}}
$multi=New-PartitionFixture -Multi
if($null -eq $multi -or @($multi.Blocks.chapter | Select-Object -Unique).Count -ne 2){throw 'PROVEN_CHAPTER_EDGE_REFUSED'}
$snapshot=$words | ConvertTo-Json -Depth 12 -Compress
$again=New-PvsAutoEditManualReview $refs $aligned $edited $sources ([pscustomobject]@{start=0;end=36}) 30
if(($words | ConvertTo-Json -Depth 12 -Compress) -cne $snapshot){throw 'PARTITION_MUTATED_RECOGNITION'}
$badSources=@($sources | ForEach-Object {$_.PSObject.Copy()});$badSources[1].start=21
if($null -ne (New-PvsAutoEditManualReview $refs $aligned $edited $badSources ([pscustomobject]@{start=0;end=36}) 30)){throw 'OVERLAPPING_CHAPTERS_ACCEPTED'}
$bad=$edited.PSObject.Copy();$bad.Words=@($words | ForEach-Object {$_.PSObject.Copy()})
@($bad.Words | Where-Object Chapter -eq 0)[-1].Text='unknown'
$failure=$null
if($null -ne (New-PvsAutoEditManualReview $refs $aligned $bad $sources ([pscustomobject]@{start=0;end=36}) 30 -Failure ([ref]$failure)) -or $failure.reason -ne 'chapter-edge-unverified'){throw 'UNKNOWN_CHAPTER_SUFFIX_ASSIGNED_TO_NEXT_FILE'}
$null=New-PartitionFixture
$bad=$edited.PSObject.Copy();$bad.Words=@($words | ForEach-Object {$_.PSObject.Copy()});$bad.Words[6].End=29
if($null -ne (New-PvsAutoEditManualReview $refs $aligned $bad $sources ([pscustomobject]@{start=0;end=36}) 30)){throw 'EARLIER_TOKEN_CROSSING_PARTITION_SILENTLY_LOST'}
# Oversized region without an internal exact anchor remains blocked.
$null=New-PartitionFixture
foreach($w in $edited.Words){if($w.Start -ge 4 -and $w.End -le 32){$w.Text='unknown'}}
$failure=$null
if($null -ne (New-PvsAutoEditManualReview $refs $aligned $edited $sources ([pscustomobject]@{start=0;end=36}) 30 -Failure ([ref]$failure)) -or $failure.reason -ne 'manual-window-limit'){throw 'UNANCHORED_LONG_WINDOW_ACCEPTED'}
$preserved=New-PartitionFixture -Unbounded -Preserve
if($null -eq $preserved -or -not @($preserved.Blocks | Where-Object {$_.recognitionFailurePreserved -and $_.end-$_.start -gt 30}).Count){throw 'RECOGNITION_FAILURE_STILL_ABORTS_WORKFLOW'}
if(($preserved.Cues.Text -join ' ') -cne ($spoken -join ' ')){throw 'LONG_PRESERVATION_LOST_RAW_TEXT_OR_RESTORED_REFERENCE'}
# Genuine extra speech at both chapter edges cannot be dropped by a known cue.
$null=New-PartitionFixture
$prefix=(Convert-PvsReferenceRecognition ([pscustomobject]@{segments=@([pscustomobject]@{text='Extra opening words.';start=0;end=1})}) 0 -PreserveSurface).Words
$suffix=(Convert-PvsReferenceRecognition ([pscustomobject]@{segments=@([pscustomobject]@{text='Extra closing words.';start=37;end=38})}) 0 -PreserveSurface).Words
foreach($w in $words){$w.Start+=1;$w.End+=1};$sources[0].end=48
$edited.Words=@($prefix)+$words+@($suffix)
$edges=New-PvsAutoEditManualReview $refs $aligned $edited $sources ([pscustomobject]@{start=0;end=36}) 30
if($null -eq $edges -or -not $edges.Cues[0].Text.StartsWith('Extra opening words.') -or -not $edges.Cues[-1].Text.EndsWith('Extra closing words.')){throw 'CHAPTER_EDGE_EXTRA_SPEECH_LOST'}
# Run the shipping planner and speed merge with several blocks and chapters.
$result=New-PartitionFixture -Multi
$testRoot=Join-Path $root '.tmp-auto-partition-tests';$temp=Join-Path $testRoot ([guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path "$temp\engine\lib","$temp\engine\runtime" -Force | Out-Null
try{
    $engine=Join-Path $temp 'engine'
    Copy-Item "$root\extension\engine\build-sentence-plan.ps1" $engine
    Get-ChildItem "$root\extension\engine\lib" -File | Copy-Item -Destination "$engine\lib"
    foreach($name in @('runtime-lock.json','cuda-lock.json')){Copy-Item "$root\extension\engine\$name" $engine}
    Set-Content "$engine\lib\Native.ps1" -Encoding ASCII -Value '. "$PSScriptRoot\Security.ps1"; . "$PSScriptRoot\AudioCache.ps1"; function Invoke-NativeCapture {param($FilePath,$Arguments);[pscustomobject]@{ExitCode=0;Output=""}}'
    Set-Content "$engine\runtime\engine.json" -Encoding ASCII -Value '{"ffmpeg":"fixture"}'
    $wav=Join-Path $temp 'voice.wav';Set-Content $wav '' -Encoding ASCII
    $voices=@(foreach($s in $sources){[pscustomobject]@{start=$s.start;end=$s.end;path=$wav;speedPercent=100;name='fixture';inPoint=0}})
    @{voiceChapterCount=2;cues=$result.Cues;autoEditManualReviewBlocks=$result.Blocks;referenceCueCount=9} | ConvertTo-Json -Depth 18 | Set-Content "$temp\alignment-result.json" -Encoding UTF8
    $job=@{outputFolder=$temp;speedWarningMinPercent=70;speedWarningMaxPercent=130;algorithm=@{useWhisperCache=$false};sequence=@{frameRate=30;sequenceId='partition';name='partition';mainVideoClip=@{start=0;end=36};voices=$voices;linkedAudio=@();voiceTrackIndex=1}}
    $job | ConvertTo-Json -Depth 12 | Set-Content "$temp\job.json" -Encoding UTF8
    & "$engine\build-sentence-plan.ps1" -JobPath "$temp\job.json" | Out-Null
    $plan=Get-Content "$temp\sentence-edit-plan.json" -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-PvsManualReviewPlan $plan
    $candidate=Get-PvsSpeedMergeTrial $plan
    Assert-PvsManualReviewPlan $candidate
    Assert-PvsTrialPlanConservation $plan $candidate | Out-Null
    $srt=@(Read-SrtFile $plan.captionSrtPath)
    if(($srt.Text -join ' ') -cne ($spoken -join ' ') -or ($candidate.captions.Text -join ' ') -cne ($spoken -join ' ')){throw 'PARTITION_FINAL_TEXT_LOST_OR_RESTORED'}
    foreach($c in $result.Cues){if($c.PSObject.Properties['ManualEditBlock'] -and $c.ManualEditBlock -and ($c.WordTimings.Count -or -not $c.EditBoundaryReviewRequired)){throw 'PARTITION_TIMING_PROMOTED'}}
    $result=New-PartitionFixture -Unbounded -Preserve
    $voices=@([pscustomobject]@{start=$sources[0].start-0.1;end=$sources[0].end+0.1;path=$wav;speedPercent=100;name='fixture';inPoint=0})
    @{voiceChapterCount=1;cues=$result.Cues;autoEditManualReviewBlocks=$result.Blocks;referenceCueCount=9} | ConvertTo-Json -Depth 18 | Set-Content "$temp\alignment-result.json" -Encoding UTF8
    $job.sequence.voices=$voices;$job | ConvertTo-Json -Depth 12 | Set-Content "$temp\job.json" -Encoding UTF8
    & "$engine\build-sentence-plan.ps1" -JobPath "$temp\job.json" | Out-Null
    $plan=Get-Content "$temp\sentence-edit-plan.json" -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-PvsManualReviewPlan $plan
    $candidate=Get-PvsSpeedMergeTrial $plan
    Assert-PvsManualReviewPlan $candidate
    Assert-PvsTrialPlanConservation $plan $candidate | Out-Null
    if(($candidate.captions.Text -join ' ') -cne ($spoken -join ' ')){throw 'PRESERVATION_FINAL_CAPTION_TEXT_LOST'}
    $speech=@($candidate.segments | Where-Object Kind -eq 'retime')
    if($speech[0].OriginalVoiceStartFrame -ne [int][Math]::Round($voices[0].start*30) -or $speech[-1].OriginalVoiceEndFrame -ne [int][Math]::Round($voices[0].end*30)){throw 'PRESERVATION_SHAVED_CHAPTER_EDGES'}
}finally{
    $full=[IO.Path]::GetFullPath($temp)
    if(-not $full.StartsWith(([IO.Path]::GetFullPath($testRoot).TrimEnd('\')+'\'),[StringComparison]::OrdinalIgnoreCase)){throw 'UNSAFE_TEST_CLEANUP'}
    Remove-Item -LiteralPath $full -Recurse -Force
}
Write-Host 'AUTO_EDIT_PARTITION_OK:physical-bounds;immutable;shared-anchor-once;chapter-proof;unknown-suffix-blocked;30s-limit;extra-edge-speech;final-SRT;speed-conservation'
