#requires -Version 5.1
# 5.6: one-window shell.
# Every tool (What's using RAM, Reclaim Center, Intelligence, Settings, About) opens as a page inside the
# main window, selected from a left sidebar - the Windows 11 Task Manager / Fluent NavigationView pattern -
# instead of a stack of separate pop-up windows.
#
# How hosting works: each tool still builds its own Window from XAML (so its code is unchanged and it can
# still run stand-alone). Enter-YumPage moves that window's content into the main window's PageHost.
#  * Blocking pages (everything except Intelligence) used ShowDialog(); their click handlers rely on the
#    Show-* function staying on the stack. Enter-YumPage keeps that contract with a nested DispatcherFrame
#    that ends when the user leaves the page.
#  * Intelligence is persistent: it keeps scanning/researching while you look at other pages and is shown
#    again instantly when you come back.
# Leaving a page calls the tool window's Close(), so its Closed handlers (timers etc.) still run.

function Test-YumShellAvailable {
    try{ return ($null -ne $script:Yum.Ui -and $script:Yum.Ui.Contains('PageHost') -and $null -ne $script:Yum.Ui['PageHost'] -and $null -ne $script:Yum.Window -and $script:Yum.Window.IsLoaded) }catch{ return $false }
}

function Get-YumPageTitle {
    param([string]$Key)
    switch($Key){
        'Overview'{'Overview'};'Processes'{"What's running"};'ReclaimCenter'{'Reclaim Center'};'Startup'{'Startup apps'};'WindowsBloat'{'Windows bloat'};'Intelligence'{'Intelligence'};'Settings'{'Settings'};'About'{'About'}
        default{$Key}
    }
}

function Update-YumNavSelection {
    param([string]$Key)
    foreach($k in @('NavOverview','Processes','ReclaimCenter','Startup','WindowsBloat','Intelligence','Settings','About')){
        try{
            $b=$script:Yum.Ui[$k]; if($null -eq $b){continue}
            $pageKey=if($k -eq 'NavOverview'){'Overview'}else{$k}
            $b.Tag=if($pageKey -eq $Key){'Selected'}else{$null}
        }catch{}
    }
}

function Set-YumHostContent {
    param([string]$Key,$Content)
    $ui=$script:Yum.Ui
    $script:Yum.CurrentPage=$Key
    Update-YumNavSelection -Key $Key
    if($Key -eq 'Overview' -or $null -eq $Content){
        $ui.PageHost.Content=$null
        $ui.PageHost.Visibility=[System.Windows.Visibility]::Collapsed
        $ui.OverviewPage.Visibility=[System.Windows.Visibility]::Visible
        try{ Update-YumGraph }catch{}
    } else {
        $ui.OverviewPage.Visibility=[System.Windows.Visibility]::Collapsed
        $ui.PageHost.Content=$Content
        $ui.PageHost.Visibility=[System.Windows.Visibility]::Visible
    }
    try{ $script:Yum.Window.Title=if($Key -eq 'Overview'){'YUMRAM'}else{'YUMRAM - '+(Get-YumPageTitle -Key $Key)} }catch{}
}

