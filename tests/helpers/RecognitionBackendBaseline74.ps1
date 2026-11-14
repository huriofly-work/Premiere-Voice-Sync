# Frozen invocation behavior from v2.20.74, retained as a parity oracle.
function Invoke-PvsLegacyCaptionRecognition {
    param([string]$WhisperPath,[string]$CpuWhisperPath,[string]$ModelPath,[string]$ModelName,[string]$WavPath,[string]$OutBase,[string]$Language,[string]$Backend='cpu',[string[]]$BackendArguments=@(),[string]$Prompt='',[bool]$UseDtw=$true,[bool]$SplitOnWord=$true)
    $dtw=@()
    if($UseDtw){
        if($ModelName -notin @('tiny','tiny.en','base','base.en','small','small.en','medium','medium.en','large.v1','large.v2','large.v3','large.v3.turbo')){throw 'CAPTION_DTW_MODEL_UNSUPPORTED'}
        $dtw=@('-dtw',$ModelName,'-nfa')
    }
    $common=@('-m',$ModelPath,'-f',$WavPath,'-l',$Language,'-ojf')
    if($SplitOnWord){$common+=@('-ml','1','-sow')}
    $common+=@('-np','-of',$OutBase)+$dtw
    if($Prompt){$common+=@('--prompt',$Prompt)}
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
    [pscustomobject]@{Json=(Get-Content -LiteralPath ($OutBase+'.json') -Raw -Encoding UTF8 | ConvertFrom-Json);Backend=$Backend;FallbackReason=$reason;InvocationCount=$calls}
}