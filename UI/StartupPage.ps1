#requires -Version 5.1
# 5.7: Startup apps page (Core\Startup.ps1 does the work). Hosted in the main window like the other pages.

function ConvertTo-YumStartupRow {
    param($App)
    $sub=@($App.Publisher)
    if($App.Scope -eq 'All users'){$sub+='all users'}
    if(-not $App.Enabled -and $null -ne $App.DisabledAt){$sub+=('off since {0:d MMM yyyy}' -f $App.DisabledAt)}
    $mem=if($App.Running){if([double]$App.MemoryMB -ge 1024){'{0:N1} GB' -f ([double]$App.MemoryMB/1024)}else{'{0:N0} MB' -f [double]$App.MemoryMB}}else{'—'}
    $App | Add-Member -NotePropertyName StateText -NotePropertyValue $(if($App.Enabled){'On'}else{'Off'}) -Force
    $App | Add-Member -NotePropertyName SubTitle -NotePropertyValue ($sub -join '  •  ') -Force
    $App | Add-Member -NotePropertyName MemoryText -NotePropertyValue $mem -Force
    return $App
}

function Update-YumStartupList {
    param([hashtable]$State,[string]$KeepName='')
    $ui=$State.Ui
    $apps=@(Get-YumStartupApps | ForEach-Object { ConvertTo-YumStartupRow -App $_ })
    $State.Apps=$apps
    $ui.Items.ItemsSource=$null
    $ui.Items.ItemsSource=$apps
    $on=@($apps|Where-Object{$_.Enabled})
    $ui.SumOn.Text=[string]$on.Count
    $ui.SumOff.Text=[string]@($apps|Where-Object{-not $_.Enabled}).Count
    $ramMB=[double](@($on|Measure-Object -Property MemoryMB -Sum).Sum)
    $ui.SumRam.Text=if($ramMB -ge 1024){'{0:N1} GB' -f ($ramMB/1024)}else{'{0:N0} MB' -f $ramMB}
    $ui.SumSuggest.Text=[string]@($on|Where-Object{$_.Suggestion -eq 'Turn off'}).Count
    $ui.Details.Text=('{0} startup apps found • same list and on/off switch as Task Manager • checked {1:T}' -f $apps.Count,(Get-Date))
    if($KeepName){ foreach($a in $apps){ if(('{0}|{1}|{2}' -f $a.HiveName,$a.ApprovedKey,$a.Name) -eq $KeepName){ $ui.Items.SelectedItem=$a; break } } }
    Update-YumStartupExplanation -State $State
}

function Update-YumStartupExplanation {
    param([hashtable]$State)
    $ui=$State.Ui;$a=$ui.Items.SelectedItem
    if($null -eq $a){ $ui.ExplainTitle.Text='Click a program';$ui.ExplainSub.Text='';$ui.ExplainBody.Visibility='Collapsed';return }
    $ui.ExplainBody.Visibility='Visible'
    $ui.ExplainTitle.Text=[string]$a.Friendly
    $ui.ExplainSub.Text=('{0}  •  {1}' -f $a.Publisher,$(if($a.Enabled){'starts with Windows'}else{'does not start with Windows'}))
    $ui.ExplainAdvice.Text=[string]$a.Advice
    $ui.ExplainNow.Text=if($a.Running){('Running and using {0} of RAM ({1} process{2}).' -f $a.MemoryText,$a.ProcessCount,$(if([int]$a.ProcessCount -eq 1){''}else{'es'}))}else{'Not running right now, so it is not using any RAM.'}
    $ui.ExplainEffect.Text=if($a.Enabled){'It will not open by itself next time you sign in, so it will not use RAM in the background. It stays installed - open it from the Start menu whenever you want. It keeps running until then if it is open now.'}else{'It is already off. Turning it back on makes it start by itself next time you sign in.'}
    $ui.ExplainPath.Text=if($a.ExePath){[string]$a.ExePath}else{[string]$a.Command}
    $ui.OpenLocation.IsEnabled=($a.FileExists -eq $true)
    if($a.Enabled){
        $ui.Toggle.Content='Turn off at startup'
        $ui.Toggle.IsEnabled=-not [bool]$a.Locked
        $ui.Toggle.ToolTip=if($a.Locked){'YUMRAM keeps security and anti-cheat software starting with Windows.'}else{'Uses the same switch as Task Manager. Nothing is deleted.'}
    } else {
        $ui.Toggle.Content='Turn back on'
        $ui.Toggle.IsEnabled=$true
        $ui.Toggle.ToolTip='Start this program with Windows again.'
    }
    if([bool]$a.NeedsAdmin -and -not (Test-YumIsElevated)){$ui.Toggle.IsEnabled=$false;$ui.Toggle.ToolTip='This one starts for all users; run YUMRAM as administrator to change it.'}
}

