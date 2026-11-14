$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
. "$PSScriptRoot\..\..\extension\engine\lib\CaptionOnly.ps1"
$texts=@('alpha bravo charlie delta echo foxtrot.','Phan lon trong so do la nhung loai co mot khong hai.','golf hotel india juliet kilo lima.','A different complete sentence requires its missing ending.','november oscar papa quebec romeo sierra.')
$spoken=@($texts);$spoken[1]='Phan lon trong so do la nhung loai co 102.';$spoken[3]='A different complete sentence requires.'
$cues=@(for($i=0;$i -lt 5;$i++){[pscustomobject]@{Index=$i+1;Start=$i*10.0;End=($i+1)*10.0;Text=$texts[$i]}})
# Use the Vietnamese numeric fixture from the historical recovery regression.
$texts[1]=[string]::Concat('Ph',[char]0x1ea7,'n l',[char]0x1edb,'n trong s',[char]0x1ed1,' ',[char]0x111,[char]0xf3,' l',[char]0xe0,' nh',[char]0x1eef,'ng lo',[char]0xe0,'i c',[char]0xf3,' m',[char]0x1ed9,'t kh',[char]0xf4,'ng hai.')
$cues[1].Text=$texts[1];$spoken[1]=$texts[1].Replace('m'+[char]0x1ed9+'t kh'+[char]0xf4+'ng hai','102')
$tokens=@(ConvertTo-NormalizedWords ($spoken -join ' '))
$script:words=@(for($i=0;$i -lt $tokens.Count;$i++){[pscustomobject]@{Text=$tokens[$i];Start=$i*0.2;End=($i+1)*0.2;Chapter=0}})
$sources=@([pscustomobject]@{start=10.0;end=10.0+$words.Count*0.2})
$aligned=@(Align-CuesToRecognizedWords $cues $words $sources)
$before=$aligned | ConvertTo-Json -Depth 12 -Compress
$result=Repair-PvsAutoEditReferenceWords $cues $aligned $words $sources {
    param($voice,$start,$end)
    foreach($w in $script:words){if($voice.start+$w.Start -ge $start-0.000001 -and $voice.start+$w.End -le $end+0.000001){$copy=$w.PSObject.Copy();$copy.Start+=$voice.start-$start;$copy.End+=$voice.start-$start;$copy}}
}
if($result.Repaired -or ($result.RecoveredCueIndices -join ',') -ne '2'){throw 'ONE_UNRESOLVED_CUE_DISCARDED_VALID_RECOVERY'}
if($result.Cues[1].Text -cne $texts[1] -or -not $result.Cues[1].EditBoundaryReviewRequired -or $result.Cues[3].PSObject.Properties['AutoEditReferenceRecovery']){throw 'PARTIAL_RECOVERY_RESTORED_UNHEARD_TEXT_OR_LOST_PROTECTION'}
if(($aligned | ConvertTo-Json -Depth 12 -Compress) -cne $before -or $result.PSObject.Properties['OmittedCueIndices']){throw 'PARTIAL_RECOVERY_MUTATED_BASELINE_OR_GRANTED_OMISSION'}
Write-Host 'AUTO_EDIT_PARTIAL_RECOVERY_OK:good-cue-retained;partial-cue-unresolved;no-omission;immutable;boundary-review'
