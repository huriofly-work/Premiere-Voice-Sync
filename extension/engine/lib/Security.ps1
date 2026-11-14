Set-StrictMode -Version Latest

# The single Whisper checkpoint the engine is reviewed and released with. The
# id doubles as the whisper.cpp DTW alignment-head preset for that checkpoint.
function Get-PvsRuntimeModelProfile {
    [pscustomobject]@{Id='large.v3.turbo';Path='models\ggml-large-v3-turbo.bin'}
}

function Assert-PvsSafePath {
    param([Parameter(Mandatory)][string]$Path, [string]$Root = '', [switch]$Tree)
    $full = [IO.Path]::GetFullPath($Path)
    if ($Root) {
        $rootFull = [IO.Path]::GetFullPath($Root).TrimEnd('\')
        if ($full -ne $rootFull -and -not $full.StartsWith($rootFull + '\',[StringComparison]::OrdinalIgnoreCase)) { throw "SECURITY_PATH_OUTSIDE_ROOT:$full" }
    }
    $chain = New-Object System.Collections.Generic.List[string]
    $cursor = $full
    while ($cursor) {
        $chain.Insert(0, $cursor)
        $parent = Split-Path $cursor -Parent
        if ($parent -eq $cursor) { break }
        $cursor = $parent
    }
    # From the root down: probing a deeper path would already pass through a link above it.
    foreach ($item in $chain) {
        if (Test-Path -LiteralPath $item) {
            if ((Get-Item -LiteralPath $item -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "SECURITY_LINKED_PATH:$item" }
        }
    }
    if ($Tree -and (Test-Path -LiteralPath $full -PathType Container)) {
        foreach ($item in (Get-ChildItem -LiteralPath $full -Force)) {
            if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "SECURITY_LINKED_PATH:$($item.FullName)" }
            if ($item.PSIsContainer) { Assert-PvsSafePath -Path $item.FullName -Root $full -Tree }
        }
    }
}

function Remove-PvsSafeTree {
    param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)][string]$Root)
    $full = [IO.Path]::GetFullPath($Path)
    if ($full -eq [IO.Path]::GetFullPath($Root).TrimEnd('\')) { throw 'SECURITY_CANNOT_REMOVE_ROOT' }
    Assert-PvsSafePath -Path $full -Root $Root -Tree
    if (Test-Path -LiteralPath $full) { Remove-Item -LiteralPath $full -Recurse -Force }
}

function Assert-PvsHashManifest {
    param([Parameter(Mandatory)][string]$Root,[Parameter(Mandatory)][string]$Manifest,[string[]]$ExpectedFiles = @())
    Assert-PvsSafePath -Path $Root -Tree
    Assert-PvsSafePath -Path $Manifest -Root $Root
    if (-not (Test-Path -LiteralPath $Manifest -PathType Leaf)) { throw 'SECURITY_CHECKSUM_REQUIRED' }
    $seen = @{}
    foreach ($line in (Get-Content -LiteralPath $Manifest -Encoding ASCII)) {
        if ($line -notmatch '^([A-Fa-f0-9]{64})  ([^\r\n]+)$') { throw 'SECURITY_CHECKSUM_FORMAT' }
        $hash = $matches[1]; $relative = $matches[2].Replace('/','\')
        if ([IO.Path]::IsPathRooted($relative) -or $relative -match '(^|\\)\.{1,2}(\\|$)|:') { throw 'SECURITY_CHECKSUM_PATH' }
        if ($seen.ContainsKey($relative)) { throw 'SECURITY_CHECKSUM_DUPLICATE' }
        if ($ExpectedFiles.Count -and $relative -notin $ExpectedFiles) { throw "SECURITY_UNEXPECTED_FILE:$relative" }
        $file = Join-Path $Root $relative
        Assert-PvsSafePath -Path $file -Root $Root
        if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { throw "SECURITY_FILE_MISSING:$relative" }
        if ((Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash -ne $hash) { throw "SECURITY_HASH_MISMATCH:$relative" }
        $seen[$relative] = $hash
    }
    if (-not $seen.Count) { throw 'SECURITY_CHECKSUM_EMPTY' }
    foreach ($relative in $ExpectedFiles) { if (-not $seen.ContainsKey($relative)) { throw "SECURITY_CHECKSUM_ENTRY_MISSING:$relative" } }
    if ($ExpectedFiles.Count) {
        $prefix = [IO.Path]::GetFullPath($Root).TrimEnd('\') + '\'
        foreach ($file in (Get-ChildItem -LiteralPath $Root -File -Force -Recurse)) {
            $relative = $file.FullName.Substring($prefix.Length)
            if ($file.FullName -ne [IO.Path]::GetFullPath($Manifest) -and -not $seen.ContainsKey($relative)) { throw "SECURITY_UNLISTED_FILE:$relative" }
        }
    }
    return $seen
}

function Assert-PvsRuntimeLock {
    param([Parameter(Mandatory)][string]$EngineRoot)
    $lockPath = Join-Path $EngineRoot 'runtime-lock.json'
    Assert-PvsSafePath -Path $lockPath
    $lock = Get-Content -LiteralPath $lockPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $runtime = Join-Path $EngineRoot 'runtime'
    Assert-PvsLockedFiles -Root $runtime -Lock $lock -BinaryDirectory (Join-Path $runtime 'bin')
    Assert-PvsSafePath -Path (Join-Path $runtime 'engine.json') -Root $runtime
    $config = Get-Content -LiteralPath (Join-Path $runtime 'engine.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    # The reviewed code, not the editable config, names the one shipped model.
    # The lock must hash exactly that model file, so a config swap to another
    # (or an older) checkpoint is rejected even when its weights are present.
    $model = Get-PvsRuntimeModelProfile
    # Normalize separators: Join-Path accepts '/' too, so 'models/x.bin' must count.
    $modelFiles = @($lock.files | Where-Object { ([string]$_.path).Replace('/','\').StartsWith('models\', [StringComparison]::OrdinalIgnoreCase) } | ForEach-Object { [string]$_.path })
    if ($modelFiles.Count -ne 1 -or $modelFiles[0] -cne $model.Path) { throw 'SECURITY_RUNTIME_MODEL_LOCK' }
    if ($config.whisperVersion -ne $lock.whisperVersion -or $config.whisper -ne 'bin\whisper-cli.exe' -or $config.ffmpeg -ne 'bin\ffmpeg.exe' -or $config.model -cne $model.Id -or $config.modelPath -cne $model.Path -or $config.backends.cuda.version -ne $lock.cuda.version -or $config.backends.cuda.url -ne $lock.cuda.url -or $config.backends.cuda.sha256 -ne $lock.cuda.sha256) { throw 'SECURITY_RUNTIME_CONFIG_CHANGED' }
}

function Assert-PvsLockedFiles {
    param([string]$Root,$Lock,[string]$BinaryDirectory)
    Assert-PvsSafePath -Path $Root -Tree
    if ($Lock.schema -ne 1 -or -not @($Lock.files).Count) { throw 'SECURITY_LOCK_SCHEMA' }
    $seen = @{}
    foreach ($entry in $Lock.files) {
        $relative = [string]$entry.path
        if ([IO.Path]::IsPathRooted($relative) -or $relative -match '(^|[\\/])\.{1,2}([\\/]|$)|:' -or $seen.ContainsKey($relative) -or [string]$entry.sha256 -notmatch '^[a-fA-F0-9]{64}$') { throw 'SECURITY_LOCK_ENTRY' }
        $file = Join-Path $Root $relative
        Assert-PvsSafePath -Path $file -Root $Root
        if ((Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash -ne [string]$entry.sha256) { throw "SECURITY_RUNTIME_HASH:$relative" }
        $seen[$relative] = $true
    }
    # Whisper loads backend DLLs automatically. Never execute it beside an unreviewed DLL.
    foreach ($dll in (Get-ChildItem -LiteralPath $BinaryDirectory -File -Filter '*.dll' -Force -Recurse)) {
        $relative = $dll.FullName.Substring([IO.Path]::GetFullPath($Root).TrimEnd('\').Length + 1)
        if (-not $seen.ContainsKey($relative)) { throw "SECURITY_UNEXPECTED_DLL:$relative" }
    }
}

function Assert-PvsCudaLock {
    param([string]$Root,[string]$LockPath)
    Assert-PvsSafePath -Path $LockPath
    $lock = Get-Content -LiteralPath $LockPath -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-PvsLockedFiles -Root $Root -Lock $lock -BinaryDirectory $Root
}

function Get-PvsVerifiedModelCopy {
    param([string]$Source,[string]$DataRoot)
    $model = Join-Path $DataRoot ('Models\' + [IO.Path]::GetFileName($Source))
    Assert-PvsSafePath -Path $model -Root $DataRoot
    $sourceHash = (Get-FileHash -LiteralPath $Source -Algorithm SHA256).Hash
    if (-not (Test-Path -LiteralPath $model) -or (Get-FileHash -LiteralPath $model -Algorithm SHA256).Hash -ne $sourceHash) {
        New-Item -ItemType Directory -Path (Split-Path $model -Parent) -Force | Out-Null
        Copy-Item -LiteralPath $Source -Destination $model -Force
    }
    return $model
}
