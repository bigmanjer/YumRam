#requires -Version 5.1
# 5.7 behaviour: Startup apps use Task Manager's StartupApproved flag (never delete), protect security
# software, parse Run commands, and the page is hosted in the sidebar.
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'App\Bootstrap.ps1')
Initialize-YumConfig
$script:Yum.Config.Logging=$false
function Assert-That([bool]$Condition,[string]$Message){if(-not $Condition){throw $Message}}

# 1. Command-line parsing.
Assert-That ((Get-YumStartupExePath -Command '"C:\Program Files\LGHUB\a b.exe" --minimized') -eq 'C:\Program Files\LGHUB\a b.exe') 'Quoted path.'
Assert-That ((Get-YumStartupExePath -Command 'C:\Riot Games\Riot Client\RiotClientServices.exe --launch-background-mode') -eq 'C:\Riot Games\Riot Client\RiotClientServices.exe') 'Unquoted path with spaces.'
Assert-That ((Get-YumStartupExePath -Command '%windir%\system32\x.exe /q') -like '*\system32\x.exe') 'Environment variables expand.'

# 2. Advice.
Assert-That ((Get-YumStartupSuggestion -Name 'SecurityHealth' -ExePath 'C:\Windows\system32\SecurityHealthSystray.exe' -Publisher 'Microsoft' -Kind 'Windows').Locked) 'Windows Security must be locked on.'
Assert-That ((Get-YumStartupSuggestion -Name 'Riot Vanguard' -ExePath 'C:\Program Files\Riot Vanguard\vgtray.exe' -Publisher 'Riot' -Kind 'App').Level -eq 'Keep') 'Anti-cheat must be Keep.'
Assert-That ((Get-YumStartupSuggestion -Name 'Steam' -ExePath 'C:\Steam\steam.exe' -Publisher 'Valve' -Kind 'App').Level -eq 'Turn off') 'Launchers are safe to turn off.'
Assert-That ((Get-YumStartupSuggestion -Name 'RtkAudUService' -ExePath 'C:\x\RtkAudUService64.exe' -Publisher 'Realtek' -Kind 'App').Level -eq 'Careful') 'Hardware helpers are Careful.'
$locked=[pscustomobject]@{Name='SecurityHealth';Friendly='Windows Security';Locked=$true;NeedsAdmin=$false;HiveName='HKCU';ApprovedKey='Run'}
Assert-That (-not (Set-YumStartupAppEnabled -App $locked -Enabled $false).Success) 'Locked apps must refuse to be turned off.'

# 3. Round trip on a throw-away value: same bytes as Task Manager, read back correctly, cleaned up.
$name='YUMRAM-Test-'+[guid]::NewGuid().ToString('N')
$app=[pscustomobject]@{Name=$name;Friendly='Test';Locked=$false;NeedsAdmin=$false;HiveName='HKCU';ApprovedKey='Run'}
try{
    Assert-That (Set-YumStartupAppEnabled -App $app -Enabled $false).Success 'Turning off failed.'
    $k=[Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run');$v=$k.GetValue($name);$k.Close()
    Assert-That ($v.Length -eq 12 -and $v[0] -eq 3 -and [BitConverter]::ToInt64($v,4) -gt 0) 'Off must be 03 00 00 00 + FILETIME.'
    $st=Get-YumStartupApprovedState -Hive ([Microsoft.Win32.Registry]::CurrentUser) -SubKey 'Run' -Name $name
    Assert-That (-not $st.Enabled -and $null -ne $st.DisabledAt -and ((Get-Date)-$st.DisabledAt).TotalMinutes -lt 5) 'Off state / date not read back.'
    Assert-That (Set-YumStartupAppEnabled -App $app -Enabled $true).Success 'Turning on failed.'
    $k=[Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run');$v=$k.GetValue($name);$k.Close()
    Assert-That ($v[0] -eq 2 -and (@($v[1..11]|Where-Object{$_ -ne 0}).Count -eq 0)) 'On must be 02 followed by zeros.'
} finally {
    $k=[Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run',$true);if($k){$k.DeleteValue($name,$false);$k.Close()}
}
Assert-That ((Get-YumStartupApprovedState -Hive ([Microsoft.Win32.Registry]::CurrentUser) -SubKey 'Run' -Name ('missing-'+$name)).Enabled) 'No flag means on (Windows default).'

# 4. Inventory runs and the page is in the shell.
$apps=@(Get-YumStartupApps)
foreach($a in $apps){Assert-That ($null -ne $a.PSObject.Properties['Enabled'] -and $null -ne $a.PSObject.Properties['Advice']) 'Inventory rows incomplete.'}
$shell=Get-Content -Raw (Join-Path $root 'UI\Shell.ps1')
Assert-That ($shell -match "'Startup'\{Show-YumStartupApps\}") 'Startup page must be reachable from the sidebar.'
Assert-That ((Get-Content -Raw (Join-Path $root 'UI\StartupPage.ps1')) -match "Enter-YumPage -Key 'Startup'") 'Startup page must be hosted.'
Write-Host ('Release 5.7 startup test passed ({0} startup apps on this PC).' -f $apps.Count)
