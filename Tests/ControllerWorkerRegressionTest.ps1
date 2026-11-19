#requires -Version 5.1
# Behavioral test: the background controller must actually execute.
# 5.2.x used System.Timers.Timer scriptblock handlers, which never run in Windows PowerShell 5.1,
# so automatic target maintenance and queued cleanup requests were silently dead.
# The target is forced to 0.1 GB so this test never trims anything on the machine running it.
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'App\Bootstrap.ps1')
Initialize-YumConfig
$script:Yum.Config.MinimumAvailableGB=0.1
$script:Yum.Config.Logging=$false
try {
    Start-YumControllerWorker
    if($null -eq $script:Yum.ControllerPowerShell){throw 'Controller worker did not start.'}
    $deadline=(Get-Date).AddSeconds(15)
    while($script:Yum.ControllerHeartbeatUtc -eq [datetime]::MinValue -and (Get-Date) -lt $deadline){Start-Sleep -Milliseconds 200}
    if($script:Yum.ControllerHeartbeatUtc -eq [datetime]::MinValue){
        $errs=@($script:Yum.ControllerPowerShell.Streams.Error | ForEach-Object {[string]$_})
        throw ('Controller worker never ticked. Worker errors: ' + ($errs -join ' | '))
    }
    $v0=[int]$script:Yum.CleanupResultVersion
    [void](Request-YumCleanup -Force)
    $deadline=(Get-Date).AddSeconds(15)
    while([int]$script:Yum.CleanupResultVersion -eq $v0 -and (Get-Date) -lt $deadline){Start-Sleep -Milliseconds 200}
    if([int]$script:Yum.CleanupResultVersion -eq $v0){throw 'Queued cleanup request was never processed by the controller.'}
    $r=$script:Yum.CleanupResult
    if(-not $r.Success){throw "Controller cleanup result reported failure: $($r.Reason)"}
    if(-not $r.TargetReached){throw 'Expected target (0.1 GB) to be reported as reached.'}
} finally {
    Stop-YumControllerWorker
}
if($null -ne $script:Yum.ControllerPowerShell){throw 'Controller worker did not stop.'}
Write-Output 'PASS: controller worker ticks, processes queued requests, and stops cleanly.'
