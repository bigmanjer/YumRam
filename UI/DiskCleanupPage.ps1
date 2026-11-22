#requires -Version 5.1
# 5.15.2: Disk cleanup page (Core\DiskCleanup.ps1 does the work). Measuring, cleaning and folder analysis run in a
# background runspace; the UI thread only polls and renders, like the Windows bloat page.

function Start-YumDiskWork {
    param([hashtable]$State,[scriptblock]$Work,$Argument,[scriptblock]$Done,[string]$Busy='Working…')
    $ps=[powershell]::Create()
    [void]$ps.AddScript({
        param($Shared,[string]$Root,$Arg,[string]$WorkText)
        foreach($m in 'Core\Logging.ps1','Core\Config.ps1','Core\Native.ps1','Core\DiskCleanup.ps1'){ . (Join-Path $Root $m) }
        $script:Yum=$Shared
        & ([scriptblock]::Create($WorkText)) $Arg
    }.ToString()).AddArgument($script:Yum).AddArgument([string]$script:Yum.Root).AddArgument($Argument).AddArgument($Work.ToString())
    $job=@{Ps=$ps;Handle=$ps.BeginInvoke();State=$State;Done=$Done}
    $t=New-Object System.Windows.Threading.DispatcherTimer
    $t.Interval=[TimeSpan]::FromMilliseconds(250)
    $t.Tag=$job
    $t.Add_Tick({param($s,$e)
        $j=$s.Tag
        if(-not $j.Handle.IsCompleted){return}
        $s.Stop()
        $res=$null
        try{ $res=$j.Ps.EndInvoke($j.Handle) }catch{ try{Write-YumLogException -Context 'Disk cleanup background work failed' -Exception $_.Exception}catch{} }
        try{$j.Ps.Dispose()}catch{}
        try{ & $j.Done $j.State $res }catch{ try{Write-YumLogException -Context 'Disk cleanup page update failed' -Exception $_.Exception}catch{} }
    })
    if($null -ne $State){ $State.Busy=$true; $State.Ui.Details.Text=$Busy; Update-YumDiskButtons -State $State }
    $t.Start()
}

function Update-YumDiskButtons {
    param([hashtable]$State)
    $b=[bool]$State.Busy
    foreach($n in 'Reload','CleanSelected','UsageScan','UsageUp'){ $State.Ui[$n].IsEnabled=-not $b }
}

function Update-YumDiskSummary {
    param([hashtable]$State)
    $ui=$State.Ui
    $sel=@($State.Rows | Where-Object { -not $_.Locked })
    $ui.SumJunk.Text=Format-YumBytes (Get-YumSum $sel 'Bytes')
    try{ $d=New-Object IO.DriveInfo ($env:SystemDrive); $usedPct=100*(1-$d.AvailableFreeSpace/[double]$d.TotalSize); $ui.SumDrive.Text=('{0} of {1}' -f (Format-YumBytes $d.AvailableFreeSpace),(Format-YumBytes $d.TotalSize)); $ui.SumDriveBar.Value=$usedPct
         $ui.SumDriveBar.Foreground=Get-YumBrush $(if($usedPct -ge 90){'#F87171'}elseif($usedPct -ge 80){'#FBBF24'}else{'#7DD3FC'}) }catch{}
    $ui.SumFreed.Text=Format-YumBytes ([double]$script:Yum.Config['DiskCleanupFreedTotal'])
    $ui.AutoClean.IsChecked=[bool]$script:Yum.Config['DiskAutoClean']
    $last=[string]$script:Yum.Config['DiskCleanupLast']
    $ui.AutoLast.Text=if($last){'last clean '+([datetime]$last).ToString('d MMM HH:mm')}else{'never cleaned yet'}
}

