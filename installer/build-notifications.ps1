param([string]$OutputDirectory = (Join-Path (Split-Path $PSScriptRoot -Parent) 'extension\native'))
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$source=Join-Path (Split-Path $PSScriptRoot -Parent) 'extension\native'
$compiler=Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
$references=@(Get-ChildItem -LiteralPath (Join-Path $env:WINDIR 'System32\WinMetadata') -Filter '*.winmd' | ForEach-Object { '/reference:'+ $_.FullName })
$references+=@('System.Runtime.dll','System.Runtime.WindowsRuntime.dll','System.Runtime.InteropServices.WindowsRuntime.dll','System.Windows.Forms.dll','System.Drawing.dll','System.Web.Extensions.dll') | ForEach-Object { '/reference:'+ (Join-Path (Split-Path $compiler -Parent) $_) }
New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
$assembly=Join-Path $OutputDirectory 'PvsNotifications.exe'
& $compiler /nologo /platform:x64 /target:winexe /optimize+ /out:$assembly @references (Join-Path $source 'NotificationIdentity.cs') (Join-Path $source 'NotificationProtocol.cs') (Join-Path $source 'NotificationHost.cs') (Join-Path $source 'NotificationWindow.cs')
if($LASTEXITCODE -ne 0){throw 'NOTIFICATION_HELPER_COMPILE_FAILED'}
@{sha256=(Get-FileHash -LiteralPath $assembly -Algorithm SHA256).Hash.ToLowerInvariant()} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $OutputDirectory 'helper-lock.json') -Encoding ASCII
Write-Host 'NOTIFICATION_HELPER_BUILT'
