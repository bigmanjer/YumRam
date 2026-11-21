#requires -Version 5.1
# 5.15: Windows bloat page (Core\WindowsBloat.ps1 does the work). Hosted in the main window like the other pages.
# App scans and removals run in a background runspace (Get/Remove-AppxPackage take seconds); the UI thread only
# polls with a DispatcherTimer and renders, as everywhere else in YUMRAM.

function Start-YumBloatWork {
    # Runs $Work (a scriptblock taking one argument) in a runspace with the Windows bloat module loaded,
    # then calls $Done with (State, result) on the UI thread.
    param([hashtable]$State,[scriptblock]$Work,$Argument,[scriptblock]$Done)
    $ps=[powershell]::Create()
    [void]$ps.AddScript({
        param($Shared,[string]$Root,$Arg,[string]$WorkText)
        foreach($m in 'Core\Logging.ps1','Core\Native.ps1','Core\WindowsBloat.ps1'){ . (Join-Path $Root $m) }
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
        try{ $res=$j.Ps.EndInvoke($j.Handle) }catch{ try{Write-YumLogException -Context 'Windows bloat background work failed' -Exception $_.Exception}catch{} }
        try{$j.Ps.Dispose()}catch{}
        try{ & $j.Done $j.State $res }catch{ try{Write-YumLogException -Context 'Windows bloat page update failed' -Exception $_.Exception}catch{} }
    })
    $State.Busy=$true
    Update-YumBloatButtons -State $State
    $t.Start()
}

function Update-YumBloatButtons {
    param([hashtable]$State)
    $ui=$State.Ui;$busy=[bool]$State.Busy
    foreach($n in 'Reload','RemoveSuggested','ApplyRecommended'){ $ui[$n].IsEnabled=-not $busy }
    Update-YumBloatExplanation -State $State
}

function Update-YumBloatSummary {
    param([hashtable]$State)
    $ui=$State.Ui
    $ui.SumApps.Text=[string]@($State.Apps).Count
    $ui.SumSuggest.Text=[string]@($State.Apps | Where-Object { $_.Suggest -eq 'Remove' }).Count
    $ui.SumSettings.Text=[string]@($State.Settings | Where-Object { $_.State -ne 'Off' }).Count
    $hist=@(Get-YumBloatHistory)
    $ui.SumRemoved.Text=[string]$hist.Count
    $ui.History.ItemsSource=$null
    $ui.History.ItemsSource=@($hist | Sort-Object Time -Descending | ForEach-Object { [pscustomobject]@{Label=('{0}  •  {1}' -f $_.Name,([string]$_.Time).Replace('T',' ').Substring(0,16));PackageFamilyName=[string]$_.PackageFamilyName} })
}

function Update-YumBloatSettingsList {
    param([hashtable]$State,[string]$KeepKey='')
    $rows=@(Get-YumWindowsBloatTweakRows | ForEach-Object {
        $_ | Add-Member -NotePropertyName SubTitle -NotePropertyValue $(if($_.Scope -eq 'Machine'){'whole PC • needs administrator'}else{'your account'}) -Force; $_ })
    $State.Settings=$rows
    $State.Ui.Settings.ItemsSource=$null
    $State.Ui.Settings.ItemsSource=$rows
    if($KeepKey){ foreach($r in $rows){ if($r.Key -eq $KeepKey){ $State.Ui.Settings.SelectedItem=$r; break } } }
    Update-YumBloatSummary -State $State
}

function Set-YumBloatAppRows {
    param([hashtable]$State,$Rows,[string]$KeepKey='')
    $apps=@($Rows | Where-Object { $null -ne $_ } | ForEach-Object {
        $sub=@($_.Publisher)
        if([bool]$_.Provisioned){$sub+='also set up for new users'}
        $_ | Add-Member -NotePropertyName SubTitle -NotePropertyValue (($sub | Where-Object {$_}) -join '  •  ') -Force; $_ })
    $State.Apps=$apps
    $State.Ui.Apps.ItemsSource=$null
    $State.Ui.Apps.ItemsSource=$apps
    if($KeepKey){ foreach($a in $apps){ if($a.Key -eq $KeepKey){ $State.Ui.Apps.SelectedItem=$a; break } } }
    Update-YumBloatSummary -State $State
}

