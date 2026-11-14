$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$root=Resolve-Path (Join-Path $PSScriptRoot '..\..')
. "$root\extension\engine\lib\Alignment.ps1"
. "$root\extension\engine\lib\CaptionOnly.ps1"

$numeric='Khoảng cách đó vào khoảng 9 phẩy 46 nghìn tỷ kilomet.'
$last='một cuộc trao đổi đơn giản nhất cũng có thể tiêu tốn hàng chục nghìn năm.'
$texts=@('alpha bravo charlie delta echo foxtrot.',$numeric,'Điều này có nghĩa là,',$last)+@(for($i=0;$i -lt 80;$i++){"future$($i)a future$($i)b future$($i)c future$($i)d future$($i)e future$($i)f."})
$refs=@(for($i=0;$i -lt $texts.Count;$i++){[pscustomobject]@{Index=$i+1;Text=$texts[$i];Start=$i*5;End=($i+1)*5}})
$actual=@($texts[0],'khoảng cách đó và khoảng 9 46 000 tỷ km.',$texts[2],($last -replace '^một','1'),'Phần hay nhất vẫn còn ở phía sau hãy nhấn vào video dài ở phần video liên quan bên dưới để xem đầy đủ.')
$tokens=@(ConvertTo-NormalizedWords ($actual -join ' '))
$words=@(for($i=0;$i -lt $tokens.Count;$i++){[pscustomobject]@{Text=$tokens[$i];Start=$i*0.15;End=($i+1)*0.15;Chapter=0}})
$script:shortWords=$words
$sources=@([pscustomobject]@{start=0.0;end=$tokens.Count*0.15})
$selection=Select-PvsSubtitleReference $refs $words $sources -AllowEditedReference -AllowUnmatchedRanges -SkipUnverifiedCues -RecognizeReferenceWindow {
    param($source,$start,$end)
    foreach($w in $script:shortWords){if($w.Start -ge $start-0.000001 -and $w.End -le $end+0.000001){$copy=$w.PSObject.Copy();$copy.Start-=$start;$copy.End-=$start;$copy}}
}
if(($selection.Cues.Index -join ',') -ne '1,2,3,4'){throw 'SHORT_LOST_LAST_REFERENCE_OR_ADDED_FUTURE_SRT'}
$numberCue=@($selection.Cues|Where-Object Index -eq 2)[0]
$lastCue=@($selection.Cues|Where-Object Index -eq 4)[0]
if($numberCue.Text -cne $numeric -or -not $numberCue.ReferenceNumberReviewRequired -or $numberCue.ReferenceNumberExpected -cne '9 phẩy 46 nghìn tỷ'){throw 'NUMBER_MISMATCH_REPLACED_SRT_WITH_ASR'}
$ctaStart=@(ConvertTo-NormalizedWords ($actual[0..3] -join ' ')).Count*0.15
if($lastCue.Text -cne $last -or $lastCue.End -gt $ctaStart+0.000001){throw 'SHORT_LAST_SRT_EXTENDED_INTO_CTA'}
if(@($selection.EditedReference.Cues|Where-Object Index -in @(2,4)).Count -or $selection.EditedReference.Resolved){throw 'SHORT_RECOVERY_CHANGED_SHARED_EDIT_PROOF'}
$script:ctaCalls=0
$completed=Complete-PvsSubtitleReference $selection $selection.RecognitionWords $sources {
    param($source,$start,$end,$chapter)
    $script:ctaCalls++
    if($start -lt $lastCue.End-0.000001){throw 'SRT_SENTENCE_WAS_SENT_TO_CTA_ASR'}
    [pscustomobject]@{Index=1;Start=$start;End=$end;Text=$actual[-1];Chapter=0;WordTimings=@()}
}
if($script:ctaCalls -ne 1 -or $completed.SupplementRanges.Count -ne 1 -or $completed.Cues[3].Text -cne $last){throw 'SHORT_SUPPLEMENT_IS_NOT_CTA_ONLY'}

