#requires -Version 5.1
# 5.8: CPU balance (Process Lasso "ProBalance" parity).
#
# Windows lets a CPU-bound program at Normal priority take every cycle, so the program you are using
# stutters. CPU balance does what Bitsum documents for ProBalance: when the PC is busy and a BACKGROUND
# program is hogging the CPU, it temporarily lowers that program's priority class to Below Normal and
# restores it as soon as the program calms down. Below Normal only changes precedence under contention;
# an uncontended Below Normal program still runs at full speed.
#
# Never touched: the foreground program (and other processes of the same app / its children), the
# detected game, YUMRAM, Windows core processes, services (session 0), protected/excluded programs, and
# programs that already set a non-Normal priority themselves (they did so for a reason).
# Thresholds are YUMRAM's own (Bitsum does not publish ProBalance's): total CPU >= 70% and the program
# >= 10% of all cores for 2 s; restore after 3 s below 4% or when total CPU drops under 50%.

$script:YumCpuBalanceCoreNames=@('idle','system','registry','smss','csrss','wininit','services','lsass','winlogon','svchost','dwm','fontdrvhost','memory compression','audiodg','explorer','sihost','ctfmon','taskhostw','searchhost','startmenuexperiencehost','shellexperiencehost','textinputhost','runtimebroker','securityhealthservice','msmpeng','nissrv','mssense','conhost','wmiprvse','spoolsv','lsaiso','wudfhost','dllhost')

# ---------------------------------------------------------------- 5.11 CPU care: machine profile
# Windows reports the exact layout of the CPU it runs on, so YUMRAM needs no CPU database: physical
# cores, which logical processors share a core (SMT), efficiency class (Intel P/E cores), and which cores
# share an L3 cache (AMD CCX/CCD, incl. X3D chips with one large-cache die). Measured on a Ryzen 7 4800H
# (2 x 4-core CCX, SMT) under a 32-thread hog: Below Normal fixed stutter (wake 5.1 -> 2.0 ms) but not
# throughput; keeping the hog off one CCX made a 4-thread foreground job 35% faster (314 -> 205 ms)
# while the hog kept ~60% of its work. EcoQoS changed nothing measurable on that (Zen 2) chip; Microsoft
# tuned it first for Intel 10th/11th gen mobile, Ryzen 5000 mobile and Qualcomm, later broader silicon.
if(-not ('YumCpuCareNative' -as [type])){
    Add-Type -TypeDefinition @'
using System; using System.Runtime.InteropServices; using System.Collections.Generic;
public static class YumCpuCareNative {
    [DllImport("kernel32.dll", SetLastError=true)] static extern bool GetLogicalProcessorInformationEx(int rel, IntPtr buf, ref uint len);
    [DllImport("kernel32.dll", SetLastError=true)] static extern IntPtr OpenProcess(uint access, bool inherit, int pid);
    [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr h);
    [DllImport("kernel32.dll", SetLastError=true)] static extern bool SetProcessInformation(IntPtr h, int cls, ref PPTS info, int size);
    [DllImport("kernel32.dll", SetLastError=true)] static extern bool SetProcessInformation(IntPtr h, int cls, ref MPI info, int size);
    [StructLayout(LayoutKind.Sequential)] struct PPTS { public uint Version, ControlMask, StateMask; }
    [StructLayout(LayoutKind.Sequential)] struct MPI { public uint MemoryPriority; }
    public class Core { public ulong Mask; public int EfficiencyClass; public bool Smt; }
    public class Cache { public ulong Mask; public uint SizeKB; }
    public static List<Core> Cores = new List<Core>(); public static List<Cache> L3 = new List<Cache>();
    public static void Detect() {
        Cores.Clear(); L3.Clear(); uint len = 0;
        GetLogicalProcessorInformationEx(0xFFFF, IntPtr.Zero, ref len);
        IntPtr buf = Marshal.AllocHGlobal((int)len);
        try {
            if (!GetLogicalProcessorInformationEx(0xFFFF, buf, ref len)) return;
            int off = 0;
            while (off < len) {
                IntPtr p = new IntPtr(buf.ToInt64() + off);
                int rel = Marshal.ReadInt32(p, 0); int size = Marshal.ReadInt32(p, 4);
                if (rel == 0) { // RelationProcessorCore
                    byte flags = Marshal.ReadByte(p, 8); byte eff = Marshal.ReadByte(p, 9);
                    ushort groups = (ushort)Marshal.ReadInt16(p, 30); ulong mask = (ulong)Marshal.ReadInt64(p, 32); ushort grp = (ushort)Marshal.ReadInt16(p, 40);
                    if (groups >= 1 && grp == 0) Cores.Add(new Core { Mask = mask, EfficiencyClass = eff, Smt = (flags & 1) == 1 });
                } else if (rel == 2) { // RelationCache
                    byte level = Marshal.ReadByte(p, 8); uint csize = (uint)Marshal.ReadInt32(p, 12); int ctype = Marshal.ReadInt32(p, 16);
                    ulong mask = (ulong)Marshal.ReadInt64(p, 40); ushort grp = (ushort)Marshal.ReadInt16(p, 48);
                    if (level == 3 && (ctype == 0 || ctype == 2) && grp == 0) L3.Add(new Cache { Mask = mask, SizeKB = csize / 1024 });
                }
                if (size <= 0) break; off += size;
            }
        } finally { Marshal.FreeHGlobal(buf); }
    }
    static IntPtr Open(int pid) { return OpenProcess(0x0200 | 0x1000, false, pid); } // SET_INFORMATION | QUERY_LIMITED
    public static bool EcoQoS(int pid, bool on) {
        IntPtr h = Open(pid); if (h == IntPtr.Zero) return false;
        // on: opt into EcoQoS; off: hand control back to Windows' own heuristics (ControlMask 0).
        var s = new PPTS { Version = 1, ControlMask = on ? 1u : 0u, StateMask = on ? 1u : 0u };
        bool ok = SetProcessInformation(h, 4, ref s, 12); CloseHandle(h); return ok;
    }
    public static bool MemoryPriority(int pid, uint priority) {
        IntPtr h = Open(pid); if (h == IntPtr.Zero) return false;
        var s = new MPI { MemoryPriority = priority }; bool ok = SetProcessInformation(h, 0, ref s, 4); CloseHandle(h); return ok;
    }
}
'@
}

# Instant reaction to app switches (idea from the open-source EnergyStar, which un-throttles the app you
# switch to on the Windows foreground event instead of polling): the UI thread hooks EVENT_SYSTEM_FOREGROUND
# and wakes the CPU care worker, so a held-back program you click on is restored within milliseconds.
if(-not ('YumForegroundHook' -as [type])){
    Add-Type -TypeDefinition @'
using System; using System.Runtime.InteropServices; using System.Threading;
public static class YumForegroundHook {
    delegate void WinEventProc(IntPtr hook, uint ev, IntPtr hwnd, int idObject, int idChild, uint thread, uint time);
    [DllImport("user32.dll")] static extern IntPtr SetWinEventHook(uint min, uint max, IntPtr mod, WinEventProc proc, uint pid, uint tid, uint flags);
    [DllImport("user32.dll")] static extern bool UnhookWinEvent(IntPtr hook);
    static WinEventProc _proc; static IntPtr _hook = IntPtr.Zero;
    public static AutoResetEvent Wake = new AutoResetEvent(false);
    public static bool Start() {
        if (_hook != IntPtr.Zero) return true;
        _proc = (h, e, w, o, c, t, tm) => { Wake.Set(); };
        _hook = SetWinEventHook(3, 3, IntPtr.Zero, _proc, 0, 0, 0); // EVENT_SYSTEM_FOREGROUND, out of context
        return _hook != IntPtr.Zero;
    }
    public static void Stop() { if (_hook != IntPtr.Zero) { UnhookWinEvent(_hook); _hook = IntPtr.Zero; } }
}
'@
}