function Enter-YumPage {
    # Called by a Show-* function instead of ShowDialog()/Show(). Returns $false when there is no shell
    # (tests, probes, or the main window is not up yet) so the caller falls back to a normal window.
    param([Parameter(Mandatory=$true)][string]$Key,[Parameter(Mandatory=$true)]$Window,[switch]$Persistent)
    if(-not (Test-YumShellAvailable)){return $false}
    $content=$Window.Content
    $Window.Content=$null
    # Window-level resources (styles used only by this tool) travel with the content.
    try{
        if($null -ne $Window.Resources -and $Window.Resources.Count -gt 0 -and $content -is [System.Windows.FrameworkElement]){
            foreach($rk in @($Window.Resources.Keys)){ if(-not $content.Resources.Contains($rk)){ $content.Resources[$rk]=$Window.Resources[$rk] } }
        }
    }catch{}
    $entry=@{Key=$Key;Window=$Window;Content=$content;Persistent=[bool]$Persistent;Leaving=$false;Frame=$null}
    $script:Yum.Pages[$Key]=$entry
    $Window.Add_Closed({param($s,$e)
        try{
            foreach($k in @($script:Yum.Pages.Keys)){
                $p=$script:Yum.Pages[$k]
                if($null -eq $p -or -not [object]::ReferenceEquals($p.Window,$s)){continue}
                [void]$script:Yum.Pages.Remove($k)
                if($null -ne $p.Frame){ $p.Frame.Continue=$false }                       # Done/Close button on a blocking page
                elseif(-not $p.Leaving -and $script:Yum.CurrentPage -eq $k){ Open-YumPage -Key 'Overview' }  # Close on a persistent page
            }
        }catch{ Write-YumLogException -Context 'Hosted page close failed' -Exception $_.Exception }
    })
    Set-YumHostContent -Key $Key -Content $content
    if($Persistent){return $true}
    $frame=New-Object System.Windows.Threading.DispatcherFrame
    $entry.Frame=$frame
    $script:Yum.PageFrame=$frame
    try{ [System.Windows.Threading.Dispatcher]::PushFrame($frame) }
    finally{
        $script:Yum.PageFrame=$null
        $entry.Frame=$null
        $entry.Leaving=$true
        try{ if($script:Yum.Pages.ContainsKey($Key) -and [object]::ReferenceEquals($script:Yum.Pages[$Key],$entry)){ [void]$script:Yum.Pages.Remove($Key) } }catch{}
        try{ $Window.Close() }catch{}
    }
    # Opened directly (not from Open-YumPage's loop): nobody else will move on, so do it here.
    if([int]$script:Yum.NavLoopDepth -eq 0 -and $script:Yum.CurrentPage -eq $Key){
        $pending=[string]$script:Yum.PendingPage
        Set-YumHostContent -Key 'Overview' -Content $null
        if(-not [string]::IsNullOrWhiteSpace($pending)){ Open-YumPage -Key $pending }
    }
    return $true
}

function Invoke-YumPageFunction {
    param([string]$Key)
    switch($Key){
        'Processes'{Show-YumTopProcesses}
        'ReclaimCenter'{Show-YumMemoryReclaim}
        'Startup'{Show-YumStartupApps}
        'WindowsBloat'{Show-YumWindowsBloat}
        'Intelligence'{Show-YumIntelligence}
        'Settings'{Show-YumSettings}
        'About'{Show-YumAbout}
    }
}

function Open-YumPage {
    param([Parameter(Mandatory=$true)][string]$Key)
    try{
        if(-not (Test-YumShellAvailable)){ if($Key -ne 'Overview'){Invoke-YumPageFunction -Key $Key}; return }
        if($Key -eq $script:Yum.CurrentPage){return}
        # A blocking page is on screen: ask it to finish; the loop below (further down the stack) opens $Key.
        if($null -ne $script:Yum.PageFrame){ $script:Yum.PendingPage=$Key; $script:Yum.PageFrame.Continue=$false; return }
        $next=$Key
        $script:Yum.NavLoopDepth=[int]$script:Yum.NavLoopDepth+1
        try{
        while(-not [string]::IsNullOrWhiteSpace($next)){
            $script:Yum.PendingPage=$null
            if($next -eq 'Overview'){ Set-YumHostContent -Key 'Overview' -Content $null; break }
            $cached=$script:Yum.Pages[$next]
            if($null -ne $cached -and [bool]$cached.Persistent){ Set-YumHostContent -Key $next -Content $cached.Content; break }
            $isPersistent=($next -eq 'Intelligence')
            Invoke-YumPageFunction -Key $next
            if($isPersistent){ break }
            # A blocking page just ended: go where the user asked, or back to Overview.
            $next=if(-not [string]::IsNullOrWhiteSpace([string]$script:Yum.PendingPage)){[string]$script:Yum.PendingPage}else{'Overview'}
            # If the page failed to host (error dialog) we are already back; stop instead of looping.
            if($next -eq 'Overview' -and $script:Yum.CurrentPage -eq 'Overview'){break}
        }
        } finally { $script:Yum.NavLoopDepth=[math]::Max(0,[int]$script:Yum.NavLoopDepth-1) }
    }catch{ Write-YumLogException -Context ("Open page '{0}' failed" -f $Key) -Exception $_.Exception; try{Set-YumHostContent -Key 'Overview' -Content $null}catch{} }
}

function Test-YumPageShowing {
    # True when a tool window is on screen, either as its own window or as the current page.
    param($Window)
    if($null -eq $Window){return $false}
    try{ if($Window.IsVisible){return $true} }catch{}
    try{
        $p=$script:Yum.Pages[[string]$script:Yum.CurrentPage]
        return ($null -ne $p -and [object]::ReferenceEquals($p.Window,$Window) -and $script:Yum.Window.IsVisible)
    }catch{ return $false }
}

