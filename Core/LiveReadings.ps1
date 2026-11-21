#requires -Version 5.1
# 5.15.2: live CPU / GPU / VRAM readings that work whether or not monitoring is on (user report: CPU speed showed
# "-- GHz" and GPU did not move while monitoring was off; GPU "3D" was unexplained and VRAM was missing).
# All counters are opened once and then read with NextValue / one ReadCategory (a few ms). UI thread only.

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

function Get-YumGpuAdapters {
    if($null -eq $script:YumLive.Adapters){
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

function Format-YumVram {
    param($Gpu)
    if($null -eq $Gpu -or $null -eq $Gpu.Main){return ''}
    # One line per graphics chip (laptops have two: the busy % may come from the built-in one while the gaming
    # card idles), biggest VRAM first. Fits the narrow Overview card; per-chip busy % is in the tooltip.
    #   VRAM in use
    #   RTX 3050  0.0 / 3.9 GB
    #   Radeon  0.4 / 0.5 GB
    $lines=foreach($a in @($Gpu.Adapters | Sort-Object VramTotalGB -Descending | Select-Object -First 2)){
        $short=([string]$a.Name -replace '^(NVIDIA|AMD|Intel\(R\))\s+','' -replace '^GeForce\s+','' -replace '\(TM\)|\(R\)','' -replace '\s+(Laptop GPU|Graphics)$','').Trim()
        if([string]::IsNullOrWhiteSpace($short)){$short=[string]$a.Name}
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
