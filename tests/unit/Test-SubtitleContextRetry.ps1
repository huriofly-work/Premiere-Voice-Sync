$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
. "$PSScriptRoot\Test-SubtitleProjection.ps1"
function Test-ContextRetry([string]$Fault='',[bool]$Accept=$true,[int]$Chapter=0,[bool]$ShortLeft=$false){
    $texts=@('alpha bravo charlie delta echo foxtrot','nước hồ giàu sắt,','golf hotel india juliet kilo lima');$middleIndex=2
    $initial=@(New-ProjectionWords $texts[0] 0 3)+@(New-ProjectionWords 'nước hồ dầu sắc' 3 5)+@(New-ProjectionWords $texts[2] 5 8)
    if($ShortLeft){
        $initial=@(New-ProjectionWords $texts[0] 0 1.5)+@(New-ProjectionWords 'Quan trọng hơn' 1.5 3)+@($initial|Where-Object {$_.Start -ge 3})
        $texts=@($texts[0],'Quan trọng hơn,',$texts[1],$texts[2]);$middleIndex=3
    }
    $refs=@(for($i=0;$i -lt $texts.Count;$i++){[pscustomobject]@{Index=$i+1;Text=$texts[$i];Start=900+$i*10;End=910+$i*10}})
    foreach($word in $initial){$word.Chapter=$Chapter}
    $script:contextSource=$initial;$script:contextCalls=0;$script:contextFault=$Fault
    $sources=@([pscustomobject]@{start=20.0;end=28.0})
    if($Chapter -eq 1){$sources=@([pscustomobject]@{start=0.0;end=1.0})+$sources}
    $selection=Select-PvsSubtitleReference $refs $initial $sources -AllowEditedReference -AllowUnmatchedRanges -SkipUnverifiedCues -RecognizeReferenceWindow {
        param($source,$start,$end)
        $heard=$script:contextSource
        if([Math]::Abs($start-20.5) -lt 0.000001 -and [Math]::Abs($end-27.5) -lt 0.000001){
            $script:contextCalls++
            $middle=switch($script:contextFault){
                extra {@(New-ProjectionWords 'lời thêm nước hồ giàu sắc' 3 5)}
                unrelated {@(New-ProjectionWords 'âm nhạc vang giữa đồng' 3 5)}
                default {@(New-ProjectionWords 'nước hồ giàu sắc' 3 5)}
            }
            $heard=@($script:contextSource|Where-Object {$_.End -le 3})+$middle+@($script:contextSource|Where-Object {$_.Start -ge 5})
            if($script:contextFault -eq 'neighbor'){$heard[3].Text='unrelated';$heard[4].Text='unrelated';$heard[5].Text='unrelated'}
        }
        $local=@(foreach($word in $heard){if($source.start+$word.Start -ge $start-0.000001 -and $source.start+$word.End -le $end+0.000001){$copy=$word.PSObject.Copy();$copy.Start+=$source.start-$start;$copy.End+=$source.start-$start;$copy.Chapter=0;$copy}})
        if($script:contextCalls -and $script:contextFault -eq 'nan'){$local[1].Start=[double]::NaN}
        $local
    }
    $cue=@($selection.Cues|Where-Object Index -eq $middleIndex)
    if([bool]$cue.Count -ne $Accept -or $script:contextCalls -ne 1){throw "CONTEXT_RETRY_DECISION_WRONG:$Fault/$Accept/$($script:contextCalls)"}
    if($selection.EditedReference.Resolved -or @($selection.EditedReference.Cues|Where-Object Index -eq $middleIndex).Count){throw 'CONTEXT_RETRY_CHANGED_SHARED_OMISSION_PROOF'}
    if(-not $Accept){return}
    if(-not $cue[0].SubtitleReferenceContextRetry -or $cue[0].Text -cne $texts[$middleIndex-1] -or $cue[0].Start -ne 23 -or $cue[0].End -ne 25 -or $cue[0].Chapter -ne $Chapter){throw 'CONTEXT_RETRY_TEXT_BOUNDS_OR_CHAPTER_WRONG'}
    if(Test-PvsSubtitleDtwCue $cue[0] @{}){throw 'CONTEXT_RETRY_PROMOTED_TIMING'}
    $completed=Complete-PvsSubtitleReference $selection $selection.RecognitionWords $sources {throw 'CONTEXT_RECOVERY_SENT_TO_ASR'}
    $captions=@(New-PvsStandaloneCaptions $completed.Cues $sources @() 30 30)
    if((@(ConvertTo-NormalizedWords ($captions.Text -join ' ')) -join '|') -cne (@(ConvertTo-NormalizedWords ($texts -join ' ')) -join '|')){throw 'CONTEXT_RETRY_FINAL_SRT_CHANGED'}
}
Test-ContextRetry
Test-ContextRetry '' $true 1
Test-ContextRetry '' $true 0 $true
foreach($fault in @('extra','unrelated','neighbor')){Test-ContextRetry $fault $false}
$failed=$false
try{Test-ContextRetry 'nan'}catch{if($_.Exception.Message -eq 'SUBTITLE_REFERENCE_RETRY_TIMING_INVALID'){$failed=$true}else{throw}}
if(-not $failed){throw 'CONTEXT_RETRY_ACCEPTED_BAD_TIMING'}
Write-Host 'SUBTITLE_CONTEXT_RETRY_OK:neighbors-required;unchanged-identity-threshold;extra-speech;unrelated;offset;chapter;final-SRT;shared-omission-proof;invalid-timing'
