
function Read-YumXamlText {
    param([Parameter(Mandatory=$true)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        throw "XAML file not found: $Path"
    }
    $utf8 = [System.Text.UTF8Encoding]::new($false,$true)
    return [System.IO.File]::ReadAllText($Path, $utf8)
}
function Show-YumMessage {
    param(
        [Parameter(Mandatory = $true)][string]$Message,
        [string]$Title = "YUMRAM",
        [System.Windows.MessageBoxButton]$Buttons = "OK",
        [System.Windows.MessageBoxImage]$Icon = "Information"
    )

    [System.Windows.MessageBox]::Show(
        $script:Yum.Window,
        $Message,
        $Title,
        $Buttons,
        $Icon
    ) | Out-Null
}

function Show-YumCleanupPreview {
    try {
        $path=Join-Path $script:Yum.Root 'UI\Xaml\CleanupPreview.xaml';[xml]$xaml=Read-YumXamlText -Path $path;$reader=New-Object System.Xml.XmlNodeReader $xaml;$window=[Windows.Markup.XamlReader]::Load($reader)
        $items=$window.FindName('Items');$summary=$window.FindName('Summary');$close=$window.FindName('Close');$refresh=$window.FindName('Refresh')
        $state=@{Window=$window;Items=$items;Summary=$summary;Refresh=$refresh;LiveTimer=$null}
        $refresh.Tag=$state;$close.Tag=$state
        $doRefresh={param($State)
            try{$r=Get-YumCleanupPreview;$State.Items.Items.Clear();if($null -eq $r){$State.Summary.Text='Preview unavailable — no telemetry snapshot.';return};$State.Summary.Text=('Plan: {0} | Available RAM: {1:N2} GB | Target: {2:N2} GB | Planned actions: {3} | Monitoring: {4}' -f $r.Reason,$r.BeforeAvailableGB,$script:Yum.Config.MinimumAvailableGB,@($r.Candidates).Count,($(if($null -ne $script:Yum.TelemetryTimer){'ON — actions occur automatically while below target'}else{'OFF — Preview only; Clean Now performs a one-shot cleanup'})));if(@($r.Candidates).Count -eq 0){$State.Summary.Text+=' | No safe candidates right now — YUMRAM will leave the system alone until a qualifying candidate appears.'};foreach($item in @($r.Candidates)){[void]$State.Items.Items.Add($item)}}catch{Write-YumLogException -Context 'Cleanup preview refresh failed' -Exception $_.Exception;$State.Summary.Text='Preview failed — check YUMRAM.log.'}}
        & $doRefresh $state
        $refresh.Add_Click({param($sender,$e)& $doRefresh $sender.Tag})
        $liveTimer=New-Object System.Windows.Threading.DispatcherTimer
        $liveTimer.Interval=[TimeSpan]::FromSeconds(1)
        $liveTimer.Add_Tick({param($sender,$e)try{& $doRefresh $state}catch{Write-YumLogException -Context 'Live cleanup preview refresh failed' -Exception $_.Exception}})
        $state.LiveTimer=$liveTimer
        $liveTimer.Start()
        $close.Add_Click({param($sender,$e)try{$sender.Tag.LiveTimer.Stop();$sender.Tag.LiveTimer.Dispose()}catch{};$sender.Tag.Window.Close()})
        $window.Add_Closed({try{$state.LiveTimer.Stop();$state.LiveTimer.Dispose()}catch{}})
        $window.Owner=$script:Yum.Window;[void]$window.ShowDialog()
    }catch{Write-YumLogException -Context 'Cleanup preview dialog failed' -Exception $_.Exception;Show-YumMessage -Message ('The cleanup preview could not be opened.`n`n{0}' -f $_.Exception.Message) -Title 'YUMRAM - Error' -Buttons 'OK' -Icon 'Error'}
}

function Update-YumDialogList {
    param(
        [Parameter(Mandatory = $true)][hashtable]$State
    )

    try {
        $State.Items.Items.Clear()
        $configured = @($script:Yum.Config[$State.ListName]) | Sort-Object -Unique

        foreach ($name in $configured) {
            [void]$State.Items.Items.Add([string]$name)
        }

        if ($null -ne $State.Count) {
            $State.Count.Text = "{0} item(s) configured." -f $State.Items.Items.Count
        }
    }
    catch {
        Write-YumLogException -Context "Dialog list refresh failed" -Exception $_.Exception
    }
}

function Invoke-YumDialogAddSelectedItem {
    param(
        [Parameter(Mandatory = $true)][hashtable]$State
    )

    try {
        $value = $State.Input.Text.Trim()

        if ([string]::IsNullOrWhiteSpace($value)) {
            return
        }

        if (-not (Add-YumConfiguredName -List $State.ListName -Name $value)) {
            Show-YumMessage `
                -Message "Enter a process name only (for example: Minecraft or cs2). Do not enter a path or wildcard." `
                -Title "YUMRAM - Invalid Name" `
                -Buttons "OK" `
                -Icon "Warning"
            return
        }

        $State.Input.Clear()
        Update-YumDialogList -State $State
    }
    catch {
        Write-YumLogException -Context "Dialog item add failed" -Exception $_.Exception
        Show-YumMessage -Message "The item could not be added." -Title "YUMRAM - Error" -Buttons "OK" -Icon "Error"
    }
}

function Invoke-YumDialogRemoveSelectedItems {
    param(
        [Parameter(Mandatory = $true)][hashtable]$State
    )

    try {
        $selected = @(
            $State.Items.SelectedItems |
                ForEach-Object { [string]$_ }
        )

        if ($selected.Count -eq 0) {
            return
        }

        Remove-YumConfiguredName -List $State.ListName -Names $selected
        Update-YumDialogList -State $State
    }
    catch {
        Write-YumLogException -Context "Dialog item removal failed" -Exception $_.Exception
        Show-YumMessage -Message "The selected item(s) could not be removed." -Title "YUMRAM - Error" -Buttons "OK" -Icon "Error"
    }
}

function Invoke-YumDialogEnterAdd {
    param(
        $Sender,
        $EventArgs
    )

    if ($EventArgs.Key -eq [System.Windows.Input.Key]::Enter) {
        Invoke-YumDialogAddSelectedItem -State $Sender.Tag
        $EventArgs.Handled = $true
    }
}

function Show-YumListManager {
    param(
        [ValidateSet("KnownGames", "ProtectedProcesses")]
        [string]$List
    )

    try {
        $isGames = $List -eq "KnownGames"

        if ($isGames) {
            $title = "🎮 Manage Games"
            $description = "Add executable process names that YUMRAM should recognize as games."
        }
        else {
            $title = "🛡 Manage Protected Processes"
            $description = "Protected processes are excluded from reclaim candidates."
        }

        $xamlPath = Join-Path $script:Yum.Root "UI\Xaml\ListManager.xaml"
        if (-not (Test-Path -LiteralPath $xamlPath)) {
            throw "Missing dialog XAML: $xamlPath"
        }

        [xml]$xaml = Read-YumXamlText -Path $xamlPath

        $reader = New-Object System.Xml.XmlNodeReader $xaml
        $window = [Windows.Markup.XamlReader]::Load($reader)

        $window.Title = $title
        $titleControl = $window.FindName("DialogTitle")
        $descriptionControl = $window.FindName("DialogDescription")
        if ($null -ne $titleControl) { $titleControl.Text = $title }
        if ($null -ne $descriptionControl) { $descriptionControl.Text = $description }

        $items = $window.FindName("Items")
        $available = $window.FindName("Available")
        $approve = $window.FindName("ApproveSelected")
        $refresh = $window.FindName("RefreshServices")
        $status = $window.FindName("Status")
        $input = $window.FindName("Input")
        $add = $window.FindName("Add")
        $remove = $window.FindName("Remove")
        $count = $window.FindName("Count")

        $state = @{
            Window = $window
            Items = $items
            Input = $input
            Count = $count
            ListName = $List
        }

        $add.Tag = $state
        $remove.Tag = $state
        if($null -ne $approve){$approve.Tag=$state}
        if($null -ne $refresh){$refresh.Tag=$state}
        $input.Tag = $state

        $add.Add_Click({
            param($sender, $eventArgs)
            Invoke-YumDialogAddSelectedItem -State $sender.Tag
        })

        $remove.Add_Click({
            param($sender, $eventArgs)
            Invoke-YumDialogRemoveSelectedItems -State $sender.Tag
        })

        $input.Add_KeyDown({
            param($sender, $eventArgs)
            Invoke-YumDialogEnterAdd -Sender $sender -EventArgs $eventArgs
        })

        $window.Owner = $script:Yum.Window
        Update-YumDialogList -State $state
        Update-YumServiceInventoryList -State $state
        [void]$window.ShowDialog()
    }
    catch {
        Write-YumLogException -Context "Manager window failed" -Exception $_.Exception
        Show-YumMessage `
            -Message ("The manager window could not be opened.`n`n{0}" -f $_.Exception.Message) `
            -Title "YUMRAM - Error" `
            -Buttons "OK" `
            -Icon "Error"
    }
}

function Show-YumInfoWindow {
    param([string]$Title,[string]$Subtitle,[string[]]$Lines)
    try {
        $path=Join-Path $script:Yum.Root 'UI\Xaml\InfoDialog.xaml'
        [xml]$xaml=Read-YumXamlText -Path $path
        $reader=New-Object System.Xml.XmlNodeReader $xaml
        $window=[Windows.Markup.XamlReader]::Load($reader)
        $window.Title=$Title
        $window.FindName('DialogTitle').Text=$Title
        $window.FindName('DialogSubtitle').Text=$Subtitle
        $box=$window.FindName('InfoItems')
        foreach($line in $Lines){[void]$box.Items.Add([string]$line)}
        $close=$window.FindName('Close')
        $close.Tag=@{Window=$window}
        if($null -ne $close){$close.Add_Click({param($sender,$eventArgs) $sender.Tag.Window.Close()})}
        $window.Owner=$script:Yum.Window
        [void]$window.ShowDialog()
    } catch { Write-YumLogException -Context 'Info dialog failed' -Exception $_.Exception; Show-YumMessage -Message $_.Exception.Message -Title 'YUMRAM - Error' -Buttons 'OK' -Icon 'Error' }
}


function Invoke-YumEndTask {
    param([System.Diagnostics.Process]$Process)
    if($null -eq $Process){return [pscustomobject]@{Success=$false;Reason='No process selected'}}
    try {
        $fg=Get-YumForegroundProcessId
        $game=Get-YumSnapshotCopy
        $gamePid=if($game -and $game.Game.Detected){[int]$game.Game.ProcessId}else{0}
        if(Test-YumProtectedProcess -Process $Process -ForegroundPid $fg -GamePid $gamePid){return [pscustomobject]@{Success=$false;Reason='Protected by YUMRAM safety policy'}}
        $answer=[System.Windows.MessageBox]::Show($script:Yum.Window,("End task for {0} (PID {1})?`n`nThis is a manual user action and may cause unsaved work to be lost." -f $Process.ProcessName,$Process.Id),'YUMRAM - End Task','YesNo','Warning')
        if($answer -ne [System.Windows.MessageBoxResult]::Yes){return [pscustomobject]@{Success=$false;Reason='Cancelled'}}
        try {[void]$Process.CloseMainWindow()} catch {}
        try { Start-Sleep -Milliseconds 700; $Process.Refresh() } catch {}
        if($Process.HasExited){return [pscustomobject]@{Success=$true;Reason='Application closed normally'}}
        $force=[System.Windows.MessageBox]::Show($script:Yum.Window,("{0} did not close normally.`n`nForce ending PID {1}?" -f $Process.ProcessName,$Process.Id),'YUMRAM - Confirm Force End','YesNo','Warning')
        if($force -ne [System.Windows.MessageBoxResult]::Yes){return [pscustomobject]@{Success=$false;Reason='Process did not close and force action was cancelled'}}
        $Process.Kill()
        return [pscustomobject]@{Success=$true;Reason='Process force-ended by user'}
    } catch {
        Write-YumLogException -Context 'Manual end task failed' -Exception $_.Exception
        return [pscustomobject]@{Success=$false;Reason=$_.Exception.Message}
    }
}

function ConvertTo-YumPlainHashtable {
    param($InputObject)
    if($null -eq $InputObject){ return $null }
    if($InputObject -is [System.Collections.IDictionary]){
        $result=@{}
        foreach($key in $InputObject.Keys){
            $value=$InputObject[$key]
            if($value -is [System.Collections.IDictionary]){$result[[string]$key]=ConvertTo-YumPlainHashtable $value}
            elseif($value -is [System.Collections.IEnumerable] -and -not ($value -is [string])){$result[[string]$key]=@($value)}
            else{$result[[string]$key]=$value}
        }
        return $result
    }
    return $InputObject
}

function Show-YumSystemScan {
    try {
        $path=Join-Path $script:Yum.Root 'UI\Xaml\SystemScan.xaml'
        if(-not(Test-Path -LiteralPath $path)){throw "Missing dialog XAML: $path"}
        [xml]$xaml=Read-YumXamlText -Path $path
        $reader=New-Object System.Xml.XmlNodeReader $xaml
        $window=[Windows.Markup.XamlReader]::Load($reader)
        $summary=$window.FindName('Summary');$processes=$window.FindName('Processes');$services=$window.FindName('Services');$apps=$window.FindName('Apps');$startup=$window.FindName('Startup');$filter=$window.FindName('Filter');$search=$window.FindName('Search');$refresh=$window.FindName('Refresh');$organize=$window.FindName('OrganizeSelected');$close=$window.FindName('Close');$closeBottom=$window.FindName('CloseBottom');$approve=$window.FindName('ApproveSelected');$protect=$window.FindName('ProtectSelected');$details=$window.FindName('Details')
        $state=@{Window=$window;Summary=$summary;Processes=$processes;Services=$services;Apps=$apps;Startup=$startup;Filter=$filter;Search=$search;Refresh=$refresh;OrganizeSelected=$organize;ApproveSelected=$approve;ProtectSelected=$protect;Details=$details;Scan=$null;Busy=$false;LiveTimer=$null}
        foreach($control in @($refresh,$organize,$filter,$search,$close,$closeBottom,$approve,$protect)){if($null -ne $control){$control.Tag=$state}}
        try { Add-YumOrganizationContextMenu -ListView $processes -State $state -Mode 'SystemScan'; Add-YumOrganizationContextMenu -ListView $services -State $state -Mode 'SystemScan'; Add-YumOrganizationContextMenu -ListView $apps -State $state -Mode 'SystemScan'; Add-YumOrganizationContextMenu -ListView $startup -State $state -Mode 'SystemScan' } catch { Write-YumLogException -Context 'System inventory organization menu attach failed' -Exception $_.Exception }
        $refresh.Add_Click({param($sender,$e)try{Start-YumSystemScanAsync -State $sender.Tag}catch{Write-YumLogException -Context 'System inventory refresh failed' -Exception $_.Exception;$sender.Tag.Summary.Text='Refresh failed — check YUMRAM.log.'}})
        if($null -ne $organize){$organize.Add_Click({param($sender,$e)try{$state=$sender.Tag;$tabs=$state.Window.FindName('Tabs');$tab=$tabs.SelectedItem;$item=$null;$mode='SystemScan';$targetList=$null;switch([string]$tab.Header){'Processes'{$item=$state.Processes.SelectedItem;$targetList=$state.Processes};'Services'{$item=$state.Services.SelectedItem;$targetList=$state.Services};'Apps'{$item=$state.Apps.SelectedItem;$targetList=$state.Apps};'Startup'{$item=$state.Startup.SelectedItem;$targetList=$state.Startup}};if($null -eq $item){$state.Details.Text='Select an item first, then choose Organize Selected.';return};[void](Show-YumOrganizationMenuForItem -Item $item -State $state -Mode $mode -PlacementTarget $targetList)}catch{Write-YumLogException -Context 'System inventory selected organization failed' -Exception $_.Exception}})}
        $filter.Add_SelectionChanged({param($sender,$e)try{Update-YumSystemScanList -State $sender.Tag}catch{Write-YumLogException -Context 'System inventory filter failed' -Exception $_.Exception;$sender.Tag.Details.Text='Filter update failed — check YUMRAM.log.'}})
        $search.Add_TextChanged({param($sender,$e)try{Update-YumSystemScanList -State $sender.Tag}catch{Write-YumLogException -Context 'System inventory search failed' -Exception $_.Exception;$sender.Tag.Details.Text='Search update failed — check YUMRAM.log.'}})
        if($null -ne $approve){$approve.Add_Click({param($sender,$e)try{$state=$sender.Tag;$tab=$state.Window.FindName('Tabs').SelectedItem;$header=[string]$tab.Header;if($header -eq 'Processes'){foreach($row in @($state.Processes.SelectedItems)){if($null -ne $row.Process){[void](Add-YumConfiguredName -List 'OptionalBackgroundProcesses' -Name ([string]$row.Process));}}$state.Details.Text='Selected processes added to the approved optional-background list.'}elseif($header -eq 'Services'){foreach($row in @($state.Services.SelectedItems)){if($null -ne $row.Name){$current=@($script:Yum.Config.OptionalServices);if($current -notcontains [string]$row.Name){$script:Yum.Config.OptionalServices=@($current + [string]$row.Name)}}};[void](Save-YumConfig);$state.Details.Text='Selected services added to the approved optional-service list.'}else{$state.Details.Text='Approve Selected applies to Processes and Services. Apps and Startup entries are informational.'}}catch{Write-YumLogException -Context 'System inventory approval failed' -Exception $_.Exception;$sender.Tag.Details.Text='Approval failed — check YUMRAM.log.'}})}
        if($null -ne $protect){$protect.Add_Click({param($sender,$e)try{$state=$sender.Tag;$tab=$state.Window.FindName('Tabs').SelectedItem;$header=[string]$tab.Header;if($header -eq 'Processes'){foreach($row in @($state.Processes.SelectedItems)){if($null -ne $row.Process){[void](Add-YumConfiguredName -List 'ProtectedProcesses' -Name ([string]$row.Process))}}$state.Details.Text='Selected processes added to Protected Processes.'}else{$state.Details.Text='Protect Selected applies to Processes.'}}catch{Write-YumLogException -Context 'System inventory protection failed' -Exception $_.Exception;$sender.Tag.Details.Text='Protection update failed — check YUMRAM.log.'}})}
        $processes.Add_SelectionChanged({param($sender,$e)try{if($sender.SelectedItem){$r=$sender.SelectedItem;$sender.Tag=$state;$details.Text=('PID {0} | RAM {1:N0} MB | CPU {2:N1}% | Parent {3} | Publisher {4} | Risk {5} | {6}' -f $r.PID,$r.MemoryMB,$r.CPU,$r.ParentPID,$r.Publisher,$r.Risk,$r.Reason)}}catch{Write-YumLogException -Context 'System inventory selection failed' -Exception $_.Exception}})
        $close.Add_Click({param($sender,$e)$sender.Tag.Window.Close()})
        $window.Owner=$script:Yum.Window
        $filter.SelectedIndex=0
        $auto=New-Object System.Windows.Threading.DispatcherTimer
        $auto.Interval=[TimeSpan]::FromSeconds([double]$script:Yum.Config.LiveInventoryIntervalSeconds)
        $auto.Tag=$state
        $auto.Add_Tick({param($sender,$e)try{if(-not $sender.Tag.Busy){Start-YumSystemScanAsync -State $sender.Tag}}catch{Write-YumLogException -Context 'Live inventory refresh failed' -Exception $_.Exception}})
        $state.LiveTimer=$auto
        $close.Add_Click({param($sender,$e)try{$sender.Tag.LiveTimer.Stop()}catch{};$sender.Tag.Window.Close()})
        [void]$window.Show()
        $auto.Start()
        Start-YumSystemScanAsync -State $state
    } catch {
        Write-YumLogException -Context 'System inventory dialog failed' -Exception $_.Exception
        Show-YumMessage -Message ('The system inventory could not be opened.`n`n{0}' -f $_.Exception.Message) -Title 'YUMRAM - Scan Error' -Buttons 'OK' -Icon 'Error'
    }
}

function Start-YumSystemScanAsync {
    param([Parameter(Mandatory)][hashtable]$State)
    if($State.Busy){return}
    $State.Busy=$true
    $State.Summary.Text='Scanning processes, services, apps, and startup activity…'
    $State.Details.Text='Working…'
    Set-YumFooter '🔎 Building live system inventory in the background…'
    $root=$script:Yum.Root;$config=$script:Yum.Config;$max=[int]$config.ScannerMaxItems;$fg=0;$gamePid=0
    try{$fg=[int](Get-YumForegroundProcessId)}catch{}
    try{$snap=Get-YumSnapshotCopy;if($snap -and $snap.Game.Detected){$gamePid=[int]$snap.Game.ProcessId}}catch{}
    $worker=[powershell]::Create()
    try{
        [void]$worker.AddScript({param($root,$config,$max,$fg,$gamePid)
            $ErrorActionPreference='Stop'
            try {
                $script:Yum=[pscustomobject]@{Root=$root;ConfigDirectory=$root;Config=$config}
                $loggingPath=Join-Path $root 'Core\Logging.ps1';if(Test-Path -LiteralPath $loggingPath){. $loggingPath | Out-Null}
                . (Join-Path $root 'Core\Scanner.ps1') | Out-Null
                $researchPath=Join-Path $root 'Core\Research.ps1'; if(Test-Path -LiteralPath $researchPath){. $researchPath | Out-Null}
                $known=@($config.KnownGames);$optional=@($config.OptionalBackgroundProcesses)
                Invoke-YumNewSystemScan -MaxItems $max -ForegroundPid $fg -GamePid $gamePid -KnownGames $known -OptionalApps $optional
            } catch {
                [pscustomobject]@{Status='Failed';Timestamp=Get-Date;Processes=@();Services=@();Apps=@();Records=@();Errors=@(('System inventory scanner: {0}' -f $_.Exception.Message));ProcessCount=0;ServiceCount=0;AppCount=0;RecordCount=0;LowRiskCount=0;ReviewCount=0;ProtectedCount=0;CandidateWorkingSetGB=0}
            }
        }).AddArgument($root).AddArgument($config).AddArgument($max).AddArgument($fg).AddArgument($gamePid)
        $async=$worker.BeginInvoke()
        $poll=New-Object System.Windows.Threading.DispatcherTimer
        $poll.Interval=[TimeSpan]::FromMilliseconds(100)
        $poll.Tag=@{Worker=$worker;Async=$async;State=$State;Started=(Get-Date);TimeoutSeconds=90}
        $poll.Add_Tick({param($sender,$e)
            $ctx=$sender.Tag
            if(-not $ctx.Async.IsCompleted){
                try {
                    $statusPath=Join-Path $root 'research-status.json'
                    if(Test-Path -LiteralPath $statusPath){
                        $status=(Get-Content -LiteralPath $statusPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop)
                        $stage=[string]$status.Stage
                        $name=[string]$status.Name
                        $index=[int]$status.Index
                        $total=[int]$status.Total
                        $message=[string]$status.Message
                        if($stage -and $stage -ne 'Complete'){
                            $ctx.State.Summary.Text=('Research {0}/{1}: {2} — {3}' -f $index,$total,$name,$stage)
                            Set-YumFooter ('🧠 {0}: {1}' -f $stage,$name)
                        }
                    }
                } catch {}
                if(((Get-Date)-$ctx.Started).TotalSeconds -ge [double]$ctx.TimeoutSeconds){
                    $sender.Stop();try{$ctx.Worker.Stop()}catch{};try{$ctx.Worker.Dispose()}catch{};$ctx.State.Busy=$false;$ctx.State.Summary.Text='System inventory timed out after 90 seconds. No partial results were applied.';Set-YumFooter '⚠ System inventory timed out.';Write-YumLog 'System inventory timed out after 90 seconds.'
                }
                return
            }
            $sender.Stop()
            try{
                $result=@($ctx.Worker.EndInvoke($ctx.Async)) | Where-Object {$null -ne $_ -and $null -ne $_.PSObject.Properties['Processes'] -and $null -ne $_.PSObject.Properties['Services'] -and $null -ne $_.PSObject.Properties['Apps'] -and $null -ne $_.PSObject.Properties['Status']} | Select-Object -Last 1
                if($null -eq $result){throw 'System scanner returned no structured result.'}
                if($null -eq $result.Startup){
                    $result|Add-Member -NotePropertyName Startup -NotePropertyValue @() -Force
                    $result|Add-Member -NotePropertyName StartupCount -NotePropertyValue 0 -Force
                }
                $ctx.State.Scan=$result
                Update-YumSystemScanList -State $ctx.State
                if([string]$result.Status -eq 'Failed'){$ctx.State.Summary.Text='System inventory failed — check YUMRAM.log.';Set-YumFooter '⚠ System inventory failed.'}else{Set-YumFooter 'System inventory complete 💜'}
            }catch{Write-YumLogException -Context 'System inventory worker failed' -Exception $_.Exception;$ctx.State.Summary.Text='System inventory failed — check YUMRAM.log.'}finally{$ctx.State.Busy=$false;try{$ctx.Worker.Dispose()}catch{}}
        })
        $poll.Start()
    }catch{try{$worker.Dispose()}catch{};$State.Busy=$false;throw}
}
function Update-YumSystemScanList {
    param([hashtable]$State)
    if($null -eq $State.Scan){$State.Summary.Text='Inventory is still scanning…';return}
    foreach($list in @($State.Processes,$State.Services,$State.Apps,$State.Startup)){if($null -ne $list){$list.Items.Clear()}}
    $filterText='All Processes'
    if($null -ne $State.Filter -and $null -ne $State.Filter.SelectedItem){$filterText=[string]$State.Filter.SelectedItem.Content}
    $query=''
    if($null -ne $State.Search){$query=$State.Search.Text.Trim()}
    $rows=@($State.Scan.Processes)
    if($filterText -eq 'Low Risk'){$rows=@($rows|Where-Object {$_.Risk -in @('Safe to Manage','Candidate')})}
    elseif($filterText -eq 'Review'){$rows=@($rows|Where-Object {$_.Risk -eq 'Review'})}
    elseif($filterText -eq 'Protected'){$rows=@($rows|Where-Object {$_.Risk -eq 'Protected'})}
    if(-not [string]::IsNullOrWhiteSpace($query)){
        $q=$query.ToLowerInvariant()
        $rows=@($rows|Where-Object {([string]$_.Process).ToLowerInvariant().Contains($q) -or ([string]$_.Publisher).ToLowerInvariant().Contains($q) -or ([string]$_.Path).ToLowerInvariant().Contains($q) -or ([string]$_.ParentPID).ToLowerInvariant().Contains($q)})
    }
    foreach($row in $rows){[void]$State.Processes.Items.Add($row)}
    foreach($row in @($State.Scan.Services)){
        if([string]::IsNullOrWhiteSpace($query) -or ([string]$row.Name).ToLowerInvariant().Contains($query.ToLowerInvariant()) -or ([string]$row.DisplayName).ToLowerInvariant().Contains($query.ToLowerInvariant())){[void]$State.Services.Items.Add($row)}
    }
    foreach($row in @($State.Scan.Apps)){
        if([string]::IsNullOrWhiteSpace($query) -or ([string]$row.Name).ToLowerInvariant().Contains($query.ToLowerInvariant()) -or ([string]$row.PublisherId).ToLowerInvariant().Contains($query.ToLowerInvariant())){[void]$State.Apps.Items.Add($row)}
    }
    foreach($row in @($State.Scan.Startup)){
        if([string]::IsNullOrWhiteSpace($query) -or ([string]$row.Name).ToLowerInvariant().Contains($query.ToLowerInvariant()) -or ([string]$row.Command).ToLowerInvariant().Contains($query.ToLowerInvariant())){[void]$State.Startup.Items.Add($row)}
    }
    $errText=if(@($State.Scan.Errors).Count -gt 0){' | Partial scan: '+(@($State.Scan.Errors) -join '; ')}else{''}
    $State.Summary.Text=('Processes: {0} shown/{1} | Services: {2} | Apps: {3} | Startup: {4} | Low Risk: {5} | Review: {6} | Protected: {7} | Potential WS: {8:N2} GB{9}' -f @($rows.Count,@($State.Scan.Processes).Count,@($State.Scan.Services).Count,@($State.Scan.Apps).Count,@($State.Scan.Startup).Count,$State.Scan.LowRiskCount,$State.Scan.ReviewCount,$State.Scan.ProtectedCount,$State.Scan.CandidateWorkingSetGB,$errText))
    if(@($State.Scan.Errors).Count -gt 0){$State.Details.Text='Some inventory categories failed. See YUMRAM.log. Scanning remains usable for categories that succeeded.'}else{$State.Details.Text='Live inventory updated. Select a process to inspect details.'}
}

function Update-YumTopProcessList {
    param([Parameter(Mandatory)][System.Windows.Controls.ListView]$List)
    $List.Items.Clear()
    $fg=Get-YumForegroundProcessId
    $snap=Get-YumSnapshotCopy
    $gamePid=if($snap -and $snap.Game.Detected){[int]$snap.Game.ProcessId}else{0}
    foreach($process in @(Get-Process -ErrorAction SilentlyContinue | Sort-Object WorkingSet64 -Descending | Select-Object -First 40)){
        try{
            $priority='Unknown';try{$priority=[string]$process.PriorityClass}catch{}
            $protected=Test-YumProtectedProcess -Process $process -ForegroundPid $fg -GamePid $gamePid
            $processPath=''
            try{$processPath=[string]$process.MainModule.FileName}catch{}
            [void]$List.Items.Add([pscustomobject]@{Process=$process.ProcessName;Name=$process.ProcessName;PID=$process.Id;MemoryMB=[math]::Round($process.WorkingSet64/1MB,0);Priority=$priority;Protected=$protected;ProcessObject=$process;Path=$processPath;Publisher='Unknown';Category='Apps';Risk=if($protected){'Protected'}else{'Review'};Placement='';ActionLane='Review before management'})
        }catch{}
    }
}

function Show-YumTopProcesses {
    try {
        $path=Join-Path $script:Yum.Root 'UI\Xaml\TopProcesses.xaml'
        [xml]$xaml=Read-YumXamlText -Path $path
        $reader=New-Object System.Xml.XmlNodeReader $xaml
        $window=[Windows.Markup.XamlReader]::Load($reader)
        $items=$window.FindName('Items');$refresh=$window.FindName('Refresh');$endTask=$window.FindName('EndTask');$close=$window.FindName('Close');$details=$window.FindName('Details')
        $state=@{Window=$window;Items=$items;ListView=$items;Details=$details}
        $refresh.Tag=$state;$endTask.Tag=$state;$close.Tag=@{Window=$window}
        $refresh.Add_Click({param($sender,$e)Update-YumTopProcessList -List $sender.Tag.Items})
        $endTask.Add_Click({
            param($sender,$e)
            $selected=$sender.Tag.Items.SelectedItem
            if($null -eq $selected){$sender.Tag.Details.Text='Select a process first.';return}
            $r=Invoke-YumEndTask -Process $selected.ProcessObject
            $sender.Tag.Details.Text=$r.Reason
            Update-YumTopProcessList -List $sender.Tag.Items
        })
        $items.Tag=$state
        try { Add-YumOrganizationContextMenu -ListView $items -State $state -Mode 'NoRefresh' } catch { Write-YumLogException -Context 'Top processes organization menu attach failed' -Exception $_.Exception }
        $items.Add_SelectionChanged({param($sender,$e)if($sender.SelectedItem){$sender.Tag.Details.Text=('PID {0} | {1:N0} MB | Priority {2} | Protected {3}' -f $sender.SelectedItem.PID,$sender.SelectedItem.MemoryMB,$sender.SelectedItem.Priority,$sender.SelectedItem.Protected)}})
        $close.Add_Click({param($sender,$e)$sender.Tag.Window.Close()})
        Update-YumTopProcessList -List $items
        $window.Owner=$script:Yum.Window
        [void]$window.ShowDialog()
    } catch { Write-YumLogException -Context 'Top processes dialog failed' -Exception $_.Exception; Show-YumMessage -Message $_.Exception.Message -Title 'YUMRAM - Error' -Buttons 'OK' -Icon 'Error' }
}

function Show-YumSettings {
    try {
        $path=Join-Path $script:Yum.Root 'UI\Xaml\Settings.xaml';[xml]$xaml=Read-YumXamlText -Path $path;$reader=New-Object System.Xml.XmlNodeReader $xaml;$window=[Windows.Markup.XamlReader]::Load($reader)
        $names=@('MinimumAvailable','CleanupTarget','Hysteresis','CleanInterval','ProcessCooldown','Mode','TelemetryInterval','GpuInterval','GameInterval','SafePressure','BalancedPressure','AggressivePressure','SafePass','BalancedPass','AggressivePass','AutoDetectGames','ProtectGame','AutoCleanOnGameStart','GamePriority','EnableOptionalBackground','EnableOptionalServices','StartMonitoringAutomatically','ScannerMaxItems','EnableSystemScanner','Validation','Apply','Reset','Close')
        $ui=@{};foreach($n in $names){$ui[$n]=$window.FindName($n)}
        $cfg=$script:Yum.Config
        foreach($pair in @(
            @('MinimumAvailable','MinimumAvailableGB'),@('CleanupTarget','CleanupTargetAvailableGB'),@('Hysteresis','TargetHysteresisGB'),@('CleanInterval','MinimumCleanIntervalSeconds'),@('ProcessCooldown','ProcessCooldownSeconds'),@('TelemetryInterval','TelemetryIntervalSeconds'),@('GpuInterval','GPUIntervalSeconds'),@('GameInterval','GameDetectionIntervalSeconds'),@('SafePressure','SafePressurePercent'),@('BalancedPressure','BalancedPressurePercent'),@('AggressivePressure','AggressivePressurePercent'),@('SafePass','SafeProcessesPerPass'),@('BalancedPass','BalancedProcessesPerPass'),@('AggressivePass','AggressiveProcessesPerPass'),@('ScannerMaxItems','ScannerMaxItems')
        )){$ui[$pair[0]].Text=[string]$cfg[$pair[1]]}
        $ui.AutoDetectGames.IsChecked=[bool]$cfg.AutoDetectGames;$ui.ProtectGame.IsChecked=[bool]$cfg.ProtectGame;$ui.AutoCleanOnGameStart.IsChecked=[bool]$cfg.AutoCleanOnGameStart;$ui.EnableOptionalBackground.IsChecked=[bool]$cfg.EnableOptionalBackgroundCleanup;$ui.EnableOptionalServices.IsChecked=[bool]$cfg.EnableOptionalServiceCleanup;$ui.StartMonitoringAutomatically.IsChecked=[bool]$cfg.StartMonitoringAutomatically;$ui.EnableSystemScanner.IsChecked=[bool]$cfg.EnableSystemScanner;$modeItems=@($ui.Mode.Items);for($i=0;$i -lt $modeItems.Count;$i++){if([string]$modeItems[$i].Tag -eq [string]$cfg.Mode){$ui.Mode.SelectedIndex=$i;break}};$display=@('Keep Existing','Normal (Default)','Above Normal (Game Preference)','High (Advanced)');$stored=[string]$cfg.GamePriority;$label=switch($stored){'KeepExisting'{'Keep Existing'};'AboveNormal'{'Above Normal (Game Preference)'};'High'{'High (Advanced)'};default{'Normal (Default)'}};$ui.GamePriority.SelectedIndex=[array]::IndexOf($display,$label)
        $state=@{Window=$window;Ui=$ui};$ui.Apply.Tag=$state;$ui.Reset.Tag=$state;$ui.Close.Tag=$state
        $ui.Close.Add_Click({param($sender,$e)$sender.Tag.Window.Close()})
        $loadDefaults={param($u)
            $d=@{MinimumAvailable='4.0';CleanupTarget='4.0';Hysteresis='0.3';CleanInterval='30';ProcessCooldown='60';TelemetryInterval='0.5';GpuInterval='3';GameInterval='2';SafePressure='92';BalancedPressure='85';AggressivePressure='78';SafePass='3';BalancedPass='6';AggressivePass='10';ScannerMaxItems='80'}
            foreach($k in $d.Keys){$u.$k.Text=$d[$k]};$modeItems=@($u.Mode.Items);for($i=0;$i -lt $modeItems.Count;$i++){if([string]$modeItems[$i].Tag -eq 'Balanced'){$u.Mode.SelectedIndex=$i;break}};$u.GamePriority.SelectedIndex=0;$u.AutoDetectGames.IsChecked=$true;$u.ProtectGame.IsChecked=$true;$u.AutoCleanOnGameStart.IsChecked=$false;$u.EnableOptionalBackground.IsChecked=$true;$u.EnableOptionalServices.IsChecked=$false;$u.StartMonitoringAutomatically.IsChecked=$false;$u.EnableSystemScanner.IsChecked=$true;$u.Validation.Foreground=Get-YumBrush '#FDE68A';$u.Validation.Text='Defaults loaded. Click Apply to save.'
        }
        $ui.Reset.Add_Click({param($sender,$e)& $loadDefaults $sender.Tag.Ui})
        $ui.Apply.Add_Click({param($sender,$e)
            try{
                $u=$sender.Tag.Ui
                $fields=@{
                    MinimumAvailableGB=@($u.MinimumAvailable.Text,0.1,1000);TargetHysteresisGB=@($u.Hysteresis.Text,0.0,100);MinimumCleanIntervalSeconds=@($u.CleanInterval.Text,0.0,3600);ProcessCooldownSeconds=@($u.ProcessCooldown.Text,0.0,86400);TelemetryIntervalSeconds=@($u.TelemetryInterval.Text,0.25,10);GPUIntervalSeconds=@($u.GpuInterval.Text,0.5,30);GameDetectionIntervalSeconds=@($u.GameInterval.Text,0.5,30);SafePressurePercent=@($u.SafePressure.Text,50,99);BalancedPressurePercent=@($u.BalancedPressure.Text,50,99);AggressivePressurePercent=@($u.AggressivePressure.Text,50,99);SafeProcessesPerPass=@($u.SafePass.Text,1,32);BalancedProcessesPerPass=@($u.BalancedPass.Text,1,32);AggressiveProcessesPerPass=@($u.AggressivePass.Text,1,64);ScannerMaxItems=@($u.ScannerMaxItems.Text,10,500)
                }
                foreach($kv in $fields.GetEnumerator()){$d=0.0;if(-not [double]::TryParse([string]$kv.Value[0],[Globalization.NumberStyles]::Float,[Globalization.CultureInfo]::InvariantCulture,[ref]$d)){throw "Invalid value: $($kv.Key)."};if($d -lt $kv.Value[1] -or $d -gt $kv.Value[2]){throw "$($kv.Key) must be between $($kv.Value[1]) and $($kv.Value[2])."};$val=if($kv.Key -match 'Pass|Items'){[int][math]::Round($d)}elseif($kv.Key -match 'Seconds|Interval'){[math]::Round($d,2)}else{[math]::Round($d,1)};Update-YumConfigValue -Name $kv.Key -Value $val};Update-YumConfigValue -Name CleanupTargetAvailableGB -Value ([double]$script:Yum.Config.MinimumAvailableGB)
                if([double]$cfg.SafePressurePercent -lt [double]$cfg.BalancedPressurePercent){throw 'Safe pressure should be at least as high as Balanced pressure.'};if([double]$cfg.BalancedPressurePercent -lt [double]$cfg.AggressivePressurePercent){throw 'Balanced pressure should be at least as high as Aggressive pressure.'}
                foreach($pair in @(@('Mode',[string]$u.Mode.SelectedItem.Tag),@('AutoDetectGames',[bool]$u.AutoDetectGames.IsChecked),@('ProtectGame',[bool]$u.ProtectGame.IsChecked),@('AutoCleanOnGameStart',[bool]$u.AutoCleanOnGameStart.IsChecked),@('EnableOptionalBackgroundCleanup',[bool]$u.EnableOptionalBackground.IsChecked),@('EnableOptionalServiceCleanup',[bool]$u.EnableOptionalServices.IsChecked),@('StartMonitoringAutomatically',[bool]$u.StartMonitoringAutomatically.IsChecked),@('EnableSystemScanner',[bool]$u.EnableSystemScanner.IsChecked))){Update-YumConfigValue -Name $pair[0] -Value $pair[1]};$choice=[string]$u.GamePriority.SelectedItem.Content;$stored=switch -Regex ($choice){'^Keep Existing'{'KeepExisting'};'^Above Normal'{'AboveNormal'};'^High'{'High'};default{'Normal'}};Update-YumConfigValue -Name GamePriority -Value $stored
                $u.Validation.Foreground=Get-YumBrush '#86EFAC';$u.Validation.Text='Settings saved. Restart Monitoring to apply changed telemetry timing. Memory target and safety switches apply immediately.';Apply-YumUiConfig
            }catch{$u.Validation.Foreground=Get-YumBrush '#FCA5A5';$u.Validation.Text=$_.Exception.Message;Write-YumLogException -Context 'Settings apply failed' -Exception $_.Exception}
        })
        $window.Owner=$script:Yum.Window;[void]$window.ShowDialog()
    }catch{Write-YumLogException -Context 'Settings dialog failed' -Exception $_.Exception;Show-YumMessage -Message $_.Exception.Message -Title 'YUMRAM - Settings Error' -Buttons 'OK' -Icon 'Error'}
}

function Show-YumAbout {
    $lines=@(
        ('YUMRAM {0}' -f $script:Yum.Config.Version),
        '',
        'Your Ultimate Memory Reclaim & Monitor',
        '',
        'YUMRAM combines Available-RAM telemetry, conservative working-set reclaim, game protection, optional background-app cleanup, and a reversible optional-service layer.',
        '',
        'Game priority changes CPU scheduling preference only. It does not create additional RAM or GPU capacity. High priority is intentionally treated as an advanced option.',
        '',
        'Working-set reduction is reported separately from measured Available RAM improvement.',
        '',
        'Protected processes, the foreground process, and the active game are excluded by the safety layer.',
        '',
        '💜 Built to reclaim memory without acting like a process killer.'
    )
    Show-YumInfoWindow -Title '💜 About YUMRAM' -Subtitle ('{0} — Live inventory, target controller, telemetry, and safe cleanup.' -f $script:Yum.Config.Version) -Lines $lines
}

function Start-YumOptionalBackgroundScanAsync {
    param([Parameter(Mandatory)][hashtable]$State)
    if($State.Busy){return}
    $State.Busy=$true;$State.Status.Text='Scanning background applications…  Collecting processes and risk evidence.'
    $root=$script:Yum.Root;$config=$script:Yum.Config;$fg=Get-YumForegroundProcessId;$snap=Get-YumSnapshotCopy;$gamePid=if($snap -and $snap.Game.Detected){[int]$snap.Game.ProcessId}else{0}
    $worker=[powershell]::Create()
    try{
        [void]$worker.AddScript({param($root,$config,$fg,$gamePid)
            $script:Yum=[ordered]@{Root=$root;Config=$config}
            function Test-YumNameInList {param([string]$Name,[string[]]$List) $c=$Name -replace '\.exe$','';foreach($x in @($List)){if($c -ieq [string]$x){return $true}};return $false}
            function Test-YumOptionalBackgroundProcess {param([string]$Name) Test-YumNameInList -Name $Name -List @($config.OptionalBackgroundProcesses)}
            function Test-YumProtectedProcess {param($Process,[int]$ForegroundPid=0,[int]$GamePid=0) if($null -eq $Process){return $true};try{if($Process.Id -eq $PID){return $true};if(Test-YumNameInList -Name $Process.ProcessName -List @($config.ProtectedProcesses)){return $true};if($config.ProtectForegroundProcess -and $Process.Id -eq $ForegroundPid){return $true};if($config.ProtectGame -and $GamePid -gt 0 -and $Process.Id -eq $GamePid){return $true};return $false}catch{return $true}}
            $null = . (Join-Path $root 'Core\Scanner.ps1')
            @(Get-YumProcessSnapshotRows -MaxItems 160 -ForegroundPid $fg -GamePid $gamePid | Where-Object {-not $_.Foreground -and -not $_.Game -and $_.Risk -ne 'Protected'} | Sort-Object @{Expression='Score';Descending=$true},@{Expression='MemoryMB';Descending=$true})
        }).AddArgument($root).AddArgument($config).AddArgument($fg).AddArgument($gamePid)
        $async=$worker.BeginInvoke();$poll=New-Object System.Windows.Threading.DispatcherTimer;$poll.Interval=[TimeSpan]::FromMilliseconds(100);$poll.Tag=@{Worker=$worker;Async=$async;Poll=$poll;State=$State};$poll.Add_Tick({param($sender,$e)$ctx=$sender.Tag;if(-not $ctx.Async.IsCompleted){return};$sender.Stop();try{$ctx.State.Discovered.Items.Clear();foreach($row in @($ctx.Worker.EndInvoke($ctx.Async))){[void]$ctx.State.Discovered.Items.Add($row)};$ctx.State.Status.Text=('Scan complete — {0} background processes classified. Select items to add them to Approved Apps.' -f $ctx.State.Discovered.Items.Count);Set-YumFooter ('Background scan complete — {0} reviewable applications found.' -f $ctx.State.Discovered.Items.Count)}catch{Write-YumLogException -Context 'Optional background scan worker failed' -Exception $_.Exception;$ctx.State.Status.Text='Scan failed — check YUMRAM.log.'}finally{$ctx.State.Busy=$false;try{$ctx.Worker.Dispose()}catch{}}});$poll.Start()
    }catch{try{$worker.Dispose()}catch{};$State.Busy=$false;throw}
}

function Show-YumBloatManager {
    try {
        $xamlPath=Join-Path $script:Yum.Root 'UI\Xaml\BloatManager.xaml'
        if(-not(Test-Path -LiteralPath $xamlPath)){throw "Missing dialog XAML: $xamlPath"}
        [xml]$xaml=Read-YumXamlText -Path $xamlPath
        $reader=New-Object System.Xml.XmlNodeReader $xaml
        $window=[Windows.Markup.XamlReader]::Load($reader)
        $items=$window.FindName('Items')
        $discovered=$window.FindName('Discovered')
        $recommendations=$window.FindName('Recommendations')
        $input=$window.FindName('Input')
        $add=$window.FindName('Add')
        $addDiscovered=$window.FindName('AddDiscovered')
        $addRecommended=$window.FindName('AddRecommended')
        $remove=$window.FindName('Remove')
        $close=$window.FindName('Close')
        $enable=$window.FindName('Enable')
        $scan=$window.FindName('Scan');$scanStatus=$window.FindName('ScanStatus');$doneTop=$window.FindName('DoneTop')

        $state=@{Window=$window;Items=$items;Discovered=$discovered;Recommendations=$recommendations;Input=$input;Status=$scanStatus;ListName='OptionalBackgroundProcesses';Busy=$false;ListView=$discovered}
        foreach($control in @($add,$addDiscovered,$addRecommended,$remove,$input,$scan,$close,$doneTop)){if($null -ne $control){$control.Tag=$state}}
        $enable.IsChecked=[bool]$script:Yum.Config.EnableOptionalBackgroundCleanup
        $enable.Tag=$state

        $enable.Add_Click({
            param($sender,$eventArgs)
            Update-YumConfigValue -Name 'EnableOptionalBackgroundCleanup' -Value ([bool]$sender.IsChecked)
        })

        $add.Add_Click({param($sender,$eventArgs) Invoke-YumDialogAddSelectedItem -State $sender.Tag})

        $addDiscovered.Add_Click({
            param($sender,$eventArgs)
            foreach($row in @($sender.Tag.Discovered.SelectedItems)){
                if($null -ne $row.Process){[void](Add-YumConfiguredName -List 'OptionalBackgroundProcesses' -Name ([string]$row.Process))}
            }
            Update-YumDialogList -State $sender.Tag
        })

        $recommendations.Items.Clear()
        foreach($rec in @($script:Yum.Config.RecommendedOptionalBackgroundProcesses)){[void]$recommendations.Items.Add($rec)}

        $addRecommended.Add_Click({
            param($sender,$eventArgs)
            foreach($rec in @($sender.Tag.Recommendations.SelectedItems)){
                if($null -ne $rec.Name){[void](Add-YumConfiguredName -List 'OptionalBackgroundProcesses' -Name ([string]$rec.Name))}
            }
            Update-YumDialogList -State $sender.Tag
        })

        $remove.Add_Click({param($sender,$eventArgs) Invoke-YumDialogRemoveSelectedItems -State $sender.Tag})
        $input.Add_KeyDown({param($sender,$eventArgs) Invoke-YumDialogEnterAdd -Sender $sender -EventArgs $eventArgs})
        if($null -ne $close){$close.Add_Click({param($sender,$eventArgs) $sender.Tag.Window.Close()})}

        $scan.Add_Click({ param($sender,$eventArgs) try { Start-YumOptionalBackgroundScanAsync -State $sender.Tag } catch { Write-YumLogException -Context 'Optional background app scan failed' -Exception $_.Exception } })

        $window.Owner=$script:Yum.Window
        Update-YumDialogList -State $state
        [void]$window.ShowDialog()
    } catch {
        Write-YumLogException -Context 'Optional background manager failed' -Exception $_.Exception
        Show-YumMessage -Message $_.Exception.Message -Title 'YUMRAM - Error' -Buttons 'OK' -Icon 'Error'
    }
}

function Invoke-YumServiceAdd {
    param(
        [Parameter(Mandatory = $true)][hashtable]$State
    )

    $value = $State.Input.Text.Trim()
    if ([string]::IsNullOrWhiteSpace($value)) {
        return
    }

    try {
        $service = Get-Service -Name $value -ErrorAction Stop
        if (@($script:Yum.Config.OptionalServices) -notcontains $service.Name) {
            $script:Yum.Config.OptionalServices = @($script:Yum.Config.OptionalServices) + $service.Name
            [void](Save-YumConfig)
            $State.Input.Clear()
            Update-YumDialogList -State $State
        }
    }
    catch {
        Show-YumMessage -Message "Enter an existing Windows service name." -Title "YUMRAM - Invalid Service" -Buttons "OK" -Icon "Warning"
    }
}

function Invoke-YumServiceRemove {
    param(
        [Parameter(Mandatory = $true)][hashtable]$State
    )

    $selected = @(
        $State.Items.SelectedItems |
            ForEach-Object { [string]$_ }
    )

    if ($selected.Count -eq 0) {
        return
    }

    $script:Yum.Config.OptionalServices = @(
        $script:Yum.Config.OptionalServices |
            Where-Object { $selected -notcontains $_ }
    )

    [void](Save-YumConfig)
    Update-YumDialogList -State $State
}


function Update-YumServiceInventoryList {
    param([hashtable]$State)
    try {
        if($null -eq $State.Available){return}
        $State.Available.Items.Clear()
        $rows=@(Get-YumServiceScanRows -MaxItems ([int]$script:Yum.Config.LiveInventoryMaxItems))
        foreach($row in $rows){
            if($row.Risk -eq 'Protected'){continue}
            [void]$State.Available.Items.Add($row)
        }
        if($null -ne $State.Status){$State.Status.Text=('Discovered {0} stoppable/review services. Add selected services to the approved list; safety checks remain active.' -f $State.Available.Items.Count)}
    }catch{Write-YumLogException -Context 'Service inventory refresh failed' -Exception $_.Exception}
}

function Invoke-YumServiceApproveSelected {
    param([hashtable]$State)
    try{
        foreach($row in @($State.Available.SelectedItems)){
            $name=[string]$row.Name
            if([string]::IsNullOrWhiteSpace($name)){continue}
            if(@($script:Yum.Config.OptionalServices) -notcontains $name){$script:Yum.Config.OptionalServices=@($script:Yum.Config.OptionalServices)+$name}
        }
        [void](Save-YumConfig)
        Update-YumDialogList -State $State
        Update-YumServiceInventoryList -State $State
    }catch{Write-YumLogException -Context 'Service approval failed' -Exception $_.Exception}
}

function Show-YumServiceManager {
    try {
        $xamlPath = Join-Path $script:Yum.Root "UI\Xaml\ServiceManager.xaml"
        if (-not (Test-Path -LiteralPath $xamlPath)) {
            throw "Missing dialog XAML: $xamlPath"
        }

        [xml]$xaml = Read-YumXamlText -Path $xamlPath
        $reader = New-Object System.Xml.XmlNodeReader $xaml
        $window = [Windows.Markup.XamlReader]::Load($reader)

        $items = $window.FindName("Items")
        $available = $window.FindName("Available")
        $approve = $window.FindName("ApproveSelected")
        $refresh = $window.FindName("RefreshServices")
        $status = $window.FindName("Status")
        $input = $window.FindName("Input")
        $add = $window.FindName("Add")
        $remove = $window.FindName("Remove")
        $close = $window.FindName("Close")
        $enable = $window.FindName("Enable")

        $state = @{
            Window = $window
            Items = $items
            Available = $available
            Input = $input
            ApproveSelected = $approve
            RefreshServices = $refresh
            Status = $status
            ListName = "OptionalServices"
        }

        $add.Tag = $state
        $remove.Tag = $state
        if($null -ne $approve){$approve.Tag=$state}
        if($null -ne $refresh){$refresh.Tag=$state}
        $input.Tag = $state
        $close.Tag = @{ Window = $window }
        $enable.IsChecked = [bool]$script:Yum.Config.EnableOptionalServiceCleanup

        $enable.Add_Click({
            param($sender, $eventArgs)
            Update-YumConfigValue -Name "EnableOptionalServiceCleanup" -Value ([bool]$sender.IsChecked)
        })

        $add.Add_Click({
            param($sender, $eventArgs)
            Invoke-YumServiceAdd -State $sender.Tag
        })

        $remove.Add_Click({
            param($sender, $eventArgs)
            Invoke-YumServiceRemove -State $sender.Tag
        })

        $input.Add_KeyDown({
            param($sender, $eventArgs)
            if ($eventArgs.Key -eq [System.Windows.Input.Key]::Enter) {
                Invoke-YumServiceAdd -State $sender.Tag
                $eventArgs.Handled = $true
            }
        })

        $close.Add_Click({
            param($sender, $eventArgs)
            $sender.Tag.Window.Close()
        })
        if($null -ne $approve){$approve.Add_Click({param($sender,$eventArgs) Invoke-YumServiceApproveSelected -State $sender.Tag})}
        if($null -ne $refresh){$refresh.Add_Click({param($sender,$eventArgs) Update-YumServiceInventoryList -State $sender.Tag})}
        try { Add-YumOrganizationContextMenu -ListView $available -State $state -Mode 'NoRefresh' } catch { Write-YumLogException -Context 'Service organization menu attach failed' -Exception $_.Exception }

        $window.Owner = $script:Yum.Window
        Update-YumDialogList -State $state
        Update-YumServiceInventoryList -State $state
        [void]$window.ShowDialog()
    }
    catch {
        Write-YumLogException -Context "Optional service manager failed" -Exception $_.Exception
        Show-YumMessage -Message "The optional service manager could not be opened." -Title "YUMRAM - Error" -Buttons "OK" -Icon "Error"
    }
}

function Show-YumOrganizationMenuForItem {
    param([Parameter(Mandatory)]$Item,[Parameter(Mandatory)][hashtable]$State,[string]$Mode='Intelligence',[object]$PlacementTarget=$null)
    if($null -eq $Item){return}
    $menu=New-Object System.Windows.Controls.ContextMenu
    $header=New-Object System.Windows.Controls.MenuItem
    $header.Header='Organize / Classify'
    $header.IsEnabled=$false
    [void]$menu.Items.Add($header)
    $categories=@(
        @('Games / Gaming','Games / Gaming','Protect during gaming'),
        @('User Background Apps','User Background Apps','Candidate only under memory pressure'),
        @('Identified Applications','Identified Applications','Candidate under memory pressure when research supports it'),
        @('Security','Security','Protect; never manage automatically'),
        @('Drivers / Hardware','Drivers / Hardware','Protect; never manage automatically'),
        @('Startup Inventory','Startup Inventory','Review startup behavior before changes'),
        @('Review Queue','Review Queue','Research/review before management'),
        @('Unknown / Quarantine','Unknown / Quarantine for Review','Never manage automatically')
    )
    foreach($entry in $categories){
        $mi=New-Object System.Windows.Controls.MenuItem
        $mi.Header=$entry[0]
        $mi.Tag=@{Item=$Item;Category=$entry[0];Placement=$entry[1];Action=$entry[2];State=$State;Mode=$Mode}
        $mi.Add_Click({
            param($ms,$me)
            try {
                $t=$ms.Tag
                $org=Set-YumManualOrganization -Item $t.Item -Category $t.Category -Placement $t.Placement -ActionLane $t.Action
                $t.Item.Category=$org.Category
                $t.Item.Placement=$org.Placement
                $t.Item.ActionLane=$org.ActionLane
                $t.Item.Recommendation=$org.ActionLane
                $t.Item|Add-Member -NotePropertyName ManualOverride -NotePropertyValue $true -Force
                $t.Item|Add-Member -NotePropertyName ManualOrganizationUpdated -NotePropertyValue $org.Updated -Force
                if($t.Mode -eq 'SystemScan'){try{Update-YumSystemScanList -State $t.State}catch{}}elseif($t.Mode -eq 'Intelligence'){try{Update-YumIntelligenceList -State $t.State}catch{}}else{try{if($null -ne $t.State.ListView){$t.State.ListView.Items.Refresh()}}catch{}}
                if($null -ne $t.State.Details){$t.State.Details.Text=('MANUAL ORGANIZATION SAVED`nName: {0}`nCategory: {1}`nPlacement: {2}`nAction Lane: {3}' -f $t.Item.Name,$org.Category,$org.Placement,$org.ActionLane)}
                Set-YumFooter ('📁 Organized: {0} → {1}' -f $t.Item.Name,$org.Category)
            } catch {Write-YumLogException -Context 'Manual organization failed' -Exception $_.Exception}
        })
        [void]$menu.Items.Add($mi)
    }
    $clear=New-Object System.Windows.Controls.MenuItem
    $clear.Header='Clear Manual Organization'
    $clear.Tag=@{Item=$Item;State=$State;Mode=$Mode}
    $clear.Add_Click({
        param($ms,$me)
        try {
            $t=$ms.Tag
            $orgs=Load-YumManualOrganizations
            $identity=Get-YumRecordIdentityFields -Item $t.Item
            $key=Get-YumManualOrganizationKey -Name ([string]$t.Item.Name) -Path ([string]$t.Item.Path) -Publisher ([string]$t.Item.Publisher) -FileHash $identity.FileHash -SignerThumbprint $identity.SignerThumbprint
            $legacyKey=Get-YumManualOrganizationKey -Name ([string]$t.Item.Name) -Path ([string]$t.Item.Path) -Publisher ([string]$t.Item.Publisher)
            if($orgs.ContainsKey($key)){$orgs.Remove($key)}
            if($orgs.ContainsKey($legacyKey)){$orgs.Remove($legacyKey)}
            [void](Save-YumManualOrganizations -Organizations $orgs)
            try {
                $t.Item.Risk='Review'
                $t.Item.Category='Review Queue'
                $t.Item.Placement='Review Queue'
                $t.Item.ActionLane='Review before management'
                $t.Item.Recommendation='Research/review before management'
                $t.Item.ManualOverride=$false
                $t.Item.ManualOrganizationUpdated=''
                $t.Item.ResearchStatus='Review'
                $t.Item.ResearchComplete=$false
                $t.Item.ResearchPerformed=$false
                $t.Item.ResearchExhausted=$false
                $t.Item.ResearchErrorState=''
            } catch {}
            try{
                if($null -ne $script:Yum.IntelligenceDb -and $script:Yum.IntelligenceDb -is [hashtable]){
                    $dbKey=[string]$t.Item.Key
                    if(-not [string]::IsNullOrWhiteSpace($dbKey)){$script:Yum.IntelligenceDb[$dbKey]=$t.Item;[void](Save-YumIntelligenceDb -Database $script:Yum.IntelligenceDb)}
                }
            }catch{}
            if($t.Mode -eq 'SystemScan'){try{Update-YumSystemScanList -State $t.State}catch{}}elseif($t.Mode -eq 'Intelligence'){
                try{Update-YumIntelligenceList -State $t.State}catch{}
            }else{try{if($null -ne $t.State.ListView){$t.State.ListView.Items.Refresh()}}catch{}}
            if($null -ne $t.State.Details){$t.State.Details.Text='Manual organization cleared. The item is now eligible for the next user-initiated Run Research.'}
            Set-YumFooter ('↩ Organization restored: {0} • Run Research to investigate it.' -f $t.Item.Name)
        } catch {Write-YumLogException -Context 'Manual organization clear failed' -Exception $_.Exception}
    })
    [void]$menu.Items.Add((New-Object System.Windows.Controls.Separator))
    [void]$menu.Items.Add($clear)
    if($null -ne $PlacementTarget){$menu.PlacementTarget=$PlacementTarget}elseif($null -ne $State.ListView){$menu.PlacementTarget=$State.ListView}
    $menu.IsOpen=$true
    return $menu
}

function Add-YumOrganizationContextMenu {
    param([Parameter(Mandatory)][System.Windows.Controls.ListView]$ListView,[Parameter(Mandatory)][hashtable]$State,[string]$Mode='Intelligence')
    # WPF callbacks execute after this function's local scope has ended. Capture the
    # required values explicitly so PowerShell 5.1 cannot lose $State/$Mode.
    $stateRef=$State
    $modeRef=$Mode
    $handler = {
        param($sender,$eventArgs)
        try {
            $source=$eventArgs.OriginalSource -as [System.Windows.DependencyObject]
            $itemContainer=$null
            while($null -ne $source){
                if($source -is [System.Windows.Controls.ListViewItem]){$itemContainer=$source;break}
                try{$source=[System.Windows.Media.VisualTreeHelper]::GetParent($source)}catch{$source=$null}
            }
            if($null -ne $itemContainer){$sender.SelectedItem=$itemContainer.DataContext}
            $item=$sender.SelectedItem
            if($null -eq $item){return}
            [void](Show-YumOrganizationMenuForItem -Item $item -State $stateRef -Mode $modeRef -PlacementTarget $sender)
            $eventArgs.Handled=$true
        }catch{Write-YumLogException -Context 'Organization context menu failed' -Exception $_.Exception}
    }.GetNewClosure()
    $ListView.Add_MouseRightButtonUp($handler)
}



function Get-YumIntelligenceMergedRecords {
    param([hashtable]$State)
    $byIdentity=@{}
    $order=New-Object System.Collections.Generic.List[string]
    try {
        if($null -eq $script:Yum.IntelligenceDb -or -not ($script:Yum.IntelligenceDb -is [hashtable])){ [void](Load-YumIntelligenceDb) }
    } catch { Write-YumLogException -Context 'Intelligence database load during view refresh failed' -Exception $_ }
    if($null -eq $script:Yum.IntelligenceDb -or -not ($script:Yum.IntelligenceDb -is [hashtable])){ $script:Yum.IntelligenceDb=@{} }

    $sources=New-Object System.Collections.Generic.List[object]
    if($null -ne $State.Data -and $null -ne $State.Data.PSObject.Properties['Records']){ foreach($r in @($State.Data.Records)){[void]$sources.Add($r)} }
    foreach($r in $script:Yum.IntelligenceDb.Values){if($null -ne $r){[void]$sources.Add($r)}}

    foreach($record in $sources){
        if($null -eq $record){continue}
        try { [void](Ensure-YumIntelligenceRecordSchema -Record $record) } catch { continue }
        try {
            $stable='';try{$stable=[string](Get-YumStableIntelligenceKey -Record $record)}catch{}
            $identityKey=if(-not [string]::IsNullOrWhiteSpace($stable)){$stable}else{[string]$record.Key}
            if([string]::IsNullOrWhiteSpace($identityKey)){continue}
            if(-not $byIdentity.ContainsKey($identityKey)){
                $byIdentity[$identityKey]=$record
                [void]$order.Add($identityKey)
            } elseif([bool]$record.Live -and -not [bool]$byIdentity[$identityKey].Live){
                $byIdentity[$identityKey]=$record
            }
        } catch { Write-YumLogException -Context 'Intelligence view record merge failed' -Exception $_.Exception }
    }

    $final=New-Object System.Collections.Generic.List[object]
    foreach($identityKey in $order){
        $record=$byIdentity[$identityKey]
        if($null -eq $record){continue}
        try{
            if(-not [bool]$record.Live){
                $record.StateText='SAVED'
                if([string]::IsNullOrWhiteSpace([string]$record.Reason)){$record.Reason='Saved classification; not present in current live scan.'}
                $record.Memory='—';$record.CPU='—';$record.PID='—'
            } else { $record.StateText='LIVE' }
            [void](Apply-YumManualOrganizationToRecord -Record $record)
            [void]$final.Add($record)
        }catch{Write-YumLogException -Context 'Intelligence view record finalize failed' -Exception $_.Exception}
    }
    return @($final.ToArray())
}

function Refresh-YumIntelligenceView {
    param([Parameter(Mandatory)][hashtable]$State)
    try {
        $merged=@(Get-YumIntelligenceMergedRecords -State $State)
        $timestamp=if($null -ne $State.Data -and $null -ne $State.Data.PSObject.Properties['Timestamp']){$State.Data.Timestamp}else{Get-Date}
        $pc=if($null -ne $State.Data -and $null -ne $State.Data.PSObject.Properties['ProcessCount']){[int]$State.Data.ProcessCount}else{0}
        $sc=if($null -ne $State.Data -and $null -ne $State.Data.PSObject.Properties['ServiceCount']){[int]$State.Data.ServiceCount}else{0}
        $ac=if($null -ne $State.Data -and $null -ne $State.Data.PSObject.Properties['AppCount']){[int]$State.Data.AppCount}else{0}
        $errors=if($null -ne $State.Data -and $null -ne $State.Data.PSObject.Properties['Errors']){@($State.Data.Errors)}else{@()}
        $State.Data=[pscustomobject]@{Records=$merged;Timestamp=$timestamp;ProcessCount=$pc;ServiceCount=$sc;AppCount=$ac;Errors=$errors;Status='Completed';DurationMs=0;SavedCount=[int]$script:Yum.IntelligenceDb.Count;DatabaseCount=[int]$script:Yum.IntelligenceDb.Count}
        Update-YumIntelligenceList -State $State
        if($null -ne $State.DatabaseStatus){$State.DatabaseStatus.Text=('Local profile loaded • {0:N0} saved records • {1:N0} visible' -f [int]$script:Yum.IntelligenceDb.Count,$merged.Count)}
        if($null -ne $State.Summary){$State.Summary.Text=('View refreshed • {0} total records available. No scan was started.' -f $merged.Count)}
        Set-YumFooter ('🧠 Intelligence view refreshed • {0} records loaded.' -f $merged.Count)
        return $true
    } catch {
        Write-YumLogException -Context 'Intelligence view refresh failed' -Exception $_.Exception
        if($null -ne $State.Summary){$State.Summary.Text='Saved Intelligence could not be loaded. Check YUMRAM.log.'}
        Set-YumFooter '⚠ Intelligence view refresh failed.'
        return $false
    }
}

function Show-YumIntelligence {
    param([ValidateSet('All','Apps','Games','Protected','Background','Services','Review','Unknown')][string]$InitialFilter='All')
    try {
        if($null -ne $script:Yum.IntelligenceWindow){
            try {
                if($script:Yum.IntelligenceWindow.IsVisible){
                    $existing=$script:Yum.IntelligenceWindow.Tag
                    $desired = switch($InitialFilter){'Apps'{'Apps'};'Background'{'Apps'};'Games'{'Games'};'Protected'{'Protected'};'Services'{'Services'};'Review'{'Review'};'Unknown'{'Unknown'};default{'All Items'}}
                    for($i=0;$i -lt $existing.Filter.Items.Count;$i++){if([string]$existing.Filter.Items[$i].Content -eq $desired){$existing.Filter.SelectedIndex=$i;break}}
                    $script:Yum.IntelligenceWindow.Title = if($InitialFilter -eq 'All'){'YUMRAM - Intelligence'}else{('YUMRAM - Intelligence — {0}' -f $InitialFilter)}
                    $script:Yum.IntelligenceWindow.Activate()
                    return
                }
            } catch { $script:Yum.IntelligenceWindow=$null }
        }
        $path=Join-Path $script:Yum.Root 'UI\Xaml\Intelligence.xaml'
        if(-not (Test-Path -LiteralPath $path)){throw "Missing intelligence XAML: $path"}
        [xml]$xaml=Read-YumXamlText -Path $path
        $reader=New-Object System.Xml.XmlNodeReader $xaml
        $window=[Windows.Markup.XamlReader]::Load($reader)
        if($null -eq $window){throw 'Intelligence window could not be created.'}

        $state=@{
            Window=$window
            ListView=$window.FindName('IntelligenceResults'); Filter=$window.FindName('Filter'); Search=$window.FindName('Search')
            Refresh=$window.FindName('Refresh'); RefreshView=$window.FindName('RefreshView'); RunResearch=$window.FindName('RunResearch'); ResearchSelected=$window.FindName('ResearchSelected'); Close=$window.FindName('Close'); ApplyOrganization=$window.FindName('ApplyOrganization'); ClearOrganization=$window.FindName('ClearOrganization'); ManualCategory=$window.FindName('ManualCategory'); ManualOrganizationStatus=$window.FindName('ManualOrganizationStatus')
            Details=$window.FindName('Details'); Summary=$window.FindName('Summary'); LastScan=$window.FindName('LastScan')
            Busy=$false; ResearchBusy=$false; ResearchRunId=''; ForceFreshResearch=$false; ResearchConcurrency=1; ResearchProgressCount=0; ResearchProgressText='Ready'; ResearchPendingManual=$false; Data=$null; Timer=$null; SearchTimer=$null; LastListSignature='';LastRenderedRevision=-1
            ScannedCount=$window.FindName('ScannedCount'); ReviewCount=$window.FindName('ReviewCount'); ResearchingCount=$window.FindName('ResearchingCount'); ResolvedCount=$window.FindName('ResolvedCount'); UnknownCount=$window.FindName('UnknownCount'); ProtectedCount=$window.FindName('ProtectedCount'); CachedCount=$window.FindName('CachedCount'); ResearchErrorCount=$window.FindName('ResearchErrorCount')
            OverviewMessage=$window.FindName('OverviewMessage'); DatabaseStatus=$window.FindName('DatabaseStatus'); DatabaseCount=$window.FindName('DatabaseCount'); ResearchProgress=$window.FindName('ResearchProgress'); ActivityStatus=$window.FindName('ActivityStatus'); ActivityDetail=$window.FindName('ActivityDetail'); ActivityProgress=$window.FindName('ActivityProgress'); SelectedResearch=$window.FindName('SelectedResearch'); SelectedAction=$window.FindName('SelectedAction')
        }
        try {
            [void](Load-YumIntelligenceDb)
            if($null -eq $script:Yum.IntelligenceDb -or -not ($script:Yum.IntelligenceDb -is [hashtable])){$script:Yum.IntelligenceDb=@{}}
            $initial=[pscustomobject]@{Records=@();Timestamp=Get-Date;ProcessCount=0;ServiceCount=0;AppCount=0;Errors=@();SavedCount=[int]$script:Yum.IntelligenceDb.Count;DatabaseCount=[int]$script:Yum.IntelligenceDb.Count;Status='Completed';DurationMs=0}
            $state.Data=$initial
            # Load every persisted record defensively; one corrupt legacy item must never blank the page.
            $tmp=New-Object System.Collections.Generic.List[object]
            foreach($saved in @($script:Yum.IntelligenceDb.Values)){
                if($null -eq $saved){continue}
                try{
                    [void](Ensure-YumIntelligenceRecordSchema -Record $saved)
                    $saved.Live=$false;$saved.StateText='SAVED';$saved.Memory='—';$saved.CPU='—';$saved.PID='—'
                    if([string]::IsNullOrWhiteSpace([string]$saved.Reason)){$saved.Reason='Saved classification; not present in current live scan.'}
                    [void]$tmp.Add($saved)
                }catch{Write-YumLogException -Context ('Saved Intelligence record skipped during initial load: {0}' -f [string]$saved.Name) -Exception $_.Exception}
            }
            $state.Data.Records=@($tmp.ToArray())
        } catch {
            Write-YumLogException -Context 'Initial Intelligence database load failed' -Exception $_.Exception
            $state.Data=[pscustomobject]@{Records=@();Timestamp=Get-Date;ProcessCount=0;ServiceCount=0;AppCount=0;Errors=@('Saved Intelligence load failed');SavedCount=0;DatabaseCount=0;Status='Completed';DurationMs=0}
        }
        foreach($name in @('ListView','Filter','Search','Refresh','RefreshView','RunResearch','ResearchSelected','Close','ApplyOrganization','ClearOrganization','ManualCategory','ManualOrganizationStatus','Details','Summary','LastScan','ScannedCount','ReviewCount','ResearchingCount','ResolvedCount','UnknownCount','ProtectedCount','CachedCount','ResearchErrorCount','OverviewMessage','DatabaseStatus','DatabaseCount','ResearchProgress','ActivityStatus','ActivityDetail','ActivityProgress','SelectedResearch','SelectedAction')){
            if($null -eq $state[$name]){throw "Intelligence UI control missing: $name"}
        }
        foreach($c in @($state.Filter,$state.Search,$state.Refresh,$state.RefreshView,$state.RunResearch,$state.ResearchSelected,$state.Close,$state.ApplyOrganization,$state.ClearOrganization,$state.ManualCategory)){$c.Tag=$state}
        $state['ListView'].Tag=$state
        try { Add-YumOrganizationContextMenu -ListView $state.ListView -State $state -Mode 'Intelligence' } catch { Write-YumLogException -Context 'Intelligence organization menu attach failed' -Exception $_.Exception }
        $window.Tag=$state
        $script:Yum.IntelligenceWindow=$window

        $state.Refresh.Add_Click({
            param($s,$e)
            try {
                $ctx=$s.Tag
                if($ctx.Busy -or $ctx.ResearchBusy){return}
                $ctx.ForceFreshResearch=$false
                $ctx.Summary.Text='Running Intelligence Scan. Unresolved items remain available for manual research.'
                try{$ctx.ActivityStatus.Text='SCANNING SYSTEM';$ctx.ActivityDetail.Text='Collecting processes, services, apps, startup entries, and identity evidence…';$ctx.ActivityProgress.IsIndeterminate=$true;$ctx.ActivityProgress.Value=0;$ctx.Refresh.Content='⏳ SCANNING…';$ctx.RunResearch.IsEnabled=$false}catch{}
                Start-YumIntelligenceScanAsync -State $ctx
            } catch { Write-YumLogException -Context 'Manual Intelligence Scan failed' -Exception $_.Exception; $s.Tag.Summary.Text='Intelligence Scan could not start. Check YUMRAM.log.'; $s.Tag.Busy=$false }
        })
        $state.RefreshView.Add_Click({param($s,$e)try{if($s.Tag.Busy -or $s.Tag.ResearchBusy){return};[void](Refresh-YumIntelligenceView -State $s.Tag)}catch{Write-YumLogException -Context 'Manual Intelligence view refresh failed' -Exception $_.Exception}})

        $state.Filter.Add_SelectionChanged({param($s,$e)try{Update-YumIntelligenceList -State $s.Tag -Force}catch{Write-YumLogException -Context 'Intelligence filter failed' -Exception $_.Exception}})
        $state.SearchTimer=New-Object System.Windows.Threading.DispatcherTimer
        $state.SearchTimer.Interval=[TimeSpan]::FromMilliseconds(250)
        $state.SearchTimer.Tag=$state
        $state.SearchTimer.Add_Tick({param($s,$e)$s.Stop();try{Update-YumIntelligenceList -State $s.Tag -Force}catch{Write-YumLogException -Context 'Intelligence debounced search failed' -Exception $_.Exception}})
        $state.Search.Add_TextChanged({param($s,$e)try{$timer=$s.Tag.SearchTimer;if($null -ne $timer){$timer.Stop();$timer.Start()}}catch{Write-YumLogException -Context 'Intelligence search debounce failed' -Exception $_.Exception}})
        $state['ListView'].Add_SelectionChanged({
            param($s,$e)
            try {
                $ctx=$s.Tag
                if($null -ne $s.SelectedItem -and $null -ne $ctx){
                    $r=$s.SelectedItem
                    try{[void](Ensure-YumIntelligenceRecordSchema -Record $r)}catch{Write-YumLogException -Context 'Intelligence selection schema normalization failed' -Exception $_.Exception}
$stateLabel=if($null -ne $r.StateText){[string]$r.StateText}else{if($r.Live){'LIVE'}else{'SAVED'}};$manual=if($null -ne $r.PSObject.Properties['ManualOverride'] -and [bool]$r.ManualOverride){'YES'}else{'NO'};$sources=if($null -ne $r.PSObject.Properties['ResearchSources']){(@($r.ResearchSources) -join ', ')}else{''};$links=if($null -ne $r.PSObject.Properties['ResearchLinks']){(@($r.ResearchLinks) -join '
')}else{''};$identityState=[string]$r.IdentityState;if([string]::IsNullOrWhiteSpace($identityState)){$identityState='Not recorded'};$identityConfidence=if($null -ne $r.PSObject.Properties['IdentityConfidence']){[int]$r.IdentityConfidence}else{[int]$r.Confidence};$unknownReason=[string]$r.UnknownReason;if([string]::IsNullOrWhiteSpace($unknownReason)){$unknownReason=[string]$r.ResearchReason};$hash='';try{if($null -ne $r.PSObject.Properties['FileHash']){$hash=[string]$r.FileHash}}catch{};if([string]::IsNullOrWhiteSpace($hash)){$hash='Not calculated yet'};$signature='Unknown';try{if($null -ne $r.PSObject.Properties['Signature']){$signature=[string]$r.Signature};if([string]::IsNullOrWhiteSpace($signature) -and $null -ne $r.PSObject.Properties['SignerThumbprint']){$signature=[string]$r.SignerThumbprint}}catch{};if([string]::IsNullOrWhiteSpace($signature)){$signature='Unknown'};$ctx.Details.Text=('State: {0}`nName: {1}`nCategory: {2}`nRisk: {3}`nPlacement: {4}`nPublisher: {5}`nIdentity: {6} ({7}% confidence)`nSignature: {8}`nSHA-256: {9}`nManual override: {10}`nEvidence: {11}`nWhy Unknown: {12}`nSources: {13}' -f $stateLabel,$r.Name,$r.Category,$r.Risk,$r.Placement,$r.Publisher,$identityState,$identityConfidence,$signature,$hash,$manual,$r.Reason,$unknownReason,$sources);if($null -ne $ctx.SelectedResearch){$liveStage=if($null -ne $r.PSObject.Properties['ResearchProgressStage']){[string]$r.ResearchProgressStage}else{''};$liveMessage=if($null -ne $r.PSObject.Properties['ResearchProgressMessage']){[string]$r.ResearchProgressMessage}else{''};$liveLine=if(-not [string]::IsNullOrWhiteSpace($liveStage)){('`nLive progress: {0} — {1}' -f $liveStage,$liveMessage)}else{''};$ctx.SelectedResearch.Text=('Research: {0}`nConfidence: {1}%`nComplete: {2}`nPerformed: {3}`nExhausted: {4}`nError: {5}{6}' -f [string]$r.ResearchStatus,[string]$r.ResearchConfidence,[bool]$r.ResearchComplete,[bool]$r.ResearchPerformed,[bool]$r.ResearchExhausted,[string]$r.ResearchErrorState,$liveLine)};if($null -ne $ctx.SelectedAction){$ctx.SelectedAction.Text=('Action Lane: {0}`nRecommendation: {1}' -f [string]$r.ActionLane,[string]$r.Recommendation)}};try{if($null -ne $ctx.ManualOrganizationStatus){$ctx.ManualOrganizationStatus.Text=if([bool]$r.ManualOverride){('MANUAL OVERRIDE SAVED • ' + [string]$r.Category)}else{'No manual override selected.'}}}catch{}
            } catch { Write-YumLogException -Context 'Intelligence selection update failed' -Exception $_.Exception }
        })

        $state.ApplyOrganization.Add_Click({param($s,$e)try{
            $ctx=$s.Tag; $item=$ctx.ListView.SelectedItem
            if($null -eq $item){$ctx.ManualOrganizationStatus.Text='Select a record first.';return}
            $cat=[string]$ctx.ManualCategory.SelectedItem.Content
            if([string]::IsNullOrWhiteSpace($cat)){$ctx.ManualOrganizationStatus.Text='Choose a category first.';return}
            $placement=switch($cat){'Games / Gaming'{'Games / Gaming'};'User Background Apps'{'User Background Apps'};'Identified Applications'{'Identified Applications'};'Security'{'Security'};'Drivers / Hardware'{'Drivers / Hardware'};'Startup Inventory'{'Startup Inventory'};'Review Queue'{'Review Queue'};default{'Unknown / Quarantine for Review'}}
            $action=switch($cat){'Games / Gaming'{'Protect during gaming'};'User Background Apps'{'Candidate only under memory pressure'};'Identified Applications'{'Candidate under memory pressure when research supports it'};'Security'{'Protect; never manage automatically'};'Drivers / Hardware'{'Protect; never manage automatically'};'Startup Inventory'{'Review startup behavior before changes'};'Review Queue'{'Research/review before management'};default{'Never manage automatically'}}
            $loadedOrgs=Load-YumManualOrganizations;$previousOrgs=@{};foreach($k in $loadedOrgs.Keys){$previousOrgs[$k]=$loadedOrgs[$k]}
            $org=Set-YumManualOrganization -Item $item -Category $cat -Placement $placement -ActionLane $action
            $item.Category=$org.Category;$item.Placement=$org.Placement;$item.ActionLane=$org.ActionLane;$item.Recommendation=$org.ActionLane;$item.ManualOverride=$true;$item.ManualOrganizationUpdated=$org.Updated
            $stable='';try{$stable=[string](Get-YumStableIntelligenceKey -Record $item)}catch{};$key=if(-not [string]::IsNullOrWhiteSpace($stable)){$stable}else{[string]$item.Key}
            if(-not [string]::IsNullOrWhiteSpace($key)){
                $script:Yum.IntelligenceDb[$key]=$item
                if(-not (Save-YumIntelligenceDb -Database $script:Yum.IntelligenceDb)){
                    [void](Save-YumManualOrganizations -Organizations $previousOrgs)
                    throw 'Intelligence database save failed; manual organization was rolled back.'
                }
            }
            [void](Refresh-YumIntelligenceView -State $ctx)
            $ctx.ManualOrganizationStatus.Text=('SAVED • {0} → {1}' -f [string]$item.Name,$cat)
            Set-YumFooter ('📁 Manual organization saved • {0} → {1}' -f [string]$item.Name,$cat)
        }catch{Write-YumLogException -Context 'Manual Intelligence organization apply failed' -Exception $_.Exception;try{$s.Tag.ManualOrganizationStatus.Text='Save failed — no changes were committed. Check YUMRAM.log.'}catch{}}})

        $state.ClearOrganization.Add_Click({param($s,$e)try{
            $ctx=$s.Tag;$item=$ctx.ListView.SelectedItem
            if($null -eq $item){$ctx.ManualOrganizationStatus.Text='Select a record first.';return}
            $loadedOrgs=Load-YumManualOrganizations;$previousOrgs=@{};foreach($k in $loadedOrgs.Keys){$previousOrgs[$k]=$loadedOrgs[$k]}
            $orgs=Load-YumManualOrganizations;$identity=Get-YumRecordIdentityFields -Item $item;$key=Get-YumManualOrganizationKey -Name ([string]$item.Name) -Path ([string]$item.Path) -Publisher ([string]$item.Publisher) -FileHash $identity.FileHash -SignerThumbprint $identity.SignerThumbprint;$legacy=Get-YumManualOrganizationKey -Name ([string]$item.Name) -Path ([string]$item.Path) -Publisher ([string]$item.Publisher)
            if($orgs.ContainsKey($key)){$orgs.Remove($key)};if($orgs.ContainsKey($legacy)){$orgs.Remove($legacy)}
            if(-not (Save-YumManualOrganizations -Organizations $orgs)){throw 'Manual organization reset could not be saved.'}
            $item.Category='Review Queue';$item.Placement='Review Queue';$item.ActionLane='Research/review before management';$item.Recommendation='Research/review before management';$item.Risk='Review';$item.ManualOverride=$false;$item.ManualOrganizationUpdated='';$item.ResearchStatus='Review';$item.ResearchComplete=$false;$item.ResearchPerformed=$false;$item.ResearchExhausted=$false;$item.ResearchConfidence=0;$item.ResearchSources=@();$item.ResearchLinks=@();$item.ResearchReason='Awaiting manual research.';$item.ResearchErrorState='';$item.ResearchStarted='';$item.ResearchCompleted='';$item.OnlineResearchPerformed=$false;$item.ResearchRunDisposition='Unchanged';$item.ResearchRunResolved=$false;$item.ResearchRunOnline=$false;$item.AutoResearchEligible=$true
            $stable='';try{$stable=[string](Get-YumStableIntelligenceKey -Record $item)}catch{};$saveKey=if(-not [string]::IsNullOrWhiteSpace($stable)){$stable}else{[string]$item.Key};if(-not [string]::IsNullOrWhiteSpace($saveKey)){$script:Yum.IntelligenceDb[$saveKey]=$item;if(-not (Save-YumIntelligenceDb -Database $script:Yum.IntelligenceDb)){[void](Save-YumManualOrganizations -Organizations $previousOrgs);throw 'Intelligence database save failed; reset was rolled back.'}}
            [void](Refresh-YumIntelligenceView -State $ctx);$ctx.ManualOrganizationStatus.Text=('RESET • {0} is back in Review Queue.' -f [string]$item.Name);Set-YumFooter ('↩ Manual organization reset • {0}' -f [string]$item.Name)
        }catch{Write-YumLogException -Context 'Manual Intelligence organization reset failed' -Exception $_;try{$s.Tag.ManualOrganizationStatus.Text='Reset failed — no changes were committed. Check YUMRAM.log.'}catch{}}})

        $state.ResearchSelected.Add_Click({param($s,$e)try{
            $ctx=$s.Tag;$item=$ctx.ListView.SelectedItem
            if($null -eq $item){Set-YumFooter 'Select an item first.';return}
            if($ctx.ResearchBusy){Set-YumFooter 'Research is already running.';return}
            $ctx.ForceFreshResearch=$true;$ctx.ResearchPendingManual=$false;$ctx.RunResearch.IsEnabled=$false;$ctx.ResearchSelected.IsEnabled=$false;$ctx.Refresh.IsEnabled=$false;$ctx.ActivityStatus.Text='RESEARCHING SELECTED';$ctx.ActivityDetail.Text=('Researching {0} using local identity evidence and optional corroboration.' -f [string]$item.Name);$ctx.ActivityProgress.IsIndeterminate=$true
            Start-YumIntelligenceResearchAsync -State $ctx -Records @($item)
        }catch{Write-YumLogException -Context 'Research selected item failed' -Exception $_.Exception}})

        $state.RunResearch.Add_Click({param($s,$e)try{
            $ctx=$s.Tag
            if($null -eq $ctx){throw 'Research button state is unavailable.'}
            if($ctx.ResearchBusy){
                $ctx.ResearchPendingManual=$true
                $ctx.ForceFreshResearch=$true
                $ctx.Summary.Text='Research is already running. A fresh manual retry will start after the current run.'
                Set-YumFooter '🧠 Research is already running • manual retry queued.'
                return
            }
            if($ctx.Busy){Set-YumFooter 'Intelligence Scan is still running. Research will be available when the scan finishes.';return}
            $records=@(); if($null -ne $ctx.Data -and $null -ne $ctx.Data.Records){$records=@($ctx.Data.Records|Where-Object{$null -ne $_})}
            if($records.Count -eq 0){Set-YumFooter 'No Intelligence records are loaded yet. Run Scan or reopen Intelligence.';return}
            # Primary queue: canonical unresolved predicate. Fallback keeps the manual button usable
            # for legacy records whose category/status fields were not migrated perfectly.
            $queue=@($records|Where-Object{Test-YumResearchUnresolved -Record $_})
            if($queue.Count -eq 0){
                $queue=@($records|Where-Object{
                    $manual=(($null -ne $_.PSObject.Properties['ManualOverride']) -and [bool]$_.ManualOverride)
                    $status=if($null -ne $_.PSObject.Properties['ResearchStatus']){[string]$_.ResearchStatus}else{'Not Researched'}
                    $risk=[string]$_.Risk; $category=[string]$_.Category
                    (-not $manual) -and $status -notin @('Organized','Unknown','Researching') -and $risk -ne 'Protected' -and $category -notin @('Security','Drivers / Hardware')
                })
            }
            if($queue.Count -eq 0){Set-YumFooter 'No items currently require research. Use Run Scan to refresh the inventory.';return}
            $ctx.ResearchPendingManual=$false
            # A user pressing RUN RESEARCH is an explicit research request.
            # It must bypass the passive cache/auto-research gate and actually execute the research pipeline.
            $ctx.ForceFreshResearch=$true
            try{ Write-YumLog ('MANUAL RESEARCH ACCEPTED: {0} records queued; ForceFreshResearch=true; OnlineResearch={1}.' -f $queue.Count,[bool]$script:Yum.Config.EnableOnlineResearch) }catch{}
            $ctx.Summary.Text=('RUN RESEARCH is executing {0} items — local evidence first, online verification when required.' -f $queue.Count)
            Set-YumFooter ('🧠 Manual research started • {0} items.' -f $queue.Count)
            if($null -ne $ctx.RunResearch){$ctx.RunResearch.IsEnabled=$false}
            Start-YumIntelligenceResearchAsync -State $ctx -Records $queue
        }catch{Write-YumLogException -Context 'Manual Intelligence Research failed' -Exception $_.Exception;try{if($null -ne $s.Tag -and $null -ne $s.Tag.Summary){$s.Tag.Summary.Text='Research could not start. Check YUMRAM.log.'};Set-YumFooter '⚠ Manual research could not start. Check YUMRAM.log.'}catch{}}})
        $state.Timer=New-Object System.Windows.Threading.DispatcherTimer
        $state.Timer.Interval=[TimeSpan]::FromMilliseconds(500)
        $state.Timer.Tag=$state
        $state.Timer.Add_Tick({param($s,$e)
            $ctx=$s.Tag
            try {
                # Intelligence owns its own UI refresh loop. The main-window timer cannot refresh
                # this dialog because it is a separate WPF window with its own state snapshot.
                if($null -ne $ctx -and $ctx.Window.IsVisible){
                    try { Get-YumResearchStatusForUi -State $ctx | Out-Null } catch {}
                    try { if((-not $ctx.Busy -and -not $ctx.ResearchBusy) -and ((@($ctx.Data.Records)).Count -eq 0)){[void](Refresh-YumIntelligenceView -State $ctx)} else { Update-YumIntelligenceList -State $ctx } } catch { Write-YumLogException -Context 'Intelligence live UI refresh failed' -Exception $_.Exception }
                }
            } catch { Write-YumLogException -Context 'Intelligence UI timer failed' -Exception $_.Exception }
        })
        $state.Timer.Start()

        $state.Close.Add_Click({param($s,$e)
            try { if($null -ne $s.Tag.Timer){$s.Tag.Timer.Stop();$s.Tag.Timer.Dispose()} } catch {}
            try { $s.Tag.SearchTimer.Stop() } catch {}
            try { $script:Yum.IntelligenceWindow=$null } catch {}
            $s.Tag.Window.Close()
        })

        $window.Owner=$script:Yum.Window
        $window.Title = if($InitialFilter -eq 'All'){'YUMRAM - Intelligence'}else{('YUMRAM - Intelligence — {0}' -f $InitialFilter)}
        $desiredFilter = switch($InitialFilter){
            'Apps' {'Apps'}
            'Background' {'Apps'}
            'Games' {'Games'}
            'Protected' {'Protected'}
            'Services' {'Services'}
            'Review' {'Needs Research'}
            'Unknown' {'Unknown'}
            default {'Overview'}
        }
        # Select by visible content rather than hard-coded indexes so UI reordering cannot route to the wrong category.
        for($i=0;$i -lt $state.Filter.Items.Count;$i++){
            $item=$state.Filter.Items[$i]
            if($null -ne $item -and [string]$item.Content -eq $desiredFilter){$state.Filter.SelectedIndex=$i;break}
        }
        try { [void](Refresh-YumIntelligenceView -State $state) } catch { Write-YumLogException -Context 'Initial Intelligence view refresh failed' -Exception $_.Exception }
        # Attach this Intelligence window to a Research pass that is already running elsewhere.
        try {
            $statusPath=Join-Path $script:Yum.Root 'research-status.json'
            if(Test-Path -LiteralPath $statusPath){
                $statusRaw=Get-Content -LiteralPath $statusPath -Raw -ErrorAction Stop
                if(-not [string]::IsNullOrWhiteSpace($statusRaw)){
                    $status=$statusRaw|ConvertFrom-Json -ErrorAction Stop
                    $stage=[string]$status.Stage
                    if($stage -in @('Started','Queued','Researching Item','Researching Local','Researching Online')){
                        $state.ResearchBusy=$true
                        [void](Merge-YumLiveResearchResults -State $state)
                        [void](Get-YumResearchStatusForUi -State $state)
                        Update-YumIntelligenceList -State $state -Force
                    }
                }
            }
        } catch { Write-YumLogException -Context 'Intelligence live Research attach failed' -Exception $_.Exception }

        # Scan is manual; unresolved records remain queued until the user explicitly starts Run Research.
        try{if(-not $state.ResearchBusy){$state.ActivityStatus.Text='READY';$state.ActivityDetail.Text=('Saved knowledge loaded • {0} items need research.' -f @($state.Data.Records|Where-Object{Test-YumResearchUnresolved -Record $_}).Count);$state.ActivityProgress.IsIndeterminate=$false;$state.ActivityProgress.Value=0}}catch{}
        [void]$window.Show()
        $window.Activate()
    } catch {
        Write-YumLogException -Context 'Intelligence window failed' -Exception $_.Exception
        try { Show-YumMessage -Message ('Smart Intelligence could not be opened.`n`n{0}' -f $_.Exception.Message) -Title 'YUMRAM - Intelligence Error' -Buttons 'OK' -Icon 'Error' } catch { Write-YumLogException -Context 'Intelligence error dialog failed' -Exception $_.Exception }
    }
}

function Get-YumResearchStatusForUi {
    param([hashtable]$State)
    try {
        $statusPath=Join-Path $script:Yum.Root 'research-status.json'
        if(-not (Test-Path -LiteralPath $statusPath)){return $false}
        $raw=Get-Content -LiteralPath $statusPath -Raw -ErrorAction Stop
        if([string]::IsNullOrWhiteSpace($raw)){return $false}
        $status=$raw|ConvertFrom-Json -ErrorAction Stop
        $stage=[string]$status.Stage
        $name=[string]$status.Name
        $index=[int]$status.Index
        $total=[int]$status.Total
        $message=[string]$status.Message
        if($stage -in @('Started','Queued','Researching Item','Researching Local','Researching Online','Organized','Unknown','Research Error','Error','Complete')){
            if($stage -in @('Started','Queued','Researching Item','Researching Local','Researching Online')){
                $State.ResearchBusy=$true
                try {
                    if($null -ne $State.Data -and $null -ne $State.Data.PSObject.Properties['Records']){
                        foreach($record in $State.Data.Records){
                            if($null -ne $record -and [string]$record.Key -eq [string]$status.Key){
                                $terminal=$false
                                try {
                                    $rs=[string]$record.ResearchStatus
                                    $complete=[bool]$record.ResearchComplete
                                    $terminal=($complete -and $rs -in @('Organized','Unknown','Research Error'))
                                } catch {}
                                # Never let a transient status file regress an already terminal record.
                                if($terminal){ return $true }
                                $record|Add-Member -NotePropertyName ResearchStatus -NotePropertyValue 'Researching' -Force
                                $record|Add-Member -NotePropertyName ResearchProgressStage -NotePropertyValue $stage -Force
                                $record|Add-Member -NotePropertyName ResearchProgressMessage -NotePropertyValue $message -Force
                                $record|Add-Member -NotePropertyName ResearchProgressIndex -NotePropertyValue $index -Force
                                $record|Add-Member -NotePropertyName ResearchProgressTotal -NotePropertyValue $total -Force
                                break
                            }
                        }
                    }
                } catch {}
                try { Update-YumIntelligenceList -State $State -Force } catch {}
            }
            if($null -ne $State.ResearchProgress){
                if($stage -eq 'Complete'){ $State.ResearchProgress.Text=('Complete • {0}' -f $message); try{$State.ActivityStatus.Text='RESEARCH COMPLETE';$State.ActivityDetail.Text=$message;$State.ActivityProgress.IsIndeterminate=$false;$State.ActivityProgress.Value=100}catch{} } elseif($stage -eq 'Research Error'){ $State.ResearchProgress.Text=('Research ERROR {0}/{1} • {2} • {3}' -f $index,$total,$name,$message); try{$State.ActivityStatus.Text='RESEARCH ERROR';$State.ActivityDetail.Text=$message;$State.ActivityProgress.IsIndeterminate=$false;$State.ActivityProgress.Value=([math]::Min(100,[math]::Max(0,($index / [double][math]::Max(1,$total))*100)))}catch{} }
                elseif($total -gt 0){ $State.ResearchProgress.Text=('Research {0}/{1} • {2}' -f $index,$stage); try{$State.ActivityStatus.Text=('RESEARCHING • {0}/{1}' -f $index,$total);$State.ActivityDetail.Text=('{0} • {1}' -f $stage,$name);$State.ActivityProgress.IsIndeterminate=$false;$State.ActivityProgress.Value=[math]::Min(100,[math]::Max(0,($index / [double]$total)*100))}catch{} }
                else { $State.ResearchProgress.Text=('Research • {0}' -f $stage) }
            }
            if($stage -in @('Organized','Unknown','Research Error','Error','Complete','Skipped')){
                $State.ResearchBusy=$false
            }
            if($null -ne $State.Summary -and $stage -in @('Queued','Researching Item','Researching Local','Researching Online')){
                $State.Summary.Text=('Scan complete • Research {0}/{1} • {2} • {3}' -f $index,$total,$stage,$name)
            }
            return $true
        }
    } catch {}
    return $false
}


function Merge-YumLiveResearchResults {
    param([Parameter(Mandatory=$true)][hashtable]$State,[string]$RunId='')
    # One atomic checkpoint is shared by the worker and the Intelligence UI. No per-item files are created.
    try {
        $path=Join-Path $script:Yum.Root 'research-live-results.json'
        if(-not (Test-Path -LiteralPath $path)){return $false}
        $mutex=$null;$lockTaken=$false
        try{
            $mutex=New-Object System.Threading.Mutex($false,'Global\YUMRAM-ResearchLiveCheckpoint')
            $lockTaken=$mutex.WaitOne([TimeSpan]::FromSeconds(2))
            if(-not $lockTaken){return $false}
            $raw=Get-Content -LiteralPath $path -Raw -ErrorAction Stop
        } finally {
            if($lockTaken){try{$mutex.ReleaseMutex()}catch{}}
            if($null -ne $mutex){try{$mutex.Dispose()}catch{}}
        }
        if([string]::IsNullOrWhiteSpace($raw)){return $false}
        $snapshot=$raw | ConvertFrom-Json -ErrorAction Stop
        if($null -eq $snapshot -or $null -eq $snapshot.PSObject.Properties['Records']){return $false}
        $snapshotRunId='';try{$snapshotRunId=[string]$snapshot.RunId}catch{}
        if(-not [string]::IsNullOrWhiteSpace($RunId) -and -not [string]::IsNullOrWhiteSpace($snapshotRunId) -and $snapshotRunId -ne $RunId){return $false}
        if(-not [string]::IsNullOrWhiteSpace($snapshotRunId)){$State.ResearchRunId=$snapshotRunId}
        $completed=0;try{$completed=[int]$snapshot.Completed}catch{}
        $lastCompleted=0;try{$lastCompleted=[int]$State.ResearchLastMergedCompleted}catch{}
        if($completed -lt $lastCompleted){return $false}
        $updates=@($snapshot.Records | Where-Object { $null -ne $_ })
        $oldRecords=@()
        if($null -ne $State.Data -and $null -ne $State.Data.PSObject.Properties['Records']){$oldRecords=@($State.Data.Records | Where-Object { $null -ne $_ })}
        $merged=@($oldRecords)
        foreach($updated in $updates){
            try{[void](Ensure-YumIntelligenceRecordSchema -Record $updated)}catch{continue}
            $key=[string]$updated.Key
            if([string]::IsNullOrWhiteSpace($key)){continue}
            $found=$false
            for($i=0;$i -lt $merged.Count;$i++){
                if($null -ne $merged[$i] -and [string]$merged[$i].Key -eq $key){
                    $existing=$merged[$i]
                    $existingTerminal=$false
                    try{$existingTerminal=([bool]$existing.ResearchComplete -and [string]$existing.ResearchStatus -in @('Organized','Unknown','Research Error'))}catch{}
                    $updatedTransient=$false
                    try{$updatedTransient=([string]$updated.ResearchStatus -eq 'Researching' -or -not [bool]$updated.ResearchComplete)}catch{}
                    if($existingTerminal -and $updatedTransient){continue}
                    $merged[$i]=$updated
                    $found=$true
                    break
                }
            }
            if(-not $found){$merged += $updated}
        }
        $State.Data=[pscustomobject]@{
            Records=$merged
            Timestamp=if($null -ne $State.Data -and $null -ne $State.Data.PSObject.Properties['Timestamp']){$State.Data.Timestamp}else{Get-Date}
            ProcessCount=if($null -ne $State.Data -and $null -ne $State.Data.PSObject.Properties['ProcessCount']){[int]$State.Data.ProcessCount}else{0}
            ServiceCount=if($null -ne $State.Data -and $null -ne $State.Data.PSObject.Properties['ServiceCount']){[int]$State.Data.ServiceCount}else{0}
            AppCount=if($null -ne $State.Data -and $null -ne $State.Data.PSObject.Properties['AppCount']){[int]$State.Data.AppCount}else{0}
            Errors=if($null -ne $State.Data -and $null -ne $State.Data.PSObject.Properties['Errors']){@($State.Data.Errors)}else{@()}
            Status='Researching'
            DurationMs=if($null -ne $State.Data -and $null -ne $State.Data.PSObject.Properties['DurationMs']){[int]$State.Data.DurationMs}else{0}
            SavedCount=if($null -ne $script:Yum.IntelligenceDb){[int]$script:Yum.IntelligenceDb.Count}else{0}
            DatabaseCount=if($null -ne $script:Yum.IntelligenceDb){[int]$script:Yum.IntelligenceDb.Count}else{0}
            ResearchCount=if($null -ne $snapshot.PSObject.Properties['ResearchedCount']){[int]$snapshot.ResearchedCount}else{0}
            CachedCount=if($null -ne $snapshot.PSObject.Properties['CachedCount']){[int]$snapshot.CachedCount}else{0}
            OnlineResearchCount=if($null -ne $snapshot.PSObject.Properties['OnlineResearchCount']){[int]$snapshot.OnlineResearchCount}else{0}
            ReviewResolvedCount=if($null -ne $snapshot.PSObject.Properties['ReviewResolvedCount']){[int]$snapshot.ReviewResolvedCount}else{0}
            UnknownCount=if($null -ne $snapshot.PSObject.Properties['UnknownCount']){[int]$snapshot.UnknownCount}else{0}
            ResearchErrorCount=if($null -ne $snapshot.PSObject.Properties['ResearchErrorCount']){[int]$snapshot.ResearchErrorCount}else{0}
            ResearchLiveRunId=$snapshotRunId
        }
        $State.ResearchLastMergedCompleted=$completed
        $total=0;try{$total=[int]$snapshot.Total}catch{}
        $State.ResearchProgressCount=$completed
        $State.ResearchProgressText=('Research {0}/{1} • live results updated' -f $completed,$total)
        Update-YumIntelligenceList -State $State -Force
        return $true
    } catch {
        Write-YumLogException -Context 'Live Intelligence research checkpoint merge failed' -Exception $_.Exception
        return $false
    }
}

function Remove-YumOwnedResearchLiveCheckpoint {
    param([string]$Path,[string]$RunId='')
    try {
        if([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path)){return}
        if([string]::IsNullOrWhiteSpace($RunId)){return}
        $raw=Get-Content -LiteralPath $Path -Raw -ErrorAction Stop
        if([string]::IsNullOrWhiteSpace($raw)){return}
        $snapshot=$raw|ConvertFrom-Json -ErrorAction Stop
        $owner='';try{$owner=[string]$snapshot.RunId}catch{}
        if(-not [string]::IsNullOrWhiteSpace($owner) -and $owner -eq $RunId){Remove-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue}
    } catch {}
}

function Start-YumIntelligenceResearchAsync {
    param([Parameter(Mandatory)][hashtable]$State,[object[]]$Records=@())
    # Normalize all research-state keys before strict-mode property access.
    # The Intelligence window can be reached through multiple WPF event paths;
    # do not assume every path populated every research key.
    foreach($entry in @{
        ResearchBusy=$false
        ResearchRunId=''
        ForceFreshResearch=$false
        ResearchConcurrency=1
        ResearchProgressCount=0
        ResearchProgressText='Ready'
        ResearchPendingManual=$false
    }.GetEnumerator()){
        if(-not $State.ContainsKey($entry.Key) -or $null -eq $State[$entry.Key]){ $State[$entry.Key]=$entry.Value }
    }
    $Records=@($Records | Where-Object { $null -ne $_ })
    if($Records.Count -eq 0){
        if($null -ne $State.Summary){$State.Summary.Text='No items currently require research.'}
        if($null -ne $State.OverviewMessage){$State.ResearchProgress.Text='Ready • No research items are queued.'}
        return
    }
    if($null -ne $State.ResearchBusy -and $State.ResearchBusy){return}
    $State.ResearchBusy=$true
    $root=$script:Yum.Root
    $config=$script:Yum.Config
    $forceFresh=[bool]$State.ForceFreshResearch
    $researchRecords=@($Records | Where-Object { $null -ne $_ })
    $runId=[guid]::NewGuid().ToString('N')
    try{Write-YumLog ('Research queue prepared: {0} non-null records.' -f $researchRecords.Count)}catch{}
    $liveResultsPath=Join-Path $root 'research-live-results.json'
    $queueDirectory=Join-Path $root 'Runtime'
    if(-not (Test-Path -LiteralPath $queueDirectory)){New-Item -ItemType Directory -Path $queueDirectory -Force | Out-Null}
    # Remove only orphaned transport artifacts from previous interrupted runs. Research
    # results/cache and diagnostics are intentionally preserved.
    try{
        foreach($stale in @(Get-ChildItem -LiteralPath $queueDirectory -Filter 'research-queue-*.json' -File -ErrorAction SilentlyContinue)){
            Remove-Item -LiteralPath $stale.FullName -Force -ErrorAction SilentlyContinue
        }
        foreach($stale in @(Get-ChildItem -LiteralPath $queueDirectory -Filter 'research-config-*.json' -File -ErrorAction SilentlyContinue)){
            Remove-Item -LiteralPath $stale.FullName -Force -ErrorAction SilentlyContinue
        }
    }catch{}
    try{
        foreach($stale in @(Get-ChildItem -LiteralPath $root -Filter 'research-live-results*.tmp' -File -ErrorAction SilentlyContinue)){
            Remove-Item -LiteralPath $stale.FullName -Force -ErrorAction SilentlyContinue
        }
    }catch{}
    $queuePath=Join-Path $queueDirectory ("research-queue-{0}.json" -f $runId)
    $configPath=Join-Path $queueDirectory ("research-config-{0}.json" -f $runId)
    try{Remove-YumOwnedResearchLiveCheckpoint -Path $liveResultsPath -RunId $runId}catch{}
    try{if(Test-Path -LiteralPath $queuePath){Remove-Item -LiteralPath $queuePath -Force -ErrorAction SilentlyContinue}}catch{}
    try{if(Test-Path -LiteralPath $configPath){Remove-Item -LiteralPath $configPath -Force -ErrorAction SilentlyContinue}}catch{}
    $worker=[powershell]::Create()
    try {
        # Cross-runspace transport uses atomic JSON files. This avoids PowerShell object-array coercion and pipeline JSON fragmentation.
        $queueJson = ConvertTo-Json -InputObject @($researchRecords) -Depth 20 -Compress
        $configJson = ConvertTo-Json -InputObject $config -Depth 20 -Compress
        $queueJson | Set-Content -LiteralPath $queuePath -Encoding UTF8 -ErrorAction Stop
        $configJson | Set-Content -LiteralPath $configPath -Encoding UTF8 -ErrorAction Stop
        try{Write-YumLog ('Research queue transport: records={0}; jsonBytes={1}; queueFile={2}; runId={3}' -f $researchRecords.Count,([Text.Encoding]::UTF8.GetByteCount([string]$queueJson)),$queuePath,[string]$runId)}catch{}
        [void]$worker.AddScript({param($root,$configPath,$recordsPath,$runId,$forceFresh)
            $ErrorActionPreference='Stop'
            $output=$null
            try {
                if(-not (Test-Path -LiteralPath $configPath)){throw "Research worker config transport file missing: $configPath"}
                if(-not (Test-Path -LiteralPath $recordsPath)){throw "Research worker queue transport file missing: $recordsPath"}
                $configJson=Get-Content -LiteralPath $configPath -Raw -ErrorAction Stop
                $recordsJson=Get-Content -LiteralPath $recordsPath -Raw -ErrorAction Stop
                $configObj=$configJson | ConvertFrom-Json -ErrorAction Stop
                $recordObj=$recordsJson | ConvertFrom-Json -ErrorAction Stop
                $script:Yum=[pscustomobject]@{Root=$root;ConfigDirectory=$root;Config=$configObj}
                $loggingPath=Join-Path $root 'Core\Logging.ps1';if(Test-Path -LiteralPath $loggingPath){. $loggingPath | Out-Null}
                $researchPath=Join-Path $root 'Core\Research.ps1';if(-not (Test-Path -LiteralPath $researchPath)){throw "Research module not found: $researchPath"};. $researchPath | Out-Null
                $workerRecords=@($recordObj | Where-Object { $null -ne $_ })
                try {
                    Write-YumLog ('RESEARCH WORKER STARTED: run={0}; records={1}; ForceFreshResearch={2}; OnlineResearch={3}; timeout={4}s' -f [string]$runId,$workerRecords.Count,[bool]$forceFresh,[bool]$script:Yum.Config.EnableOnlineResearch,[int]$script:Yum.Config.ResearchRequestTimeoutSeconds)
                } catch {}
                try{Write-YumLog ('Research worker transport received: records={0}; runId={1}' -f $workerRecords.Count,[string]$runId)}catch{}
                if($workerRecords.Count -eq 0){
                    $output=[pscustomobject]@{Records=@();ResearchedCount=0;CachedCount=0;OnlineResearchCount=0;ReviewResolvedCount=0;UnknownCount=0;CacheCount=0;ResearchErrorCount=0;OnlineEnabled=[bool]$script:Yum.Config.IntelligenceResearchEnabled;LocalClassificationComplete=$true;Errors=@('Research worker received an empty queue after file transport.');RunId=$runId}
                } else {
                    $output=Invoke-YumResearch -Records $workerRecords -RunId $runId -ForceFreshResearch:$forceFresh
                    try{Write-YumLog ('RESEARCH WORKER FINISHED: run={0}; researched={1}; cached={2}; organized={3}; unknown={4}; errors={5}' -f [string]$runId,[int]$output.ResearchedCount,[int]$output.CachedCount,[int]$output.ReviewResolvedCount,[int]$output.UnknownCount,[int]$output.ResearchErrorCount)}catch{}
                }
            } catch {
                $workerException=$_.Exception
                $workerErrorText=$workerException.ToString()
                try {
                    $diagDir=Join-Path $root 'Runtime'; if(-not(Test-Path -LiteralPath $diagDir)){New-Item -ItemType Directory -Path $diagDir -Force|Out-Null}
                    $diag=Join-Path $diagDir 'Research-Diagnostics.log'
                    $diagLine='[{0}] Run={1} Stage=Worker Failure Message={2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'),$runId,($workerErrorText -replace "`r|`n", ' | ')
                    [System.IO.File]::AppendAllText($diag,$diagLine+[Environment]::NewLine,([System.Text.UTF8Encoding]::new($false)))
                } catch {}
                try { Write-YumLogException -Context 'Research worker failure' -Exception $workerException } catch {}
                $errorRecords=New-Object System.Collections.Generic.List[object]
                foreach($wr in @($workerRecords)){
                    if($null -eq $wr){continue}
                    $wr|Add-Member -NotePropertyName Placement -NotePropertyValue 'Unknown / Quarantine for Review' -Force
                    $wr|Add-Member -NotePropertyName ActionLane -NotePropertyValue 'Never manage automatically' -Force
                    $wr|Add-Member -NotePropertyName Risk -NotePropertyValue 'Unknown' -Force
                    $wr|Add-Member -NotePropertyName Category -NotePropertyValue 'Unknown / Quarantine' -Force
                    $wr|Add-Member -NotePropertyName ResearchStatus -NotePropertyValue 'Research Error' -Force
                    $wr|Add-Member -NotePropertyName ResearchComplete -NotePropertyValue $true -Force
                    $wr|Add-Member -NotePropertyName ResearchPerformed -NotePropertyValue $false -Force
                    $wr|Add-Member -NotePropertyName ResearchExhausted -NotePropertyValue $true -Force
                    $wr|Add-Member -NotePropertyName ResearchErrorState -NotePropertyValue $workerErrorText -Force
                    $wr|Add-Member -NotePropertyName ResearchReason -NotePropertyValue ('Worker failure: {0}; item was terminally quarantined for retry/diagnostics.' -f $workerException.Message) -Force
                    $wr|Add-Member -NotePropertyName ResearchRunDisposition -NotePropertyValue 'Error' -Force
                    $wr|Add-Member -NotePropertyName ResearchRunResolved -NotePropertyValue $false -Force
                    $wr|Add-Member -NotePropertyName ResearchRunOnline -NotePropertyValue $false -Force
                    [void]$errorRecords.Add($wr)
                }
                $output=[pscustomobject]@{Records=$errorRecords.ToArray();ResearchedCount=0;OnlineResearchCount=0;ReviewResolvedCount=0;UnknownCount=0;CacheCount=0;ResearchErrorCount=$errorRecords.Count;OnlineEnabled=$false;LocalClassificationComplete=$false;Errors=@(('Research worker: {0}' -f $workerException.Message));RunId=$runId}
            }
            Write-Output ($output | ConvertTo-Json -Depth 20 -Compress)
        }).AddArgument($root).AddArgument($configPath).AddArgument($queuePath).AddArgument($runId).AddArgument($forceFresh)
        $async=$worker.BeginInvoke()
        $poll=New-Object System.Windows.Threading.DispatcherTimer
        $poll.Interval=[TimeSpan]::FromMilliseconds(400)
        $State.ResearchLastMergedCompleted=0
        $State.ResearchConcurrency=1; $State.ResearchProgressCount=0; $State.ResearchProgressText=('Queued • {0} items • 1 at a time' -f $researchRecords.Count)
        $State.ResearchRunId=$runId
    $workerTimeout=1800
        try{if($null -ne $config.PSObject.Properties['ResearchWorkerTimeoutSeconds']){$workerTimeout=[math]::Max(300,[int]$config.ResearchWorkerTimeoutSeconds)}}catch{}
        $poll.Tag=@{Worker=$worker;Async=$async;State=$State;Started=(Get-Date);TimeoutSeconds=$workerTimeout;RunId=$runId;QueuePath=$queuePath;ConfigPath=$configPath;LiveResultsPath=$liveResultsPath}
        $poll.Add_Tick({param($s,$e)
            $ctx=$s.Tag
            if(-not $ctx.Async.IsCompleted){
                try { Get-YumResearchStatusForUi -State $ctx.State | Out-Null } catch {}
                try { [void](Merge-YumLiveResearchResults -State $ctx.State -RunId $ctx.RunId) } catch {}
                if(((Get-Date)-$ctx.Started).TotalSeconds -ge [double]$ctx.TimeoutSeconds){
                    $s.Stop();try{$ctx.Worker.Stop()}catch{};try{$ctx.Worker.Dispose()}catch{}
                    $pending=$false;try{$pending=[bool]$ctx.State.ResearchPendingManual}catch{}
                    $ctx.State.ResearchBusy=$false;$ctx.State.ResearchRunId='';$ctx.State.ResearchProgressCount=0;$ctx.State.ResearchProgressText='Ready';$ctx.State.ForceFreshResearch=$false;$ctx.State.ResearchPendingManual=$false
                    try{if(Test-Path -LiteralPath $ctx.QueuePath){Remove-Item -LiteralPath $ctx.QueuePath -Force -ErrorAction SilentlyContinue}}catch{}
                    try{if(Test-Path -LiteralPath $ctx.ConfigPath){Remove-Item -LiteralPath $ctx.ConfigPath -Force -ErrorAction SilentlyContinue}}catch{}
                    try{Remove-YumOwnedResearchLiveCheckpoint -Path $ctx.LiveResultsPath -RunId $ctx.RunId}catch{}
                    $ctx.State.Summary.Text=if($pending){'Research timed out. Starting the queued manual retry.'}else{'Scan complete; automatic research timed out. Current scan results remain usable; Run Research can retry.'}
                    $timeoutFooter = if($pending){'⚠ Research timed out • starting queued manual retry.'}else{'⚠ Research timed out; Run Research can retry.'}
                    Set-YumFooter $timeoutFooter
                    if($pending){
                        try{
                            $retry=@($ctx.State.Data.Records|Where-Object{Test-YumResearchUnresolved -Record $_})
                            if($retry.Count -gt 0){$ctx.State.ForceFreshResearch=$true;$ctx.State.Window.Dispatcher.BeginInvoke([Action]{Start-YumIntelligenceResearchAsync -State $ctx.State -Records $retry})|Out-Null}
                        }catch{Write-YumLogException -Context 'Timeout queued manual retry failed' -Exception $_.Exception}
                    }
                    return
                }
                return
            }
            $s.Stop()
            try {
                $rawResults=@($ctx.Worker.EndInvoke($ctx.Async)) | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }
                try{
                    if($ctx.Worker.HadErrors){
                        foreach($err in @($ctx.Worker.Streams.Error)){ Write-YumLog ('RESEARCH WORKER ERROR STREAM: {0}' -f [string]$err) }
                    }
                }catch{}
                $rawJson=[string]($rawResults | Select-Object -Last 1)
                if([string]::IsNullOrWhiteSpace($rawJson)){throw 'Research worker returned no JSON result.'}
                $result=$rawJson | ConvertFrom-Json -ErrorAction Stop
                if($null -eq $result -or $null -eq $result.PSObject.Properties['Records']){throw 'Research worker returned invalid JSON result.'}
                $resultErrors=@(); try { if($null -ne $result.PSObject.Properties['Errors']){$resultErrors=@($result.Errors)} } catch {}
                foreach($err in $resultErrors){Write-YumLog ('Intelligence Research detail: ' + [string]$err)}
                $live=@($result.Records)
                # Canonicalize EVERY research result before any UI filtering, persistence, or manual override work.
                foreach($record in $live){
                    if($null -eq $record){continue}
                    try { [void](Ensure-YumIntelligenceRecordSchema -Record $record) }
                    catch { Write-YumLogException -Context ('Research result schema normalization failed for {0}' -f [string]$record.Name) -Exception $_.Exception; throw }
                }
                $live=@(Apply-YumManualOrganizations -Records $live)
                foreach($record in $live){
                    try {
                        $key=[string]$record.Key
                        $storageKey='';try{$storageKey=Get-YumStableIntelligenceKey -Record $record}catch{};if([string]::IsNullOrWhiteSpace($storageKey)){$storageKey=$key};if(-not [string]::IsNullOrWhiteSpace($storageKey)){$record|Add-Member -NotePropertyName StableIdentityKey -NotePropertyValue $storageKey -Force;$script:Yum.IntelligenceDb[$storageKey]=$record}
                    } catch {}
                }
                [void](Save-YumIntelligenceDb -Database $script:Yum.IntelligenceDb)
                $fullRecords=@($ctx.State.Data.Records)
                foreach($updated in $live){
                    if($null -eq $updated){continue}
                    $ukey=[string]$updated.Key
                    $replaced=$false
                    for($ri=0;$ri -lt $fullRecords.Count;$ri++){
                        if($null -ne $fullRecords[$ri] -and [string]$fullRecords[$ri].Key -eq $ukey){$fullRecords[$ri]=$updated;$replaced=$true;break}
                    }
                    if(-not $replaced){$fullRecords += $updated}
                }
                $ctx.State.Data=[pscustomobject]@{
                    Records=@($fullRecords)
                    Timestamp=$ctx.State.Data.Timestamp
                    ProcessCount=$ctx.State.Data.ProcessCount
                    ServiceCount=$ctx.State.Data.ServiceCount
                    AppCount=$ctx.State.Data.AppCount
                    Errors=@($ctx.State.Data.Errors)+$resultErrors
                    Status=$ctx.State.Data.Status
                    DurationMs=$ctx.State.Data.DurationMs
                    SavedCount=[int]$script:Yum.IntelligenceDb.Count
                    DatabaseCount=[int]$script:Yum.IntelligenceDb.Count
                    ResearchCount=[int]$result.ResearchedCount
                    CachedCount=if($null -ne $result.PSObject.Properties['CachedCount']){[int]$result.CachedCount}else{0}
                    OnlineResearchCount=[int]$result.OnlineResearchCount
                    ReviewResolvedCount=[int]$result.ReviewResolvedCount
                    UnknownCount=[int]$result.UnknownCount
                    ResearchErrorCount=if($null -ne $result.PSObject.Properties['ResearchErrorCount']){[int]$result.ResearchErrorCount}else{0}
                    ResearchComplete=[bool]$result.LocalClassificationComplete
                }
                Update-YumIntelligenceList -State $ctx.State
                $researchErrorCount=0
                if($null -ne $result.PSObject.Properties['ResearchErrorCount']){$researchErrorCount=[int]$result.ResearchErrorCount}
                $cachedCount = 0
                if($null -ne $result.PSObject.Properties['CachedCount']){$cachedCount=[int]$result.CachedCount}
                $ctx.State.Summary.Text=('Research complete — classified {0}; researched {1}; cached {2}; online verified {3}; organized {4}; Unknown {5}; errors {6}.' -f @($live).Count,[int]$result.ResearchedCount,$cachedCount,[int]$result.OnlineResearchCount,[int]$result.ReviewResolvedCount,[int]$result.UnknownCount,$researchErrorCount)
                Set-YumFooter ('🧠 Research complete • {0} researched • {1} cached • {2} online • {3} organized • {4} Unknown • {5} errors.' -f [int]$result.ResearchedCount,$cachedCount,[int]$result.OnlineResearchCount,[int]$result.ReviewResolvedCount,[int]$result.UnknownCount,$researchErrorCount)
                try{Remove-YumOwnedResearchLiveCheckpoint -Path $liveResultsPath -RunId $runId}catch{}
            } catch {
                Write-YumLogException -Context 'Intelligence research result/UI application failed' -Exception $_.Exception
                $ctx.State.Summary.Text='Scan complete, but research could not be applied. Check YUMRAM.log.'
                Set-YumFooter '⚠ Scan complete; research application failed.'
            } finally {
                $pendingManual=$false
                try{$pendingManual=[bool]$ctx.State.ResearchPendingManual}catch{}
                $ctx.State.ResearchBusy=$false;$ctx.State.ResearchRunId='';$ctx.State.ResearchProgressCount=0;$ctx.State.ResearchProgressText='Ready';$ctx.State.ResearchPendingManual=$false;try{$ctx.State.RunResearch.Content='🧠  RUN RESEARCH';$ctx.State.Refresh.IsEnabled=$true;$ctx.State.ActivityStatus.Text='READY';$ctx.State.ActivityDetail.Text=('Saved knowledge • {0} items still need research.' -f @($ctx.State.Data.Records|Where-Object{Test-YumResearchUnresolved -Record $_}).Count);$ctx.State.ActivityProgress.IsIndeterminate=$false;$ctx.State.ActivityProgress.Value=0}catch{}
                try{if(Test-Path -LiteralPath $ctx.QueuePath){Remove-Item -LiteralPath $ctx.QueuePath -Force -ErrorAction SilentlyContinue}}catch{}
                try{if(Test-Path -LiteralPath $ctx.ConfigPath){Remove-Item -LiteralPath $ctx.ConfigPath -Force -ErrorAction SilentlyContinue}}catch{}
                try{$ctx.Worker.Dispose()}catch{}
                if($pendingManual){
                    try{
                        $retry=@($ctx.State.Data.Records|Where-Object{Test-YumResearchUnresolved -Record $_})
                        if($retry.Count -gt 0){
                            $ctx.State.ForceFreshResearch=$true
                            $ctx.State.Summary.Text=('Starting queued manual retry for {0} unresolved items.' -f $retry.Count)
                            Set-YumFooter ('🧠 Starting queued manual research retry • {0} items.' -f $retry.Count)
                            $ctx.State.Window.Dispatcher.BeginInvoke([Action]{ Start-YumIntelligenceResearchAsync -State $ctx.State -Records $retry }) | Out-Null
                        }
                    } catch { Write-YumLogException -Context 'Queued manual research retry failed' -Exception $_.Exception }
                }
            }
        })
        $poll.Start()
    } catch {
        try{$worker.Dispose()}catch{}
        $State.ResearchBusy=$false
        Write-YumLogException -Context 'Intelligence research worker could not start' -Exception $_.Exception
    }
}

function Start-YumIntelligenceScanAsync {
    param([Parameter(Mandatory)][hashtable]$State)
    if($State.Busy){return}
    $State.Busy=$true
    if($null -ne $State.Refresh){$State.Refresh.IsEnabled=$false}
    $mode=if([bool]$State.ForceFreshResearch){'FRESH Intelligence Scan'}else{'Intelligence Scan'}
    $State.Summary.Text=('{0} is running… inventory first; unresolved items remain available for manual research.' -f $mode)
    $State.LastScan.Text='Scanning…'
    $root=$script:Yum.Root
    $max=[int]$script:Yum.Config.ScannerMaxItems
    $fg=0
    $gamePid=0
    try{$fg=[int](Get-YumForegroundProcessId)}catch{}
    try{$snap=Get-YumSnapshotCopy;if($snap -and $snap.Game.Detected){$gamePid=[int]$snap.Game.ProcessId}}catch{}
    $knownGames=@()
    $optionalApps=@()
    try{$knownGames=@($script:Yum.Config.KnownGames)}catch{}
    try{$optionalApps=@($script:Yum.Config.OptionalBackgroundProcesses)}catch{}
    $worker=[powershell]::Create()
    try {
        [void]$worker.AddScript({param($root,$max,$fg,$gamePid,$knownGames,$optionalApps,$config)
            $ErrorActionPreference='Stop'
            try {
                $script:Yum=[pscustomobject]@{Root=$root;ConfigDirectory=$root;Config=$config}
                $loggingPath=Join-Path $root 'Core\Logging.ps1';if(Test-Path -LiteralPath $loggingPath){. $loggingPath | Out-Null}
                $scannerPath=Join-Path $root 'Core\Scanner.ps1'
                if(-not (Test-Path -LiteralPath $scannerPath)){throw "Scanner module not found: $scannerPath"}
                . $scannerPath | Out-Null
                $researchPath=Join-Path $root 'Core\Research.ps1'; if(Test-Path -LiteralPath $researchPath){. $researchPath | Out-Null}
                Write-Output (Invoke-YumNewSystemScan -MaxItems $max -ForegroundPid $fg -GamePid $gamePid -KnownGames $knownGames -OptionalApps $optionalApps -SkipResearch)
            } catch {
                Write-Output ([pscustomobject]@{Status='Failed';Timestamp=Get-Date;DurationMs=0;Processes=@();Services=@();Apps=@();Records=@();Errors=@(('Scanner worker: {0}' -f $_.Exception.Message));ProcessCount=0;ServiceCount=0;AppCount=0;RecordCount=0})
            }
        }).AddArgument($root).AddArgument($max).AddArgument($fg).AddArgument($gamePid).AddArgument($knownGames).AddArgument($optionalApps).AddArgument($script:Yum.Config)
        $async=$worker.BeginInvoke()
        $poll=New-Object System.Windows.Threading.DispatcherTimer
        $poll.Interval=[TimeSpan]::FromMilliseconds(100)
        $poll.Tag=@{Worker=$worker;Async=$async;State=$State;Started=(Get-Date);TimeoutSeconds=90}
        $poll.Add_Tick({param($s,$e)
            $ctx=$s.Tag
            if(-not $ctx.Async.IsCompleted){
                if(((Get-Date)-$ctx.Started).TotalSeconds -ge [double]$ctx.TimeoutSeconds){
                    $s.Stop();try{$ctx.Worker.Stop()}catch{};try{$ctx.Worker.Dispose()}catch{};$ctx.State.Busy=$false;if($null -ne $ctx.State.Refresh){$ctx.State.Refresh.IsEnabled=$true};$ctx.State.LastScan.Text='Scan timed out after 90 seconds.';$ctx.State.Summary.Text='Intelligence Scan timed out. No partial results were applied.';try{$ctx.State.ActivityStatus.Text='SCAN TIMEOUT';$ctx.State.ActivityDetail.Text='The scan exceeded the 90-second safety limit. No partial results were applied.';$ctx.State.ActivityProgress.IsIndeterminate=$false;$ctx.State.ActivityProgress.Value=0}catch{};Set-YumFooter '⚠ Intelligence Scan timed out.';Write-YumLog 'Intelligence Scan timed out after 90 seconds.'
                }
                return
            }
            $s.Stop()
            try {
                $result=@($ctx.Worker.EndInvoke($ctx.Async)) | Where-Object {$null -ne $_ -and $null -ne $_.PSObject.Properties['Records'] -and $null -ne $_.PSObject.Properties['Status']} | Select-Object -Last 1
                if($null -eq $result){throw 'Scanner returned no structured result.'}
                $baseData=[pscustomobject]@{
                    Records=@($result.Records)
                    Timestamp=$result.Timestamp
                    ProcessCount=[int]$result.ProcessCount
                    ServiceCount=[int]$result.ServiceCount
                    AppCount=[int]$result.AppCount
                    Errors=$(try { if($null -ne $result.PSObject.Properties['Errors']){@($result.Errors)}else{@()} } catch {@()})
                    Status=[string]$result.Status
                    DurationMs=[double]$result.DurationMs
                    SavedCount=0
                    DatabaseCount=0
                }
                $ctx.State.Data=$baseData
                foreach($scanErr in @($baseData.Errors)){ try { Write-YumLog ('Intelligence Scan detail: ' + [string]$scanErr) } catch {} }
                # Merge live records into the persistent intelligence catalog using plain PowerShell 5.1-safe collections.
                $ctx.State.Data=[pscustomobject]@{Records=@($ctx.State.Data.Records);Timestamp=$ctx.State.Data.Timestamp;ProcessCount=$ctx.State.Data.ProcessCount;ServiceCount=$ctx.State.Data.ServiceCount;AppCount=$ctx.State.Data.AppCount;Errors=@($ctx.State.Data.Errors);Status=$ctx.State.Data.Status;DurationMs=$ctx.State.Data.DurationMs;SavedCount=0;DatabaseCount=0}
                try {
                    if($null -eq $script:Yum.IntelligenceDb -or -not ($script:Yum.IntelligenceDb -is [hashtable])){
                        [void](Load-YumIntelligenceDb)
                    }
                    if($null -eq $script:Yum.IntelligenceDb -or -not ($script:Yum.IntelligenceDb -is [hashtable])){
                        $script:Yum.IntelligenceDb=@{}
                    }
                    $live=@($result.Records)
                    try { $live=@(Apply-YumManualOrganizations -Records $live) } catch { Write-YumLogException -Context 'Manual organization apply failed during Intelligence scan' -Exception $_.Exception }
                    # Every intelligence record must expose a complete research-state contract before the UI filters/counts it.
                    foreach($record in $live){
                        if($null -eq $record){continue}
                        try { [void](Ensure-YumIntelligenceRecordSchema -Record $record) } catch {}
                        try {
                            if($null -eq $record.PSObject.Properties['ResearchStatus']){$record|Add-Member -NotePropertyName ResearchStatus -NotePropertyValue 'Not Researched' -Force}
                            if($null -eq $record.PSObject.Properties['ResearchComplete']){$record|Add-Member -NotePropertyName ResearchComplete -NotePropertyValue $false -Force}
                            if($null -eq $record.PSObject.Properties['ResearchPerformed']){$record|Add-Member -NotePropertyName ResearchPerformed -NotePropertyValue $false -Force}
                            if($null -eq $record.PSObject.Properties['ResearchExhausted']){$record|Add-Member -NotePropertyName ResearchExhausted -NotePropertyValue $false -Force}
                            if($null -eq $record.PSObject.Properties['ResearchConfidence']){$record|Add-Member -NotePropertyName ResearchConfidence -NotePropertyValue 0 -Force}
                            if($null -eq $record.PSObject.Properties['ResearchSources']){$record|Add-Member -NotePropertyName ResearchSources -NotePropertyValue @() -Force}
                            if($null -eq $record.PSObject.Properties['ResearchLinks']){$record|Add-Member -NotePropertyName ResearchLinks -NotePropertyValue @() -Force}
                            if($null -eq $record.PSObject.Properties['ResearchReason']){$record|Add-Member -NotePropertyName ResearchReason -NotePropertyValue 'Awaiting manual Run Research.' -Force}
                            if($null -eq $record.PSObject.Properties['Placement']){$record|Add-Member -NotePropertyName Placement -NotePropertyValue '' -Force}
                            if($null -eq $record.PSObject.Properties['ActionLane']){$record|Add-Member -NotePropertyName ActionLane -NotePropertyValue ([string]$record.Recommendation) -Force}
                        } catch { Write-YumLogException -Context ('Intelligence research-state normalization failed for {0}' -f [string]$record.Name) -Exception $_.Exception }
                    }
                    $previousDb=@{}
                    $previousStableDb=@{}
                    try{foreach($entry in @($script:Yum.IntelligenceDb.GetEnumerator())){if($null -ne $entry -and $null -ne $entry.Value){$previousDb[[string]$entry.Key]=$entry.Value;try{$stableKey=Get-YumStableIntelligenceKey -Record $entry.Value;if(-not [string]::IsNullOrWhiteSpace($stableKey)){$previousStableDb[$stableKey]=$entry.Value}}catch{}}}}catch{}
                    foreach($record in $live){
                        if($null -ne $record){
                            $key=[string]$record.Key
                            $stableKey='';try{$stableKey=Get-YumStableIntelligenceKey -Record $record}catch{}
                            $savedProfile=$null
                            if(-not [string]::IsNullOrWhiteSpace($stableKey) -and $previousStableDb.ContainsKey($stableKey)){$savedProfile=$previousStableDb[$stableKey]}
                            elseif(-not [string]::IsNullOrWhiteSpace($key) -and $previousDb.ContainsKey($key)){$savedProfile=$previousDb[$key]}
                            if($null -ne $savedProfile){
                                $identityCompatible=$true
                                try{
                                    $currentHash=if($null -ne $record.PSObject.Properties['FileHash']){[string]$record.FileHash}else{''}
                                    $savedHash=if($null -ne $savedProfile.PSObject.Properties['FileHash']){[string]$savedProfile.FileHash}else{''}
                                    $currentSigner=if($null -ne $record.PSObject.Properties['SignerThumbprint']){[string]$record.SignerThumbprint}else{''}
                                    $savedSigner=if($null -ne $savedProfile.PSObject.Properties['SignerThumbprint']){[string]$savedProfile.SignerThumbprint}else{''}
                                    if($currentHash -and $savedHash -and $currentHash -ne $savedHash){$identityCompatible=$false}
                                    if($currentSigner -and $savedSigner -and $currentSigner -ne $savedSigner){$identityCompatible=$false}
                                }catch{}
                                if($identityCompatible){try{foreach($field in @('Category','Risk','Placement','ActionLane','Recommendation','ResearchStatus','ResearchComplete','ResearchPerformed','ResearchExhausted','ResearchConfidence','ResearchSources','ResearchLinks','ResearchReason','ResearchErrorState','ResearchStarted','ResearchCompleted','FileHash','SignerThumbprint','IdentityState','IdentityConfidence','UnknownReason','AutoResearchEligible','ManualOverride','ManualOrganizationUpdated')){if($null -ne $savedProfile.PSObject.Properties[$field]){$record|Add-Member -NotePropertyName $field -NotePropertyValue $savedProfile.$field -Force}}}catch{}}
                            }
                            # Clear stale research errors inherited from older queue semantics for protected terminal records.
                            try{
                                $rRisk=[string]$record.Risk;$rPlacement=[string]$record.Placement;$rAction=[string]$record.ActionLane
                                if($rRisk -eq 'Protected' -and $rAction -notmatch '(?i)\bReview\b' -and $rPlacement -notin @('Review Queue','Unknown / Quarantine for Review')){
                                    $record|Add-Member -NotePropertyName ResearchStatus -NotePropertyValue 'Organized' -Force
                                    $record|Add-Member -NotePropertyName ResearchComplete -NotePropertyValue $true -Force
                                    $record|Add-Member -NotePropertyName ResearchExhausted -NotePropertyValue $true -Force
                                    $record|Add-Member -NotePropertyName ResearchErrorState -NotePropertyValue '' -Force
                                    $record|Add-Member -NotePropertyName ResearchReason -NotePropertyValue 'Protected classification does not require automatic review research.' -Force
                                }
                            }catch{}
                            $storageKey='';try{$storageKey=Get-YumStableIntelligenceKey -Record $record}catch{};if([string]::IsNullOrWhiteSpace($storageKey)){$storageKey=$key};if(-not [string]::IsNullOrWhiteSpace($storageKey)){$record|Add-Member -NotePropertyName StableIdentityKey -NotePropertyValue $storageKey -Force;$script:Yum.IntelligenceDb[$storageKey]=$record}
                        }
                    }
                    $savedItems=@()
                    foreach($entry in @($script:Yum.IntelligenceDb.GetEnumerator())){
                        if($null -ne $entry -and $null -ne $entry.Value){$savedItems += $entry.Value}
                    }
                    $liveKeys=@{}
                    $liveStableKeys=@{}
                    $merged=@()
                    foreach($record in $live){
                        if($null -ne $record){
                            $key=[string]$record.Key
                            if(-not [string]::IsNullOrWhiteSpace($key)){$liveKeys[$key]=$true}
                            try{$stable=[string](Get-YumStableIntelligenceKey -Record $record);if(-not [string]::IsNullOrWhiteSpace($stable)){$liveStableKeys[$stable]=$true}}catch{}
                            $merged += $record
                        }
                    }
                    foreach($saved in $savedItems){
                        if($null -eq $saved){continue}
                        $savedKey=[string]$saved.Key
                        $savedStable='';try{$savedStable=Get-YumStableIntelligenceKey -Record $saved}catch{}
                        if(((-not [string]::IsNullOrWhiteSpace($savedStable)) -and $liveStableKeys.ContainsKey($savedStable)) -or ((-not [string]::IsNullOrWhiteSpace($savedKey)) -and $liveKeys.ContainsKey($savedKey))){continue}
                        try {
                            [void](Ensure-YumIntelligenceRecordSchema -Record $saved)
                            if($null -eq $saved.PSObject.Properties['Memory']){$saved|Add-Member -NotePropertyName Memory -NotePropertyValue '—' -Force}else{$saved.Memory='—'}
                            if($null -eq $saved.PSObject.Properties['CPU']){$saved|Add-Member -NotePropertyName CPU -NotePropertyValue '—' -Force}else{$saved.CPU='—'}
                            if($null -eq $saved.PSObject.Properties['PID']){$saved|Add-Member -NotePropertyName PID -NotePropertyValue '—' -Force}else{$saved.PID='—'}
                            $saved.Live=$false;$saved.StateText='SAVED';$saved.Reason='Saved classification; not present in current live scan.'
                            $merged += $saved
                        } catch { Write-YumLogException -Context ('Saved Intelligence record normalization failed for {0}' -f [string]$saved.Name) -Exception $_.Exception }
                    }
                    # Final UI-boundary normalization: no record reaches filters, counts, or ListView without the full schema.
                    foreach($boundRecord in @($merged)){
                        if($null -eq $boundRecord){continue}
                        [void](Ensure-YumIntelligenceRecordSchema -Record $boundRecord)
                        if($null -eq $boundRecord.PSObject.Properties['ResearchStatus']){throw ('Intelligence record schema validation failed for {0}: ResearchStatus missing.' -f [string]$boundRecord.Name)}
                        if($null -eq $boundRecord.PSObject.Properties['ManualOverride']){throw ('Intelligence record schema validation failed for {0}: ManualOverride missing.' -f [string]$boundRecord.Name)}
                    }
                    $ctx.State.Data.Records=@($merged)
                    foreach($live in @($ctx.State.Data.Records)){try{if($null -eq $live.PSObject.Properties['StateText']){$live|Add-Member -NotePropertyName StateText -NotePropertyValue 'LIVE' -Force};if($null -eq $live.PSObject.Properties['Placement']){$live|Add-Member -NotePropertyName Placement -NotePropertyValue '' -Force};if($null -eq $live.PSObject.Properties['ActionLane']){$live|Add-Member -NotePropertyName ActionLane -NotePropertyValue $live.Recommendation -Force}}catch{}}
                    $ctx.State.Data=[pscustomobject]@{Records=@($ctx.State.Data.Records);Timestamp=$ctx.State.Data.Timestamp;ProcessCount=$ctx.State.Data.ProcessCount;ServiceCount=$ctx.State.Data.ServiceCount;AppCount=$ctx.State.Data.AppCount;Errors=@($ctx.State.Data.Errors);Status=$ctx.State.Data.Status;DurationMs=$ctx.State.Data.DurationMs;SavedCount=[int]$script:Yum.IntelligenceDb.Count;DatabaseCount=[int]$script:Yum.IntelligenceDb.Count;ResearchCount=@($ctx.State.Data.Records|Where-Object{$null -ne $_.PSObject.Properties['ResearchPerformed'] -and [bool]$_.ResearchPerformed}).Count;ReviewResolvedCount=@($ctx.State.Data.Records|Where-Object{$null -ne $_.ResearchStatus -and $_.ResearchStatus -in @('Organized','Unknown')}).Count;UnknownCount=@($ctx.State.Data.Records|Where-Object{$_.Risk -eq 'Unknown'}).Count}
                    [void](Save-YumIntelligenceDb -Database $script:Yum.IntelligenceDb)
                } catch {
                    $savedCount=if($null -ne $script:Yum.IntelligenceDb -and $script:Yum.IntelligenceDb -is [hashtable]){[int]$script:Yum.IntelligenceDb.Count}else{0};$ctx.State.Data=[pscustomobject]@{Records=@($ctx.State.Data.Records);Timestamp=$ctx.State.Data.Timestamp;ProcessCount=$ctx.State.Data.ProcessCount;ServiceCount=$ctx.State.Data.ServiceCount;AppCount=$ctx.State.Data.AppCount;Errors=@($ctx.State.Data.Errors)+@('Database merge failed');Status=$ctx.State.Data.Status;DurationMs=$ctx.State.Data.DurationMs;SavedCount=$savedCount;DatabaseCount=$savedCount}
                    Write-YumLogException -Context 'Intelligence database merge failed' -Exception $_.Exception
                }
                # Build the unresolved queue BEFORE using it in completion UI.
                # StrictMode otherwise throws here and leaves the visual activity state stuck at SCANNING.
                $researchInput=@($ctx.State.Data.Records | Where-Object { $null -ne $_ -and [bool]$_.Live -and (Test-YumResearchUnresolved -Record $_) })
                Write-YumLog ('Research queue prepared: {0} unresolved records.' -f $researchInput.Count)
                Update-YumIntelligenceList -State $ctx.State
                $ctx.State.LastScan.Text=('Updated {0:HH:mm:ss} — {1} processes, {2} services, {3} apps' -f [datetime]$ctx.State.Data.Timestamp,$ctx.State.Data.ProcessCount,$ctx.State.Data.ServiceCount,$ctx.State.Data.AppCount)
                try{$ctx.State.ActivityStatus.Text='SCAN COMPLETE';$ctx.State.ActivityDetail.Text=('Inventory complete • {0} items need research.' -f $researchInput.Count);$ctx.State.ActivityProgress.IsIndeterminate=$false;$ctx.State.ActivityProgress.Value=100}catch{}
                $saved=[int]$ctx.State.Data.SavedCount
                if($null -ne $ctx.State.DatabaseStatus){$ctx.State.DatabaseStatus.Text=('Local intelligence profile saved • {0:N0} classified records' -f $saved)}
                if($null -ne $ctx.State.DatabaseCount){$ctx.State.DatabaseCount.Text=('{0:N0}' -f $saved)}
                if([string]$ctx.State.Data.Status -eq 'Failed'){
                    $ctx.State.Summary.Text='Intelligence Scan failed. No partial results were applied.';Set-YumFooter '⚠ Intelligence Scan failed.'
                }
                elseif(@($ctx.State.Data.Errors).Count -gt 0){
                    $ctx.State.Summary.Text=('Scan completed with {0} warnings. Results were organized from the successful portions.' -f @($ctx.State.Data.Errors).Count);Set-YumFooter '🧠 Intelligence Scan completed with warnings.'
                }
                elseif($researchInput.Count -gt 0){
                    $ctx.State.Summary.Text=('Scan completed — {0} items inventoried. {1} items need research. Click Run Research to investigate and organize them.' -f @($ctx.State.Data.Records).Count,$researchInput.Count);Set-YumFooter ('🧠 Scan complete • {0} items ready for manual research.' -f $researchInput.Count)
                }
                else{
                    $ctx.State.Summary.Text=('Scan completed — {0} items inventoried. No research is required.' -f @($ctx.State.Data.Records).Count);Set-YumFooter '🧠 Intelligence Scan completed • no research required.'
                }
            } catch {
                Write-YumLogException -Context 'Intelligence Scan result/UI application failed' -Exception $_.Exception
                $ctx.State.Summary.Text='Intelligence Scan failed — check YUMRAM.log.';$ctx.State.LastScan.Text='Scan failed'
            } finally {
                $ctx.State.Busy=$false
                if($null -ne $ctx.State.Refresh){$ctx.State.Refresh.IsEnabled=$true;$ctx.State.Refresh.Content='🔍  RUN SCAN'}
                # Busy is cleared above. Recompute the research-button state now; the scan
                # completion refresh intentionally ran while Busy=$true and therefore disabled it.
                # A revision-based refresh may otherwise skip this state transition.
                if($null -ne $ctx.State.RunResearch -and -not $ctx.State.ResearchBusy){
                    $ctx.State.RunResearch.Content='🧠  RUN RESEARCH'
                    $hasRecords=$false
                    try{$hasRecords=(@($ctx.State.Data.Records|Where-Object{$null -ne $_}).Count -gt 0)}catch{}
                    $ctx.State.RunResearch.IsEnabled=$hasRecords
                }
                # Never leave the activity panel visually stuck in SCANNING after an exception.
                try{
                    if([string]$ctx.State.ActivityStatus.Text -eq 'SCANNING SYSTEM'){
                        $ctx.State.ActivityStatus.Text='SCAN ERROR'
                        $ctx.State.ActivityDetail.Text='Scan finished with an application error. Check YUMRAM.log.'
                        $ctx.State.ActivityProgress.IsIndeterminate=$false
                    }
                }catch{}
                try{$ctx.Worker.Dispose()}catch{}
            }
        })
        $poll.Start()
    } catch {try{$worker.Dispose()}catch{};$State.Busy=$false;throw}
}
function Update-YumIntelligenceList {
    param([Parameter(Mandatory)][hashtable]$State,[switch]$Force)
    if($null -eq $State.Data){$State.Summary.Text='Building intelligence view…';try{$State.RunResearch.IsEnabled=$false}catch{};return}
    $revision=0;try{$revision=[int]$script:Yum.IntelligenceViewRevision}catch{}
    if(-not $Force -and [int]$State.LastRenderedRevision -eq $revision -and -not $State.Busy -and -not $State.ResearchBusy){return}
    $all=@($State.Data.Records)
    $researchable=@($all|Where-Object{Test-YumResearchUnresolved -Record $_})
    # Keep the manual research control clickable whenever Intelligence has records loaded.
    # The click handler performs the final queue calculation and reports a clear no-op when appropriate.
    try{$State.RunResearch.IsEnabled=(-not $State.Busy -and -not $State.ResearchBusy -and $all.Count -gt 0)}catch{}
    $query=''; try{$query=$State.Search.Text.Trim().ToLowerInvariant()}catch{}
    $filter='All Items'; try{$filter=[string]$State.Filter.SelectedItem.Content}catch{}
    $rows=$all
    switch($filter){
        'Review Queue' {$rows=@($rows|Where-Object {Test-YumResearchUnresolved -Record $_})}
        'Needs Research' {$rows=@($rows|Where-Object {Test-YumResearchUnresolved -Record $_})}
        'Researching' {$rows=@($rows|Where-Object {[string]$_.ResearchStatus -eq 'Researching'})}
        'Research Errors' {$rows=@($rows|Where-Object {$_.ResearchStatus -eq 'Research Error'})}
        'Cached / Knowledge' {$rows=@($rows|Where-Object {$null -ne $_.PSObject.Properties['ResearchRunDisposition'] -and [string]$_.ResearchRunDisposition -eq 'Cached'})}
        'Organized' {$rows=@($rows|Where-Object {$_.ResearchStatus -eq 'Organized'})}
        'Unknown' {$rows=@($rows|Where-Object {$_.ResearchStatus -eq 'Unknown' -or $_.Risk -eq 'Unknown'})}
        'Protected' {$rows=@($rows|Where-Object {$_.Risk -eq 'Protected'})}
        'Games' {$rows=@($rows|Where-Object {$_.Category -match 'Game' -or $_.Category -match '(?i)gaming'})}
        'Apps' {$rows=@($rows|Where-Object {$_.Category -in @('Apps','Background App','User Application','Identified Applications','User Background Apps')})}
        'Services' {$rows=@($rows|Where-Object {$_.Source -eq 'Service' -or $_.Category -eq 'Services'})}
        'Startup' {$rows=@($rows|Where-Object {$_.Source -eq 'Startup' -or $_.Category -eq 'Startup App' -or $_.Category -eq 'Startup Inventory'})}
        'Drivers / Hardware' {$rows=@($rows|Where-Object {$_.Category -in @('Drivers / Hardware','Drivers','Hardware') -or $_.Risk -eq 'Protected' -and [string]$_.Reason -match '(?i)driver|hardware'})}
        'Processes' {$rows=@($rows|Where-Object {$_.Source -eq 'Process'})}
        default {$rows=$all}
    }
    if($query){$rows=@($rows|Where-Object {([string]$_.Name).ToLowerInvariant().Contains($query) -or ([string]$_.Category).ToLowerInvariant().Contains($query) -or ([string]$_.Publisher).ToLowerInvariant().Contains($query) -or ([string]$_.ResearchReason).ToLowerInvariant().Contains($query)})}
    $signature=('{0}|{1}|rev={2}|count={3}' -f $filter,$query,$revision,$rows.Count)
    if($signature -ne [string]$State.LastListSignature){
        $selectedKey=''; try{if($null -ne $State.ListView.SelectedItem){$selectedKey=[string]$State.ListView.SelectedItem.Key}}catch{}
        $State.ListView.ItemsSource=[object[]]@($rows)
        $State.LastListSignature=$signature
        $State.LastRenderedRevision=$revision
        if(-not [string]::IsNullOrWhiteSpace($selectedKey)){
            foreach($item in @($State.ListView.Items)){
                if($null -ne $item -and [string]$item.Key -eq $selectedKey){$State.ListView.SelectedItem=$item;break}
            }
        }
    }
    $live=@($all|Where-Object {$_.Live})
    $needs=@($all|Where-Object {Test-YumResearchUnresolved -Record $_})
    $resolved=@($all|Where-Object {$_.ResearchStatus -eq 'Organized'})
    $unknown=@($all|Where-Object {$_.ResearchStatus -eq 'Unknown' -or $_.Risk -eq 'Unknown'})
    $protected=@($all|Where-Object {$_.Risk -eq 'Protected'})
    $cached=0;$errors=0;$researching=0
    foreach($r in $all){
        if($null -ne $r.PSObject.Properties['ResearchStatus'] -and [string]$r.ResearchStatus -eq 'Research Error'){$errors++}
        elseif($null -ne $r.PSObject.Properties['ResearchStatus'] -and [string]$r.ResearchStatus -eq 'Researching'){$researching++}
    }
    try{if($null -ne $State.Data.PSObject.Properties['CachedCount']){$cached=[int]$State.Data.CachedCount}}catch{}
    $State.ScannedCount.Text=[string]$live.Count
    $State.ReviewCount.Text=[string]$needs.Count
    $State.ResearchingCount.Text=if($State.ResearchBusy){if($null -ne $State.ResearchProgressCount){[string]$State.ResearchProgressCount}else{[string]$researching}}else{[string]$researching}
    $State.ResolvedCount.Text=[string]$resolved.Count
    $State.UnknownCount.Text=[string]$unknown.Count
    $State.ProtectedCount.Text=[string]$protected.Count
    $State.CachedCount.Text=[string]$cached
    $State.ResearchErrorCount.Text=[string]$errors
    if($null -ne $State.DatabaseCount){$State.DatabaseCount.Text=('{0:N0} saved records' -f [int]$script:Yum.IntelligenceDb.Count)}
    if($State.ResearchBusy){$State.ResearchProgress.Text=if($null -ne $State.ResearchProgressText){[string]$State.ResearchProgressText}else{'Research in progress…'}}elseif(-not $State.Busy){$State.ResearchProgress.Text=('Ready • {0} items need research' -f $needs.Count); try{$State.ActivityStatus.Text='READY';$State.ActivityDetail.Text=('Saved knowledge loaded • {0} items need research.' -f $needs.Count);$State.ActivityProgress.IsIndeterminate=$false;$State.ActivityProgress.Value=0}catch{}}
    $State.Summary.Text=('Showing {0} of {1} records • Review {2} • Resolved {3} • Unknown {4} • Errors {5}' -f $rows.Count,$all.Count,$needs.Count,$resolved.Count,$unknown.Count,$errors)
}
