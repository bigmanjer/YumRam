#requires -Version 5.1
# 5.17.0: Uninstall programs page (Core\Uninstaller.ps1 does the work). Hosted in the main window like the other pages.

function ConvertTo-YumUninstallRow {
    param($P)
    $sub=@()
    if([string]$P.Publisher){ $sub+=[string]$P.Publisher }
    if([string]$P.Version){ $sub+=('version {0}' -f $P.Version) }
    if([string]$P.Kind -eq 'Store'){ $sub+='Store app' } elseif([string]$P.Scope -eq 'All users'){ $sub+='all users' }
    $size=if($null -ne $P.SizeMB -and [double]$P.SizeMB -gt 0){ if([double]$P.SizeMB -ge 1024){'{0:N1} GB' -f ([double]$P.SizeMB/1024)}else{'{0:N0} MB' -f [double]$P.SizeMB} }else{'—'}
    $date=if($null -ne $P.InstallDate){ ([datetime]$P.InstallDate).ToString('yyyy-MM-dd') }else{'—'}
    $P | Add-Member -NotePropertyName SubTitle -NotePropertyValue ($sub -join '  •  ') -Force
    $P | Add-Member -NotePropertyName SizeText -NotePropertyValue $size -Force
    $P | Add-Member -NotePropertyName DateText -NotePropertyValue $date -Force
    return $P
}

function Update-YumUninstallList {
    param([hashtable]$State,[string]$KeepKey='')
    $ui=$State.Ui
    $q=([string]$ui.Search.Text).Trim()
    $rows=@($State.All | Where-Object { $null -ne $_ })
    if($q){ $rows=@($rows | Where-Object { ([string]$_.Name -like "*$q*") -or ([string]$_.Publisher -like "*$q*") }) }
    $sort=[string]$ui.SortBy.SelectedItem.Tag
    # (wrapped in @(): a switch that sorts zero rows would give $null, not an empty list)
    $rows=@(switch($sort){
        'Name' { @($rows | Sort-Object Name) }
        'Date' { @($rows | Sort-Object @{Expression={ if($null -eq $_.InstallDate){[datetime]::MinValue}else{[datetime]$_.InstallDate} };Descending=$true},Name) }
        default{ @($rows | Sort-Object @{Expression={ if($null -eq $_.SizeMB){-1}else{[double]$_.SizeMB} };Descending=$true},Name) }
    })
    $State.Shown=$rows
    $ui.Items.ItemsSource=$null
    $ui.Items.ItemsSource=$rows
    $all=@($State.All)
    $ui.SumCount.Text=('{0}' -f $all.Count)
    $mb=[double](@($all | Where-Object { $null -ne $_.SizeMB } | Measure-Object -Property SizeMB -Sum).Sum)
    $ui.SumSize.Text=if($mb -ge 1024){'{0:N1} GB' -f ($mb/1024)}else{'{0:N0} MB' -f $mb}
    # Desktop programs only: for Store apps Windows reports the date of their last automatic update.
    $ui.SumRecent.Text=('{0}' -f @($all | Where-Object { $_.Kind -ne 'Store' -and $null -ne $_.InstallDate -and ((Get-Date)-[datetime]$_.InstallDate).TotalDays -le 30 }).Count)
    $big=@($all | Where-Object { $null -ne $_.SizeMB } | Sort-Object { -[double]$_.SizeMB } | Select-Object -First 1)
    $ui.SumBiggest.Text=if($big.Count){ '{0} ({1})' -f $big[0].Name,(ConvertTo-YumUninstallRow $big[0]).SizeText }else{'--'}
    if($KeepKey){ foreach($r in $rows){ if(('{0}|{1}' -f $r.Name,$r.RegistryPath) -eq $KeepKey){ $ui.Items.SelectedItem=$r; break } } }
    $stores=@($all | Where-Object { $_.Kind -eq 'Store' }).Count
    if(-not $State.Busy){ $ui.Details.Text=('{0} desktop programs and {1} Store apps{2} • sizes come from Windows (some programs do not report one) • checked {3:T}' -f ($all.Count-$stores),$stores,$(if($q){(' • {0} match "{1}"' -f $rows.Count,$q)}else{''}),(Get-Date)) }
    Update-YumUninstallExplanation -State $State
}

