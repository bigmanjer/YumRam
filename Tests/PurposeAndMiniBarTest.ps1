#requires -Version 5.1
# 5.15.2 (user reports): a friend "didn't know what things were for / which device", and "minimize to a little
# floating bar that can be hidden in the tray". Light checks: reads this PC, changes nothing.
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'App\Bootstrap.ps1')
Initialize-YumConfig
$script:Yum.Config.Logging=$false
function Assert-That([bool]$Condition,[string]$Message){if(-not $Condition){throw $Message}}

# 1. Device / feature words.
$cases=@(
    @('RtkAudUService64','','Realtek Semiconductor','sound'),
    @('AsusPTPService','','ASUSTeK COMPUTER INC.','touchpad'),
    @('voicemeeter8x64','','VB-Audio Software','microphone and speakers'),
    @('NVDisplay.Container','','NVIDIA Corporation','graphics card'),
    @('lghub_agent','','Logitech','mouse, keyboard'),
    @('vgtray','','Riot Games, Inc.','anti-cheat'),
    @('spoolsv','','Microsoft Corporation','printers'),
    @('BthAvctpSvc','','Microsoft Corporation','Bluetooth'),
    @('AsusHotkey','','ASUSTeK COMPUTER INC.','Fn keys')
)
foreach($c in $cases){ $p=Get-YumPurpose -Name $c[0] -Path $c[1] -Publisher $c[2]; Assert-That ($p.UsedFor -match [regex]::Escape($c[3])) ('{0}: expected "{1}", got "{2}"' -f $c[0],$c[3],$p.UsedFor) }
Assert-That ((Get-YumPurpose -Name 'steamservice' -Publisher 'Valve Corporation' -Description 'Steam Client Service monitors and updates Steam content').UsedFor -notmatch 'screen') '"monitors" in a description is not a screen.'
Assert-That ((Get-YumPurpose -Name 'zzqq-unknown-thing').Text -eq '') 'Nothing known -> empty, caller keeps its own text.'
$x=Get-YumPurpose -Name 'Discord' -Publisher 'Discord Inc.'; Assert-That ($x.Text -notmatch '\.\.' -and $x.Text -match 'Used for: chat') ('Purpose text tidy: "{0}"' -f $x.Text)

# 2. A real service gets Windows' own description (read-only), and it is cheap after the first call.
$svc=@(Get-CimInstance Win32_Service -Filter "Name='Spooler'" -ErrorAction SilentlyContinue)
if($svc.Count){ $p=Get-YumPurpose -Name 'Spooler' -DisplayName 'Print Spooler'; Assert-That ($p.What.Length -gt 10) 'Service description used.' }
$sw=[Diagnostics.Stopwatch]::StartNew(); foreach($i in 1..200){ [void](Get-YumPurpose -Name 'Discord' -Publisher 'Discord Inc.') }; Assert-That ($sw.ElapsedMilliseconds -lt 500) ('Cached purpose lookups too slow: {0} ms' -f $sw.ElapsedMilliseconds)

# 3. Wiring: Intelligence, What's running and Startup show it.
$ix=[IO.File]::ReadAllText((Join-Path $root 'UI\Xaml\Intelligence.xaml')); Assert-That ($ix -match 'x:Name="SelectedPurpose"' -and $ix -match 'WHAT IS IT FOR') 'Intelligence shows "What is it for?".'
$dl=[IO.File]::ReadAllText((Join-Path $root 'UI\Dialogs.ps1')); Assert-That (([regex]::Matches($dl,'Get-YumPurpose')).Count -ge 2) "Intelligence and What's running use Get-YumPurpose."
Assert-That ([IO.File]::ReadAllText((Join-Path $root 'UI\StartupPage.ps1')) -match 'Get-YumPurpose') 'Startup apps use Get-YumPurpose.'

# 4. Mini bar: builds, reads, and is offered everywhere it should be.
Add-Type -AssemblyName PresentationFramework
Initialize-YumTheme
$mb=Initialize-YumMiniBar
Assert-That ($null -ne $mb.Window -and $mb.Window.Topmost -and -not $mb.Window.ShowInTaskbar) 'Mini bar is a small always-on-top window without a taskbar button.'
foreach($n in 'MiniFree','MiniOpen','MiniHide'){ Assert-That ($null -ne $mb.Window.FindName($n)) "Mini bar is missing $n" }
$mb.Window.Show(); Update-YumMiniBar
Assert-That ($mb.Ram.Value.Text -match '^\d+%$' -and $mb.Cpu.Value.Text -match '^\d+%$') ('Mini bar shows live numbers (RAM {0}, CPU {1}).' -f $mb.Ram.Value.Text,$mb.Cpu.Value.Text)
Close-YumMiniBar
Assert-That ($null -eq $script:Yum['MiniBar']) 'Mini bar closes cleanly.'
$tray=[IO.File]::ReadAllText((Join-Path $root 'UI\Tray.ps1')); Assert-That ($tray -match 'Show mini bar' -and $tray -match 'Test-YumMiniBarPreferred') 'Tray menu and close button offer the mini bar.'
Assert-That ([IO.File]::ReadAllText((Join-Path $root 'UI\Xaml\Settings.xaml')) -match 'x:Name="MiniBarOnMinimize"') 'Settings has the mini bar option.'
Assert-That ([IO.File]::ReadAllText((Join-Path $root 'UI\Xaml\MainWindow.xaml')) -match 'x:Name="MiniBarButton"') 'Overview has a Mini bar button.'
Write-Host 'PurposeAndMiniBarTest passed.'