# 5.15: parent process of every process in ONE Toolhelp snapshot (~1 ms). The game benchmark measured the
# WMI query used before (Win32_Process.ParentProcessId) at 0.24 s idle and 1.7 s per program under a
# saturating load - so CPU care acted 4-14 s late exactly when it was needed.
if(-not ('YumProcTree' -as [type])){
    Add-Type -TypeDefinition @'
using System; using System.Collections.Generic; using System.Runtime.InteropServices;
public static class YumProcTree {
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    struct PROCESSENTRY32W { public uint dwSize, cntUsage, th32ProcessID; public IntPtr th32DefaultHeapID; public uint th32ModuleID, cntThreads, th32ParentProcessID; public int pcPriClassBase; public uint dwFlags; [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 260)] public string szExeFile; }
    [DllImport("kernel32.dll", SetLastError = true)] static extern IntPtr CreateToolhelp32Snapshot(uint flags, uint pid);
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode)] static extern bool Process32FirstW(IntPtr snap, ref PROCESSENTRY32W e);
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode)] static extern bool Process32NextW(IntPtr snap, ref PROCESSENTRY32W e);
    [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr h);
    // 5.15: CPU time, parent, session and start time of EVERY process in one NtQuerySystemInformation
    // (SystemProcessInformation) call - what Task Manager reads. Opening ~250 processes one by one for
    // TotalProcessorTime took ~0.4 s per check under a saturating load. x64 layout only; returns null otherwise.
    public sealed class Info { public int Parent; public int Session; public double CpuMs; public long CreateTime; public long PrivateBytes; }
    [DllImport("ntdll.dll")] static extern int NtQuerySystemInformation(int cls, IntPtr buf, int len, out int needed);
    public static Dictionary<int,Info> Snapshot() {
        if (IntPtr.Size != 8) return null;
        int len = 1 << 20; IntPtr buf = IntPtr.Zero;
        try {
            for (int tries = 0; tries < 6; tries++) {
                buf = Marshal.AllocHGlobal(len); int need;
                int st = NtQuerySystemInformation(5, buf, len, out need);
                if (st == unchecked((int)0xC0000004)) { Marshal.FreeHGlobal(buf); buf = IntPtr.Zero; len = Math.Max(len * 2, need + 65536); continue; }
                if (st != 0) return null;
                var d = new Dictionary<int,Info>(); int off = 0;
                while (true) {
                    IntPtr e = new IntPtr(buf.ToInt64() + off);
                    int pid = (int)Marshal.ReadIntPtr(e, 0x50).ToInt64();
                    var i = new Info();
                    i.CreateTime = Marshal.ReadInt64(e, 0x20);
                    i.CpuMs = (Marshal.ReadInt64(e, 0x28) + Marshal.ReadInt64(e, 0x30)) / 10000.0;
                    i.Parent = (int)Marshal.ReadIntPtr(e, 0x58).ToInt64();
                    i.Session = Marshal.ReadInt32(e, 0x64);
                    i.PrivateBytes = Marshal.ReadInt64(e, 0xC8);
                    d[pid] = i;
                    int next = Marshal.ReadInt32(e, 0); if (next == 0) break; off += next;
                }
                return d;
            }
            return null;
        } finally { if (buf != IntPtr.Zero) Marshal.FreeHGlobal(buf); }
    }
    public static Dictionary<int,int> Parents() {
        var d = new Dictionary<int,int>();
        IntPtr s = CreateToolhelp32Snapshot(2, 0); // TH32CS_SNAPPROCESS
        if (s == IntPtr.Zero || s == new IntPtr(-1)) return d;
        try { var e = new PROCESSENTRY32W(); e.dwSize = (uint)Marshal.SizeOf(typeof(PROCESSENTRY32W));
              if (Process32FirstW(s, ref e)) { do { d[(int)e.th32ProcessID] = (int)e.th32ParentProcessID; } while (Process32NextW(s, ref e)); } }
        finally { CloseHandle(s); }
        return d;
    }
}
'@
}

function Get-YumCpuProfile {
    # Cached: CPU layout + chassis. Power source is read live in the tick.
    if($null -ne $script:Yum['CpuProfile']){return $script:Yum['CpuProfile']}
    $cores=@();$l3=@();$name='';$laptop=$false
    try{[YumCpuCareNative]::Detect();$cores=@([YumCpuCareNative]::Cores);$l3=@([YumCpuCareNative]::L3)}catch{}
    try{$name=([string](Get-CimInstance Win32_Processor -ErrorAction Stop | Select-Object -First 1).Name).Trim()}catch{}
    try{$laptop=(@(Get-CimInstance Win32_Battery -ErrorAction Stop).Count -gt 0)}catch{}
    $logical=[Environment]::ProcessorCount
    $all=[uint64]0;foreach($c in $cores){$all=$all -bor [uint64]$c.Mask}
    $classes=@($cores | ForEach-Object { [int]$_.EfficiencyClass } | Sort-Object -Unique)
    $hybrid=($classes.Count -gt 1)
    $smt=(@($cores | Where-Object { $_.Smt }).Count -gt 0)
    # Where may a held-back hog run while the foreground gets room? ($hogMask = allowed logical CPUs)
    $hogMask=[uint64]0;$how='';$freeCores=0
    if($cores.Count -ge 4 -and $logical -le 64){
        if($hybrid){
            $low=[int]$classes[0]
            foreach($c in $cores){if([int]$c.EfficiencyClass -eq $low){$hogMask=$hogMask -bor [uint64]$c.Mask}}
            $freeCores=@($cores | Where-Object { [int]$_.EfficiencyClass -ne $low }).Count
            $how='hybrid CPU: hogs go to the efficiency cores, your app keeps the performance cores'
        } elseif($l3.Count -gt 1){
            $keep=@($l3 | Sort-Object @{Expression={[int]$_.SizeKB};Descending=$true},@{Expression={[uint64]$_.Mask}} | Select-Object -First 1)[0]
            $hogMask=[uint64]($all - ($all -band [uint64]$keep.Mask))
            $freeCores=@($cores | Where-Object { ([uint64]$_.Mask -band [uint64]$keep.Mask) -ne 0 }).Count
            $how=('your app keeps one of the {0} core groups to itself' -f $l3.Count)
        } else {
            $half=[math]::Ceiling($cores.Count/2)
            for($i=$half;$i -lt $cores.Count;$i++){$hogMask=$hogMask -bor [uint64]$cores[$i].Mask}
            $freeCores=$half
            $how=('your app keeps {0} whole cores' -f $half)
        }
    }
    $prof=[pscustomobject]@{Name=$name;Laptop=$laptop;Logical=$logical;Cores=$cores.Count;Smt=$smt;Hybrid=$hybrid;L3Groups=$l3.Count;AllMask=$all;HogMask=$hogMask;FreeCores=$freeCores;RoomHow=$how
        Summary=('{0}: {1} cores / {2} threads{3}{4}{5}, {6}' -f $(if($name){$name}else{'CPU'}),$cores.Count,$logical,'',$(if($hybrid){', performance + efficiency cores'}else{''}),'',$(if($laptop){'laptop'}else{'desktop'}))}
    $script:Yum['CpuProfile']=$prof
    return $prof
}

