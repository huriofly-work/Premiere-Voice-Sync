param(
    [Parameter(Mandatory)][string]$SrtPath,
    [Parameter(Mandatory)][string]$WhisperJsonPath,
    [Parameter(Mandatory)][string]$VoicePath,
    [double]$FrameRate = 30,
    [int]$MaxCharacters = 42,
    [int]$FocusCueIndex = 0,
    [int[]]$FocusCueIndexes = @(),
    [string]$PreviousLibraryPath
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$root = Resolve-Path (Join-Path $PSScriptRoot '..\..')
. (Join-Path $root 'extension\engine\lib\Srt.ps1')
. (Join-Path $root 'extension\engine\lib\Alignment.ps1')

$cues = @(Read-SrtFile $SrtPath)
$words = @(Convert-WhisperJsonToWords -Path $WhisperJsonPath -ChapterIndex 0)
if ($cues.Count -eq 0 -or $words.Count -eq 0) { throw 'REAL_CAPTION_FIXTURE_EMPTY' }
$voiceClip = [pscustomobject]@{ start=0.0; end=([double]$words[$words.Count - 1].End + 2.0) }
$aligned = @(Align-CuesToRecognizedWords -Cues $cues -RecognizedWords $words -VoiceClips @($voiceClip))
$ffmpeg = Join-Path $root 'extension\engine\runtime\bin\ffmpeg.exe'
$previousPreference = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
$silenceOutput = & $ffmpeg -hide_banner -i $VoicePath -af 'silencedetect=noise=-35dB:d=0.12' -f null NUL 2>&1
$ErrorActionPreference = $previousPreference
$silences = [System.Collections.Generic.List[object]]::new()
$pending = $null
foreach ($line in $silenceOutput) {
    $value = [string]$line
    if ($value -match 'silence_start:\s*([0-9.]+)') { $pending = [double]$Matches[1]; continue }
    if ($null -ne $pending -and $value -match 'silence_end:\s*([0-9.]+)') {
        $end = [double]$Matches[1]
        $silences.Add([pscustomobject]@{ Start=$pending; End=$end; Duration=($end - $pending) })
        $pending = $null
    }
}
$captionCount = 0
$failures = [System.Collections.Generic.List[string]]::new()
foreach ($cue in $aligned) {
    if ($null -eq $cue.Start -or $null -eq $cue.End) { $failures.Add("UNMAPPED:$($cue.Index)"); continue }
    try {
        $parts = @(Split-PvsVoiceAlignedCaptionCue -Cue $cue -MaxCharacters $MaxCharacters -FrameRate $FrameRate -VoiceSilences ($silences.ToArray()))
        if ([int]$cue.Index -eq $FocusCueIndex -or $FocusCueIndexes -contains [int]$cue.Index) {
            foreach ($part in $parts) { Write-Host "AFTER:$($cue.Index):$($part.StartFrame)-$($part.EndFrame):$($part.Text)" }
        }
        $captionCount += $parts.Count
        foreach ($part in $parts) {
            if (([string]$part.Text).Length -gt $MaxCharacters) { $failures.Add("WIDTH:$($cue.Index)") }
            if ([int]$part.EndFrame -le [int]$part.StartFrame) { $failures.Add("DURATION:$($cue.Index)") }
        }
    } catch { $failures.Add("$($cue.Index):$($_.Exception.Message)") }
}
if (($FocusCueIndex -gt 0 -or $FocusCueIndexes.Count -gt 0) -and $PreviousLibraryPath) {
    $focusCues = @($aligned | Where-Object { [int]$_.Index -eq $FocusCueIndex -or $FocusCueIndexes -contains [int]$_.Index })
    Remove-Variable -Name PvsCaptionProtectedPairSet -Scope Script -ErrorAction SilentlyContinue
    . $PreviousLibraryPath
    foreach ($focusCue in $focusCues) {
        foreach ($part in @(Split-PvsVoiceAlignedCaptionCue -Cue $focusCue -MaxCharacters $MaxCharacters -FrameRate $FrameRate -VoiceSilences ($silences.ToArray()))) {
            Write-Host "BEFORE:$($focusCue.Index):$($part.StartFrame)-$($part.EndFrame):$($part.Text)"
        }
    }
}
Write-Host "REAL_CAPTION_CORPUS:cues=$($cues.Count);words=$($words.Count);silences=$($silences.Count);captions=$captionCount;failures=$($failures.Count)"
foreach ($failure in $failures) { Write-Host "CAPTION_FAILURE:$failure" }
if ($failures.Count -gt 0) { exit 1 }
