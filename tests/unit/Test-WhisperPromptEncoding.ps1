$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$root=Resolve-Path (Join-Path $PSScriptRoot '..\..')
. "$root\extension\engine\lib\Native.ps1"
$folder=Join-Path $env:TEMP ('PVS-PromptEncoding-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $folder | Out-Null
try {
    if((ConvertTo-NativeArgument '') -cne '""'){throw 'NATIVE_EMPTY_ARGUMENT_LOST'}
    # Capture response-file bytes at the process boundary; no ASR/model needed.
    function Invoke-NativeCapture {
        param($FilePath,$Arguments,$WorkingDirectory)
        if($Arguments.Count -ne 1 -or -not $Arguments[0].StartsWith('@')){throw 'PROMPT_NOT_PASSED_AS_RESPONSE_FILE'}
        $script:responsePath=$Arguments[0].Substring(1)
        $bytes=[IO.File]::ReadAllBytes($script:responsePath)
        if($bytes.Length -lt 3 -or $bytes[0] -ne 45 -or $bytes[1] -ne 109 -or $bytes[2] -ne 10){throw 'RESPONSE_FILE_HAS_SPURIOUS_EXECUTABLE_ARGUMENT'}
        $utf8=New-Object Text.UTF8Encoding($false,$true)
        $expected=$utf8.GetBytes("Năm một nghìn chín trăm bảy mươi chín.`n")
        $actual=$bytes[($bytes.Length-$expected.Length)..($bytes.Length-1)]
        if([Convert]::ToBase64String($actual) -ne [Convert]::ToBase64String($expected)){throw 'PROMPT_UTF8_BYTES_CHANGED'}
        return [pscustomobject]@{ExitCode=0;Output='mock';StdOut='';StdErr=''}
    }
    $result=Invoke-PvsWhisperCapture -FilePath 'C:\not-executed.exe' -Arguments @('-m','C:\model.bin','-of',(Join-Path $folder 'result'),'--prompt','Năm một nghìn chín trăm bảy mươi chín.')
    if($result.ExitCode -ne 0 -or (Test-Path -LiteralPath $script:responsePath)){throw 'PROMPT_FILE_NOT_CLEANED'}
    $rejected=$false
    try{Invoke-PvsWhisperCapture -FilePath 'C:\not-executed.exe' -Arguments @('-of',(Join-Path $folder 'result'),'--prompt',"line1`nline2") | Out-Null}catch{$rejected=$_.Exception.Message -eq 'WHISPER_RESPONSE_NEWLINE_REJECTED'}
    if(-not $rejected -or @(Get-ChildItem -LiteralPath $folder).Count){throw 'PROMPT_NEWLINE_OR_CLEANUP_FAILED'}
    Write-Host 'WHISPER_PROMPT_ENCODING_OK:utf8-prompt-bytes;single-process-arg;owned-temp-cleaned;newlines-rejected'
} finally {Remove-PvsSafeTree -Path $folder -Root $env:TEMP}
