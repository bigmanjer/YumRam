#requires -Version 5.1
# 5.17.0: Uninstall programs (Core\Uninstaller.ps1). Runs in strict mode like the app. The end-to-end part installs a
# fake program in this account only (HKCU + %LOCALAPPDATA% / %APPDATA%), uninstalls it with its own uninstaller,
# finds and removes its leftovers - no real program is touched.
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$repoRoot=$root
. (Join-Path $root 'App\Bootstrap.ps1')
Initialize-YumConfig
$script:Yum.Config.Logging=$false
function Assert-That([bool]$Condition,[string]$Message){if(-not $Condition){throw $Message}}

# 1. The installed-programs list.
$sw=[Diagnostics.Stopwatch]::StartNew(); $all=@(Get-YumInstalledPrograms); $ms=$sw.ElapsedMilliseconds
Assert-That ($all.Count -ge 5) ('Installed programs are listed ({0}).' -f $all.Count)
Assert-That ($ms -lt 3000) ('The list is quick ({0} ms).' -f $ms)
foreach($p in $all){ Assert-That ([string]$p.Name -and ([string]$p.UninstallString -or [bool]$p.IsMsi)) ('Every entry can be uninstalled: {0}' -f $p.Name) }
Assert-That (@($all | Where-Object { [string]$_.Name -match '^(Security )?Update for |\(KB\d+\)' }).Count -eq 0) 'Windows updates are not listed.'
# Command lines and names.
$c=Split-YumCommandLine '"C:\Program Files\Acme App\unins000.exe" /SILENT'; Assert-That ($c.File -eq 'C:\Program Files\Acme App\unins000.exe' -and $c.Arguments -eq '/SILENT') 'Quoted uninstaller path.'
$c=Split-YumCommandLine 'C:\Program Files\Acme App\uninstall.exe /S'; Assert-That ($c.File -eq 'C:\Program Files\Acme App\uninstall.exe' -and $c.Arguments -eq '/S') 'Unquoted path with spaces.'
$c=Get-YumUninstallCommand ([pscustomobject]@{Kind='Desktop';IsMsi=$false;ProductCode='';UninstallString='MsiExec.exe /I{11111111-2222-3333-4444-555555555555}'})
Assert-That ($c.Arguments -eq '/x {11111111-2222-3333-4444-555555555555}') 'Windows Installer programs are removed with msiexec /x, not /i (modify).'
Assert-That ((ConvertTo-YumCleanProgramName 'Mozilla Firefox (x64 en-US)') -eq 'Mozilla Firefox' -and (ConvertTo-YumCleanProgramName '7-Zip 24.08 (x64)') -eq '7-Zip') 'Program names without version / architecture.'
Assert-That ((Get-YumProgramAdvice 'Microsoft Visual C++ 2015-2022 Redistributable (x64)' 'Microsoft Corporation').Advice -eq 'Careful') 'Runtimes: careful.'
Assert-That ((Get-YumProgramAdvice 'NVIDIA Graphics Driver 560.94' 'NVIDIA Corporation').Advice -eq 'Careful') 'Drivers: careful.'
Assert-That ((Get-YumProgramAdvice 'VP9 Video Extensions' 'Microsoft Corporation').Advice -eq 'Careful') 'Codecs: careful.'
Assert-That ((Get-YumProgramAdvice 'Some Game' 'Some Studio').Advice -eq 'Your call') 'Ordinary programs: your call.'