function Test-YumPageAlive {
    # True when a tool window still exists (own window, or hosted page even if another page is in front).
    param($Window)
    if($null -eq $Window){return $false}
    try{ if($Window.IsVisible){return $true} }catch{}
    foreach($p in @($script:Yum.Pages.Values)){ if($null -ne $p -and [object]::ReferenceEquals($p.Window,$Window)){return $true} }
    return $false
}

function Set-YumSidebarCompact {
    param([bool]$Compact)
    try{
        $ui=$script:Yum.Ui
        $script:Yum.SidebarCompact=$Compact
        $ui.Sidebar.Width=if($Compact){68}else{220}
        $vis=if($Compact){[System.Windows.Visibility]::Collapsed}else{[System.Windows.Visibility]::Visible}
        foreach($k in @('NavOverview','Processes','ReclaimCenter','Startup','WindowsBloat','Intelligence','Settings','About')){
            $b=$ui[$k]; if($null -eq $b){continue}
            try{ $b.Content.Children[1].Visibility=$vis }catch{}
            $b.HorizontalContentAlignment=if($Compact){[System.Windows.HorizontalAlignment]::Center}else{[System.Windows.HorizontalAlignment]::Left}
        }
        foreach($k in @('SideBrand','SideStatusPanel')){ if($null -ne $ui[$k]){ $ui[$k].Visibility=$vis } }
        if($null -ne $ui.SideRamCompact){ $ui.SideRamCompact.Visibility=if($Compact){[System.Windows.Visibility]::Visible}else{[System.Windows.Visibility]::Collapsed} }
    }catch{}
}

function Update-YumSideScanUi {
    # 5.15.2: shows a running Intelligence scan / research in the sidebar on every page (user report: the scan
    # was hard to notice). Reads the page's busy flags and, while researching, the small status file (1/s).
    try{
        $ui=$script:Yum.Ui;if($null -eq $ui['SideScanPanel']){return}
        $st=$null;try{ if(Test-YumPageAlive -Window $script:Yum.IntelligenceWindow){ $st=$script:Yum.IntelligenceWindow.Tag } }catch{}
        $scanning=($null -ne $st -and [bool]$st.Busy); $research=($null -ne $st -and [bool]$st.ResearchBusy)
        if(-not $scanning -and -not $research){ if($ui.SideScanPanel.Visibility -ne 'Collapsed'){$ui.SideScanPanel.Visibility='Collapsed'}; return }
        if(((Get-Date)-[datetime]$script:Yum['LastSideScanRead']).TotalSeconds -lt 1){return}
        $script:Yum['LastSideScanRead']=Get-Date
        $ui.SideScanPanel.Visibility='Visible'
        if($scanning -and -not $research){ $ui.SideScanText.Text='🔍 Scanning this PC…'; $ui.SideScanBar.IsIndeterminate=$true; return }
        $s=$null;try{ $s=Get-Content -LiteralPath (Get-YumResearchStatusPath) -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop }catch{}
        if($null -ne $s -and [int]$s.Total -gt 0){
            $ui.SideScanText.Text=('🔍 Researching {0}/{1}: {2}' -f [int]$s.Index,[int]$s.Total,[string]$s.Name)
            $ui.SideScanBar.IsIndeterminate=$false; $ui.SideScanBar.Value=[math]::Min(100,[math]::Max(0,100.0*[int]$s.Index/[int]$s.Total))
        } else { $ui.SideScanText.Text='🔍 Researching…'; $ui.SideScanBar.IsIndeterminate=$true }
    }catch{}
}
function Update-YumSidebarStatus {
    param([double]$UsedPercent,[double]$AvailableGB,[double]$TotalGB)
    try{
        $ui=$script:Yum.Ui
        if($null -ne $ui.SideRamText){ $ui.SideRamText.Text=('{0:N0}% used  •  {1:N1} GB free' -f $UsedPercent,$AvailableGB) }
        if($null -ne $ui.SideRamBar){ $ui.SideRamBar.Value=[math]::Min(100,[math]::Max(0,$UsedPercent)) }
        if($null -ne $ui.SideRamCompact){ $ui.SideRamCompact.Text=('{0:N0}%' -f $UsedPercent) }
        if($null -ne $ui.SideRamBar){ $ui.SideRamBar.Foreground=if($UsedPercent -ge 85){Get-YumBrush '#F87171'}elseif($UsedPercent -ge 70){Get-YumBrush '#FBBF24'}else{Get-YumBrush '#CFA8FF'} }
    }catch{}
}

