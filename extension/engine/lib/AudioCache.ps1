Set-StrictMode -Version Latest

# Data only: never persist a timeline plan, PCM file or executable. Callers
# still verify the runtime lock and rebuild all source/timeline coordinates.
function Initialize-PvsAudioCache {
    param([bool]$Enabled=$true,[string]$Root='',[string]$RuntimeIdentity='')
    if(-not $Root){$Root=Join-Path $env:LOCALAPPDATA 'PremiereVoiceSync\Cache\Whisper\Audio-v1'}
    Assert-PvsSafePath -Path $Root -Tree
    $script:pvsAudioCache=[pscustomobject]@{Enabled=$Enabled;Root=$Root;Runtime=$RuntimeIdentity;Hashes=@{};WhisperHits=0;WhisperMisses=0;QuietHits=0;QuietMisses=0;InvalidEntries=0;WriteFailures=0}
    if(-not $Enabled){return}
    try {
    New-Item -ItemType Directory -Path $Root -Force | Out-Null
    if(-not (Test-Path -LiteralPath $Root -PathType Container)){throw 'AUDIO_CACHE_NOT_DIRECTORY'}
    # Bound persistent data. Eviction only touches this tool-owned cache tree.
    $total=0L;$cutoff=(Get-Date).AddDays(-30)
    foreach($file in @(Get-ChildItem -LiteralPath $Root -File -Filter '*.json' | Sort-Object LastWriteTimeUtc -Descending)){
        $total+=$file.Length
        if($file.LastWriteTime -lt $cutoff -or $total -gt 512MB){Remove-Item -LiteralPath $file.FullName -Force}
    }
    foreach($file in @(Get-ChildItem -LiteralPath $Root -File -Filter '*.tmp' | Where-Object {$_.LastWriteTime -lt (Get-Date).AddDays(-1)})){Remove-Item -LiteralPath $file.FullName -Force}
    } catch {
        # Storage availability is optional, unlike the link/path security gate
        # above. Preserve recognition when disk permissions/eviction fail.
        $script:pvsAudioCache.Enabled=$false
        $script:pvsAudioCache.WriteFailures++
        Write-Verbose "Audio cache disabled: $($_.Exception.Message)"
    }
}

function Get-PvsAudioCacheState {
    if(-not (Get-Variable pvsAudioCache -Scope Script -ErrorAction SilentlyContinue)){return $null}
    return $script:pvsAudioCache
}

function Get-PvsAudioDigest {
    param([string]$Text)
    $sha=[Security.Cryptography.SHA256]::Create()
    try{return ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Text)))).Replace('-','').ToLowerInvariant()}finally{$sha.Dispose()}
}

