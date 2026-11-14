$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$root=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
. "$root\extension\engine\lib\CaptionOnly.ps1"
function Check([bool]$Value,[string]$Message){if(-not $Value){throw "CUT_BATCH_TEST_FAILED:$Message"}}
function Clone($Value){ConvertFrom-Json (ConvertTo-Json -InputObject $Value -Depth 30)}
$refs=@();$words=@();$quiet=@()
for($i=0;$i -lt 24;$i++){
    $tokens=@(0..9|ForEach-Object {"cue$($i)word$_"})
    $refs+=[pscustomobject]@{Index=$i+1;Start=$i*4.0;End=($i+1)*4.0;Text=($tokens -join ' ')+','}
    for($w=0;$w -lt 10;$w++){$words+=[pscustomobject]@{Text=$tokens[$w];Start=$i*4+0.2+$w*0.25;End=$i*4+0.4+$w*0.25;Chapter=0;SubtitleTimingQuality='dtw'}}
    if($i -lt 23){$quiet+=[pscustomobject]@{Start=$i*4+2.8;End=$i*4+4.1;Duration=1.3}}
}
$voices=@([pscustomobject]@{start=0.0;end=96.0;inPoint=0;speedPercent=100;path='';name='fixture'})
$evidence=@(Get-PvsReferenceCueEvidence $refs $words @() $voices)
$cuts=@(Get-PvsWholeCueQuietCuts $evidence $words $voices $quiet 30 @())
Check ($cuts.Count -eq 23) 'fixture-has-many-independent-whole-cue-proofs'
$script:normalizer=${function:ConvertTo-NormalizedWords};$script:normalizationCalls=0
function ConvertTo-NormalizedWords {param([AllowEmptyString()][string]$Text);$script:normalizationCalls++;& $script:normalizer $Text}
$batch=@(Test-PvsAcousticReferenceCuts $cuts $refs $voices $quiet 30)
Check ($batch.Count -eq $cuts.Count -and -not ($batch -contains $false)) 'valid-proof-batch'
Check ($script:normalizationCalls -le $refs.Count+4*$cuts.Count) 'reference-index-built-once-not-for-each-proof'
$raw=@(Get-PvsAcousticReferenceCuts $refs $words $voices $quiet 30)
Check ($raw.Count -gt 0) 'raw-context-fixture'
$mixed=@($cuts[0],$raw[0],[pscustomobject]@{revision='unknown'},$cuts[1])
$mixedExpected=@(foreach($proof in $mixed){Test-PvsAcousticReferenceCut $proof $refs $voices $quiet 30})
Check ((@(Test-PvsAcousticReferenceCuts $mixed $refs $voices $quiet 30) -join ',') -ceq ($mixedExpected -join ',')) 'mixed-whole-raw-unknown-batch'
Check (@(Test-PvsAcousticReferenceCuts $cuts $refs $voices $quiet 30 -RequireAll).Count -eq 0) 'successful-audit-emits-no-plan-data'
foreach($fault in @('none','duplicate','changed-number','estimated','moved-time','chapter','quiet','frame')){
    $r=Clone $refs;$p=Clone $cuts;$v=Clone $voices;$q=Clone $quiet
    switch($fault){
        duplicate {$r[-1].Text=$r[0].Text}
        changed-number {$r[0].Text+=' 123'}
        estimated {$p[0].leftEvidence.CaptionWordTimings[0].SubtitleTimingQuality='estimated'}
        moved-time {$p[0].leftEvidence.CaptionWordTimings[0].Start=-1}
        chapter {$p[0].chapter=1}
        quiet {$q=@()}
        frame {$p[0].cutFrame++}
    }
    $expected=@(foreach($proof in $p){Test-PvsAcousticReferenceCut $proof $r $v $q 30})
    $actual=@(Test-PvsAcousticReferenceCuts $p $r $v $q 30)
    Check (($expected -join ',') -ceq ($actual -join ',')) "single-and-batch-parity-$fault"
    if($fault -in @('duplicate','changed-number','estimated','moved-time','chapter','quiet')){Check (-not $actual[0]) "unchanged-safety-gate-$fault"}
    if($actual -contains $false){
        $failed=$false
        try{Test-PvsAcousticReferenceCuts $p $r $v $q 30 -RequireAll}catch{if($_.Exception.Message -ne 'ACOUSTIC_PARTITION_PROOF_INVALID'){throw};$failed=$true}
        Check $failed "postcheck-still-rejects-$fault"
    }
}
# The count index must use exactly the same equality as the previous -ceq
# scan, including invariant-culture Unicode equivalences and empty text.
$samples=@('a','A','ae',([string][char]0xE6),'ab',('a'+[char]0+'b'),'')
$countRefs=@($samples|ForEach-Object {[pscustomobject]@{Text=$_}})
$counts=New-PvsAcousticReferenceTextCounts $countRefs
foreach($ref in $countRefs){
    $key=@(ConvertTo-NormalizedWords $ref.Text) -join ' '
    $expected=@($countRefs|Where-Object {(@(ConvertTo-NormalizedWords $_.Text) -join ' ') -ceq $key}).Count
    Check ($counts[$key] -eq $expected) 'index-preserves-original-string-equality'
}
Check (@(Test-PvsAcousticReferenceCuts @() $refs $voices $quiet 30).Count -eq 0) 'empty-batch'
Check (@(Test-PvsAcousticReferenceCuts $null $refs $voices $quiet 30).Count -eq 0) 'null-proof-batch'
Check (@(New-PvsAcousticEditGroups @() @() @() $null @() 30).Count -eq 0) 'null-cuts-preserve-empty-group-result'
Write-Host 'ACOUSTIC_CUT_BATCH_OK:linear-reference-index;single-batch-parity;current-text-duplicates;numeric-edit;dtw-time-chapter-quiet-guards;invariant-equality;require-all'
