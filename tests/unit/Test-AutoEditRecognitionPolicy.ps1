$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
. "$root\extension\engine\lib\CaptionOnly.ps1"
$ast=[Management.Automation.Language.Parser]::ParseFile("$root\extension\engine\run-alignment.ps1",[ref]$null,[ref]$null)
$writer=$ast.Find({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Write-PvsAutoEditPreservationResult'},$true)
if(-not $writer){throw 'RECOGNITION_PRESERVATION_POLICY_MISSING'}
. ([scriptblock]::Create($writer.Extent.Text))
$outer=$ast.Find({param($n) $n -is [Management.Automation.Language.TryStatementAst] -and $n.Extent.Text.Contains('ALIGNMENT_READY') -and $n.CatchClauses.Count -gt 0},$true)
if(-not $outer){throw 'RECOGNITION_QUALITY_CATCH_MISSING'}
function Get-PvsAudioCacheStats {[pscustomobject]@{enabled=$false}}
$temp=Join-Path $root ('.tmp-recognition-policy-tests\'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $temp -Force | Out-Null
try{
    $job=[pscustomobject]@{outputFolder=$temp};$targetCues=@([pscustomobject]@{Index=1},[pscustomobject]@{Index=2})
    $voiceClips=@([pscustomobject]@{start=10.0;end=20.0},[pscustomobject]@{start=20.0;end=30.0})
    $recognitionBackend='cpu';$recognitionBackendLabel='CPU';$backend=[pscustomobject]@{reason='fixture'};$gpuFallbackUsed=$false;$gpuFallbackReason=''
    $emptyGuard=$ast.Find({param($n) $n -is [Management.Automation.Language.IfStatementAst] -and $n.Extent.Text.Contains("reason='recognition-empty'") -and -not $n.Extent.Text.Contains('Align-CuesToRecognizedWords')},$true)
    if(-not $emptyGuard){throw 'EMPTY_RECOGNITION_POLICY_MISSING'}
    $recognized=New-Object System.Collections.Generic.List[object]
    & ([scriptblock]::Create($emptyGuard.Extent.Text))
    $emptyResult=Get-Content "$temp\alignment-result.json" -Raw -Encoding UTF8 | ConvertFrom-Json
    if(-not $emptyResult.preserveTimeline -or $emptyResult.reviewReason.reason -ne 'recognition-empty'){throw 'EMPTY_RECOGNITION_DID_NOT_FINISH_WITH_REVIEW'}
    foreach($code in @('EDIT_RECOGNITION_TIMESTAMP_INVALID','EDITED_REFERENCE_RETRY_TIMING_INVALID','SUBTITLE_REFERENCE_RETRY_TIMING_INVALID')){
        & ([scriptblock]::Create("try { throw '$code' } "+$outer.CatchClauses[0].Extent.Text))
        $result=Get-Content "$temp\alignment-result.json" -Raw -Encoding UTF8 | ConvertFrom-Json
        if(-not $result.ok -or -not $result.preserveTimeline -or $result.manualReviewStatus -ne 'manual-review-pending' -or $result.recognitionReviewTasks.Count -ne 2 -or ($result.unresolvedReferenceCueIndices -join ',') -ne '1,2'){throw 'MODEL_QUALITY_ERROR_DID_NOT_PRESERVE_AND_FINISH'}
        if($result.PSObject.Properties['editedSourceMap'] -or $result.PSObject.Properties['captionSrtPath']){throw 'PRESERVATION_FABRICATED_EDIT_OR_CAPTION_RESULT'}
    }
    foreach($code in @('MEDIA_PATH_NOT_FOUND','NATIVE_ASR_FAILED','ACCESS_DENIED','WORKFLOW_CANCELLED')){
        $failed=$false
        try{& ([scriptblock]::Create("try { throw '$code' } "+$outer.CatchClauses[0].Extent.Text))}catch{if($_.Exception.Message -eq $code){$failed=$true}else{throw}}
        if(-not $failed){throw "TECHNICAL_OR_CANCELLATION_ERROR_SWALLOWED:$code"}
    }
    $captionAst=[Management.Automation.Language.Parser]::ParseFile("$root\extension\engine\run-captions.ps1",[ref]$null,[ref]$null)
    $captionWriter=$captionAst.Find({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Write-PvsCaptionPreservationResult'},$true)
    . ([scriptblock]::Create($captionWriter.Extent.Text))
    $captionTry=$captionAst.Find({param($n) $n -is [Management.Automation.Language.TryStatementAst] -and $n.Extent.Text.Contains("Write-Host 'CAPTIONS_READY'") -and $n.CatchClauses.Count -gt 0},$true)
    $job | Add-Member sequenceId 'fixture';$job | Add-Member snapshot 'fixture'
    $sources=$voiceClips;$backendName='cpu';$backendLabel='CPU'
    & ([scriptblock]::Create("try { throw 'SUBTITLE_RECOGNITION_TIMESTAMP_MISSING' } "+$captionTry.CatchClauses[0].Extent.Text))
    $result=Get-Content "$temp\caption-result.json" -Raw -Encoding UTF8 | ConvertFrom-Json
    if(-not $result.preserveTimeline -or $result.captionCueCount -ne 0 -or $result.PSObject.Properties['captionSrtPath']){throw 'UNUSABLE_CAPTIONS_NOT_PRESERVED_AS_REVIEW'}
    $edgeTry=$captionAst.Find({param($n) $n -is [Management.Automation.Language.TryStatementAst] -and $n.Body.Extent.Text.Contains('Repair-PvsSubtitleRecognitionEdge') -and -not $n.Body.Extent.Text.Contains("Write-Host 'CAPTIONS_READY'")},$true)
    $primaryBeforeEdge=[pscustomobject]@{transcription=@([pscustomobject]@{text='Useful primary speech.';offsets=@{from=0;to=2000}})}
    $before=$primaryBeforeEdge | ConvertTo-Json -Depth 8 -Compress
    $json=[pscustomobject]@{transcription=@()};$recognitionRejectedRanges=New-Object System.Collections.Generic.List[object]
    $sourceIndex=0;$source=$sources[0];$outBase='fixture'
    . ([scriptblock]::Create("try { throw 'SUBTITLE_RECOGNITION_TAIL_UNVERIFIED:fixture' } "+$edgeTry.CatchClauses[0].Extent.Text))
    if(($edge.Json | ConvertTo-Json -Depth 8 -Compress) -cne $before -or $recognitionRejectedRanges.Count -ne 1){throw 'UNVERIFIED_TAIL_DISCARDED_USEFUL_PRIMARY_CAPTIONS'}
    $failed=$false
    try{& ([scriptblock]::Create("try { throw 'ACCESS_DENIED' } "+$edgeTry.CatchClauses[0].Extent.Text))}catch{if($_.Exception.Message -eq 'ACCESS_DENIED'){$failed=$true}else{throw}}
    if(-not $failed){throw 'CAPTION_EDGE_SWALLOWED_IO_FAILURE'}
}finally{
    $full=[IO.Path]::GetFullPath($temp);$allowed=[IO.Path]::GetFullPath((Join-Path $root '.tmp-recognition-policy-tests')).TrimEnd('\')+'\'
    if(-not $full.StartsWith($allowed,[StringComparison]::OrdinalIgnoreCase)){throw 'UNSAFE_TEST_CLEANUP'}
    Remove-Item -LiteralPath $full -Recurse -Force
}
Write-Host 'AUTO_EDIT_RECOGNITION_POLICY_OK:model-quality-finishes-with-review;no-fake-edit-or-caption;technical-errors-and-cancel-propagate'
