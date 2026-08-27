
function Get-YumProcessCpuMap {
    $map=@()
    try{
        $out=@{}
        foreach($perf in @(Get-CimInstance Win32_PerfFormattedData_PerfProc_Process -ErrorAction Stop)){
            $id=0;try{$id=[int]$perf.IDProcess}catch{}
            if($id -gt 0){$out[$id]=[math]::Min(100.0,([double]$perf.PercentProcessorTime/[math]::Max(1,[Environment]::ProcessorCount)))}
        }
        return $out
    }catch{return @{}}
}

#requires -Version 5.1

function Get-YumMemoryTelemetry {
    try {
        $status=New-Object YumRamNative+MEMORYSTATUSEX
        if ([YumRamNative]::GlobalMemoryStatusEx($status)) {
            $total=[double]$status.ullTotalPhys/1GB;$available=[double]$status.ullAvailPhys/1GB;$used=[math]::Max(0,$total-$available);$pct=if($total -gt 0){$used/$total*100}else{0}
            return [pscustomobject]@{TotalBytes=[uint64]$status.ullTotalPhys;AvailableBytes=[uint64]$status.ullAvailPhys;UsedBytes=[uint64]($status.ullTotalPhys-$status.ullAvailPhys);TotalGB=$total;UsedGB=$used;AvailableGB=$available;UsedPercent=$pct}
        }
    } catch { Write-YumLog ("GlobalMemoryStatusEx failed: {0}" -f $_.Exception.Message) }
    try {
        $os=Get-CimInstance Win32_OperatingSystem -ErrorAction Stop;$total=[double]$os.TotalVisibleMemorySize/1MB;$available=[double]$os.FreePhysicalMemory/1MB;$used=[math]::Max(0,$total-$available);$pct=if($total -gt 0){$used/$total*100}else{0}
        return [pscustomobject]@{TotalBytes=[uint64]($os.TotalVisibleMemorySize*1KB);AvailableBytes=[uint64]($os.FreePhysicalMemory*1KB);UsedBytes=[uint64](($os.TotalVisibleMemorySize-$os.FreePhysicalMemory)*1KB);TotalGB=$total;UsedGB=$used;AvailableGB=$available;UsedPercent=$pct}
    } catch { return $null }
}

function Get-YumCPU {
    try {
        if($null -ne $script:Yum.CpuCounter){return [math]::Round([double]$script:Yum.CpuCounter.NextValue(),1)}
        $counter=New-Object System.Diagnostics.PerformanceCounter('Processor','% Processor Time','_Total');[void]$counter.NextValue();$script:Yum.CpuCounter=$counter;Start-Sleep -Milliseconds 900;return [math]::Round([double]$counter.NextValue(),1)
    } catch {
        try {$m=Get-CimInstance Win32_Processor | Measure-Object LoadPercentage -Average;if($null -ne $m.Average){return [math]::Round([double]$m.Average,1)}}catch{}
        return 0.0
    }
}

function Get-YumGpu3D { try {$counter=Get-Counter '\GPU Engine(*)\Utilization Percentage' -ErrorAction Stop;$max=0.0;foreach($sample in $counter.CounterSamples){if(([string]$sample.InstanceName -match 'engtype_3D')){$max=[math]::Max($max,[double]$sample.CookedValue)}};return [math]::Round([math]::Min(100,$max),1)}catch{return 0.0} }

function Update-YumSnapshot {
    param([hashtable]$Changes,[switch]$CoreTelemetry)
    [System.Threading.Monitor]::Enter($script:Yum.CacheLock);try{$current=$script:Yum.Snapshot;$next=[pscustomobject]@{Timestamp=if($current){$current.Timestamp}else{Get-Date};Memory=if($current){$current.Memory}else{$null};CPU=if($current){$current.CPU}else{0.0};GPU3D=if($current){$current.GPU3D}else{0.0};ForegroundProcessId=if($current){$current.ForegroundProcessId}else{0};Game=if($current){$current.Game}else{[pscustomobject]@{ProcessId=0;ProcessName=$null;Detected=$false}}};foreach($k in $Changes.Keys){if($next.PSObject.Properties.Name -contains $k){$next.$k=$Changes[$k]}};$now=Get-Date;if($CoreTelemetry){$next.Timestamp=$now;$script:Yum.LastCoreTelemetryUpdate=$now};$script:Yum.LastTelemetryUpdate=$now;$script:Yum.Snapshot=$next;$script:Yum.SnapshotVersion++;$script:Yum.TelemetryCache['Snapshot']=$next}finally{[System.Threading.Monitor]::Exit($script:Yum.CacheLock)}
}
function Get-YumTelemetrySnapshot { param([switch]$IncludeGpu,[switch]$IncludeGame) $m=Get-YumMemoryTelemetry;if($null -eq $m){throw 'Memory telemetry unavailable'};$c=Get-YumCPU;[pscustomobject]@{Timestamp=Get-Date;Memory=$m;CPU=$c;GPU3D=if($IncludeGpu){Get-YumGpu3D}else{0.0};ForegroundProcessId=(Get-YumForegroundProcessId);Game=if($IncludeGame){Get-YumGameSnapshot}else{[pscustomobject]@{ProcessId=0;ProcessName=$null;Detected=$false}}} }
function Publish-YumSnapshot { param([Parameter(Mandatory)]$Snapshot) Update-YumSnapshot -Changes @{Memory=$Snapshot.Memory;CPU=$Snapshot.CPU;GPU3D=$Snapshot.GPU3D;ForegroundProcessId=$Snapshot.ForegroundProcessId;Game=$Snapshot.Game} -CoreTelemetry }
function Get-YumSnapshotCopy {
    [System.Threading.Monitor]::Enter($script:Yum.CacheLock);try{$s=$script:Yum.TelemetryCache['Snapshot'];if($null -ne $s){$script:Yum.Snapshot=$s;$script:Yum.SnapshotVersion=[int]$script:Yum.TelemetryCache['SnapshotVersion'];$script:Yum.LastCoreTelemetryUpdate=$script:Yum.TelemetryCache['LastCore'];$script:Yum.LastGpuSample=$script:Yum.TelemetryCache['LastGpu'];$script:Yum.LastGameSample=$script:Yum.TelemetryCache['LastGame'];return $s};return $script:Yum.Snapshot}finally{[System.Threading.Monitor]::Exit($script:Yum.CacheLock)}
}

