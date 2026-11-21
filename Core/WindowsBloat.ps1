#requires -Version 5.1
# 5.15: Windows bloat - preinstalled apps and Windows ad/suggestion/AI settings, all reversible.
#
# Research (Docs/AUDIT-AND-RESEARCH-2026-11.md): modelled on the safety lists of Win11Debloat (MIT,
# Config/Apps.json "SelectedByDefault"/"unsafe") and winutil's undo model (MIT, config/tweaks.json
# "OriginalValue"). No code was copied; package and registry names are public facts.
#
# Rules:
#   - Apps: only packages in $script:YumBloatApps are ever offered. Store, Edge, Terminal, Photos, Calculator,
#     Notepad, Paint, Xbox Identity, App Installer, frameworks and non-removable packages never are.
#     Removal = Remove-AppxPackage for you (no admin). As administrator you can also de-provision it so new
#     user accounts do not get it. Every removal is recorded; "Get it back" opens its Microsoft Store page.
#   - Settings: documented per-user values (and a few machine policies that need administrator). Before a
#     change YUMRAM saves the exact original value (or that it did not exist) in windows-bloat-undo.json;
#     Undo puts that back. Nothing else in Windows is touched: no services, no Windows Update, no Defender.

$script:YumBloatNever=@('Microsoft.WindowsStore','Microsoft.StorePurchaseApp','Microsoft.DesktopAppInstaller','Microsoft.MicrosoftEdge*','Microsoft.Edge*','Microsoft.WindowsTerminal','Microsoft.Windows.Photos','Microsoft.WindowsCalculator','Microsoft.WindowsNotepad','Microsoft.Paint','Microsoft.XboxIdentityProvider','Microsoft.SecHealthUI','Microsoft.VCLibs*','Microsoft.NET.*','Microsoft.UI.Xaml*','Microsoft.WindowsAppRuntime*','Microsoft.Services.Store.Engagement','Microsoft.HEIFImageExtension','Microsoft.WebMediaExtensions','Microsoft.VP9VideoExtensions','Microsoft.WebpImageExtension','Microsoft.ZuneMusic','Microsoft.ScreenSketch','Microsoft.WindowsCamera','Microsoft.AV1VideoExtension','Microsoft.HEVCVideoExtension','Microsoft.RawImageExtension')

