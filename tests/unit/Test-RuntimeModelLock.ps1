$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$root=Resolve-Path (Join-Path $PSScriptRoot '..\..')
. "$root\extension\engine\lib\Security.ps1"
. "$root\extension\engine\lib\RecognitionBackend.ps1"

# The shipped profile is Whisper large-v3-turbo; DTW must use its own
# alignment-head preset, and the lock must pin the published upstream weights.
$modelProfile=Get-PvsRuntimeModelProfile
if($modelProfile.Id -cne 'large.v3.turbo' -or $modelProfile.Path -cne 'models\ggml-large-v3-turbo.bin'){throw 'RUNTIME_MODEL_PROFILE_CHANGED'}
$repoConfig=Get-Content -LiteralPath "$root\extension\engine\engine-config.json" -Raw -Encoding UTF8|ConvertFrom-Json
if($repoConfig.model -cne $modelProfile.Id -or $repoConfig.modelPath -cne $modelProfile.Path){throw 'ENGINE_CONFIG_NOT_TURBO'}
$repoLock=Get-Content -LiteralPath "$root\extension\engine\runtime-lock.json" -Raw -Encoding UTF8|ConvertFrom-Json
$models=@($repoLock.files|Where-Object{([string]$_.path).StartsWith('models\')})
# SHA-256 of ggml-large-v3-turbo.bin (1624555275 bytes) in Hugging Face
# ggerganov/whisper.cpp at revision 5359861c739e955e79d9a303bcbc70fb988958b1.
if($models.Count -ne 1 -or $models[0].path -cne $modelProfile.Path -or $models[0].sha256 -cne '1fc70f774d38eb169993ac391eea357ef47c88757ef72ee5943879b7e8e2bc69'){throw 'RUNTIME_LOCK_MODEL_NOT_TURBO'}
$dtwArgs=@(Get-PvsWhisperRecognitionArguments -ModelPath 'C:\m.bin' -ModelName $repoConfig.model -WavPath 'a.wav' -OutBase 'o' -Language 'vi' -UseDtw $true)
$dtw=[Array]::IndexOf([object[]]$dtwArgs,'-dtw')
if($dtw -lt 0 -or $dtwArgs[$dtw+1] -cne 'large.v3.turbo' -or $dtwArgs -notcontains '-nfa'){throw 'TURBO_DTW_PRESET_MISSING'}

$temp=Join-Path $env:TEMP ('PVS-RuntimeModelLock-'+[guid]::NewGuid().ToString('N'))
try{
    function New-Fixture([string[]]$ModelFiles,[string]$Model,[string]$ModelPath){
        $engine=Join-Path $temp ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path "$engine\runtime\bin","$engine\runtime\models" -Force|Out-Null
        $files=@()
        foreach($relative in @('bin\whisper-cli.exe','bin\ffmpeg.exe')+$ModelFiles){
            $path=Join-Path "$engine\runtime" $relative
            [IO.File]::WriteAllText($path,"fixture:$relative")
            $files+=[ordered]@{path=$relative;sha256=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()}
        }
        $lock=[ordered]@{schema=1;whisperVersion=$repoLock.whisperVersion;cuda=$repoLock.cuda;files=$files}
        [IO.File]::WriteAllText("$engine\runtime-lock.json",(ConvertTo-Json $lock -Depth 5))
        $config=[ordered]@{modelPath=$ModelPath;ffmpeg='bin\ffmpeg.exe';whisper='bin\whisper-cli.exe';whisperVersion=$repoLock.whisperVersion;model=$Model;backends=@{cuda=$repoLock.cuda}}
        [IO.File]::WriteAllText("$engine\runtime\engine.json",(ConvertTo-Json $config -Depth 5))
        return $engine
    }
    function Assert-Rejected($Engine,[string]$Code,[string]$Case){
        try{Assert-PvsRuntimeLock -EngineRoot $Engine}catch{if($_.Exception.Message -ceq $Code){return};throw "${Case}:unexpected:$($_.Exception.Message)"}
        throw "${Case}:accepted"
    }
    $turbo='models\ggml-large-v3-turbo.bin';$small='models\ggml-small.bin'
    Assert-PvsRuntimeLock -EngineRoot (New-Fixture @($turbo) 'large.v3.turbo' $turbo)
    # Silent downgrade to the old Small runtime, even fully hash-locked.
    Assert-Rejected (New-Fixture @($small) 'small' $small) 'SECURITY_RUNTIME_MODEL_LOCK' 'small-lock'
    Assert-Rejected (New-Fixture @($turbo) 'small' $small) 'SECURITY_RUNTIME_CONFIG_CHANGED' 'small-config'
    # A second locked checkpoint would make the shipped model ambiguous.
    Assert-Rejected (New-Fixture @($turbo,$small) 'large.v3.turbo' $turbo) 'SECURITY_RUNTIME_MODEL_LOCK' 'two-models'
    Assert-Rejected (New-Fixture @($turbo,'models/ggml-small.bin') 'large.v3.turbo' $turbo) 'SECURITY_RUNTIME_MODEL_LOCK' 'two-models-forward-slash'
    # Turbo weights with another DTW preset would align with the wrong heads.
    Assert-Rejected (New-Fixture @($turbo) 'large.v3' $turbo) 'SECURITY_RUNTIME_CONFIG_CHANGED' 'wrong-preset'
    Assert-Rejected (New-Fixture @($turbo) 'Large.V3.Turbo' $turbo) 'SECURITY_RUNTIME_CONFIG_CHANGED' 'preset-case'
    Assert-Rejected (New-Fixture @($turbo) 'large.v3.turbo' 'models\GGML-large-v3-turbo.bin') 'SECURITY_RUNTIME_CONFIG_CHANGED' 'path-case'
    Write-Host 'RUNTIME_MODEL_LOCK_OK'
}finally{
    if(Test-Path -LiteralPath $temp){Remove-Item -LiteralPath $temp -Recurse -Force}
}