function Get-YumOnBattery {
    try{ Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop; return ([System.Windows.Forms.SystemInformation]::PowerStatus.PowerLineStatus -eq [System.Windows.Forms.PowerLineStatus]::Offline) }catch{ return $false }
}

function Get-YumCpuCareLevel {
    # Gentle = Below Normal only (ProBalance). Balanced = + make room (whole cores) for the app you are
    # using when a hog keeps going. Strong = + Efficiency mode (Idle priority + EcoQoS) + low memory priority,
    # sooner. On a laptop on battery, Strong by default (EcoQoS and less heat matter most there).
    $c=$script:Yum.Config
    $lvl='Balanced';try{if($c.Contains('CpuCareLevel') -and $c['CpuCareLevel']){$lvl=[string]$c['CpuCareLevel']}}catch{}
    if($lvl -notin @('Gentle','Balanced','Strong')){$lvl='Balanced'}
    $auto=$true;try{if($c.Contains('CpuCareStrongOnBattery')){$auto=[bool]$c['CpuCareStrongOnBattery']}}catch{}
    if($auto -and $lvl -ne 'Strong' -and (Get-YumOnBattery)){return 'Strong'}
    return $lvl
}

function Get-YumCpuBalanceSettings {
    $c=$script:Yum.Config
    $get={param($n,$d) try{ if($c.Contains($n) -and $null -ne $c[$n]){ return $c[$n] } }catch{}; return $d}
    [pscustomobject]@{
        Enabled=[bool](& $get 'CpuBalanceEnabled' $true)
        SystemPercent=[double](& $get 'CpuBalanceSystemPercent' 70)
        ProcessPercent=[double](& $get 'CpuBalanceProcessPercent' 10)
        HotSeconds=[int](& $get 'CpuBalanceHotSeconds' 2)
        CalmSeconds=[int](& $get 'CpuBalanceCalmSeconds' 3)
        RestorePercent=[double](& $get 'CpuBalanceRestorePercent' 4)
        MaxRestrained=[int](& $get 'CpuBalanceMaxRestrained' 5)
        Exclusions=@(& $get 'CpuBalanceExclusions' @()) | ForEach-Object { ([string]$_ -replace '\.exe$','').Trim().ToLowerInvariant() } | Where-Object { $_ }
    }
}

function Test-YumCpuBalanceEligible {
    # Pure policy check (unit-tested). $P: Name, Id, SessionId, Priority, Path.
    param($P,[int]$ForegroundPid,[string]$ForegroundName,[int]$GamePid,$Settings)
    $n=([string]$P.Name).ToLowerInvariant()
    if([int]$P.Id -le 4 -or [int]$P.Id -eq $PID -or [int]$P.Id -eq $ForegroundPid -or ($GamePid -gt 0 -and [int]$P.Id -eq $GamePid)){return 'protected-id'}
    if($ForegroundName -and $n -eq $ForegroundName.ToLowerInvariant()){return 'same app as foreground'}
    if([int]$P.SessionId -eq 0){return 'service'}
    if([string]$P.Priority -ne 'Normal'){return 'own priority'}
    if($script:YumCpuBalanceCoreNames -contains $n){return 'windows core'}
    if(@($Settings.Exclusions) -contains $n){return 'excluded'}
    # The trim-protection list also names powershell/pwsh only because YUMRAM itself runs in PowerShell;
    # YUMRAM is already excluded by PID here, and a PowerShell script can be a real CPU hog.
    try{ $prot=@($script:Yum.Config.ProtectedProcesses | ForEach-Object {([string]$_ -replace '\.exe$','').ToLowerInvariant()} | Where-Object { $_ -notin @('powershell','pwsh') }); if($prot -contains $n){return 'protected'} }catch{}
    # Note: no blanket "anything under C:\Windows" rule. Measured: a CPU hog run by powershell.exe (which
    # lives in C:\Windows) was skipped, and Windows' own user-session hogs are exactly what should yield.
    # Core Windows processes are named above; services are excluded by session 0.
    return ''
}

function Get-YumCpuBalanceState {
    if($null -eq $script:Yum['CpuBalance']){
        $script:Yum['CpuBalance']=[hashtable]::Synchronized(@{Restrained=[hashtable]::Synchronized(@{});Last=@{};Hot=@{};Calm=@{};LastTick=$null;SystemPercent=0.0;Day=(Get-Date).ToString('yyyy-MM-dd');TodayCount=0;LastAction='';TickMs=0.0;Active=$false})
    }
    return $script:Yum['CpuBalance']
}

function Get-YumCpuBalanceStatePath { return (Join-Path ([string]$script:Yum.ConfigDirectory) 'cpu-balance.json') }

function Get-YumRecordValue {
    # Records are hashtables (live) or objects (from the saved file, maybe an older format); strict mode
    # throws on a missing field, so read fields through here.
    param($Record,[string]$Name,$Default=$null)
    if($null -eq $Record){return $Default}
    if($Record -is [System.Collections.IDictionary]){ if($Record.Contains($Name) -and $null -ne $Record[$Name]){return $Record[$Name]}; return $Default }
    $prop=$Record.PSObject.Properties[$Name]; if($null -ne $prop -and $null -ne $prop.Value){return $prop.Value}; return $Default
}

function Save-YumCpuBalanceRestrained {
    try{
        $st=Get-YumCpuBalanceState
        $rows=@($st.Restrained.Values | ForEach-Object { [pscustomobject]@{Id=(Get-YumRecordValue $_ 'Id' 0);Name=(Get-YumRecordValue $_ 'Name' '');StartTicks=(Get-YumRecordValue $_ 'StartTicks' 0);AppliedPriority=[string](Get-YumRecordValue $_ 'AppliedPriority' 'BelowNormal');RoomMask=[uint64](Get-YumRecordValue $_ 'RoomMask' 0);OriginalAffinity=[uint64](Get-YumRecordValue $_ 'OriginalAffinity' 0);Eco=[bool](Get-YumRecordValue $_ 'Eco' $false);Mem=[bool](Get-YumRecordValue $_ 'Mem' $false)} })
        ConvertTo-Json -InputObject @($rows) -Depth 3 | Set-Content -LiteralPath (Get-YumCpuBalanceStatePath) -Encoding UTF8
    }catch{}
}

function Restore-YumCpuBalanceProcess {
    param($Record,[string]$Why)
    $st=Get-YumCpuBalanceState
    try{
        $p=Get-Process -Id ([int]$Record.Id) -ErrorAction Stop
        $ticks=0L;try{$ticks=$p.StartTime.Ticks}catch{}
        # Only undo our own changes, on the same process instance, and only where nobody changed them since.
        if($Record.StartTicks -eq 0 -or $ticks -eq $Record.StartTicks){
            $applied=[string](Get-YumRecordValue $Record 'AppliedPriority' 'BelowNormal')
            $undone=New-Object System.Collections.Generic.List[string]
            if([string]$p.PriorityClass -eq $applied){$p.PriorityClass=[System.Diagnostics.ProcessPriorityClass]::Normal;$undone.Add('priority')}
            $roomMask=[uint64](Get-YumRecordValue $Record 'RoomMask' 0)
            if($roomMask -ne 0){ try{ if([uint64][int64]$p.ProcessorAffinity -eq $roomMask){$p.ProcessorAffinity=[IntPtr][int64](Get-YumRecordValue $Record 'OriginalAffinity' 0);$undone.Add('all cores')} }catch{} }
            if([bool](Get-YumRecordValue $Record 'Eco' $false)){ try{ if([YumCpuCareNative]::EcoQoS([int]$Record.Id,$false)){$undone.Add('EcoQoS off')} }catch{} }
            if([bool](Get-YumRecordValue $Record 'Mem' $false)){ try{ if([YumCpuCareNative]::MemoryPriority([int]$Record.Id,5)){$undone.Add('memory priority')} }catch{} }
            if($undone.Count -gt 0){try{Write-YumLog ('CPU care: restored {0} (PID {1}): {2} - {3}.' -f $Record.Name,$Record.Id,($undone -join ', '),$Why)}catch{}}
        }
    }catch{}
    [void]$st.Restrained.Remove([int]$Record.Id)
    Save-YumCpuBalanceRestrained
}