function Start-YumUninstallLoad {
    # Desktop programs at once (~0.2 s); Store apps from a background read, then merged in.
    param([hashtable]$State,[string]$KeepKey='')
    $State.All=@(Get-YumInstalledPrograms | ForEach-Object { ConvertTo-YumUninstallRow $_ })
    Update-YumUninstallList -State $State -KeepKey $KeepKey
    $ps=[powershell]::Create()
    [void]$ps.AddScript({ param([string]$Root) . (Join-Path $Root 'Core\Uninstaller.ps1'); @(Get-YumStoreApps) }).AddArgument([string]$script:Yum.Root)
    $job=@{Ps=$ps;Handle=$ps.BeginInvoke();State=$State;Keep=$KeepKey}
    $t=New-Object System.Windows.Threading.DispatcherTimer; $t.Interval=[TimeSpan]::FromMilliseconds(250); $t.Tag=$job
    $t.Add_Tick({param($s,$e)
        $j=$s.Tag; if(-not $j.Handle.IsCompleted){return}; $s.Stop()
        $store=@(); try{ $store=@($j.Ps.EndInvoke($j.Handle)) }catch{}; try{$j.Ps.Dispose()}catch{}
        $st=$j.State
        $st.All=@(@($st.All | Where-Object { $_.Kind -ne 'Store' })+@($store | Where-Object { $null -ne $_ } | ForEach-Object { ConvertTo-YumUninstallRow $_ }))
        try{ Update-YumUninstallList -State $st -KeepKey ([string]$j.Keep) }catch{}
    })
    $t.Start()
}

function Update-YumUninstallExplanation {
    param([hashtable]$State)
    $ui=$State.Ui
    if($State.Busy){ return }
    $p=$ui.Items.SelectedItem
    if($null -eq $p){
        $ui.ExplainTitle.Text='Click a program'; $ui.ExplainSub.Text=''
        $ui.ExplainAdvice.Text='Pick a program to see what it is, how much space it uses, and to uninstall it. YUMRAM runs its own uninstaller and then cleans up what it leaves behind.'
        $ui.ExplainBody.Visibility='Collapsed'; return
    }
    $ui.ExplainBody.Visibility='Visible'
    $ui.ExplainTitle.Text=[string]$p.Name
    $ui.ExplainSub.Text=[string]$p.SubTitle
    $extra=@()
    if([string]$p.SizeText -ne '—'){ $extra+=('Uses {0}.' -f $p.SizeText) }
    if([string]$p.DateText -ne '—'){ $extra+=('Installed {0}.' -f $p.DateText) }
    $ui.ExplainAdvice.Text=('{0}{1}{2}' -f ([string]$p.Why),$(if($extra.Count){[Environment]::NewLine+[Environment]::NewLine}else{''}),($extra -join ' '))
    $loc=[string]$p.InstallLocation
    $ui.ExplainPath.Text=if($loc){$loc}elseif([string]$p.UninstallString){'Its uninstaller: '+[string]$p.UninstallString}else{'Windows did not record where it is installed.'}
    $ui.OpenLocation.IsEnabled=($loc -and [IO.Directory]::Exists($loc))
    $isSelf=([string]$p.Name -match '^(?i)YUMRAM')
    $ui.Uninstall.IsEnabled=-not $isSelf
    $ui.Uninstall.Content='Uninstall…'
    $ui.Uninstall.ToolTip=if($isSelf){'Uninstall YUMRAM from Settings > Apps (YUMRAM cannot remove itself while it runs).'}elseif([string]$p.Kind -eq 'Store'){'Removes this Store app (you can get it back from the Microsoft Store).'}else{'Runs this program''s own uninstaller, then looks for what it left behind.'}
}

function Set-YumUninstallBusy {
    param([hashtable]$State,[bool]$Busy,[string]$Text='')
    $State.Busy=$Busy
    foreach($n in 'Reload','Search','SortBy','Items'){ try{ $State.Ui[$n].IsEnabled=-not $Busy }catch{} }
    if($Text){ $State.Ui.Details.Text=$Text }
}

