#requires -Version 5.1
param(
    [Parameter(Mandatory=$true)]$Cache,
    [Parameter(Mandatory=$true)]$Config,
    [Parameter(Mandatory=$true)]$StopEvent,
    [Parameter(Mandatory=$true)][ValidateSet('Core','Aux')][string]$Mode
)

function Publish-Core {
    param($Memory,$CPU)
    [System.Threading.Monitor]::Enter($Cache.SyncRoot)
    try {
        $old = $Cache['Snapshot']
        $game = if ($null -ne $old) { $old.Game } else { [pscustomobject]@{ProcessId=0;ProcessName=$null;Detected=$false} }
        $gpu = if ($null -ne $old) { [double]$old.GPU3D } else { 0.0 }
        $fg = if ($null -ne $old) { [int]$old.ForegroundProcessId } else { 0 }
        $now=Get-Date
        $Cache['Snapshot']=[pscustomobject]@{Timestamp=$now;Memory=$Memory;CPU=[double]$CPU;GPU3D=$gpu;ForegroundProcessId=$fg;Game=$game}
        $Cache['LastCore']=$now
        $Cache['CoreCount']=[int]$Cache['CoreCount']+1; $Cache['SnapshotVersion']=[int]$Cache['SnapshotVersion']+1
    } finally { [System.Threading.Monitor]::Exit($Cache.SyncRoot) }
}

function Publish-Aux {
    param($Gpu,$Game,$ForegroundPid,[bool]$GpuSampled,[bool]$GameSampled)
    [System.Threading.Monitor]::Enter($Cache.SyncRoot)
    try {
        $old=$Cache['Snapshot']
        if($null -eq $old){ return }
        $now=Get-Date
        $Cache['Snapshot']=[pscustomobject]@{Timestamp=$old.Timestamp;Memory=$old.Memory;CPU=$old.CPU;GPU3D=[double]$Gpu;ForegroundProcessId=[int]$ForegroundPid;Game=$Game}
        if($GpuSampled){$Cache['LastGpu']=$now}
        if($GameSampled){$Cache['LastGame']=$now}
        $Cache['AuxCount']=[int]$Cache['AuxCount']+1; $Cache['SnapshotVersion']=[int]$Cache['SnapshotVersion']+1
    } finally { [System.Threading.Monitor]::Exit($Cache.SyncRoot) }
}

function Fail-Worker {
    param([Exception]$Exception)
    try {
        [System.Threading.Monitor]::Enter($Cache.SyncRoot)
        $Cache['ErrorCount']=[int]$Cache['ErrorCount']+1
        $Cache['LastError']=$Exception.Message
    } finally { [System.Threading.Monitor]::Exit($Cache.SyncRoot) }
}

function Get-MemoryFast {
    try {
        if("YumRamNative" -as [type]){
            $status=New-Object YumRamNative+MEMORYSTATUSEX
            if([YumRamNative]::GlobalMemoryStatusEx($status)){
                $total=[double]$status.ullTotalPhys/1GB
                $available=[double]$status.ullAvailPhys/1GB
                $used=[math]::Max(0,$total-$available)
                return [pscustomobject]@{TotalBytes=[uint64]$status.ullTotalPhys;AvailableBytes=[uint64]$status.ullAvailPhys;UsedBytes=[uint64]($status.ullTotalPhys-$status.ullAvailPhys);TotalGB=$total;UsedGB=$used;AvailableGB=$available;UsedPercent=$(if($total -gt 0){$used/$total*100}else{0})}
            }
        }
    } catch {}
    try {
        $os=Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
        $total=[double]$os.TotalVisibleMemorySize/1MB
        $available=[double]$os.FreePhysicalMemory/1MB
        $used=[math]::Max(0,$total-$available)
        return [pscustomobject]@{TotalBytes=[uint64]($os.TotalVisibleMemorySize*1KB);AvailableBytes=[uint64]($os.FreePhysicalMemory*1KB);UsedBytes=[uint64](($os.TotalVisibleMemorySize-$os.FreePhysicalMemory)*1KB);TotalGB=$total;UsedGB=$used;AvailableGB=$available;UsedPercent=$(if($total -gt 0){$used/$total*100}else{0})}
    } catch { return $null }
}

function Get-ForegroundPid {
    try {
        if("YumRamForegroundNative" -as [type]){
            $hwnd=[YumRamForegroundNative]::GetForegroundWindow()
            if($hwnd -ne [IntPtr]::Zero){$foregroundPid=0;[void][YumRamForegroundNative]::GetWindowThreadProcessId($hwnd,[ref]$foregroundPid);return [int]$foregroundPid}
        }
    } catch {}
    return 0
}