# Suggest: 'Remove' = nearly nobody needs it; 'Your call' = some people use it.
$script:YumBloatApps=@(
    @{Id='Microsoft.BingNews';Name='Microsoft News';Suggest='Remove';Why='News feed app. The same news is on the web and in Edge.'}
    @{Id='Microsoft.BingWeather';Name='Weather';Suggest='Your call';Why='Weather app. Keep it if you use it; the weather is also on the web.'}
    @{Id='Microsoft.BingSports';Name='Sports';Suggest='Remove';Why='Sports news app.'}
    @{Id='Microsoft.BingFinance';Name='Money';Suggest='Remove';Why='Finance news app (discontinued by Microsoft).'}
    @{Id='Microsoft.BingTravel';Name='Travel';Suggest='Remove';Why='Travel app (discontinued by Microsoft).'}
    @{Id='Microsoft.BingFoodAndDrink';Name='Food & Drink';Suggest='Remove';Why='Recipes app (discontinued by Microsoft).'}
    @{Id='Microsoft.BingHealthAndFitness';Name='Health & Fitness';Suggest='Remove';Why='Health app (discontinued by Microsoft).'}
    @{Id='Clipchamp.Clipchamp';Name='Clipchamp';Suggest='Remove';Why='Online video editor that comes preinstalled. Keep it only if you edit videos with it.'}
    @{Id='Microsoft.MicrosoftSolitaireCollection';Name='Solitaire Collection';Suggest='Remove';Why='Card games with ads.'}
    @{Id='Microsoft.MicrosoftOfficeHub';Name='Microsoft 365 (Office) hub';Suggest='Remove';Why='Launcher that advertises Microsoft 365. Removing it does not remove Word, Excel or other Office apps.'}
    @{Id='Microsoft.Getstarted';Name='Tips';Suggest='Remove';Why='Windows tips app.'}
    @{Id='Microsoft.WindowsFeedbackHub';Name='Feedback Hub';Suggest='Remove';Why='Sends feedback to Microsoft. Only useful if you report Windows problems.'}
    @{Id='Microsoft.People';Name='People';Suggest='Remove';Why='Old contacts app.'}
    @{Id='Microsoft.SkypeApp';Name='Skype';Suggest='Remove';Why='Skype was shut down by Microsoft in 2025.'}
    @{Id='Microsoft.MixedReality.Portal';Name='Mixed Reality Portal';Suggest='Remove';Why='Only for Windows Mixed Reality headsets (discontinued).'}
    @{Id='Microsoft.549981C3F5F10';Name='Cortana';Suggest='Remove';Why='Cortana was retired by Microsoft.'}
    @{Id='Microsoft.Windows.DevHome';Name='Dev Home';Suggest='Remove';Why='Developer dashboard (retired by Microsoft).'}
    @{Id='MicrosoftTeams';Name='Teams (personal)';Suggest='Remove';Why='Personal Teams chat. Work or school Teams is a separate app and is not touched.'}
    @{Id='MSTeams';Name='Teams';Suggest='Your call';Why='Microsoft Teams. Keep it if you use Teams for work or school.'}
    @{Id='Microsoft.MicrosoftJournal';Name='Journal';Suggest='Remove';Why='Pen note-taking app.'}
    @{Id='Microsoft.PowerAutomateDesktop';Name='Power Automate';Suggest='Your call';Why='Automation tool. Keep it if you build automations.'}
    @{Id='Microsoft.Todos';Name='Microsoft To Do';Suggest='Your call';Why='To-do list app.'}
    @{Id='Microsoft.WindowsMaps';Name='Maps';Suggest='Your call';Why='Maps app (Microsoft is retiring it).'}
    @{Id='Microsoft.ZuneVideo';Name='Films & TV';Suggest='Your call';Why='Video store/player. Media Player still plays your videos.'}
    @{Id='Microsoft.Copilot';Name='Copilot';Suggest='Your call';Why='Microsoft''s AI assistant app.'}
    @{Id='Microsoft.OutlookForWindows';Name='Outlook (new)';Suggest='Your call';Why='New Outlook mail app. Keep it if you read mail in it.'}
    @{Id='microsoft.windowscommunicationsapps';Name='Mail and Calendar (old)';Suggest='Remove';Why='Old Mail and Calendar, retired by Microsoft in favour of the new Outlook.'}
    @{Id='Microsoft.GamingApp';Name='Xbox';Suggest='Your call';Why='Xbox app (Game Pass, PC game store). Keep it if you play Game Pass or Xbox PC games.'}
    @{Id='Microsoft.XboxGamingOverlay';Name='Game Bar';Suggest='Your call';Why='Win+G overlay for recording and performance stats. Keep it if you record games.'}
    @{Id='Microsoft.YourPhone';Name='Phone Link';Suggest='Your call';Why='Connects an Android phone or iPhone to the PC.'}
    @{Id='Microsoft.MicrosoftStickyNotes';Name='Sticky Notes';Suggest='Your call';Why='Desktop notes.'}
    @{Id='MicrosoftCorporationII.QuickAssist';Name='Quick Assist';Suggest='Your call';Why='Remote help tool. Scammers often ask people to open it; keep it only if you use it with someone you trust.'}
    @{Id='Microsoft.WindowsSoundRecorder';Name='Sound Recorder';Suggest='Your call';Why='Voice recorder.'}
    @{Id='MicrosoftCorporationII.MicrosoftFamily';Name='Microsoft Family';Suggest='Your call';Why='Parental controls app.'}
    @{Id='*CandyCrush*';Name='Candy Crush';Suggest='Remove';Why='Promoted game installed by Windows.'}
    @{Id='*BubbleWitch*';Name='Bubble Witch';Suggest='Remove';Why='Promoted game installed by Windows.'}
    @{Id='*MarchofEmpires*';Name='March of Empires';Suggest='Remove';Why='Promoted game installed by Windows.'}
    @{Id='*Disney*';Name='Disney+';Suggest='Your call';Why='Promoted app. Keep it if you watch Disney+ in it.'}
    @{Id='*TikTok*';Name='TikTok';Suggest='Your call';Why='Promoted app.'}
    @{Id='*Instagram*';Name='Instagram';Suggest='Your call';Why='Promoted app.'}
    @{Id='*Facebook*';Name='Facebook';Suggest='Your call';Why='Promoted app.'}
    @{Id='*Twitter*';Name='Twitter / X';Suggest='Your call';Why='Promoted app.'}
    @{Id='*LinkedInforWindows*';Name='LinkedIn';Suggest='Your call';Why='Promoted app.'}
    @{Id='*Duolingo*';Name='Duolingo';Suggest='Your call';Why='Promoted app.'}
    @{Id='*AmazonPrimeVideo*';Name='Prime Video';Suggest='Your call';Why='Promoted app.'}
    @{Id='*king.com*';Name='King games';Suggest='Remove';Why='Promoted game installed by Windows.'}
)