function Initialize-YumShell {
    $ui=$script:Yum.Ui
    $script:Yum.Pages=@{}
    $script:Yum.CurrentPage='Overview'
    $script:Yum.PageFrame=$null
    $script:Yum.PendingPage=$null
    $script:Yum.NavLoopDepth=0
    $ui.NavOverview.Add_Click({Open-YumPage -Key 'Overview'})
    $ui.Processes.Add_Click({Open-YumPage -Key 'Processes'})
    $ui.ReclaimCenter.Add_Click({Open-YumPage -Key 'ReclaimCenter'})
    $ui.Startup.Add_Click({Open-YumPage -Key 'Startup'})
    try{ $ui.WindowsBloat.Add_Click({Open-YumPage -Key 'WindowsBloat'}) }catch{}
    $ui.Intelligence.Add_Click({Open-YumPage -Key 'Intelligence'})
    $ui.Settings.Add_Click({Open-YumPage -Key 'Settings'})
    $ui.About.Add_Click({Open-YumPage -Key 'About'})
    $ui.SidebarToggle.Add_Click({Set-YumSidebarCompact -Compact (-not [bool]$script:Yum.SidebarCompact);$script:Yum.SidebarPinnedByUser=$true})
    # Keyboard: Ctrl+1..7 jump to a page (accessibility; works from anywhere in the window).
    $script:Yum.Window.Add_PreviewKeyDown({param($s,$e)
        try{
            if(([System.Windows.Input.Keyboard]::Modifiers -band [System.Windows.Input.ModifierKeys]::Control) -eq 0){return}
            $map=@{D1='Overview';D2='Processes';D3='ReclaimCenter';D4='Startup';D5='Intelligence';D6='Settings';D7='About';D8='WindowsBloat';NumPad8='WindowsBloat';NumPad1='Overview';NumPad2='Processes';NumPad3='ReclaimCenter';NumPad4='Startup';NumPad5='Intelligence';NumPad6='Settings';NumPad7='About'}
            $k=[string]$e.Key
            if($map.ContainsKey($k)){ $e.Handled=$true; Open-YumPage -Key $map[$k] }
        }catch{}
    })
    # Adaptive sidebar: icons only when the window is narrow (NavigationView LeftCompact behaviour).
    $script:Yum.Window.Add_SizeChanged({param($s,$e)
        try{ if(-not [bool]$script:Yum.SidebarPinnedByUser){ $want=($s.ActualWidth -lt 1240); if($want -ne [bool]$script:Yum.SidebarCompact){Set-YumSidebarCompact -Compact $want} } }catch{}
    })
    # Fit the first window inside the screen's work area.
    try{
        $wa=[System.Windows.SystemParameters]::WorkArea
        if($script:Yum.Window.Width -gt ($wa.Width-40)){$script:Yum.Window.Width=[math]::Max($script:Yum.Window.MinWidth,$wa.Width-40)}
        if($script:Yum.Window.Height -gt ($wa.Height-40)){$script:Yum.Window.Height=[math]::Max($script:Yum.Window.MinHeight,$wa.Height-40)}
    }catch{}
    Set-YumSidebarCompact -Compact $false
    Update-YumNavSelection -Key 'Overview'
}

# ---------------------------------------------------------------- global hotkey (Mem Reduct parity)
if(-not ('YumRamHotkey' -as [type])){
    Add-Type -ReferencedAssemblies PresentationCore,WindowsBase,PresentationFramework -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using System.Windows.Interop;
public class YumRamHotkey : IDisposable {
    [DllImport("user32.dll", SetLastError=true)] static extern bool RegisterHotKey(IntPtr hWnd, int id, uint fsModifiers, uint vk);
    [DllImport("user32.dll", SetLastError=true)] static extern bool UnregisterHotKey(IntPtr hWnd, int id);
    private HwndSource _source; private IntPtr _hwnd; private int _id;
    public bool Registered; public int LastError;
    public event EventHandler Pressed;
    public YumRamHotkey(IntPtr hwnd, int id, uint modifiers, uint vk) {
        _hwnd = hwnd; _id = id;
        _source = HwndSource.FromHwnd(hwnd);
        if (_source != null) { _source.AddHook(Hook); }
        Registered = RegisterHotKey(hwnd, id, modifiers | 0x4000u, vk); // MOD_NOREPEAT
        if (!Registered) { LastError = Marshal.GetLastWin32Error(); }
    }
    private IntPtr Hook(IntPtr hwnd, int msg, IntPtr wParam, IntPtr lParam, ref bool handled) {
        if (msg == 0x0312 && wParam.ToInt32() == _id) { handled = true; EventHandler h = Pressed; if (h != null) { h(this, EventArgs.Empty); } }
        return IntPtr.Zero;
    }
    public void Dispose() {
        try { if (Registered) { UnregisterHotKey(_hwnd, _id); } } catch { }
        Registered = false;
        try { if (_source != null) { _source.RemoveHook(Hook); } } catch { }
    }
}
'@
}

