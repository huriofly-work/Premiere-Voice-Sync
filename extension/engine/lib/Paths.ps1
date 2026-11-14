function Resolve-PvsExistingPath {
    param(
        [Parameter(Mandatory)][string]$Path,
        [string]$Purpose = 'File'
    )

    if (Test-Path -LiteralPath $Path -PathType Leaf) {
        return (Resolve-Path -LiteralPath $Path).Path
    }

    try {
        $repaired = [Text.Encoding]::UTF8.GetString(
            [Text.Encoding]::GetEncoding(1252).GetBytes($Path)
        )
        if (
            $repaired -ne $Path -and
            $repaired.IndexOf([char]0xFFFD) -lt 0 -and
            (Test-Path -LiteralPath $repaired -PathType Leaf)
        ) {
            return (Resolve-Path -LiteralPath $repaired).Path
        }
    }
    catch {}

    throw "MEDIA_PATH_NOT_FOUND:$Purpose path does not exist: $Path"
}