# Settings. Scope 'User' = HKCU, no administrator. 'Machine' = HKLM policy, needs administrator.
# Each value: Path (under the hive), Name, Value (DWORD). 'Off' state = these values.
$script:YumBloatTweaks=@(
    @{Id='StartSuggestions';Name='Suggested apps and promotions in Start';Scope='User';Suggest='Recommended';When='Next time you open Start';Why='Stops "suggested" apps and promotions in Start and the tips in its Recommended section.';Values=@(
        @{Path='Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager';Name='SystemPaneSuggestionsEnabled';Value=0}
        @{Path='Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager';Name='SubscribedContent-338388Enabled';Value=0}
        @{Path='Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced';Name='Start_IrisRecommendations';Value=0})}
    @{Id='SilentAppInstalls';Name='Windows installing promoted apps by itself';Scope='User';Suggest='Recommended';When='From now on';Why='Stops Windows from quietly installing promoted apps and games (Candy Crush and the like) for you.';Values=@(
        @{Path='Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager';Name='SilentInstalledAppsEnabled';Value=0}
        @{Path='Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager';Name='PreInstalledAppsEnabled';Value=0}
        @{Path='Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager';Name='OemPreInstalledAppsEnabled';Value=0})}
    @{Id='TipsNotifications';Name='Tips, "welcome" and "finish setting up" nags';Scope='User';Suggest='Recommended';When='From now on';Why='Stops Windows tip notifications, the "welcome experience" after updates and the "let''s finish setting up your device" screen.';Values=@(
        @{Path='Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager';Name='SubscribedContent-338389Enabled';Value=0}
        @{Path='Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager';Name='SoftLandingEnabled';Value=0}
        @{Path='Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager';Name='SubscribedContent-310093Enabled';Value=0}
        @{Path='Software\Microsoft\Windows\CurrentVersion\UserProfileEngagement';Name='ScoobeSystemSettingEnabled';Value=0})}
    @{Id='SettingsAds';Name='Suggestions inside the Settings app';Scope='User';Suggest='Recommended';When='Next time you open Settings';Why='Stops suggested content and promotions shown in Settings.';Values=@(
        @{Path='Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager';Name='SubscribedContent-353694Enabled';Value=0}
        @{Path='Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager';Name='SubscribedContent-353696Enabled';Value=0})}
    @{Id='LockScreenAds';Name='Tips and ads on the lock screen';Scope='User';Suggest='Recommended';When='Next time the screen locks';Why='Stops "fun facts, tips and more" and promotions on the lock screen. Your lock-screen picture stays.';Values=@(
        @{Path='Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager';Name='RotatingLockScreenOverlayEnabled';Value=0}
        @{Path='Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager';Name='SubscribedContent-338387Enabled';Value=0})}
    @{Id='ExplorerAds';Name='Promotions in File Explorer';Scope='User';Suggest='Recommended';When='Next time File Explorer opens';Why='Stops OneDrive / Microsoft 365 promotions shown in File Explorer.';Values=@(
        @{Path='Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced';Name='ShowSyncProviderNotifications';Value=0})}
    @{Id='AdvertisingId';Name='Advertising ID and tailored experiences';Scope='User';Suggest='Recommended';When='From now on';Why='Apps can no longer use an advertising ID to show you personalised ads, and Microsoft does not use diagnostic data to tailor tips and ads for you.';Values=@(
        @{Path='Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo';Name='Enabled';Value=0}
        @{Path='Software\Microsoft\Windows\CurrentVersion\Privacy';Name='TailoredExperiencesWithDiagnosticDataEnabled';Value=0})}
    @{Id='BingInSearch';Name='Bing web results in Start search';Scope='User';Suggest='Your call';When='After you sign out and back in';Why='Start search shows only your apps, files and settings instead of Bing web results. Searching the web still works in your browser.';Values=@(
        @{Path='Software\Microsoft\Windows\CurrentVersion\Search';Name='BingSearchEnabled';Value=0}
        @{Path='Software\Policies\Microsoft\Windows\Explorer';Name='DisableSearchBoxSuggestions';Value=1})}
    @{Id='Copilot';Name='Copilot button and built-in Copilot';Scope='User';Suggest='Your call';When='After you sign out and back in';Why='Hides the Copilot taskbar button and turns off the built-in Windows Copilot. The separate Copilot app (if installed) is in the apps list above.';Values=@(
        @{Path='Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced';Name='ShowCopilotButton';Value=0}
        @{Path='Software\Policies\Microsoft\Windows\WindowsCopilot';Name='TurnOffWindowsCopilot';Value=1})}
    @{Id='Recall';Name='Recall snapshots';Scope='User';Suggest='Recommended';When='After you sign out and back in';Why='Stops Recall from saving snapshots of your screen (only on Copilot+ PCs; harmless elsewhere).';Values=@(
        @{Path='Software\Policies\Microsoft\Windows\WindowsAI';Name='DisableAIDataAnalysis';Value=1})}
    @{Id='Widgets';Name='Widgets and the news feed';Scope='Machine';Suggest='Your call';When='After you sign out and back in';Why='Turns off the Widgets board and its news feed for this PC (a Windows policy, needs administrator). Its background process stops using RAM.';Values=@(
        @{Path='SOFTWARE\Policies\Microsoft\Dsh';Name='AllowNewsAndInterests';Value=0})}
    @{Id='Telemetry';Name='Send only required diagnostic data';Scope='Machine';Suggest='Your call';When='From now on';Why='Limits diagnostic data sent to Microsoft to the "required" level (a Windows policy, needs administrator). Settings may then say "some settings are managed by your organization" - that is this policy.';Values=@(
        @{Path='SOFTWARE\Policies\Microsoft\Windows\DataCollection';Name='AllowTelemetry';Value=1})}
)

