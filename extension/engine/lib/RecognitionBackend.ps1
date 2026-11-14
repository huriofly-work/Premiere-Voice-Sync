Set-StrictMode -Version Latest

function New-PvsWhisperRecognitionProfile {
    param([string]$ModelPath,[string]$ModelName)
    # The caller still verifies runtime-lock/CUDA-lock. This descriptor never
    # authorizes a new model, downloads weights, or changes a running job.
    [pscustomobject]@{SchemaVersion=1;BackendId='whisper.cpp';ModelId=$ModelName;ModelPath=$ModelPath;
        Capabilities=[pscustomobject]@{Text=$true;NativeDtwCandidates=$true;VerifiedWordTiming=$false}}
}

function Get-PvsWhisperRecognitionArguments {
    param([string]$ModelPath,[string]$ModelName,[string]$WavPath,[string]$OutBase,[string]$Language,
        [string]$Prompt='',[bool]$UseDtw=$false,[bool]$SplitOnWord=$true)
    $dtw=@()
    if($UseDtw){
        if($ModelName -notin @('tiny','tiny.en','base','base.en','small','small.en','medium','medium.en','large.v1','large.v2','large.v3','large.v3.turbo')){throw 'CAPTION_DTW_MODEL_UNSUPPORTED'}
        $dtw=@('-dtw',$ModelName,'-nfa')
    }
    $arguments=@('-m',$ModelPath,'-f',$WavPath,'-l',$Language,'-ojf')
    if($SplitOnWord){$arguments+=@('-ml','1','-sow')}
    $arguments+=@('-np','-of',$OutBase)+$dtw
    if($Prompt){$arguments+=@('--prompt',$Prompt)}
    return $arguments
}

function ConvertFrom-PvsWhisperRecognitionResult {
    param($Raw,$Profile,[string]$Language,[bool]$DtwRequested)
    $segments=New-Object System.Collections.Generic.List[object]
    $pieces=New-Object System.Collections.Generic.List[string]
    $parsed=$null -ne $Raw -and $Raw.PSObject.Properties['transcription']
    if($parsed){
        foreach($segment in $Raw.transcription){
            $text=if($segment.PSObject.Properties['text']){[string]$segment.text}else{''}
            $pieces.Add($text);$start=$null;$end=$null
            if($segment.PSObject.Properties['offsets'] -and $null -ne $segment.offsets){
                $start=[double]$segment.offsets.from/1000.0;$end=[double]$segment.offsets.to/1000.0
            }
            # Native segment bounds, including zero/past-edge hypotheses, are
            # NOT verified acoustic word timing. Existing guards decide their
            # usability after the physical WAV duration/energy is known.
            $segments.Add([pscustomobject]@{Text=$text;Start=$start;End=$end;TimingQuality='native-unverified'})
        }
    }
    $detected=''
    if($null -ne $Raw -and $Raw.PSObject.Properties['result'] -and $null -ne $Raw.result -and $Raw.result.PSObject.Properties['language']){$detected=[string]$Raw.result.language}
    [pscustomobject]@{SchemaVersion=1;BackendId=$Profile.BackendId;ModelId=$Profile.ModelId;
        RequestedLanguage=$Language;DetectedLanguage=$detected;Text=($pieces.ToArray() -join '');
        Segments=$segments.ToArray();Words=@();TimeUnit='seconds';Coordinates='source-window-relative';
        ParseStatus=$(if($parsed){'parsed'}else{'unsupported-raw-format'});
        Timing=[pscustomobject]@{Provider='whisper.cpp';DtwRequested=$DtwRequested;Verified=$false;RawDtwTimeUnit='centiseconds'};
        RawFormat='whisper.cpp-full-json';Raw=$Raw}
}

function Invoke-PvsRecognitionBackend {
    param($Profile,[string]$WhisperPath,[string]$CpuWhisperPath,[string]$WavPath,[string]$OutBase,[string]$Language,
        [string]$Backend='cpu',[string[]]$BackendArguments=@(),[string]$Prompt='',[bool]$UseDtw=$true,[bool]$SplitOnWord=$true)
    if($Profile.SchemaVersion -ne 1 -or $Profile.BackendId -ne 'whisper.cpp'){throw 'RECOGNITION_BACKEND_UNSUPPORTED'}
    $common=@(Get-PvsWhisperRecognitionArguments -ModelPath $Profile.ModelPath -ModelName $Profile.ModelId -WavPath $WavPath -OutBase $OutBase -Language $Language -Prompt $Prompt -UseDtw $UseDtw -SplitOnWord $SplitOnWord)
    $run=Invoke-PvsWhisperCapture $WhisperPath (@($BackendArguments)+$common) -WorkingDirectory (Split-Path $WhisperPath -Parent)
    $calls=if($run.PSObject.Properties['CacheHit'] -and $run.CacheHit){0}else{1};$reason=''
    $gpuLoaded=$Backend -eq 'cpu' -or $run.Output -match '(?im)^load_backend:\s+loaded CUDA backend from .+ggml-cuda\.dll'
    if(($run.ExitCode -ne 0 -or -not $gpuLoaded) -and $Backend -ne 'cpu'){
        $reason=if($run.ExitCode -eq 0 -and -not $gpuLoaded){'Whisper did not load CUDA for caption alignment.'}else{($run.Output -replace '\s+',' ').Trim()}
        $Backend='cpu'
        if(Test-Path -LiteralPath ($OutBase+'.json')){Remove-Item -LiteralPath ($OutBase+'.json') -Force}
        $run=Invoke-PvsWhisperCapture $CpuWhisperPath (@('--no-gpu')+$common) -WorkingDirectory (Split-Path $CpuWhisperPath -Parent)
        if(-not $run.PSObject.Properties['CacheHit'] -or -not $run.CacheHit){$calls++}
    }
    if($run.ExitCode -ne 0){throw "CAPTION_RECOGNITION_FAILED:$($run.Output)"}
    $raw=Get-Content -LiteralPath ($OutBase+'.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $result=ConvertFrom-PvsWhisperRecognitionResult -Raw $raw -Profile $Profile -Language $Language -DtwRequested $UseDtw
    # Json is the compatibility boundary for the existing acoustic/SRT core.
    [pscustomobject]@{Json=$raw;Result=$result;Backend=$Backend;FallbackReason=$reason;InvocationCount=$calls}
}