function Start-YumUninstallFlow {
    # Confirm -> start its own uninstaller -> wait until Windows no longer lists it -> look for leftovers.
    param([hashtable]$State)
    $ui=$State.Ui; $p=$ui.Items.SelectedItem; if($null -eq $p){return}
    $msg=if([string]$p.Kind -eq 'Store'){ "Remove the Store app ""$($p.Name)""?`n`nYou can get it back from the Microsoft Store." }else{ "Uninstall ""$($p.Name)""?`n`nIts own uninstaller opens now - follow its steps (Windows may ask for permission). When it is done, YUMRAM looks for what it left behind and shows it before removing anything." }
    if([string]$p.Advice -eq 'Careful'){ $msg+="`n`nCareful: $($p.Why)" }
    $ans=[System.Windows.MessageBox]::Show($script:Yum.Window,$msg,'YUMRAM - Uninstall',[System.Windows.MessageBoxButton]::OKCancel,$(if([string]$p.Advice -eq 'Careful'){[System.Windows.MessageBoxImage]::Warning}else{[System.Windows.MessageBoxImage]::Question}))
    if($ans -ne [System.Windows.MessageBoxResult]::OK){ return }
    $r=Start-YumProgramUninstall -Program $p
    if(-not $r.Started){
        $ui.Details.Text=[string]$r.Reason
        if([string]$r.Reason -match 'missing' -and -not (Test-YumProgramStillInstalled -Program $p)){ Start-YumLeftoverSearch -State $State -Program $p }
        return
    }
    $State.Current=@{Program=$p;Run=$r;Started=(Get-Date);Exited=$null}
    Set-YumUninstallBusy -State $State -Busy $true -Text ([string]$r.Reason)
    $ui.PanelLabel.Text='UNINSTALLING'
    $ui.ExplainAdvice.Text=('Follow the steps in {0}''s uninstaller. YUMRAM waits until Windows no longer lists it, then looks for leftovers. If you cancel the uninstaller, nothing else happens.' -f $p.Name)
    $ui.Uninstall.Content='Stop waiting'; $ui.Uninstall.IsEnabled=$true
    $t=New-Object System.Windows.Threading.DispatcherTimer; $t.Interval=[TimeSpan]::FromSeconds(1); $t.Tag=$State
    $State.WaitTimer=$t
    $t.Add_Tick({param($s,$e)
        $st=$s.Tag; $c=$st.Current; if($null -eq $c){ $s.Stop(); return }
        $p=$c.Program; $r=$c.Run
        $running=if($null -ne $r.Job){ -not $r.Job.Handle.IsCompleted }elseif($null -ne $r.Process){ -not $r.Process.HasExited }else{$false}
        if(-not $running -and $null -eq $c.Exited){ $c.Exited=Get-Date }
        # Store apps: ask Windows only once the removal finished (that check takes ~0.5 s).
        if($null -ne $r.Job -and $running){ $st.Ui.Details.Text=('Removing {0}… ({1} s)' -f $p.Name,[int]((Get-Date)-[datetime]$c.Started).TotalSeconds); return }
        $still=Test-YumProgramStillInstalled -Program $p
        if(-not $still){
            $s.Stop(); $st.Current=$null
            Write-YumLog ('Uninstall: {0} is no longer installed.' -f $p.Name)
            Start-YumLeftoverSearch -State $st -Program $p
            return
        }
        # Uninstallers often hand over to a copy of themselves and exit at once; keep watching for up to 10 minutes.
        if($null -ne $c.Exited -and ((Get-Date)-[datetime]$c.Exited).TotalMinutes -ge 10){
            $s.Stop(); $st.Current=$null; Set-YumUninstallBusy -State $st -Busy $false -Text ('{0} is still installed - its uninstaller was closed or cancelled. Nothing else was changed.' -f $p.Name)
            $st.Ui.PanelLabel.Text='WHAT IS IT?'; Update-YumUninstallExplanation -State $st; return
        }
        $secs=[int]((Get-Date)-[datetime]$c.Started).TotalSeconds
        $st.Ui.Details.Text=if($running){ 'Waiting for {0}''s uninstaller… ({1} s)' -f $p.Name,$secs }else{ 'The uninstaller window closed; waiting for Windows to confirm {0} is gone… ({1} s). If you cancelled it, press "Stop waiting".' -f $p.Name,$secs }
    })
    $t.Start()
}

function Stop-YumUninstallWait {
    param([hashtable]$State)
    try{ if($null -ne $State['WaitTimer']){ $State.WaitTimer.Stop() } }catch{}
    $p=$null; try{ $p=$State.Current.Program }catch{}
    $State.Current=$null
    Set-YumUninstallBusy -State $State -Busy $false -Text $(if($p){ '{0}: stopped waiting. If it is still installed, nothing else was changed.' -f $p.Name }else{''})
    $State.Ui.PanelLabel.Text='WHAT IS IT?'
    Start-YumUninstallLoad -State $State
}