function Get-YumBloatUndoPath { return (Join-Path ([string]$script:Yum.ConfigDirectory) 'windows-bloat-undo.json') }
function Get-YumBloatHistoryPath { return (Join-Path ([string]$script:Yum.ConfigDirectory) 'windows-bloat-history.json') }

function Read-YumBloatJson {
    param([string]$Path)
    try{ if(Test-Path -LiteralPath $Path){ $o=Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json; return $o } }catch{}   # PS 5.1: assign first
    return $null
}

function Test-YumBloatNeverRemove {
    param([string]$Name)
    foreach($n in $script:YumBloatNever){ if($Name -like $n){return $true} }
    return $false
}

function Find-YumBloatCatalogEntry {
    param([string]$Name,[object[]]$Catalog=$script:YumBloatApps)
    if([string]::IsNullOrWhiteSpace($Name) -or (Test-YumBloatNeverRemove $Name)){return $null}
    foreach($e in $Catalog){ if($Name -like [string]$e.Id){return $e} }
    return $null
}

function ConvertTo-YumBloatAppRows {
    # Packages (Get-AppxPackage objects, or test objects with the same properties) -> rows for known bloat only.
    param([object[]]$Packages,[object[]]$Provisioned=@(),[object[]]$Catalog=$script:YumBloatApps)
    $rows=New-Object System.Collections.Generic.List[object]
    $seen=@{}
    foreach($p in @($Packages)){
        try{
            $name=[string]$p.Name
            if($seen.ContainsKey($name)){continue}
            if([bool]$p.IsFramework -or [bool]$p.NonRemovable){continue}
            $e=Find-YumBloatCatalogEntry -Name $name -Catalog $Catalog; if($null -eq $e){continue}
            $prov=@($Provisioned | Where-Object { [string]$_.DisplayName -eq $name })
            $seen[$name]=$true
            [void]$rows.Add([pscustomobject]@{Kind='App';Key=('app|'+$name);Name=[string]$e.Name;PackageName=$name;PackageFullName=[string]$p.PackageFullName;PackageFamilyName=[string]$p.PackageFamilyName;Version=[string]$p.Version;Publisher=$(if([string]$p.Publisher -match 'CN=([^,]+)'){$Matches[1]}else{[string]$p.Publisher});Suggest=[string]$e.Suggest;Why=[string]$e.Why;Provisioned=($prov.Count -gt 0);ProvisionedName=$(if($prov.Count){[string]$prov[0].PackageName}else{''});State='Installed'})
        }catch{}
    }
    return @($rows | Sort-Object @{Expression={if($_.Suggest -eq 'Remove'){0}else{1}}},Name)
}

