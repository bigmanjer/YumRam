#requires -Version 5.1
<#
YUMRAM notification-area (tray) icon (5.4).

- The icon itself shows the live RAM-in-use percentage, coloured like the main window's ring
  (purple < 70 %, amber < 85 %, red above).
- Menu: Open YUMRAM, Free RAM now, Start/Stop monitoring, Exit. Left-click or double-click opens.
- Minimizing the main window hides it to the tray when MinimizeToTray is on.
- 5.15.2: the X button keeps YUMRAM running (CloseToBackground); "Exit YUMRAM" in the tray menu quits.

Requirements met elsewhere: the main window runs with Show() + a DispatcherFrame (UI\MainWindow.ps1);
with ShowDialog(), hiding the window would end the application.
#>

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
if (-not ('YumTrayNative' -as [type])) {
    Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class YumTrayNative {
    [DllImport("user32.dll", SetLastError=true)] public static extern bool DestroyIcon(IntPtr hIcon);
}
'@
}

function Get-YumTrayLevel {
    param([double]$Percent)
    if($Percent -ge 85){return 'High'} elseif($Percent -ge 70){return 'Elevated'} else {return 'Normal'}
}

function New-YumTrayIconHandle {
    # Draws the percentage into a small square icon. Returns an HICON the caller must destroy.
    param([int]$Percent,[string]$Level)
    $size=[System.Windows.Forms.SystemInformation]::SmallIconSize.Width
    if($size -lt 16){$size=16}
    $bmp=New-Object System.Drawing.Bitmap($size,$size)
    $g=[System.Drawing.Graphics]::FromImage($bmp)
    try{
        $g.SmoothingMode=[System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $g.TextRenderingHint=[System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit
        $g.Clear([System.Drawing.Color]::Transparent)
        $bg=switch($Level){'High'{[System.Drawing.Color]::FromArgb(248,113,113)}'Elevated'{[System.Drawing.Color]::FromArgb(251,191,36)}default{[System.Drawing.Color]::FromArgb(168,85,247)}}
        $fg=if($Level -eq 'Elevated'){[System.Drawing.Color]::FromArgb(17,10,23)}else{[System.Drawing.Color]::White}
        $r=[math]::Max(3,[int]($size/4))
        $path=New-Object System.Drawing.Drawing2D.GraphicsPath
        $d=$r*2;$w=$size-1;$h=$size-1
        $path.AddArc(0,0,$d,$d,180,90);$path.AddArc($w-$d,0,$d,$d,270,90);$path.AddArc($w-$d,$h-$d,$d,$d,0,90);$path.AddArc(0,$h-$d,$d,$d,90,90);$path.CloseFigure()
        $brush=New-Object System.Drawing.SolidBrush($bg);$g.FillPath($brush,$path);$brush.Dispose();$path.Dispose()
        $text=[string][math]::Min(99,[math]::Max(0,$Percent))
        $fontSize=if($text.Length -ge 2){$size*0.56}else{$size*0.66}
        $font=New-Object System.Drawing.Font('Segoe UI',[float]$fontSize,[System.Drawing.FontStyle]::Bold,[System.Drawing.GraphicsUnit]::Pixel)
        $sf=New-Object System.Drawing.StringFormat;$sf.Alignment=[System.Drawing.StringAlignment]::Center;$sf.LineAlignment=[System.Drawing.StringAlignment]::Center
        $tb=New-Object System.Drawing.SolidBrush($fg)
        $g.DrawString($text,$font,$tb,(New-Object System.Drawing.RectangleF(0,0,$size,($size+1))),$sf)
        $tb.Dispose();$sf.Dispose();$font.Dispose()
    } finally { $g.Dispose() }
    try { return $bmp.GetHicon() } finally { $bmp.Dispose() }
}

function Initialize-YumTray {
    if($null -ne $script:Yum.TrayIcon){return}
    $icon=New-Object System.Windows.Forms.NotifyIcon
    $icon.Text='YUMRAM'
    $menu=New-Object System.Windows.Forms.ContextMenuStrip
    $open=$menu.Items.Add('Open YUMRAM');$open.Font=New-Object System.Drawing.Font($open.Font,[System.Drawing.FontStyle]::Bold)
    $free=$menu.Items.Add('Free RAM now')
    $mon=$menu.Items.Add('Start monitoring')
    $mini=$menu.Items.Add('Show mini bar');$mini.ToolTipText='A small floating bar with RAM, CPU, GPU and disk. Drag it anywhere.'
    $mini.Add_Click({ try{ $mb=$script:Yum['MiniBar']; if($null -ne $mb -and $mb.Window.IsVisible){ Hide-YumMiniBar }else{ $mb=Initialize-YumMiniBar; $mb.Window.Show() } }catch{ Write-YumLogException -Context 'Tray mini bar failed' -Exception $_.Exception } })
    $script:Yum['TrayMenuMini']=$mini
    [void]$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))
    $report=$menu.Items.Add('Report a problem…');$report.ToolTipText='Opens the GitHub bug form in your browser, filled in (no user or PC names). Nothing is posted until you press Create.'
    $report.Add_Click({ [void](Open-YumReportProblem) })
    $exit=$menu.Items.Add('Exit YUMRAM')
    $open.Add_Click({ Show-YumMainWindow })
    $free.Add_Click({ try{ if(Request-YumMemoryReclaim -Mode Quick){ $script:Yum.TrayReclaimPending=$true; Set-YumFooter 'Freeing RAM from the tray…' } }catch{ Write-YumLogException -Context 'Tray Free RAM failed' -Exception $_.Exception } })
    $mon.Add_Click({ try{ if($null -eq $script:Yum.TelemetryTimer){Start-YumMonitoring}else{Stop-YumMonitoring} }catch{ Write-YumLogException -Context 'Tray monitoring toggle failed' -Exception $_.Exception } })
    $exit.Add_Click({ Exit-YumApp })
    $menu.Add_Opening({
        try{
            $script:Yum.TrayMenuMonitor.Text=if($null -eq $script:Yum.TelemetryTimer){'Start monitoring'}else{'Stop monitoring'}
            $script:Yum.TrayMenuFreeRam.Enabled=-not (Test-YumReclaimBusy)
            $mb=$script:Yum['MiniBar']; $script:Yum['TrayMenuMini'].Text=if($null -ne $mb -and $mb.Window.IsVisible){'Hide mini bar'}else{'Show mini bar'}
        }catch{}
    })
    $icon.ContextMenuStrip=$menu
    $icon.Add_MouseClick({ param($s,$e) if($e.Button -eq [System.Windows.Forms.MouseButtons]::Left){ Show-YumMainWindow } })
    $script:Yum.TrayIcon=$icon
    $script:Yum.TrayMenu=$menu
    $script:Yum.TrayMenuMonitor=$mon
    $script:Yum.TrayMenuFreeRam=$free
    $script:Yum.TrayIconHandle=[IntPtr]::Zero
    $script:Yum.TrayLastKey=''
    Update-YumTray -Percent 0 -AvailableGB 0 -Force
    $icon.Visible=$true
}