function Start-YumLeftoverSearch {
    param([hashtable]$State,$Program)
    $ui=$State.Ui
    Set-YumUninstallBusy -State $State -Busy $true -Text ('{0} was uninstalled. Looking for what it left behind…' -f $Program.Name)
    $ui.PanelLabel.Text='UNINSTALLED'; $ui.ExplainTitle.Text=[string]$Program.Name; $ui.ExplainSub.Text='uninstalled'
    $ui.ExplainAdvice.Text='Looking for folders, shortcuts and registry entries it left behind…'; $ui.ExplainBody.Visibility='Collapsed'
    $ps=[powershell]::Create()
    [void]$ps.AddScript({ param([string]$Root,$P) . (Join-Path $Root 'Core\Uninstaller.ps1'); @(Find-YumProgramLeftovers -Program $P) }).AddArgument([string]$script:Yum.Root).AddArgument($Program)
    $job=@{Ps=$ps;Handle=$ps.BeginInvoke();State=$State;Program=$Program}
    $t=New-Object System.Windows.Threading.DispatcherTimer; $t.Interval=[TimeSpan]::FromMilliseconds(300); $t.Tag=$job
    $t.Add_Tick({param($s,$e)
        $j=$s.Tag; if(-not $j.Handle.IsCompleted){return}; $s.Stop()
        $rows=@(); try{ $rows=@($j.Ps.EndInvoke($j.Handle) | Where-Object { $null -ne $_ }) }catch{ try{Write-YumLogException -Context 'Leftover search failed' -Exception $_.Exception}catch{} }; try{$j.Ps.Dispose()}catch{}
        Show-YumLeftovers -State $j.State -Program $j.Program -Rows $rows
    })
    $t.Start()
}

function Show-YumLeftovers {
    param([hashtable]$State,$Program,$Rows)
    $ui=$State.Ui
    foreach($r in @($Rows)){
        $short=[string]$r.Path; foreach($pair in @(@($env:LOCALAPPDATA,'%LOCALAPPDATA%'),@($env:APPDATA,'%APPDATA%'),@($env:ProgramData,'%ProgramData%'),@($env:USERPROFILE,'%USERPROFILE%'))){ if($pair[0] -and $short.StartsWith($pair[0],[StringComparison]::OrdinalIgnoreCase)){ $short=$pair[1]+$short.Substring($pair[0].Length); break } }
        $kind=switch([string]$r.Type){'Folder'{'Folder'};'Shortcut'{'Shortcut'};default{'Registry'}}
        $r | Add-Member -NotePropertyName ShortPath -NotePropertyValue $short -Force
        $r | Add-Member -NotePropertyName Line2 -NotePropertyValue ('{0}{1} - {2}' -f $kind,$(if([double]$r.SizeMB -gt 0){' ({0:N1} MB)' -f [double]$r.SizeMB}else{''}),$r.Note) -Force
    }
    $State.Leftovers=@($Rows)
    $State.LeftProgram=$Program
    Set-YumUninstallBusy -State $State -Busy $false -Text ''
    $ui.LeftPanel.Visibility='Visible'
    $ui.OpenBackups.Visibility='Collapsed'
    if(@($Rows).Count -eq 0){
        $ui.LeftText.Text='Nothing left behind - it removed itself completely.'
        $ui.Leftovers.ItemsSource=$null; $ui.RemoveLeftovers.Visibility='Collapsed'; $ui.SkipLeftovers.Content='OK'
        $ui.ExplainAdvice.Text=('{0} is gone.' -f $Program.Name)
        $ui.Details.Text=('{0} was uninstalled; nothing was left behind.' -f $Program.Name)
    } else {
        $mb=[double](@($Rows | Measure-Object -Property SizeMB -Sum).Sum)
        $ui.LeftText.Text=('{0} things it left behind{1}. Ticked ones are safe to remove; folders and shortcuts go to the Recycle Bin and registry entries are backed up first. Unticked: its settings in your account (may include your own files) - tick them if you are sure.' -f @($Rows).Count,$(if($mb -gt 0){' ({0:N0} MB)' -f $mb}else{''}))
        $ui.Leftovers.ItemsSource=$null; $ui.Leftovers.ItemsSource=@($Rows)
        $ui.RemoveLeftovers.Visibility='Visible'; $ui.RemoveLeftovers.IsEnabled=$true; $ui.SkipLeftovers.Content='Keep them'
        $ui.ExplainAdvice.Text=('{0} is gone. Below is what it left behind.' -f $Program.Name)
        $ui.Details.Text=('{0} was uninstalled. It left {1} things behind - see the panel on the right.' -f $Program.Name,@($Rows).Count)
    }
    Start-YumUninstallLoad -State $State
}

