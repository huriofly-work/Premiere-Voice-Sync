param([string]$PackagePath)
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$root=Split-Path $PSScriptRoot -Parent
$version=(Get-Content -LiteralPath (Join-Path $root 'VERSION') -Raw -Encoding UTF8).Trim()
$metadataPath=Join-Path $root ("docs\releases\$version.json")
$metadata=Get-Content -LiteralPath $metadataPath -Raw -Encoding UTF8 | ConvertFrom-Json
if($metadata.schemaVersion -ne 1 -or $metadata.version -cne $version -or $metadata.tag -cne ('v'+$version)){throw 'DISTRIBUTION_VERSION_MISMATCH'}
if($metadata.package.filename -cne ("Premiere-Voice-Sync-$version-Panel.zip") -or $metadata.package.sha256 -cnotmatch '^[A-F0-9]{64}$' -or $metadata.package.bytes -le 0){throw 'DISTRIBUTION_PACKAGE_METADATA_INVALID'}
if($metadata.channel -notin @('stable','prerelease')){throw 'DISTRIBUTION_CHANNEL_INVALID'}
if($metadata.nativeAcceptance -ne 'accepted' -and $metadata.channel -ne 'prerelease'){throw 'UNACCEPTED_BUILD_MUST_BE_PRERELEASE'}
if($PackagePath){
    $package=Get-Item -LiteralPath $PackagePath
    if($package.Name -cne $metadata.package.filename -or $package.Length -ne $metadata.package.bytes -or (Get-FileHash -LiteralPath $package.FullName -Algorithm SHA256).Hash -cne $metadata.package.sha256){throw 'DISTRIBUTION_PACKAGE_BYTES_MISMATCH'}
    . (Join-Path $root 'installer\package-security.ps1')
    $expanded=Join-Path $package.DirectoryName ([IO.Path]::GetFileNameWithoutExtension($package.Name))
    Assert-PvsPackage -Root $expanded | Out-Null
    $checksumPath=$package.FullName+'.sha256'
    $expected=$metadata.package.sha256+'  '+$metadata.package.filename
    if((Get-Content -LiteralPath $checksumPath -Raw -Encoding ASCII).Trim() -cne $expected){throw 'DISTRIBUTION_CHECKSUM_FILE_MISMATCH'}
}
Write-Host ("GITHUB_DISTRIBUTION_OK:version=$version;channel="+$metadata.channel+';native='+$metadata.nativeAcceptance+';packageChecked='+[bool]$PackagePath)