function Get-YumWindowsBloatApps {
    # Real scan. Provisioned packages are only readable as administrator.
    $pk=@();try{ $pk=@(Get-AppxPackage -ErrorAction Stop) }catch{ try{Write-YumLog ('Windows bloat: app list unavailable: {0}' -f $_.Exception.Message)}catch{} }
    $prov=@();try{ if(Test-YumIsElevated){ $prov=@(Get-AppxProvisionedPackage -Online -ErrorAction Stop) } }catch{}
    return @(ConvertTo-YumBloatAppRows -Packages $pk -Provisioned $prov)
}

function Add-YumBloatHistory {
    param([object]$Entry)
    try{
        $h=New-Object System.Collections.Generic.List[object]
        $old=Read-YumBloatJson (Get-YumBloatHistoryPath); foreach($x in @($old)){ if($null -ne $x){[void]$h.Add($x)} }
        [void]$h.Add($Entry)
        ConvertTo-Json -InputObject @($h.ToArray()) -Depth 4 | Set-Content -LiteralPath (Get-YumBloatHistoryPath) -Encoding UTF8
    }catch{ try{Write-YumLogException -Context 'Windows bloat history save failed' -Exception $_.Exception}catch{} }
}

function Get-YumBloatHistory { $h=Read-YumBloatJson (Get-YumBloatHistoryPath); return @($h | Where-Object { $null -ne $_ }) }

