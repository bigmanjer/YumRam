#requires -Version 5.1
# 5.15.2: CPU %, speed, GPU busy and VRAM readable without monitoring (user report: "-- GHz" and frozen GPU while
# monitoring was off, no VRAM). Runs in strict mode like the app; reads only Windows counters and DXGI.
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'App\Bootstrap.ps1')
Initialize-YumConfig
$script:Yum.Config.Logging=$false
function Assert-That([bool]$Condition,[string]$Message){if(-not $Condition){throw $Message}}

$null=Get-YumLiveCpu; Start-Sleep -Milliseconds 1100
$sw=[Diagnostics.Stopwatch]::StartNew(); $c=Get-YumLiveCpu; $cpuMs=$sw.Elapsed.TotalMilliseconds
Assert-That ($null -ne $c) 'CPU reading returned nothing.'
Assert-That ([double]$c.Percent -ge 0 -and [double]$c.Percent -le 100) ('CPU % out of range: {0}' -f $c.Percent)
Assert-That ([double]$c.MHz -gt 200 -and [double]$c.MHz -lt 8000) ('CPU speed not plausible: {0} MHz' -f $c.MHz)
Assert-That ($cpuMs -lt 100) ('CPU reading should be cheap, took {0:N0} ms.' -f $cpuMs)

$ad=@(Get-YumGpuAdapters)
Assert-That ($ad.Count -ge 1) 'No graphics adapter found through DXGI.'
foreach($a in $ad){ Assert-That ([string]$a.Name -ne '' -and [string]$a.Luid -match '^luid_0x[0-9a-f]{8}_0x[0-9a-f]{8}$') ('Bad adapter record: {0} {1}' -f $a.Name,$a.Luid) }
$null=Get-YumLiveGpu; Start-Sleep -Milliseconds 1100
$sw=[Diagnostics.Stopwatch]::StartNew(); $g=Get-YumLiveGpu; $gpuMs=$sw.Elapsed.TotalMilliseconds
Assert-That ($null -ne $g.Main) 'No main adapter picked.'
Assert-That ([double]$g.Busiest -ge 0 -and [double]$g.Busiest -le 100) ('GPU busy out of range: {0}' -f $g.Busiest)
foreach($r in @($g.Adapters)){ if($null -ne $r.VramUsedGB -and [double]$r.VramTotalGB -gt 0){ Assert-That ([double]$r.VramUsedGB -ge 0 -and [double]$r.VramUsedGB -le [double]$r.VramTotalGB*1.05+0.1) ('VRAM in use not plausible for {0}: {1:N2} of {2:N2} GB' -f $r.Name,$r.VramUsedGB,$r.VramTotalGB) } }
Assert-That ($gpuMs -lt 250) ('GPU reading should be cheap, took {0:N0} ms.' -f $gpuMs)
$txt=Format-YumVram $g
Assert-That ($txt -match 'VRAM') ('VRAM text missing: "{0}"' -f $txt)
Assert-That ((Format-YumVram $null) -eq '') 'No reading -> empty text, no error.'

# Wiring: Overview uses them while paused and explains the GPU number.
$mw=[IO.File]::ReadAllText((Join-Path $root 'UI\MainWindow.ps1'))
Assert-That ($mw -match 'Update-YumLiveReadingsUi -Paused') 'Overview refresh calls the live readings.'
Assert-That ($mw -notmatch 'start monitoring for live CPU') 'No more "start monitoring for live CPU".'
$x=[IO.File]::ReadAllText((Join-Path $root 'UI\Xaml\MainWindow.xaml'))
Assert-That ($x -match 'x:Name="GpuVram"' -and $x -match "graphics chip's 3D engine") 'GPU card shows VRAM and explains itself.'

# 5.15.2: disk like Task Manager (busy %, read/write, response, free space) and X keeps YUMRAM running.
$null=Get-YumLiveDisk; Start-Sleep -Milliseconds 1100
$sw=[Diagnostics.Stopwatch]::StartNew(); $d=Get-YumLiveDisk; $diskMs=$sw.Elapsed.TotalMilliseconds
Assert-That (@($d.Disks).Count -ge 1) 'No physical disk found.'
Assert-That ($null -ne $d.Busiest -and [double]$d.Busiest -ge 0 -and [double]$d.Busiest -le 100) ('Disk busy out of range: {0}' -f $d.Busiest)
Assert-That ([double]$d.ReadMBs -ge 0 -and [double]$d.WriteMBs -ge 0) 'Disk speeds must not be negative.'
Assert-That (@($d.Drives | Where-Object { $_.Letter -eq $env:SystemDrive }).Count -eq 1) 'Windows drive free space missing.'
Assert-That ($diskMs -lt 250) ('Disk reading should be cheap, took {0:N0} ms.' -f $diskMs)
$dl=Format-YumDiskLines $d
Assert-That ($dl -match 'Disk 0' -and $dl -match 'GB free of') ('Disk text incomplete: "{0}"' -f $dl)
Assert-That ((Format-YumDiskSpeed 0.5) -match 'KB/s' -and (Format-YumDiskSpeed 12.34) -eq ('{0:N1} MB/s' -f 12.34) -and (Format-YumDiskSpeed $null) -eq '--') 'Disk speed wording.'
Assert-That ($x -match 'x:Name="DiskBusy"' -and $x -match 'x:Name="DiskSpaceBar"' -and $x -match 'x:Name="DiskRing"' -and $x -match 'x:Name="GpuRing"' -and $x -match 'Active time') 'Overview has the disk card and explains it.'
$script:Yum['ExitRequested']=$false; $script:Yum.Config['CloseToBackground']=$true
Assert-That (Test-YumCloseToBackground) 'X keeps YUMRAM running by default.'
$script:Yum.Config['CloseToBackground']=$false; Assert-That (-not (Test-YumCloseToBackground)) 'Setting off: X quits.'
$script:Yum.Config['CloseToBackground']=$true; $script:Yum['ExitRequested']=$true; Assert-That (-not (Test-YumCloseToBackground)) 'Tray Exit / update / sign-out still quits.'
$script:Yum['ExitRequested']=$false
$tray=[IO.File]::ReadAllText((Join-Path $root 'UI\Tray.ps1'))
Assert-That ($tray -match '\$exit\.Add_Click\(\{ Exit-YumApp \}\)') 'Tray Exit really quits.'
Assert-That ($mw -match 'Add_Closing' -and $mw -match '0x11' -and $mw -match 'YUMRAM-V5-ShowWindow') 'Closing hook, sign-out hook and re-open signal are wired.'
Assert-That ([IO.File]::ReadAllText((Join-Path $root 'UI\Xaml\Settings.xaml')) -match 'x:Name="CloseToBackground"') 'Settings has the close option.'
Write-Host ('LiveReadingsTest passed. Disk {5:N0} ms.  CPU {0}% {1} MHz ({2:N0} ms); {3} ({4:N0} ms)' -f $c.Percent,$c.MHz,$cpuMs,$txt,$gpuMs,$diskMs)