# 2. End to end with a fake program (this account only).
$tag=[guid]::NewGuid().ToString('N').Substring(0,8)
$leaf="YumUninstallProbe$tag"
$inst=Join-Path $env:LOCALAPPDATA $leaf; $data=Join-Path $env:APPDATA $leaf; $other=Join-Path $env:LOCALAPPDATA ($leaf+'Other')
$menu=Join-Path $env:APPDATA ('Microsoft\Windows\Start Menu\Programs\{0}.lnk' -f $leaf)
$ukey="HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\$leaf"; $skey="HKCU:\Software\$leaf"
$tmp=Join-Path $env:TEMP ('yum-unin-'+$tag); New-Item -ItemType Directory $tmp | Out-Null
$oldDir=$script:Yum.ConfigDirectory; $script:Yum.ConfigDirectory=$tmp
try{
    New-Item -ItemType Directory $inst,$data,$other -Force | Out-Null
    [IO.File]::WriteAllText((Join-Path $inst 'app.exe'),'not a real program'); [IO.File]::WriteAllText((Join-Path $inst 'leftover.dat'),'left behind')
    [IO.File]::WriteAllText((Join-Path $data 'settings.json'),'{}'); [IO.File]::WriteAllText((Join-Path $other 'keep.txt'),'must stay')
    $ws=New-Object -ComObject WScript.Shell; $l=$ws.CreateShortcut($menu); $l.TargetPath=(Join-Path $inst 'app.exe'); $l.Save()
    New-Item -Path $skey -Force | Out-Null; New-ItemProperty -Path $skey -Name 'Theme' -Value 'dark' -Force | Out-Null
    # Its uninstaller removes the program and its Windows entry but leaves files behind - like many real ones.
    $un=Join-Path $inst 'uninstall.cmd'
    [IO.File]::WriteAllText($un,("@echo off`r`ndel /q `"{0}\app.exe`"`r`nreg delete `"HKCU\Software\Microsoft\Windows\CurrentVersion\Uninstall\{1}`" /f >nul`r`n" -f $inst,$leaf))
    New-Item -Path $ukey -Force | Out-Null
    foreach($kv in @(@('DisplayName',"YUM Uninstall Probe $tag"),@('Publisher','YumTest Labs'),@('DisplayVersion','1.2.3'),@('InstallLocation',$inst),@('UninstallString',('"{0}"' -f $un)),@('InstallDate',(Get-Date -Format 'yyyyMMdd')))){ New-ItemProperty -Path $ukey -Name $kv[0] -Value $kv[1] -Force | Out-Null }
    New-ItemProperty -Path $ukey -Name 'EstimatedSize' -Value 2048 -PropertyType DWord -Force | Out-Null

    $p=Get-YumInstalledPrograms | Where-Object { $_.KeyName -eq $leaf } | Select-Object -First 1
    Assert-That ($null -ne $p -and $p.Scope -eq 'This account' -and [double]$p.SizeMB -eq 2) 'The fake program is listed (this account, 2 MB).'
    Assert-That (Test-YumProgramStillInstalled -Program $p) 'It is installed before.'
    $r=Start-YumProgramUninstall -Program $p
    Assert-That ($r.Started -and $null -ne $r.Process) ('Its own uninstaller started ({0}).' -f $r.Reason)
    [void]$r.Process.WaitForExit(30000)
    $deadline=(Get-Date).AddSeconds(15); while((Test-YumProgramStillInstalled -Program $p) -and (Get-Date) -lt $deadline){ Start-Sleep -Milliseconds 200 }
    Assert-That (-not (Test-YumProgramStillInstalled -Program $p)) 'Windows no longer lists it.'

    # Leftovers: install folder + shortcut + registry ticked; its settings folder listed but not ticked; a folder
    # with a similar name and a folder used by another program are never offered.
    $usedByOther=[pscustomobject]@{Name='Other program';RegistryPath='HKCU\x';InstallLocation=(Join-Path $env:LOCALAPPDATA ($leaf+'Other'));DisplayIcon='';UninstallString=''}
    $rows=@(Find-YumProgramLeftovers -Program $p -OtherPrograms @($usedByOther))
    Write-Host ('found: ' + (($rows | ForEach-Object { '{0}:{1}:{2}' -f $_.Type,$_.Path,$_.Ticked }) -join ' | '))
    $find={ param($path) $rows | Where-Object { [string]$_.Path -ieq $path } | Select-Object -First 1 }
    $ri=& $find $inst; $rd=& $find $data; $rs=& $find $menu; $rk=& $find "HKCU\SOFTWARE\$leaf"
    Assert-That ($null -ne $ri -and $ri.Ticked) 'Its install folder is found and ticked.'
    Assert-That ($null -ne $rd -and -not $rd.Ticked) 'Its settings folder is found but not ticked (may hold your own files).'
    Assert-That ($null -ne $rs -and $rs.Ticked) 'Its Start menu shortcut is found.'
    Assert-That ($null -ne $rk -and $rk.Ticked) 'Its registry settings are found.'
    Assert-That ($null -eq (& $find $other)) 'A folder with a longer, similar name is never offered.'
    Assert-That (@($rows | Where-Object { [string]$_.Path -match '(?i)\\(Microsoft|Windows|Common Files)$' }).Count -eq 0) 'Shared folders are never offered.'
    # Remove everything found (the settings folder too, as if the user ticked it).
    $rd.Ticked=$true
    $done=@(Remove-YumProgramLeftovers -Program $p -Items @($rows | Where-Object { $_.Ticked }))
    Assert-That (@($done | Where-Object { -not $_.Removed }).Count -eq 0) ('All leftovers removed: ' + (($done | Where-Object { -not $_.Removed } | ForEach-Object { $_.Path+' '+$_.Result }) -join '; '))
    Assert-That (-not (Test-Path -LiteralPath $inst) -and -not (Test-Path -LiteralPath $data) -and -not (Test-Path -LiteralPath $menu) -and -not (Test-Path -LiteralPath $skey)) 'The leftovers are gone.'
    Assert-That (Test-Path -LiteralPath $other) 'The similar-named folder is still there.'
    $bak=@(Get-ChildItem -Path (Join-Path $tmp 'uninstall-backups') -Recurse -Filter *.reg)
    Assert-That ($bak.Count -ge 1 -and ((Get-Content -LiteralPath $bak[0].FullName -Raw) -match [regex]::Escape($leaf))) 'Registry settings were backed up to a .reg file first.'
    Assert-That ([IO.File]::Exists((Join-Path $tmp 'uninstall-last.txt'))) 'The list of what was removed is written.'
    # The backup really restores.
    $p2=Start-Process -FilePath (Join-Path $env:windir 'System32\reg.exe') -ArgumentList @('import',('"{0}"' -f $bak[0].FullName)) -WindowStyle Hidden -Wait -PassThru
    Assert-That ($p2.ExitCode -eq 0 -and (Get-ItemProperty -Path $skey -Name Theme).Theme -eq 'dark') 'Double-clicking the backup puts the settings back.'
} finally {
    $script:Yum.ConfigDirectory=$oldDir
    foreach($k in $ukey,$skey){ Remove-Item -Path $k -Recurse -Force -ErrorAction SilentlyContinue }
    foreach($d in $inst,$data,$other,$tmp){ Remove-Item -LiteralPath $d -Recurse -Force -ErrorAction SilentlyContinue }
    Remove-Item -LiteralPath $menu -Force -ErrorAction SilentlyContinue
}
$ux=[IO.File]::ReadAllText((Join-Path $repoRoot 'UI\Xaml\Uninstaller.xaml')); $mx=[IO.File]::ReadAllText((Join-Path $repoRoot 'UI\Xaml\MainWindow.xaml'))
Assert-That ($mx -match 'x:Name="Uninstaller"' -and $ux -match 'x:Name="RemoveLeftovers"') 'Sidebar button and leftovers panel exist.'
Write-Host ('UninstallerTest passed. {0} programs listed in {1} ms; fake program uninstalled, leftovers found, removed and restorable.' -f $all.Count,$ms)
