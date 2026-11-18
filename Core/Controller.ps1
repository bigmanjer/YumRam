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
    while(-not $StopEvent.Wait(1000)){
        try {
            if([bool]$script:Yum.MonitoringActive){
                $snap = Get-YumSnapshotCopy
                if($null -ne $snap){ Update-YumGameState -Snapshot $snap }
            }
            Invoke-YumBackgroundController
            $script:Yum.ControllerHeartbeatUtc = [datetime]::UtcNow
        } catch {
            try { Write-YumLogException -Context 'Controller worker tick failed' -Exception $_.Exception } catch {}
        }
    }
    try { Write-YumLog 'Controller worker stopped.' } catch {}
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
