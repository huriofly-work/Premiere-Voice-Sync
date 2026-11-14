param([Parameter(Mandatory)][string]$RequestPath)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
Set-StrictMode -Version Latest
[Console]::OutputEncoding = New-Object Text.UTF8Encoding($false)
. "$PSScriptRoot\lib\Security.ps1"
Assert-PvsSafePath -Path $RequestPath
$request = Get-Content -LiteralPath $RequestPath -Raw -Encoding UTF8 | ConvertFrom-Json
$allowed = @('run-alignment.ps1','run-captions.ps1','build-sentence-plan.ps1','build-dtw-trial-plan.ps1','build-speed-merge-trial-plan.ps1')
if ([string]$request.script -cnotin $allowed) { throw 'WORKFLOW_SCRIPT_NOT_ALLOWED' }
$scriptPath = Join-Path $PSScriptRoot ([string]$request.script)
Assert-PvsSafePath -Path $scriptPath
$cancelPath = $RequestPath + '.cancel'
Assert-PvsSafePath -Path $cancelPath
if (Test-Path -LiteralPath $cancelPath) { exit 1223 }

# The child blocks on stdin until assigned to our private Windows Job Object.
# No engine/native child can escape the job during process startup. Closing the
# wrapper also kills that job; Premiere and other workflow jobs are never members.
Add-Type -TypeDefinition @'
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
namespace Pvs {
  public sealed class WorkflowJob : IDisposable {
    [StructLayout(LayoutKind.Sequential)] struct BasicLimit {
      public long ProcessTime, JobTime; public uint Flags; public UIntPtr Min, Max;
      public uint ActiveLimit; public UIntPtr Affinity; public uint Priority, Scheduling;
    }
    [StructLayout(LayoutKind.Sequential)] struct Io {
      public ulong ReadOps, WriteOps, OtherOps, ReadBytes, WriteBytes, OtherBytes;
    }
    [StructLayout(LayoutKind.Sequential)] struct ExtendedLimit {
      public BasicLimit Basic; public Io Io; public UIntPtr ProcessMemory, JobMemory, PeakProcess, PeakJob;
    }
    [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)] static extern IntPtr CreateJobObject(IntPtr a, string n);
    [DllImport("kernel32.dll", SetLastError=true)] static extern bool SetInformationJobObject(IntPtr h, int c, ref ExtendedLimit p, uint n);
    [DllImport("kernel32.dll", SetLastError=true)] static extern bool AssignProcessToJobObject(IntPtr h, IntPtr p);
    [DllImport("kernel32.dll", SetLastError=true)] static extern bool TerminateJobObject(IntPtr h, uint code);
    [DllImport("kernel32.dll", SetLastError=true)] static extern bool QueryInformationJobObject(IntPtr h, int c, IntPtr p, uint n, IntPtr r);
    [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr h);
    IntPtr handle;
    public WorkflowJob() {
      handle=CreateJobObject(IntPtr.Zero, null);
      if(handle==IntPtr.Zero) throw new Win32Exception();
      var limits=new ExtendedLimit(); limits.Basic.Flags=0x2000; // KILL_ON_JOB_CLOSE
      if(!SetInformationJobObject(handle,9,ref limits,(uint)Marshal.SizeOf(limits))) {
        var error=new Win32Exception(); Dispose(); throw error;
      }
    }
    public void Assign(IntPtr process) { if(!AssignProcessToJobObject(handle,process)) throw new Win32Exception(); }
    public void Terminate() { if(!TerminateJobObject(handle,1223)) throw new Win32Exception(); }
    public uint ActiveCount {
      get {
        IntPtr data=Marshal.AllocHGlobal(48);
        try {
          if(!QueryInformationJobObject(handle,1,data,48,IntPtr.Zero)) throw new Win32Exception();
          return (uint)Marshal.ReadInt32(data,40);
        } finally { Marshal.FreeHGlobal(data); }
      }
    }
    public void Dispose() { if(handle!=IntPtr.Zero) { CloseHandle(handle); handle=IntPtr.Zero; } }
  }
}
'@