function ConvertFrom-YumHotkeyText {
    # "Ctrl+Alt+R" -> @{Modifiers=uint;Key=uint;Text='Ctrl+Alt+R'}; $null when invalid.
    param([string]$Text)
    if([string]::IsNullOrWhiteSpace($Text)){return $null}
    $mods=[uint32]0;$vk=[uint32]0;$parts=@()
    foreach($raw in ($Text -split '\+')){
        $p=$raw.Trim(); if(-not $p){continue}
        switch -Regex ($p){
            '^(ctrl|control)$'{$mods=$mods -bor 0x2;$parts+='Ctrl';continue}
            '^alt$'{$mods=$mods -bor 0x1;$parts+='Alt';continue}
            '^shift$'{$mods=$mods -bor 0x4;$parts+='Shift';continue}
            '^(win|windows)$'{$mods=$mods -bor 0x8;$parts+='Win';continue}
            default{
                $name=if($p -match '^\d$'){'D'+$p}else{$p}
                if($name -notmatch '^[A-Za-z][A-Za-z0-9]*$'){return $null}
                $key=[System.Windows.Input.Key]::None
                try{ $key=[System.Windows.Input.Key][Enum]::Parse([System.Windows.Input.Key],$name,$true) }catch{ return $null }
                if($key -eq [System.Windows.Input.Key]::None){return $null}
                if($vk -ne 0){return $null}
                $vk=[uint32][System.Windows.Input.KeyInterop]::VirtualKeyFromKey($key)
                $parts+=($p.Substring(0,1).ToUpperInvariant()+$p.Substring(1))
            }
        }
    }
    if($vk -eq 0 -or $mods -eq 0){return $null}   # a bare key would steal normal typing
    return [pscustomobject]@{Modifiers=$mods;Key=$vk;Text=($parts -join '+')}
}

function Register-YumGlobalHotkey {
    try{
        if($null -ne $script:Yum.Hotkey){ try{$script:Yum.Hotkey.Dispose()}catch{}; $script:Yum.Hotkey=$null }
        $script:Yum.HotkeyStatus='Off'
        if(-not [bool]$script:Yum.Config['GlobalHotkeyEnabled']){return}
        $spec=ConvertFrom-YumHotkeyText -Text ([string]$script:Yum.Config['GlobalHotkey'])
        if($null -eq $spec){ $script:Yum.HotkeyStatus='Invalid shortcut'; Write-YumLog ('Global hotkey "{0}" is not valid; use e.g. Ctrl+Alt+R.' -f [string]$script:Yum.Config['GlobalHotkey']); return }
        $hwnd=(New-Object System.Windows.Interop.WindowInteropHelper($script:Yum.Window)).EnsureHandle()
        $hk=New-Object YumRamHotkey($hwnd,0x5952,$spec.Modifiers,$spec.Key)
        if(-not $hk.Registered){ $hk.Dispose(); $script:Yum.HotkeyStatus=('{0} is used by another program' -f $spec.Text); Write-YumLog ('Global hotkey {0} could not be registered (Win32 error {1}); another program probably owns it.' -f $spec.Text,$hk.LastError); return }
        $hk.Add_Pressed({
            try{
                if(Request-YumMemoryReclaim -Mode Quick){
                    $script:Yum.TrayReclaimPending=$true
                    Set-YumFooter ('💜 Freeing RAM (hotkey {0})…' -f [string]$script:Yum.HotkeyText)
                    try{ if($null -ne $script:Yum.Ui.ReclaimStatus){$script:Yum.Ui.ReclaimStatus.Text='Freeing RAM… results appear in a few seconds.'} }catch{}
                    if(-not $script:Yum.Window.IsVisible){ Show-YumTrayNotice -Title 'YUMRAM' -Text 'Freeing RAM…' }
                }
            }catch{ Write-YumLogException -Context 'Hotkey Free RAM failed' -Exception $_.Exception }
        })
        $script:Yum.Hotkey=$hk
        $script:Yum.HotkeyText=$spec.Text
        $script:Yum.HotkeyStatus=('{0} frees RAM from anywhere' -f $spec.Text)
        Write-YumLog ('Global hotkey registered: {0} = Free RAM now.' -f $spec.Text)
    }catch{ $script:Yum.HotkeyStatus='Unavailable'; Write-YumLogException -Context 'Global hotkey registration failed' -Exception $_.Exception }
    finally{ try{ if($null -ne $script:Yum.Ui -and $null -ne $script:Yum.Ui['HotkeyHint']){ $script:Yum.Ui.HotkeyHint.Text=if([string]$script:Yum.HotkeyStatus -eq 'Off'){''}else{'⌨ '+[string]$script:Yum.HotkeyStatus} } }catch{} }
}

