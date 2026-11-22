#requires -Version 5.1
<#
Captures the README gallery (Docs\Screenshots) from the real app, page by page (5.16.1).

  powershell -NoProfile -ExecutionPolicy Bypass -STA -File Tools\Capture-Screenshots.ps1 [-Out Docs\Screenshots]

- Runs YUMRAM from this folder with a temporary copy of its settings (your config is not changed), monitoring on,
  update check and hotkey off. Takes about 2 minutes: the Overview waits 35 s so the 30-second graph is full.
- Privacy: before every picture, your Windows user name and computer name are replaced on screen (in this
  throw-away copy only) with "User" and "PC"; the disk view looks at C:\Program Files, not your profile.
  Still look at every picture before publishing it.
#>
param([string]$Out)
$ErrorActionPreference='Stop'
$Root=Split-Path -Parent $PSScriptRoot
if(-not $Out){ $Out=Join-Path $Root 'Docs\Screenshots' }
New-Item -ItemType Directory -Path $Out -Force | Out-Null
. (Join-Path $Root 'App\Bootstrap.ps1'); Initialize-YumConfig; . (Join-Path $Root 'Core\Research.ps1')
$tmp=Join-Path $env:TEMP ('yum-shots-'+[guid]::NewGuid().ToString('N')); New-Item -ItemType Directory $tmp | Out-Null
Get-ChildItem $Root -Filter *.json | Copy-Item -Destination $tmp
$script:Yum.ConfigDirectory=$tmp; $script:Yum.ConfigFile=(Join-Path $tmp 'config.json'); $script:Yum.Config.LogFileName=(Join-Path $tmp 'shots.log')
$script:Yum.Config.StartMonitoringAutomatically=$true; $script:Yum.Config['UpdateCheckEnabled']=$false; $script:Yum.Config['GlobalHotkeyEnabled']=$false
$script:Taken=New-Object System.Collections.Generic.List[string]

function Hide-YumPersonalText {
    # Replace the user and computer name in every visible text of a window (throw-away copy only).
    param($Root)
    $names=@(@([string]$env:USERNAME,'User'),@([string]$env:COMPUTERNAME,'PC')) | Where-Object { $_[0].Length -ge 2 }
    $stack=New-Object System.Collections.Generic.Stack[object]; $stack.Push($Root)
    while($stack.Count -gt 0){
        $el=$stack.Pop()
        try{
            if($el -is [System.Windows.Controls.TextBlock] -or $el -is [System.Windows.Controls.TextBox]){
                $t=[string]$el.Text
                foreach($n in $names){ if($t -and $t.IndexOf($n[0],[StringComparison]::OrdinalIgnoreCase) -ge 0){ $t=[regex]::Replace($t,[regex]::Escape($n[0]),$n[1],'IgnoreCase'); $el.Text=$t } }
            }
            $count=[System.Windows.Media.VisualTreeHelper]::GetChildrenCount($el)
            for($i=0;$i -lt $count;$i++){ $stack.Push([System.Windows.Media.VisualTreeHelper]::GetChild($el,$i)) }
        }catch{}
    }
}
function Save-YumShot([string]$Name){
    $win=$script:Yum.Window; Hide-YumPersonalText -Root $win; $win.UpdateLayout()
    $w=[int]$win.ActualWidth; $h=[int]$win.ActualHeight-40
    $rtb=New-Object System.Windows.Media.Imaging.RenderTargetBitmap($w,$h,96,96,[System.Windows.Media.PixelFormats]::Pbgra32)
    $dv=New-Object System.Windows.Media.DrawingVisual; $dc=$dv.RenderOpen(); $dc.DrawRectangle($win.Background,$null,(New-Object System.Windows.Rect(0,0,$w,$h))); $dc.Close()
    $rtb.Render($dv); $rtb.Render($win)
    $enc=New-Object System.Windows.Media.Imaging.PngBitmapEncoder; $enc.Frames.Add([System.Windows.Media.Imaging.BitmapFrame]::Create($rtb))
    $fs=[IO.File]::Create((Join-Path $Out "$Name.png")); try{ $enc.Save($fs) }finally{ $fs.Dispose() }
    $script:Taken.Add($Name)
}
function Go([string]$k){ $script:GoKey=$k; [void]$script:Yum.Window.Dispatcher.BeginInvoke([action]{ Open-YumPage -Key $script:GoKey }) }
function PW([string]$k){ $p=$script:Yum.Pages[$k]; if($p){$p.Window}else{$null} }
$script:Wait=0
function Hold([scriptblock]$Busy,[int]$Max){ if((& $Busy) -and $script:Wait++ -lt $Max){ $script:I--; return }; $script:Wait=0 }

