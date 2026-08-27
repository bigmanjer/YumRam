#requires -Version 5.1
Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase

if (-not ('YumRamNative' -as [type])) {
    Add-Type @'
using System;
using System.Runtime.InteropServices;

public static class YumRamNative
{
    [DllImport("kernel32.dll", SetLastError=true)]
    public static extern bool K32EmptyWorkingSet(IntPtr hProcess);

    [StructLayout(LayoutKind.Sequential)]
    public class MEMORYSTATUSEX
    {
        public uint dwLength;
        public uint dwMemoryLoad;
        public ulong ullTotalPhys;
        public ulong ullAvailPhys;
        public ulong ullTotalPageFile;
        public ulong ullAvailPageFile;
        public ulong ullTotalVirtual;
        public ulong ullAvailVirtual;
        public ulong ullAvailExtendedVirtual;
        public MEMORYSTATUSEX() { dwLength=(uint)Marshal.SizeOf(typeof(MEMORYSTATUSEX)); }
    }

    [DllImport("kernel32.dll", SetLastError=true)]
    public static extern bool GlobalMemoryStatusEx([In, Out] MEMORYSTATUSEX lpBuffer);

    [DllImport("user32.dll")]
    public static extern IntPtr GetForegroundWindow();

    [DllImport("user32.dll")]
    public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint processId);
}
'@
}

function Get-YumForegroundProcessId {
    try {
        $foregroundPid = [uint32]0
        $hwnd = [YumRamNative]::GetForegroundWindow()
        if ($hwnd -eq [IntPtr]::Zero) { return 0 }
        [void][YumRamNative]::GetWindowThreadProcessId($hwnd, [ref]$foregroundPid)
        return [int]$foregroundPid
    } catch { return 0 }
}

function Invoke-YumEmptyWorkingSet {
    param([Parameter(Mandatory)][System.Diagnostics.Process]$Process)
    try {
        $before=[int64]$Process.WorkingSet64
        if ($before -lt 100MB) { return [pscustomobject]@{Success=$false;Before=$before;After=$before;Reduced=0;Win32Error=0;Reason='Below threshold'} }
        $handle=$Process.Handle
        $ok=[YumRamNative]::K32EmptyWorkingSet($handle)
        if (-not $ok) {
            $code=[Runtime.InteropServices.Marshal]::GetLastWin32Error()
            return [pscustomobject]@{Success=$false;Before=$before;After=$before;Reduced=0;Win32Error=$code;Reason='K32EmptyWorkingSet failed'}
        }
        $Process.Refresh()
        $after=[int64]$Process.WorkingSet64
        $reduced=[math]::Max([int64]0,$before-$after)
        return [pscustomobject]@{Success=$true;Before=$before;After=$after;Reduced=$reduced;Win32Error=0;Reason='Trimmed'}
    } catch {
        return [pscustomobject]@{Success=$false;Before=0;After=0;Reduced=0;Win32Error=$_.Exception.HResult;Reason=$_.Exception.Message}
    }
}