function Get-YumDiskPickable {
    # Rows a tick can apply to: not locked (needs administrator) and something to clean (or Windows' own tools).
    param([hashtable]$State)
    return @(@($State.Rows) | Where-Object { -not [bool]$_.Locked -and ([double]$_.Bytes -gt 0 -or [string]$_.Special) })
}
function Set-YumDiskPickAll {
    param([hashtable]$State,[bool]$On)
    foreach($r in Get-YumDiskPickable -State $State){ $r.Selected=$On; if($On){ $State.Picked[[string]$r.Key]=$true }else{ [void]$State.Picked.Remove([string]$r.Key) } }
    try{ $State.Ui.Junk.Items.Refresh() }catch{}
    Update-YumDiskPickAll -State $State
}
function Update-YumDiskPickAll {
    param([hashtable]$State)
    try{ $p=@(Get-YumDiskPickable -State $State); $State.Ui.PickAll.IsChecked=($p.Count -gt 0 -and @($p | Where-Object { -not [bool]$_.Selected }).Count -eq 0) }catch{}
}

function Set-YumDiskRows {
    param([hashtable]$State,$Rows)
    $State.Rows=@($Rows | Where-Object { $null -ne $_ })
    $State.Picked=@{}; foreach($r in $State.Rows){ if([bool]$r.Selected){ $State.Picked[$r.Key]=$true } }
    $State.Ui.Junk.ItemsSource=$null
    $State.Ui.Junk.ItemsSource=$State.Rows
    Update-YumDiskPickAll -State $State
    Update-YumDiskSummary -State $State
}

function Start-YumDiskMeasure {
    param([hashtable]$State,[string]$After='')
    $State.After=$After
    Start-YumDiskWork -State $State -Busy 'Measuring caches and leftovers…' -Work { param($a) Measure-YumDiskJunk } -Argument $null -Done {
        param($st,$res)
        $st.Busy=$false
        Set-YumDiskRows -State $st -Rows @($res)
        $st.Ui.Details.Text=if($st.After){[string]$st.After}else{('Measured {0:T}. Tick what to clean, or click a line to read what it is.' -f (Get-Date))}
        Update-YumDiskButtons -State $st
    }
}

function Update-YumDiskExplanation {
    param([hashtable]$State)
    $ui=$State.Ui;$it=$ui.Junk.SelectedItem
    if($null -eq $it){ $ui.ExplainBody.Visibility='Collapsed'; return }
    $ui.ExplainBody.Visibility='Visible'
    $ui.ExplainTitle.Text=[string]$it.Name
    $ui.ExplainSub.Text=('{0}  •  {1}  •  advice: {2}' -f $it.SizeText,$it.SubTitle,$(if($it.Advice -eq 'Clean'){'Clean (recommended)'}else{'Your call'}))
    $ui.ExplainWhy.Text=[string]$it.Why
    $ui.ExplainEffect.Text=[string]$it.Effect
    $ui.ExplainUndo.Text=if($it.Key -eq 'Recycle'){'No. Emptying the Recycle Bin is permanent.'}else{'Nothing to undo: these are copies and leftovers that Windows or the program creates again when it needs them. Your own files are never in these folders.'}
}

function Start-YumDiskUsage {
    param([hashtable]$State,[string]$Path)
    if([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path -PathType Container)){ $State.Ui.Details.Text='That folder does not exist.'; return }
    $State.Ui.UsagePath.Text=$Path
    Start-YumDiskWork -State $State -Busy ('Measuring {0} … a whole drive can take a minute or two.' -f $Path) -Work { param($a) Get-YumDiskUsage -Path $a -TopFiles 50 } -Argument $Path -Done {
        param($st,$res)
        $st.Busy=$false
        $u=@($res)[0]
        if($null -ne $u){
            $st.Ui.UsageFolders.ItemsSource=@($u.Folders)
            $st.Ui.UsageFiles.ItemsSource=@($u.TopFiles)
            $st.Ui.Details.Text=('{0}: {1} in {2:N0} files, measured in {3} s{4}. Double-click a folder to look inside.' -f $u.Path,(Format-YumBytes $u.Bytes),$u.Files,$u.Seconds,$(if([int]$u.Denied -gt 0){(' ({0} places Windows keeps private were skipped{1})' -f $u.Denied,$(if(-not (Test-YumIsElevated)){'; run as administrator to include them'}else{''}))}else{''}))
        }
        Update-YumDiskButtons -State $st
    }
}

