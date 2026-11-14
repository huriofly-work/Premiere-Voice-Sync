$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$root=Resolve-Path (Join-Path $PSScriptRoot '..\..')
. "$root\extension\engine\lib\Srt.ps1"
. "$root\extension\engine\lib\Alignment.ps1"
. "$root\extension\engine\lib\CaptionOnly.ps1"
. "$root\extension\engine\lib\SubtitleTiming.ps1"
function Test-IdentityCase([string]$Expected,[string]$Actual,[bool]$Accepted){
    $texts=@('alpha bravo charlie delta echo foxtrot',$Expected,'golf hotel india juliet kilo lima')
    $reference=@(for($i=0;$i -lt 3;$i++){[pscustomobject]@{Index=$i+1;Text=$texts[$i];Start=900+$i*10;End=910+$i*10}})
    $tokens=@(ConvertTo-NormalizedWords ($texts[0]+' '+$Actual+' '+$texts[2]))
    $heard=@(for($i=0;$i -lt $tokens.Count;$i++){[pscustomobject]@{Text=$tokens[$i];Start=$i*0.2;End=($i+1)*0.2;Chapter=0;SubtitleTimingQuality='dtw';SubtitleTimingOrigin='fixture'}})
    $source=@([pscustomobject]@{start=20.0;end=20+$tokens.Count*0.2})
    $script:identityHeard=$heard
    $selection=Select-PvsSubtitleReference $reference $heard $source -AllowEditedReference -AllowUnmatchedRanges -SkipUnverifiedCues -RecognizeReferenceWindow {
        param($source,$start,$end)
        foreach($word in $script:identityHeard){if($source.start+$word.Start -ge $start-0.000001 -and $source.start+$word.End -le $end+0.000001){$copy=$word.PSObject.Copy();$copy.Start+=$source.start-$start;$copy.End+=$source.start-$start;$copy}}
    }
    $middle=@($selection.Cues | Where-Object Index -eq 2)
    if([bool]$middle.Count -ne $Accepted){throw "IDENTITY_DECISION_WRONG:$Expected|$Actual|$Accepted"}
    if(-not $Accepted){return}
    if($middle[0].Text -cne $Expected -or -not $middle[0].SubtitleReferencePartialMatch -or (Test-PvsSubtitleDtwCue $middle[0] @{})){throw 'IDENTITY_CHANGED_TEXT_OR_CLAIMED_VERIFIED_DTW'}
    $complete=Complete-PvsSubtitleReference $selection $selection.RecognitionWords $source {throw 'IDENTIFIED_SRT_SENT_TO_ASR'}
    $captions=@(New-PvsStandaloneCaptions $complete.Cues $source @() 30 30)
    $expectedWords=@(ConvertTo-NormalizedWords ($texts -join ' ')) -join '|'
    $actualWords=@(ConvertTo-NormalizedWords (($captions | ForEach-Object {$_.Text}) -join ' ')) -join '|'
    if($actualWords -cne $expectedWords){throw 'IDENTIFIED_SRT_LOST_DURING_CAPTION_SPLIT'}
    if($selection.EditedReference.Resolved -or @($selection.EditedReference.Cues | Where-Object Index -eq 2).Count){throw 'IDENTITY_RELAXED_SHARED_EDIT_PROOF'}
}
Test-IdentityCase 'Tàn nhẫn hơn nữa là' 'Tản nhận hơn nữa là' $true
Test-IdentityCase 'Giới hạn của tốc độ ánh sáng khiến các nhà khoa học bất lực' 'rời hạn của tốc độ ánh sáng khiến các nhà khoa học bất lực' $true
Test-IdentityCase 'Một nền văn minh có thể hưng thịnh trong nhiều năm' 'một nền văn minh có thể hương thích trong nhiều năm' $true
Test-IdentityCase 'Giả thuyết thứ năm là Quy tắc Rừng Tối' 'giả thuyết thứ năm là quy tắc dừng tối' $true
Test-IdentityCase 'câu này đúng' 'câu này lạ' $true
Test-IdentityCase 'đầu câu này vẫn có trong đoạn voice' 'câu này vẫn có trong đoạn voice' $true
Test-IdentityCase 'câu này vẫn có trong đoạn voice cuối' 'câu này vẫn có trong đoạn voice' $true
Test-IdentityCase 'câu này vẫn có trong đoạn voice' 'câu này vẫn còn có trong đoạn voice' $true
Test-IdentityCase 'những tàu thăm dò bay ra ngoài vũ trụ' 'nhạc nền vang lên giữa cánh đồng hoa cỏ' $false
Test-IdentityCase 'Toàn bộ câu này đã bị bỏ khỏi voice' '' $false
# Same short SRT text appears twice, but each occurrence has different strong
# neighbors. Neither the unresolved nor the exactly recovered occurrence may
# disappear merely because the shared edit matcher rejects global duplicates.
$phrase='Theo Nguyên lý Tầm thường'
$texts=@('alpha bravo charlie delta echo foxtrot',$phrase,'golf hotel india juliet kilo lima',$phrase,'mike november oscar papa quebec romeo')
$reference=@(for($i=0;$i -lt $texts.Count;$i++){[pscustomobject]@{Index=$i+1;Text=$texts[$i];Start=900+$i*10;End=910+$i*10}})
$spoken=@($texts);$spoken[1]=$spoken[1] -replace 'Tầm','Tẩm'
$tokens=@(ConvertTo-NormalizedWords ($spoken -join ' '))
$heard=@(for($i=0;$i -lt $tokens.Count;$i++){[pscustomobject]@{Text=$tokens[$i];Start=$i*0.2;End=($i+1)*0.2;Chapter=0}})
$script:identityHeard=$heard
$source=@([pscustomobject]@{start=20.0;end=20+$tokens.Count*0.2})
$selection=Select-PvsSubtitleReference $reference $heard $source -AllowEditedReference -AllowUnmatchedRanges -SkipUnverifiedCues -RecognizeReferenceWindow {
    param($source,$start,$end)
    foreach($word in $script:identityHeard){if($source.start+$word.Start -ge $start-0.000001 -and $source.start+$word.End -le $end+0.000001){$copy=$word.PSObject.Copy();$copy.Start+=$source.start-$start;$copy.End+=$source.start-$start;$copy}}
}
if(($selection.Cues.Index -join ',') -ne '1,2,3,4,5' -or @($selection.Cues|Where-Object Text -ceq $phrase).Count -ne 2){throw 'CONTEXT_IDENTIFIED_REPEATED_SRT_SENT_TO_ASR'}
Write-Host 'SUBTITLE_SENTENCE_IDENTITY_OK:short;accent;pronunciation;edges;ASR-omission-insertion;SRT-text-through-final-captions;no-fake-DTW;whole-omission-and-unrelated-speech-rejected;shared-edit-proof-unchanged'