function Restore-YumCpuBalanceAll {
    param([string]$Why='CPU balance stopped')
    $st=Get-YumCpuBalanceState
    foreach($r in @($st.Restrained.Values)){ Restore-YumCpuBalanceProcess -Record $r -Why $Why }
    $st.Active=$false
}

function Restore-YumCpuBalanceInterrupted {
    # After a crash: put back anything a previous YUMRAM run left at Below Normal.
    try{
        $path=Get-YumCpuBalanceStatePath
        if(-not (Test-Path -LiteralPath $path)){return}
        # PS 5.1: ConvertFrom-Json emits a JSON array as ONE object; assign first, then enumerate.
        $parsed=Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
        foreach($r in @($parsed)){ if($null -ne $r -and $null -ne $r.PSObject.Properties['Id']){
            $g={param($n,$d) if($null -ne $r.PSObject.Properties[$n]){$r.$n}else{$d}}
            Restore-YumCpuBalanceProcess -Record ([pscustomobject]@{Id=[int]$r.Id;Name=[string]$r.Name;StartTicks=[int64]$r.StartTicks;AppliedPriority=[string](& $g 'AppliedPriority' 'BelowNormal');RoomMask=[uint64](& $g 'RoomMask' 0);OriginalAffinity=[uint64](& $g 'OriginalAffinity' 0);Eco=[bool](& $g 'Eco' $false);Mem=[bool](& $g 'Mem' $false)}) -Why 'left over from the previous YUMRAM run' } }
        Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
    }catch{}
}

function Get-YumCpuKnowledgePath { return (Join-Path ([string]$script:Yum.ConfigDirectory) 'cpu-knowledge.json') }

function Get-YumCpuKnowledge {
    # This PC's game benchmark results (Tools\Bench-CpuCare.ps1). Cached; re-read when the file changes.
    try{
        $p=Get-YumCpuKnowledgePath
        if(-not (Test-Path -LiteralPath $p)){ $script:Yum['CpuKnowledge']=$null; return $null }
        $stamp=(Get-Item -LiteralPath $p).LastWriteTimeUtc.Ticks
        $c=$script:Yum['CpuKnowledge']
        if($null -ne $c -and [int64]$c.Stamp -eq [int64]$stamp){ return $c.Data }
        $d=Get-Content -LiteralPath $p -Raw | ConvertFrom-Json   # PS 5.1: assign first
        $script:Yum['CpuKnowledge']=@{Stamp=$stamp;Data=$d}
        return $d
    }catch{ return $null }
}

function Get-YumCpuKnowledgeSummary {
    # One sentence for Settings > CPU.
    $k=Get-YumCpuKnowledge
    if($null -eq $k -or @($k.Knowledge).Count -eq 0){ return 'Not measured on this PC yet. "Measure games" runs YUMRAM''s own test game next to test background loads with each CPU care level and remembers which works best here. Until then, your chosen level is always used.' }
    $learned=@($k.Knowledge | Where-Object { $null -ne $_ -and $null -ne $_.PSObject.Properties['Low1ByLevel'] } | ForEach-Object {
        # Review fix: say what CPU care will really do (same rule as Get-YumGamingAdvice), not just the top number.
        $e=$_;$cur='Balanced';try{$cur=Get-YumCpuCareLevel}catch{}
        $a=Get-YumGamingAdvice -Knowledge ([pscustomobject]@{Knowledge=@($e)}) -CurrentLevel $cur -GameAloneShare 0 -OtherShare $(if([string]$e.Hog -eq 'Saturating'){70}else{30})
        '{0} game + {1} load: {2}' -f ([string]$e.GameKey).ToLower(),([string]$e.Hog).ToLower(),$(if($null -ne $a){'uses '+$a.Level}else{'keeps '+$cur+' (no clear winner)'}) })
    $when='';try{$when=([datetime]$k.Created).ToString('d MMM yyyy')}catch{}
    return ('Measured {0} ({1} situations). While you play - {2}.' -f $when,$learned.Count,($learned -join '; '))
}

function Start-YumCpuBenchmark {
    # Settings > CPU > Measure games. Runs Tools\Bench-CpuCare.ps1 in its own window; CPU care pauses meanwhile
    # (it would otherwise hold back the benchmark's own test load and spoil the measurement).
    $bench=Join-Path ([string]$script:Yum.Root) 'Tools\Bench-CpuCare.ps1'
    if(-not (Test-Path -LiteralPath $bench)){ return [pscustomobject]@{Success=$false;Reason='The game benchmark is not part of this copy of YUMRAM.'} }
    try{ $old=[int]$script:Yum['CpuBenchPid']; $oldOk=$false; if($old -gt 0){ try{ $oldOk=([int64](Get-Process -Id $old -ErrorAction Stop).StartTime.ToUniversalTime().Ticks -eq [int64]$script:Yum['CpuBenchStart']) }catch{} }; if($oldOk){ return [pscustomobject]@{Success=$false;Reason='The game benchmark is already running in its own window.'} } }catch{}
    $msg=('Measure games on this PC?{0}{0}For about 15 minutes YUMRAM runs its own test game next to test background loads, with CPU care off, Gentle, Balanced and Strong, and records frame rates. Your programs are not touched, but the PC will be fully busy: close games and heavy apps, and keep a laptop plugged in.{0}{0}CPU care pauses until it is done. The result is used only while you play, and only when one level was clearly better.' -f [Environment]::NewLine)
    $r=[System.Windows.MessageBox]::Show($script:Yum.Window,$msg,'YUMRAM - Measure games',[System.Windows.MessageBoxButton]::YesNo,[System.Windows.MessageBoxImage]::Question)
    if($r -ne [System.Windows.MessageBoxResult]::Yes){ return $null }
    $dir=[string]$script:Yum.ConfigDirectory
    $ps=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $args2=@('-NoProfile','-ExecutionPolicy','Bypass','-STA','-File',('"{0}"' -f $bench),'-OutDir',('"{0}"' -f (Join-Path $dir 'cpu-bench')),'-KnowledgeDir',('"{0}"' -f $dir),'-Profile','User','-Repeat','2')
    $p=Start-Process -FilePath $ps -ArgumentList $args2 -PassThru
    $script:Yum['CpuBenchPid']=$p.Id; try{ $script:Yum['CpuBenchStart']=[int64]$p.StartTime.ToUniversalTime().Ticks }catch{ $script:Yum['CpuBenchStart']=[int64]0 }
    try{ Restore-YumCpuBalanceAll -Why 'game benchmark started' }catch{}
    try{Write-YumLog ('CPU care: game benchmark started (PID {0}); CPU care paused until it finishes.' -f $p.Id)}catch{}
    return [pscustomobject]@{Success=$true;Reason='Measuring games in its own window (about 15 minutes). CPU care is paused until it finishes.'}
}