$script:Steps=@(
 { }
)
$script:Steps+=@(1..35 | ForEach-Object { { } })   # let the 30-second graph fill
$script:Steps+=@(
 { Save-YumShot 'Overview' },
 { Go 'Processes' }, { }, { }, { $st=(PW 'Processes').Tag; if(@($st.Rows).Count){ $st.Ui.Items.SelectedIndex=0 } }, { Save-YumShot 'WhatsRunning' },
 { Go 'ReclaimCenter' }, { }, { Save-YumShot 'ReclaimCenter' },
 { Go 'Startup' }, { }, { }, { }, { Save-YumShot 'StartupApps' },
 { Go 'WindowsBloat' }, { }, { }, { }, { Save-YumShot 'WindowsBloat' },
 { Go 'DiskCleanup' }, { }, { Hold { (PW 'DiskCleanup') -and (PW 'DiskCleanup').Tag.Busy } 40 },
 { $st=(PW 'DiskCleanup').Tag; $st.Ui.Junk.SelectedIndex=0; Start-YumDiskUsage -State $st -Path ${env:ProgramFiles} }, { },
 { Hold { (PW 'DiskCleanup').Tag.Busy } 60 }, { }, { Save-YumShot 'DiskCleanup' },
 { Go 'Intelligence' }, { }, { }, { $st=$script:Yum.IntelligenceWindow.Tag; if(@($st.ListView.Items).Count){ $st.ListView.SelectedIndex=0 } }, { Save-YumShot 'Intelligence' },
 { Go 'Settings' }, { },
 # Show the defaults (update check and shortcut are on for users; only this capture copy has them off). Not applied.
 { $w=PW 'Settings'; foreach($n in 'UpdateCheckEnabled','GlobalHotkeyEnabled'){ try{ $cb=$w.FindName($n); if($cb){ $cb.IsChecked=$true } }catch{} }; try{ $w.FindName('HotkeyStatus').Text='On' }catch{} }, { Save-YumShot 'Settings' },
 { $w=PW 'Settings'; $el=$w.FindName('CpuCareLevel'); while($el -and -not ($el -is [System.Windows.Controls.TabItem])){ $el=[System.Windows.LogicalTreeHelper]::GetParent($el) }; if($el){ $el.IsSelected=$true } }, { }, { Save-YumShot 'Settings-CPU' },
 { Go 'About' }, { }, { Save-YumShot 'About' },
 { Go 'Overview' }, { },
 { $x=@($script:Yum.TrayMenu.Items | Where-Object { $_.Text -match 'Exit' })[0]; $x.PerformClick() }
)
$script:I=0
$t=New-Object System.Windows.Threading.DispatcherTimer; $t.Interval=[TimeSpan]::FromSeconds(1)
$t.Add_Tick({ if($script:I -ge $script:Steps.Count){$t.Stop();return}; $s=$script:Steps[$script:I]; $script:I++; try{ & $s }catch{ Write-Host ("step {0}: {1}" -f $script:I,$_.Exception.Message) } })
$t.Start()
Start-YumApplicationUi
Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
"Saved {0} pictures to {1}: {2}" -f $script:Taken.Count,$Out,($script:Taken -join ', ')
