<#
.SYNOPSIS
Disables Windows power throttling (EcoQoS) for running Android Emulator qemu processes.

.DESCRIPTION
On Windows 11 with an Intel hybrid CPU (12th gen or newer), Windows treats the
headless emulator (qemu-system-x86_64-headless.exe, started with -no-window) as
background work and moves it onto the E-cores. Cold boot gets 2-3x slower and
the guest produces ANRs. This script opts the qemu process out of power
throttling with one Win32 call (SetProcessInformation / ProcessPowerThrottling).

No administrator rights needed. Affinity and priority are not changed. The
change lasts until that emulator process exits.

.PARAMETER Wait
Seconds to wait for a qemu process to appear. Default 0: only look once.
Use it to start the script before (or together with) the emulator.

.EXAMPLE
powershell -ExecutionPolicy Bypass -File emulator_power_fix.ps1

.EXAMPLE
powershell -ExecutionPolicy Bypass -File emulator_power_fix.ps1 -Wait 60

.LINK
https://issuetracker.google.com/issues/572278410
#>
param([int]$Wait = 0)

Add-Type -Namespace EmuFix -Name Native -MemberDefinition @'
[StructLayout(LayoutKind.Sequential)]
public struct PowerThrottlingState { public uint Version; public uint ControlMask; public uint StateMask; }
[DllImport("kernel32.dll", SetLastError = true)]
public static extern IntPtr OpenProcess(uint access, bool inherit, int pid);
[DllImport("kernel32.dll", SetLastError = true)]
public static extern bool SetProcessInformation(IntPtr process, int infoClass, ref PowerThrottlingState info, int size);
[DllImport("kernel32.dll")]
public static extern bool CloseHandle(IntPtr handle);
'@

$deadline = (Get-Date).AddSeconds($Wait)
$procs = @(Get-Process -Name 'qemu-system-*' -ErrorAction SilentlyContinue)
while ($procs.Count -eq 0 -and (Get-Date) -lt $deadline) {
    Start-Sleep -Milliseconds 500
    $procs = @(Get-Process -Name 'qemu-system-*' -ErrorAction SilentlyContinue)
}
if ($procs.Count -eq 0) {
    'No running qemu-system-* process found. Start the emulator first, or use -Wait <seconds>.'
    exit 1
}

foreach ($p in $procs) {
    $h = [EmuFix.Native]::OpenProcess(0x0200, $false, $p.Id)   # PROCESS_SET_INFORMATION
    if ($h -eq [IntPtr]::Zero) {
        '{0} (PID {1}): could not open process (error {2})' -f $p.Name, $p.Id, [Runtime.InteropServices.Marshal]::GetLastWin32Error()
        continue
    }
    $s = New-Object EmuFix.Native+PowerThrottlingState
    $s.Version = 1          # PROCESS_POWER_THROTTLING_CURRENT_VERSION
    $s.ControlMask = 0x5    # EXECUTION_SPEED | IGNORE_TIMER_RESOLUTION
    $s.StateMask = 0        # 0 = do not throttle
    $ok = [EmuFix.Native]::SetProcessInformation($h, 4, [ref]$s, 12)   # 4 = ProcessPowerThrottling
    $err = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
    [void][EmuFix.Native]::CloseHandle($h)
    if ($ok) { '{0} (PID {1}): power throttling disabled' -f $p.Name, $p.Id }
    else     { '{0} (PID {1}): SetProcessInformation failed (error {2})' -f $p.Name, $p.Id, $err }
}