function Get-YumGamingAdvice {
    # Pure decision (unit-tested). Returns @{Level;Reason} when the benchmark on this PC showed another level
    # clearly better (mean 1 % low >= 5 % higher) than the configured one for this kind of game and load;
    # $null otherwise. Never returns 'Off'.
    param($Knowledge,[string]$CurrentLevel,[double]$GameAloneShare,[double]$OtherShare)
    if($null -eq $Knowledge){return $null}
    $entries=@($Knowledge.Knowledge | Where-Object { $null -ne $_ -and $null -ne $_.PSObject.Properties['Low1ByLevel'] })
    if($entries.Count -eq 0){return $null}
    $gc=if($GameAloneShare -le 0){''}elseif($GameAloneShare -lt 30){'Light'}elseif($GameAloneShare -lt 60){'Medium'}else{'Heavy'}
    $hk=if($OtherShare -ge 45){'Saturating'}else{'Half'}
    $pick=@($entries | Where-Object { [string]$_.Hog -eq $hk -and ($gc -eq '' -or [string]$_.GameClass -eq $gc) })
    if($pick.Count -eq 0 -and $hk -eq 'Half'){ $pick=@($entries | Where-Object { [string]$_.Hog -eq 'Bursty' -and ($gc -eq '' -or [string]$_.GameClass -eq $gc) }) }
    if($pick.Count -eq 0){ $pick=@($entries | Where-Object { [string]$_.Hog -eq $hk }) }
    if($pick.Count -eq 0){return $null}
    $best='';$bestRatio=0.0
    foreach($lv in 'Gentle','Balanced','Strong'){
        $ratios=@(); foreach($e in $pick){ $cur=[double]$e.Low1ByLevel.$CurrentLevel; $v=[double]$e.Low1ByLevel.$lv; if($cur -gt 0 -and $v -gt 0){$ratios+=($v/$cur)} }
        if($ratios.Count -eq 0){continue}
        $m=($ratios | Measure-Object -Average).Average
        if($m -gt $bestRatio){$bestRatio=$m;$best=$lv}
    }
    # 10 % on medians of repeated runs, and not worse on average FPS (benchmark: single runs swing far more than 5 %).
    if(-not $best -or $best -eq $CurrentLevel -or $bestRatio -lt 1.10){return $null}
    try{ $avgR=@(); foreach($e in $pick){ if($null -ne $e.PSObject.Properties['AvgByLevel'] -and $null -ne $e.AvgByLevel){ $c=[double]$e.AvgByLevel.$CurrentLevel; $v=[double]$e.AvgByLevel.$best; if($c -gt 0 -and $v -gt 0){$avgR+=($v/$c)} } }; if($avgR.Count -and (($avgR | Measure-Object -Average).Average) -lt 0.95){return $null} }catch{}
    $src='measured on this PC'
    try{ if([string]$Knowledge.Source -eq 'community'){ $src=('shared by {0} people with {1}' -f [int]$Knowledge.Contributors,[string]$Knowledge.How) } }catch{}
    return [pscustomobject]@{Level=$best;Reason=($src+': with a {0}game and a {1} background load, {2} gave {3:N0} % better 1 % lows than {4}, so {2} is used while you play.' -f $(if($gc){$gc.ToLower()+' '}else{''}),$(if($hk -eq 'Saturating'){'heavy'}else{'partial'}),$best,(($bestRatio-1)*100),$CurrentLevel)}
}