function Show-YumDiskCleanup {
    try {
        [xml]$xaml=Read-YumXamlText -Path (Join-Path $script:Yum.Root 'UI\Xaml\DiskCleanup.xaml')
        $window=[Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $xaml))
        $ui=@{}
        foreach($n in 'PickAll','Junk','Reload','AdminPill','AdminText','RestartAdmin','SumJunk','SumDrive','SumDriveBar','SumFreed','AutoClean','AutoLast','CleanSelected','UsagePath','UsageScan','UsageUp','UsageOpen','UsageTabs','UsageFolders','UsageFiles','ExplainTitle','ExplainSub','ExplainWhy','ExplainBody','ExplainEffect','ExplainUndo','LastResult','OpenFolder','SeeDeleted','StorageSense','Close','Details'){$ui[$n]=$window.FindName($n);if($null -eq $ui[$n]){throw "Disk cleanup page control missing: $n"}}
        $state=@{Window=$window;Ui=$ui;Rows=@();Picked=@{};Busy=$false}
        $window.Tag=$state
        foreach($c in 'Junk','Reload','AutoClean','CleanSelected','UsageScan','UsageUp','UsageOpen','UsageFolders','UsageFiles','Close'){$ui[$c].Tag=$state}
        if(Test-YumIsElevated){$ui.AdminPill.Visibility='Collapsed';$ui.RestartAdmin.Visibility='Collapsed'}else{$ui.AdminText.Text='Not administrator: Windows'' own files are locked'}
        $ui.RestartAdmin.Add_Click({ try{ [void](Restart-YumAsAdministrator) }catch{} })
        $ui.UsagePath.Text=($env:SystemDrive+'\')
        # Tick boxes live in the list rows; one handler for all of them.
        $ui.Junk.AddHandler([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent,[System.Windows.RoutedEventHandler]{param($s,$e)
            try{ $cb=$e.OriginalSource; if($cb -is [System.Windows.Controls.CheckBox]){ $st=$s.Tag; $k=[string]$cb.Tag; if([bool]$cb.IsChecked){$st.Picked[$k]=$true}else{[void]$st.Picked.Remove($k)}
                # 5.16.2 (user: "when I tick one and scroll, it unticks"): the list reuses row visuals while scrolling and
                # re-reads Selected from the row, so the row itself must remember the tick.
                foreach($r in @($st.Rows)){ if([string]$r.Key -eq $k){ $r.Selected=[bool]$cb.IsChecked } }
                Update-YumDiskPickAll -State $st } }catch{} })
        # 5.16.2 (user request): Select all / none.
        $ui.PickAll.Tag=$state
        $ui.PickAll.Add_Click({param($s,$e) try{ Set-YumDiskPickAll -State $s.Tag -On ([bool]$s.IsChecked) }catch{} })
        $ui.Junk.Add_SelectionChanged({param($s,$e)try{ Update-YumDiskExplanation -State $s.Tag }catch{}})
        $ui.Reload.Add_Click({param($s,$e) Start-YumDiskMeasure -State $s.Tag })
        $ui.AutoClean.Add_Click({param($s,$e) try{ Update-YumConfigValue -Name DiskAutoClean -Value ([bool]$s.IsChecked); Show-YumToast -Text $(if([bool]$s.IsChecked){'Automatic weekly clean on: only the safest leftovers.'}else{'Automatic weekly clean off.'}) }catch{} })
        $ui.CleanSelected.Add_Click({param($s,$e)
            $st=$s.Tag; if($st.Busy){return}
            $keys=@($st.Picked.Keys); $rows=@($st.Rows | Where-Object { $keys -contains $_.Key -and -not $_.Locked -and ($_.Bytes -gt 0 -or [string]$_.Special) })
            if($rows.Count -eq 0){ $st.Ui.Details.Text='Tick at least one category that has something to clean.'; return }
            $total=Format-YumBytes (Get-YumSum $rows 'Bytes')
            $names=($rows | ForEach-Object { '  •  {0}  ({1})' -f $_.Name,$_.SizeText }) -join [Environment]::NewLine
            $warn=if(@($rows | Where-Object { $_.Key -eq 'Recycle' }).Count){"`n`nThe Recycle Bin is emptied permanently."}else{''}
            if(@($rows | Where-Object { [string]$_.Special }).Count){ $total+=' plus what Windows'' own tools find (a few minutes)' }
            # 5.15.3: say which open programs hold caches - their files in use are skipped, so close them for the full result.
            try{ $open=@(Get-YumOpenCacheApps -Keys @($rows | ForEach-Object { $_.Key })); if($open.Count){ $warn+=("`n`nOpen now: {0}. Their files in use are skipped - close them first for the biggest result, or clean anyway." -f ($open -join ', ')) } }catch{}
            $r=[System.Windows.MessageBox]::Show($script:Yum.Window,("Clean about {0}?`n`n{1}{2}`n`nFiles in use are skipped. Your own files, cookies and passwords are never touched." -f $total,$names,$warn),'YUMRAM - Disk cleanup',[System.Windows.MessageBoxButton]::YesNo,[System.Windows.MessageBoxImage]::Question)
            if($r -ne [System.Windows.MessageBoxResult]::Yes){return}
            Start-YumDiskWork -State $st -Busy ('Cleaning {0} categories…' -f $rows.Count) -Argument ([string[]]@($rows | ForEach-Object { $_.Key })) -Work { param($a) Invoke-YumDiskCleanup -Keys $a } -Done {
                param($st2,$res)
                $st2.Busy=$false
                $x=@($res)[0]
                $lines=@($x.Rows | ForEach-Object { '{0}: {1}{2}' -f $_.Name,(Format-YumBytes $_.Freed),$(if($_.Skipped -gt 0){(' ({0:N0} in use, skipped)' -f $_.Skipped)}elseif($_.Note){' ('+$_.Note+')'}else{''}) })
                $msg=('Freed {0}. Windows drive free: {1} -> {2}.' -f (Format-YumBytes $x.Freed),(Format-YumBytes $x.DriveFreeBefore),(Format-YumBytes $x.DriveFreeAfter))
                $st2.Ui.LastResult.Text=($msg+[Environment]::NewLine+($lines -join [Environment]::NewLine))
                try{ Show-YumToast -Text $msg }catch{}
                Start-YumDiskMeasure -State $st2 -After $msg
            }
        })
        $ui.UsageScan.Add_Click({param($s,$e) Start-YumDiskUsage -State $s.Tag -Path ([string]$s.Tag.Ui.UsagePath.Text).Trim() })
        $ui.UsageUp.Add_Click({param($s,$e) try{ $p=[IO.Directory]::GetParent(([string]$s.Tag.Ui.UsagePath.Text).TrimEnd('\')); if($null -ne $p){ Start-YumDiskUsage -State $s.Tag -Path $p.FullName } }catch{} })
        $ui.UsageFolders.Add_MouseDoubleClick({param($s,$e) try{ $it=$s.SelectedItem; if($null -ne $it -and [bool]$it.IsFolder){ Start-YumDiskUsage -State $s.Tag -Path ([string]$it.Path) } }catch{} })
        $ui.UsageOpen.Add_Click({param($s,$e)
            try{ $st=$s.Tag; $it=if($st.Ui.UsageTabs.SelectedIndex -eq 1){$st.Ui.UsageFiles.SelectedItem}else{$st.Ui.UsageFolders.SelectedItem}
                 if($null -eq $it){ $st.Ui.Details.Text='Select a folder or file first.'; return }
                 $p=[string]$it.Path
                 if(Test-Path -LiteralPath $p -PathType Leaf){ Start-Process explorer.exe -ArgumentList ('/select,"{0}"' -f $p) } elseif(Test-Path -LiteralPath $p){ Start-Process explorer.exe -ArgumentList ('"{0}"' -f $p) } }catch{} })
        $ui.OpenFolder.Tag=$state; $ui.SeeDeleted.Tag=$state
        $ui.StorageSense.Content=if(Get-YumStorageSenseOn){'Windows Storage Sense: on  ›'}else{'Windows Storage Sense: off - turn on  ›'}
        $ui.StorageSense.Add_Click({ try{ Start-Process 'ms-settings:storagesense' }catch{} })
        $ui.OpenFolder.Add_Click({param($s,$e)
            try{ $it=$s.Tag.Ui.Junk.SelectedItem; if($null -eq $it){return}
                 if($it.Key -eq 'Recycle'){ Start-Process explorer.exe -ArgumentList 'shell:RecycleBinFolder'; return }
                 $roots=@($it.Roots); if($roots.Count -eq 0){ $s.Tag.Ui.Details.Text='Nothing to show: this category has nothing on this PC right now, or Windows'' own tool handles it.'; return }
                 foreach($r in @($roots | Select-Object -First 3)){ Start-Process explorer.exe -ArgumentList ('"{0}"' -f $r) }
                 if($roots.Count -gt 3){ $s.Tag.Ui.Details.Text=('Opened 3 of {0} folders: {1}' -f $roots.Count,($roots -join '; ')) } }catch{} })
        $ui.SeeDeleted.Add_Click({param($s,$e)
            try{ $p=Get-YumDiskCleanupLogPath; if(Test-Path -LiteralPath $p){ Start-Process notepad.exe -ArgumentList ('"{0}"' -f $p) } else { $s.Tag.Ui.Details.Text='Nothing has been cleaned yet.' } }catch{} })
        $ui.Close.Add_Click({param($s,$e)$s.Tag.Window.Close()})
        Update-YumDiskSummary -State $state
        Start-YumDiskMeasure -State $state
        if(-not (Enter-YumPage -Key 'DiskCleanup' -Window $window)){
            $window.Owner=$script:Yum.Window
            [void]$window.ShowDialog()
        }
    } catch { Write-YumLogException -Context 'Disk cleanup page failed' -Exception $_.Exception; Show-YumMessage -Message ("Disk cleanup could not be opened.`n`n{0}" -f $_.Exception.Message) -Title 'YUMRAM - Disk cleanup' -Buttons 'OK' -Icon 'Error' }
}

function Invoke-YumDiskAutoCleanIfDue {
    # Called from the UI timer. At most one check every 30 minutes; runs only when turned on and a week has passed.
    try{
        if(((Get-Date)-[datetime]$script:Yum['LastDiskAutoCheck']).TotalMinutes -lt 30){return}
        $script:Yum['LastDiskAutoCheck']=Get-Date
        if(-not (Test-YumDiskAutoCleanDue)){return}
        if([bool]$script:Yum['DiskAutoRunning']){return}
        $script:Yum['DiskAutoRunning']=$true
        $keys=@(Get-YumDiskJunkCategories | Where-Object { $_.Auto } | ForEach-Object { $_.Key })
        Start-YumDiskWork -State $null -Argument ([string[]]$keys) -Work { param($a) Invoke-YumDiskCleanup -Keys $a -Automatic } -Done {
            param($st,$res)
            $script:Yum['DiskAutoRunning']=$false
            $x=@($res)[0]
            if($null -ne $x -and [double]$x.Freed -gt 0){ try{ Show-YumTrayNotice -Title 'YUMRAM disk clean' -Text ('Weekly clean freed {0} of old temporary files and leftovers.' -f (Format-YumBytes $x.Freed)) }catch{} }
        }
    }catch{ $script:Yum['DiskAutoRunning']=$false }
}