# Re-read the request in the gated child. Encode the command, so Unicode paths
# and literal argument text do not pass through shell interpolation.
$requestLiteral = $RequestPath.Replace("'", "''")
$scriptLiteral = $scriptPath.Replace("'", "''")
$command = @"
if ([Console]::ReadLine() -cne 'PVS_GO') { exit 1 }
`$ErrorActionPreference='Stop'
`$ProgressPreference='SilentlyContinue'
try {
  `$pvsRequest=Get-Content -LiteralPath '$requestLiteral' -Raw -Encoding UTF8 | ConvertFrom-Json
  [Console]::OutputEncoding=New-Object Text.UTF8Encoding(`$false)
  `$pvsParameters=@{}
  `$pvsArguments=@([string[]]`$pvsRequest.args)
  for (`$pvsIndex=0; `$pvsIndex -lt `$pvsArguments.Count; `$pvsIndex++) {
    `$pvsKey=`$pvsArguments[`$pvsIndex]
    if (`$pvsKey -ceq '-ValidateOnly') { `$pvsParameters.ValidateOnly=`$true }
    elseif (`$pvsKey -cin @('-JobPath','-PlanPath') -and `$pvsIndex+1 -lt `$pvsArguments.Count) {
      `$pvsIndex++; `$pvsParameters[`$pvsKey.Substring(1)]=`$pvsArguments[`$pvsIndex]
    } else { throw 'WORKFLOW_ARGUMENT_NOT_ALLOWED' }
  }
  & '$scriptLiteral' @pvsParameters
  if (-not `$?) { if (`$LASTEXITCODE) { exit `$LASTEXITCODE }; exit 1 }
} catch { [Console]::Error.WriteLine(`$_); exit 1 }
"@
$encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command))
$start = New-Object Diagnostics.ProcessStartInfo
$start.FileName = Join-Path $PSHOME 'powershell.exe'
$start.Arguments = '-NoProfile -ExecutionPolicy Bypass -EncodedCommand ' + $encoded
$start.UseShellExecute = $false
$start.CreateNoWindow = $true
$start.RedirectStandardInput = $true
$start.RedirectStandardOutput = $true
$start.RedirectStandardError = $true
$start.StandardOutputEncoding = New-Object Text.UTF8Encoding($false)
$start.StandardErrorEncoding = New-Object Text.UTF8Encoding($false)
$worker = New-Object Diagnostics.Process
$worker.StartInfo = $start
$job = New-Object Pvs.WorkflowJob
$started = $false
$assigned = $false
$cancelled = $false
try {
    if (-not $worker.Start()) { throw 'WORKFLOW_START_FAILED' }
    $started = $true
    $stdoutTask = $worker.StandardOutput.ReadToEndAsync()
    $stderrTask = $worker.StandardError.ReadToEndAsync()
    $job.Assign($worker.Handle)
    $assigned = $true
    $worker.StandardInput.WriteLine('PVS_GO')
    $worker.StandardInput.Close()
    while (-not $worker.WaitForExit(100)) {
        if (Test-Path -LiteralPath $cancelPath) { $cancelled = $true; $job.Terminate(); break }
    }
    $worker.WaitForExit()
    # Kill/drain any orphan native children before reporting completion, even
    # when the engine parent exited by itself. No files are cleaned up yet.
    if ($job.ActiveCount -gt 0) { $job.Terminate() }
    while ($job.ActiveCount -gt 0) { Start-Sleep -Milliseconds 50 }
    $workerExitCode = $worker.ExitCode
    [Console]::Out.Write($stdoutTask.Result)
    if (-not $cancelled) { [Console]::Error.Write($stderrTask.Result) }
    if ($cancelled) { exit 1223 }
    exit $workerExitCode
} finally {
    if ($started -and -not $worker.HasExited) {
        if ($assigned) { $job.Terminate() } else { $worker.Kill() }
        $worker.WaitForExit()
    }
    if ($assigned) {
        if ($job.ActiveCount -gt 0) { $job.Terminate() }
        while ($job.ActiveCount -gt 0) { Start-Sleep -Milliseconds 50 }
    }
    $job.Dispose()
    $worker.Dispose()
}
