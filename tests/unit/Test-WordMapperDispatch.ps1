$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$root=Resolve-Path (Join-Path $PSScriptRoot '..\..')
. "$root\extension\engine\lib\Alignment.ps1"
$target=@(for($i=0;$i -lt 400;$i++){'word'+($i%23)})
$words=@(for($i=0;$i -lt 401;$i++){[pscustomobject]@{Text='word'+($i%23)}})
$reference=@(Get-PvsReferenceWordMapping $target $words)
$actual=@(Get-SequentialWordMapping $target $words)
if(($reference -join ',') -cne ($actual -join ',')){throw 'WORD_MAPPER_AUTO_PARITY'}
if(-not ('PremiereVoiceSync.RollingWordMapperV1' -as [type])){throw 'WORD_MAPPER_FAST_NOT_LOADED'}
# Non-string input stays on PowerShell coercion semantics, without disabling
# the eligible fast path for the rest of the process.
$words[0].Text=1
if((@(Get-PvsReferenceWordMapping $target $words) -join ',') -cne (@(Get-SequentialWordMapping $target $words) -join ',')){throw 'WORD_MAPPER_COERCION_CHANGED'}
if(Get-Variable PvsWordMapperDisabled -Scope Script -ErrorAction SilentlyContinue){throw 'WORD_MAPPER_INELIGIBLE_DISABLED_ACCELERATOR'}
$words[0].Text='word0'
$script:fastCalls=0
function Invoke-PvsCompiledWordMapping {param($TargetWords,$RecognizedWords);$script:fastCalls++;throw 'COMPILER_OR_RUNTIME_UNAVAILABLE'}
$small=@(Get-SequentialWordMapping @('a') @([pscustomobject]@{Text='a'}))
if($small.Count -ne 1 -or $small[0] -ne 0 -or $script:fastCalls -ne 0){throw 'WORD_MAPPER_TINY_WINDOW_COMPILE_OVERHEAD'}
foreach($attempt in 1..2){
    $actual=@(Get-SequentialWordMapping $target $words)
    if(($actual -join ',') -cne ($reference -join ',')){throw 'WORD_MAPPER_UNAVAILABLE_CHANGED_MAPPING'}
}
if($script:fastCalls -ne 1){throw 'WORD_MAPPER_FAILURE_RETRIED'}
Write-Host 'WORD_MAPPER_DISPATCH_OK:auto-fast-parity;small-reference;non-string-reference;unavailable-fallback;no-repeated-failure'