function Start-YumBloatScan {
    param([hashtable]$State,[string]$KeepKey='',[string]$Message='')
    $State.Ui.Details.Text='Reading the app list from Windows…'
    $State.KeepKey=$KeepKey;$State.AfterMessage=$Message
    Start-YumBloatWork -State $State -Work { param($a) Get-YumWindowsBloatApps } -Argument $null -Done {
        param($st,$res)
        $st.Busy=$false
        Set-YumBloatAppRows -State $st -Rows @($res) -KeepKey ([string]$st.KeepKey)
        Update-YumBloatSettingsList -State $st
        $st.Ui.Details.Text=if($st.AfterMessage){[string]$st.AfterMessage}else{('{0} preinstalled apps from YUMRAM''s list are on this PC  •  {1} ad and tip settings checked  •  {2:T}' -f @($st.Apps).Count,@($st.Settings).Count,(Get-Date))}
        Update-YumBloatButtons -State $st
    }
}

function Get-YumBloatSelection {
    param([hashtable]$State)
    if($State.Focus -eq 'Settings'){ return $State.Ui.Settings.SelectedItem }
    return $State.Ui.Apps.SelectedItem
}

function Update-YumBloatExplanation {
    param([hashtable]$State)
    $ui=$State.Ui;$it=Get-YumBloatSelection -State $State
    $ui.GetBack.IsEnabled=($null -ne $ui.History.SelectedItem -and [string]$ui.History.SelectedItem.PackageFamilyName)
    if($null -eq $it){ $ui.ExplainTitle.Text='Click an app or a setting';$ui.ExplainSub.Text='';$ui.ExplainBody.Visibility='Collapsed';return }
    $ui.ExplainBody.Visibility='Visible'
    $ui.ExplainTitle.Text=[string]$it.Name
    $ui.ExplainWhy.Text=[string]$it.Why
    $admin=Test-YumIsElevated
    if($it.Kind -eq 'App'){
        $ui.ExplainSub.Text=('{0}  •  version {1}  •  advice: {2}' -f $it.Publisher,$it.Version,$it.Suggest)
        $ui.ExplainEffect.Text='The app is uninstalled for your account. Your files are not touched. Nothing else in Windows changes.'
        $ui.ExplainUndo.Text='Yes. It is listed under "Removed by YUMRAM" below; "Get it back" opens its Microsoft Store page, where you can install it again.'
        $ui.ForNewUsers.Visibility=if([bool]$it.Provisioned){'Visible'}else{'Collapsed'}
        $ui.ForNewUsers.IsEnabled=$admin
        $ui.Act.Content='Remove this app';$ui.Act.Visibility='Visible';$ui.Undo.Visibility='Collapsed'
        $ui.Act.IsEnabled=-not [bool]$State.Busy
    } else {
        $ui.ExplainSub.Text=('{0}  •  now: {1}  •  advice: {2}' -f $(if($it.Scope -eq 'Machine'){'Whole PC (administrator)'}else{'Your account'}),$it.State,$it.Suggest)
        $ui.ExplainEffect.Text=('{0} Takes effect: {1}.' -f $(if($it.State -eq 'Off'){'It is already off.'}else{'Windows stops showing it.'}),$it.When)
        $ui.ExplainUndo.Text=if($it.Undoable){'Yes. YUMRAM saved the original values when it turned this off; Undo puts them back exactly.'}else{'Yes. YUMRAM saves the original values before changing anything, so Undo puts them back exactly.'}
        $ui.ForNewUsers.Visibility='Collapsed'
        $ui.Act.Content='Turn it off';$ui.Act.Visibility=if($it.State -eq 'Off'){'Collapsed'}else{'Visible'}
        $ui.Undo.Visibility=if($it.Undoable){'Visible'}else{'Collapsed'}
        $needAdmin=($it.Scope -eq 'Machine' -and -not $admin)
        $ui.Act.IsEnabled=-not $needAdmin -and -not [bool]$State.Busy
        $ui.Undo.IsEnabled=-not $needAdmin -and -not [bool]$State.Busy
        $ui.Act.ToolTip=if($needAdmin){'This is a Windows policy for the whole PC; run YUMRAM as administrator to change it.'}else{$null}
    }
}

function Confirm-YumBloat {
    param([string]$Message,[string]$Title='YUMRAM - Windows bloat')
    $r=[System.Windows.MessageBox]::Show($script:Yum.Window,$Message,$Title,[System.Windows.MessageBoxButton]::YesNo,[System.Windows.MessageBoxImage]::Question)
    return ($r -eq [System.Windows.MessageBoxResult]::Yes)
}