function Update-YumTray {
    # Cheap when nothing changed: the icon is only redrawn when the rounded % or the level changes.
    param([double]$Percent,[double]$AvailableGB,[switch]$Force)
    $icon=$script:Yum.TrayIcon
    if($null -eq $icon){return}
    try{
        $p=[int][math]::Round($Percent);$level=Get-YumTrayLevel -Percent $Percent
        $key="$p|$level"
        if($Force -or $key -ne [string]$script:Yum.TrayLastKey){
            $handle=New-YumTrayIconHandle -Percent $p -Level $level
            $old=$script:Yum.TrayIconHandle
            $icon.Icon=[System.Drawing.Icon]::FromHandle($handle)
            $script:Yum.TrayIconHandle=$handle
            if($old -ne [IntPtr]::Zero){[void][YumTrayNative]::DestroyIcon($old)}
            $script:Yum.TrayLastKey=$key
        }
        $state=if($null -ne $script:Yum.TelemetryTimer){'monitoring'}else{'paused'}
        $text=('YUMRAM: {0}% used, {1:N1} GB free ({2})' -f $p,$AvailableGB,$state)
        if($text.Length -gt 63){$text=$text.Substring(0,63)}   # NotifyIcon.Text limit on .NET Framework
        if($icon.Text -ne $text){$icon.Text=$text}
    }catch{}
}

function Show-YumMainWindow {
    $w=$script:Yum.Window
    if($null -eq $w){return}
    try{ Hide-YumMiniBar }catch{}
    try{
        if(-not $w.IsVisible){$w.Show()}
        if($w.WindowState -eq [System.Windows.WindowState]::Minimized){$w.WindowState=[System.Windows.WindowState]::Normal}
        [void]$w.Activate()
    }catch{}
}