function Start-YumLeftoverRemoval {
    param([hashtable]$State)
    $ui=$State.Ui; $p=$State.LeftProgram
    $items=@($State.Leftovers | Where-Object { [bool]$_.Ticked })
    if($items.Count -eq 0){ $ui.Details.Text='Nothing is ticked.'; return }
    $mb=[double](@($items | Measure-Object -Property SizeMB -Sum).Sum)
    $msg=('Remove {0} leftovers of {1}{2}?{3}{3}Folders and shortcuts go to the Recycle Bin. Registry entries are saved to a backup file first (double-click it to put them back).' -f $items.Count,$p.Name,$(if($mb -gt 0){' ({0:N0} MB)' -f $mb}else{''}),[Environment]::NewLine)
    $ans=[System.Windows.MessageBox]::Show($script:Yum.Window,$msg,'YUMRAM - Remove leftovers',[System.Windows.MessageBoxButton]::OKCancel,[System.Windows.MessageBoxImage]::Question)
    if($ans -ne [System.Windows.MessageBoxResult]::OK){ return }
    $ui.RemoveLeftovers.IsEnabled=$false
    Set-YumUninstallBusy -State $State -Busy $true -Text ('Removing {0} leftovers…' -f $items.Count)
    $ps=[powershell]::Create()
    [void]$ps.AddScript({ param([string]$Root,$Y,$P,$I) foreach($m in 'Core\Logging.ps1','Core\Config.ps1','Core\Uninstaller.ps1'){ . (Join-Path $Root $m) }; $script:Yum=$Y; @(Remove-YumProgramLeftovers -Program $P -Items $I) }).AddArgument([string]$script:Yum.Root).AddArgument($script:Yum).AddArgument($p).AddArgument($items)
    $job=@{Ps=$ps;Handle=$ps.BeginInvoke();State=$State;Program=$p}
    $t=New-Object System.Windows.Threading.DispatcherTimer; $t.Interval=[TimeSpan]::FromMilliseconds(300); $t.Tag=$job
    $t.Add_Tick({param($s,$e)
        $j=$s.Tag; if(-not $j.Handle.IsCompleted){return}; $s.Stop()
        $res=@(); try{ $res=@($j.Ps.EndInvoke($j.Handle) | Where-Object { $null -ne $_ }) }catch{ try{Write-YumLogException -Context 'Leftover removal failed' -Exception $_.Exception}catch{} }; try{$j.Ps.Dispose()}catch{}
        $st=$j.State; Set-YumUninstallBusy -State $st -Busy $false -Text ''
        $ok=@($res | Where-Object { $_.Removed }).Count; $bad=@($res | Where-Object { -not $_.Removed })
        $st.Ui.LeftText.Text=('Removed {0} of {1}.{2}{3}' -f $ok,$res.Count,$(if($bad.Count){' Not removed: '+(($bad | ForEach-Object { '{0} ({1})' -f [IO.Path]::GetFileName([string]$_.Path),$_.Result }) -join '; ')}else{''}),' Folders and shortcuts are in the Recycle Bin.')
        $st.Ui.Leftovers.ItemsSource=$null; $st.Ui.RemoveLeftovers.Visibility='Collapsed'; $st.Ui.SkipLeftovers.Content='OK'
        $st.Ui.OpenBackups.Visibility=$(if(@($res | Where-Object { $_.Type -eq 'Registry' -and $_.Removed }).Count){'Visible'}else{'Collapsed'})
        $st.Ui.Details.Text=('{0}: {1} leftovers removed. The list of what was removed is in uninstall-last.txt in the YUMRAM folder.' -f $j.Program.Name,$ok)
    })
    $t.Start()
}