function Get-PvsAudioFileDigest {
    param([string]$Path,[switch]$Memoize)
    Assert-PvsSafePath -Path $Path
    $file=Get-Item -LiteralPath $Path
    $state=Get-PvsAudioCacheState
    $identity=$file.FullName+'|'+$file.Length+'|'+$file.LastWriteTimeUtc.Ticks
    # Only memoize within a single job, never use size/date as a persistent key.
    if($Memoize -and $null -ne $state -and $state.Hashes.ContainsKey($identity)){return $state.Hashes[$identity]}
    $hash=(Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
    if($Memoize -and $null -ne $state){$state.Hashes[$identity]=$hash}
    return $hash
}

function Get-PvsAudioCacheStats {
    $s=Get-PvsAudioCacheState
    if($null -eq $s){return $null}
    return [pscustomobject]@{enabled=$s.Enabled;whisperHits=$s.WhisperHits;whisperMisses=$s.WhisperMisses;quietHits=$s.QuietHits;quietMisses=$s.QuietMisses;invalidEntries=$s.InvalidEntries;writeFailures=$s.WriteFailures}
}

function Invoke-PvsAudioCachedNative {
    param([ValidateSet('whisper','quiet')][string]$Kind,[string]$FilePath,[string[]]$Arguments,[scriptblock]$Execute)
    $s=Get-PvsAudioCacheState
    if($null -eq $s -or -not $s.Enabled){return & $Execute}
    $inputFlag=if($Kind -eq 'whisper'){'-f'}else{'-i'}
    $inputIndex=[Array]::IndexOf($Arguments,$inputFlag)
    $outIndex=[Array]::IndexOf($Arguments,'-of')
    $modelIndex=[Array]::IndexOf($Arguments,'-m')
    if($inputIndex -lt 0 -or $inputIndex+1 -ge $Arguments.Count -or ($Kind -eq 'whisper' -and ($outIndex -lt 0 -or $modelIndex -lt 0 -or $outIndex+1 -ge $Arguments.Count -or $modelIndex+1 -ge $Arguments.Count))){return & $Execute}
    $normalized=[string[]]$Arguments.Clone()
    $normalized[$inputIndex+1]=Get-PvsAudioFileDigest $Arguments[$inputIndex+1]
    if($Kind -eq 'whisper'){
        $normalized[$outIndex+1]='<output>'
        $normalized[$modelIndex+1]=Get-PvsAudioFileDigest $Arguments[$modelIndex+1] -Memoize
    }
    $identity=@('audio-native-v1',$Kind,$s.Runtime,(Get-PvsAudioFileDigest $FilePath -Memoize),$normalized)
    $key=Get-PvsAudioDigest (ConvertTo-Json -InputObject $identity -Depth 5 -Compress)
    $path=Join-Path $s.Root ($key+'.json')
    Assert-PvsSafePath -Path $path -Root $s.Root
    $hitProperty=if($Kind -eq 'whisper'){'WhisperHits'}else{'QuietHits'}
    $missProperty=if($Kind -eq 'whisper'){'WhisperMisses'}else{'QuietMisses'}
    if(Test-Path -LiteralPath $path){
        try{
            $entry=Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
            if($entry.schema -ne 1 -or $entry.key -cne $key -or $entry.hash -cne (Get-PvsAudioDigest ([string]$entry.payload))){throw 'AUDIO_CACHE_INVALID'}
            $payload=[string]$entry.payload | ConvertFrom-Json
            if([int]$payload.capture.ExitCode -ne 0){throw 'AUDIO_CACHE_FAILED_CAPTURE'}
            if($Kind -eq 'whisper'){
                $json=[string]$payload.recognition | ConvertFrom-Json
                if(-not $json.PSObject.Properties['transcription']){throw 'AUDIO_CACHE_INVALID_RECOGNITION'}
                $destination=$Arguments[$outIndex+1]+'.json'
                Assert-PvsSafePath -Path $destination
                [IO.File]::WriteAllText($destination,[string]$payload.recognition,(New-Object Text.UTF8Encoding($false)))
            }
            $s.$hitProperty++
            $payload.capture | Add-Member -NotePropertyName CacheHit -NotePropertyValue $true -Force
            return $payload.capture
        }catch{$s.InvalidEntries++;Write-Verbose "Audio cache read skipped: $($_.Exception.Message)"}
    }
    $s.$missProperty++
    $capture=& $Execute
    # Never cache errors or a GPU invocation that silently fell back to CPU.
    $gpu=$Kind -eq 'whisper' -and $Arguments -notcontains '--no-gpu'
    if($capture.ExitCode -eq 0 -and (-not $gpu -or $capture.Output -match '(?im)^load_backend:\s+loaded CUDA backend from .+ggml-cuda\.dll')){
        $tmp=Join-Path $s.Root ($key+'.'+[guid]::NewGuid().ToString('N')+'.tmp')
        try{
            $recognition=''
            if($Kind -eq 'whisper'){
                # Get-Content strings carry provider metadata in Windows
                # PowerShell 5.1; JSON serialization would expand that graph.
                $recognition=[IO.File]::ReadAllText($Arguments[$outIndex+1]+'.json',[Text.Encoding]::UTF8)
                $json=$recognition | ConvertFrom-Json
                if(-not $json.PSObject.Properties['transcription']){throw 'AUDIO_CACHE_INVALID_RECOGNITION'}
            }
            $plainCapture=@{ExitCode=[int]$capture.ExitCode;StdOut=[string]$capture.StdOut;StdErr=[string]$capture.StdErr;Output=[string]$capture.Output}
            $payload=ConvertTo-Json -InputObject @{capture=$plainCapture;recognition=$recognition} -Depth 6 -Compress
            $entry=ConvertTo-Json -InputObject @{schema=1;key=$key;hash=(Get-PvsAudioDigest $payload);payload=$payload} -Depth 4 -Compress
            Assert-PvsSafePath -Path $tmp -Root $s.Root
            [IO.File]::WriteAllText($tmp,$entry,(New-Object Text.UTF8Encoding($false)))
            # Atomic publication: concurrent jobs may compute the same key.
            if(Test-Path -LiteralPath $path){[IO.File]::Replace($tmp,$path,[System.Management.Automation.Language.NullString]::Value)}else{[IO.File]::Move($tmp,$path)}
        }catch{$s.WriteFailures++;Write-Verbose "Audio cache write skipped: $($_.Exception.Message)"}finally{
            # An optional cache must not discard successful recognition when
            # antivirus or a transient file lock prevents temporary cleanup.
            try{if(Test-Path -LiteralPath $tmp){Remove-Item -LiteralPath $tmp -Force}}
            catch{$s.WriteFailures++;Write-Verbose "Audio cache temporary cleanup skipped: $($_.Exception.Message)"}
        }
    }
    $capture | Add-Member -NotePropertyName CacheHit -NotePropertyValue $false -Force
    return $capture
}