function Invoke-YumCpuBalanceTick {
    $st=Get-YumCpuBalanceState
    $cfg=Get-YumCpuBalanceSettings
    # 5.15: paused while the game benchmark (Settings > CPU) runs, so it can measure every level cleanly.
    # Checked before the "CPU care off" return so the end is always noticed; the start time guards against
    # Windows reusing the benchmark's PID for another program afterwards (review finding).
    try{
        $bp=[int]$script:Yum['CpuBenchPid']
        if($bp -gt 0){
            $alive=$false; try{ $bpr=Get-Process -Id $bp -ErrorAction Stop; $alive=([int64]$bpr.StartTime.ToUniversalTime().Ticks -eq [int64]$script:Yum['CpuBenchStart']) }catch{}
            if($alive){ if($st.Restrained.Count -gt 0){Restore-YumCpuBalanceAll -Why 'game benchmark running'}; $st.Active=$false; $st.LastAction='paused while the game benchmark runs'; return }
            $script:Yum['CpuBenchPid']=0; $script:Yum['CpuKnowledge']=$null; try{Write-YumLog 'CPU care: game benchmark finished; CPU care resumed with what it learned.'}catch{}; $script:Yum['CommunityPromptPending']=$true
        }
    }catch{}
    if(-not $cfg.Enabled){ if($st.Restrained.Count -gt 0){Restore-YumCpuBalanceAll -Why 'CPU balance turned off'}; $st.Active=$false; return }
    $sw=[Diagnostics.Stopwatch]::StartNew()
    # Level is re-read every few seconds (power source can change: laptop unplugged = Strong).
    if($null -eq $st['LevelAt'] -or ([datetime]::UtcNow-[datetime]$st['LevelAt']).TotalSeconds -ge 5){$st['Level']=Get-YumCpuCareLevel;$st['LevelAt']=[datetime]::UtcNow}
    $level=[string]$st['Level']
    $now=[datetime]::UtcNow
    $elapsedMs=if($null -eq $st.LastTick){0.0}else{($now-[datetime]$st.LastTick).TotalMilliseconds}
    if($elapsedMs -gt 0 -and $elapsedMs -lt 500){
        # Woken early by an app switch: only give the app you switched to its priority back (CPU % over a
        # few milliseconds would be noise, so nothing else is decided here).
        $fgNow=0;try{$fgNow=Get-YumForegroundProcessId}catch{}
        if($fgNow -gt 0){
            $fgNowName='';try{$fgNowName=[string](Get-Process -Id $fgNow -ErrorAction Stop).ProcessName}catch{}
            foreach($r in @($st.Restrained.Values)){ if([int]$r.Id -eq $fgNow -or ($fgNowName -and [string]$r.Name -ieq $fgNowName)){Restore-YumCpuBalanceProcess -Record $r -Why 'you switched to it'} }
        }
        return
    }
    $st.LastTick=$now
    $cores=[math]::Max(1,[Environment]::ProcessorCount)
    $fgPid=0;try{$fgPid=Get-YumForegroundProcessId}catch{}
    try{ if([int]$script:Yum['CpuCareForegroundOverride'] -gt 0){$fgPid=[int]$script:Yum['CpuCareForegroundOverride']} }catch{}   # measurement tests only
    $gamePid=0;try{$snap=Get-YumSnapshotCopy;if($snap -and $snap.Game -and $snap.Game.Detected){$gamePid=[int]$snap.Game.ProcessId}}catch{}
    try{ if([int]$script:Yum['CpuCareGameOverride'] -gt 0){$gamePid=[int]$script:Yum['CpuCareGameOverride']} }catch{}             # measurement tests only
    $usage=@{};$byId=@{};$total=0.0;$newLast=@{}
    $snapAll=$null;try{$snapAll=[YumProcTree]::Snapshot()}catch{}   # 5.15: one call (~4 ms) instead of one per process
    $st['Snapshot']=$snapAll
    foreach($p in @(Get-Process -ErrorAction SilentlyContinue)){
        # PID 0 is the System Idle Process: its "CPU time" is idle time. The per-process read used before could
        # not open it, but the snapshot returns it - counting it made an idle PC look ~100 % busy (5.15 fix).
        if([int]$p.Id -eq 0){continue}
        $ms=$null
        if($null -ne $snapAll -and $snapAll.ContainsKey([int]$p.Id)){ $ms=[double]$snapAll[[int]$p.Id].CpuMs }
        else{ try{$ms=$p.TotalProcessorTime.TotalMilliseconds}catch{continue} }
        $id=[int]$p.Id;$newLast[$id]=$ms;$byId[$id]=$p
        if($elapsedMs -gt 0 -and $st.Last.ContainsKey($id)){
            $pct=[math]::Max(0.0,($ms-[double]$st.Last[$id])/($elapsedMs*$cores)*100.0)
            $usage[$id]=$pct;$total+=$pct
        }
    }
    $st.Last=$newLast
    if($elapsedMs -le 0){ try{ Update-YumLeakWatch -ById $byId -State $st }catch{}; return }
    $total=[math]::Min(100.0,$total);$st.SystemPercent=$total
    $st['Usage']=$usage;$st['UsageAt']=[datetime]::UtcNow   # shared with RAM care's candidate scoring (Get-YumProcessCpuMap)
    $fgName='';if($fgPid -gt 0 -and $byId.ContainsKey($fgPid)){$fgName=[string]$byId[$fgPid].ProcessName}

    # 5.15: adaptive level while gaming, from this PC's own game benchmark (Tools\Bench-CpuCare.ps1 ->
    # cpu-knowledge.json). Only while a detected game is in front, only when the benchmark showed the other
    # level clearly better (>= 10 % higher median 1 % lows, not lower average FPS) for this kind of game and background load. No file = no change.
    $effLevel=$level
    $gamingNow=($gamePid -gt 0 -and ($fgPid -eq $gamePid -or ($fgName -and $byId.ContainsKey($gamePid) -and [string]$byId[$gamePid].ProcessName -ieq $fgName)))
    if($gamingNow){
        $gName=[string]$byId[$gamePid].ProcessName
        $gUse=0.0;foreach($k in $usage.Keys){if($byId.ContainsKey($k) -and [string]$byId[$k].ProcessName -ieq $gName){$gUse+=[double]$usage[$k]}}
        if($null -eq $st['GameAlone']){$st['GameAlone']=@{}}
        if($total -lt $cfg.SystemPercent){ $old=[double]$st['GameAlone'][$gName]; $st['GameAlone'][$gName]=$(if($old -gt 0){0.7*$old+0.3*$gUse}else{$gUse}) }   # how much CPU the game uses on its own
        $adaptive=$true;try{if($script:Yum.Config.Contains('CpuCareAdaptive')){$adaptive=[bool]$script:Yum.Config['CpuCareAdaptive']}}catch{}
        if($adaptive){
            $kn=Get-YumCpuKnowledge
            if($null -eq $kn){ try{ $cc=$script:Yum['CommunityKnowledge']; if($null -eq $cc -or ([datetime]::UtcNow-[datetime]$cc.At).TotalMinutes -ge 10){ $cc=@{At=[datetime]::UtcNow;Data=(Get-YumCommunityKnowledgeForThisPc)}; $script:Yum['CommunityKnowledge']=$cc }; $kn=$cc.Data }catch{} }
            $adv=Get-YumGamingAdvice -Knowledge $kn -CurrentLevel $level -GameAloneShare ([double]$st['GameAlone'][$gName]) -OtherShare ([math]::Max(0.0,$total-$gUse))
            if($null -ne $adv){
                $effLevel=[string]$adv.Level
                if([string]$st['AdviceNote'] -ne [string]$adv.Reason){ $st['AdviceNote']=[string]$adv.Reason; try{Write-YumLog ('CPU care (learned): {0}' -f $adv.Reason)}catch{} }
            }
        }
        # Learned "Strong is better here": upgrade programs already held back at Below Normal.
        if($effLevel -eq 'Strong' -and $level -ne 'Strong'){
            foreach($r in @($st.Restrained.Values)){
                if([string]$r.AppliedPriority -ne 'BelowNormal' -or -not $byId.ContainsKey([int]$r.Id)){continue}
                try{ $p=$byId[[int]$r.Id]; if([string]$p.PriorityClass -ne 'BelowNormal'){continue}; $p.PriorityClass=[System.Diagnostics.ProcessPriorityClass]::Idle; $r.AppliedPriority='Idle'; try{$r.Eco=[YumCpuCareNative]::EcoQoS([int]$r.Id,$true)}catch{}; try{$r.Mem=[YumCpuCareNative]::MemoryPriority([int]$r.Id,2)}catch{}; Save-YumCpuBalanceRestrained }catch{}
            }
        }
    }
    $st['EffectiveLevel']=$effLevel
    # 5.15.2: while a detected game is in front, the PC counts as busy from 50 % (or the user's lower setting).
    # Focused re-test (7 passes, heavy test game vs a saturating load): in every run where CPU care did nothing
    # (game at ~8 FPS instead of 90-113), the whole PC measured 50-55 % - just under the 70 % trigger - while
    # the game was starved to 6 % CPU. YUMRAM's reading itself matched Windows' counters.
    $busyAt=if($gamingNow){[math]::Min([double]$cfg.SystemPercent,50.0)}else{[double]$cfg.SystemPercent}
    $st['BusyAt']=$busyAt

    # 1) Restore: exited, now foreground/same app, calm, or the PC is no longer busy.
    foreach($r in @($st.Restrained.Values)){
        $id=[int]$r.Id
        if(-not $byId.ContainsKey($id)){[void]$st.Restrained.Remove($id);Save-YumCpuBalanceRestrained;continue}
        $pct=if($usage.ContainsKey($id)){[double]$usage[$id]}else{0.0}
        $r.LastPercent=$pct
        if($id -eq $fgPid -or ($fgName -and [string]$r.Name -ieq $fgName)){Restore-YumCpuBalanceProcess -Record $r -Why 'you switched to it';continue}
        # Measured flip-flop: once room is made the hog itself keeps the PC near 50 %, so "PC calm" fired,
        # the hog was restored, took everything again and was restrained again. With room made, only the
        # hog quieting down counts as calm.
        $pcCalm=($total -lt ($busyAt-20)) -and ([uint64]$r.RoomMask -eq 0)
        if($pct -lt $cfg.RestorePercent -or $pcCalm){ $r.CalmTicks=[int]$r.CalmTicks+1 } else { $r.CalmTicks=0 }
        if([int]$r.CalmTicks -ge $cfg.CalmSeconds){Restore-YumCpuBalanceProcess -Record $r -Why ('calm again ({0:N0}% CPU, PC at {1:N0}%)' -f $pct,$total)}
    }

    # 2) Restrain: background hogs while the PC is busy.
    $hot=@{}
    if($total -ge $busyAt){
        foreach($id in @($usage.Keys)){
            if([double]$usage[$id] -lt $cfg.ProcessPercent -or $st.Restrained.ContainsKey($id)){continue}
            $hot[$id]=[int]$st.Hot[$id]+1
        }
    }
    $st.Hot=$hot
    $parents=$null   # filled once, only if a candidate needs it
    foreach($id in @($hot.Keys | Sort-Object { -[double]$usage[$_] })){
        if($st.Restrained.Count -ge $cfg.MaxRestrained){break}
        if([int]$hot[$id] -lt $cfg.HotSeconds){continue}
        $p=$byId[$id]
        $prio='';try{$prio=[string]$p.PriorityClass}catch{continue}   # access denied -> not ours to change
        $path='';try{$path=[string]$p.Path}catch{}
        $sess=0;try{$sess=[int]$p.SessionId}catch{}
        $why=Test-YumCpuBalanceEligible -P ([pscustomobject]@{Name=$p.ProcessName;Id=$id;SessionId=$sess;Priority=$prio;Path=$path}) -ForegroundPid $fgPid -ForegroundName $fgName -GamePid $gamePid -Settings $cfg
        if($why){continue}
        # Children of the foreground app (e.g. a game's helper) are part of what you are using.
        if($null -eq $parents){ $parents=@{}; try{ if($null -ne $snapAll){ foreach($kv in $snapAll.GetEnumerator()){ $parents[[int]$kv.Key]=[int]$kv.Value.Parent } } else { $parents=[YumProcTree]::Parents() } }catch{} }
        try{ if($fgPid -gt 0 -and $parents.ContainsKey($id) -and [int]$parents[$id] -eq $fgPid){continue} }catch{}
        try{
            # Strong = Task Manager's Efficiency mode (Idle priority + EcoQoS) + low memory priority, so
            # Windows also drops this program's cached pages before yours. Gentle/Balanced = Below Normal.
            $strong=($effLevel -eq 'Strong')
            $p.PriorityClass=if($strong){[System.Diagnostics.ProcessPriorityClass]::Idle}else{[System.Diagnostics.ProcessPriorityClass]::BelowNormal}
            $eco=$false;$mem=$false
            $useEco=$true;try{if($script:Yum.Config.Contains('CpuCareUseEcoQoS')){$useEco=[bool]$script:Yum.Config['CpuCareUseEcoQoS']}}catch{}
            if($strong){ if($useEco){try{$eco=[YumCpuCareNative]::EcoQoS($id,$true)}catch{}}; try{$mem=[YumCpuCareNative]::MemoryPriority($id,2)}catch{} }
            $ticks=0L;try{$ticks=$p.StartTime.Ticks}catch{}
            $st.Restrained[$id]=@{Id=$id;Name=[string]$p.ProcessName;Since=Get-Date;StartTicks=$ticks;LastPercent=[double]$usage[$id];CalmTicks=0;AppliedPriority=$(if($strong){'Idle'}else{'BelowNormal'});RoomMask=[uint64]0;OriginalAffinity=[uint64]0;Eco=$eco;Mem=$mem;Room=$false;RoomFailed=$false;RoomChecked=$false;RoomTicks=0;FgBefore=0.0}
            $today=(Get-Date).ToString('yyyy-MM-dd');if($st.Day -ne $today){$st.Day=$today;$st.TodayCount=0}
            $st.TodayCount=[int]$st.TodayCount+1
            $st.LastAction=('{0:T}  held back {1} ({2:N0}% of the CPU while the PC was at {3:N0}%)' -f (Get-Date),$p.ProcessName,[double]$usage[$id],$total)
            try{Write-YumLog ('CPU care ({0}): lowered {1} (PID {2}) to {3}{4} - it used {5:N0}% of all cores while the PC was at {6:N0}%.' -f $level,$p.ProcessName,$id,$(if($strong){'Idle (Efficiency mode)'}else{'Below Normal'}),$(if($eco){' + EcoQoS'}else{''}),[double]$usage[$id],$total)}catch{}
            Save-YumCpuBalanceRestrained
        }catch{}
    }

    # 3) Make room (Balanced/Strong): a hog that keeps going while you are actively using an app is kept
    #    off whole cores (see Get-YumCpuProfile) so your app gets full cores, not shared SMT threads.
    $prof=Get-YumCpuProfile
    # Gaming: you are playing (detected game is in front) -> make room after 1 s at 70 % PC load. Players and
    # Bitsum users report background work moved off the game's cores keeps 1% lows higher. The game itself
    # is never touched (anti-cheat blocks opening it anyway).
    $gaming=($gamePid -gt 0 -and ($fgPid -eq $gamePid -or ($fgName -and $byId.ContainsKey($gamePid) -and [string]$byId[$gamePid].ProcessName -ieq $fgName)))
    $st['Gaming']=$gaming
        $fgBusy=0.0;if($fgName){foreach($k in $usage.Keys){if($byId.ContainsKey($k) -and [string]$byId[$k].ProcessName -ieq $fgName){$fgBusy+=[double]$usage[$k]}}}
        # Self-check (measured: making room helped a 4-thread app every time, but an 8-thread game simulation
        # only half the time - otherwise it fell from ~135 to ~80 FPS). After making room, compare how much
        # CPU your app actually gets; if it got less, undo the room for that program at once.
        $hist=@($st['FgHist']);$hist+=$fgBusy;if($hist.Count -gt 6){$hist=$hist[($hist.Count-6)..($hist.Count-1)]};$st['FgHist']=$hist
        foreach($r in @($st.Restrained.Values)){
            if([uint64]$r.RoomMask -eq 0 -or [bool]$r.RoomChecked){continue}
            $r.RoomTicks=[int]$r.RoomTicks+1
            if([int]$r.RoomTicks -lt 4){continue}
            $afterAvg=(@($hist | Select-Object -Last 3) | Measure-Object -Average).Average
            $r.RoomChecked=$true
            if([double]$r.FgBefore -gt 0 -and [double]$afterAvg -lt ([double]$r.FgBefore*0.9)){
                try{ $p=$byId[[int]$r.Id]; if($null -ne $p -and [uint64][int64]$p.ProcessorAffinity -eq [uint64]$r.RoomMask){$p.ProcessorAffinity=[IntPtr][int64]$r.OriginalAffinity} }catch{}
                $r.RoomMask=[uint64]0;$r.RoomFailed=$true
                $st['RoomUndone']=[int]$st['RoomUndone']+1
                try{Write-YumLog ('CPU care: undid room for {0} - {1} got less CPU with it ({2:N0}% -> {3:N0}%), so priority alone is better here.' -f $r.Name,$fgName,[double]$r.FgBefore,[double]$afterAvg)}catch{}
                Save-YumCpuBalanceRestrained
            } else {
                $st['RoomHelped']=[int]$st['RoomHelped']+1
                try{Write-YumLog ('CPU care: room for {0} kept - {1} gets {2:N0}% CPU (was {3:N0}%).' -f $r.Name,$fgName,[double]$afterAvg,[double]$r.FgBefore)}catch{}
            }
        }
    if($effLevel -ne 'Gentle' -and [uint64]$prof.HogMask -ne 0 -and $total -ge $(if($gaming){$busyAt}else{85})){
        $after=if($gaming){1}elseif($effLevel -eq 'Strong'){3}else{8}
        if($fgBusy -ge 3.0 -or $gaming){
            foreach($r in @($st.Restrained.Values)){
                if([bool]$r.Room -or [bool]$r.RoomFailed -or ((Get-Date)-[datetime]$r.Since).TotalSeconds -lt $after -or [double]$r.LastPercent -lt $cfg.ProcessPercent){continue}
                try{
                    $p=$byId[[int]$r.Id];if($null -eq $p){continue}
                    $cur=[uint64][int64]$p.ProcessorAffinity
                    if($cur -ne [uint64]$prof.AllMask){$r.Room=$true;continue}   # it chose its own cores; leave it
                    $p.ProcessorAffinity=[IntPtr][int64]$prof.HogMask
                    $r.OriginalAffinity=$cur;$r.RoomMask=[uint64]$prof.HogMask;$r.Room=$true;$r.RoomTicks=0;$r.RoomChecked=$false
                    $r.FgBefore=(@(@($st['FgHist']) | Select-Object -Last 3) | Measure-Object -Average).Average
                    $st.LastAction=('{0:T}  made room: {1} kept off {2} cores so {3} runs on whole cores' -f (Get-Date),$r.Name,$prof.FreeCores,$fgName)
                    try{Write-YumLog ('CPU care ({0}): made room - {1} (PID {2}, {3:N0}% CPU) kept on cores 0x{4:X} so {5} ({6:N0}% CPU) has {7} whole cores; {8}.' -f $level,$r.Name,$r.Id,[double]$r.LastPercent,[uint64]$prof.HogMask,$fgName,$fgBusy,$prof.FreeCores,$prof.RoomHow)}catch{}
                    Save-YumCpuBalanceRestrained
                }catch{}
            }
        }
    }
    # 5.9: busiest programs right now (by name, all processes of a program together) for the Overview card.
    try{ $byName=@{}; foreach($id in $usage.Keys){ if($byId.ContainsKey($id)){ $nm=[string]$byId[$id].ProcessName; if($nm -ieq 'Idle'){continue}; $byName[$nm]=[double]$byName[$nm]+[double]$usage[$id] } }; $st.Top=@($byName.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 3 | Where-Object { $_.Value -ge 1.0 } | ForEach-Object { '{0} {1:N0}%' -f $_.Key,$_.Value }) }catch{}
    $st.Active=($st.Restrained.Count -gt 0)
    $st.TickMs=[math]::Round($sw.Elapsed.TotalMilliseconds,1)
    # 5.15: leak sampling (once a minute, ~0.7 s under full load) runs after the decisions, never before them.
    try{ Update-YumLeakWatch -ById $byId -State $st }catch{ try{Write-YumLogException -Context 'Leak watch failed' -Exception $_.Exception}catch{} }
}

