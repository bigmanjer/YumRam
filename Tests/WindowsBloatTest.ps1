#requires -Version 5.1
# 5.15 Windows bloat: catalog safety, package matching, removal recording (with a stand-in remover - no real
# app is removed), and exact apply/undo of settings on a throwaway test registry key (not a real Windows setting).
$ErrorActionPreference='Stop'
$repoRoot=Split-Path -Parent $PSScriptRoot
. (Join-Path $repoRoot 'App\Bootstrap.ps1')
Initialize-YumConfig
$script:Yum.Config.Logging=$false
function Assert-That([bool]$Condition,[string]$Message){if(-not $Condition){throw $Message}}
$tmp=Join-Path $env:TEMP ('yum-bloat-'+[guid]::NewGuid().ToString('N'));New-Item -ItemType Directory $tmp|Out-Null
$script:Yum.ConfigDirectory=$tmp;$script:Yum.ConfigFile=(Join-Path $tmp 'config.json')
$testKey='Software\YUMRAM-Test\'+[guid]::NewGuid().ToString('N')
try{
    # 1. Things YUMRAM must never offer.
    foreach($n in 'Microsoft.WindowsStore','Microsoft.MicrosoftEdge.Stable','Microsoft.Windows.Photos','Microsoft.WindowsCalculator','Microsoft.WindowsNotepad','Microsoft.Paint','Microsoft.WindowsTerminal','Microsoft.XboxIdentityProvider','Microsoft.DesktopAppInstaller','Microsoft.VCLibs.140.00','Microsoft.UI.Xaml.2.8','Microsoft.NET.Native.Runtime.2.2','Microsoft.SecHealthUI','Microsoft.ZuneMusic'){
        Assert-That ($null -eq (Find-YumBloatCatalogEntry -Name $n)) ("{0} must never be offered for removal." -f $n)
    }
    Assert-That ($null -ne (Find-YumBloatCatalogEntry -Name 'Microsoft.BingNews')) 'Microsoft News is on the list.'
    Assert-That ($null -ne (Find-YumBloatCatalogEntry -Name 'king.com.CandyCrushSaga')) 'Candy Crush (wildcard) is on the list.'
    foreach($e in $script:YumBloatApps){ Assert-That ([string]$e.Suggest -in @('Remove','Your call')) ("Bad advice for {0}" -f $e.Id); Assert-That (-not [string]::IsNullOrWhiteSpace([string]$e.Why)) ("No explanation for {0}" -f $e.Id) }

    # 2. Matching: only catalog apps, never frameworks / non-removable, provisioned flag carried.
    $pk=@(
        [pscustomobject]@{Name='Microsoft.BingNews';PackageFullName='Microsoft.BingNews_1.0_x64__8wekyb3d8bbwe';PackageFamilyName='Microsoft.BingNews_8wekyb3d8bbwe';Version='1.0';Publisher='CN=Microsoft Corporation, O=Microsoft';IsFramework=$false;NonRemovable=$false}
        [pscustomobject]@{Name='Microsoft.WindowsStore';PackageFullName='Microsoft.WindowsStore_1';PackageFamilyName='Microsoft.WindowsStore_8wekyb3d8bbwe';Version='1';Publisher='CN=Microsoft';IsFramework=$false;NonRemovable=$false}
        [pscustomobject]@{Name='Microsoft.GamingApp';PackageFullName='Microsoft.GamingApp_1';PackageFamilyName='Microsoft.GamingApp_8wekyb3d8bbwe';Version='1';Publisher='CN=Microsoft';IsFramework=$false;NonRemovable=$true}
        [pscustomobject]@{Name='Microsoft.BingWeather';PackageFullName='Microsoft.BingWeather_1';PackageFamilyName='Microsoft.BingWeather_8wekyb3d8bbwe';Version='1';Publisher='CN=Microsoft';IsFramework=$true;NonRemovable=$false}
        [pscustomobject]@{Name='Contoso.SomeApp';PackageFullName='Contoso_1';PackageFamilyName='Contoso_x';Version='1';Publisher='CN=Contoso';IsFramework=$false;NonRemovable=$false})
    $prov=@([pscustomobject]@{DisplayName='Microsoft.BingNews';PackageName='Microsoft.BingNews_1.0_neutral_~_8wekyb3d8bbwe'})
    $rows=@(ConvertTo-YumBloatAppRows -Packages $pk -Provisioned $prov)
    Assert-That ($rows.Count -eq 1 -and $rows[0].PackageName -eq 'Microsoft.BingNews') ('Only Microsoft News should match, got: {0}' -f (($rows|ForEach-Object PackageName) -join ', '))
    Assert-That ($rows[0].Provisioned -and $rows[0].ProvisionedName -like 'Microsoft.BingNews_*' -and $rows[0].Publisher -eq 'Microsoft Corporation') 'Provisioned name and publisher are carried.'

    # 3. Removal with stand-in remover: recorded in history; refused for a non-catalog app without calling it.
    $script:called=@()
    $r=Remove-YumWindowsBloatApp -App $rows[0] -Remover { param($f) $script:called+=$f }
    Assert-That ($r.Success -and $script:called.Count -eq 1 -and $script:called[0] -eq $rows[0].PackageFullName) ('Removal should call the remover once: {0}' -f $r.Reason)
    $h=@(Get-YumBloatHistory)
    Assert-That ($h.Count -eq 1 -and $h[0].PackageFamilyName -eq 'Microsoft.BingNews_8wekyb3d8bbwe') 'Removal is recorded with its Store family name (for Get it back).'
    $store=[pscustomobject]@{Name='Store';PackageName='Microsoft.WindowsStore';PackageFullName='Microsoft.WindowsStore_1'}
    $script:called=@()
    $r2=Remove-YumWindowsBloatApp -App $store -Remover { param($f) $script:called+=$f }
    Assert-That (-not $r2.Success -and $script:called.Count -eq 0) 'A non-catalog app (Store) is refused and the remover is never called.'
    $r3=Remove-YumWindowsBloatApp -App $rows[0] -Remover { param($f) throw 'Access is denied.' }
    Assert-That (-not $r3.Success -and $r3.Reason -match 'Access is denied') 'A failing removal is reported, not hidden.'
    Assert-That (@(Get-YumBloatHistory).Count -eq 1) 'A failed removal is not recorded as removed.'

    # 4. Settings: exact apply/undo on a test key (existing DWORD, existing string, missing value).
    $k=[Microsoft.Win32.Registry]::CurrentUser.CreateSubKey($testKey)
    $k.SetValue('ExistingDword',7,[Microsoft.Win32.RegistryValueKind]::DWord)
    $k.SetValue('ExistingString','abc',[Microsoft.Win32.RegistryValueKind]::String)
    $k.SetValue('ExistingBinary',[byte[]](1,2,3),[Microsoft.Win32.RegistryValueKind]::Binary)
    $k.Close()
    $tw=@{Id='TestTweak';Name='Test tweak';Scope='User';Suggest='Recommended';When='now';Why='test';Values=@(
        @{Path=$testKey;Name='ExistingDword';Value=0},@{Path=$testKey;Name='ExistingString';Value=0},@{Path=$testKey;Name='ExistingBinary';Value=0},@{Path=$testKey;Name='Missing';Value=1})}
    Assert-That ((Get-YumBloatTweakState -Tweak $tw) -eq 'Windows default') 'Starts at Windows default.'
    $a=Set-YumBloatTweak -Tweak $tw
    Assert-That $a.Success ('Apply failed: {0}' -f $a.Reason)
    Assert-That ((Get-YumBloatTweakState -Tweak $tw) -eq 'Done') 'All values set after apply.'
    Assert-That (Test-YumBloatTweakUndoable -Tweak $tw) 'Originals saved for undo.'
    # Applying twice must not overwrite the saved originals with YUMRAM's own values.
    [void](Set-YumBloatTweak -Tweak $tw)
    $u=Set-YumBloatTweak -Tweak $tw -Undo
    Assert-That $u.Success ('Undo failed: {0}' -f $u.Reason)
    $k=[Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($testKey)
    try{
        Assert-That ([int]$k.GetValue('ExistingDword') -eq 7 -and $k.GetValueKind('ExistingDword') -eq 'DWord') 'Existing DWORD restored exactly (value and type).'
        Assert-That ([string]$k.GetValue('ExistingString') -eq 'abc' -and $k.GetValueKind('ExistingString') -eq 'String') 'Existing string restored exactly (value and type).'
        Assert-That ($null -eq $k.GetValue('Missing',$null)) 'A value that did not exist before is deleted again.'
        Assert-That ($k.GetValueKind('ExistingBinary') -eq 'Binary' -and (($k.GetValue('ExistingBinary')) -join ',') -eq '1,2,3') 'A binary original is restored exactly (review fix).'
    }finally{$k.Close()}
    Assert-That (-not (Test-YumBloatTweakUndoable -Tweak $tw)) 'Undo record cleared after undo.'
    Assert-That (-not (Set-YumBloatTweak -Tweak $tw -Undo).Success) 'Undo with nothing saved is refused.'

    # 5. Whole-PC settings need administrator.
    if(-not (Test-YumIsElevated)){
        $m=Set-YumBloatTweak -Tweak @{Id='M';Name='Machine test';Scope='Machine';When='now';Values=@(@{Path='SOFTWARE\YUMRAM-Test';Name='X';Value=1})}
        Assert-That (-not $m.Success -and $m.Reason -match 'administrator') 'Machine settings are refused without administrator.'
    }

    # 6. Real settings catalog sanity.
    foreach($t in $script:YumBloatTweaks){
        Assert-That ([string]$t.Scope -in @('User','Machine')) ("Bad scope {0}" -f $t.Id)
        foreach($v in @($t.Values)){
            Assert-That ([string]$v.Path -match '^(Software|SOFTWARE)\\') ("Bad path in {0}" -f $t.Id)
            if($t.Scope -eq 'Machine'){ Assert-That ([string]$v.Path -match '^SOFTWARE\\Policies\\') ("Machine changes must be policies: {0}" -f $t.Id) }
            Assert-That ($v.Value -is [int]) ("Value must be a DWORD int: {0}/{1}" -f $t.Id,$v.Name)
        }
    }
    Assert-That (@(Get-YumWindowsBloatTweakRows).Count -eq $script:YumBloatTweaks.Count) 'Every setting gets a row.'

    # 7. Wiring.
    $boot=[IO.File]::ReadAllText((Join-Path $repoRoot 'App\Bootstrap.ps1'))
    Assert-That ($boot -match 'Core\\WindowsBloat\.ps1' -and $boot -match 'UI\\WindowsBloatPage\.ps1') 'Modules load at startup.'
    $shell=[IO.File]::ReadAllText((Join-Path $repoRoot 'UI\Shell.ps1'))
    Assert-That ($shell -match "'WindowsBloat'\{Show-YumWindowsBloat\}" -and $shell -match "D8='WindowsBloat'") 'Page key and Ctrl+8 wired.'
    Assert-That ([IO.File]::ReadAllText((Join-Path $repoRoot 'UI\Xaml\MainWindow.xaml')) -match 'x:Name="WindowsBloat"') 'Sidebar button exists.'
}finally{
    try{ [Microsoft.Win32.Registry]::CurrentUser.DeleteSubKeyTree($testKey,$false) }catch{}
    try{ $p=[Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Software\YUMRAM-Test'); if($p -and $p.SubKeyCount -eq 0 -and $p.ValueCount -eq 0){$p.Close();[Microsoft.Win32.Registry]::CurrentUser.DeleteSubKey('Software\YUMRAM-Test',$false)}elseif($p){$p.Close()} }catch{}
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
}
Write-Host 'WindowsBloatTest passed.'
