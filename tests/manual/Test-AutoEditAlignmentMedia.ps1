param([Parameter(Mandatory)][string]$MediaRoot,[Parameter(Mandatory)][string]$SrtPath,[string]$WhisperCacheRoot,[string]$BackendDataRoot,[string]$MediaPattern='*.mp3',[int[]]$ReviewCueIndices=@())
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$root=Resolve-Path (Join-Path $PSScriptRoot '..\..')
. "$root\extension\engine\lib\Native.ps1"
. "$root\extension\engine\lib\Srt.ps1"
$folder=Join-Path $env:TEMP ('PVS-AutoAlignment-'+[guid]::NewGuid().ToString('N'))
$oldLocal=$env:LOCALAPPDATA
$oldTemp=$env:TEMP
Assert-PvsSafePath -Path $folder
try {
    New-Item -ItemType Directory -Path $folder -Force | Out-Null
    $env:LOCALAPPDATA=Join-Path $folder 'local'
    $env:TEMP=Join-Path $folder 'temp'
    New-Item -ItemType Directory -Path $env:TEMP -Force | Out-Null
    $cache=Join-Path $env:LOCALAPPDATA 'PremiereVoiceSync\Cache\Whisper'
    New-Item -ItemType Directory -Path $cache -Force | Out-Null
    if($BackendDataRoot) {
        $data=Join-Path $env:LOCALAPPDATA 'PremiereVoiceSync'
        Copy-Item -LiteralPath (Join-Path $BackendDataRoot 'backends') -Destination $data -Recurse
        Copy-Item -LiteralPath (Join-Path $BackendDataRoot 'backend-state.json') -Destination $data
    }
    $engine=Get-Content "$root\extension\engine\runtime\engine.json" -Raw -Encoding UTF8 | ConvertFrom-Json
    $voices=New-Object System.Collections.Generic.List[object]
    $cursor=0.0
    foreach($file in (Get-ChildItem -LiteralPath $MediaRoot -Filter $MediaPattern | Sort-Object Name)) {
        $duration=[double](& "$root\extension\engine\runtime\bin\ffprobe.exe" -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 $file.FullName)
        if($LASTEXITCODE -ne 0 -or $duration -le 0){throw 'MEDIA_DURATION_FAILED'}
        $voices.Add([ordered]@{name=$file.Name;path=$file.FullName;start=$cursor;end=$cursor+$duration;speedPercent=100})
        $cursor+=$duration
        if($WhisperCacheRoot) {
            $identity='{0}|{1}|{2}|{3}|vi-sow-v1' -f $file.FullName.ToLowerInvariant(),$file.Length,$file.LastWriteTimeUtc.Ticks,$engine.model
            $sha=[Security.Cryptography.SHA256]::Create()
            try{$key=([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($identity)))).Replace('-','').ToLowerInvariant()}finally{$sha.Dispose()}
            $source=Join-Path $WhisperCacheRoot "$key.json"
            if(Test-Path -LiteralPath $source){Copy-Item -LiteralPath $source -Destination $cache}
        }
    }
    if($voices.Count -eq 0){throw 'TEST_HAS_NO_VOICES'}
    $reference=@(Read-SrtFile $SrtPath)
    $job=[ordered]@{outputFolder=$folder;targetSrtPath=$SrtPath;speedWarningMinPercent=80;speedWarningMaxPercent=130;algorithm=[ordered]@{maxCaptionCharacters=42};sequence=[ordered]@{sequenceId='read-only-media-test';name='read-only-media-test';frameRate=30;mainVideoClip=[ordered]@{start=0;end=$reference[-1].End};linkedAudio=@();voiceTrackIndex=1;voices=$voices.ToArray()}}
    $jobPath=Join-Path $folder 'job.json'
    $job | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $jobPath -Encoding UTF8
    & "$root\extension\engine\run-alignment.ps1" -JobPath $jobPath
    $alignment=Get-Content (Join-Path $folder 'alignment-result.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    Write-Host "RECOVERY:cues=$($alignment.wordTimingRecoveredCues -join ',');calls=$($alignment.wordTimingRecoveryInvocationCount);backend=$($alignment.recognitionBackendLabel)"
    Write-Host "NUMERIC_CAPTIONS:refined=$($alignment.numericCaptionRefinedCues -join ',');review=$($alignment.numericCaptionReviewCues -join ',')"
    if(@($alignment.cues | Where-Object {$null -eq $_.Start -or $null -eq $_.End}).Count){throw 'MEDIA_STILL_HAS_UNALIGNED_CUES'}
    & "$root\extension\engine\build-sentence-plan.ps1" -JobPath $jobPath
    $plan=Get-Content (Join-Path $folder 'sentence-edit-plan.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    if(($plan.captions.Text -join ' ') -ne ($reference.Text -join ' ')){throw 'MEDIA_CAPTION_TEXT_CHANGED'}
    if(@($plan.captions | Where-Object {$_.Text.Length -gt 42 -or $_.End -le $_.Start}).Count){throw 'MEDIA_CAPTION_INVALID'}
    $previousEnd=0.0
    $previousCaption=$null
    foreach($caption in $plan.captions){if($caption.Start -lt $previousEnd-0.001){$previousCaption | ConvertTo-Json -Compress | Write-Host; $caption | ConvertTo-Json -Compress | Write-Host;throw "MEDIA_CAPTION_OVERLAP:cue-$($caption.SourceCueIndex):start-$($caption.Start):previousEnd-${previousEnd}:text-$($caption.Text)"};$previousEnd=$caption.End;$previousCaption=$caption}
    if($ReviewCueIndices.Count){@($plan.captions | Where-Object {$_.SourceCueIndex -in $ReviewCueIndices}) | Select-Object SourceCueIndex,Start,End,Text | Format-Table -AutoSize}
    Write-Host "AUTO_ALIGNMENT_MEDIA_OK:cues=$($reference.Count);recovered=$($alignment.wordTimingRecoveredCues -join ',');captions=$($plan.captions.Count);groups=$($plan.summary.safeSentenceGroupCount);backend=$($alignment.recognitionBackendLabel)"
} finally {
    $env:LOCALAPPDATA=$oldLocal
    $env:TEMP=$oldTemp
    Remove-PvsSafeTree -Path $folder -Root $oldTemp
}
