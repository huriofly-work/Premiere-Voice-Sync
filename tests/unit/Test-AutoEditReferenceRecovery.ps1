$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
. "$PSScriptRoot\..\..\extension\engine\lib\CaptionOnly.ps1"
. "$PSScriptRoot\..\..\extension\engine\lib\DtwEditTrial.ps1"
$texts=@('alpha bravo charlie delta echo foxtrot.','Phần lớn trong số đó là những loài có một không hai.','golf hotel india juliet kilo lima.')
$cues=@(for($i=0;$i -lt $texts.Count;$i++){[pscustomobject]@{Index=$i+1;Text=$texts[$i];Start=$i*10.0;End=($i+1)*10.0}})
function New-RecoveryWords([string]$Middle){
    $tokens=@(ConvertTo-NormalizedWords ($texts[0]+' '+$Middle+' '+$texts[2]))
    for($i=0;$i -lt $tokens.Count;$i++){[pscustomobject]@{Text=$tokens[$i];Start=$i*0.2;End=($i+1)*0.2;Chapter=0;SubtitleTimingQuality='dtw';SubtitleTimingOrigin='recovery-fixture'}}
}
function Invoke-RecoveryCase([string]$Middle,[string]$Language='vi'){
    $script:heard=@(New-RecoveryWords $Middle)
    $script:sources=@([pscustomobject]@{start=10.0;end=10.0+$script:heard.Count*0.2})
    $script:aligned=@(Align-CuesToRecognizedWords $cues $script:heard $script:sources)
    Repair-PvsAutoEditReferenceWords -Cues $cues -Aligned $script:aligned -Words $script:heard -Sources $script:sources -Language $Language -RecognizeWindow {
        param($voice,$start,$end)
        foreach($word in $script:heard){if($voice.start+$word.Start -ge $start-0.000001 -and $voice.start+$word.End -le $end+0.000001){
            $copy=$word.PSObject.Copy();$copy.Start+=$voice.start-$start;$copy.End+=$voice.start-$start;$copy
        }}
    }
}
$raw=@(New-RecoveryWords 'Phần lớn trong số đó là những loài có 102.')
$before=$raw | ConvertTo-Json -Depth 10 -Compress
$result=Invoke-RecoveryCase 'Phần lớn trong số đó là những loài có 102.'
if(-not $result.Repaired -or ($result.RecoveredCueIndices -join ',') -ne '2' -or ($result.Cues.Index -join ',') -ne '1,2,3'){throw 'AUTO_EDIT_REFERENCE_RECOVERY_FAILED'}
$middle=$result.Cues[1]
if($middle.Text -cne $texts[1] -or @($middle.WordTimings).Count -ne 10 -or $middle.Start -ne 11.2 -or $middle.End -ne 13.2){throw 'RECOVERY_TEXT_TIMING_OR_OFFSET_CHANGED'}
if(-not $middle.EditBoundaryReviewRequired -or $result.Recovery[0].kind -ne 'spoken-digit-group' -or $middle.WordTimings[-1].SubtitleTimingQuality -ne 'estimated' -or $middle.WordTimings[-1].SubtitleTimingOrigin -ne 'recovery-fixture'){throw 'RECOVERY_GROUP_PROVENANCE_LOST'}
if((Test-PvsSubtitleDtwCue $middle @{}) -or (Test-PvsTrialCueEvidence $middle $sources[0]) -or (Test-PvsAcousticEditCue $middle $sources[0])){throw 'RECOVERY_PROMOTED_TEXT_TO_EDIT_DTW'}
if(($heard | ConvertTo-Json -Depth 10 -Compress) -cne $before -or $aligned[1].PSObject.Properties['EditBoundaryReviewRequired']){throw 'RECOVERY_MUTATED_ORIGINAL_WORDS_OR_ALIGNMENT'}
# Text recovery never upgrades shared omission proof or makes a source map.
$strict=Resolve-PvsEditedReference $cues $heard $sources {param($voice,$start,$end);$heard}
if($strict.Resolved -or $strict.OmittedCueIndices.Count -or $result.PSObject.Properties['OmittedCueIndices']){throw 'RECOVERY_AUTHORIZED_PICTURE_OMISSION'}
foreach($spoken in @(
    'Phần lớn trong số đó là những loài có 103.',
    'Phần lớn trong số đó là những loài có một không.',
    'Phần lớn trong số đó là những loài có hai.',
    'Phần lớn trong số đó là những loài có.',
    'lớn trong số đó là những loài có 102.',
    'Phần lớn trong số đó là những loài có lời thêm 102.',
    ''
)){
    $bad=Invoke-RecoveryCase $spoken
    if($bad.Repaired){throw "RECOVERY_ACCEPTED_PARTIAL_OR_DIFFERENT_SPEECH:$spoken"}
}
if((Invoke-RecoveryCase 'Phần lớn trong số đó là những loài có 102.' en).Repaired){throw 'RECOVERY_CHANGED_OTHER_LANGUAGE'}
# A different digit sequence uses the same general rule, not a phrase fix.
$saved=$texts[1];$texts[1]='Mã truy cập hiện tại của thiết bị trong hệ thống là bốn hai không sáu.';$cues[1].Text=$texts[1]
if(-not (Invoke-RecoveryCase 'Mã truy cập hiện tại của thiết bị trong hệ thống là 4206.').Repaired){throw 'RECOVERY_HARDCODED_102_OR_SOURCE_SENTENCE'}
$texts[1]=$saved;$cues[1].Text=$saved
$ok=Invoke-RecoveryCase 'Phần lớn trong số đó là những loài có 102.'
foreach($fault in @('nan','overlap','chapter','outside','reordered-index','duplicate-index')){
    $bad=$ok.Cues[1].PSObject.Copy();$bad.WordTimings=@($bad.WordTimings | ForEach-Object {$_.PSObject.Copy()})
    switch($fault){
        nan {$bad.WordTimings[-1].Start=[double]::NaN}
        overlap {$bad.WordTimings[-1].Start=$bad.WordTimings[-2].Start}
        chapter {$bad.WordTimings[-1].Chapter=1}
        outside {$bad.WordTimings[-1].End=$sources[0].end+1}
        'reordered-index' {$bad.WordTimings[-1].TargetWordIndex=7}
        'duplicate-index' {$bad.WordTimings[-1].TargetWordIndex=8}
    }
    if($null -ne (Get-PvsAutoEditReferenceWordCoverage $bad $heard $sources)){throw "RECOVERY_ACCEPTED_BAD_TIMING:$fault"}
}
$failed=$false
try{Repair-PvsAutoEditReferenceWords -Cues $cues -Aligned $aligned -Words $heard -Sources $sources -RecognizeWindow {throw 'NATIVE_ASR_FAILED'} | Out-Null}catch{if($_.Exception.Message -eq 'NATIVE_ASR_FAILED'){$failed=$true}else{throw}}
if(-not $failed){throw 'RECOVERY_HID_NATIVE_FAILURE'}
# The real planner must merge around this cue even if a silence detector and
# the legacy DTW callback would otherwise offer a cut at either edge.
$ok=Invoke-RecoveryCase 'Phần lớn trong số đó là những loài có 102.'
$rows=@(Get-PvsDtwBoundaryTrial -Cues $ok.Cues -Voices $sources -Silences @() -FrameRate 30 -LegacyFinder {throw 'RECOVERED_BOUNDARY_REACHED_LEGACY_FINDER'})
if($rows.Count -ne 2 -or @($rows | Where-Object {$_.Status -ne 'rejected' -or $_.Reason -ne 'reference-text-recovery-review'}).Count){throw 'RECOVERY_DTW_BOUNDARY_NOT_BLOCKED'}
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$testRoot=Join-Path $root '.tmp-auto-edit-recovery-tests'
$temp=Join-Path $testRoot ([guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $temp -Force | Out-Null
try{
    $engine=Join-Path $temp 'engine'
    New-Item -ItemType Directory -Path (Join-Path $engine 'lib'),(Join-Path $engine 'runtime') -Force | Out-Null
    Copy-Item -LiteralPath "$root\extension\engine\build-sentence-plan.ps1" -Destination $engine
    Get-ChildItem -LiteralPath "$root\extension\engine\lib" -File | Copy-Item -Destination (Join-Path $engine 'lib')
    foreach($name in @('runtime-lock.json','cuda-lock.json')){Copy-Item -LiteralPath "$root\extension\engine\$name" -Destination $engine}
    Set-Content -LiteralPath "$engine\lib\Native.ps1" -Encoding ASCII -Value '. "$PSScriptRoot\Security.ps1"; . "$PSScriptRoot\AudioCache.ps1"; function Invoke-NativeCapture {param($FilePath,$Arguments);[pscustomobject]@{ExitCode=0;Output="silence_start: 1.1`nsilence_end: 1.3`nsilence_start: 3.1`nsilence_end: 3.3"}}'
    Set-Content -LiteralPath "$engine\runtime\engine.json" -Encoding ASCII -Value '{"ffmpeg":"fixture"}'
    $wav=Join-Path $temp 'voice.wav';Set-Content -LiteralPath $wav -Value '' -Encoding ASCII
    $voices=@([pscustomobject]@{start=10.0;end=14.4;path=$wav;speedPercent=100;name='fixture';inPoint=0})
    [ordered]@{voiceChapterCount=1;cues=$ok.Cues} | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath (Join-Path $temp 'alignment-result.json') -Encoding UTF8
    $job=@{outputFolder=$temp;speedWarningMinPercent=70;speedWarningMaxPercent=130;algorithm=@{useWhisperCache=$false};sequence=@{frameRate=30;sequenceId='recovery';name='recovery';mainVideoClip=@{start=0;end=30};voices=$voices;linkedAudio=@();voiceTrackIndex=1}}
    $jobPath=Join-Path $temp 'job.json';$job | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $jobPath -Encoding UTF8
    & "$engine\build-sentence-plan.ps1" -JobPath $jobPath | Out-Null
    $plan=Get-Content (Join-Path $temp 'sentence-edit-plan.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    if($plan.summary.safeSentenceGroupCount -ne 1 -or $plan.summary.lowConfidenceBoundaryMergeCount -ne 2 -or $plan.PSObject.Properties['editedSourceMap']){throw 'RECOVERY_LEGACY_PLANNER_CUT_OR_OMISSION'}
    foreach($cue in $cues){
        $final=@($plan.captions | Where-Object SourceCueIndex -eq $cue.Index)
        if(($final.Text -join ' ') -cne $cue.Text){throw 'RECOVERY_FINAL_CAPTION_LOST_OR_CHANGED_SRT'}
    }
    if(-not (Test-Path -LiteralPath $plan.captionSrtPath)){throw 'RECOVERY_FINAL_SRT_NOT_WRITTEN'}
}finally{
    $full=[IO.Path]::GetFullPath($temp)
    if(-not $full.StartsWith(([IO.Path]::GetFullPath($testRoot).TrimEnd('\')+'\'),[StringComparison]::OrdinalIgnoreCase)){throw 'UNSAFE_TEST_CLEANUP'}
    if(Test-Path -LiteralPath $full){Remove-Item -LiteralPath $full -Recurse -Force}
}
Write-Host 'AUTO_EDIT_REFERENCE_RECOVERY_OK:shared-selection;compact-digits;no-partial-cue;no-extra-speech;no-omission-proof;no-fake-DTW;offset;raw-immutability;invalid-timing;other-language;native-error'
