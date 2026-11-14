$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$root=Resolve-Path (Join-Path $PSScriptRoot '..\..')
. "$root\extension\engine\lib\Srt.ps1"
. "$root\extension\engine\lib\Alignment.ps1"
. "$root\extension\engine\lib\CaptionOnly.ps1"
foreach($name in @('H. R. Giger','H.R. Giger','J. R. R. Tolkien','J. Smith')){
    $text="Thiết kế con tàu đến từ nghệ sĩ Thụy Sĩ $name, tức Hans Giger."
    $parts=@(Get-PvsCaptionTextChunks $text 42)
    if(($parts.Text -join ' ') -ne $text -or @($parts | Where-Object {$_.Text.Length -gt 42}).Count){throw 'INITIAL_NAME_TEXT_OR_LIMIT_FAILED'}
    if(@($parts | Where-Object {$_.Text.Contains($name)}).Count -ne 1){throw "INITIAL_NAME_SPLIT:$name"}
}
if(Test-PvsCaptionInitialContinuation 'này.' 'Sau'){throw 'NORMAL_SENTENCE_STOP_PROTECTED'}
$surfaces=@('Thiết kế','H.','R.','Giger,','tức Hans Giger.')
$words=New-Object System.Collections.Generic.List[object]
$pieces=New-Object System.Collections.Generic.List[object]
for($i=0;$i -lt $surfaces.Count;$i++){
    $tokens=@(ConvertTo-NormalizedWords $surfaces[$i]);$first=$words.Count
    for($j=0;$j -lt $tokens.Count;$j++){$words.Add([pscustomobject]@{Text=$tokens[$j];Start=$i+$j/[double]$tokens.Count;End=$i+($j+1)/[double]$tokens.Count;Chapter=0})}
    $pieces.Add([pscustomobject]@{Text=$surfaces[$i];Start=[double]$i;End=[double]($i+1);FirstWord=$first;LastWord=$words.Count-1})
}
$cues=@(New-PvsRecognizedSubtitleCues $pieces.ToArray() $words.ToArray() 0 0)
if($cues.Count -ne 1 -or $cues[0].Text -notmatch 'H\. R\. Giger,'){throw 'RECOGNIZED_CUES_SPLIT_INITIALS'}
Write-Host 'CAPTION_INITIALS_OK:spaced-and-compact-initials;surname-kept;ordinary-stops-preserved;ASR-cues-kept'