$script:YumCpuBalanceWorkerScript = {
    param($Shared,[string]$Root,$StopEvent,[string[]]$Modules)
    $ErrorActionPreference='Continue'
    foreach($relative in $Modules){ . (Join-Path $Root $relative) }
    $script:Yum=$Shared
    # Measured: under a saturating load a Normal-priority tick took 366 ms. One thread a notch higher lets
    # CPU balance react while the PC is saturated (its own work is ~35 ms per second).
    try{ [System.Threading.Thread]::CurrentThread.Priority=[System.Threading.ThreadPriority]::AboveNormal }catch{}
    try{ Write-YumLog 'CPU balance worker started.' }catch{}
    try{ Restore-YumCpuBalanceInterrupted }catch{}
    # 5.15: warm up while the PC is (usually) calm. Measured under a saturating load: the very first check
    # took ~10 s (CPU layout via WMI 6.3 s + first-call compilation of every function); afterwards ~0.1 s.
    try{ $null=Get-YumCpuProfile; $null=Get-YumCpuCareLevel; $null=Get-YumCpuBalanceSettings; $null=[YumProcTree]::Snapshot(); $null=Get-YumForegroundProcessId; Invoke-YumCpuBalanceTick }catch{}
    $handles=[System.Threading.WaitHandle[]]@($StopEvent.WaitHandle,[YumForegroundHook]::Wake)
    # Every second, or at once when you switch apps (foreground hook on the UI thread).
    while([System.Threading.WaitHandle]::WaitAny($handles,1000) -ne 0){
        try{ Invoke-YumCpuBalanceTick }catch{ try{Write-YumLogException -Context 'CPU balance tick failed' -Exception $_.Exception}catch{} }
    }
    try{ Restore-YumCpuBalanceAll -Why 'YUMRAM closed' }catch{}
    try{ Write-YumLog 'CPU balance worker stopped.' }catch{}
}

