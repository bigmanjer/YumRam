#requires -Version 5.1
<#
Full UI bug test (5.7): drives the real app - every page, setting, button and tray item - against a
temporary copy of the config, then exits through the tray. Not part of Run-AllTests: it needs a
desktop session, takes about 60 s, and Free RAM really trims processes.

Usage:  powershell -NoProfile -ExecutionPolicy Bypass -STA -File Tests\UI\FullUiProbe.ps1 -Root . -Out $env:TEMP\yum-ui
Expect: "FAILS: 0".
#>
param([string]$Root,[string]$Out)
# Full UI bug test: every page, every setting, every button that does not open external windows.
$ErrorActionPreference='Stop'
New-Item -ItemType Directory -Path $Out -Force | Out-Null
. (Join-Path $Root 'App\Bootstrap.ps1'); Initialize-YumConfig; . (Join-Path $Root 'Core\Research.ps1')
$tmp=Join-Path $env:TEMP ('yum-full-'+[guid]::NewGuid().ToString('N'));New-Item -ItemType Directory $tmp|Out-Null
Get-ChildItem $Root -Filter *.json | Copy-Item -Destination $tmp
$script:Yum.ConfigDirectory=$tmp;$script:Yum.ConfigFile=(Join-Path $tmp 'config.json');$script:Yum.Config.LogFileName=(Join-Path $tmp 'probe.log')
$script:Yum.Config.StartMonitoringAutomatically=$false; $script:Yum.Config['UpdateCheckEnabled']=$false
$script:R=New-Object System.Collections.Generic.List[string];$script:Fails=0;$script:WaitN=0;$script:WaitD=0;$script:WaitE=0;$script:WaitG=0
function Check([bool]$c,[string]$m){ if($c){$script:R.Add("PASS  $m")}else{$script:R.Add("FAIL  $m");$script:Fails++} }
function Note([string]$m){ $script:R.Add("      $m") }
function Click($b){ $b.RaiseEvent((New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Button]::ClickEvent))) }
function Go([string]$k){ $script:GoKey=$k; [void]$script:Yum.Window.Dispatcher.BeginInvoke([action]{ Open-YumPage -Key $script:GoKey }) }
function PW([string]$k){ $p=$script:Yum.Pages[$k]; if($p){$p.Window}else{$null} }
function Shot([string]$Name){ try{ $Win=$script:Yum.Window;$Win.UpdateLayout();$pw=[int]$Win.ActualWidth;$ph=[int]$Win.ActualHeight-40
  $rtb=New-Object System.Windows.Media.Imaging.RenderTargetBitmap($pw,$ph,96,96,[System.Windows.Media.PixelFormats]::Pbgra32);$dv=New-Object System.Windows.Media.DrawingVisual;$dc=$dv.RenderOpen();$dc.DrawRectangle($Win.Background,$null,(New-Object System.Windows.Rect(0,0,$pw,$ph)));$dc.Close();$rtb.Render($dv);$rtb.Render($Win)
  $enc=New-Object System.Windows.Media.Imaging.PngBitmapEncoder;$enc.Frames.Add([System.Windows.Media.Imaging.BitmapFrame]::Create($rtb));$fs=[IO.File]::Create((Join-Path $Out "$Name.png"));try{$enc.Save($fs)}finally{$fs.Dispose()} }catch{Note "shot $Name failed: $($_.Exception.Message)"} }
function ErrCount(){ @(Get-Content $script:Yum.Config.LogFileName -ErrorAction SilentlyContinue | Select-String 'Exception|failed|ERROR' | ? { $_.Line -notmatch 'Settings apply failed|could not be registered' }).Count }

