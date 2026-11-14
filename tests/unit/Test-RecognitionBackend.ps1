$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$root=Resolve-Path (Join-Path $PSScriptRoot '..\..')
. "$root\extension\engine\lib\CaptionTiming.ps1"
. "$PSScriptRoot\..\helpers\RecognitionBackendBaseline74.ps1"
$temp=Join-Path $env:TEMP ('PVS-RecognitionBackend-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $temp|Out-Null
$script:fixture='{"result":{"language":"vi"},"transcription":[{"text":" Nội dung ngoài SRT.","offsets":{"from":250,"to":1200},"tokens":[{"id":1,"text":" Nội","t_dtw":30}]},{"text":"","offsets":{"from":1500,"to":1500},"tokens":[]}]}'
function Invoke-PvsWhisperCapture {
    param($FilePath,$Arguments,$WorkingDirectory)
    $call=$script:captured.Count
    $script:captured.Add([pscustomobject]@{FilePath=$FilePath;Arguments=@($Arguments);WorkingDirectory=$WorkingDirectory})
    $out=$Arguments[[Array]::IndexOf([object[]]$Arguments,'-of')+1]+'.json'
    if($call -gt 0 -and (Test-Path -LiteralPath $out)){throw 'FALLBACK_DID_NOT_REMOVE_STALE_GPU_RESULT'}
    [IO.File]::WriteAllText($out,$script:fixture,(New-Object Text.UTF8Encoding($false)))
    if($script:scenario -eq 'fail-all'){return [pscustomobject]@{ExitCode=3;Output='native failure';CacheHit=$false}}
    if($call -eq 0 -and $script:scenario -eq 'gpu-fail'){return [pscustomobject]@{ExitCode=2;Output=" native`n failed ";CacheHit=$false}}
    $output=if($script:scenario -eq 'silent-cpu'){'CPU only'}else{'load_backend: loaded CUDA backend from C:\verified\ggml-cuda.dll'}
    [pscustomobject]@{ExitCode=0;Output=$output;CacheHit=($script:scenario -eq 'warm')}
}
$cases=@(
    @{Backend='cpu';Scenario='cold';Language='vi';UseDtw=$true;SplitOnWord=$true;ModelName='small'},
    @{Backend='cpu';Scenario='warm';Language='en';UseDtw=$true;SplitOnWord=$true;ModelName='small'},
    @{Backend='cuda';Scenario='cold';Language='auto';UseDtw=$true;SplitOnWord=$true;ModelName='small'},
    @{Backend='cuda';Scenario='warm';Language='vi';UseDtw=$true;SplitOnWord=$true;ModelName='small'},
    @{Backend='cuda';Scenario='silent-cpu';Language='vi';UseDtw=$true;SplitOnWord=$true;ModelName='small'},
    @{Backend='cuda';Scenario='gpu-fail';Language='vi';UseDtw=$true;SplitOnWord=$true;ModelName='small'},
    @{Backend='cuda';Scenario='fail-all';Language='vi';UseDtw=$true;SplitOnWord=$true;ModelName='small'},
    @{Backend='cpu';Scenario='cold';Language='zh';UseDtw=$false;SplitOnWord=$false;ModelName='small'},
    @{Backend='cpu';Scenario='cold';Language='en';UseDtw=$false;SplitOnWord=$true;ModelName='small'},
    @{Backend='cpu';Scenario='cold';Language='vi';UseDtw=$true;SplitOnWord=$true;ModelName='large.v3.turbo'},
    @{Backend='cpu';Scenario='cold';Language='vi';UseDtw=$true;SplitOnWord=$true;ModelName='unsupported'}
)
try{
    foreach($case in $cases){
        $parameters=@{WhisperPath=(Join-Path $temp 'gpu\whisper.exe');CpuWhisperPath=(Join-Path $temp 'cpu\whisper.exe');ModelPath=(Join-Path $temp 'model.bin');WavPath=(Join-Path $temp 'voice.wav');OutBase=(Join-Path $temp 'result');Language=$case.Language;Backend=$case.Backend;BackendArguments=@('--device','0');Prompt='Tên riêng "Null Seek" giữ nguyên.';UseDtw=$case.UseDtw;SplitOnWord=$case.SplitOnWord;ModelName=$case.ModelName}
        $records=@()
        foreach($function in @('Invoke-PvsLegacyCaptionRecognition','Invoke-PvsCaptionDtwRecognition')){
            if(Test-Path -LiteralPath ($parameters.OutBase+'.json')){Remove-Item -LiteralPath ($parameters.OutBase+'.json')}
            $script:captured=New-Object System.Collections.Generic.List[object];$script:scenario=$case.Scenario
            $errorText='';$result=$null
            try{$result=& $function @parameters}catch{$errorText=$_.Exception.Message}
            $summary=if($null -ne $result){[pscustomobject]@{Json=$result.Json;Backend=$result.Backend;FallbackReason=$result.FallbackReason;InvocationCount=$result.InvocationCount}}else{$null}
            $records+=,[pscustomobject]@{Commands=($script:captured.ToArray()|ConvertTo-Json -Depth 8 -Compress);Summary=($summary|ConvertTo-Json -Depth 10 -Compress);Error=$errorText}
            if($null -ne $result -and $function -eq 'Invoke-PvsCaptionDtwRecognition'){
                $canonical=$result.Result
                if($canonical.SchemaVersion -ne 1 -or $canonical.BackendId -ne 'whisper.cpp' -or $canonical.ModelId -cne $case.ModelName -or $canonical.RequestedLanguage -cne $case.Language -or $canonical.DetectedLanguage -cne 'vi'){throw 'RECOGNITION_PROFILE_OR_LANGUAGE_CHANGED'}
                if($canonical.Text -cne ' Nội dung ngoài SRT.' -or $canonical.TimeUnit -cne 'seconds' -or $canonical.Coordinates -cne 'source-window-relative' -or $canonical.Segments[0].Start -ne 0.25 -or $canonical.Segments[0].End -ne 1.2){throw 'RECOGNITION_TEXT_OR_COORDINATES_CHANGED'}
                if($canonical.Words.Count -or $canonical.Timing.Verified -or $canonical.Timing.DtwRequested -ne $case.UseDtw -or $canonical.Segments[1].Start -ne $canonical.Segments[1].End){throw 'RAW_SEGMENT_OR_DTW_PROMOTED_TO_VERIFIED_WORDS'}
                if(($canonical.Raw|ConvertTo-Json -Depth 10 -Compress) -cne ($result.Json|ConvertTo-Json -Depth 10 -Compress)){throw 'RAW_RECOGNITION_CHANGED'}
            }
        }
        if(($records[0]|ConvertTo-Json -Depth 12 -Compress) -cne ($records[1]|ConvertTo-Json -Depth 12 -Compress)){throw "RECOGNITION_74_PARITY_FAILED:$($case|ConvertTo-Json -Compress)"}
    }
    $profile=New-PvsWhisperRecognitionProfile 'pinned-model.bin' small
    $profile.BackendId='unregistered-backend';$caught=$false
    try{Invoke-PvsRecognitionBackend $profile}catch{if($_.Exception.Message -eq 'RECOGNITION_BACKEND_UNSUPPORTED'){$caught=$true}else{throw}}
    if(-not $caught){throw 'UNREGISTERED_RECOGNITION_BACKEND_EXECUTED'}
    Write-Host 'RECOGNITION_BACKEND_OK:74-command-result-parity;CPU-CUDA-fallback;cache-counts;languages;Unicode-prompt;DTW-preset;raw-output;seconds-once;no-fake-word-timing;unknown-backend-rejected'
}finally{if(Test-Path -LiteralPath $temp){$resolved=[IO.Path]::GetFullPath($temp);$expected=[IO.Path]::GetFullPath($env:TEMP).TrimEnd('\')+'\PVS-RecognitionBackend-';if(-not $resolved.StartsWith($expected,[StringComparison]::OrdinalIgnoreCase)){throw 'UNSAFE_TEST_TEMP'};Remove-Item -LiteralPath $resolved -Recurse -Force}}
