#requires -Version 5.1
# Regressions found by the 5.7 full UI test (Tests\UI\FullUiProbe.ps1).
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'App\Bootstrap.ps1')
Initialize-YumConfig
$script:Yum.Config.Logging=$false
function Assert-That([bool]$Condition,[string]$Message){if(-not $Condition){throw $Message}}

# Target hysteresis is used (it was saved but ignored).
$script:Yum.Config.MinimumAvailableGB=9.0;$script:Yum.Config['TargetHysteresisGB']=0.5
$d=Get-YumPressureDecision -Memory ([pscustomobject]@{AvailableGB=7.0;TotalGB=16.0;UsedPercent=56.0}) -Mode 'Balanced'
Assert-That ([math]::Abs([double]$d.StopTargetGB-9.5) -lt 0.001) "Cleanup must aim goal+hysteresis (got $($d.StopTargetGB))."
$script:Yum.Config['TargetHysteresisGB']=50
$d=Get-YumPressureDecision -Memory ([pscustomobject]@{AvailableGB=7.0;TotalGB=16.0;UsedPercent=56.0}) -Mode 'Balanced'
Assert-That ([double]$d.StopTargetGB -le 11.0) 'Hysteresis must be capped at 2 GB.'

# Automatic care yields to a manual reclaim request.
$cl=Get-Content -Raw (Join-Path $root 'Core\Cleanup.ps1')
Assert-That (([regex]::Matches($cl,'ReclaimRequest\)\{\$stopReason=')).Count -ge 2) 'Adaptive and fallback passes must stop when Free RAM / Deep is requested.'

# Settings: GPU interval matches the worker minimum; tray and timing apply live.
$dl=Get-Content -Raw (Join-Path $root 'UI\Dialogs.ps1')
Assert-That ($dl -match "GPUIntervalSeconds=@\(\`$u.GpuInterval.Text,5,60\)" -and $dl -match "GpuInterval='5'") 'GPU interval must default to 5 and accept 5-60 s.'
Assert-That ($dl -match 'Initialize-YumTray' -and $dl -match 'Remove-YumTray' -and $dl -match 'Stop-YumMonitoring;Start-YumMonitoring') 'Settings must apply tray and sampling changes live.'
$mw=Get-Content -Raw (Join-Path $root 'UI\MainWindow.ps1')
Assert-That ($mw -match 'Ui\.Mode\.Text=\(\[string\]\$script:Yum\.Config\.Mode\)') 'Sidebar mode badge must follow config changes.'
Assert-That ($mw -match "Status\.Text='● Paused'" -and $mw -match 'LastPausedMemoryRead') 'Paused monitoring must not look like a telemetry fault.'

# Reclaim explains an empty result.
$mr=Get-Content -Raw (Join-Path $root 'Core\MemoryReclaim.ps1')
Assert-That ($mr -match 'Nothing left to trim') 'An empty reclaim must say why.'
Write-Host 'Release 5.7 fixes test passed.'