function Invoke-YumBloatRemoveApps {
    param([hashtable]$State,[object[]]$Apps,[bool]$ForNewUsers)
    $list=@($Apps | ForEach-Object { [pscustomobject]@{Name=$_.Name;PackageName=$_.PackageName;PackageFullName=$_.PackageFullName;PackageFamilyName=$_.PackageFamilyName;Version=$_.Version;ProvisionedName=$_.ProvisionedName} })
    $State.Ui.Details.Text=('Removing {0} app{1}…' -f $list.Count,$(if($list.Count -eq 1){''}else{'s'}))
    Start-YumBloatWork -State $State -Argument @{Apps=$list;ForNewUsers=$ForNewUsers} -Work {
        param($a)
        foreach($app in @($a.Apps)){ Remove-YumWindowsBloatApp -App $app -ForNewUsers:([bool]$a.ForNewUsers) }
    } -Done {
        param($st,$res)
        $st.Busy=$false
        $ok=@($res | Where-Object { $_.Success }).Count;$bad=@($res | Where-Object { -not $_.Success })
        $msg=if(@($res).Count -eq 1){[string]@($res)[0].Reason}else{('{0} removed{1}. Get any of them back from "Removed by YUMRAM".' -f $ok,$(if($bad.Count){(', {0} could not be removed: {1}' -f $bad.Count,(($bad | ForEach-Object {$_.Reason}) -join '; '))}else{''}))}
        try{ Show-YumToast -Kind $(if($bad.Count){'Warn'}else{'Ok'}) -Text $msg }catch{}
        Start-YumBloatScan -State $st -Message $msg
    }
}

