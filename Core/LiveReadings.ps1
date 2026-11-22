#requires -Version 5.1
# 5.15.2: live CPU / GPU / VRAM readings that work whether or not monitoring is on (user report: CPU speed showed
# "-- GHz" and GPU did not move while monitoring was off; GPU "3D" was unexplained and VRAM was missing).
# Counters are opened once, then read with NextValue / one ReadCategory. Since 5.15.9 the app reads them in a background runspace (Start-YumLiveSampler).

function Initialize-YumGpuInfoType {
  # compiled on first use, not at start-up (only Overview's GPU card needs it)
  if(-not ('YumGpuInfo' -as [type])){
    Add-Type -TypeDefinition @'
using System; using System.Collections.Generic; using System.Runtime.InteropServices;
public static class YumGpuInfo {
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    public struct DXGI_ADAPTER_DESC1 {
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string Description;
        public uint VendorId, DeviceId, SubSysId, Revision;
        public UIntPtr DedicatedVideoMemory, DedicatedSystemMemory, SharedSystemMemory;
        public uint LuidLow; public int LuidHigh; public uint Flags;
    }
    [ComImport, Guid("29038f61-3839-4626-91fd-086879011a05"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IDXGIAdapter1 {
        void SetPrivateData(); void SetPrivateDataInterface(); void GetPrivateData(); void GetParent();
        void EnumOutputs(); void GetDesc(); void CheckInterfaceSupport();
        [PreserveSig] int GetDesc1(out DXGI_ADAPTER_DESC1 desc);
    }
    [ComImport, Guid("770aae78-f26f-4dba-a829-253c83d1b387"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IDXGIFactory1 {
        void SetPrivateData(); void SetPrivateDataInterface(); void GetPrivateData(); void GetParent();
        void EnumAdapters(); void MakeWindowAssociation(); void GetWindowAssociation(); void CreateSwapChain(); void CreateSoftwareAdapter();
        [PreserveSig] int EnumAdapters1(uint index, out IDXGIAdapter1 adapter);
        [PreserveSig] bool IsCurrent();
    }
    [DllImport("dxgi.dll")] static extern int CreateDXGIFactory1(ref Guid riid, [MarshalAs(UnmanagedType.Interface)] out object factory);
    public sealed class Adapter { public string Name; public string Luid; public double DedicatedGB; public uint VendorId; public bool Software; }
    public static List<Adapter> Adapters() {
        var list = new List<Adapter>();
        Guid g = new Guid("770aae78-f26f-4dba-a829-253c83d1b387"); object o;
        if (CreateDXGIFactory1(ref g, out o) != 0 || o == null) return list;
        var f = (IDXGIFactory1)o;
        for (uint i = 0; i < 16; i++) {
            IDXGIAdapter1 a; if (f.EnumAdapters1(i, out a) != 0 || a == null) break;
            DXGI_ADAPTER_DESC1 d; if (a.GetDesc1(out d) == 0) {
                list.Add(new Adapter { Name = (d.Description ?? "").Trim(), Luid = String.Format("luid_0x{0:x8}_0x{1:x8}", d.LuidHigh, d.LuidLow),
                    DedicatedGB = d.DedicatedVideoMemory.ToUInt64() / 1073741824.0, VendorId = d.VendorId, Software = (d.Flags & 2) != 0 });
            }
            Marshal.ReleaseComObject(a);
        }
        Marshal.ReleaseComObject(f);
        return list;
    }
}
'@
  }
}

$script:YumLive=@{Adapters=$null;VramCounters=@{};GpuCategory=$null;GpuPrev=@{};CpuTime=$null;CpuPerf=$null;BaseMHz=0.0}
$script:YumLiveReadingsSource=$PSCommandPath

# 5.15.9 (user: "program lagging, not responding at first, then responded"; "minimal lag to no lag"). Measured on
# the test PC with real data: the first Overview refresh blocked the window 3.0 s while Windows opened the GPU
# (1.5 s), CPU (1.1 s) and disk counters on the UI thread. The readings are now taken by a background runspace
# (same functions, loaded from this file) every ~2 s while the Overview or mini bar asks; the UI only copies the
# latest values (no waiting). The functions below stay callable directly (tests, the sampler itself).
function Start-YumLiveSampler {
    if($null -ne $script:Yum['LiveSampler']){return}
    $shared=[hashtable]::Synchronized(@{Gpu=$null;Cpu=$null;Disk=$null;Temps=$null;TempsAt=[datetime]::MinValue;Adapters=$null;Updated=[datetime]::MinValue;Samples=0;WantedUntil=(Get-Date).AddSeconds(10);Stop=$false;Error='';IntervalMs=2000})
    $ps=[powershell]::Create()
    [void]$ps.AddScript({
        param($S,$Src)
        . ([scriptblock]::Create($Src))
        $last=[datetime]::MinValue
        while(-not $S.Stop){
            try{
                # Second sample after 0.5 s so busy % (a difference of two samples) is real right away.
                $gap=if([int]$S.Samples -lt 2){500}else{[int]$S.IntervalMs-150}
                if((Get-Date) -lt $S.WantedUntil -and ((Get-Date)-$last).TotalMilliseconds -ge $gap){
                    $last=Get-Date
                    # (5.16.1: CPU and disk first - the GPU adapter list compiles a helper the first time)
                    # Each reading is published as soon as it exists (the first GPU read alone takes ~1.5 s).
                    $S.Cpu=Get-YumLiveCpu; $S.Disk=Get-YumLiveDisk; if($null -eq $S.Adapters){ $S.Adapters=@(Get-YumGpuAdapters) }; $S.Gpu=Get-YumLiveGpu
                    # 5.16.2: temperatures every ~5 s (disk every 60 s, administrator only).
                    if(((Get-Date)-[datetime]$S.TempsAt).TotalSeconds -ge 4.5){ $S.TempsAt=Get-Date; try{ $S.Temps=Get-YumLiveTemps -Gpu $S.Gpu -Previous $S.Temps }catch{ $S.Error='temps: '+$_.Exception.Message } }
                    $S.Updated=Get-Date; $S.Samples=[int]$S.Samples+1; $S.Error=''
                }
            }catch{ $S.Error=$_.Exception.Message }
            Start-Sleep -Milliseconds 150
        }
    }).AddArgument($shared).AddArgument([IO.File]::ReadAllText($script:YumLiveReadingsSource))
    $h=$ps.BeginInvoke()
    $script:Yum['LiveSampler']=@{Shared=$shared;Ps=$ps;Handle=$h}
}

function Stop-YumLiveSampler {
    try{ $v=$script:Yum['LiveSampler']; if($null -ne $v){ $v.Shared.Stop=$true; try{$v.Ps.Stop()}catch{}; try{$v.Ps.Dispose()}catch{}; $script:Yum['LiveSampler']=$null } }catch{}
}

function Get-YumLiveReading {
    # Latest background reading: Kind = Gpu | Cpu | Disk. $null until the first sample (a fraction of a second).
    # Asking keeps the sampler reading for 8 s; nothing is read while nobody asks (window hidden, other page).
    param([ValidateSet('Gpu','Cpu','Disk','Temps')][string]$Kind)
    try{
        Start-YumLiveSampler
        $s=$script:Yum['LiveSampler'].Shared
        $s.WantedUntil=(Get-Date).AddSeconds(8)
        return $s[$Kind]
    }catch{ return $null }
}

function Get-YumGpuAdapters {
    if($null -eq $script:YumLive.Adapters){
        # In the app: take the list the background sampler made instead of compiling DXGI code on the UI thread.
        $smp=$null; try{ if($null -ne (Get-Variable -Name Yum -Scope Script -ErrorAction SilentlyContinue) -and $script:Yum -is [System.Collections.IDictionary]){ $smp=$script:Yum['LiveSampler'] } }catch{}
        if($null -ne $smp){ $pub=$smp.Shared.Adapters; if($null -eq $pub){ return @() }; $script:YumLive.Adapters=@($pub); return @($pub) }
        $a=@(); try{ Initialize-YumGpuInfoType; $a=@([YumGpuInfo]::Adapters() | Where-Object { -not $_.Software -and $_.VendorId -ne 0x1414 }) }catch{}   # 0x1414 = Microsoft Basic Render
        $script:YumLive.Adapters=$a
    }
    return @($script:YumLive.Adapters)
}

function Get-YumLiveGpu {
    # Per adapter: 3D engine busy % (same calculation as the telemetry worker) and dedicated VRAM in use.
    # Returns @{Adapters=[@{Name;ThreeD;VramUsedGB;VramTotalGB}]; Main=<adapter games use: most dedicated VRAM>}.
    $L=$script:YumLive
    $adapters=@(Get-YumGpuAdapters)
    $threeD=@{}
    try{
        if($null -eq $L.GpuCategory){ $L.GpuCategory=New-Object System.Diagnostics.PerformanceCounterCategory('GPU Engine') }
        $data=$L.GpuCategory.ReadCategory()['Utilization Percentage']; $next=@{}
        foreach($key in $data.Keys){
            $name=[string]$key; if($name -notmatch 'engtype_3D$'){continue}
            $s=$data[$key].Sample; $next[$name]=$s
            if($L.GpuPrev.ContainsKey($name)){ $v=[System.Diagnostics.CounterSample]::Calculate($L.GpuPrev[$name],$s); if($name -match '(luid_0x[0-9a-f]+_0x[0-9a-f]+)'){ $k=$Matches[1].ToLowerInvariant(); $threeD[$k]=[double]$threeD[$k]+[double]$v } }
        }
        $L.GpuPrev=$next
    }catch{}
    $rows=foreach($ad in $adapters){
        $key=([string]$ad.Luid).ToLowerInvariant()
        $used=$null
        try{
            if(-not $L.VramCounters.ContainsKey($key)){ $L.VramCounters[$key]=New-Object System.Diagnostics.PerformanceCounter('GPU Adapter Memory','Dedicated Usage',($key+'_phys_0')) }
            $used=[double]$L.VramCounters[$key].NextValue()/1GB
        }catch{ $L.VramCounters[$key]=$null }
        [pscustomobject]@{Name=[string]$ad.Name;ThreeD=[math]::Round([math]::Min(100,[double]$threeD[$key]),1);VramUsedGB=$used;VramTotalGB=[double]$ad.DedicatedGB}
    }
    $rows=@($rows)
    $main=@($rows | Sort-Object VramTotalGB -Descending | Select-Object -First 1)[0]
    return [pscustomobject]@{Adapters=$rows;Main=$main;Busiest=[math]::Round((@($rows | ForEach-Object ThreeD) + 0 | Measure-Object -Maximum).Maximum,1)}
}

function Get-YumLiveCpu {
    # CPU % (Task Manager's "Utilization" basis) and effective speed. Cheap after the first call.
    $L=$script:YumLive
    try{
        if($null -eq $L.CpuTime){ $L.CpuTime=New-Object System.Diagnostics.PerformanceCounter('Processor Information','% Processor Utility','_Total'); [void]$L.CpuTime.NextValue() }
        if($null -eq $L.CpuPerf){ $L.CpuPerf=New-Object System.Diagnostics.PerformanceCounter('Processor Information','% Processor Performance','_Total'); [void]$L.CpuPerf.NextValue() }
        if($L.BaseMHz -le 0){ try{ $L.BaseMHz=[double](Get-CimInstance Win32_Processor -ErrorAction Stop | Select-Object -First 1).MaxClockSpeed }catch{} }
        $pct=[math]::Min(100.0,[math]::Max(0.0,[double]$L.CpuTime.NextValue()))
        $mhz=if($L.BaseMHz -gt 0){[math]::Round($L.BaseMHz*[double]$L.CpuPerf.NextValue()/100.0,0)}else{0}
        return [pscustomobject]@{Percent=[math]::Round($pct,1);MHz=$mhz;BaseMHz=$L.BaseMHz}
    }catch{ return $null }
}

function Get-YumGpuShortName {
    # "NVIDIA GeForce RTX 3050 Laptop GPU" -> "RTX 3050"; "AMD Radeon(TM) Graphics" -> "Radeon".
    param([string]$Name)
    $short=([string]$Name -replace '^(NVIDIA|AMD|Intel\(R\))\s+','' -replace '^GeForce\s+','' -replace '\(TM\)|\(R\)','' -replace '\s+(Laptop GPU|Graphics)$','').Trim()
    if([string]::IsNullOrWhiteSpace($short)){$short=[string]$Name}
    return $short
}

function Format-YumVram {
    param($Gpu)
    if($null -eq $Gpu -or $null -eq $Gpu.Main){return ''}
    # One line per graphics chip (laptops have two: the busy % may come from the built-in one while the gaming
    # card idles), biggest VRAM first. Fits the narrow Overview card; per-chip busy % is in the tooltip.
    #   VRAM in use
    #   RTX 3050  0.0 / 3.9 GB
    #   Radeon  0.4 / 0.5 GB
    $lines=foreach($a in @($Gpu.Adapters | Sort-Object VramTotalGB -Descending | Select-Object -First 2)){
        $short=Get-YumGpuShortName ([string]$a.Name)
        if($null -ne $a.VramUsedGB -and [double]$a.VramTotalGB -gt 0){ '{0}  {1:N1} / {2:N1} GB' -f $short,[double]$a.VramUsedGB,[double]$a.VramTotalGB }
        elseif([double]$a.VramTotalGB -gt 0){ '{0}  {1:N1} GB' -f $short,[double]$a.VramTotalGB }
    }
    $lines=@($lines | Where-Object { $_ })
    if($lines.Count -eq 0){return ''}
    return ((@('VRAM in use')+$lines) -join [Environment]::NewLine)
}

# 5.15.2 (user request: "add disk information like task manager"). Same numbers Task Manager's Disk page uses:
# active time = 100 - PhysicalDisk "% Idle Time", read/write speed, average response time, plus free space per
# drive and SSD/HDD. One ReadCategory per refresh (a few ms); disk type is looked up once.
$script:YumLive.DiskCategory=$null; $script:YumLive.DiskPrev=@{}; $script:YumLive.DiskTypes=$null

function Get-YumDiskTypes {
    if($null -eq $script:YumLive.DiskTypes){
        $t=@{}
        try{ foreach($d in @(Get-CimInstance -Namespace root\Microsoft\Windows\Storage -ClassName MSFT_PhysicalDisk -ErrorAction Stop -OperationTimeoutSec 3)){
                 $kind=switch([int]$d.MediaType){4{'SSD'}3{'HDD'}default{''}}
                 if([int]$d.BusType -eq 17 -and $kind -eq 'SSD'){$kind='SSD (NVMe)'}
                 if([int]$d.BusType -eq 7){$kind=if($kind){"USB $kind"}else{'USB drive'}}
                 $t[[string]$d.DeviceId]=$kind } }catch{}
        $script:YumLive.DiskTypes=$t
    }
    return $script:YumLive.DiskTypes
}

function Get-YumLiveDisk {
    # Returns @{Disks=[@{Number;Letters;Type;ActivePercent;ReadMBs;WriteMBs;ResponseMs}]; Busiest; ReadMBs; WriteMBs; Drives=[@{Letter;FreeGB;TotalGB}]}
    $L=$script:YumLive
    $disks=@()
    try{
        if($null -eq $L.DiskCategory){ $L.DiskCategory=New-Object System.Diagnostics.PerformanceCounterCategory('PhysicalDisk') }
        $all=$L.DiskCategory.ReadCategory(); $next=@{}
        $idle=$all['% Idle Time']; $rd=$all['Disk Read Bytes/sec']; $wr=$all['Disk Write Bytes/sec']; $resp=$all['Avg. Disk sec/Transfer']
        $types=Get-YumDiskTypes
        foreach($key in @($idle.Keys)){
            $inst=[string]$key; if($inst -eq '_Total'){continue}
            $cur=@{Idle=$idle[$key].Sample;Read=$rd[$key].Sample;Write=$wr[$key].Sample;Resp=$resp[$key].Sample}; $next[$inst]=$cur
            $num=($inst -split ' ')[0]; $letters=(($inst -split ' ' | Select-Object -Skip 1) -join ' ').Trim().ToUpperInvariant()
            $active=$null;$r=$null;$w=$null;$ms=$null
            if($L.DiskPrev.ContainsKey($inst)){
                $p=$L.DiskPrev[$inst]
                $active=[math]::Round([math]::Min(100,[math]::Max(0,100-[double][System.Diagnostics.CounterSample]::Calculate($p.Idle,$cur.Idle))),0)
                $r=[double][System.Diagnostics.CounterSample]::Calculate($p.Read,$cur.Read)/1MB
                $w=[double][System.Diagnostics.CounterSample]::Calculate($p.Write,$cur.Write)/1MB
                $ms=[double][System.Diagnostics.CounterSample]::Calculate($p.Resp,$cur.Resp)*1000
            }
            $disks+=[pscustomobject]@{Number=$num;Letters=$letters;Type=[string]$types[$num];ActivePercent=$active;ReadMBs=$r;WriteMBs=$w;ResponseMs=$ms}
        }
        $L.DiskPrev=$next
    }catch{}
    $drives=@()
    try{ foreach($d in [IO.DriveInfo]::GetDrives()){ if($d.DriveType -eq [IO.DriveType]::Fixed -and $d.IsReady){ $drives+=[pscustomobject]@{Letter=$d.Name.TrimEnd('\');FreeGB=$d.AvailableFreeSpace/1GB;TotalGB=$d.TotalSize/1GB} } } }catch{}
    $ready=@($disks | Where-Object { $null -ne $_.ActivePercent })
    $busiest=if($ready.Count){[double]($ready | Measure-Object ActivePercent -Maximum).Maximum}else{$null}
    $sumR=if($ready.Count){[double]($ready | Measure-Object ReadMBs -Sum).Sum}else{$null}
    $sumW=if($ready.Count){[double]($ready | Measure-Object WriteMBs -Sum).Sum}else{$null}
    return [pscustomobject]@{Disks=@($disks | Sort-Object Number);Busiest=$busiest;ReadMBs=$sumR;WriteMBs=$sumW;Drives=$drives}
}

function Format-YumDiskSpeed { param($MBs) if($null -eq $MBs){return '--'}; if([double]$MBs -lt 1){ return ('{0:N0} KB/s' -f ([double]$MBs*1024)) }; return ('{0:N1} MB/s' -f [double]$MBs) }

function Format-YumDiskLines {
    # Task Manager style, one line per physical disk, then free space per drive.
    #   Disk 0 (C:) SSD  3 % · 120 KB/s read · 1.1 MB/s write · 0.4 ms
    #   C:  120 GB free of 476 GB
    param($Disk,[string]$SkipDrive)
    if($null -eq $Disk){return ''}
    $lines=foreach($d in @($Disk.Disks)){
        $name=('Disk {0}' -f $d.Number); if($d.Letters){$name+=(' ({0})' -f $d.Letters)}; if($d.Type){$name+=(' '+$d.Type)}
        if($null -eq $d.ActivePercent){ $name } else { ('{0}: {1} % busy · read {2} · write {3} · {4:N1} ms' -f $name,$d.ActivePercent,(Format-YumDiskSpeed $d.ReadMBs),(Format-YumDiskSpeed $d.WriteMBs),[double]$d.ResponseMs) }
    }
    $space=foreach($v in @($Disk.Drives | Where-Object { $_.Letter -ne $SkipDrive })){ ('{0}  {1:N0} GB free of {2:N0} GB' -f $v.Letter,[double]$v.FreeGB,[double]$v.TotalGB) }
    return ((@($lines)+@($space) | Where-Object { $_ }) -join [Environment]::NewLine)
}

# 5.16.2 (user: "showing temps would be nice"). Only what Windows and the graphics driver give without extra
# drivers (tools that read CPU sensors directly install kernel drivers - e.g. WinRing0, which Windows now flags):
#  - CPU area: Windows' "Thermal Zone Information" counter (the hottest zone; on laptops it sits at the CPU).
#  - NVIDIA graphics: nvml.dll from the NVIDIA driver - read only while the chip is awake (busy or holding VRAM), so
#    YUMRAM never wakes a sleeping laptop GPU (that costs battery).
#  - Disks: Windows' drive health data (MSFT_StorageReliabilityCounter), every 60 s, administrator only.
# Runs in the background sampler (Start-YumLiveSampler).
function Initialize-YumNvmlType {
    if('YumNvml' -as [type]){ return $true }
    if(-not [IO.File]::Exists((Join-Path $env:windir 'System32\nvml.dll'))){ return $false }
    try{
        Add-Type -TypeDefinition @'
using System; using System.Runtime.InteropServices; using System.Text; using System.Collections.Generic;
public static class YumNvml {
    [DllImport("nvml.dll", EntryPoint = "nvmlInit_v2")] static extern int Init();
    [DllImport("nvml.dll", EntryPoint = "nvmlShutdown")] static extern int Shutdown();
    [DllImport("nvml.dll", EntryPoint = "nvmlDeviceGetCount_v2")] static extern int Count(out uint n);
    [DllImport("nvml.dll", EntryPoint = "nvmlDeviceGetHandleByIndex_v2")] static extern int Handle(uint i, out IntPtr h);
    [DllImport("nvml.dll", EntryPoint = "nvmlDeviceGetTemperature")] static extern int Temp(IntPtr h, int sensor, out uint t);
    [DllImport("nvml.dll", EntryPoint = "nvmlDeviceGetName", CharSet = CharSet.Ansi)] static extern int Name(IntPtr h, StringBuilder name, uint len);
    // Returns "name|celsius" per NVIDIA GPU; opened and closed each time.
    public static string[] Read() {
        var list = new List<string>();
        try {
            if (Init() != 0) return list.ToArray();
            try {
                uint n; if (Count(out n) != 0) return list.ToArray();
                for (uint i = 0; i < n; i++) {
                    IntPtr h; if (Handle(i, out h) != 0) continue;
                    uint t; if (Temp(h, 0, out t) != 0) continue;
                    var sb = new StringBuilder(96); Name(h, sb, 96);
                    list.Add(sb.ToString() + "|" + t);
                }
            } finally { Shutdown(); }
        } catch { }
        return list.ToArray();
    }
}
'@
        return $true
    }catch{ return $false }
}

function Get-YumLiveTemps {
    param($Gpu,$Previous)
    $L=$script:YumLive
    $out=[ordered]@{CpuC=$null;CpuSource='';GpuC=$null;GpuName='';GpuAsleep=$false;DiskC=$null;DiskName='';DiskAt=[datetime]::MinValue}
    # CPU area (thermal zones).
    try{
        if($null -eq $L['ThermalCategory']){ $L['ThermalCategory']=New-Object System.Diagnostics.PerformanceCounterCategory('Thermal Zone Information') }
        $all=$L['ThermalCategory'].ReadCategory()
        $hp=$all['High Precision Temperature']; $lo=$all['Temperature']
        $best=$null;$bestName=''
        $useHp=($null -ne $hp -and $hp.Count -gt 0); $src=if($useHp){$hp}else{$lo}
        foreach($k in @($src.Keys)){
            $raw=[double]$src[$k].RawValue
            $c=if($useHp){$raw/10.0-273.15}else{$raw-273.15}
            if($c -gt 5 -and $c -lt 125 -and ($null -eq $best -or $c -gt $best)){ $best=$c; $bestName=[string]$k }
        }
        if($null -ne $best){ $out.CpuC=[math]::Round($best,0); $out.CpuSource=$bestName }
    }catch{}
    # NVIDIA graphics - only when the chip is awake.
    try{
        $nv=@(@($Gpu.Adapters) | Where-Object { [string]$_.Name -match '(?i)nvidia' })
        if($nv.Count -gt 0){
            $awake=@($nv | Where-Object { ([double]$_.VramUsedGB -gt 0.05) -or ([double]$_.ThreeD -gt 0.5) }).Count -gt 0
            $out.GpuName=[string]$nv[0].Name
            if(-not $awake){ $out.GpuAsleep=$true }
            elseif(Initialize-YumNvmlType){
                foreach($r in [YumNvml]::Read()){ $p=$r.Split('|'); if($p.Count -eq 2){ $t=[double]$p[1]; if($t -gt 0 -and $t -lt 130 -and ($null -eq $out.GpuC -or $t -gt $out.GpuC)){ $out.GpuC=$t } } }
            }
        }
    }catch{}
    # Disks: every 60 s, administrator only (Windows refuses otherwise).
    try{
        $prevAt=[datetime]::MinValue; if($null -ne $Previous){ $prevAt=[datetime]$Previous.DiskAt }
        if(((Get-Date)-$prevAt).TotalSeconds -lt 60 -and $null -ne $Previous){ $out.DiskC=$Previous.DiskC; $out.DiskName=$Previous.DiskName; $out.DiskAt=$prevAt }
        elseif(([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){
            $out.DiskAt=Get-Date
            $hot=$null
            foreach($r in @(Get-CimInstance -Namespace root\Microsoft\Windows\Storage -ClassName MSFT_StorageReliabilityCounter -ErrorAction Stop -OperationTimeoutSec 5)){ $t=[double]$r.Temperature; if($t -gt 0 -and $t -lt 110 -and ($null -eq $hot -or $t -gt $hot)){ $hot=$t } }
            $out.DiskC=$hot
        } else { $out.DiskAt=Get-Date }
    }catch{ $out.DiskAt=Get-Date }
    return [pscustomobject]$out
}

function Format-YumTemp {
    # "84°C" and a colour: green / amber / red at the given warm / hot thresholds.
    param($Celsius,[double]$Warm,[double]$Hot)
    if($null -eq $Celsius){ return $null }
    $c=[double]$Celsius
    $hex=if($c -ge $Hot){'#F87171'}elseif($c -ge $Warm){'#FBBF24'}else{'#86EFAC'}
    return [pscustomobject]@{Text=('{0:N0}°C' -f $c);Hex=$hex}
}
