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
            $how=('{0} core groups with their own cache: your app keeps the {1}largest-cache group' -f $l3.Count,$(if(@($l3|ForEach-Object{$_.SizeKB}|Sort-Object -Unique).Count -gt 1){''}else{'first / '}))
        } else {
            $half=[math]::Ceiling($cores.Count/2)
            for($i=$half;$i -lt $cores.Count;$i++){$hogMask=$hogMask -bor [uint64]$cores[$i].Mask}
            $freeCores=$half
            $how=('your app keeps {0} whole cores' -f $half)
        }
    }
    $prof=[pscustomobject]@{Name=$name;Laptop=$laptop;Logical=$logical;Cores=$cores.Count;Smt=$smt;Hybrid=$hybrid;L3Groups=$l3.Count;AllMask=$all;HogMask=$hogMask;FreeCores=$freeCores;RoomHow=$how
        Summary=('{0}: {1} cores / {2} threads{3}{4}{5}, {6}' -f $(if($name){$name}else{'CPU'}),$cores.Count,$logical,$(if($smt){' (SMT)'}else{''}),$(if($hybrid){', performance + efficiency cores'}else{''}),$(if($l3.Count -gt 1){(', {0} cache groups' -f $l3.Count)}else{''}),$(if($laptop){'laptop'}else{'desktop'}))}
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

function Invoke-YumCpuBalanceTick {
    $st=Get-YumCpuBalanceState
    $cfg=Get-YumCpuBalanceSettings
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
    foreach($p in @(Get-Process -ErrorAction SilentlyContinue)){
        $ms=$null;try{$ms=$p.TotalProcessorTime.TotalMilliseconds}catch{continue}
        $id=[int]$p.Id;$newLast[$id]=$ms;$byId[$id]=$p
        if($elapsedMs -gt 0 -and $st.Last.ContainsKey($id)){
            $pct=[math]::Max(0.0,($ms-[double]$st.Last[$id])/($elapsedMs*$cores)*100.0)
            $usage[$id]=$pct;$total+=$pct
        }
    }
    $st.Last=$newLast
    try{ Update-YumLeakWatch -ById $byId -State $st }catch{ try{Write-YumLogException -Context 'Leak watch failed' -Exception $_.Exception}catch{} }
    if($elapsedMs -le 0){return}
    $total=[math]::Min(100.0,$total);$st.SystemPercent=$total
    $fgName='';if($fgPid -gt 0 -and $byId.ContainsKey($fgPid)){$fgName=[string]$byId[$fgPid].ProcessName}

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
        $pcCalm=($total -lt ($cfg.SystemPercent-20)) -and ([uint64]$r.RoomMask -eq 0)
        if($pct -lt $cfg.RestorePercent -or $pcCalm){ $r.CalmTicks=[int]$r.CalmTicks+1 } else { $r.CalmTicks=0 }
        if([int]$r.CalmTicks -ge $cfg.CalmSeconds){Restore-YumCpuBalanceProcess -Record $r -Why ('calm again ({0:N0}% CPU, PC at {1:N0}%)' -f $pct,$total)}
    }

    # 2) Restrain: background hogs while the PC is busy.
    $hot=@{}
    if($total -ge $cfg.SystemPercent){
        foreach($id in @($usage.Keys)){
            if([double]$usage[$id] -lt $cfg.ProcessPercent -or $st.Restrained.ContainsKey($id)){continue}
            $hot[$id]=[int]$st.Hot[$id]+1
        }
    }
    $st.Hot=$hot
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
        try{ $parent=[int](Get-CimInstance Win32_Process -Filter ("ProcessId={0}" -f $id) -Property ParentProcessId -ErrorAction Stop).ParentProcessId; if($fgPid -gt 0 -and $parent -eq $fgPid){continue} }catch{}
        try{
            # Strong = Task Manager's Efficiency mode (Idle priority + EcoQoS) + low memory priority, so
            # Windows also drops this program's cached pages before yours. Gentle/Balanced = Below Normal.
            $strong=($level -eq 'Strong')
            $p.PriorityClass=if($strong){[System.Diagnostics.ProcessPriorityClass]::Idle}else{[System.Diagnostics.ProcessPriorityClass]::BelowNormal}
            $eco=$false;$mem=$false
            $useEco=$true;try{if($script:Yum.Config.Contains('CpuCareUseEcoQoS')){$useEco=[bool]$script:Yum.Config['CpuCareUseEcoQoS']}}catch{}
            if($strong){ if($useEco){try{$eco=[YumCpuCareNative]::EcoQoS($id,$true)}catch{}}; try{$mem=[YumCpuCareNative]::MemoryPriority($id,2)}catch{} }
            $ticks=0L;try{$ticks=$p.StartTime.Ticks}catch{}
            $st.Restrained[$id]=@{Id=$id;Name=[string]$p.ProcessName;Since=Get-Date;StartTicks=$ticks;LastPercent=[double]$usage[$id];CalmTicks=0;AppliedPriority=$(if($strong){'Idle'}else{'BelowNormal'});RoomMask=[uint64]0;OriginalAffinity=[uint64]0;Eco=$eco;Mem=$mem;Room=$false}
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
    if($level -ne 'Gentle' -and [uint64]$prof.HogMask -ne 0 -and $total -ge $(if($gaming){70}else{85})){
        $after=if($gaming){1}elseif($level -eq 'Strong'){3}else{8}
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
    [void]$ps.AddArgument([string[]]@('Core\Logging.ps1','Core\Config.ps1','Core\Native.ps1','Core\Telemetry.ps1','Core\CpuBalance.ps1','Core\LeakWatch.ps1'))
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
