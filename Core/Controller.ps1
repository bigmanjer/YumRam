#requires -Version 5.1
<#
YUMRAM background controller worker (5.3.0).

Why this exists:
Earlier builds drove the cleanup controller and the reclaim verifier with
System.Timers.Timer + a PowerShell scriptblock (Add_Elapsed). In Windows
PowerShell 5.1 those handlers fire on thread-pool threads that have no
runspace, so the scriptblock never executes and the timer swallows the error.
Result: automatic target maintenance, queued "safe optimization" requests and
auto-clean-on-game-start silently never ran.

This worker runs Invoke-YumBackgroundController once per second inside its own
runspace. The runtime state ($script:Yum) is a shared reference; all
cross-thread state already goes through the existing Monitor locks
(CacheLock / RequestLock / CleanupLock / LogLock). The worker never touches
WPF objects: results are published to $script:Yum.CleanupResult and the UI
DispatcherTimer picks them up (Update-YumCleanupResultUI).
#>

$script:YumControllerWorkerScript = {
    param($Shared,[string]$Root,$StopEvent,[string[]]$Modules)
    $ErrorActionPreference = 'Continue'
    foreach($relative in $Modules){ . (Join-Path $Root $relative) }
    $script:Yum = $Shared
    try { Write-YumLog 'Controller worker started.' } catch {}
    $handles=[System.Threading.WaitHandle[]]@($StopEvent.WaitHandle,$script:Yum.ControllerWakeEvent)
    $warmed=$false
    while($true){
        # Wake every second, or immediately when the UI queues a request.
        if([System.Threading.WaitHandle]::WaitAny($handles,1000) -eq 0){break}
        # 5.3.1: warm the executable-identity cache once (Authenticode checks cost ~4-7 s cold) so the
        # first Free RAM / automatic pass does not pay for it. Skipped if a request is already waiting.
        if(-not $warmed -and $null -eq $script:Yum.ReclaimRequest){
            $warmed=$true
            try{ [void](Get-YumFastReclaimCandidates -TopN 16) }catch{}
        }
        try {
            # Manual Free RAM / Deep Reclaim requests run here, off the UI thread (5.3.1).
            $reclaimMode=$null
            [System.Threading.Monitor]::Enter($script:Yum.RequestLock)
            try{$reclaimMode=$script:Yum.ReclaimRequest;$script:Yum.ReclaimRequest=$null}finally{[System.Threading.Monitor]::Exit($script:Yum.RequestLock)}
            if($null -ne $reclaimMode){
                try{ [void](Invoke-YumMemoryReclaim -Mode $reclaimMode -Force) }
                catch{ try{Write-YumLogException -Context 'Queued RAM reclaim failed' -Exception $_.Exception}catch{} }
                finally{ $script:Yum.ReclaimResultVersion++ }
            }
            if([bool]$script:Yum.MonitoringActive){
                $snap = Get-YumSnapshotCopy
                if($null -ne $snap){ Update-YumGameState -Snapshot $snap }
            }
            Invoke-YumBackgroundController
            # 5.3.2: refresh the "reachable Available RAM" estimate: once at start, every 30 s while
            # monitoring, and right after a manual reclaim. ~0.5 s CPU (identities are cached).
            $estimateAge=([datetime]::UtcNow-[datetime]$script:Yum.ReachableEstimateUtc).TotalSeconds
            if(-not [bool]$script:Yum.CleanupRunning -and ($null -eq $script:Yum.ReachableEstimate -or $null -ne $reclaimMode -or ([bool]$script:Yum.MonitoringActive -and $estimateAge -ge 30))){
                $script:Yum.ReachableEstimateUtc=[datetime]::UtcNow
                try{ $script:Yum.ReachableEstimate=Get-YumReachableEstimate }catch{ try{Write-YumLogException -Context 'Reachable estimate failed' -Exception $_.Exception}catch{} }
            }
            $script:Yum.ControllerHeartbeatUtc = [datetime]::UtcNow
        } catch {
            try { Write-YumLogException -Context 'Controller worker tick failed' -Exception $_.Exception } catch {}
        }
    }
    try { Write-YumLog 'Controller worker stopped.' } catch {}
}

function Request-YumMemoryReclaim {
    # Queue a manual reclaim for the controller worker so the UI never blocks on it.
    param([ValidateSet('Quick','Deep')][string]$Mode='Quick')
    [System.Threading.Monitor]::Enter($script:Yum.RequestLock)
    try{
        if([bool]$script:Yum.ReclaimRunning -or $null -ne $script:Yum.ReclaimRequest){return $false}
        $script:Yum.ReclaimRequest=$Mode
        $script:Yum.ReclaimRequestedAt=Get-Date
    }finally{[System.Threading.Monitor]::Exit($script:Yum.RequestLock)}
    try{Start-YumControllerWorker}catch{}
    try{[void]$script:Yum.ControllerWakeEvent.Set()}catch{}
    return $true
}

function Test-YumReclaimBusy {
    return ([bool]$script:Yum.ReclaimRunning -or $null -ne $script:Yum.ReclaimRequest)
}

function Get-YumControllerWorkerModules {
    @('Core\Logging.ps1','Core\Config.ps1','Core\Intelligence.ps1','Core\Native.ps1','Core\MemoryReclaim.ps1','Core\Games.ps1','Core\Safety.ps1','Core\Bloatware.ps1','Core\Scanner.ps1','Core\Telemetry.ps1','Core\Cleanup.ps1')
}

function Start-YumControllerWorker {
    if($null -ne $script:Yum.ControllerPowerShell){ return }
    $stop = New-Object System.Threading.ManualResetEventSlim($false)
    $runspace = [runspacefactory]::CreateRunspace()
    $runspace.ApartmentState = 'MTA'
    $runspace.ThreadOptions = 'ReuseThread'
    $runspace.Open()
    $ps = [powershell]::Create()
    $ps.Runspace = $runspace
    [void]$ps.AddScript($script:YumControllerWorkerScript.ToString())
    [void]$ps.AddArgument($script:Yum)
    [void]$ps.AddArgument([string]$script:Yum.Root)
    [void]$ps.AddArgument($stop)
    [void]$ps.AddArgument([string[]](Get-YumControllerWorkerModules))
    $script:Yum.ControllerStopEvent = $stop
    $script:Yum.ControllerRunspace = $runspace
    $script:Yum.ControllerPowerShell = $ps
    $script:Yum.ControllerAsync = $ps.BeginInvoke()
    # Kept for backward compatibility with code that tests "is the controller running".
    $script:Yum.ControllerTimer = $ps
}

function Stop-YumControllerWorker {
    param([int]$TimeoutMs = 5000)
    $ps = $script:Yum.ControllerPowerShell
    if($null -eq $ps){ return }
    try { if($null -ne $script:Yum.ControllerStopEvent){ $script:Yum.ControllerStopEvent.Set() } } catch {}
    try {
        $async = $script:Yum.ControllerAsync
        if($null -ne $async -and $async.AsyncWaitHandle.WaitOne($TimeoutMs)){ [void]$ps.EndInvoke($async) } else { $ps.Stop() }
    } catch {}
    try { $ps.Dispose() } catch {}
    try { $script:Yum.ControllerRunspace.Close(); $script:Yum.ControllerRunspace.Dispose() } catch {}
    try { $script:Yum.ControllerStopEvent.Dispose() } catch {}
    $script:Yum.ControllerPowerShell = $null
    $script:Yum.ControllerAsync = $null
    $script:Yum.ControllerRunspace = $null
    $script:Yum.ControllerStopEvent = $null
    $script:Yum.ControllerTimer = $null
}
