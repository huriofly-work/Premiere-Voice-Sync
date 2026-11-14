$ErrorActionPreference='Stop'
& node (Join-Path $PSScriptRoot 'srt-join.test.js')
if($LASTEXITCODE -ne 0){throw 'SRT_JOIN_FAILED'}
. (Join-Path $PSScriptRoot '..\..\extension\engine\lib\Srt.ps1')
. (Join-Path $PSScriptRoot '..\..\extension\engine\lib\Security.ps1')
$folder=Join-Path $env:TEMP ('PVS-SrtJoin-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $folder | Out-Null
try{
    $output=Join-Path $folder 'joined.srt'
    $module=Join-Path $PSScriptRoot '..\..\extension\js\srt-join.js'
    $script=Join-Path $folder 'write-fixture.js'
    [IO.File]::WriteAllText($script,'const j=require(process.argv[2]);const f=[{path:"one.srt",text:"1\n00:00:00,500 --> 00:00:02,000\nCh\u00e0o.\n"},{path:"two.srt",text:"1\n00:00:00,250 --> 00:00:01,000\nTi\u1ebfp.\n"}];require("fs").writeFileSync(process.argv[3],j.join(f,"append").text,"utf8");')
    & node $script $module $output
    if($LASTEXITCODE -ne 0){throw 'SRT_JOIN_FIXTURE_FAILED'}
    $cues=@(Read-SrtFile $output)
    if($cues.Count -ne 2 -or $cues[0].Index -ne 1 -or $cues[1].Index -ne 2 -or $cues[1].Start -ne 2.25 -or $cues[1].End -ne 3.0 -or $cues[0].Text -cne ('Ch'+[char]0xE0+'o.')){throw 'SRT_JOIN_ENGINE_CONTRACT_FAILED'}
    Write-Host 'SRT_JOIN_ENGINE_OK:existing-parser;UTF8;continuous-indices;appended-time'
}finally{Remove-PvsSafeTree -Path $folder -Root $env:TEMP}
