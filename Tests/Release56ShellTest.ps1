#requires -Version 5.1
# 5.6 behaviour: one-window shell (sidebar pages), global hotkey parsing, freed-RAM statistics.
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'App\Bootstrap.ps1')
Initialize-YumConfig
$script:Yum.Config.Logging=$false
function Assert-That([bool]$Condition,[string]$Message){if(-not $Condition){throw $Message}}

# 1. Every tool page is hosted in the main window (and still falls back to its own window without a shell).
$dialogs=Get-Content -Raw (Join-Path $root 'UI\Dialogs.ps1')
foreach($k in 'Processes','Settings','About','ReclaimCenter'){Assert-That ($dialogs -match ("Enter-YumPage -Key '{0}' -Window \`$window\)" -f $k)) "$k must be hosted as a page."}
Assert-That ($dialogs -match "Enter-YumPage -Key 'Intelligence' -Window \`$window -Persistent") 'Intelligence must be a persistent page.'
Assert-That ($dialogs -notmatch 'GetWindow\(\$s\)\.Close\(\)') 'A hosted page must never close its parent (main) window.'
Assert-That (-not (Test-YumShellAvailable)) 'No shell before the main window exists.'
Add-Type -AssemblyName PresentationFramework
$w=New-Object System.Windows.Window
Assert-That (-not (Enter-YumPage -Key 'About' -Window $w)) 'Without a shell Enter-YumPage must return $false so the caller shows a normal window.'

# 2. Main window XAML has every name the code looks up.
[xml]$x=Get-Content -Raw (Join-Path $root 'UI\Xaml\MainWindow.xaml')
$names=@($x.SelectNodes('//*[@*[local-name()="Name"]]') | ForEach-Object { $_.GetAttribute('Name','http://schemas.microsoft.com/winfx/2006/xaml') })
$mw=Get-Content -Raw (Join-Path $root 'UI\MainWindow.ps1')
$list=[regex]::Match($mw,"foreach\(\`$n in @\(([^)]*)\)\)").Groups[1].Value
foreach($n in ([regex]::Matches($list,"'([^']+)'") | ForEach-Object { $_.Groups[1].Value })){Assert-That ($names -contains $n) "MainWindow.xaml is missing x:Name=$n"}
foreach($n in 'NavOverview','Processes','ReclaimCenter','Intelligence','Settings','About','PageHost','OverviewPage','Sidebar'){Assert-That ($names -contains $n) "Shell element $n missing."}

# 3. Hotkey text parsing.
$hk=ConvertFrom-YumHotkeyText -Text 'ctrl+alt+r'
Assert-That ($null -ne $hk -and $hk.Text -eq 'Ctrl+Alt+R' -and $hk.Modifiers -eq 3 -and $hk.Key -eq 0x52) 'Ctrl+Alt+R should parse.'
Assert-That ((ConvertFrom-YumHotkeyText -Text 'Ctrl+Shift+F9').Key -eq 0x78) 'F9 should parse.'
Assert-That ($null -eq (ConvertFrom-YumHotkeyText -Text 'R')) 'A bare key must be rejected (it would steal typing).'
Assert-That ($null -eq (ConvertFrom-YumHotkeyText -Text 'Ctrl+Alt+R+T')) 'Two keys must be rejected.'
Assert-That ($null -eq (ConvertFrom-YumHotkeyText -Text 'Ctrl+Banana')) 'Unknown keys must be rejected.'
Assert-That ([bool]$script:Yum.Config['GlobalHotkeyEnabled'] -and [string]$script:Yum.Config['GlobalHotkey'] -eq 'Ctrl+Alt+R') 'Hotkey defaults missing.'

# 4. Freed-RAM statistics: only real gains count, day rollover resets today.
$tmp=Join-Path $env:TEMP ('yum-stats-'+[guid]::NewGuid().ToString('N'));New-Item -ItemType Directory $tmp|Out-Null
try{
    $script:Yum.ConfigDirectory=$tmp;$script:Yum.FreedStats=$null
    Add-YumFreedStat -GainGB 1.5;Add-YumFreedStat -GainGB 0.0;Add-YumFreedStat -GainGB -0.4;Add-YumFreedStat -GainGB 0.5
    $s=Get-YumFreedStats
    Assert-That ([int]$s.TotalRuns -eq 2 -and [math]::Abs([double]$s.TotalGB-2.0) -lt 0.001 -and [double]$s.BestGB -eq 1.5) "Stats wrong: runs=$($s.TotalRuns) total=$($s.TotalGB)"
    $s.Day='2000-01-01';Add-YumFreedStat -GainGB 0.25
    Assert-That ([math]::Abs([double]$s.TodayGB-0.25) -lt 0.001 -and [int]$s.TodayRuns -eq 1 -and [int]$s.TotalRuns -eq 3) 'A new day must reset today but keep the total.'
    $script:Yum.FreedStats=$null
    Assert-That ([int](Get-YumFreedStats).TotalRuns -eq 3) 'Stats must persist to stats.json.'
}finally{Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue}
Write-Host 'Release 5.6 shell test passed.'