function Remove-YumWindowsBloatApp {
    # Removes one catalog app for the current user; with -ForNewUsers (administrator) also de-provisions it.
    # -Remover / -Deprovisioner exist for tests (they replace the real Appx calls).
    param([Parameter(Mandatory)]$App,[switch]$ForNewUsers,[scriptblock]$Remover,[scriptblock]$Deprovisioner)
    try{
        if($null -eq (Find-YumBloatCatalogEntry -Name ([string]$App.PackageName))){ return [pscustomobject]@{Success=$false;Reason='Not on YUMRAM''s list of removable Windows apps.'} }
        if($null -eq $Remover){ $Remover={ param($full) Remove-AppxPackage -Package $full -ErrorAction Stop } }
        if($null -eq $Deprovisioner){ $Deprovisioner={ param($prov) Remove-AppxProvisionedPackage -Online -PackageName $prov -ErrorAction Stop | Out-Null } }
        & $Remover ([string]$App.PackageFullName)
        $dep=$false;$depNote=''
        if($ForNewUsers -and [string]$App.ProvisionedName){
            if(Test-YumIsElevated){ try{ & $Deprovisioner ([string]$App.ProvisionedName); $dep=$true }catch{ $depNote=(' It is still installed for new user accounts: {0}' -f $_.Exception.Message) } }
            else{ $depNote=' New user accounts will still get it (that part needs administrator).' }
        }
        Add-YumBloatHistory -Entry ([pscustomobject]@{Time=(Get-Date).ToString('s');Name=[string]$App.Name;PackageName=[string]$App.PackageName;PackageFamilyName=[string]$App.PackageFamilyName;Version=[string]$App.Version;ForNewUsers=$dep})
        try{Write-YumLog ('Windows bloat: removed {0} ({1}){2}.' -f $App.Name,$App.PackageName,$(if($dep){', also for new users'}else{''}))}catch{}
        return [pscustomobject]@{Success=$true;Reason=('{0} removed{1}. Get it back any time from the Microsoft Store.{2}' -f $App.Name,$(if($dep){' (also for new user accounts)'}else{''}),$depNote)}
    }catch{
        try{Write-YumLogException -Context ('Windows bloat: removing {0} failed' -f $App.PackageName) -Exception $_.Exception}catch{}
        return [pscustomobject]@{Success=$false;Reason=('{0} could not be removed: {1}' -f $App.Name,$_.Exception.Message)}
    }
}

function Open-YumBloatStorePage {
    param([string]$PackageFamilyName)
    if([string]::IsNullOrWhiteSpace($PackageFamilyName)){return}
    Start-Process ('ms-windows-store://pdp/?PFN={0}' -f $PackageFamilyName)
}

# ---------------------------------------------------------------- settings
function Get-YumBloatRegistryKey {
    param([string]$Scope,[string]$Path,[switch]$Write)
    $hive=if($Scope -eq 'Machine'){[Microsoft.Win32.Registry]::LocalMachine}else{[Microsoft.Win32.Registry]::CurrentUser}
    if($Write){ return $hive.CreateSubKey($Path) }
    return $hive.OpenSubKey($Path)
}

function Get-YumBloatTweakState {
    # 'Done' = every value is at YUMRAM's setting; 'Windows default' = none is; 'Partly' otherwise.
    param([Parameter(Mandatory)]$Tweak)
    $hit=0;$n=0
    foreach($v in @($Tweak.Values)){
        $n++
        try{ $k=Get-YumBloatRegistryKey -Scope $Tweak.Scope -Path $v.Path; if($null -ne $k){ try{ $cur=$k.GetValue($v.Name,$null); if($null -ne $cur -and [int]$cur -eq [int]$v.Value){$hit++} }finally{$k.Close()} } }catch{}
    }
    if($n -gt 0 -and $hit -eq $n){return 'Done'}
    if($hit -eq 0){return 'Windows default'}
    return 'Partly'
}

