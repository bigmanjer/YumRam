#requires -Version 5.1


function Initialize-YumTheme {
    # 5.4: load UI\Xaml\Theme.xaml once into Application.Resources so every window shares one design
    # system (tokens + control styles). Windows are loaded with XamlReader and never call Application.Run,
    # but WPF still resolves StaticResource/implicit styles through Application.Current.Resources.
    if([bool]$script:YumThemeLoaded){return}
    $themePath=Join-Path $script:Yum.Root 'UI\Xaml\Theme.xaml'
    if(-not(Test-Path -LiteralPath $themePath)){return}
    $app=[System.Windows.Application]::Current
    if($null -eq $app){$app=New-Object System.Windows.Application;$app.ShutdownMode=[System.Windows.ShutdownMode]::OnExplicitShutdown}
    $theme=[Windows.Markup.XamlReader]::Parse([IO.File]::ReadAllText($themePath,[System.Text.UTF8Encoding]::new($false,$true)))
    $app.Resources.MergedDictionaries.Add($theme)
    $script:YumThemeLoaded=$true
}
$script:YumThemeLoaded=$false

function Read-YumXamlText {
    param([Parameter(Mandatory=$true)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        throw "XAML file not found: $Path"
    }
    try { Initialize-YumTheme } catch { try { Write-YumLogException -Context 'Theme load failed; using window styles' -Exception $_.Exception } catch {} }
    $utf8 = [System.Text.UTF8Encoding]::new($false,$true)
    return [System.IO.File]::ReadAllText($Path, $utf8)
}
function Test-YumAdministrator {
    try{$id=[Security.Principal.WindowsIdentity]::GetCurrent();$p=New-Object Security.Principal.WindowsPrincipal($id);return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)}catch{return $false}
}
function Start-YumElevated {
    if(Test-YumAdministrator){return $true}
    try{
        $scriptPath=Join-Path $script:Yum.Root 'App\YUMRAM.ps1'
        $powershell=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
        if(-not (Test-Path -LiteralPath $scriptPath)){throw "YUMRAM startup script not found: $scriptPath"}
        $quotedScript='"{0}"' -f ($scriptPath -replace '"','\"')
        $arguments='-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File {0}' -f $quotedScript
        Write-YumLog ('Requesting elevation for: {0}' -f $scriptPath)
        $proc=Start-Process -FilePath $powershell -Verb RunAs -WindowStyle Hidden -ArgumentList $arguments -WorkingDirectory $script:Yum.Root -PassThru -ErrorAction Stop
        if($null -eq $proc){throw 'Windows did not return an elevated process handle.'}
        Write-YumLog ('Elevated process launched successfully. PID={0}' -f $proc.Id)
        return $false
    }catch{
        Write-YumLogException -Context 'Elevation launch failed' -Exception $_.Exception
        try{[System.Windows.MessageBox]::Show(("YUMRAM could not start the elevated instance.`n`n{0}" -f $_.Exception.Message),'YUMRAM - Startup Error','OK','Error')|Out-Null}catch{}
        return $false
    }
}
function Get-YumBrush {param([string]$Hex) if($script:Yum.BrushCache.Contains($Hex)){return $script:Yum.BrushCache[$Hex]} $b=New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.ColorConverter]::ConvertFromString($Hex));try{$b.Freeze()}catch{};$script:Yum.BrushCache[$Hex]=$b;return $b}
function Set-YumFooter {param([string]$Text) try{$script:Yum.Ui.Footer.Text=$Text}catch{}}
function Update-YumGraph {
    try{
        $canvas=$script:Yum.Ui.Graph
        $w=[double]$canvas.ActualWidth
        $h=[double]$canvas.ActualHeight
        if($w -le 10 -or $h -le 10){return}
        if(-not $script:Yum.GraphInitialized){
            foreach($percent in @(0,25,50,75,100)){
                $y=$h-(($percent/100)*$h)
                $line=New-Object System.Windows.Shapes.Line
                $line.X1=0;$line.X2=$w;$line.Y1=$y;$line.Y2=$y
                $line.Stroke=Get-YumBrush '#321B42';$line.StrokeThickness=1
                [void]$canvas.Children.Add($line)
            }
            foreach($spec in @(
                @{Key='GraphMemoryLine';Brush='#CFA8FF'},
                @{Key='GraphMemoryAvailableLine';Brush='#86EFAC'},
                @{Key='GraphCPULine';Brush='#FF9ECD'},
                @{Key='GraphGPULine';Brush=$script:Yum.Config.GPUColor}
            )){
                $pl=New-Object System.Windows.Shapes.Polyline
                $pl.Stroke=Get-YumBrush $spec.Brush
                $pl.StrokeThickness=2
                $pl.SnapsToDevicePixels=$true
                $script:Yum[$spec.Key]=$pl
                [void]$canvas.Children.Add($pl)
            }
            $script:Yum.GraphInitialized=$true
        }
        $step=$w/[math]::Max(1,$script:Yum.GraphPointsLimit-1)

        # CPU/GPU retain a true 0-100% scale.
        $fixedSeries=@(
            @{Values=$script:Yum.GraphCPU;Line=$script:Yum.GraphCPULine},
            @{Values=$script:Yum.GraphGPU;Line=$script:Yum.GraphGPULine}
        )
        foreach($s in $fixedSeries){
            $points=$s.Line.Points;$points.Clear()
            if($s.Values.Count -lt 2){continue}
            $step=$w/[math]::Max(1,$s.Values.Count-1)
            for($i=0;$i -lt $s.Values.Count;$i++){
                $v=[math]::Max(0,[math]::Min(100,[double]$s.Values[$i]))
                [void]$points.Add((New-Object System.Windows.Point(($i*$step),($h-(($v/100)*$h)))))
            }
        }

        # RAM uses one shared auto-scaled range so Used and Available remain truthful relative to each other.
        $memorySeries=@(
            @{Values=$script:Yum.GraphMemory;Line=$script:Yum.GraphMemoryLine},
            @{Values=$script:Yum.GraphMemoryAvailable;Line=$script:Yum.GraphMemoryAvailableLine}
        )
        # 5.8.1: plain loops instead of pipelines + Measure-Object (ran 2x per second).
        $valCount=0;$min=[double]::MaxValue;$max=[double]::MinValue
        foreach($s in $memorySeries){foreach($v in $s.Values){$valCount++;$d=[double]$v;if($d -lt $min){$min=$d};if($d -gt $max){$max=$d}}}
        if($valCount -ge 2){
            $span=$max-$min
            $minimumSpan=6.0
            if($span -lt $minimumSpan){
                $mid=($min+$max)/2;$min=$mid-($minimumSpan/2);$max=$mid+($minimumSpan/2)
            } else {
                $padding=[math]::Max(1.0,$span*0.10);$min-=$padding;$max+=$padding
            }
            if($min -lt 0){$min=0};if($max -gt 100){$max=100}
            if(($max-$min) -lt 0.5){$max=[math]::Min(100,$min+0.5)}
            $localSpan=[math]::Max(0.5,$max-$min)
            foreach($s in $memorySeries){
                $points=$s.Line.Points;$points.Clear();if($s.Values.Count -lt 2){continue}
                $step=$w/[math]::Max(1,$s.Values.Count-1)
                for($i=0;$i -lt $s.Values.Count;$i++){
                    $v=[math]::Max($min,[math]::Min($max,[double]$s.Values[$i]));$normalized=($v-$min)/$localSpan
                    [void]$points.Add((New-Object System.Windows.Point(($i*$step),($h-($normalized*$h)))))
                }
            }
        }
    }catch{Write-YumLogException -Context 'Graph update failed' -Exception $_.Exception}
}
function Get-YumUiSnapshot {return Get-YumSnapshotCopy}
function Update-YumMemoryRing {
    # 5.4: RAM-in-use gauge. Draws an arc from 12 o'clock clockwise, sized to the ring's Grid.
    param([double]$Percent)
    try{
        $ring=$script:Yum.Ui.MemoryRing;$label=$script:Yum.Ui.MemoryRingText
        if($null -eq $ring){return}
        $p=[math]::Min(99.99,[math]::Max(0.0,$Percent))
        if($null -ne $label){$label.Text=('{0:N0}%' -f $Percent)}
        $size=104.0;$thick=10.0;$r=($size-$thick)/2.0;$c=$size/2.0
        $angle=($p/100.0)*2*[math]::PI
        $start=New-Object System.Windows.Point($c,($c-$r))
        $end=New-Object System.Windows.Point(($c+$r*[math]::Sin($angle)),($c-$r*[math]::Cos($angle)))
        $fig=New-Object System.Windows.Media.PathFigure;$fig.StartPoint=$start;$fig.IsClosed=$false
        $arc=New-Object System.Windows.Media.ArcSegment($end,(New-Object System.Windows.Size($r,$r)),0.0,($p -gt 50),[System.Windows.Media.SweepDirection]::Clockwise,$true)
        [void]$fig.Segments.Add($arc)
        $geo=New-Object System.Windows.Media.PathGeometry;[void]$geo.Figures.Add($fig);$geo.Freeze()
        $ring.Data=$geo
        # Colour by pressure: calm below 70%, amber to 85%, red above.
        $ring.Stroke=if($Percent -ge 85){Get-YumBrush '#F87171'}elseif($Percent -ge 70){Get-YumBrush '#FBBF24'}else{Get-YumBrush '#CFA8FF'}
    }catch{}
}
function Update-YumTargetUi {
    try {
        $s=Get-YumSnapshotCopy
        if($null -eq $s -or $null -eq $s.Memory -or $null -eq $script:Yum.Ui.TargetBox){return}
        $m=$s.Memory
        $target=[double]$script:Yum.Config.MinimumAvailableGB
        if($target -le 0){$target=0.1}
        $ratio=[math]::Min(100,([double]$m.AvailableGB/$target)*100)
        $text='Available: {0:N1} GB / Target: {1:N1} GB ({2:N0}%)' -f $m.AvailableGB,$target,$ratio
        # 5.3.2: show what this PC can realistically reach right now (current Available + what the
        # current mode may trim x the retention learned on this machine).
        $est=$script:Yum.ReachableEstimate
        $outOfReach=$false
        if($null -ne $est){
            $reachable=[double]$m.AvailableGB+[double]$est.ReclaimableGB
            $outOfReach=($m.AvailableGB -lt $target -and $reachable -lt ($target-0.1))
            $text+=(' • reachable ≈ {0:N1} GB' -f $reachable)
            $learned=if([int]$est.RetentionSamples -ge 2){'learned on this PC from {0} reclaims' -f [int]$est.RetentionSamples}else{'default until YUMRAM has measured this PC'}
            $script:Yum.Ui.Target.ToolTip=("Reachable now ≈ {0:N1} GB = Available {1:N1} GB + {2:N1} GB that {3} mode may reclaim.`n{4} trimmable processes ({5:N0} MB) × {6:P0} retention ({7}).`nOnly part of trimmed memory becomes Available; Windows needs it for active apps." -f $reachable,$m.AvailableGB,[double]$est.ReclaimableGB,$est.Mode,[int]$est.CandidateCount,[double]$est.CandidateMB,[double]$est.Retention,$learned)
        }
        $script:Yum.Ui.Target.Text=$text
        $script:Yum.Ui.TargetBar.Value=$ratio
        $script:Yum.Ui.TargetStatus.Text=if($m.AvailableGB -ge $target){'[OK]'}elseif($outOfReach){'[OUT OF REACH]'}else{'[LOW]'}
        if($m.AvailableGB -ge $target){$brush='#86EFAC'}elseif($outOfReach -or $m.AvailableGB -ge ($target*.75)){$brush='#FDE68A'}else{$brush='#FCA5A5'}
        $script:Yum.Ui.TargetStatus.Foreground=Get-YumBrush $brush
        $script:Yum.Ui.TargetBar.Foreground=Get-YumBrush $brush
    } catch { Write-YumLogException -Context 'Target UI update failed' -Exception $_.Exception }
}
function Update-YumUiFromSnapshot {
    try{
        $s=Get-YumUiSnapshot
        if($null -eq $s -or $null -eq $s.Memory){return}
        $newSnapshot=($script:Yum.SnapshotVersion -ne $script:Yum.LastUiSnapshotVersion)
        $m=$s.Memory
        $target=[double]$script:Yum.Config.MinimumAvailableGB
        if($target -le 0){$target=0.1}
        # 5.8.1 (measured: ~24% of one core at idle): draw only what is on screen. Hidden in the tray =
        # tray icon only; another page = sidebar only. History keeps recording, so the graph is whole
        # when you come back. Telemetry reads this flag to skip GPU sampling (display-only, ~0.25 s CPU).
        $windowShown=$false;try{$windowShown=[bool]$script:Yum.Window.IsVisible -and $script:Yum.Window.WindowState -ne [System.Windows.WindowState]::Minimized}catch{}
        $overviewShown=($windowShown -and [string]$script:Yum.CurrentPage -eq 'Overview')
        try{ if($null -ne $script:Yum.TelemetryCache){ $script:Yum.TelemetryCache['UiWantsGpu']=$overviewShown } }catch{}
        if($newSnapshot -and -not $overviewShown){
            $script:Yum.LastUiSnapshotVersion=$script:Yum.SnapshotVersion
            $availablePctH=if([double]$m.TotalGB -gt 0){([double]$m.AvailableGB/[double]$m.TotalGB)*100}else{0}
            foreach($pair in @(@($script:Yum.GraphMemory,[double]$m.UsedPercent),@($script:Yum.GraphMemoryAvailable,[double]$availablePctH),@($script:Yum.GraphCPU,[double]$s.CPU),@($script:Yum.GraphGPU,[double]$s.GPU3D))){[void]$pair[0].Add($pair[1]);while($pair[0].Count -gt $script:Yum.GraphPointsLimit){$pair[0].RemoveAt(0)}}
            Update-YumTray -Percent ([double]$m.UsedPercent) -AvailableGB ([double]$m.AvailableGB)
            if($windowShown){Update-YumSidebarStatus -UsedPercent ([double]$m.UsedPercent) -AvailableGB ([double]$m.AvailableGB) -TotalGB ([double]$m.TotalGB)}
            $script:Yum.UiNeedsFullRefresh=$true
            $newSnapshot=$false
        }
        $forcedRefresh=$false
        if($overviewShown -and [bool]$script:Yum['UiNeedsFullRefresh']){$script:Yum.UiNeedsFullRefresh=$false;$forcedRefresh=(-not $newSnapshot);$newSnapshot=$true}
        if($newSnapshot){
            $script:Yum.LastUiSnapshotVersion=$script:Yum.SnapshotVersion
            $script:Yum.Ui.Available.Text='{0:N2} GB' -f $m.AvailableGB
            $script:Yum.Ui.Memory.Text='{0:N1}%' -f $m.UsedPercent
            $script:Yum.Ui.CPU.Text='{0:N1}%' -f $s.CPU
            $script:Yum.Ui.GPU.Text='{0:N1}%' -f $s.GPU3D
            $script:Yum.Ui.Game.Text=if($s.Game.Detected){$s.Game.ProcessName}else{'None'}
            $availablePct=if([double]$m.TotalGB -gt 0){([double]$m.AvailableGB/[double]$m.TotalGB)*100}else{0}
            $script:Yum.Ui.Usage.Text='{0:N2} / {1:N2} GB  •  Available {2:N2} GB ({3:N1}%)' -f $m.UsedGB,$m.TotalGB,$m.AvailableGB,$availablePct
            $script:Yum.Ui.MemoryBar.Value=[math]::Min(100,[math]::Max(0,$m.UsedPercent))
            Update-YumMemoryRing -Percent ([double]$m.UsedPercent)
            Update-YumTray -Percent ([double]$m.UsedPercent) -AvailableGB ([double]$m.AvailableGB)
            Update-YumSidebarStatus -UsedPercent ([double]$m.UsedPercent) -AvailableGB ([double]$m.AvailableGB) -TotalGB ([double]$m.TotalGB)
            if(-not $forcedRefresh){[void]$script:Yum.GraphMemory.Add([double]$m.UsedPercent)};while($script:Yum.GraphMemory.Count -gt $script:Yum.GraphPointsLimit){$script:Yum.GraphMemory.RemoveAt(0)}
            if(-not $forcedRefresh){[void]$script:Yum.GraphMemoryAvailable.Add([double]$availablePct)};while($script:Yum.GraphMemoryAvailable.Count -gt $script:Yum.GraphPointsLimit){$script:Yum.GraphMemoryAvailable.RemoveAt(0)}
            if(-not $forcedRefresh){[void]$script:Yum.GraphCPU.Add([double]$s.CPU)};while($script:Yum.GraphCPU.Count -gt $script:Yum.GraphPointsLimit){$script:Yum.GraphCPU.RemoveAt(0)}
            if(-not $forcedRefresh){[void]$script:Yum.GraphGPU.Add([double]$s.GPU3D)};while($script:Yum.GraphGPU.Count -gt $script:Yum.GraphPointsLimit){$script:Yum.GraphGPU.RemoveAt(0)}
            Update-YumTargetUi
            $script:Yum.Ui.Mode.Text=$script:Yum.Config.Mode.ToUpperInvariant()
            Update-YumGraph
        }
        $coreTimestamp=$script:Yum.LastCoreTelemetryUpdate
        if($coreTimestamp -eq [datetime]::MinValue){$coreTimestamp=$s.Timestamp}
        $age=((Get-Date)-$coreTimestamp).TotalSeconds
        $gpuAge=if($script:Yum.LastGpuSample -eq [datetime]::MinValue){999}else{((Get-Date)-$script:Yum.LastGpuSample).TotalSeconds}
        $gameAge=if($script:Yum.LastGameSample -eq [datetime]::MinValue){999}else{((Get-Date)-$script:Yum.LastGameSample).TotalSeconds}
        if($null -ne $script:Yum.Ui.TelemetryStatus){$script:Yum.Ui.TelemetryStatus.Text=('Telemetry: {0:N1}s | GPU {1:N1}s | Game {2:N1}s' -f $age,$gpuAge,$gameAge)};if($null -ne $script:Yum.Ui.QuickMonitorTelemetry){$script:Yum.Ui.QuickMonitorTelemetry.Text=('Telemetry: {0:N1}s ago' -f $age)}
        # 5.7: monitoring paused is not a fault. It used to show "Telemetry delayed" and a frozen "--%" in the
        # sidebar/tray; now it says Paused and keeps RAM readings live with one cheap read every 2 s.
        if($null -eq $script:Yum.TelemetryTimer){
            $script:Yum.Ui.Status.Text='● Paused';$script:Yum.Ui.Status.Foreground=Get-YumBrush '#FDE68A'
            if(((Get-Date)-[datetime]$script:Yum.LastPausedMemoryRead).TotalSeconds -ge 2){
                $script:Yum.LastPausedMemoryRead=Get-Date
                try{$pm=Get-YumMemoryTelemetry;if($null -ne $pm){Update-YumSidebarStatus -UsedPercent ([double]$pm.UsedPercent) -AvailableGB ([double]$pm.AvailableGB) -TotalGB ([double]$pm.TotalGB);Update-YumTray -Percent ([double]$pm.UsedPercent) -AvailableGB ([double]$pm.AvailableGB);Update-YumMemoryRing -Percent ([double]$pm.UsedPercent);$script:Yum.Ui.Available.Text='{0:N2} GB' -f $pm.AvailableGB;try{Update-YumSnapshotMemory -Memory $pm}catch{};$script:Yum.UiNeedsFullRefresh=$true}}catch{}
            }
            if($null -ne $script:Yum.Ui.TelemetryStatus){$script:Yum.Ui.TelemetryStatus.Text='Monitoring paused'};if($null -ne $script:Yum.Ui.QuickMonitorTelemetry){$script:Yum.Ui.QuickMonitorTelemetry.Text='Automatic care is off.'}
            return
        }
        # 5.8: just started (or resumed) and no new sample yet - say so instead of 'Paused' / 'delayed'.
        $startedAt=[datetime]::MinValue;try{$startedAt=[datetime]$script:Yum['MonitoringStartedAt']}catch{}
        if($script:Yum.LastCoreTelemetryUpdate -lt $startedAt -and ((Get-Date)-$startedAt).TotalSeconds -lt 5){$script:Yum.Ui.Status.Text='● Starting…';$script:Yum.Ui.Status.Foreground=Get-YumBrush '#FDE68A';return}
        if($age -gt 3){$script:Yum.Ui.Status.Text='⚠ Telemetry delayed';$script:Yum.Ui.Status.Foreground=Get-YumBrush '#FDE68A';Set-YumFooter ('⚠ Telemetry delayed — last sample {0:N1}s ago.' -f $age)}elseif($null -ne $script:Yum.TelemetryTimer -and $script:Yum.LastCoreTelemetryUpdate -ne [datetime]::MinValue){$script:Yum.Ui.Status.Text='● Monitoring';$script:Yum.Ui.Status.Foreground=Get-YumBrush $script:Yum.Config.GPUColor;$pressure=Get-YumPressureDecision -Memory $m -Mode $script:Yum.Config.Mode;if($pressure.Emergency){Set-YumFooter '⚠ Emergency memory pressure — reclaim is needed.'}elseif($m.AvailableGB -lt $target){Set-YumFooter ('💜 Below configured target — seeking {0:N2} GB available.' -f $target)}elseif($pressure.ShouldClean){Set-YumFooter '💜 Elevated memory pressure — monitoring closely.'}else{Set-YumFooter ('Everything looks comfy 💜  •  Available {0:N2} GB  •  Target {1:N2} GB' -f $m.AvailableGB,$target)}}else{$script:Yum.Ui.Status.Text='● Paused';$script:Yum.Ui.Status.Foreground=Get-YumBrush '#FDE68A'}
    }catch{Write-YumLogException -Context 'UI refresh failed' -Exception $_.Exception}
}
function Apply-YumUiConfig {
    $script:Yum.SuppressUiEvents=$true
    try{
        $modeTags=@('Safe','Balanced','Aggressive');$modeItems=@($script:Yum.Ui.ModeBox.Items);for($i=0;$i -lt $modeItems.Count;$i++){if([string]$modeItems[$i].Tag -eq [string]$script:Yum.Config.Mode){$script:Yum.Ui.ModeBox.SelectedIndex=$i;break}}
        $priorityDisplay=@('Keep Existing','Normal (Default)','Above Normal (Game Preference)','High (Advanced)')
        $priorityLabel = switch ([string]$script:Yum.Config.GamePriority) {
            'KeepExisting' { 'Keep Existing' }
            'AboveNormal' { 'Above Normal (Game Preference)' }
            'High' { 'High (Advanced)' }
            default { 'Normal (Default)' }
        }
        $script:Yum.Ui.PriorityBox.SelectedIndex=[array]::IndexOf($priorityDisplay,$priorityLabel)
        if($null -ne $script:Yum.Ui.ModeHelp){$script:Yum.Ui.ModeHelp.Text=switch([string]$script:Yum.Config.Mode){'Safe'{'Minimal intervention — low-risk candidates only, up to 8 follow-up passes, no optional apps/services.'};'Aggressive'{'Maximum reclaim — broader known-safe candidates, approved optional apps/services, repeated passes toward the target.'};default{'Recommended balance — moderate candidates and repeated passes toward the target without touching protected/unknown items.'}}}
        $script:Yum.Ui.TargetBox.Text=$script:Yum.Config.MinimumAvailableGB.ToString('0.##',[Globalization.CultureInfo]::InvariantCulture)
        # 5.7: the sidebar Mode badge followed only telemetry ticks, so a mode change in Settings looked ignored.
        if($null -ne $script:Yum.Ui.Mode){$script:Yum.Ui.Mode.Text=([string]$script:Yum.Config.Mode).ToUpperInvariant()}
        $script:Yum.Ui.AutoGame.IsChecked=[bool]$script:Yum.Config.AutoDetectGames
        $script:Yum.Ui.ProtectGame.IsChecked=[bool]$script:Yum.Config.ProtectGame
        $script:Yum.Ui.AutoClean.IsChecked=[bool]$script:Yum.Config.AutoCleanOnGameStart
        if($null -ne $script:Yum.Ui.CpuBalanceToggle){$script:Yum.Ui.CpuBalanceToggle.IsChecked=[bool](Get-YumCpuBalanceSettings).Enabled}
    }finally{$script:Yum.SuppressUiEvents=$false}
}
function Update-YumUpdateUi {
    # 5.10: picks up a finished background update check and shows the banner once something is available.
    try{
        $r=Receive-YumUpdateCheck
        if($null -eq $r){return}
        $ui=$script:Yum.Ui
        if([string]$r.Status -eq 'Available'){
            $ui.UpdateTitle.Text=('YUMRAM {0} is available' -f $r.Latest)
            $ui.UpdateText.Text=('You have {0}. The download is checked against its published SHA-256 before anything is installed; your settings and statistics are kept, and the current version is kept so you can go back.' -f $r.Current)
            $ui.UpdateBanner.Visibility='Visible'
            if(-not $script:Yum.Window.IsVisible){Show-YumTrayNotice -Title ('YUMRAM {0} is available' -f $r.Latest) -Text 'Open YUMRAM to install it.'}
        } else { $ui.UpdateBanner.Visibility='Collapsed' }
        # About shows the latest status if it is open.
        try{ $a=$script:Yum.Pages['About']; if($null -ne $a){ $a.Window.FindName('UpdateStatus').Text=[string]$r.Message } }catch{}
    }catch{ Write-YumLogException -Context 'Update UI failed' -Exception $_.Exception }
}
function Invoke-YumInstallUpdate {
    $info=$script:Yum['UpdateInfo']
    if($null -eq $info -or [string]$info.Status -ne 'Available'){return}
    $script:Yum.Ui.UpdateInstall.IsEnabled=$false;$script:Yum.Ui.UpdateText.Text='Downloading and verifying…'
    Set-YumFooter 'Downloading the update…'
    $script:Yum.Window.Dispatcher.Invoke([action]{},[System.Windows.Threading.DispatcherPriority]::Background)
    $r=Install-YumUpdate -Info $info
    if($r.Success){Set-YumFooter ([string]$r.Message);$script:Yum.Ui.UpdateText.Text=[string]$r.Message;$script:Yum.Window.Close()}
    else{$script:Yum.Ui.UpdateInstall.IsEnabled=$true;$script:Yum.Ui.UpdateText.Text=('Not installed: {0}' -f $r.Message);Set-YumFooter ('⚠ Update not installed: '+[string]$r.Message)}
}
function Update-YumCpuBalanceUi {
    try{
        $ui=$script:Yum.Ui;if($null -eq $ui -or $null -eq $ui['CpuBalanceText']){return}
        $s=Get-YumCpuBalanceSummary
        $ui.CpuBalanceText.Text=[string]$s.Text
        $ui.CpuBalanceCount.Text=if(-not $s.Count){''}elseif([string]$s.Count -match '^0 '){'Has not needed to step in today.'}else{'Stepped in '+[string]$s.Count+'.'}
        $ui.CpuBalancePill.Visibility=if($s.Active){'Visible'}else{'Collapsed'}
    }catch{}
}
function Start-YumMonitoring {
    if($null -ne $script:Yum.TelemetryTimer){return}
    $script:Yum.StopRequested=$false
    Start-YumTelemetry
    $script:Yum.MonitoringActive=$true
    $script:Yum['MonitoringStartedAt']=Get-Date
    Start-YumControllerTimer;$script:Yum.Ui.Monitor.Content='■ Stop Monitoring';$script:Yum.Ui.Status.Text='● Monitoring';if($null -ne $script:Yum.Ui.QuickMonitorStatus){$script:Yum.Ui.QuickMonitorStatus.Text='ACTIVE';$script:Yum.Ui.QuickMonitorStatus.Foreground=Get-YumBrush $script:Yum.Config.GPUColor};$script:Yum.Ui.Status.Foreground=Get-YumBrush $script:Yum.Config.GPUColor;Write-YumLog 'Monitoring started.'
}
function Stop-YumMonitoring {
    $script:Yum.MonitoringActive=$false
    Stop-YumTelemetry;$script:Yum.Ui.Monitor.Content='▶ Start Monitoring';$script:Yum.Ui.Status.Text='● Paused';if($null -ne $script:Yum.Ui.QuickMonitorStatus){$script:Yum.Ui.QuickMonitorStatus.Text='PAUSED';$script:Yum.Ui.QuickMonitorStatus.Foreground=Get-YumBrush '#FDE68A'};$script:Yum.Ui.Status.Foreground=Get-YumBrush '#FDE68A';Write-YumLog 'Monitoring stopped.'
}
function Invoke-YumApplyTarget {
    try{$v=0.0;$ok=[double]::TryParse($script:Yum.Ui.TargetBox.Text.Trim(),[Globalization.NumberStyles]::Float,[Globalization.CultureInfo]::InvariantCulture,[ref]$v);if(-not $ok -or $v -le 0){Show-YumMessage -Message 'Enter a valid Available RAM target greater than 0 GB.' -Title 'YUMRAM - Invalid Target' -Buttons 'OK' -Icon 'Warning';return};$s=Get-YumSnapshotCopy;$m=if($s){$s.Memory}else{Get-YumMemoryTelemetry};if($null -eq $m -or $v -gt $m.TotalGB){Show-YumMessage -Message 'The target must be greater than 0 and no more than installed RAM.' -Title 'YUMRAM - Invalid Target' -Buttons 'OK' -Icon 'Warning';return};$v=[math]::Round($v,1);Update-YumConfigValue -Name MinimumAvailableGB -Value $v;Update-YumConfigValue -Name CleanupTargetAvailableGB -Value $v;$script:Yum.Ui.TargetBox.Text=$v.ToString('0.##');$script:Yum.ControllerBackoffSeconds=0.0;Update-YumTargetUi;$est=$script:Yum.ReachableEstimate;if($null -ne $est -and $v -gt ([double]$m.AvailableGB+[double]$est.ReclaimableGB+0.1)){Set-YumFooter ("Target set to {0} GB 💜 — note: about {1:N1} GB is reachable right now on this PC; YUMRAM will keep working toward it and back off between attempts." -f $v,([double]$m.AvailableGB+[double]$est.ReclaimableGB))}else{Set-YumFooter "Target updated to $v GB 💜"};Write-YumLog "Minimum Available RAM target changed to $v GB."}catch{Write-YumLogException -Context 'Target apply failed' -Exception $_.Exception}
}
function Test-YumSingleInstance {try{$mutex=New-Object System.Threading.Mutex($false,'Local\YUMRAM-V5-SingleInstance');$owned=$false;try{$owned=$mutex.WaitOne(0)}catch [System.Threading.AbandonedMutexException]{$owned=$true};if(-not $owned){$mutex.Dispose();[System.Windows.MessageBox]::Show('YUMRAM is already running.','YUMRAM','OK','Information')|Out-Null;return $false};$script:Yum.SingleInstanceMutex=$mutex;$script:Yum.SingleInstanceOwned=$true;return $true}catch{Write-YumLogException -Context 'Single instance check failed' -Exception $_.Exception;return $true}}
function Stop-YumSingleInstance {try{if($script:Yum.SingleInstanceOwned -and $script:Yum.SingleInstanceMutex){try{$script:Yum.SingleInstanceMutex.ReleaseMutex()}catch{};$script:Yum.SingleInstanceMutex.Dispose()}}catch{}finally{$script:Yum.SingleInstanceMutex=$null;$script:Yum.SingleInstanceOwned=$false}}
function Start-YumApplicationUi {
    $path=Join-Path $script:Yum.Root 'UI\Xaml\MainWindow.xaml';if(-not(Test-Path -LiteralPath $path)){throw "Missing main window XAML: $path"};[xml]$xaml=Read-YumXamlText -Path $path;$reader=New-Object System.Xml.XmlNodeReader $xaml;$script:Yum.Window=[Windows.Markup.XamlReader]::Load($reader);$script:Yum.Ui=[ordered]@{};foreach($n in @('Intelligence','TelemetryStatus','QuickMonitorStatus','QuickMonitorTelemetry','ModeHelp','Mode','Status','Available','Memory','CPU','GPU','Game','Usage','MemoryBar','Target','TargetStatus','TargetBar','Graph','FreeRam','DeepReclaim','ReclaimCenter','ReclaimStatus','Monitor','ModeBox','TargetBox','Apply','AutoGame','ProtectGame','AutoClean','PriorityBox','Processes','Settings','About','Footer','VersionStatus','MemoryRing','MemoryRingText','NavOverview','Startup','PageHost','OverviewPage','Sidebar','SidebarToggle','SideBrand','SideVersion','SideStatusPanel','SideRamText','SideRamBar','SideRamCompact','HotkeyHint','FreedToday','FreedTodayRuns','FreedTotal','FreedTotalRuns','CpuBalanceToggle','CpuBalanceText','CpuBalanceCount','CpuBalancePill','UpdateBanner','UpdateNotes','UpdateInstall','UpdateTitle','UpdateText')){$script:Yum.Ui[$n]=$script:Yum.Window.FindName($n)};Apply-YumUiConfig;if($null -ne $script:Yum.Ui.VersionStatus){$script:Yum.Ui.VersionStatus.Text=('YUMRAM V{0}' -f [string]$script:Yum.Config.Version)};if($null -ne $script:Yum.Ui.SideVersion){$script:Yum.Ui.SideVersion.Text=('version {0}' -f [string]$script:Yum.Config.Version)}
    # 5.6: one window - the sidebar opens every tool as a page (UI\Shell.ps1).
    Initialize-YumShell
    # 5.3.1: reclaim runs on the controller worker; the UI timer shows the result (Update-YumReclaimResultUI).
    $script:Yum.Ui.FreeRam.Add_Click({try{if(Request-YumMemoryReclaim -Mode Quick){Set-YumFooter '💜 Freeing RAM now… (window stays responsive)';$script:Yum.Ui.ReclaimStatus.Text='Freeing RAM… results appear in a few seconds.'}else{Set-YumFooter '💜 A reclaim is already running.'};Update-YumReclaimButtons}catch{Write-YumLogException -Context 'Free RAM action failed' -Exception $_.Exception;Set-YumFooter '⚠ Free RAM failed — check YUMRAM.log.'}})
    $script:Yum.Ui.DeepReclaim.Add_Click({try{if(Request-YumMemoryReclaim -Mode Deep){Set-YumFooter '💜 Deep reclaim running… (window stays responsive)';$script:Yum.Ui.ReclaimStatus.Text='Deep reclaim running… results appear in a few seconds.'}else{Set-YumFooter '💜 A reclaim is already running.'};Update-YumReclaimButtons}catch{Write-YumLogException -Context 'Deep RAM reclaim failed' -Exception $_.Exception;Set-YumFooter '⚠ Deep reclaim failed — check YUMRAM.log.'}})
    $script:Yum.Ui.Monitor.Add_Click({if($null -eq $script:Yum.TelemetryTimer){Start-YumMonitoring}else{Stop-YumMonitoring}})
    $script:Yum.Ui.Apply.Add_Click({Invoke-YumApplyTarget})
    $script:Yum.Ui.TargetBox.Add_KeyDown({param($s,$e)if($e.Key -eq [System.Windows.Input.Key]::Enter){Invoke-YumApplyTarget;$e.Handled=$true}})
    $script:Yum.Ui.ModeBox.Add_PreviewMouseWheel({param($s,$e)if(-not $s.IsDropDownOpen){$e.Handled=$true}})
    $script:Yum.Ui.PriorityBox.Add_PreviewMouseWheel({param($s,$e)if(-not $s.IsDropDownOpen){$e.Handled=$true}})
    $script:Yum.Ui.ModeBox.Add_SelectionChanged({
        if(-not $script:Yum.SuppressUiEvents -and $script:Yum.Ui.ModeBox.SelectedItem){
            $mode = [string]$script:Yum.Ui.ModeBox.SelectedItem.Tag
            if($mode -in @('Safe','Balanced','Aggressive')){
                Update-YumConfigValue -Name Mode -Value $mode
                $profile = Get-YumModeProfile

                if($null -ne $script:Yum.Ui.ModeHelp){
                    switch($mode){
                        'Safe' {
                            $script:Yum.Ui.ModeHelp.Text = 'Minimal intervention - low-risk candidates only, up to 8 follow-up passes, no optional apps/services.'
                        }
                        'Aggressive' {
                            $script:Yum.Ui.ModeHelp.Text = 'Maximum reclaim - broader known-safe candidates, approved optional apps/services, repeated passes toward the target.'
                        }
                        default {
                            $script:Yum.Ui.ModeHelp.Text = 'Recommended balance - moderate candidates and repeated passes toward the target without touching protected/unknown items.'
                        }
                    }
                }

                Set-YumFooter ('Mode: {0} - up to {1} process trim candidates per pass; {2} follow-up pass(es).' -f $profile.Name,$profile.PassLimit,$profile.FollowUpPasses)
            }
        }
    })
    $script:Yum.Ui.PriorityBox.Add_SelectionChanged({if(-not $script:Yum.SuppressUiEvents -and $script:Yum.Ui.PriorityBox.SelectedItem){$choice=[string]$script:Yum.Ui.PriorityBox.SelectedItem.Content;if($choice -like 'High*'){$answer=[System.Windows.MessageBox]::Show($script:Yum.Window,"High priority gives the game more CPU scheduling preference. It does not increase RAM or GPU capacity, and Microsoft recommends using High with care because a CPU-bound high-priority process can consume most available CPU time.`n`nApply High priority to detected games?",'YUMRAM - Game Priority','YesNo','Warning');if($answer -ne [System.Windows.MessageBoxResult]::Yes){$script:Yum.SuppressUiEvents=$true;try{$script:Yum.Ui.PriorityBox.SelectedIndex=0}catch{}finally{$script:Yum.SuppressUiEvents=$false};Update-YumConfigValue -Name GamePriority -Value 'KeepExisting';return}}$stored=switch -Regex ($choice){'^Keep Existing'{'KeepExisting'};'^Above Normal'{'AboveNormal'};'^High'{'High'};default{'Normal'}};Update-YumConfigValue -Name GamePriority -Value $stored}})
    $script:Yum.Ui.AutoGame.Add_Click({if(-not $script:Yum.SuppressUiEvents){Update-YumConfigValue -Name AutoDetectGames -Value ([bool]$script:Yum.Ui.AutoGame.IsChecked)}})
    $script:Yum.Ui.ProtectGame.Add_Click({if(-not $script:Yum.SuppressUiEvents){Update-YumConfigValue -Name ProtectGame -Value ([bool]$script:Yum.Ui.ProtectGame.IsChecked)}})
    $script:Yum.Ui.UpdateInstall.Add_Click({Invoke-YumInstallUpdate})
    $script:Yum.Ui.UpdateNotes.Add_Click({try{$i=$script:Yum['UpdateInfo'];if($i -and $i.PageUrl -match '^https://github\.com/'){Start-Process ([string]$i.PageUrl)}}catch{}})
    $script:Yum.Ui.CpuBalanceToggle.Add_Click({if(-not $script:Yum.SuppressUiEvents){Update-YumConfigValue -Name CpuBalanceEnabled -Value ([bool]$script:Yum.Ui.CpuBalanceToggle.IsChecked);Update-YumCpuBalanceUi;Set-YumFooter $(if([bool]$script:Yum.Ui.CpuBalanceToggle.IsChecked){'CPU balance on 💜'}else{'CPU balance off - anything YUMRAM held back is put back now.'})}})
    $script:Yum.Ui.AutoClean.Add_Click({if(-not $script:Yum.SuppressUiEvents){Update-YumConfigValue -Name AutoCleanOnGameStart -Value ([bool]$script:Yum.Ui.AutoClean.IsChecked)}})
    $script:Yum.Window.Add_SizeChanged({Update-YumGraph})
    # 5.4: the main window runs with Show() + a DispatcherFrame instead of ShowDialog(), because hiding a
    # ShowDialog window (minimize to tray) ends the dialog and would quit YUMRAM.
    $script:Yum.MainFrame=New-Object System.Windows.Threading.DispatcherFrame
    $script:Yum.Window.Add_Closed({try{if($null -ne $script:Yum.PageFrame){$script:Yum.PageFrame.Continue=$false}}catch{};try{if($null -ne $script:Yum.Hotkey){$script:Yum.Hotkey.Dispose();$script:Yum.Hotkey=$null}}catch{};try{Remove-YumTray}catch{};$script:Yum.StopRequested=$true;Stop-YumMonitoring;try{Stop-YumControllerWorker}catch{};try{Stop-YumCpuBalanceWorker}catch{};try{if($null -ne $script:Yum.UiTimer){$script:Yum.UiTimer.Stop()}}catch{};Restart-YumOptionalServices;Write-YumLog 'YUMRAM closed.';Stop-YumSingleInstance;try{$script:Yum.MainFrame.Continue=$false}catch{}})
    $script:Yum.Window.Add_StateChanged({
        try{ if($script:Yum.Window.WindowState -eq [System.Windows.WindowState]::Minimized -and $null -ne $script:Yum.TrayIcon -and [bool]$script:Yum.Config['MinimizeToTray']){ Hide-YumToTray } }catch{}
    })
    if([bool]$script:Yum.Config['ShowTrayIcon']){ try{ Initialize-YumTray }catch{ Write-YumLogException -Context 'Tray icon failed; continuing without it' -Exception $_.Exception } }
    $timer=New-Object System.Windows.Threading.DispatcherTimer;$timer.Interval=[TimeSpan]::FromSeconds([double]$script:Yum.Config.UIRefreshIntervalSeconds);$timer.Add_Tick({param($tm,$te)try{$want=if($script:Yum.Window.IsVisible){[TimeSpan]::FromSeconds([double]$script:Yum.Config.UIRefreshIntervalSeconds)}else{[TimeSpan]::FromSeconds(1)};if($tm.Interval -ne $want){$tm.Interval=$want}}catch{};Update-YumUiFromSnapshot;Update-YumCpuBalanceUi;Update-YumUpdateUi;Update-YumCleanupResultUI;try{[void](Update-YumReclaimVerification)}catch{};Update-YumReclaimResultUI});$script:Yum.UiTimer=$timer;$timer.Start()
    try{$initialMemory=Get-YumMemoryTelemetry;if($null -ne $initialMemory){Update-YumSnapshot -Changes @{Memory=$initialMemory;CPU=0.0;GPU3D=0.0;ForegroundProcessId=0;Game=[pscustomobject]@{ProcessId=0;ProcessName=$null;Detected=$false}} -CoreTelemetry}}catch{Write-YumLogException -Context 'Initial memory telemetry failed' -Exception $_.Exception}
    # 5.10: the first snapshot does not bump the version counter; ask for one full draw (paused start showed '--').
    $script:Yum.UiNeedsFullRefresh=$true
    Update-YumUiFromSnapshot
    # The controller worker lives for the whole session so queued requests (safe optimization,
    # auto-clean on game start) are processed; automatic maintenance still waits for monitoring.
    try{Start-YumControllerWorker}catch{Write-YumLogException -Context 'Controller worker start failed' -Exception $_.Exception}
    # 5.8: CPU balance runs on its own worker (independent of memory monitoring, like ProBalance).
    try{Start-YumCpuBalanceWorker}catch{Write-YumLogException -Context 'CPU balance worker start failed' -Exception $_.Exception}
    if([bool]$script:Yum.Config.StartMonitoringAutomatically){Start-YumMonitoring}
    $script:Yum.Window.Show()
    try{ Register-YumGlobalHotkey }catch{}
    try{ Update-YumFreedStatsUi }catch{}
    # 5.10: once-a-day GitHub release check in the background (Settings > General to turn off).
    try{ Start-YumUpdateCheck }catch{ Write-YumLogException -Context 'Update check start failed' -Exception $_.Exception }
    [System.Windows.Threading.Dispatcher]::PushFrame($script:Yum.MainFrame)   # returns when the window closes
}
function Update-YumReclaimButtons {
    try{
        $busy=Test-YumReclaimBusy
        $script:Yum.Ui.FreeRam.IsEnabled=-not $busy
        $script:Yum.Ui.DeepReclaim.IsEnabled=-not $busy
    }catch{}
}
function Update-YumReclaimResultUI {
    # Shows the result of a reclaim the controller worker finished (and later verification updates).
    try{
        Update-YumReclaimButtons
        $v=[int]$script:Yum.ReclaimResultVersion
        if($v -eq [int]$script:Yum.LastUiReclaimResultVersion){return}
        $script:Yum.LastUiReclaimResultVersion=$v
        $r=$script:Yum.LastReclaim
        if($null -eq $r -or $null -eq $r.PSObject.Properties['Summary']){return}
        $text=[string]$r.Summary
        # 5.6: count the measured Available gain once per reclaim (verification updates reuse the version counter).
        try{$key=if($r.PSObject.Properties['Timestamp']){([datetime]$r.Timestamp).Ticks.ToString()}else{$text};if($key -ne [string]$script:Yum.LastStatReclaimKey -and $r.PSObject.Properties['AvailableGainGB']){$script:Yum.LastStatReclaimKey=$key;Add-YumFreedStat -GainGB ([double]$r.AvailableGainGB) -Source 'Reclaim'}}catch{}
        if($r.PSObject.Properties['RetainedGainGB'] -and $null -ne $r.RetainedGainGB){$text+=(' Retained after 30s: +{0:N2} GB.' -f [double]$r.RetainedGainGB)}
        $script:Yum.Ui.ReclaimStatus.Text=$text
        Set-YumFooter ('💜 '+$text)
        # A reclaim started from the tray reports back there while the window is hidden.
        if([bool]$script:Yum.TrayReclaimPending -and -not (Test-YumReclaimBusy)){
            $script:Yum.TrayReclaimPending=$false
            if(-not $script:Yum.Window.IsVisible){
                $gain=if($r.PSObject.Properties['AvailableGainGB']){[double]$r.AvailableGainGB}else{0.0}
                Show-YumTrayNotice -Title 'YUMRAM freed RAM' -Text ('Available RAM +{0:N2} GB. {1}' -f $gain,[string]$r.Summary)
            }
        }
    }catch{Write-YumLogException -Context 'Reclaim result UI failed' -Exception $_.Exception}
}
function Update-YumCleanupResultUI {
    $v=0;$r=$null;[System.Threading.Monitor]::Enter($script:Yum.CacheLock);try{$v=$script:Yum.CleanupResultVersion;$r=$script:Yum.CleanupResult}finally{[System.Threading.Monitor]::Exit($script:Yum.CacheLock)}
    if($v -le $script:Yum.LastUiCleanupResultVersion -or $null -eq $r){return};$script:Yum.LastUiCleanupResultVersion=$v
    try{if($r.Success -and $r.PSObject.Properties['AvailableImprovementGB']){Add-YumFreedStat -GainGB ([double]$r.AvailableImprovementGB) -Source 'Automatic'}}catch{}
    if($r.Success -and $r.TargetReached){$suffix=if($r.PSObject.Properties['StopReason']){' • '+[string]$r.StopReason}else{''};Set-YumFooter ('🎯 Target reached: {0:N2} GB available | reclaimed {1:N0} MB | Available +{2:N2} GB{3}' -f $r.AfterAvailableGB,(($r.WorkingSetReduced)/1MB),[double]$r.AvailableImprovementGB,$suffix)}elseif($r.Success -and $r.WorkingSetReduced -gt 0){$suffix=if($r.PSObject.Properties['StopReason']){' • '+[string]$r.StopReason}else{''};Set-YumFooter ('✨ Cleanup: {0:N0} MB WS reduced | Available +{1:N2} GB | Target {2:N2} GB | Shortfall {3:N2} GB{4}' -f (($r.WorkingSetReduced)/1MB),$r.AvailableImprovementGB,$r.TargetGB,[double]$r.TargetShortfallGB,$suffix)}elseif($r.Skipped){Set-YumFooter "Cleanup skipped — $($r.Reason)."}elseif($r.Success){$suffix=if($r.PSObject.Properties['StopReason']){' • '+[string]$r.StopReason}else{''};Set-YumFooter ('Cleanup completed — target shortfall {0:N2} GB{1}' -f [double]$r.TargetShortfallGB,$suffix)}else{Set-YumFooter "Cleanup failed — $($r.Reason)."}
}
function Start-YumRamApplication {
    Write-YumLog 'Startup phase: initializing configuration.'
    Initialize-YumConfig
    Write-YumLog 'Startup phase: configuration initialized.'

    try {
        $researchPath = Join-Path $script:Yum.Root 'Core\Research.ps1'
        if(Test-Path -LiteralPath $researchPath){
            . $researchPath
            Write-YumLog 'Startup phase: intelligence research module loaded.'
        }
        else {
            Write-YumLog 'Startup phase: research module not present; continuing without online research.'
        }
    }
    catch {
        Write-YumLogException -Context 'Startup research module load failed' -Exception $_.Exception
    }

    Write-YumLog 'Startup phase: restoring interrupted state.'
    Restore-YumInterruptedServiceStops
    Write-YumLog 'Startup phase: interrupted state restored.'
    Write-YumLog 'Startup phase: elevation check.'

    if(-not (Start-YumElevated)){
        Write-YumLog 'Startup phase: elevation relaunch requested; exiting unelevated instance.'
        return
    }

    Write-YumLog 'Startup phase: single-instance check.'
    if(-not (Test-YumSingleInstance)){
        return
    }

    Write-YumLog ("YUMRAM {0} starting." -f $script:Yum.Config.Version)
    Write-YumLog 'Startup phase: loading main UI.'
    Start-YumApplicationUi
}
