param([Parameter(Mandatory)][string]$MediaPath,[Parameter(Mandatory)][string]$SrtPath,[int]$ExpectedFirstCue=1,[int]$ExpectedLastCue=0,[string]$BackendDataRoot,[switch]$ShowNumericDiagnostics,[double]$FrameRate=30,[string]$ExportedCaptionSrtPath='',[string]$AcceptedCaptionSrtPath='')
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
if($ShowNumericDiagnostics){$VerbosePreference='Continue'}
$root=Resolve-Path (Join-Path $PSScriptRoot '..\..')
. "$root\extension\engine\lib\Native.ps1"
. "$root\extension\engine\lib\Srt.ps1"
. "$root\extension\engine\lib\Alignment.ps1"
. "$root\extension\engine\lib\CaptionOnly.ps1"
$folder=Join-Path $env:TEMP ('PVS-ReferenceCase-'+[guid]::NewGuid().ToString('N'))
Assert-PvsSafePath -Path $folder
$previousLocal=$env:LOCALAPPDATA
try {
    New-Item -ItemType Directory -Path $folder | Out-Null
    $env:LOCALAPPDATA=Join-Path $folder 'local'
    if($BackendDataRoot){$data=Join-Path $env:LOCALAPPDATA 'PremiereVoiceSync';New-Item -ItemType Directory -Path $data -Force | Out-Null;Copy-Item -LiteralPath (Join-Path $BackendDataRoot 'backends') -Destination $data -Recurse;Copy-Item -LiteralPath (Join-Path $BackendDataRoot 'backend-state.json') -Destination $data}
    $wav=Join-Path $folder 'input.wav'
    $native=Invoke-NativeCapture -FilePath (Join-Path $root 'extension\engine\runtime\bin\ffmpeg.exe') -Arguments @('-y','-hide_banner','-loglevel','error','-i',$MediaPath,'-ar','16000','-ac','1','-c:a','pcm_s16le',$wav)
    if ($native.ExitCode -ne 0) { throw 'CASE_WAV_FAILED' }
    $duration=Get-PvsPcmWaveDuration -Path $wav
    $job=[ordered]@{schemaVersion=1;workflow='caption-only';sequenceId='explicit-media-test';snapshot='unchanged';frameRate=$FrameRate;language='vi';maxCaptionCharacters=42;targetSrtPath=$SrtPath;outputFolder=$folder;sources=@([ordered]@{start=0.0;end=$duration;path=$wav})}
    $jobPath=Join-Path $folder 'job.json'
    $job | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $jobPath -Encoding UTF8
    $failure=$null
    try { & "$root\extension\engine\run-captions.ps1" -JobPath $jobPath } catch { $failure=$_.Exception.Message }
    $reference=@(Read-SrtFile $SrtPath)
    if($ExpectedLastCue -eq 0){$ExpectedLastCue=$reference.Count}
    Write-Host "CASE:duration=$duration;referenceCues=$($reference.Count);expected=$ExpectedFirstCue-$ExpectedLastCue;failure=$failure"
    if (-not $failure) {
        $result=Get-Content -LiteralPath (Join-Path $folder 'caption-result.json') -Raw -Encoding UTF8 | ConvertFrom-Json
        Write-Host "CAPTION_TIMING:mode=$($result.captionTimingMode);reasons=$($result.captionTimingReasons -join ';');review=$($result.captionTimingReviewCues -join ',');refined=$($result.captionTimingRefinedCues -join ',')"
        if($result.language -eq 'vi' -and $result.captionTimingMode -ne 'dtw-word-boundary-v1'){throw 'REFERENCE_DTW_TIMING_NOT_ENABLED'}
        $captions=@(Read-SrtFile $result.captionSrtPath)
        $expected=@($reference | Where-Object {$_.Index -ge $ExpectedFirstCue -and $_.Index -le $ExpectedLastCue})
        if (($captions.Text -join ' ') -ne ($expected.Text -join ' ')) { throw 'REFERENCE_CONTENT_CHANGED' }
        if($result.referenceScopeRanges[0].firstCue -ne $ExpectedFirstCue -or $result.referenceScopeRanges[-1].lastCue -ne $ExpectedLastCue){throw 'REFERENCE_SCOPE_WRONG'}
        if (@($captions | Where-Object {$_.Text.Length -gt 42 -or $_.End -le $_.Start}).Count) { throw 'REFERENCE_CAPTION_LIMIT_FAILED' }
        $previousEnd=0.0
        foreach ($caption in $captions) {
            if ($caption.Start -lt $previousEnd-0.001 -or $caption.Start -lt 0 -or $caption.End -gt $duration+0.001) { throw 'REFERENCE_CAPTION_TIMELINE_INVALID' }
            $previousEnd=$caption.End
        }
        Write-Host ('REFERENCE_REVIEW_CUES:'+(@($result.referenceReviewCues | ForEach-Object {$_.cueIndex}) -join ','))
        if($AcceptedCaptionSrtPath){
            $accepted=@(Read-SrtFile $AcceptedCaptionSrtPath)
            if($accepted.Count -ne $captions.Count){throw 'DTW_ACCEPTED_CAPTION_COUNT_CHANGED'}
            for($i=0;$i -lt $accepted.Count;$i++){if($accepted[$i].Text -cne $captions[$i].Text -or [Math]::Abs($accepted[$i].Start-$captions[$i].Start) -gt 0.001 -or [Math]::Abs($accepted[$i].End-$captions[$i].End) -gt 0.001){throw "DTW_ACCEPTED_CAPTION_CHANGED:$($i+1)"}}
            Write-Host 'DTW_ACCEPTED_SRT_MATCH:all-text-and-edges-within-one-millisecond'
        }
        Write-Host "NUMERIC_CAPTIONS:refined=$($result.numericCaptionRefinedCues -join ',');review=$($result.numericCaptionReviewCues -join ',');calls=$($result.numericCaptionInvocationCount)"
        @($captions | Where-Object {$_.Text -match '1979|Trong Alien:|Hôm nay|Hans|Giger|^R\.$|Đây là tàu|về sau được gọi|con tàu bỏ hoang'}) | Select-Object Start,End,Text | Format-Table -AutoSize
        if($ExportedCaptionSrtPath){
            $exported=@(Read-SrtFile $ExportedCaptionSrtPath)
            if((@(ConvertTo-NormalizedWords ($exported.Text -join ' ')) -join ' ') -ne (@(ConvertTo-NormalizedWords ($captions.Text -join ' ')) -join ' ')){throw 'EXPORTED_CAPTION_CONTENT_DIFFERS_FROM_FIXTURE'}
            $newBoundaries=@{};$cursor=0
            foreach($caption in $captions){$cursor+=@(ConvertTo-NormalizedWords $caption.Text).Count;$newBoundaries[$cursor]=$caption.End}
            $removed=New-Object System.Collections.Generic.List[int];$shifted=New-Object System.Collections.Generic.List[int];$cursor=0
            foreach($caption in $exported){
                $cursor+=@(ConvertTo-NormalizedWords $caption.Text).Count
                if(-not $newBoundaries.ContainsKey($cursor)){$removed.Add([int]$caption.Index)}
                elseif([Math]::Abs([double]$caption.End-[double]$newBoundaries[$cursor]) -gt 2/$FrameRate){$shifted.Add([int]$caption.Index)}
            }
            Write-Host "EXPORTED_CAPTION_AUDIT:old=$($exported.Count);new=$($captions.Count);all-words-preserved;removed-cut-indices=$($removed.ToArray() -join ',');same-word-cut-shift-over-2-frames=$($shifted.ToArray() -join ',')"
            Write-Host 'AUDIT_LIMIT:changed boundaries identify listening-review locations; not proof of speech accuracy.'
        }
        Write-Host "REFERENCE_MEDIA_OK:captions=$($captions.Count);backend=$($result.recognitionBackendLabel);edgeRetries=$($result.recognitionEdgeRetryCount);text-preserved"
    }
    if ($failure) { throw $failure }
} finally { $env:LOCALAPPDATA=$previousLocal;Remove-PvsSafeTree -Path $folder -Root $env:TEMP }