function New-YumTelemetryRunspace {
    param([ValidateSet('Core','Aux')][string]$Mode)
    $runspace=[runspacefactory]::CreateRunspace();$runspace.ApartmentState='MTA';$runspace.ThreadOptions='ReuseThread';$runspace.Open();$ps=[powershell]::Create();$ps.Runspace=$runspace
    $workerPath=Join-Path $script:Yum.Root 'Core\TelemetryWorker.ps1';$workerText=[System.IO.File]::ReadAllText($workerPath,([System.Text.UTF8Encoding]::new($false,$true)))
    [void]$ps.AddScript($workerText);[void]$ps.AddArgument($script:Yum.TelemetryCache);[void]$ps.AddArgument($script:Yum.Config);[void]$ps.AddArgument($script:Yum.TelemetryStopEvent);[void]$ps.AddArgument($Mode)
    return [pscustomobject]@{Runspace=$runspace;PowerShell=$ps;Async=$ps.BeginInvoke()}
}

function Start-YumTelemetry {
    if($null -ne $script:Yum.TelemetryTimer){return}
    $script:Yum.StopRequested=$false;$script:Yum.TelemetryStopEvent=New-Object System.Threading.ManualResetEventSlim($false)
    try {
        $core=New-YumTelemetryRunspace -Mode Core;$aux=New-YumTelemetryRunspace -Mode Aux
        $script:Yum.TelemetryCoreRunspace=$core.Runspace;$script:Yum.TelemetryCorePowerShell=$core.PowerShell;$script:Yum.TelemetryCoreAsync=$core.Async
        $script:Yum.TelemetryAuxRunspace=$aux.Runspace;$script:Yum.TelemetryAuxPowerShell=$aux.PowerShell;$script:Yum.TelemetryAuxAsync=$aux.Async
        $script:Yum.TelemetryTimer=$core.PowerShell;$script:Yum.GpuTimer=$aux.PowerShell
        Write-YumLog 'Telemetry worker runspaces started.'
    } catch { Stop-YumTelemetry;throw }
}

function Stop-YumTelemetry {
    $script:Yum.StopRequested=$true
    if($null -ne $script:Yum.TelemetryStopEvent){try{$script:Yum.TelemetryStopEvent.Set()}catch{}}
    foreach($kind in @('Core','Aux')){
        $ps=$script:Yum.("Telemetry{0}PowerShell" -f $kind);$async=$script:Yum.("Telemetry{0}Async" -f $kind);$rs=$script:Yum.("Telemetry{0}Runspace" -f $kind)
        if($null -ne $ps){try{if($null -ne $async -and $async.IsCompleted){$ps.EndInvoke($async)|Out-Null}else{$ps.Stop()}}catch{};try{$ps.Dispose()}catch{}}
        if($null -ne $rs){try{$rs.Close();$rs.Dispose()}catch{}}
        $script:Yum.("Telemetry{0}PowerShell" -f $kind)=$null;$script:Yum.("Telemetry{0}Async" -f $kind)=$null;$script:Yum.("Telemetry{0}Runspace" -f $kind)=$null
    }
    if($null -ne $script:Yum.TelemetryStopEvent){try{$script:Yum.TelemetryStopEvent.Dispose()}catch{};$script:Yum.TelemetryStopEvent=$null}
    $script:Yum.TelemetryTimer=$null;$script:Yum.GpuTimer=$null;$script:Yum.GameTimer=$null
}

function Start-YumControllerTimer {
    if($null -ne $script:Yum.ControllerTimer){return}
    $timer=New-Object System.Timers.Timer
    $timer.Interval=1000
    $timer.AutoReset=$true
    $timer.Add_Elapsed({ try { Invoke-YumBackgroundController } catch { Write-YumLogException -Context 'Controller timer failed' -Exception $_.Exception } })
    $script:Yum.ControllerTimer=$timer
    $timer.Start()
}