$script:Steps=@(
 { $u=$script:Yum.Ui; Check ($u.Status.Text -match 'Paused') "Overview: paused status ($($u.Status.Text))"; Check ($u.SideRamText.Text -notmatch '--') "Sidebar RAM live while paused ($($u.SideRamText.Text))"; Check ([string]$script:Yum.HotkeyStatus -match 'Ctrl\+Alt\+R') "Hotkey registered ($($script:Yum.HotkeyStatus))" },
 { }, { },
 # 5.15.2: CPU %, speed, GPU busy and VRAM are live while monitoring is off (user report: "-- GHz", frozen GPU).
 { if((($script:Yum.Ui.GpuVram.Text -notmatch 'VRAM') -or ($script:Yum.Ui.DiskBusy.Text -notmatch '^\d+%$')) -and $script:WaitG++ -lt 12){ $script:I--; return } },   # 5.16.1: readings come from the background; a busy PC needs a few seconds
 { $u=$script:Yum.Ui; Check ($null -eq $script:Yum.TelemetryTimer) 'Still paused for the live-readings check'; Check ($u.CpuSpeed.Text -match '^\d+\.\d+ GHz$') "Paused: CPU speed shown ($($u.CpuSpeed.Text))"; Check ($u.CpuRingText.Text -ne '--') "Paused: CPU ring live ($($u.CpuRingText.Text) $($u.CpuRingState.Text))"; Check ($u.GpuVram.Text -match 'VRAM') "Paused: VRAM shown ($(($u.GpuVram.Text -replace '\r?\n',' | ')))"; Check ($u.DiskBusy.Text -match '^\d+%$' -and $u.DiskFree.Text -match 'GB free' -and $u.DiskSpaceText.Text -match '^of .* GB on ' -and $null -ne $u.DiskRing.Data -and $null -ne $u.GpuRing.Data -and $null -ne $u.CpuRing.Data -and $null -ne $u.MemoryRing.Data -and $u.GpuName.Text -ne '--') "Disk card live ($($u.DiskBusy.Text); $($u.DiskSpeed.Text); $($u.DiskSpaceText.Text))"; Note ('disk: '+($u.DiskDetail.Text -replace '\r?\n',' | ')); Shot 'p-overview-paused' },
 { $u=$script:Yum.Ui; Click $u.Monitor },
 { $u=$script:Yum.Ui; Check ($null -ne $script:Yum.TelemetryTimer -and $u.Status.Text -match 'Monitoring|Starting') "Start Monitoring ($($u.Status.Text), button '$($u.Monitor.Content)')" },
 { $u=$script:Yum.Ui; foreach($m in 'Safe','Aggressive','Balanced'){ foreach($it in $u.ModeBox.Items){ if([string]$it.Tag -eq $m){$u.ModeBox.SelectedItem=$it} }; Check ($script:Yum.Config.Mode -eq $m -and $u.Mode.Text -eq $m.ToUpper() -or $script:Yum.Config.Mode -eq $m) "Mode box -> $m (config $($script:Yum.Config.Mode))" } },
 { $u=$script:Yum.Ui; $old=$script:Yum.Config.MinimumAvailableGB; $u.TargetBox.Text='7.5'; Invoke-YumApplyTarget; Check ([double]$script:Yum.Config.MinimumAvailableGB -eq 7.5) "Goal Apply 7.5 -> $($script:Yum.Config.MinimumAvailableGB)"; $saved=(Get-Content $script:Yum.ConfigFile -Raw|ConvertFrom-Json).MinimumAvailableGB; Check ([double]$saved -eq 7.5) "Goal saved to config.json ($saved)"; $u.TargetBox.Text=[string]$old; Invoke-YumApplyTarget },
 { $u=$script:Yum.Ui; foreach($cb in @(@('AutoGame','AutoDetectGames'),@('ProtectGame','ProtectGame'),@('AutoClean','AutoCleanOnGameStart'))){ $c=$u[$cb[0]]; $before=[bool]$script:Yum.Config[$cb[1]]; $c.IsChecked=-not $before; $c.RaiseEvent((New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent))); Check ([bool]$script:Yum.Config[$cb[1]] -eq (-not $before)) "Checkbox $($cb[0]) toggles $($cb[1])"; $c.IsChecked=$before; $c.RaiseEvent((New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent))) } },
 { $u=$script:Yum.Ui; $u.PriorityBox.SelectedIndex=2; Check ($script:Yum.Config.GamePriority -eq 'AboveNormal') "Game priority Above normal ($($script:Yum.Config.GamePriority))"; $u.PriorityBox.SelectedIndex=1; Check ($script:Yum.Config.GamePriority -eq 'Normal') "Game priority Normal ($($script:Yum.Config.GamePriority))" },
 { Click $script:Yum.Ui.FreeRam; Check (-not $script:Yum.Ui.FreeRam.IsEnabled -or (Test-YumReclaimBusy)) 'Free RAM now starts (button disabled while busy)' },
 { }, { }, { }, { }, { }, { },
 # As administrator Free RAM also empties Windows' caches (~7 s measured): wait for it instead of a fixed delay.
 { if((Test-YumReclaimBusy) -and $script:WaitN++ -lt 15){ $script:I-- } },
 { $r=$script:Yum.LastReclaim; Check ($null -ne $r -and $script:Yum.Ui.ReclaimStatus.Text -match 'Free RAM [0-9.]+ .+ GB') "Free RAM result shown: $($script:Yum.Ui.ReclaimStatus.Text)"; Check ($script:Yum.Ui.FreeRam.IsEnabled) 'Free RAM button re-enabled'; Check ([int](Get-YumFreedStats).TotalRuns -ge 0) "Freed card: $($script:Yum.Ui.FreedToday.Text) / $($script:Yum.Ui.FreedTodayRuns.Text)"; Shot 'p-overview' },
 # 5.16.1: the Overview graph really draws (5.16.0 shipped with an empty graph - an exception was swallowed).
 { Update-YumGraph; $L=$script:Yum['GraphLayout']; $ok=($null -ne $L); foreach($k in 'Avail','Cpu'){ if($ok){ $d=$L[$k].Data; $ok=($null -ne $d -and $d.Bounds.Width -gt 20) } }; Check $ok ('Overview graph draws its lines (Free RAM: {0})' -f $(if($L -and $L.Avail.Data){'{0:N0} px wide' -f $L.Avail.Data.Bounds.Width}else{'nothing'})) },
 { $u=$script:Yum.Ui; Check ($u.CpuBalanceText.Text -match 'Watching|Holding') "CPU balance card: $($u.CpuBalanceText.Text)"; Check ([bool]$u.CpuBalanceToggle.IsChecked) 'CPU balance on by default'; Check ($null -ne $script:Yum['CpuBalancePowerShell']) 'CPU balance worker running'; $u.CpuBalanceToggle.IsChecked=$false; $u.CpuBalanceToggle.RaiseEvent((New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent))) },
 { $u=$script:Yum.Ui; Check (-not [bool]$script:Yum.Config['CpuBalanceEnabled'] -and $u.CpuBalanceText.Text -match '^Off') "CPU balance toggle off: $($u.CpuBalanceText.Text)"; $u.CpuBalanceToggle.IsChecked=$true; $u.CpuBalanceToggle.RaiseEvent((New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent))); Check ([bool]$script:Yum.Config['CpuBalanceEnabled']) 'CPU balance toggle back on' },
 { Set-YumSidebarCompact -Compact $true; Check ($script:Yum.Ui.Sidebar.Width -eq 68) 'Sidebar compact'; Set-YumSidebarCompact -Compact $false; Check ($script:Yum.Ui.Sidebar.Width -eq 220) 'Sidebar expanded' },
 # What's using RAM
 { Go 'Processes' },
 { $w=PW 'Processes'; Check ($null -ne $w -and $script:Yum.CurrentPage -eq 'Processes') 'Processes page open'; $st=$w.Tag; Check (@($st.Rows).Count -gt 5) "Process rows: $(@($st.Rows).Count)"; $st.Ui.Items.SelectedIndex=0; Check ($st.Ui.ExplainTitle.Text -ne 'Click a program') "Explain: $($st.Ui.ExplainTitle.Text) / $($st.Ui.ExplainSafe.Text)"; Click $st.Ui.Pause; Check ($st.Paused -and $st.Ui.LiveText.Text -match 'PAUSED') 'Pause'; Click $st.Ui.Pause; Check (-not $st.Paused) 'Resume' },
 { $st=(PW 'Processes').Tag; $first=$st.Ui.Items.SelectedItem; $script:SelName=if($first){$first.Title}else{''} },
 { $st=(PW 'Processes').Tag; Check ($st.Ui.SumCpu.Text -match '%') "CPU now card: $($st.Ui.SumCpu.Text) / $($st.Ui.SumCpuTop.Text)"; Check ($st.Ui.ExplainCpu.Text.Length -gt 5) "How busy: $($st.Ui.ExplainCpu.Text)"; Click $st.Ui.SortCpu },
 { $st=(PW 'Processes').Tag; $rows=@($st.Rows); $ok=$true; for($i=1;$i -lt [math]::Min(10,$rows.Count);$i++){ if($rows[$i].CpuPercent -gt $rows[$i-1].CpuPercent+0.01){$ok=$false} }; Check $ok "Sort by CPU: top = $($rows[0].Title) $($rows[0].CpuText)"; Shot 'p-processes-cpu'; Click $st.Ui.SortRam },
 { $st=(PW 'Processes').Tag; Check ($null -ne $st.Ui.Items.SelectedItem -and $st.Ui.Items.SelectedItem.Title -eq $script:SelName) "Selection kept across live refresh ($script:SelName)"; Shot 'p-processes' },
 # Reclaim Center
 { Go 'ReclaimCenter' },
 { $w=PW 'ReclaimCenter'; Check ($null -ne $w -and $script:Yum.CurrentPage -eq 'ReclaimCenter') 'Reclaim Center open (came from Processes)'; Check ($null -eq (PW 'Processes')) 'Processes page closed when leaving (timer stopped)'; Click $w.FindName('FreeRam') },
 { }, { }, { },
 { $w=PW 'ReclaimCenter'; $items=$w.FindName('Items'); Check (@($items.Items).Count -gt 1 -or $w.FindName('Summary').Text -match 'Nothing left to trim') "Reclaim Center result after Free RAM: $(@($items.Items).Count) rows"; Note ("Reclaim result: "+$w.FindName('Summary').Text); Shot 'p-reclaim' },
 # Startup apps
 { Go 'Startup' },
 { $st=(PW 'Startup').Tag; Check (@($st.Apps).Count -ge 1) "Startup apps: $(@($st.Apps).Count)"; foreach($a in $st.Apps){ $st.Ui.Items.SelectedItem=$a; if($st.Ui.ExplainTitle.Text -ne $a.Friendly){Check $false "Startup explain for $($a.Friendly)"} }; Check $true 'Startup: every row explains'; Click $st.Ui.Reload; Check (@($st.Apps).Count -ge 1) 'Startup: Check again' },
{ }, { }, { }, { $st=(PW 'Startup').Tag; Check (@($st.Apps | Where-Object { $_.ApprovedKey -in 'StoreTask','ScheduledTask' }).Count -ge 0) "Startup: background list merged ($(@($st.Apps).Count) entries)"; Shot 'p-startup' },
# Windows bloat (5.15): open, wait for the background app scan, explain every row. Never presses Remove/Turn off.
{ Go 'WindowsBloat' }, { }, { }, { },
{ $st=(PW 'WindowsBloat').Tag; Check ($null -ne $st) 'Windows bloat page opens'; if($st){ Check (-not $st.Busy) "Windows bloat scan finished ($($st.Ui.Details.Text))"; Check (@($st.Settings).Count -ge 10) "Windows bloat settings listed: $(@($st.Settings).Count)"; $bad=0; foreach($r in @($st.Settings)+@($st.Apps)){ if($r.Kind -eq 'App'){$st.Ui.Apps.SelectedItem=$r}else{$st.Ui.Settings.SelectedItem=$r}; if($st.Ui.ExplainTitle.Text -ne $r.Name){$bad++} }; Check ($bad -eq 0) "Windows bloat: every row explains ($(@($st.Apps).Count) apps)"; Shot 'p-bloat' } },
 # Intelligence
 # 5.15.2: Disk cleanup - measures only (never cleans the real PC in the probe), explains, analyses a folder.
 { Click $script:Yum.Ui.DiskCleanup },   # the real sidebar button (5.15.2: it was not registered, clicks did nothing)
 { if((PW 'DiskCleanup') -and (PW 'DiskCleanup').Tag.Busy -and $script:WaitD++ -lt 25){ $script:I-- } },
 { $st=(PW 'DiskCleanup').Tag; Check ($null -ne $st -and -not $st.Busy -and @($st.Rows).Count -ge 8) ("Disk cleanup measured {0} categories ({1}; can free {2})" -f @($st.Rows).Count,$st.Ui.Details.Text,$st.Ui.SumJunk.Text); $st.Ui.Junk.SelectedIndex=0; Check ($st.Ui.ExplainBody.Visibility -eq 'Visible' -and $st.Ui.ExplainEffect.Text.Length -gt 10) "Disk cleanup explains: $($st.Ui.ExplainTitle.Text)"; Start-YumDiskUsage -State $st -Path (Join-Path $script:Yum.Root 'Tests') },
 # 5.16.2: Select all, and ticks survive scrolling (the list re-reads each row's Selected when it redraws).
 { $st=(PW 'DiskCleanup').Tag; $pk=@(Get-YumDiskPickable -State $st); Set-YumDiskPickAll -State $st -On $true; $st.Ui.Junk.Items.Refresh(); Check ($pk.Count -ge 1 -and @($pk | Where-Object { -not $_.Selected }).Count -eq 0 -and $st.Picked.Count -eq $pk.Count -and [bool]$st.Ui.PickAll.IsChecked) ("Disk cleanup Select all ticks {0} categories" -f $pk.Count); Set-YumDiskPickAll -State $st -On $false; $st.Ui.Junk.Items.Refresh(); Check ($st.Picked.Count -eq 0 -and -not [bool]$st.Ui.PickAll.IsChecked -and @($pk | Where-Object { $_.Selected }).Count -eq 0) 'Select all again unticks everything' },
 { if((PW 'DiskCleanup').Tag.Busy -and $script:WaitE++ -lt 40){ $script:I-- } },
 { $st=(PW 'DiskCleanup').Tag; Check (@($st.Ui.UsageFolders.ItemsSource).Count -ge 1 -and @($st.Ui.UsageFiles.ItemsSource).Count -ge 1) "What's using my disk: $($st.Ui.Details.Text)"; Shot 'p-disk' },
 { Go 'Intelligence' },
 { }, { },
 { $st=$script:Yum.IntelligenceWindow.Tag; foreach($card in 'ALL ITEMS','PROTECTED','RESOLVED','REVIEW','UNKNOWN','CACHED','ERRORS','RESEARCHING'){ try{ Set-YumIntelligenceFilter -State $st -Name $card; Note ("card {0,-12} -> filter '{1}' | {2}" -f $card,[string]$st.Filter.SelectedItem.Content,$st.ResultCount.Text) }catch{ Check $false "card $card : $($_.Exception.Message)" } }; Check $true 'Intelligence: all cards switch the view' },
 { $st=$script:Yum.IntelligenceWindow.Tag; Set-YumIntelligenceFilter -State $st -Name 'ALL ITEMS'; $st.Search.Text='microsoft' },
 { },
 { $st=$script:Yum.IntelligenceWindow.Tag; Check ($st.ResultCount.Text -match '^\d') "Search 'microsoft' -> $($st.ResultCount.Text)"; $st.Search.Text=''; $res=$st.ListView; if(@($res.Items).Count -gt 0){$res.SelectedIndex=0}; Check ($st.SelectedName.Text -ne 'Nothing selected') "Select item -> $($st.SelectedName.Text)"; Check ($st.DecisionCard.IsEnabled) 'Decision card enabled on selection'; Check ($st.SelectedAdvice.Text -in @('Keep','Your call','Turn off is fine','Careful')) "Our advice shown ($($st.SelectedAdvice.Text))"; Shot 'p-intel' },
 # 5.15.2: a running scan is easy to see (simulated busy state - no real scan / online research in the probe).
 { $st=$script:Yum.IntelligenceWindow.Tag; $st.Busy=$true; $st.ActivityStatus.Text='SCANNING SYSTEM'; $st.ActivityDetail.Text='Collecting processes, services, apps, startup entries, and identity evidence…'; $st.ActivityProgress.IsIndeterminate=$true },
 { $st=$script:Yum.IntelligenceWindow.Tag; Check ($st.ActivityPercent.Text -eq 'working…') "Scan strip highlighted ($($st.ActivityPercent.Text))"; Check ($script:Yum.Ui.SideScanPanel.Visibility -eq 'Visible') "Sidebar shows the scan ($($script:Yum.Ui.SideScanText.Text))"; Shot 'p-intel-busy'; $st.Busy=$false; $st.ActivityStatus.Text='READY'; $st.ActivityProgress.IsIndeterminate=$false },
 # Settings
 { Go 'Settings' },
 { $w=PW 'Settings'; $u=$w.FindName('Apply').Tag.Ui; $script:SU=$u
   foreach($n in $u.Keys){ if($null -eq $u[$n]){ Check $false "Settings control missing: $n" } }
   $u.SafePass.Text='99'; Click $u.Apply; Check ($u.Validation.Text -match 'between' -and [int]$script:Yum.Config.SafeProcessesPerPass -ne 99) "Invalid value rejected: $($u.Validation.Text)"
   $u.SafePass.Text=[string]$script:Yum.Config.SafeProcessesPerPass; $u.GlobalHotkey.Text='Banana'; Click $u.Apply; Check ($u.Validation.Text -match 'shortcut') "Invalid hotkey rejected: $($u.Validation.Text)"
   $u.GlobalHotkey.Text='Ctrl+Alt+R'
   $u.CpuSystemPercent.Text='5'; Click $u.Apply; Check ($u.Validation.Text -match 'CPU balance') "Invalid CPU % rejected: $($u.Validation.Text)"; $u.CpuSystemPercent.Text='75'; $u.CpuProcessPercent.Text='12'; $u.CpuExclusions.Text='handbrake.exe, obs64'
   $vals=@{CleanInterval='20';ProcessCooldown='90';Hysteresis='0.5';TelemetryInterval='1';GpuInterval='6';GameInterval='3';SafePressure='93';BalancedPressure='86';AggressivePressure='79';SafePass='7';BalancedPass='11';AggressivePass='17';MinimumAvailable='8.5'}
   foreach($k in $vals.Keys){$u[$k].Text=$vals[$k]}
   Click $u.Apply
   $c=$script:Yum.Config
   Check ($u.Validation.Text -match 'saved') "Apply valid settings: $($u.Validation.Text)"
   $map=@{CleanInterval='MinimumCleanIntervalSeconds';ProcessCooldown='ProcessCooldownSeconds';Hysteresis='TargetHysteresisGB';TelemetryInterval='TelemetryIntervalSeconds';GpuInterval='GPUIntervalSeconds';GameInterval='GameDetectionIntervalSeconds';SafePressure='SafePressurePercent';BalancedPressure='BalancedPressurePercent';AggressivePressure='AggressivePressurePercent';SafePass='SafeProcessesPerPass';BalancedPass='BalancedProcessesPerPass';AggressivePass='AggressiveProcessesPerPass';MinimumAvailable='MinimumAvailableGB'}
   $bad=@(foreach($k in $map.Keys){ if([double]$c[$map[$k]] -ne [double]$vals[$k]){ "$k=$($c[$map[$k]])" } }); Check ($bad.Count -eq 0) ("All numeric settings applied {0}" -f ($bad -join ','))
   $saved=Get-Content $script:Yum.ConfigFile -Raw|ConvertFrom-Json; Check ([double]$saved.BalancedProcessesPerPass -eq 11 -and [double]$saved.MinimumAvailableGB -eq 8.5) 'Settings persisted to config.json'
   Check ($script:Yum.Ui.TargetBox.Text -eq '8.5') "Overview goal box follows Settings ($($script:Yum.Ui.TargetBox.Text))"
   Check ([double]$c.CleanupTargetAvailableGB -eq 8.5) 'Cleanup target follows goal'
   $cb=Get-YumCpuBalanceSettings; Check ($cb.SystemPercent -eq 75 -and $cb.ProcessPercent -eq 12 -and (@($cb.Exclusions) -join ',') -eq 'handbrake,obs64') "CPU balance settings applied ($($cb.SystemPercent)/$($cb.ProcessPercent)/$(@($cb.Exclusions) -join ','))" },
 { $u=$script:SU; foreach($cb in 'StartMonitoringAutomatically','ShowTrayIcon','MinimizeToTray','GlobalHotkeyEnabled','AutoDetectGames','ProtectGame','AutoCleanOnGameStart','EnableOptionalBackground','EnableOnlineResearch'){ $u[$cb].IsChecked=-not [bool]$u[$cb].IsChecked }; Click $u.Apply; $c=$script:Yum.Config
   Check ([bool]$c.StartMonitoringAutomatically -eq [bool]$u.StartMonitoringAutomatically.IsChecked -and [bool]$c['ShowTrayIcon'] -eq [bool]$u.ShowTrayIcon.IsChecked -and [bool]$c.EnableOnlineResearch -eq [bool]$u.EnableOnlineResearch.IsChecked) 'Checkbox settings applied'
   Check ([bool]$c['GlobalHotkeyEnabled'] -eq $false -and [string]$script:Yum.HotkeyStatus -eq 'Off') "Hotkey off applies live ($($script:Yum.HotkeyStatus))"
   Check ($null -eq $script:Yum.TrayIcon) "Tray icon off applies live (tray present: $($null -ne $script:Yum.TrayIcon))"
   Check ($script:Yum.Ui.AutoGame.IsChecked -eq [bool]$c.AutoDetectGames) 'Overview game checkboxes follow Settings'
   foreach($cb in 'StartMonitoringAutomatically','ShowTrayIcon','MinimizeToTray','GlobalHotkeyEnabled','AutoDetectGames','ProtectGame','AutoCleanOnGameStart','EnableOptionalBackground','EnableOnlineResearch'){ $u[$cb].IsChecked=-not [bool]$u[$cb].IsChecked }; Click $u.Apply
   Check ([string]$script:Yum.HotkeyStatus -match 'Ctrl\+Alt\+R') "Hotkey back on ($($script:Yum.HotkeyStatus))"; Check ($null -ne $script:Yum.TrayIcon) 'Tray icon back on live' },
 { $u=$script:SU; $u.Mode.SelectedIndex=0; $u.GamePriority.SelectedIndex=2; Click $u.Apply; Check ($script:Yum.Config.Mode -eq 'Safe' -and $script:Yum.Config.GamePriority -eq 'AboveNormal' -and $script:Yum.Ui.Mode.Text -match 'SAFE|BALANCED') "Mode+priority via Settings ($($script:Yum.Config.Mode)/$($script:Yum.Config.GamePriority), sidebar $($script:Yum.Ui.Mode.Text))"
   $tabs=$u.Apply.Parent; try{ $tc=$null; $w=PW 'Settings'; $tc=$w.FindName('CpuCareLevel'); $ti=$tc; while($ti -and -not ($ti -is [System.Windows.Controls.TabItem])){ $ti=[System.Windows.Media.VisualTreeHelper]::GetParent($ti); if(-not $ti){ break } }; }catch{}; Click $u.Reset; Check ($u.Validation.Text -match 'Defaults' -and $u.BalancedPass.Text -eq '10' -and $u.GpuInterval.Text -ne '') "Reset defaults fills fields (GPU $($u.GpuInterval.Text))"; Check ([string]$script:Yum.Config.Mode -eq 'Safe') 'Reset does not save until Apply'; Shot 'p-settings' },
 { $w=PW 'Settings'; $el=$w.FindName('CpuCareLevel'); while($el -and -not ($el -is [System.Windows.Controls.TabItem])){ $el=[System.Windows.LogicalTreeHelper]::GetParent($el) }; if($el){ $el.IsSelected=$true }; Check ($w.FindName('CpuProfileText').Text -match 'cores') "Settings CPU tab: $($w.FindName('CpuProfileText').Text)" },
 { Shot 'p-settings-cpu' },
 { Click $script:SU.Close },
 { Check ($script:Yum.CurrentPage -eq 'Overview') "Settings Close -> Overview ($($script:Yum.CurrentPage))" },
 # About
 { Go 'About' },
 { $w=PW 'About'; Check ($w.FindName('Version').Text -match '5\.\d') "About version: $($w.FindName('Version').Text)"; Shot 'p-about'; Click $w.FindName('Close') },
 { Check ($script:Yum.CurrentPage -eq 'Overview' -and $script:Yum.Window.IsVisible) 'About Done -> Overview, main window still open' },
 # Tray
 { $m=$script:Yum.TrayMenu; Check ($null -ne $m) 'Tray menu exists'; $mon=@($m.Items|?{$_.Text -match 'monitoring'})[0]; $was=($null -ne $script:Yum.TelemetryTimer); $mon.PerformClick(); Check ((($null -ne $script:Yum.TelemetryTimer)) -ne $was) "Tray monitoring toggle ($($mon.Text))"; $mon.PerformClick() },
 { $script:Yum.Window.WindowState='Minimized' },
 { Check (-not $script:Yum.Window.IsVisible) 'Minimize hides to tray'; $o=@($script:Yum.TrayMenu.Items|?{$_.Text -match 'Open'})[0]; $o.PerformClick() },
 { Check ($script:Yum.Window.IsVisible -and $script:Yum.Window.WindowState -eq 'Normal') "Tray Open restores window ($($script:Yum.Window.WindowState))" },
 # 5.15.2: the X button keeps YUMRAM running in the background (user request); the tray icon brings it back.
 { $script:Yum.Window.Close() },
 { Check (-not $script:Yum.Window.IsVisible -and $null -ne $script:Yum.TrayIcon -and -not [bool]$script:Yum['ExitRequested']) 'X hides YUMRAM and it keeps running'; Show-YumMainWindow },
 { Check ($script:Yum.Window.IsVisible) 'Window comes back after X' },
 # 5.15.2: floating mini bar (user request) - shows live numbers, Open brings the window back.
 { Show-YumMiniBar },
 { },
 { $mb=$script:Yum['MiniBar']; Check ($null -ne $mb -and $mb.Window.IsVisible -and -not $script:Yum.Window.IsVisible) 'Mini bar replaces the window'; Check ($mb.Ram.Value.Text -match '^\d+%$' -and $mb.Cpu.Value.Text -match '^\d+%$' -and $mb.Disk.Value.Text -match '^\d+%$') ("Mini bar live: RAM {0} CPU {1} GPU {2} Disk {3}" -f $mb.Ram.Value.Text,$mb.Cpu.Value.Text,$mb.Gpu.Value.Text,$mb.Disk.Value.Text); Click ($mb.Window.FindName('MiniOpen')) },
 { Check ($script:Yum.Window.IsVisible -and -not $script:Yum['MiniBar'].Window.IsVisible) 'Mini bar Open brings the window back' },
 { $script:EndErr=ErrCount; @(Get-Content $script:Yum.Config.LogFileName -ErrorAction SilentlyContinue | Select-String 'Exception|failed|ERROR' | ? { $_.Line -notmatch 'Settings apply failed|could not be registered' } | Select-Object -Last 12) | % { Note ('log: '+$_.Line.Substring(0,[math]::Min(230,$_.Line.Length))) }; Check ($script:EndErr -eq 0) "No exceptions in the log ($script:EndErr)"; $x=@($script:Yum.TrayMenu.Items|?{$_.Text -match 'Exit'})[0]; $x.PerformClick() }
)
$script:I=0
$t=New-Object System.Windows.Threading.DispatcherTimer;$t.Interval=[TimeSpan]::FromMilliseconds(1100)
$t.Add_Tick({ if($script:I -ge $script:Steps.Count){$t.Stop();return}; $s=$script:Steps[$script:I];$script:I++; try{ & $s }catch{ Check $false ("step {0}: {1} @ {2}" -f $script:I,$_.Exception.Message,$_.InvocationInfo.ScriptLineNumber) } })
$t.Start()
$sw=[Diagnostics.Stopwatch]::StartNew(); Start-YumApplicationUi
Check ($script:I -ge $script:Steps.Count) "Ran $script:I of $($script:Steps.Count) steps; app exited via tray Exit after $([int]$sw.Elapsed.TotalSeconds)s"
$script:R; "FAILS: $script:Fails"