function Invoke-YumSelfTrim {
    try{
        $before=(Get-Process -Id $PID).WorkingSet64
        [GC]::Collect();[GC]::WaitForPendingFinalizers();[GC]::Collect()
        $r=Invoke-YumEmptyWorkingSet -Process (Get-Process -Id $PID)
        $after=(Get-Process -Id $PID).WorkingSet64
        Write-YumLog ('Hidden in the tray: YUMRAM released its own idle memory ({0:N0} MB -> {1:N0} MB).' -f ($before/1MB),($after/1MB))
    }catch{}
}

function Hide-YumToTray {
    $w=$script:Yum.Window
    if($null -eq $w -or $null -eq $script:Yum.TrayIcon){return}
    $w.Hide()
    # 5.8.1: a RAM tool should practise what it preaches. Once hidden (and still hidden 10 s later),
    # release YUMRAM's own idle memory: one GC + trim of its own working set. Pages stay in standby.
    try{
        if($null -ne $script:Yum['SelfTrimTimer']){$script:Yum['SelfTrimTimer'].Stop()}
        $st=New-Object System.Windows.Threading.DispatcherTimer;$st.Interval=[TimeSpan]::FromSeconds(10)
        $st.Add_Tick({param($s,$e)$s.Stop();try{if(-not $script:Yum.Window.IsVisible){Invoke-YumSelfTrim}}catch{}})
        $script:Yum['SelfTrimTimer']=$st;$st.Start()
    }catch{}
    if(-not [bool]$script:Yum.TrayHintShown){
        $script:Yum.TrayHintShown=$true
        try{ $script:Yum.TrayIcon.ShowBalloonTip(4000,'YUMRAM is still running','It keeps working from the notification area. Click the icon to open it.',[System.Windows.Forms.ToolTipIcon]::Info) }catch{}
    }
}

function Exit-YumApp {
    # Really quit (tray "Exit YUMRAM", installing an update, Windows signing out). The X button only hides.
    $script:Yum['ExitRequested']=$true
    try{ $script:Yum.Window.Close() }catch{}
}

function Test-YumCloseToBackground {
    # 5.15.2 (user request: "close should put it to task bar to run in background").
    if([bool]$script:Yum['ExitRequested']){return $false}
    $c=$script:Yum.Config['CloseToBackground']
    return (($null -eq $c) -or [bool]$c)
}

function Invoke-YumCloseToBackground {
    # With the tray icon: hide to the notification area. Without it: minimize to the taskbar (never vanish).
    $w=$script:Yum.Window
    if(Test-YumMiniBarPreferred){ Show-YumMiniBar; try{ Write-YumLog 'Window closed with X: YUMRAM keeps running as the mini bar.' }catch{}; return }
    if($null -ne $script:Yum.TrayIcon){
        $first=-not [bool]$script:Yum['CloseHintShown']; $script:Yum['CloseHintShown']=$true
        $script:Yum.TrayHintShown=$true
        Hide-YumToTray
        if($first){ try{ $script:Yum.TrayIcon.ShowBalloonTip(6000,'YUMRAM is still running','Closing the window keeps YUMRAM working in the background. Click the icon near the clock to open it; right-click it and choose Exit YUMRAM to quit.',[System.Windows.Forms.ToolTipIcon]::Info) }catch{} }
    } else {
        $w.WindowState=[System.Windows.WindowState]::Minimized
    }
    try{ Write-YumLog 'Window closed with X: YUMRAM keeps running in the background.' }catch{}
}

function Show-YumTrayNotice {
    param([string]$Title,[string]$Text)
    if($null -eq $script:Yum.TrayIcon){return}
    if($Text.Length -gt 250){$Text=$Text.Substring(0,247)+'...'}   # balloon text limit is 255
    try{ $script:Yum.TrayIcon.ShowBalloonTip(5000,$Title,$Text,[System.Windows.Forms.ToolTipIcon]::Info) }catch{}
}

function Remove-YumTray {
    $icon=$script:Yum.TrayIcon
    if($null -eq $icon){return}
    try{$icon.Visible=$false}catch{}
    try{$icon.Dispose()}catch{}
    try{$script:Yum.TrayMenu.Dispose()}catch{}
    try{ if($script:Yum.TrayIconHandle -ne [IntPtr]::Zero){[void][YumTrayNative]::DestroyIcon($script:Yum.TrayIconHandle)} }catch{}
    $script:Yum.TrayIcon=$null;$script:Yum.TrayMenu=$null;$script:Yum.TrayIconHandle=[IntPtr]::Zero
}
