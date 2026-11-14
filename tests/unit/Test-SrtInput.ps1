$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$root=Resolve-Path (Join-Path $PSScriptRoot '..\..')
. "$root\extension\engine\lib\Srt.ps1"
. "$root\extension\engine\lib\Security.ps1"
$temp=Join-Path $env:TEMP ('PVS-SrtInput-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $temp | Out-Null
try{
    $path=Join-Path $temp 'input.srt'
    [IO.File]::WriteAllText($path,"1`n0:00:00,000 --> 0:00:01,000`nHello.`n `t `n2`n00:00:01,000 --> 00:00:02,000`nWorld.")
    $items=@(Read-SrtFile $path)
    if($items.Count -ne 2 -or $items[1].Text -ne 'World.'){throw 'SRT_VALID_CUE_DROPPED'}
    foreach($bad in @(
        "2`n00:00:01,00 --> 00:00:02,000`nMalformed.",
        "2`n00:60:00,000 --> 00:60:01,000`nBad minutes.",
        "2`n00:00:60,000 --> 00:01:01,000`nBad seconds.",
        "2`n00:00:02,000 --> 00:00:01,000`nBackwards.",
        "2`n00:00:01,000 --> 00:00:01,000`nEmpty duration.",
        "2`n00:00:01,000 --> 00:00:02,000"
    )){
        [IO.File]::WriteAllText($path,"1`n00:00:00,000 --> 00:00:01,000`nGood.`n`n"+$bad)
        $rejected=$false
        try{Read-SrtFile $path | Out-Null}catch{$rejected=$_.Exception.Message -match 'SRT_|Timecode SRT'}
        if(-not $rejected){throw 'SRT_MALFORMED_CUE_SILENTLY_IGNORED'}
    }
    Write-Host 'SRT_INPUT_OK:one-digit-hour;whitespace-separators;malformed-mixed-cue-rejected;timestamp-range;positive-duration;text-required'
}finally{Remove-PvsSafeTree -Path $temp -Root $env:TEMP}