function Show-YumUninstaller {
    try {
        [xml]$xaml=Read-YumXamlText -Path (Join-Path $script:Yum.Root 'UI\Xaml\Uninstaller.xaml')
        $window=[Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $xaml))
        $ui=@{}
        foreach($n in 'Items','Reload','AdminPill','AdminText','SumCount','SumSize','SumRecent','SumBiggest','Search','SearchHint','SortBy','PanelLabel','ExplainTitle','ExplainSub','ExplainAdvice','ExplainBody','ExplainPath','Uninstall','OpenLocation','LeftPanel','LeftText','Leftovers','RemoveLeftovers','SkipLeftovers','OpenBackups','Close','Details'){ $ui[$n]=$window.FindName($n) }
        $state=@{Window=$window;Ui=$ui;All=@();Shown=@();Busy=$false;Current=$null;WaitTimer=$null;Leftovers=@();LeftProgram=$null}
        $window.Tag=$state
        foreach($c in 'Items','Reload','Search','SortBy','Uninstall','OpenLocation','Leftovers','RemoveLeftovers','SkipLeftovers','OpenBackups','Close'){ $ui[$c].Tag=$state }
        if(Test-YumIsElevated){ $ui.AdminPill.Visibility='Collapsed' }else{ $ui.AdminText.Text='Not administrator: Windows asks before uninstalling "all users" programs' }
        $ui.Items.Add_SelectionChanged({param($s,$e) try{ Update-YumUninstallExplanation -State $s.Tag }catch{} })
        $ui.Search.Add_TextChanged({param($s,$e) try{ $s.Tag.Ui.SearchHint.Visibility=$(if([string]$s.Text){'Collapsed'}else{'Visible'}); Update-YumUninstallList -State $s.Tag }catch{} })
        $ui.SortBy.Add_SelectionChanged({param($s,$e) try{ if($null -ne $s.Tag){ Update-YumUninstallList -State $s.Tag } }catch{} })
        $ui.Reload.Add_Click({param($s,$e) try{ $sel=$s.Tag.Ui.Items.SelectedItem; Start-YumUninstallLoad -State $s.Tag -KeepKey $(if($sel){'{0}|{1}' -f $sel.Name,$sel.RegistryPath}else{''}) }catch{} })
        $ui.Uninstall.Add_Click({param($s,$e) try{ if($null -ne $s.Tag.Current){ Stop-YumUninstallWait -State $s.Tag } else { Start-YumUninstallFlow -State $s.Tag } }catch{ Write-YumLogException -Context 'Uninstall failed' -Exception $_.Exception } })
        $ui.OpenLocation.Add_Click({param($s,$e) try{ $p=$s.Tag.Ui.Items.SelectedItem; if($null -ne $p -and [IO.Directory]::Exists([string]$p.InstallLocation)){ Start-Process -FilePath 'explorer.exe' -ArgumentList ('"{0}"' -f $p.InstallLocation) } }catch{} })
        # Leftover tick boxes: the row remembers the tick (the list reuses row visuals while scrolling).
        $ui.Leftovers.AddHandler([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent,[System.Windows.RoutedEventHandler]{param($s,$e)
            try{ $cb=$e.OriginalSource; if($cb -is [System.Windows.Controls.CheckBox]){ foreach($r in @($s.Tag.Leftovers)){ if([string]$r.Path -eq [string]$cb.Tag){ $r.Ticked=[bool]$cb.IsChecked } } } }catch{} })
        $ui.RemoveLeftovers.Add_Click({param($s,$e) try{ Start-YumLeftoverRemoval -State $s.Tag }catch{ Write-YumLogException -Context 'Leftover removal failed' -Exception $_.Exception } })
        $ui.SkipLeftovers.Add_Click({param($s,$e) $st=$s.Tag; $st.Ui.LeftPanel.Visibility='Collapsed'; $st.Leftovers=@(); $st.Ui.PanelLabel.Text='WHAT IS IT?'; Update-YumUninstallExplanation -State $st })
        $ui.OpenBackups.Add_Click({param($s,$e) try{ Start-Process -FilePath 'explorer.exe' -ArgumentList ('"{0}"' -f (Get-YumUninstallBackupDirectory)) }catch{} })
        $ui.Close.Add_Click({param($s,$e) $s.Tag.Window.Close() })
        Start-YumUninstallLoad -State $state
        if(-not (Enter-YumPage -Key 'Uninstaller' -Window $window)){
            $window.Owner=$script:Yum.Window
            [void]$window.ShowDialog()
        }
    } catch { Write-YumLogException -Context 'Uninstall page failed' -Exception $_.Exception; Show-YumMessage -Message ("Uninstall programs could not be opened.`n`n{0}" -f $_.Exception.Message) -Title 'YUMRAM - Uninstall programs' -Buttons 'OK' -Icon 'Error' }
}