function Set-YumBloatTweak {
    # Apply: save each original value (or "did not exist") once, then write YUMRAM's value.
    # Undo: put every saved original back exactly (delete values that did not exist before).
    param([Parameter(Mandatory)]$Tweak,[switch]$Undo)
    if($Tweak.Scope -eq 'Machine' -and -not (Test-YumIsElevated)){ return [pscustomobject]@{Success=$false;Reason=('"{0}" is a Windows policy for the whole PC; run YUMRAM as administrator to change it.' -f $Tweak.Name)} }
    try{
        $undoAll=@{}
        $saved=Read-YumBloatJson (Get-YumBloatUndoPath)
        if($null -ne $saved){ foreach($p in $saved.PSObject.Properties){ $undoAll[$p.Name]=@($p.Value) } }
        if(-not $Undo){
            if(-not $undoAll.ContainsKey($Tweak.Id)){
                $orig=New-Object System.Collections.Generic.List[object]
                foreach($v in @($Tweak.Values)){
                    $existed=$false;$val=$null;$kind=''
                    $k=Get-YumBloatRegistryKey -Scope $Tweak.Scope -Path $v.Path
                    if($null -ne $k){ try{ $val=$k.GetValue($v.Name,$null,'DoNotExpandEnvironmentNames'); if($null -ne $val){$existed=$true;$kind=[string]$k.GetValueKind($v.Name)} }finally{$k.Close()} }
                    [void]$orig.Add([pscustomobject]@{Path=$v.Path;Name=$v.Name;Existed=$existed;Kind=$kind;Value=$val})
                }
                $undoAll[$Tweak.Id]=@($orig.ToArray())
                ConvertTo-Json -InputObject $undoAll -Depth 5 | Set-Content -LiteralPath (Get-YumBloatUndoPath) -Encoding UTF8
            }
            foreach($v in @($Tweak.Values)){ $k=Get-YumBloatRegistryKey -Scope $Tweak.Scope -Path $v.Path -Write; try{ $k.SetValue($v.Name,[int]$v.Value,[Microsoft.Win32.RegistryValueKind]::DWord) }finally{$k.Close()} }
            try{Write-YumLog ('Windows bloat: turned off "{0}" (originals saved for undo).' -f $Tweak.Name)}catch{}
            return [pscustomobject]@{Success=$true;Reason=('Done: {0}. Takes effect: {1}.' -f $Tweak.Name,$Tweak.When)}
        } else {
            if(-not $undoAll.ContainsKey($Tweak.Id)){ return [pscustomobject]@{Success=$false;Reason=('Nothing to undo for "{0}": YUMRAM did not change it.' -f $Tweak.Name)} }
            foreach($o in @($undoAll[$Tweak.Id])){
                $k=Get-YumBloatRegistryKey -Scope $Tweak.Scope -Path ([string]$o.Path) -Write
                try{
                    if([bool]$o.Existed){
                        $kind=[Microsoft.Win32.RegistryValueKind]::DWord;try{if([string]$o.Kind){$kind=[Microsoft.Win32.RegistryValueKind][string]$o.Kind}}catch{}
                        $val=$o.Value;if($kind -eq [Microsoft.Win32.RegistryValueKind]::DWord){$val=[int]$val}elseif($kind -eq [Microsoft.Win32.RegistryValueKind]::QWord){$val=[int64]$val}
                        $k.SetValue([string]$o.Name,$val,$kind)
                    } else { $k.DeleteValue([string]$o.Name,$false) }
                }finally{$k.Close()}
            }
            $undoAll.Remove($Tweak.Id)
            ConvertTo-Json -InputObject $undoAll -Depth 5 | Set-Content -LiteralPath (Get-YumBloatUndoPath) -Encoding UTF8
            try{Write-YumLog ('Windows bloat: undid "{0}" (original values restored).' -f $Tweak.Name)}catch{}
            return [pscustomobject]@{Success=$true;Reason=('Undone: {0} is back to how it was. Takes effect: {1}.' -f $Tweak.Name,$Tweak.When)}
        }
    }catch{
        try{Write-YumLogException -Context ('Windows bloat setting "{0}" failed' -f $Tweak.Name) -Exception $_.Exception}catch{}
        return [pscustomobject]@{Success=$false;Reason=('"{0}" could not be changed: {1}' -f $Tweak.Name,$_.Exception.Message)}
    }
}

function Test-YumBloatTweakUndoable {
    param([Parameter(Mandatory)]$Tweak)
    $saved=Read-YumBloatJson (Get-YumBloatUndoPath)
    return ($null -ne $saved -and $null -ne $saved.PSObject.Properties[[string]$Tweak.Id])
}

function Get-YumWindowsBloatTweakRows {
    param([object[]]$Tweaks=$script:YumBloatTweaks)
    foreach($t in $Tweaks){
        $state=Get-YumBloatTweakState -Tweak $t
        [pscustomobject]@{Kind='Setting';Key=('set|'+$t.Id);Tweak=$t;Name=[string]$t.Name;Suggest=[string]$t.Suggest;Why=[string]$t.Why;When=[string]$t.When;Scope=[string]$t.Scope;State=$(if($state -eq 'Done'){'Off'}elseif($state -eq 'Partly'){'Partly off'}else{'On'});Undoable=(Test-YumBloatTweakUndoable -Tweak $t)}
    }
}
