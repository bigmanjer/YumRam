# Optional background reclamation. This module intentionally does NOT disable services.
# Automatic cleanup may stop only explicitly classified optional background processes.
# Services require explicit user configuration and dependency checks.


function Save-YumStoppedServiceState {
    try {
        $payload = @{
            Timestamp = (Get-Date).ToString('o')
            Services = @($script:Yum.StoppedOptionalServices)
        }
        $json = $payload | ConvertTo-Json -Depth 4
        if (-not (Test-Path -LiteralPath $script:Yum.ConfigDirectory)) {
            New-Item -ItemType Directory -Path $script:Yum.ConfigDirectory -Force | Out-Null
        }
        Set-Content -LiteralPath $script:Yum.StateFile -Value $json -Encoding UTF8
    } catch {
        Write-YumLogException 'Stopped-service state save failed' $_.Exception
    }
}

function Restore-YumInterruptedServiceStops {
    try {
        if (-not (Test-Path -LiteralPath $script:Yum.StateFile)) { return }
        $state = Get-Content -LiteralPath $script:Yum.StateFile -Raw | ConvertFrom-Json
        foreach($name in @($state.Services)) {
            try {
                $svc = Get-Service -Name ([string]$name) -ErrorAction Stop
                if($svc.Status -eq 'Stopped') {
                    Start-Service -Name $svc.Name -ErrorAction Stop
                    Write-YumLog ("Recovered optional service after an interrupted YUMRAM session: {0}" -f $svc.Name)
                }
            } catch {
                Write-YumLogException 'Interrupted service recovery failed' $_.Exception
            }
        }
        Remove-Item -LiteralPath $script:Yum.StateFile -Force -ErrorAction SilentlyContinue
        $script:Yum.StoppedOptionalServices.Clear()
    } catch {
        Write-YumLogException 'Interrupted service-state recovery failed' $_.Exception
    }
}

function Get-YumOptionalBackgroundProcesses {
    @($script:Yum.Config.OptionalBackgroundProcesses)
}

function Test-YumOptionalBackgroundProcess {
    param([Parameter(Mandatory)][string]$Name)
    $clean=$Name -replace '\.exe$',''
    foreach($item in @(Get-YumOptionalBackgroundProcesses)) {
        if([string]$item -ieq $clean){return $true}
    }
    return $false
}

function Get-YumOptionalBackgroundProcessCandidates {
    param([int]$ForegroundPid=0,[int]$GamePid=0)
    $rows=New-Object System.Collections.Generic.List[object]
    $cpuMap=@{};try{if(Get-Command Get-YumProcessCpuMap -ErrorAction SilentlyContinue){$cpuMap=Get-YumProcessCpuMap}}catch{}
    foreach($p in @(Get-Process)) {
        try {
            if($p.Id -eq $PID -or $p.Id -eq $ForegroundPid -or $p.Id -eq $GamePid){continue}
            if(Test-YumProtectedProcess -Process $p){continue}
            if(-not (Test-YumOptionalBackgroundProcess -Name $p.ProcessName)){continue}
            if($p.PriorityClass -eq [System.Diagnostics.ProcessPriorityClass]::RealTime){continue}
            $cpu=0.0
            if($cpuMap.Contains([int]$p.Id)){ $cpu=[double]$cpuMap[[int]$p.Id] }
            else {
                try {
                    $cpuSeconds=[double]$p.TotalProcessorTime.TotalSeconds
                    $ageSeconds=1.0
                    try { $ageSeconds=[math]::Max(1.0,((Get-Date)-$p.StartTime).TotalSeconds) } catch {}
                    $cpu=[math]::Min(100.0,(($cpuSeconds/[math]::Max(1,[Environment]::ProcessorCount))/$ageSeconds)*100.0)
                } catch {}
            }
            $ws=[int64]$p.WorkingSet64
            if($ws -lt 50MB){continue}
            [void]$rows.Add([pscustomobject]@{Process=$p;WorkingSet=$ws;CPU=$cpu;Reason='Configured optional background process'})
        } catch {}
    }
    @($rows | Sort-Object WorkingSet -Descending)
}

function Invoke-YumStopOptionalBackgroundProcess {
    param([Parameter(Mandatory)][System.Diagnostics.Process]$Process)
    try {
        if(-not (Test-YumOptionalBackgroundProcess -Name $Process.ProcessName)){return [pscustomobject]@{Success=$false;Reason='Not classified as optional'}}
        if(Test-YumProtectedProcess -Process $Process){return [pscustomobject]@{Success=$false;Reason='Protected process'}}
        [void]$Process.CloseMainWindow()
        Start-Sleep -Milliseconds 250
        $Process.Refresh()
        if(-not $Process.HasExited){
            # Never use Kill here. Optional cleanup is cooperative only.
            return [pscustomobject]@{Success=$false;Reason='Process did not exit cooperatively'}
        }
        Write-YumLog ("Optional background process exited: {0} PID {1}" -f $Process.ProcessName,$Process.Id)
        return [pscustomobject]@{Success=$true;Reason='Exited cooperatively'}
    } catch {
        Write-YumLogException 'Optional background process stop failed' $_.Exception
        return [pscustomobject]@{Success=$false;Reason=$_.Exception.Message}
    }
}


