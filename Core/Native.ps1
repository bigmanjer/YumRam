#requires -Version 5.1
Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase

if (-not ('YumRamNative' -as [type])) {
    Add-Type @'
using System;
using System.ComponentModel;
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

    [StructLayout(LayoutKind.Sequential)]
    public class PERFORMANCE_INFORMATION
    {
        public uint cb;
        public ulong CommitTotal;
        public ulong CommitLimit;
        public ulong CommitPeak;
        public ulong PhysicalTotal;
        public ulong PhysicalAvailable;
        public ulong SystemCache;
        public ulong KernelTotal;
        public ulong KernelPaged;
        public ulong KernelNonpaged;
        public uint PageSize;
        public uint HandleCount;
        public uint ProcessCount;
        public uint ThreadCount;
        public PERFORMANCE_INFORMATION() { cb=(uint)Marshal.SizeOf(typeof(PERFORMANCE_INFORMATION)); }
    }

    [DllImport("kernel32.dll", SetLastError=true)]
    public static extern bool GlobalMemoryStatusEx([In, Out] MEMORYSTATUSEX lpBuffer);

    [DllImport("psapi.dll", SetLastError=true)]
    public static extern bool GetPerformanceInfo([In, Out] PERFORMANCE_INFORMATION pPerformanceInformation, uint cb);

    [DllImport("ntdll.dll", SetLastError=false)]
    public static extern int NtSetSystemInformation(int SystemInformationClass, IntPtr SystemInformation, int SystemInformationLength);

    [DllImport("advapi32.dll", SetLastError=true)]
    public static extern bool OpenProcessToken(IntPtr ProcessHandle, uint DesiredAccess, out IntPtr TokenHandle);

    [DllImport("advapi32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
    public static extern bool LookupPrivilegeValue(string lpSystemName, string lpName, out LUID lpLuid);

    [DllImport("advapi32.dll", SetLastError=true)]
    public static extern bool AdjustTokenPrivileges(IntPtr TokenHandle, bool DisableAllPrivileges, IntPtr NewState, uint BufferLength, IntPtr PreviousState, IntPtr ReturnLength);

    [DllImport("kernel32.dll", SetLastError=true)]
    public static extern bool CloseHandle(IntPtr hObject);

    [StructLayout(LayoutKind.Sequential)]
    public struct LUID { public uint LowPart; public int HighPart; }

    [StructLayout(LayoutKind.Sequential)]
    public struct TOKEN_PRIVILEGES_ONE { public uint PrivilegeCount; public LUID Luid; public uint Attributes; }

    public const uint TOKEN_ADJUST_PRIVILEGES=0x20;
    public const uint TOKEN_QUERY=0x8;
    public const uint SE_PRIVILEGE_ENABLED=0x2;
    public const int SystemMemoryListInformation=80;

    [DllImport("user32.dll")]
    public static extern IntPtr GetForegroundWindow();

    [DllImport("user32.dll")]
    public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint processId);
}
'@
}

function Enable-YumNativePrivilege {
    param([Parameter(Mandatory)][string]$Privilege)
    $token=[IntPtr]::Zero
    try {
        $processHandle=[System.Diagnostics.Process]::GetCurrentProcess().Handle
        if(-not [YumRamNative]::OpenProcessToken($processHandle, ([YumRamNative]::TOKEN_ADJUST_PRIVILEGES -bor [YumRamNative]::TOKEN_QUERY), [ref]$token)){
            return [pscustomobject]@{Success=$false;Error=[Runtime.InteropServices.Marshal]::GetLastWin32Error()}
        }
        $luid=[YumRamNative+LUID]::new()
        if(-not [YumRamNative]::LookupPrivilegeValue($null,$Privilege,[ref]$luid)){
            return [pscustomobject]@{Success=$false;Error=[Runtime.InteropServices.Marshal]::GetLastWin32Error()}
        }
        $tp=[YumRamNative+TOKEN_PRIVILEGES_ONE]::new();$tp.PrivilegeCount=1;$tp.Luid=$luid;$tp.Attributes=[YumRamNative]::SE_PRIVILEGE_ENABLED
        $ptr=[Runtime.InteropServices.Marshal]::AllocHGlobal([Runtime.InteropServices.Marshal]::SizeOf($tp))
        try{
            [Runtime.InteropServices.Marshal]::StructureToPtr($tp,$ptr,$false)
            $ok=[YumRamNative]::AdjustTokenPrivileges($token,$false,$ptr,0,[IntPtr]::Zero,[IntPtr]::Zero)
            $err=[Runtime.InteropServices.Marshal]::GetLastWin32Error()
            return [pscustomobject]@{Success=($ok -and $err -eq 0);Error=$err}
        } finally {[Runtime.InteropServices.Marshal]::FreeHGlobal($ptr)}
    } catch { return [pscustomobject]@{Success=$false;Error=$_.Exception.HResult} }
    finally {if($token -ne [IntPtr]::Zero){[void][YumRamNative]::CloseHandle($token)}}
}

function Invoke-YumSetSystemMemoryListCommand {
    param([Parameter(Mandatory)][ValidateSet(2,3,4,5)][int]$Command)
    $ptr=[IntPtr]::Zero
    try {
        $ptr=[Runtime.InteropServices.Marshal]::AllocHGlobal(4)
        [Runtime.InteropServices.Marshal]::WriteInt32($ptr,$Command)
        $status=[YumRamNative]::NtSetSystemInformation([YumRamNative]::SystemMemoryListInformation,$ptr,4)
        [pscustomobject]@{Success=($status -ge 0);Status=$status;ErrorCode=([uint32]$status)}
    } catch { [pscustomobject]@{Success=$false;Status=-1;ErrorCode=$_.Exception.HResult} }
    finally {if($ptr -ne [IntPtr]::Zero){[Runtime.InteropServices.Marshal]::FreeHGlobal($ptr)}}
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