# ---------------------------------------------------------------- freed-RAM statistics (IObit / Wise parity)
function Get-YumStatsPath { return (Join-Path ([string]$script:Yum.ConfigDirectory) 'stats.json') }

function Get-YumFreedStats {
    if($null -ne $script:Yum.FreedStats){ return $script:Yum.FreedStats }
    $s=[ordered]@{Day=(Get-Date).ToString('yyyy-MM-dd');TodayGB=0.0;TodayRuns=0;TotalGB=0.0;TotalRuns=0;BestGB=0.0;Since=(Get-Date).ToString('yyyy-MM-dd')}
    try{
        $p=Get-YumStatsPath
        if(Test-Path -LiteralPath $p){
            $j=Get-Content -LiteralPath $p -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
            foreach($k in @($s.Keys)){ if($null -ne $j.PSObject.Properties[$k]){ $s[$k]=$j.$k } }
        }
    }catch{}
    $script:Yum.FreedStats=$s
    return $s
}

function Add-YumFreedStat {
    # Counts Available RAM actually gained (measured after Windows settles), never trimmed working set.
    param([double]$GainGB,[string]$Source='',[switch]$SameReclaim)
    try{
        if($GainGB -le 0.01){return}
        $s=Get-YumFreedStats
        $today=(Get-Date).ToString('yyyy-MM-dd')
        if([string]$s.Day -ne $today){$s.Day=$today;$s.TodayGB=0.0;$s.TodayRuns=0}
        $s.TodayGB=[math]::Round([double]$s.TodayGB+$GainGB,3);if(-not $SameReclaim){$s.TodayRuns=[int]$s.TodayRuns+1}
        $s.TotalGB=[math]::Round([double]$s.TotalGB+$GainGB,3);if(-not $SameReclaim){$s.TotalRuns=[int]$s.TotalRuns+1}
        if($GainGB -gt [double]$s.BestGB){$s.BestGB=[math]::Round($GainGB,3)}
        try{ ([pscustomobject]$s | ConvertTo-Json) | Set-Content -LiteralPath (Get-YumStatsPath) -Encoding UTF8 }catch{}
        Update-YumFreedStatsUi
    }catch{}
}

function Update-YumFreedStatsUi {
    try{
        $ui=$script:Yum.Ui; if($null -eq $ui -or $null -eq $ui['FreedToday']){return}
        $s=Get-YumFreedStats
        $today=(Get-Date).ToString('yyyy-MM-dd')
        $tGB=if([string]$s.Day -eq $today){[double]$s.TodayGB}else{0.0}
        $tRuns=if([string]$s.Day -eq $today){[int]$s.TodayRuns}else{0}
        $ui.FreedToday.Text=('{0:N1} GB' -f $tGB)
        $ui.FreedTodayRuns.Text=if($tRuns -eq 1){'1 reclaim today'}else{'{0} reclaims today' -f $tRuns}
        $ui.FreedTotal.Text=('{0:N1} GB' -f [double]$s.TotalGB)
        $ui.FreedTotalRuns.Text=('{0:N0} {1} since {2}' -f [int]$s.TotalRuns,$(if([int]$s.TotalRuns -eq 1){'reclaim'}else{'reclaims'}),[string]$s.Since)
    }catch{}
}