function Test-NumberCase([string]$Expected,[string]$Actual,[bool]$Review,[string]$Surface=''){
    $ref=@([pscustomobject]@{Index=1;Text=$Expected;Start=900;End=910})
    $tokens=@(ConvertTo-NormalizedWords $Actual)
    $heard=@(for($i=0;$i -lt $tokens.Count;$i++){$w=[pscustomobject]@{Text=$tokens[$i];Start=$i*0.2;End=($i+1)*0.2;Chapter=0};if($Surface -and $tokens[$i] -match '^\d+$'){$w|Add-Member NoteProperty NumericSurfaceText $Surface};$w})
    $source=@([pscustomobject]@{start=0.0;end=$tokens.Count*0.2})
    $cue=@(Align-CuesToRecognizedWords $ref $heard $source)[0]
    if(-not (Test-PvsSubtitleNumberReferenceIdentity $cue $heard $source) -or $cue.ReferenceNumberReviewRequired -ne $Review -or $cue.Text -cne $Expected){throw "NUMBER_IDENTITY_DECISION_WRONG:$Expected|$Actual"}
}
Test-NumberCase 'alpha 13 phẩy 8 bravo charlie' 'alpha 13 8 bravo charlie' $false '13,8'
Test-NumberCase 'alpha 13 phẩy 8 bravo charlie' 'alpha 13 9 bravo charlie' $true '13,9'
Test-NumberCase 'alpha 100000 bravo charlie' 'alpha 100 000 bravo charlie' $false
Test-NumberCase 'alpha 100000 bravo charlie' 'alpha một trăm nghìn bravo charlie' $false
Test-NumberCase 'alpha 100000 bravo charlie' 'alpha 200 000 bravo charlie' $true
# Unrelated surrounding content must never pass merely because it has a number.
$cue=[pscustomobject]@{Index=1;Text='khoảng cách đó vào khoảng 9 nghìn tỷ kilomet';Start=0;End=2;Chapter=0;WordTimings=@()}
$bad=@(for($i=0;$i -lt 5;$i++){[pscustomobject]@{Text=@('nhạc','vang','100','trên','đồi')[$i];Start=$i*0.2;End=($i+1)*0.2;Chapter=0}})
if(Test-PvsSubtitleNumberReferenceIdentity $cue $bad @([pscustomobject]@{start=0;end=2})){throw 'NUMBER_HELPER_ACCEPTED_UNRELATED_CONTENT'}
# A short phrase far ahead in the full script also occurs inside a spoken
# sentence. It must not veto the whole Short's strong, ordered anchors.
$texts=@('Bạn nghĩ rằng bộ não đã tạo ra ý thức của bạn',
    'Ngày nay con người có thể lên trời xuống biển',
    'chúng ta biết rất ít về ý thức trong bộ não',
    'Nói đơn giản là ý thức trong trạng thái bình thường',
    'dường như phụ thuộc rất lớn vào bộ não',
    'nhưng khẳng định rằng não tạo ra ý thức',
    'có lẽ chưa hẳn đã chính xác')+@(for($i=0;$i -lt 80;$i++){"future$($i)a future$($i)b future$($i)c future$($i)d future$($i)e future$($i)f"})+@('về ý thức')
$refs=@(for($i=0;$i -lt $texts.Count;$i++){[pscustomobject]@{Index=$i+1;Text=$texts[$i];Start=900+$i*5;End=905+$i*5}})
$spoken=@($texts[0] -replace 'não','náo')+@($texts[1..3])+@($texts[4] -replace 'bộ não','võ náo')+@($texts[5] -replace 'não','náo')+@($texts[6] -replace 'lẽ','lẻ')+@('phần hay nhất vẫn còn phía sau hãy xem video dài')
$tokens=@(ConvertTo-NormalizedWords ($spoken -join ' '))
$words=@(for($i=0;$i -lt $tokens.Count;$i++){[pscustomobject]@{Text=$tokens[$i];Start=$i*0.15;End=($i+1)*0.15;Chapter=0}})
$script:shortWords=$words
$sources=@([pscustomobject]@{start=0.0;end=$tokens.Count*0.15})
if((Find-PvsEditedReferenceMatches $refs $words $sources).Ordered){throw 'INCIDENTAL_FUTURE_PHRASE_FIXTURE_DID_NOT_REPRODUCE'}
if($null -ne (Resolve-PvsEditedReference $refs $words $sources $null)){throw 'SUBTITLE_POLICY_RELAXED_AUTO_EDIT_DEFAULT'}
$selection=Select-PvsSubtitleReference $refs $words $sources -AllowEditedReference -AllowUnmatchedRanges -AllowAudioOutsideReference -SkipUnverifiedCues -RecognizeReferenceWindow {
    param($source,$start,$end)
    foreach($w in $script:shortWords){if($w.Start -ge $start-0.000001 -and $w.End -le $end+0.000001){$copy=$w.PSObject.Copy();$copy.Start-=$start;$copy.End-=$start;$copy}}
}
if(($selection.Cues.Index -join ',') -ne '1,2,3,4,5,6,7' -or ($selection.Cues.Text -join '|') -cne ($texts[0..6] -join '|')){throw 'SHORT_INCIDENTAL_PHRASE_REPLACED_VALID_SRT_WITH_ASR'}
if($selection.EditedReference.Resolved -or $selection.FallbackRanges.Count){throw 'SHORT_ANCHOR_POLICY_INVALID'}
Write-Host 'SUBTITLE_SHORT_REFERENCE_OK:long-SRT-short-audio;last-sentence-kept;CTA-only;future-cues-not-added;number-content-review;numeric-format-and-spoken-equivalence;incidental-future-phrase;neighbor-revisit;shared-edit-proof-unchanged'
