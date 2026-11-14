param([int]$CallerProcessId, [switch]$ProbeOnly, [switch]$FlashOnly)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

# Resolve only the caller's own ancestry. Never select an arbitrary running Premiere.
function Find-PvsAttentionHost {
    param([int]$StartId, [scriptblock]$ReadProcess = { param($ProcessId) Get-CimInstance Win32_Process -Filter "ProcessId = $ProcessId" })
    $visited = @{}
    $child = $null
    $session = $null
    $cursor = $StartId
    for ($depth = 0; $depth -lt 16 -and $cursor -gt 0; $depth++) {
        if ($visited.ContainsKey($cursor)) { return $null }
        $visited[$cursor] = $true
        $record = & $ReadProcess $cursor
        if ($null -eq $record -or [int]$record.ProcessId -ne $cursor) { return $null }
        if ($null -eq $session) { $session = [int]$record.SessionId }
        if ([int]$record.SessionId -ne $session) { return $null }
        if ($null -ne $child -and [datetime]$record.CreationDate -gt [datetime]$child.CreationDate) { return $null }
        if ([string]$record.Name -ieq 'Adobe Premiere Pro.exe') {
            if ([IO.Path]::GetFileName([string]$record.ExecutablePath) -ine 'Adobe Premiere Pro.exe') { return $null }
            return $record
        }
        $child = $record
        $cursor = [int]$record.ParentProcessId
    }
    return $null
}

function Invoke-PvsAttention {
    param([int]$StartId, [switch]$ReadOnly, [switch]$OnlyFlash)
    if ($StartId -le 0) { return @{ ok = $false; reason = 'invalid-caller' } }
    $hostRecord = Find-PvsAttentionHost -StartId $StartId
    if ($null -eq $hostRecord) { return @{ ok = $false; reason = 'host-not-in-ancestry' } }
    $hostProcess = Get-Process -Id ([int]$hostRecord.ProcessId) -ErrorAction Stop
    # Recheck identity against PID reuse between discovery and activation.
    if ($hostProcess.ProcessName -ine 'Adobe Premiere Pro' -or $hostProcess.Path -ine [string]$hostRecord.ExecutablePath -or
        [Math]::Abs(($hostProcess.StartTime.ToUniversalTime() - ([datetime]$hostRecord.CreationDate).ToUniversalTime()).TotalSeconds) -gt 1) {
        return @{ ok = $false; reason = 'host-identity-changed' }
    }
    if ($ReadOnly) { return @{ ok = $true; reason = 'probe-only'; hostProcessId = $hostProcess.Id } }
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class PvsAttentionWindow {
    [StructLayout(LayoutKind.Sequential)] public struct FlashInfo {
        public UInt32 size; public IntPtr window; public UInt32 flags; public UInt32 count; public UInt32 timeout;
    }
    [DllImport("user32.dll")] public static extern bool IsWindow(IntPtr window);
    [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr window);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr window);
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] public static extern IntPtr GetLastActivePopup(IntPtr window);
    [DllImport("user32.dll")] public static extern UInt32 GetWindowThreadProcessId(IntPtr window, out UInt32 processId);
    [DllImport("user32.dll")] public static extern bool ShowWindowAsync(IntPtr window, int command);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr window);
    [DllImport("user32.dll")] public static extern bool FlashWindowEx(ref FlashInfo info);
}
'@ | Out-Null
    $window = $hostProcess.MainWindowHandle
    if ($window -eq [IntPtr]::Zero -or -not [PvsAttentionWindow]::IsWindow($window)) { return @{ ok = $false; reason = 'no-host-window' } }
    [uint32]$owner = 0
    [PvsAttentionWindow]::GetWindowThreadProcessId($window, [ref]$owner) | Out-Null
    if ($owner -ne $hostProcess.Id) { return @{ ok = $false; reason = 'window-owner-changed' } }
    [uint32]$foregroundOwner = 0
    [PvsAttentionWindow]::GetWindowThreadProcessId([PvsAttentionWindow]::GetForegroundWindow(), [ref]$foregroundOwner) | Out-Null
    if ($foregroundOwner -eq $hostProcess.Id) { return @{ ok = $true; reason = 'already-foreground' } }
    if ($OnlyFlash) {
        $flash = New-Object PvsAttentionWindow+FlashInfo
        $flash.size = [Runtime.InteropServices.Marshal]::SizeOf($flash)
        $flash.window = $window; $flash.flags = 2; $flash.count = 3; $flash.timeout = 0
        [PvsAttentionWindow]::FlashWindowEx([ref]$flash) | Out-Null
        return @{ ok = $true; reason = 'taskbar-flashed' }
    }
    if ([PvsAttentionWindow]::IsIconic($window)) { [PvsAttentionWindow]::ShowWindowAsync($window, 9) | Out-Null }
    $popup = [PvsAttentionWindow]::GetLastActivePopup($window)
    [uint32]$popupOwner = 0
    [PvsAttentionWindow]::GetWindowThreadProcessId($popup, [ref]$popupOwner) | Out-Null
    $target = if ($popupOwner -eq $hostProcess.Id -and [PvsAttentionWindow]::IsWindowVisible($popup)) { $popup } else { $window }
    # One request only; Windows may deny focus. Never force topmost, send keys or loop.
    $activated = [PvsAttentionWindow]::SetForegroundWindow($target)
    if (-not $activated) {
        $flash = New-Object PvsAttentionWindow+FlashInfo
        $flash.size = [Runtime.InteropServices.Marshal]::SizeOf($flash)
        $flash.window = $window; $flash.flags = 2; $flash.count = 3; $flash.timeout = 0
        [PvsAttentionWindow]::FlashWindowEx([ref]$flash) | Out-Null
    }
    return @{ ok = $true; reason = $(if ($activated) { 'foreground-requested' } else { 'taskbar-flashed' }) }
}

if ($MyInvocation.InvocationName -ne '.') {
    try { Invoke-PvsAttention -StartId $CallerProcessId -ReadOnly:$ProbeOnly -OnlyFlash:$FlashOnly | ConvertTo-Json -Compress }
    catch { @{ ok = $false; reason = 'attention-unavailable' } | ConvertTo-Json -Compress }
}