function Show-YumWindowsBloat {
    try {
        [xml]$xaml=Read-YumXamlText -Path (Join-Path $script:Yum.Root 'UI\Xaml\WindowsBloat.xaml')
        $window=[Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $xaml))
        $ui=@{}
        foreach($n in 'Apps','Settings','Reload','AdminPill','AdminText','SumApps','SumSuggest','SumSettings','SumRemoved','ExplainTitle','ExplainSub','ExplainWhy','ExplainBody','ExplainEffect','ExplainUndo','ForNewUsers','Act','Undo','History','GetBack','RemoveSuggested','ApplyRecommended','Close','Details'){$ui[$n]=$window.FindName($n);if($null -eq $ui[$n]){throw "Windows bloat page control missing: $n"}}
        $state=@{Window=$window;Ui=$ui;Apps=@();Settings=@();Focus='Apps';Busy=$false}
        $window.Tag=$state
        foreach($c in 'Apps','Settings','Reload','Act','Undo','History','GetBack','RemoveSuggested','ApplyRecommended','Close'){$ui[$c].Tag=$state}
        if(Test-YumIsElevated){$ui.AdminPill.Visibility='Collapsed'}else{$ui.AdminText.Text='Not administrator: whole-PC settings and "new users" are read-only'}
        $ui.Apps.Add_SelectionChanged({param($s,$e)try{ if($null -ne $s.SelectedItem){$s.Tag.Focus='Apps';$s.Tag.Ui.Settings.SelectedItem=$null}; Update-YumBloatExplanation -State $s.Tag }catch{}})
        $ui.Settings.Add_SelectionChanged({param($s,$e)try{ if($null -ne $s.SelectedItem){$s.Tag.Focus='Settings';$s.Tag.Ui.Apps.SelectedItem=$null}; Update-YumBloatExplanation -State $s.Tag }catch{}})
        $ui.History.Add_SelectionChanged({param($s,$e)try{ Update-YumBloatExplanation -State $s.Tag }catch{}})
        $ui.Reload.Add_Click({param($s,$e)try{ $sel=Get-YumBloatSelection -State $s.Tag; Start-YumBloatScan -State $s.Tag -KeepKey $(if($sel){[string]$sel.Key}else{''}) }catch{Write-YumLogException -Context 'Windows bloat reload failed' -Exception $_.Exception}})
        $ui.Act.Add_Click({param($s,$e)
            $st=$s.Tag;$it=Get-YumBloatSelection -State $st;if($null -eq $it -or $st.Busy){return}
            if($it.Kind -eq 'App'){
                if(-not (Confirm-YumBloat -Message ('Remove {0}?{1}{1}It is uninstalled for your account. You can install it again from the Microsoft Store at any time.' -f $it.Name,[Environment]::NewLine))){return}
                Invoke-YumBloatRemoveApps -State $st -Apps @($it) -ForNewUsers ([bool]$st.Ui.ForNewUsers.IsChecked)
            } else {
                $r=Set-YumBloatTweak -Tweak $it.Tweak
                $st.Ui.Details.Text=[string]$r.Reason
                try{ Show-YumToast -Kind $(if($r.Success){'Ok'}else{'Warn'}) -Text ([string]$r.Reason) }catch{}
                Update-YumBloatSettingsList -State $st -KeepKey ([string]$it.Key)
            }
        })
        $ui.Undo.Add_Click({param($s,$e)
            $st=$s.Tag;$it=Get-YumBloatSelection -State $st;if($null -eq $it -or $it.Kind -ne 'Setting'){return}
            $r=Set-YumBloatTweak -Tweak $it.Tweak -Undo
            $st.Ui.Details.Text=[string]$r.Reason
            try{ Show-YumToast -Kind $(if($r.Success){'Ok'}else{'Warn'}) -Text ([string]$r.Reason) }catch{}
            Update-YumBloatSettingsList -State $st -KeepKey ([string]$it.Key)
        })
        $ui.RemoveSuggested.Add_Click({param($s,$e)
            $st=$s.Tag;if($st.Busy){return}
            $sel=@($st.Apps | Where-Object { $_.Suggest -eq 'Remove' })
            if($sel.Count -eq 0){ $st.Ui.Details.Text='Nothing marked Remove is installed - this PC is already clean of those.'; try{Show-YumToast -Text 'No apps marked Remove are installed.'}catch{}; return }
            $names=($sel | ForEach-Object { '  •  '+$_.Name }) -join [Environment]::NewLine
            if(-not (Confirm-YumBloat -Message ('Remove these {0} apps?{1}{1}{2}{1}{1}They are uninstalled for your account and can be installed again from the Microsoft Store. Apps marked "Your call" are not included.' -f $sel.Count,[Environment]::NewLine,$names))){return}
            Invoke-YumBloatRemoveApps -State $st -Apps $sel -ForNewUsers ([bool](Test-YumIsElevated))
        })
        $ui.ApplyRecommended.Add_Click({param($s,$e)
            $st=$s.Tag
            $sel=@($st.Settings | Where-Object { $_.Suggest -eq 'Recommended' -and $_.State -ne 'Off' -and ($_.Scope -ne 'Machine' -or (Test-YumIsElevated)) })
            if($sel.Count -eq 0){ $st.Ui.Details.Text='Every recommended setting is already off.'; try{Show-YumToast -Text 'Every recommended setting is already off.'}catch{}; return }
            $names=($sel | ForEach-Object { '  •  '+$_.Name }) -join [Environment]::NewLine
            if(-not (Confirm-YumBloat -Message ('Turn off these {0}?{1}{1}{2}{1}{1}YUMRAM saves the original values first, so each one can be undone exactly.' -f $sel.Count,[Environment]::NewLine,$names))){return}
            $ok=0;$bad=@()
            foreach($it in $sel){ $r=Set-YumBloatTweak -Tweak $it.Tweak; if($r.Success){$ok++}else{$bad+=$r.Reason} }
            $msg=('{0} setting{1} turned off.{2} Some take effect after you sign out and back in.' -f $ok,$(if($ok -eq 1){''}else{'s'}),$(if($bad.Count){' Failed: '+($bad -join '; ')}else{''}))
            $st.Ui.Details.Text=$msg
            try{ Show-YumToast -Kind $(if($bad.Count){'Warn'}else{'Ok'}) -Text $msg }catch{}
            Update-YumBloatSettingsList -State $st
        })
        $ui.GetBack.Add_Click({param($s,$e)try{ $h=$s.Tag.Ui.History.SelectedItem; if($null -ne $h){ Open-YumBloatStorePage -PackageFamilyName ([string]$h.PackageFamilyName) } }catch{Write-YumLogException -Context 'Open Store page failed' -Exception $_.Exception}})
        $ui.Close.Add_Click({param($s,$e)$s.Tag.Window.Close()})
        Update-YumBloatSettingsList -State $state
        Start-YumBloatScan -State $state
        if(-not (Enter-YumPage -Key 'WindowsBloat' -Window $window)){
            $window.Owner=$script:Yum.Window
            [void]$window.ShowDialog()
        }
    } catch { Write-YumLogException -Context 'Windows bloat page failed' -Exception $_.Exception; Show-YumMessage -Message ("Windows bloat could not be opened.`n`n{0}" -f $_.Exception.Message) -Title 'YUMRAM - Windows bloat' -Buttons 'OK' -Icon 'Error' }
}
