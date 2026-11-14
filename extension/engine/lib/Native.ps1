Set-StrictMode -Version Latest
. "$PSScriptRoot\Security.ps1"
. "$PSScriptRoot\AudioCache.ps1"
. "$PSScriptRoot\RecognitionBackend.ps1"

function ConvertTo-NativeArgument {
    param([AllowEmptyString()][string]$Value)
    if ([string]::IsNullOrEmpty($Value)) { return '""' }
    if ($Value -notmatch '[\s"]') { return $Value }
    return '"' + ($Value -replace '(\\*)"', '$1$1\"' -replace '(\\+)$', '$1$1') + '"'
}

function Invoke-NativeCapture {
    param([Parameter(Mandatory)][string]$FilePath,[string[]]$Arguments=@(),[string]$WorkingDirectory='')
    $filterIndex=[Array]::IndexOf($Arguments,'-af')
    if($filterIndex -ge 0 -and $filterIndex+1 -lt $Arguments.Count -and $Arguments[$filterIndex+1] -like 'silencedetect=*' -and $Arguments -contains 'NUL'){
        return Invoke-PvsAudioCachedNative -Kind quiet -FilePath $FilePath -Arguments $Arguments -Execute {Invoke-PvsNativeCaptureUncached -FilePath $FilePath -Arguments $Arguments -WorkingDirectory $WorkingDirectory}
    }
    return Invoke-PvsNativeCaptureUncached -FilePath $FilePath -Arguments $Arguments -WorkingDirectory $WorkingDirectory
}

function Invoke-PvsNativeCaptureUncached {
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [string[]]$Arguments = @(),
        [string]$WorkingDirectory = ''
    )
    if (-not [IO.Path]::IsPathRooted($FilePath)) { throw 'SECURITY_NATIVE_PATH_MUST_BE_ABSOLUTE' }
    Assert-PvsSafePath -Path $FilePath
    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = $FilePath
    $startInfo.Arguments = (($Arguments | ForEach-Object { ConvertTo-NativeArgument ([string]$_) }) -join ' ')
    $startInfo.UseShellExecute = $false
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $startInfo.CreateNoWindow = $true
    if ($WorkingDirectory) { $startInfo.WorkingDirectory = $WorkingDirectory }
    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $startInfo
    if (-not $process.Start()) { throw "Khong khoi dong duoc: $FilePath" }
    $stdoutTask = $process.StandardOutput.ReadToEndAsync()
    $stderrTask = $process.StandardError.ReadToEndAsync()
    $process.WaitForExit()
    $stdout = $stdoutTask.Result
    $stderr = $stderrTask.Result
    $result = [pscustomobject]@{
        ExitCode = [int]$process.ExitCode
        StdOut = [string]$stdout
        StdErr = [string]$stderr
        Output = ([string]$stdout + [string]$stderr)
    }
    $process.Dispose()
    return $result
}

function Invoke-PvsWhisperCapture {
    param([string]$FilePath,[string[]]$Arguments,[string]$WorkingDirectory='')
    return Invoke-PvsAudioCachedNative -Kind whisper -FilePath $FilePath -Arguments $Arguments -Execute {Invoke-PvsWhisperCaptureUncached -FilePath $FilePath -Arguments $Arguments -WorkingDirectory $WorkingDirectory}
}

function Invoke-PvsWhisperCaptureUncached {
    param([string]$FilePath,[string[]]$Arguments,[string]$WorkingDirectory='')
    $promptIndex=[Array]::IndexOf($Arguments,'--prompt')
    if($promptIndex -lt 0){return Invoke-NativeCapture -FilePath $FilePath -Arguments $Arguments -WorkingDirectory $WorkingDirectory}
    # whisper.cpp expects UTF-8 prompt text, but Windows main() receives ANSI
    # argv. Its @response-file reader preserves bytes; paths still use the OS
    # code page, while prompt bytes must be UTF-8. No shell or global CP change.
    if($null -eq ('Pvs.NativeCodePage' -as [type])){
        Add-Type -TypeDefinition 'namespace Pvs { public static class NativeCodePage { [System.Runtime.InteropServices.DllImport("kernel32.dll")] public static extern uint GetACP(); } }'
    }
    $ansi=[Text.Encoding]::GetEncoding([int][Pvs.NativeCodePage]::GetACP())
    $utf8=New-Object Text.UTF8Encoding($false)
    $outIndex=[Array]::IndexOf($Arguments,'-of')
    if($outIndex -lt 0 -or $outIndex+1 -ge $Arguments.Count -or $promptIndex+1 -ge $Arguments.Count){throw 'WHISPER_RESPONSE_ARGUMENTS_INVALID'}
    $directory=Split-Path $Arguments[$outIndex+1] -Parent
    Assert-PvsSafePath -Path $directory
    $responsePath=Join-Path $directory ('whisper-args-'+[guid]::NewGuid().ToString('N')+'.txt')
    $stream=New-Object IO.MemoryStream
    try{
        # The CLI itself inserts argv[0] before reading these lines. An extra
        # executable name would be treated as a spurious input media file.
        $lines=$Arguments
        for($i=0;$i -lt $lines.Count;$i++){
            if($lines[$i] -match '[\r\n]'){throw 'WHISPER_RESPONSE_NEWLINE_REJECTED'}
            $encoding=if($i -eq $promptIndex+1){$utf8}else{$ansi}
            $bytes=$encoding.GetBytes($lines[$i]+"`n")
            $stream.Write($bytes,0,$bytes.Length)
        }
        [IO.File]::WriteAllBytes($responsePath,$stream.ToArray())
        return Invoke-NativeCapture -FilePath $FilePath -Arguments @('@'+$responsePath) -WorkingDirectory $WorkingDirectory
    } finally {
        $stream.Dispose()
        if(Test-Path -LiteralPath $responsePath){Remove-Item -LiteralPath $responsePath -Force}
    }
}