function Get-GameSnapshot {
    $known=@($Config.KnownGames)
    try {
        foreach($p in @(Get-Process -ErrorAction SilentlyContinue)){
            try {
                if($p.Id -eq $PID){continue}
                $clean=$p.ProcessName -replace '\.exe$',''
                foreach($g in $known){ if($clean -ieq ([string]$g -replace '\.exe$','')) { return [pscustomobject]@{ProcessId=[int]$p.Id;ProcessName=$p.ProcessName;Detected=$true} } }
            } catch {}
        }
    } catch {}
    return [pscustomobject]@{ProcessId=0;ProcessName=$null;Detected=$false}
}

try {
    if(-not ('YumRamNative' -as [type])){
        Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class YumRamNative {
 [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Auto)] public class MEMORYSTATUSEX { public uint dwLength; public uint dwMemoryLoad; public ulong ullTotalPhys; public ulong ullAvailPhys; public ulong ullTotalPageFile; public ulong ullAvailPageFile; public ulong ullTotalVirtual; public ulong ullAvailVirtual; public ulong ullAvailExtendedVirtual; public MEMORYSTATUSEX(){dwLength=(uint)Marshal.SizeOf(typeof(MEMORYSTATUSEX));} }
 [DllImport("kernel32.dll", SetLastError=true)] public static extern bool GlobalMemoryStatusEx([In,Out] MEMORYSTATUSEX lpBuffer);
}
"@
    }
    if(-not ('YumRamForegroundNative' -as [type])){
        Add-Type @"
using System; using System.Runtime.InteropServices;
public static class YumRamForegroundNative { [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow(); [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint lpdwProcessId); }
"@
    }
} catch { Fail-Worker $_.Exception }

if($Mode -eq 'Core'){
    $cpuCounter=$null
    try { $cpuCounter=New-Object System.Diagnostics.PerformanceCounter('Processor','% Processor Time','_Total'); [void]$cpuCounter.NextValue() } catch { $cpuCounter=$null }
    $cpu=0.0
    $lastCpu=Get-Date
    $nextCpu=(Get-Date).AddSeconds(1.0)
    while(-not $StopEvent.IsSet){
        try {
            $memory=Get-MemoryFast
            if($null -eq $memory){ throw 'Memory sample unavailable' }
            $now=Get-Date
            if($cpuCounter -and $now -ge $nextCpu){ $cpu=[math]::Round([double]$cpuCounter.NextValue(),1); $nextCpu=$now.AddSeconds(1.0) }
            Publish-Core -Memory $memory -CPU $cpu
        } catch { Fail-Worker $_.Exception }
        Start-Sleep -Milliseconds ([int][math]::Max(50,([double]$Config.TelemetryIntervalSeconds*1000)))
    }
} else {
    $lastGpu=Get-Date '2000-01-01'; $lastGame=Get-Date '2000-01-01'; $gpu=0.0; $game=[pscustomobject]@{ProcessId=0;ProcessName=$null;Detected=$false}; $fg=0
    while(-not $StopEvent.IsSet){
        try {
            $now=Get-Date; $gpuSampled=$false; $gameSampled=$false
            if(($now-$lastGpu).TotalSeconds -ge [double]$Config.GPUIntervalSeconds){
                try {
                    $counter=Get-Counter '\GPU Engine(*)\Utilization Percentage' -ErrorAction Stop
                    $max=0.0
                    foreach($sample in $counter.CounterSamples){ if(([string]$sample.InstanceName -match 'engtype_3D')){ $max=[math]::Max($max,[double]$sample.CookedValue) } }
                    $gpu=[math]::Round([math]::Min(100,$max),1)
                } catch { $gpu=0.0 }
                $lastGpu=$now; $gpuSampled=$true
            }
            if(($now-$lastGame).TotalSeconds -ge [double]$Config.GameDetectionIntervalSeconds){ $game=Get-GameSnapshot; $fg=Get-ForegroundPid; $lastGame=$now; $gameSampled=$true }
            Publish-Aux -Gpu $gpu -Game $game -ForegroundPid $fg -GpuSampled:$gpuSampled -GameSampled:$gameSampled
        } catch { Fail-Worker $_.Exception }
        Start-Sleep -Milliseconds 200
    }
}