function Test-YumOptionalServiceSafety {
    param([Parameter(Mandatory)][System.ServiceProcess.ServiceController]$Service)
    try {
        # Only user-approved, non-core, manually-started services are eligible.
        # Automatic/boot/system services are intentionally never stopped by YUMRAM.
        $protectedNames = @(
            'EventLog','RpcSs','DcomLaunch','RpcEptMapper','PlugPlay','Power','ProfSvc',
            'SamSs','Schedule','W32Time','Winmgmt','BITS','wuauserv','WinDefend',
            'SecurityHealthService','LanmanWorkstation','LanmanServer','Dhcp','Dnscache',
            'NlaSvc','Netman','AudioSrv','Audiosrv','Spooler','CryptSvc','Winlogon'
        )
        if ($protectedNames -contains $Service.Name) { return $false }
        if ($Service.CanStop -ne $true) { return $false }
        if (@($Service.DependentServices | Where-Object { $_.Status -eq 'Running' }).Count -gt 0) { return $false }
        $cim = Get-CimInstance Win32_Service -Filter ("Name='{0}'" -f ($Service.Name.Replace("'","''"))) -ErrorAction Stop
        if ($null -eq $cim) { return $false }
        if ([string]$cim.StartMode -ne 'Manual') { return $false }
        return $true
    } catch { return $false }
}

function Get-YumOptionalServiceCandidates {
    $rows=New-Object System.Collections.Generic.List[object]
    foreach($name in @(Get-YumOptionalServices)) {
        try {
            $svc=Get-Service -Name $name -ErrorAction Stop
            if($svc.Status -ne 'Running'){continue}
            if(-not (Test-YumOptionalServiceSafety -Service $svc)){continue}
            [void]$rows.Add([pscustomobject]@{Service=$svc;Name=$svc.Name;DisplayName=$svc.DisplayName;Reason='Explicitly user-approved optional service'})
        } catch {}
    }
    $rows.ToArray()
}

function Invoke-YumIntelligentStopService {
    param([Parameter(Mandatory)][System.ServiceProcess.ServiceController]$Service)
    try {
        # Intelligent target maintenance may stop a narrowly classified, manually-started
        # third-party service without requiring it to have been pre-listed by the user.
        # Safety is still mandatory: no core service, no automatic/boot service, no
        # running dependents, and the service must be stoppable. Startup configuration
        # is never changed; stopped services are restored on clean/interrupted shutdown.
        if(-not (Test-YumOptionalServiceSafety -Service $Service)){
            return [pscustomobject]@{Success=$false;Reason='Service did not pass YUMRAM intelligent-service safety policy'}
        }
        Stop-Service -Name $Service.Name -ErrorAction Stop
        if($script:Yum.StoppedOptionalServices -notcontains $Service.Name){
            [void]$script:Yum.StoppedOptionalServices.Add($Service.Name)
            Save-YumStoppedServiceState
        }
        Write-YumLog ("Intelligent target maintenance stopped service: {0} ({1})" -f $Service.Name,$Service.DisplayName)
        return [pscustomobject]@{Success=$true;Reason='Stopped temporarily; service startup configuration was not changed'}
    } catch {
        Write-YumLogException 'Intelligent service stop failed' $_.Exception
        return [pscustomobject]@{Success=$false;Reason=$_.Exception.Message}
    }
}

function Invoke-YumStopOptionalService {
    param([Parameter(Mandatory)][System.ServiceProcess.ServiceController]$Service)
    try {
        # Termination is intentionally disabled until the Intelligence database is proven stable.
        if($null -eq $script:Yum.Config.EnableServiceTermination -or -not [bool]$script:Yum.Config.EnableServiceTermination){return [pscustomobject]@{Success=$false;Reason='Service termination is disabled in the current stable build'}}
        if(-not (Get-YumOptionalServices | Where-Object {$_ -ieq $Service.Name})){return [pscustomobject]@{Success=$false;Reason='Service is not user-approved'}}
        if(-not (Test-YumOptionalServiceSafety -Service $Service)){return [pscustomobject]@{Success=$false;Reason='Service did not pass YUMRAM optional-service safety policy'}}
        Stop-Service -Name $Service.Name -ErrorAction Stop
        if($script:Yum.StoppedOptionalServices -notcontains $Service.Name){[void]$script:Yum.StoppedOptionalServices.Add($Service.Name);Save-YumStoppedServiceState}
        Write-YumLog ("Optional service stopped for reclaim: {0} ({1})" -f $Service.Name,$Service.DisplayName)
        return [pscustomobject]@{Success=$true;Reason='Stopped; service startup configuration was not changed'}
    } catch {
        Write-YumLogException 'Optional service stop failed' $_.Exception
        return [pscustomobject]@{Success=$false;Reason=$_.Exception.Message}
    }
}

function Restart-YumOptionalServices {
    foreach($name in @($script:Yum.StoppedOptionalServices)) {
        try {
            $svc=Get-Service -Name $name -ErrorAction Stop
            if($svc.Status -eq 'Stopped') {
                Start-Service -Name $name -ErrorAction Stop
                Write-YumLog ("Optional service restarted: {0}" -f $name)
            }
        } catch { Write-YumLogException 'Optional service restart failed' $_.Exception }
    }
    $script:Yum.StoppedOptionalServices.Clear()
    Remove-Item -LiteralPath $script:Yum.StateFile -Force -ErrorAction SilentlyContinue
}

function Test-YumUserApprovedOptionalServiceName {
    param([string]$Name)
    if([string]::IsNullOrWhiteSpace($Name)){return $false}
    foreach($item in @(Get-YumOptionalServices)){if([string]$item -ieq $Name){return $true}}
    return $false
}