function Show-YumStartupApps {
    try {
        [xml]$xaml=Read-YumXamlText -Path (Join-Path $script:Yum.Root 'UI\Xaml\Startup.xaml')
        $window=[Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $xaml))
        $ui=@{}
        foreach($n in 'Items','Reload','AdminPill','AdminText','SumOn','SumOff','SumRam','SumSuggest','ExplainTitle','ExplainSub','ExplainAdvice','ExplainBody','ExplainNow','ExplainEffect','ExplainPath','Toggle','OpenLocation','Close','Details'){$ui[$n]=$window.FindName($n);if($null -eq $ui[$n]){throw "Startup page control missing: $n"}}
        $state=@{Window=$window;Ui=$ui;Apps=@()}
        $window.Tag=$state
        foreach($c in 'Items','Reload','Toggle','OpenLocation','Close'){$ui[$c].Tag=$state}
        if(Test-YumIsElevated){$ui.AdminPill.Visibility='Collapsed'}else{$ui.AdminText.Text='Not administrator: "all users" apps are read-only'}
        $ui.Items.Add_SelectionChanged({param($s,$e)try{Update-YumStartupExplanation -State $s.Tag}catch{}})
        $ui.Reload.Add_Click({param($s,$e)try{$sel=$s.Tag.Ui.Items.SelectedItem;$k=if($sel){'{0}|{1}|{2}' -f $sel.HiveName,$sel.ApprovedKey,$sel.Name}else{''};Update-YumStartupList -State $s.Tag -KeepName $k}catch{Write-YumLogException -Context 'Startup list reload failed' -Exception $_.Exception}})
        $ui.Toggle.Add_Click({param($s,$e)
            $st=$s.Tag;$a=$st.Ui.Items.SelectedItem;if($null -eq $a){return}
            $r=Set-YumStartupAppEnabled -App $a -Enabled (-not [bool]$a.Enabled)
            $st.Ui.Details.Text=[string]$r.Reason
            if($r.Success){try{Update-YumStartupList -State $st -KeepName ('{0}|{1}|{2}' -f $a.HiveName,$a.ApprovedKey,$a.Name);$st.Ui.Details.Text=[string]$r.Reason}catch{}}
        })
        $ui.OpenLocation.Add_Click({param($s,$e)try{$a=$s.Tag.Ui.Items.SelectedItem;if($null -ne $a -and $a.FileExists){Start-Process -FilePath 'explorer.exe' -ArgumentList ('/select,"{0}"' -f $a.ExePath)}}catch{Write-YumLogException -Context 'Open startup app location failed' -Exception $_.Exception}})
        $ui.Close.Add_Click({param($s,$e)$s.Tag.Window.Close()})
        Update-YumStartupList -State $state
        if(-not (Enter-YumPage -Key 'Startup' -Window $window)){
            $window.Owner=$script:Yum.Window
            [void]$window.ShowDialog()
        }
    } catch { Write-YumLogException -Context 'Startup apps page failed' -Exception $_.Exception; Show-YumMessage -Message ("Startup apps could not be opened.`n`n{0}" -f $_.Exception.Message) -Title 'YUMRAM - Startup apps' -Buttons 'OK' -Icon 'Error' }
}
