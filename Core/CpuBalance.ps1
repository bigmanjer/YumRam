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

function Save-YumCpuBalanceRestrained {
    try{
        $st=Get-YumCpuBalanceState
        $rows=@($st.Restrained.Values | ForEach-Object { [pscustomobject]@{Id=$_.Id;Name=$_.Name;StartTicks=$_.StartTicks} })
        ConvertTo-Json -InputObject @($rows) -Depth 3 | Set-Content -LiteralPath (Get-YumCpuBalanceStatePath) -Encoding UTF8
    }catch{}
}

function Restore-YumCpuBalanceProcess {
    param($Record,[string]$Why)
    $st=Get-YumCpuBalanceState
    try{
        $p=Get-Process -Id ([int]$Record.Id) -ErrorAction Stop
        $ticks=0L;try{$ticks=$p.StartTime.Ticks}catch{}
        # Only undo our own change: same process instance, still Below Normal.
        if(($Record.StartTicks -eq 0 -or $ticks -eq $Record.StartTicks) -and $p.PriorityClass -eq [System.Diagnostics.ProcessPriorityClass]::BelowNormal){
            $p.PriorityClass=[System.Diagnostics.ProcessPriorityClass]::Normal
            try{Write-YumLog ('CPU balance: restored {0} (PID {1}) to Normal - {2}.' -f $Record.Name,$Record.Id,$Why)}catch{}
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
        foreach($r in @($parsed)){ if($null -ne $r -and $null -ne $r.PSObject.Properties['Id']){ Restore-YumCpuBalanceProcess -Record ([pscustomobject]@{Id=[int]$r.Id;Name=[string]$r.Name;StartTicks=[int64]$r.StartTicks}) -Why 'left over from the previous YUMRAM run' } }
        Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
    }catch{}
}

function Invoke-YumCpuBalanceTick {
    $st=Get-YumCpuBalanceState
    $cfg=Get-YumCpuBalanceSettings
    if(-not $cfg.Enabled){ if($st.Restrained.Count -gt 0){Restore-YumCpuBalanceAll -Why 'CPU balance turned off'}; $st.Active=$false; return }
    $sw=[Diagnostics.Stopwatch]::StartNew()
    $now=[datetime]::UtcNow
    $elapsedMs=if($null -eq $st.LastTick){0.0}else{($now-[datetime]$st.LastTick).TotalMilliseconds}
    $st.LastTick=$now
    $cores=[math]::Max(1,[Environment]::ProcessorCount)
    $fgPid=0;try{$fgPid=Get-YumForegroundProcessId}catch{}
    $gamePid=0;try{$snap=Get-YumSnapshotCopy;if($snap -and $snap.Game -and $snap.Game.Detected){$gamePid=[int]$snap.Game.ProcessId}}catch{}
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
        if($pct -lt $cfg.RestorePercent -or $total -lt ($cfg.SystemPercent-20)){ $r.CalmTicks=[int]$r.CalmTicks+1 } else { $r.CalmTicks=0 }
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
            $p.PriorityClass=[System.Diagnostics.ProcessPriorityClass]::BelowNormal
            $ticks=0L;try{$ticks=$p.StartTime.Ticks}catch{}
            $st.Restrained[$id]=@{Id=$id;Name=[string]$p.ProcessName;Since=Get-Date;StartTicks=$ticks;LastPercent=[double]$usage[$id];CalmTicks=0}
            $today=(Get-Date).ToString('yyyy-MM-dd');if($st.Day -ne $today){$st.Day=$today;$st.TodayCount=0}
            $st.TodayCount=[int]$st.TodayCount+1
            $st.LastAction=('{0:T}  held back {1} ({2:N0}% of the CPU while the PC was at {3:N0}%)' -f (Get-Date),$p.ProcessName,[double]$usage[$id],$total)
            try{Write-YumLog ('CPU balance: lowered {0} (PID {1}) to Below Normal - it used {2:N0}% of all cores while the PC was at {3:N0}%.' -f $p.ProcessName,$id,[double]$usage[$id],$total)}catch{}
            Save-YumCpuBalanceRestrained
        }catch{}
    }
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
    while(-not $StopEvent.Wait(1000)){
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
    [void]$ps.AddArgument([string[]]@('Core\Logging.ps1','Core\Config.ps1','Core\Native.ps1','Core\Telemetry.ps1','Core\CpuBalance.ps1'))
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
    $text=if($held.Count -gt 0){'Holding back {0} so what you are using stays smooth.' -f ((@($held | ForEach-Object { '{0} ({1:N0}% CPU)' -f $_.Name,[double]$_.LastPercent })) -join ', ')}else{'Watching. Nothing is hogging the CPU (PC at {0:N0}%).' -f [double]$st.SystemPercent}
    [pscustomobject]@{Text=$text;Count=$(if($n -eq 1){'1 time today'}else{'{0} times today' -f $n});Active=($held.Count -gt 0)}
}
