#requires -Version 5.1
# 5.4: notification-area icon with live RAM %. Checks the icon redraw does not leak GDI/USER handles,
# the tooltip stays within the 63-character NotifyIcon limit, and the main window runs in a way that
# survives being hidden to the tray.
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'App\Bootstrap.ps1')
Initialize-YumConfig
$script:Yum.Config.Logging=$false
Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class YumTrayTestNative {
    [DllImport("user32.dll")] public static extern uint GetGuiResources(IntPtr hProcess, uint uiFlags);
}
'@
function Get-GuiHandleCount { $h=[System.Diagnostics.Process]::GetCurrentProcess().Handle; return @([YumTrayTestNative]::GetGuiResources($h,0),[YumTrayTestNative]::GetGuiResources($h,1)) }

if(-not [bool]$script:Yum.Config['ShowTrayIcon']){throw 'ShowTrayIcon must default to true.'}
if(-not [bool]$script:Yum.Config['MinimizeToTray']){throw 'MinimizeToTray must default to true.'}
foreach($case in @(@(12,'Normal'),@(69.9,'Normal'),@(70,'Elevated'),@(84.9,'Elevated'),@(85,'High'),@(100,'High'))){
    $got=Get-YumTrayLevel -Percent $case[0]
    if($got -ne $case[1]){throw "Level for $($case[0])% should be $($case[1]), got $got"}
}

try{
    Initialize-YumTray
    if($null -eq $script:Yum.TrayIcon){throw 'Initialize-YumTray did not create the icon.'}
    if($script:Yum.TrayIconHandle -eq [IntPtr]::Zero){throw 'No icon handle after initialization.'}
    # Warm up, then redraw 300 different values: handle counts must stay flat.
    for($i=0;$i -lt 20;$i++){Update-YumTray -Percent $i -AvailableGB 8}
    $before=Get-GuiHandleCount
    for($i=0;$i -lt 300;$i++){Update-YumTray -Percent ($i % 101) -AvailableGB 123456.7}
    $after=Get-GuiHandleCount
    if(($after[0]-$before[0]) -gt 10 -or ($after[1]-$before[1]) -gt 10){throw "Tray icon redraw leaks handles: GDI $($before[0])->$($after[0]), USER $($before[1])->$($after[1])"}
    if($script:Yum.TrayIcon.Text.Length -gt 63){throw 'Tooltip exceeds 63 characters.'}
    if($script:Yum.TrayIcon.Text -notmatch '^YUMRAM: \d+% used'){throw "Unexpected tooltip: $($script:Yum.TrayIcon.Text)"}
    # No redraw when nothing changed.
    Update-YumTray -Percent 55 -AvailableGB 1;$h=$script:Yum.TrayIconHandle;Update-YumTray -Percent 55.2 -AvailableGB 2
    if($script:Yum.TrayIconHandle -ne $h){throw 'The icon was redrawn although the rounded % and level did not change.'}
    Show-YumTrayNotice -Title 'Test' -Text ('x'*400)   # must not throw on long text
}finally{ Remove-YumTray }
if($null -ne $script:Yum.TrayIcon -or $script:Yum.TrayIconHandle -ne [IntPtr]::Zero){throw 'Remove-YumTray did not release the icon.'}

# Static contract: the main window must not use ShowDialog (hiding it would end the app).
$mw=Get-Content -Raw (Join-Path $root 'UI\MainWindow.ps1')
if($mw -match '\$script:Yum\.Window\.ShowDialog\(\)'){throw 'Main window still uses ShowDialog(); minimize-to-tray would exit YUMRAM.'}
if($mw -notmatch 'Dispatcher\]::PushFrame\(\$script:Yum\.MainFrame\)'){throw 'Main window message loop (PushFrame) missing.'}
if($mw -notmatch 'MainFrame\.Continue=\$false'){throw 'Closing the main window must end the message loop.'}
$settings=Get-Content -Raw (Join-Path $root 'UI\Xaml\Settings.xaml')
foreach($n in 'ShowTrayIcon','MinimizeToTray'){ if($settings -notmatch ('x:Name="'+$n+'"')){throw "Settings is missing the $n checkbox."} }
Write-Host 'Tray icon test passed.'
