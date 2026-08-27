#requires -Version 5.1


function Read-YumXamlText {
    param([Parameter(Mandatory=$true)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        throw "XAML file not found: $Path"
    }
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
        try{[System.Windows.MessageBox]::Show(('YUMRAM could not start the elevated instance.`n`n{0}' -f $_.Exception.Message),'YUMRAM - Startup Error','OK','Error')|Out-Null}catch{}
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
        $allMemoryVals=@()
        foreach($s in $memorySeries){$allMemoryVals += @($s.Values | ForEach-Object {[double]$_})}
        if($allMemoryVals.Count -ge 2){
            $min=[double](($allMemoryVals | Measure-Object -Minimum).Minimum)
            $max=[double](($allMemoryVals | Measure-Object -Maximum).Maximum)
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
function Update-YumTargetUi {
    try {
        $s=Get-YumSnapshotCopy
        if($null -eq $s -or $null -eq $s.Memory -or $null -eq $script:Yum.Ui.TargetBox){return}
        $m=$s.Memory
        $target=[double]$script:Yum.Config.MinimumAvailableGB
        if($target -le 0){$target=0.1}
        $ratio=[math]::Min(100,([double]$m.AvailableGB/$target)*100)
        $script:Yum.Ui.Target.Text='Available: {0:N1} GB / Target: {1:N1} GB ({2:N0}%)' -f $m.AvailableGB,$target,$ratio
        $script:Yum.Ui.TargetBar.Value=$ratio
        $script:Yum.Ui.TargetStatus.Text=if($m.AvailableGB -ge $target){'[OK]'}else{'[LOW]'}
        if($m.AvailableGB -ge $target){$brush='#86EFAC'}elseif($m.AvailableGB -ge ($target*.75)){$brush='#FDE68A'}else{$brush='#FCA5A5'}
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
            [void]$script:Yum.GraphMemory.Add([double]$m.UsedPercent);while($script:Yum.GraphMemory.Count -gt $script:Yum.GraphPointsLimit){$script:Yum.GraphMemory.RemoveAt(0)}
            [void]$script:Yum.GraphMemoryAvailable.Add([double]$availablePct);while($script:Yum.GraphMemoryAvailable.Count -gt $script:Yum.GraphPointsLimit){$script:Yum.GraphMemoryAvailable.RemoveAt(0)}
            [void]$script:Yum.GraphCPU.Add([double]$s.CPU);while($script:Yum.GraphCPU.Count -gt $script:Yum.GraphPointsLimit){$script:Yum.GraphCPU.RemoveAt(0)}
            [void]$script:Yum.GraphGPU.Add([double]$s.GPU3D);while($script:Yum.GraphGPU.Count -gt $script:Yum.GraphPointsLimit){$script:Yum.GraphGPU.RemoveAt(0)}
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
        if($age -gt 3){$script:Yum.Ui.Status.Text='⚠ Telemetry delayed';$script:Yum.Ui.Status.Foreground=Get-YumBrush '#FDE68A';Set-YumFooter ('⚠ Telemetry delayed — last sample {0:N1}s ago.' -f $age)}elseif($null -ne $script:Yum.TelemetryTimer -and $script:Yum.LastCoreTelemetryUpdate -ne [datetime]::MinValue){$script:Yum.Ui.Status.Text='● Monitoring';$script:Yum.Ui.Status.Foreground=Get-YumBrush $script:Yum.Config.GPUColor;if($m.AvailableGB -lt $target){Set-YumFooter '💜 Memory pressure detected — seeking target.'}else{Set-YumFooter ('Everything looks comfy 💜  •  Available {0:N2} GB  •  Target {1:N2} GB' -f $m.AvailableGB,$target)}}else{$script:Yum.Ui.Status.Text='● Paused';$script:Yum.Ui.Status.Foreground=Get-YumBrush '#FDE68A'}
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
        $script:Yum.Ui.AutoGame.IsChecked=[bool]$script:Yum.Config.AutoDetectGames
        $script:Yum.Ui.ProtectGame.IsChecked=[bool]$script:Yum.Config.ProtectGame
        $script:Yum.Ui.AutoClean.IsChecked=[bool]$script:Yum.Config.AutoCleanOnGameStart
    }finally{$script:Yum.SuppressUiEvents=$false}
}
function Start-YumMonitoring {
    if($null -ne $script:Yum.TelemetryTimer){return}
    $script:Yum.StopRequested=$false
    Start-YumTelemetry
    Start-YumControllerTimer;if($null -ne $script:Yum.Ui.Clean -and [bool]$script:Yum.Config.TargetMaintenanceEnabled){$script:Yum.Ui.Clean.Content='🎯 TARGET MODE ACTIVE'};$script:Yum.Ui.Monitor.Content='■ Stop Monitoring';$script:Yum.Ui.Status.Text='● Monitoring';if($null -ne $script:Yum.Ui.QuickMonitorStatus){$script:Yum.Ui.QuickMonitorStatus.Text='ACTIVE';$script:Yum.Ui.QuickMonitorStatus.Foreground=Get-YumBrush $script:Yum.Config.GPUColor};$script:Yum.Ui.Status.Foreground=Get-YumBrush $script:Yum.Config.GPUColor;Write-YumLog 'Monitoring started.'
}
function Stop-YumMonitoring {
    Stop-YumTelemetry;$script:Yum.Ui.Monitor.Content='▶ Start Monitoring';if($null -ne $script:Yum.Ui.Clean){$script:Yum.Ui.Clean.Content='🎯 Reach & Maintain Target'};$script:Yum.Ui.Status.Text='● Paused';if($null -ne $script:Yum.Ui.QuickMonitorStatus){$script:Yum.Ui.QuickMonitorStatus.Text='PAUSED';$script:Yum.Ui.QuickMonitorStatus.Foreground=Get-YumBrush '#FDE68A'};$script:Yum.Ui.Status.Foreground=Get-YumBrush '#FDE68A';Write-YumLog 'Monitoring stopped.'
}
function Invoke-YumApplyTarget {
    try{$v=0.0;$ok=[double]::TryParse($script:Yum.Ui.TargetBox.Text.Trim(),[Globalization.NumberStyles]::Float,[Globalization.CultureInfo]::InvariantCulture,[ref]$v);if(-not $ok -or $v -le 0){Show-YumMessage -Message 'Enter a valid Available RAM target greater than 0 GB.' -Title 'YUMRAM - Invalid Target' -Buttons 'OK' -Icon 'Warning';return};$s=Get-YumSnapshotCopy;$m=if($s){$s.Memory}else{Get-YumMemoryTelemetry};if($null -eq $m -or $v -gt $m.TotalGB){Show-YumMessage -Message 'The target must be greater than 0 and no more than installed RAM.' -Title 'YUMRAM - Invalid Target' -Buttons 'OK' -Icon 'Warning';return};$v=[math]::Round($v,1);Update-YumConfigValue -Name MinimumAvailableGB -Value $v;Update-YumConfigValue -Name CleanupTargetAvailableGB -Value $v;$script:Yum.Ui.TargetBox.Text=$v.ToString('0.##');Update-YumTargetUi;Set-YumFooter "Target updated to $v GB 💜";Write-YumLog "Minimum Available RAM target changed to $v GB."}catch{Write-YumLogException -Context 'Target apply failed' -Exception $_.Exception}
}
function Test-YumSingleInstance {try{$mutex=New-Object System.Threading.Mutex($false,'Local\YUMRAM-V5-SingleInstance');$owned=$false;try{$owned=$mutex.WaitOne(0)}catch [System.Threading.AbandonedMutexException]{$owned=$true};if(-not $owned){$mutex.Dispose();[System.Windows.MessageBox]::Show('YUMRAM is already running.','YUMRAM','OK','Information')|Out-Null;return $false};$script:Yum.SingleInstanceMutex=$mutex;$script:Yum.SingleInstanceOwned=$true;return $true}catch{Write-YumLogException -Context 'Single instance check failed' -Exception $_.Exception;return $true}}
function Stop-YumSingleInstance {try{if($script:Yum.SingleInstanceOwned -and $script:Yum.SingleInstanceMutex){try{$script:Yum.SingleInstanceMutex.ReleaseMutex()}catch{};$script:Yum.SingleInstanceMutex.Dispose()}}catch{}finally{$script:Yum.SingleInstanceMutex=$null;$script:Yum.SingleInstanceOwned=$false}}
function Start-YumApplicationUi {
    $path=Join-Path $script:Yum.Root 'UI\Xaml\MainWindow.xaml';if(-not(Test-Path -LiteralPath $path)){throw "Missing main window XAML: $path"};[xml]$xaml=Read-YumXamlText -Path $path;$reader=New-Object System.Xml.XmlNodeReader $xaml;$script:Yum.Window=[Windows.Markup.XamlReader]::Load($reader);$script:Yum.Ui=[ordered]@{};foreach($n in @('Intelligence','TelemetryStatus','QuickMonitorStatus','QuickMonitorTelemetry','ModeHelp','Mode','Status','Available','Memory','CPU','GPU','Game','Usage','MemoryBar','Target','TargetStatus','TargetBar','Graph','Clean','Preview','Monitor','ModeBox','TargetBox','Apply','AutoGame','ProtectGame','AutoClean','PriorityBox','Processes','Settings','About','Footer','VersionStatus')){$script:Yum.Ui[$n]=$script:Yum.Window.FindName($n)};Apply-YumUiConfig;if($null -ne $script:Yum.Ui.VersionStatus){$script:Yum.Ui.VersionStatus.Text=('YUMRAM V{0}' -f [string]$script:Yum.Config.Version)}
    $script:Yum.Ui.Clean.Add_Click({try{if($null -eq $script:Yum.TelemetryTimer){Start-YumMonitoring};Set-YumFooter ('🎯 Reaching target {0:N2} GB and maintaining it.' -f [double]$script:Yum.Config.MinimumAvailableGB);$script:Yum.Ui.Clean.Content='🎯 TARGET MODE ACTIVE';[void](Request-YumCleanup -Force)}catch{Write-YumLogException -Context 'Manual target-maintenance request failed' -Exception $_.Exception}})
    $script:Yum.Ui.Preview.Add_Click({Show-YumCleanupPreview})
    $script:Yum.Ui.Processes.Add_Click({try{Show-YumTopProcesses}catch{Write-YumLogException -Context 'Top memory processes view failed' -Exception $_.Exception}})
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
    $script:Yum.Ui.PriorityBox.Add_SelectionChanged({if(-not $script:Yum.SuppressUiEvents -and $script:Yum.Ui.PriorityBox.SelectedItem){$choice=[string]$script:Yum.Ui.PriorityBox.SelectedItem.Content;if($choice -like 'High*'){$answer=[System.Windows.MessageBox]::Show($script:Yum.Window,'High priority gives the game more CPU scheduling preference. It does not increase RAM or GPU capacity, and Microsoft recommends using High with care because a CPU-bound high-priority process can consume most available CPU time.`n`nApply High priority to detected games?','YUMRAM - Game Priority','YesNo','Warning');if($answer -ne [System.Windows.MessageBoxResult]::Yes){$script:Yum.SuppressUiEvents=$true;try{$script:Yum.Ui.PriorityBox.SelectedIndex=0}catch{}finally{$script:Yum.SuppressUiEvents=$false};Update-YumConfigValue -Name GamePriority -Value 'KeepExisting';return}}$stored=switch -Regex ($choice){'^Keep Existing'{'KeepExisting'};'^Above Normal'{'AboveNormal'};'^High'{'High'};default{'Normal'}};Update-YumConfigValue -Name GamePriority -Value $stored}})
    $script:Yum.Ui.AutoGame.Add_Click({if(-not $script:Yum.SuppressUiEvents){Update-YumConfigValue -Name AutoDetectGames -Value ([bool]$script:Yum.Ui.AutoGame.IsChecked)}})
    $script:Yum.Ui.ProtectGame.Add_Click({if(-not $script:Yum.SuppressUiEvents){Update-YumConfigValue -Name ProtectGame -Value ([bool]$script:Yum.Ui.ProtectGame.IsChecked)}})
    $script:Yum.Ui.AutoClean.Add_Click({if(-not $script:Yum.SuppressUiEvents){Update-YumConfigValue -Name AutoCleanOnGameStart -Value ([bool]$script:Yum.Ui.AutoClean.IsChecked)}})
    $script:Yum.Ui.Intelligence.Add_Click({try{Show-YumIntelligence}catch{Write-YumLogException -Context 'Intelligence launch failed' -Exception $_.Exception}});$script:Yum.Ui.Settings.Add_Click({Show-YumSettings});$script:Yum.Ui.About.Add_Click({Show-YumAbout})
    $script:Yum.Window.Add_SizeChanged({Update-YumGraph})
    $script:Yum.Window.Add_Closed({$script:Yum.StopRequested=$true;Stop-YumMonitoring;Restart-YumOptionalServices;Write-YumLog 'YUMRAM closed.';Stop-YumSingleInstance})
    $timer=New-Object System.Windows.Threading.DispatcherTimer;$timer.Interval=[TimeSpan]::FromSeconds([double]$script:Yum.Config.UIRefreshIntervalSeconds);$timer.Add_Tick({Update-YumUiFromSnapshot;Update-YumCleanupResultUI});$script:Yum.UiTimer=$timer;$timer.Start()
    try{$initialMemory=Get-YumMemoryTelemetry;if($null -ne $initialMemory){Update-YumSnapshot -Changes @{Memory=$initialMemory;CPU=0.0;GPU3D=0.0;ForegroundProcessId=0;Game=[pscustomobject]@{ProcessId=0;ProcessName=$null;Detected=$false}} -CoreTelemetry}}catch{Write-YumLogException -Context 'Initial memory telemetry failed' -Exception $_.Exception}
    Update-YumUiFromSnapshot
    if([bool]$script:Yum.Config.StartMonitoringAutomatically){Start-YumMonitoring}
    [void]$script:Yum.Window.ShowDialog()
}
function Update-YumCleanupResultUI {
    $v=0;$r=$null;[System.Threading.Monitor]::Enter($script:Yum.CacheLock);try{$v=$script:Yum.CleanupResultVersion;$r=$script:Yum.CleanupResult}finally{[System.Threading.Monitor]::Exit($script:Yum.CacheLock)}
    if($v -le $script:Yum.LastUiCleanupResultVersion -or $null -eq $r){return};$script:Yum.LastUiCleanupResultVersion=$v
    if($r.Preview){return}
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
