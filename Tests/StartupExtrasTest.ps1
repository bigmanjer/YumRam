#requires -Version 5.1
# 5.15 review: Startup page also lists Store app startup tasks and third-party sign-in tasks.
# The Store part runs on a throwaway test key (not a real app); tasks are only listed, never changed.
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'App\Bootstrap.ps1')
Initialize-YumConfig
$script:Yum.Config.Logging=$false
function Assert-That([bool]$Condition,[string]$Message){if(-not $Condition){throw $Message}}
$realRoot=$script:YumStoreStartupRoot
$testRoot='Software\YUMRAM-Test\AppModel-'+[guid]::NewGuid().ToString('N')
try{
    # 1. A fake Store app with a startup task that is on (State 2), one off by the user (1), one never set (0).
    $script:YumStoreStartupRoot=$testRoot
    foreach($t in @(@('Contoso.App_abc123','ContosoStartup',2),@('Fabrikam.App_def456','FabStartup',1),@('Litware.App_ghi789','LitStartup',0))){
        $k=[Microsoft.Win32.Registry]::CurrentUser.CreateSubKey(('{0}\{1}\{2}' -f $testRoot,$t[0],$t[1])); $k.SetValue('State',[int]$t[2],[Microsoft.Win32.RegistryValueKind]::DWord); $k.Close()
    }
    $rows=@(Get-YumStoreStartupTasks)
    Assert-That ($rows.Count -eq 2) ('State 0 (never set to start) is not listed, like Task Manager; got {0} rows.' -f $rows.Count)
    $on=@($rows | Where-Object { $_.Name -eq 'Contoso.App_abc123|ContosoStartup' })[0]
    Assert-That ($null -ne $on -and $on.Enabled -and $on.ApprovedKey -eq 'StoreTask' -and -not $on.NeedsAdmin) 'Enabled Store task listed, per-user, no admin.'
    foreach($p in 'Name','Friendly','Publisher','Command','ExePath','FileExists','HiveName','ApprovedKey','Scope','Location','Enabled','DisabledAt','Running','MemoryMB','ProcessCount','Kind','Suggestion','Advice','Locked','NeedsAdmin'){ Assert-That ($null -ne $on.PSObject.Properties[$p]) ("Store row has {0} (the page needs it)." -f $p) }
    $r=Set-YumStartupAppEnabled -App $on -Enabled $false
    $k=[Microsoft.Win32.Registry]::CurrentUser.OpenSubKey(('{0}\Contoso.App_abc123\ContosoStartup' -f $testRoot)); $v=[int]$k.GetValue('State'); $k.Close()
    Assert-That ($r.Success -and $v -eq 1) ('Turning off writes State 1 (off by you), got {0}: {1}' -f $v,$r.Reason)
    $r=Set-YumStartupAppEnabled -App $on -Enabled $true
    $k=[Microsoft.Win32.Registry]::CurrentUser.OpenSubKey(('{0}\Contoso.App_abc123\ContosoStartup' -f $testRoot)); $v=[int]$k.GetValue('State'); $k.Close()
    Assert-That ($r.Success -and $v -eq 2) 'Turning on writes State 2.'
    # Policy-controlled entries are locked.
    $k=[Microsoft.Win32.Registry]::CurrentUser.CreateSubKey(('{0}\Policy.App_x\PolTask' -f $testRoot)); $k.SetValue('State',4,[Microsoft.Win32.RegistryValueKind]::DWord); $k.Close()
    $pol=@(Get-YumStoreStartupTasks | Where-Object { $_.Name -like 'Policy.App_x*' })[0]
    Assert-That ($pol.Locked -and -not (Set-YumStartupAppEnabled -App $pol -Enabled $false).Success) 'Entries set by a Windows policy are locked.'
}finally{
    $script:YumStoreStartupRoot=$realRoot
    try{ [Microsoft.Win32.Registry]::CurrentUser.DeleteSubKeyTree($testRoot,$false) }catch{}
    try{ $p=[Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Software\YUMRAM-Test'); if($p -and $p.SubKeyCount -eq 0 -and $p.ValueCount -eq 0){$p.Close();[Microsoft.Win32.Registry]::CurrentUser.DeleteSubKey('Software\YUMRAM-Test',$false)}elseif($p){$p.Close()} }catch{}
}

# 2. Sign-in tasks: listed read-only from the real Task Scheduler; never \Microsoft\, never YUMRAM's own task.
$tasks=@(Get-YumSignInTasks)
foreach($t in $tasks){
    Assert-That ($t.ApprovedKey -eq 'ScheduledTask' -and $t.Name -notlike '\Microsoft\*') ('Only third-party tasks: {0}' -f $t.Name)
    Assert-That ($t.Name -ne '\YUMRAM') 'YUMRAM''s own no-prompt task is managed in Settings, not here.'
}
$src=[IO.File]::ReadAllText((Join-Path $root 'Core\Startup.ps1'))
Assert-That ($src -match 'Disable-ScheduledTask' -and $src -notmatch 'Unregister-ScheduledTask') 'Tasks are disabled, never deleted.'
# 3. The page loads them in the background.
$page=[IO.File]::ReadAllText((Join-Path $root 'UI\StartupPage.ps1'))
Assert-That ($page -match 'Get-YumStartupApps -SkipExtras' -and $page -match 'Start-YumStartupExtras -State \$state') 'Startup page reads the slow entries off the UI thread.'
# 5.16.3: names shown never contain the Windows account's security ID (S-1-5-21-...).
foreach($t in $tasks){ $f=if($t.PSObject.Properties['Friendly']){[string]$t.Friendly}else{''}; if($f -match 'S-1-5-21-\d'){ throw ('A startup task shows an account ID: ' + $f) } }
Write-Host ('StartupExtrasTest passed ({0} sign-in tasks on this PC).' -f $tasks.Count)
