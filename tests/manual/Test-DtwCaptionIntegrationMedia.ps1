param(
    [Parameter(Mandatory)][string]$MediaRoot,
    [Parameter(Mandatory)][string]$SrtPath,
    [Parameter(Mandatory)][string]$BaselineEngineRoot,
    [string]$WhisperCacheRoot='',
    [string]$BackendDataRoot='',
    [string]$MediaPattern='*.mp3',
    [double]$FrameRate=30,
    [string]$FixtureJobPath='',
    [switch]$WarmCache,
    [int[]]$ReviewCaptionIndices=@(),
    [double]$VoiceSpeedPercent=100,
    [switch]$AllowCaptionTimingChanges,
    [switch]$AllowEditTimingChanges,
    [string]$ExportedCaptionSrtPath=''
)
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$root=Resolve-Path (Join-Path $PSScriptRoot '..\..')
. "$root\extension\engine\lib\Native.ps1"
. "$root\extension\engine\lib\Srt.ps1"
. "$root\extension\engine\lib\CaptionTiming.ps1"
. "$root\extension\engine\lib\DtwEditTrial.ps1"
# Extract only the existing read-only boundary finder; never execute planner
# or host code with experimental DTW edit inputs.
$ast=[Management.Automation.Language.Parser]::ParseFile("$root\extension\engine\build-sentence-plan.ps1",[ref]$null,[ref]$null)
$finder=$ast.Find({param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Find-SafeVoiceBoundary'},$true)
. ([scriptblock]::Create($finder.Extent.Text))
$folder=Join-Path $env:TEMP ('PVS-DtwIntegration-'+[guid]::NewGuid().ToString('N'))
$oldLocal=$env:LOCALAPPDATA;$oldTemp=$env:TEMP
try {
    New-Item -ItemType Directory -Path $folder | Out-Null
    $env:LOCALAPPDATA=Join-Path $folder 'local';$env:TEMP=Join-Path $folder 'temp'
    New-Item -ItemType Directory -Path $env:TEMP -Force | Out-Null
    $data=Join-Path $env:LOCALAPPDATA 'PremiereVoiceSync'
    $cache=Join-Path $data 'Cache\Whisper';New-Item -ItemType Directory -Path $cache -Force | Out-Null
    if($WhisperCacheRoot){
        Assert-PvsSafePath -Path $WhisperCacheRoot -Tree
        foreach($file in (Get-ChildItem -LiteralPath $WhisperCacheRoot -File -Filter '*.json')){Copy-Item -LiteralPath $file.FullName -Destination $cache}
        $rawCache=Join-Path $WhisperCacheRoot 'Audio-v1'
        if(Test-Path -LiteralPath $rawCache -PathType Container){Copy-Item -LiteralPath $rawCache -Destination $cache -Recurse}
    }
    if($BackendDataRoot){Copy-Item -LiteralPath (Join-Path $BackendDataRoot 'backends') -Destination $data -Recurse;Copy-Item -LiteralPath (Join-Path $BackendDataRoot 'backend-state.json') -Destination $data}
    $voices=New-Object System.Collections.Generic.List[object];$cursor=0.0
    $mediaFiles=if($FixtureJobPath){
        $fixture=Get-Content -LiteralPath $FixtureJobPath -Raw -Encoding UTF8 | ConvertFrom-Json
        if([IO.Path]::GetFullPath([string]$fixture.targetSrtPath) -cne [IO.Path]::GetFullPath($SrtPath)){throw 'DTW_FIXTURE_REFERENCE_PATH_MISMATCH'}
        @($fixture.sequence.voices | Sort-Object start | ForEach-Object {Get-Item -LiteralPath $_.path})
    }else{@(Get-ChildItem -LiteralPath $MediaRoot -File -Filter $MediaPattern | Sort-Object Name)}
    foreach($file in $mediaFiles){
        $duration=[double](& "$root\extension\engine\runtime\bin\ffprobe.exe" -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 $file.FullName)
        if($LASTEXITCODE -ne 0 -or $duration -le 0){throw 'DTW_FIXTURE_DURATION_FAILED'}
        if([double]::IsNaN($VoiceSpeedPercent) -or [double]::IsInfinity($VoiceSpeedPercent) -or $VoiceSpeedPercent -le 0){throw 'DTW_FIXTURE_SPEED_INVALID'}
        $timelineDuration=$duration*100.0/$VoiceSpeedPercent
        $voices.Add([ordered]@{name=$file.Name;path=$file.FullName;start=$cursor;end=$cursor+$timelineDuration;speedPercent=$VoiceSpeedPercent});$cursor+=$timelineDuration
    }
    if(-not $voices.Count){throw 'DTW_FIXTURE_VOICES_MISSING'}
    $reference=@(Read-SrtFile $SrtPath)
    $job=[ordered]@{outputFolder='';targetSrtPath=$SrtPath;speedWarningMinPercent=80;speedWarningMaxPercent=130;algorithm=[ordered]@{maxCaptionCharacters=42};sequence=[ordered]@{sequenceId='read-only-dtw-integration';name='read-only-dtw-integration';frameRate=$FrameRate;mainVideoClip=[ordered]@{start=0;end=$reference[-1].End};linkedAudio=@();voiceTrackIndex=1;voices=$voices.ToArray()}}
    $plans=@();$alignments=@();$measurements=@()
    if($WarmCache){
        # Prime only the disposable fixture cache. Both measured engines then
        # see the same entries; recognition misses must still be reported.
        $warmOutput=Join-Path $folder 'warmup';New-Item -ItemType Directory -Path $warmOutput | Out-Null
        $job.outputFolder=$warmOutput;$warmPath=Join-Path $warmOutput 'job.json'
        $job | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $warmPath -Encoding UTF8
        & "$BaselineEngineRoot\run-alignment.ps1" -JobPath $warmPath
        Write-Host 'FIXTURE_CACHE_PRIMED:not-in-measurements'
    }
    foreach($engine in @($BaselineEngineRoot,"$root\extension\engine")){
        $output=Join-Path $folder ('run-'+$plans.Count);New-Item -ItemType Directory -Path $output | Out-Null
        $job.outputFolder=$output;$path=Join-Path $output 'job.json'
        $job | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $path -Encoding UTF8
        $watch=[Diagnostics.Stopwatch]::StartNew()
        & "$engine\run-alignment.ps1" -JobPath $path
        $watch.Stop();$alignmentMs=$watch.Elapsed.TotalMilliseconds
        $watch.Restart()
        & "$engine\build-sentence-plan.ps1" -JobPath $path
        $watch.Stop()
        $alignment=Get-Content -LiteralPath (Join-Path $output 'alignment-result.json') -Raw -Encoding UTF8 | ConvertFrom-Json
        $alignments+=$alignment
        $measurements+=,[pscustomobject]@{engine=$(if($plans.Count -eq 0){'baseline'}else{'candidate'});alignmentMilliseconds=[Math]::Round($alignmentMs,2);plannerMilliseconds=[Math]::Round($watch.Elapsed.TotalMilliseconds,2);backend=$alignment.recognitionBackend;nativeRecognitionCalls=$alignment.backendInvocationCount;cache=$alignment.audioCache}
        $plans+=Get-Content -LiteralPath (Join-Path $output 'sentence-edit-plan.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    }
    if($AllowEditTimingChanges){
        Assert-PvsTrialPlanConservation $plans[0] $plans[1] | Out-Null
        Write-Host 'EDIT_TIMING_CHANGE_ALLOWED:source-voice-text-duration-conserved;cut-parity-not-required'
    }else{
    if(($plans[0].segments | ConvertTo-Json -Depth 12 -Compress) -cne ($plans[1].segments | ConvertTo-Json -Depth 12 -Compress)){throw 'DTW_CHANGED_EDIT_SEGMENTS'}
    if(($plans[0].markers | ConvertTo-Json -Depth 12 -Compress) -cne ($plans[1].markers | ConvertTo-Json -Depth 12 -Compress)){throw 'DTW_CHANGED_EDIT_MARKERS'}
    if(($alignments[0].cues | ConvertTo-Json -Depth 12 -Compress) -cne ($alignments[1].cues | ConvertTo-Json -Depth 12 -Compress)){throw 'DTW_CHANGED_FULL_CUE_OUTPUT'}
    }
    if(-not $AllowEditTimingChanges){
    if($AllowCaptionTimingChanges){
        $left=@($plans[0].captions | Select-Object * -ExcludeProperty Start,End)
        $right=@($plans[1].captions | Select-Object * -ExcludeProperty Start,End)
        if(($left | ConvertTo-Json -Depth 12 -Compress) -cne ($right | ConvertTo-Json -Depth 12 -Compress)){throw 'DTW_CHANGED_NON_TIMING_CAPTION_OUTPUT'}
        Write-Host 'CAPTION_TIMING_CHANGE_ALLOWED:all-other-caption-fields-and-edit-segments-markers-unchanged'
        $changed=@(for($c=0;$c -lt $plans[0].captions.Count;$c++){if($plans[0].captions[$c].Start -ne $plans[1].captions[$c].Start -or $plans[0].captions[$c].End -ne $plans[1].captions[$c].End){[int]$plans[1].captions[$c].Index}})
        Write-Host "CAPTION_CHANGED_INDICES:$($changed -join ',')"
    }elseif(($plans[0].captions | ConvertTo-Json -Depth 12 -Compress) -cne ($plans[1].captions | ConvertTo-Json -Depth 12 -Compress)){throw 'DTW_CHANGED_FULL_CAPTION_OUTPUT'}
    }
    for($i=0;$i -lt $alignments[0].cues.Count;$i++){
        $a=$alignments[0].cues[$i];$b=$alignments[1].cues[$i]
        $fields=if($AllowEditTimingChanges){@('Index','Text','OriginalStart','OriginalEnd','Chapter')}else{@('Start','End','OriginalStart','OriginalEnd','Chapter','Confidence','WordTimings')}
        foreach($field in $fields){
            if(($a.$field | ConvertTo-Json -Depth 8 -Compress) -cne ($b.$field | ConvertTo-Json -Depth 8 -Compress)){throw "DTW_CHANGED_EDIT_ALIGNMENT:cue-$($a.Index):$field"}
        }
    }
    if($alignments[1].captionTimingMode -ne 'dtw-word-boundary-v1'){throw 'AUTO_DTW_OVERLAY_NOT_USED'}
    Write-Host "AUTO_DTW:review-count=$($alignments[1].captionTimingReviewCues.Count);refined=$($alignments[1].captionTimingRefinedCues -join ',');reasons=$($alignments[1].captionTimingReasons -join ';')"
    $captions=@($plans[1].captions)
    if(($captions.Text -join ' ') -cne ($reference.Text -join ' ')){throw 'DTW_CHANGED_REFERENCE_TEXT'}
    $previousEnd=0.0
    foreach($caption in $captions){if($caption.Text.Length -gt 42 -or $caption.End -le $caption.Start -or $caption.Start -lt $previousEnd-0.000001){throw "DTW_CAPTION_INVALID:$($caption.Index)"};$previousEnd=$caption.End}
    # Read-only upgrade audit: how far the newer speech edges are from the
    # legacy cue boundaries. This is NOT a proposed cut or executor call.
    $differences=@($alignments[1].cues | Where-Object {$_.PSObject.Properties['CaptionTimingRevision']} | ForEach-Object {[pscustomobject]@{Cue=$_.Index;StartDriftFrames=[int][Math]::Round(($_.CaptionStart-$_.Start)*$FrameRate);EndDriftFrames=[int][Math]::Round(($_.CaptionEnd-$_.End)*$FrameRate)}})
    $large=@($differences | Where-Object {[Math]::Abs($_.StartDriftFrames) -gt 3 -or [Math]::Abs($_.EndDriftFrames) -gt 3})
    Write-Host "EDIT_TIMESTAMP_UPGRADE_AUDIT:dtw-overlays=$($differences.Count);cues-differ-over-three-frames=$($large.Count);not-proof-of-better-cuts"
    $large | Select-Object -First 12 | Format-Table -AutoSize
    $quiet=@(for($chapter=0;$chapter -lt $voices.Count;$chapter++){
        $run=Invoke-NativeCapture "$root\extension\engine\runtime\bin\ffmpeg.exe" @('-hide_banner','-i',$voices[$chapter].path,'-af','silencedetect=noise=-35dB:d=0.12','-f','null','NUL')
        if($run.ExitCode -ne 0){throw 'EDIT_AUDIT_QUIET_FAILED'}
        $pending=$null
        foreach($line in ($run.Output -split '\r?\n')){
            if($line -match 'silence_start:\s*([0-9.]+)'){$pending=[double]::Parse($Matches[1],[Globalization.CultureInfo]::InvariantCulture)}
            if($null -ne $pending -and $line -match 'silence_end:\s*([0-9.]+)'){$end=[double]::Parse($Matches[1],[Globalization.CultureInfo]::InvariantCulture);[pscustomobject]@{Start=$voices[$chapter].start+$pending;End=$voices[$chapter].start+$end;Duration=$end-$pending};$pending=$null}
        }
    })
    $audit=@(for($i=0;$i+1 -lt $alignments[1].cues.Count;$i++){
        $left=$alignments[1].cues[$i];$right=$alignments[1].cues[$i+1]
        if($left.Chapter -ne $right.Chapter -or $left.Text.Trim() -notmatch '[.!?;\u2026]$' -or -not $left.PSObject.Properties['CaptionTimingRevision'] -or -not $right.PSObject.Properties['CaptionTimingRevision']){continue}
        $old=Find-SafeVoiceBoundary (($left.End+$right.Start)/2) $quiet 0.12 0.12 0.04 $FrameRate
        $new=Find-SafeVoiceBoundary (($left.CaptionEnd+$right.CaptionStart)/2) $quiet 0.12 0.12 0.04 $FrameRate
        [pscustomobject]@{Cue=$left.Index;OldSafe=[bool]$old;DtwSafe=[bool]$new;Different=[bool]($old -and $new -and $old.CutFrame -ne $new.CutFrame)}
    })
    Write-Host "EDIT_SAFE_CUT_AUDIT:boundaries=$($audit.Count);legacy-safe=$(@($audit | Where-Object OldSafe).Count);dtw-safe=$(@($audit | Where-Object DtwSafe).Count);different-safe-cuts=$(@($audit | Where-Object Different).Count);diagnostic-only-not-a-plan"
    Write-Host "DTW_CAPTION_INTEGRATION_OK:allow-edit-timing=$([bool]$AllowEditTimingChanges);captions=$($captions.Count);voices=$($voices.Count);no-Premiere-mutation"
    if($ReviewCaptionIndices.Count){
        if($ExportedCaptionSrtPath){
            $exported=@(Read-SrtFile $ExportedCaptionSrtPath)
            foreach($index in $ReviewCaptionIndices){
                $actual=@($exported | Where-Object {$_.Index -eq $index})[0];$old=@($plans[0].captions | Where-Object {$_.Index -eq $index})[0]
                [pscustomobject]@{ExportedCaption=$index;TextMatches=$actual.Text -ceq $old.Text;BaselineStart=$old.Start;ExportedStart=$actual.Start;BaselineEnd=$old.End;ExportedEnd=$actual.End} | ConvertTo-Json -Compress
            }
        }
        foreach($caption in @($captions | Where-Object {$_.Index -in $ReviewCaptionIndices})){
            $segment=@($plans[1].segments | Where-Object {$_.Kind -eq 'retime' -and $caption.Start -ge $_.NewVoiceStart -and $caption.Start -lt $_.NewVoiceEnd})
            $cue=@($alignments[1].cues | Where-Object {$_.Index -eq $caption.SourceCueIndex})
            [pscustomobject]@{Caption=$caption.Index;SourceCue=$caption.SourceCueIndex;Text=$caption.Text;Start=$caption.Start;End=$caption.End;OriginalVoiceStart=$(if($segment.Count -eq 1){$caption.Start-$segment[0].NewVoiceStart+$segment[0].OriginalVoiceStart}else{$null});OriginalVoiceEnd=$(if($segment.Count -eq 1){$caption.End-$segment[0].NewVoiceStart+$segment[0].OriginalVoiceStart}else{$null});DtwOverlay=[bool]$cue[0].PSObject.Properties['CaptionTimingRevision'];WordTimings=$(if($cue[0].PSObject.Properties['CaptionWordTimings']){$cue[0].CaptionWordTimings}else{$cue[0].WordTimings})} | ConvertTo-Json -Depth 5 -Compress
        }
    }
    [pscustomobject]@{phase='alignment-and-base-planner';cachePrimed=[bool]$WarmCache;measurements=$measurements;limits='Copied cache/backend in an isolated fixture. Includes recognition misses if any; not native timeline/Preview/Save acceptance.'} | ConvertTo-Json -Depth 5
} catch {
    Write-Host $_.ScriptStackTrace
    if($ReviewCaptionIndices.Count -and (Get-Variable plans -ErrorAction SilentlyContinue) -and $plans.Count){
        $indices=@($plans[0].captions | Where-Object {$_.Index -in $ReviewCaptionIndices} | ForEach-Object {[int]$_.SourceCueIndex})
        foreach($index in $indices){@($plans[0].segments | Where-Object {$_.Kind -eq 'retime' -and $_.LastTargetCue -ge $index-3 -and $_.FirstTargetCue -le $index+3}) | Select-Object FirstTargetCue,LastTargetCue,OriginalVoiceStartFrame,OriginalVoiceEndFrame,NewVoiceStartFrame,NewVoiceEndFrame | ConvertTo-Json -Compress | Write-Host}
    }
    throw
}
finally {$env:LOCALAPPDATA=$oldLocal;$env:TEMP=$oldTemp;Remove-PvsSafeTree -Path $folder -Root $oldTemp}