function Start-YumCpuBalanceWorker {
    if($null -ne $script:Yum['CpuBalancePowerShell']){return}
    [void](Get-YumCpuBalanceState)
    $stop=New-Object System.Threading.ManualResetEventSlim($false)
    $rs=[runspacefactory]::CreateRunspace();$rs.ApartmentState='MTA';$rs.ThreadOptions='ReuseThread';$rs.Open()
    $ps=[powershell]::Create();$ps.Runspace=$rs
    [void]$ps.AddScript($script:YumCpuBalanceWorkerScript.ToString())
    [void]$ps.AddArgument($script:Yum);[void]$ps.AddArgument([string]$script:Yum.Root);[void]$ps.AddArgument($stop)
    [void]$ps.AddArgument([string[]]@('Core\Logging.ps1','Core\Config.ps1','Core\Native.ps1','Core\Telemetry.ps1','Core\CpuBalance.ps1','Core\LeakWatch.ps1','Core\Community.ps1'))
    $script:Yum['CpuBalanceStop']=$stop;$script:Yum['CpuBalanceRunspace']=$rs;$script:Yum['CpuBalancePowerShell']=$ps;$script:Yum['CpuBalanceAsync']=$ps.BeginInvoke()
}

function Stop-YumCpuBalanceWorker {
    $ps=$script:Yum['CpuBalancePowerShell'];if($null -eq $ps){return}
    try{$script:Yum['CpuBalanceStop'].Set()}catch{}
    try{ $a=$script:Yum['CpuBalanceAsync']; if($null -ne $a -and $a.AsyncWaitHandle.WaitOne(5000)){[void]$ps.EndInvoke($a)}else{$ps.Stop()} }catch{}
    try{$ps.Dispose()}catch{};try{$script:Yum['CpuBalanceRunspace'].Dispose()}catch{}
    $script:Yum['CpuBalancePowerShell']=$null;$script:Yum['CpuBalanceAsync']=$null;$script:Yum['CpuBalanceRunspace']=$null;$script:Yum['CpuBalanceStop']=$null
    try{ Restore-YumCpuBalanceAll -Why 'YUMRAM closed' }catch{}
}

function Get-YumCpuBalanceSummary {
    # For the UI: one line + today's count.
    $st=Get-YumCpuBalanceState;$cfg=Get-YumCpuBalanceSettings
    if(-not $cfg.Enabled){return [pscustomobject]@{Text='Off. Busy background programs can make the app you are using stutter.';Count='';Active=$false}}
    $today=(Get-Date).ToString('yyyy-MM-dd');$n=if($st.Day -eq $today){[int]$st.TodayCount}else{0}
    $held=@($st.Restrained.Values)
    $text=if($held.Count -gt 0){'Holding back {0} so what you are using stays smooth.' -f ((@($held | ForEach-Object { '{0} ({1:N0}% CPU{2})' -f $_.Name,[double]$_.LastPercent,$(if([uint64]$_.RoomMask -ne 0){', room made'}elseif([string]$_.AppliedPriority -eq 'Idle'){', efficiency mode'}else{''}) })) -join ', ')}else{'Watching. Nothing is hogging the CPU (PC at {0:N0}%).' -f [double]$st.SystemPercent}
    $top=@();try{$top=@($st['Top'])}catch{}
    if($held.Count -eq 0 -and $top.Count -gt 0){$text='Watching. Busiest now: {0} (PC at {1:N0}%).' -f ($top -join ', '),[double]$st.SystemPercent}
    [pscustomobject]@{Text=$text;Count=$(if($n -eq 1){'1 time today'}else{'{0} times today' -f $n});Active=($held.Count -gt 0)}
}
