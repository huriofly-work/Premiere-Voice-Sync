param([string]$BaselineRef='v2.20.22',[int]$CueCount=300)
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$root=Resolve-Path (Join-Path $PSScriptRoot '..\..')
. "$root\extension\engine\lib\Alignment.ps1"
$old=(& git -C $root show "${BaselineRef}:extension/engine/lib/Alignment.ps1") -join "`n"
if($LASTEXITCODE -ne 0){throw 'BASELINE_SOURCE_UNAVAILABLE'}
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseInput($old,[ref]$tokens,[ref]$errors)
$fn=$ast.Find({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Align-CuesToRecognizedWords'},$true)
if(-not $fn){throw 'BASELINE_FUNCTION_MISSING'}
. ([scriptblock]::Create($fn.Extent.Text.Replace('function Align-CuesToRecognizedWords','function Invoke-LegacyCueAlignment')))
# Isolate cue partitioning from the unchanged O(n*m) lexical mapper/ASR.
# Known mappings include deleted words, substitutions and multiple chapters.
function Get-SequentialWordMapping {param($TargetWords,$RecognizedWords);return $script:fixtureMapping}
$random=New-Object Random 22022
$voices=@([pscustomobject]@{start=0},[pscustomobject]@{start=100},[pscustomobject]@{start=200})
$cues=New-Object System.Collections.Generic.List[object]
$recognized=New-Object System.Collections.Generic.List[object]
$maps=New-Object System.Collections.Generic.List[int]
for($i=0;$i -lt $CueCount;$i++){
    $words=New-Object System.Collections.Generic.List[string]
    $count=if($i%17 -eq 0){0}else{$random.Next(3,12)}
    for($w=0;$w -lt $count;$w++){
        $text='w'+$random.Next(10);$words.Add($text)
        $index=$recognized.Count
        $recognized.Add([pscustomobject]@{Text=$(if($i%13 -eq 0){'other'}else{$text});Chapter=($i%3);Start=$index*0.1;End=$index*0.1+0.09})
        $maps.Add($(if($i%11 -eq 0 -or $w%7 -eq 6){-1}else{$index}))
    }
    $cues.Add([pscustomobject]@{Text=$words -join ' ';Start=[double]$i;End=$i+0.9})
}
$script:fixtureMapping=$maps.ToArray()
$results=@()
foreach($name in @('Invoke-LegacyCueAlignment','Align-CuesToRecognizedWords')){
    $watch=[Diagnostics.Stopwatch]::StartNew()
    $value=@(& $name -Cues $cues.ToArray() -RecognizedWords $recognized.ToArray() -VoiceClips $voices)
    $watch.Stop()
    $results+=,[pscustomobject]@{Name=$name;Milliseconds=$watch.Elapsed.TotalMilliseconds;Json=ConvertTo-Json -InputObject $value -Depth 12 -Compress}
}
if($results[0].Json -cne $results[1].Json){throw 'CUE_ALIGNMENT_BASELINE_PARITY_FAILED'}
Write-Output ('CUE_ALIGNMENT_PARITY_OK:cues={0};words={1};legacyMs={2:F2};candidateMs={3:F2}' -f $CueCount,$maps.Count,$results[0].Milliseconds,$results[1].Milliseconds)
Write-Output 'Fixture only; excludes lexical DP, Whisper, FFmpeg and Premiere. No media/project/cache touched.'
