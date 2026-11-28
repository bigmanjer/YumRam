#requires -Version 5.1
# 5.17.0 (user: "consider an ability like IObit Uninstaller - I'd uninstall that program if YUMRAM did that").
# Uninstall programs the safe way, then clean what they leave behind:
#  - The list is Windows' own (the Uninstall registry keys: all users 64/32-bit + this account) plus Store apps.
#  - Uninstalling runs the program's OWN uninstaller (what Settings > Apps runs); Store apps are removed the way
#    Windows removes them. YUMRAM never deletes a program's files itself.
#  - Only after Windows confirms the program is gone, leftovers are searched: folders and registry keys named
#    exactly after the program (or publisher\program), never shared folders, never anything another installed
#    program or a running process uses.
#  - Removing leftovers is undoable: folders and shortcuts go to the Recycle Bin, registry keys are exported to a .reg
#    backup first (double-click it to restore). Every removal is listed.

$script:YumUninstallRoots=@(
    @{Hive='HKLM';View='Registry64';Path='SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall';Scope='All users'},
    @{Hive='HKLM';View='Registry32';Path='SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall';Scope='All users'},
    @{Hive='HKCU';View='Default';Path='SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall';Scope='This account'}
)
# Folder / key names that are shared by many programs or by Windows: never offered as a leftover.
$script:YumUninstallNeverNames=@('microsoft','windows','common files','windowsapps','intel','google','nvidia','nvidia corporation','amd','advanced micro devices','realtek','programs','packages','temp','tmp','cache','classes','policies','wow6432node','clients','registeredapplications','software','system','system32','syswow64','users','public','default','appdata','local','roaming','locallow','programdata','program files','program files (x86)','start menu','startup','desktop','documents','downloads','microsoft corporation','apple','apple inc.','mozilla','oracle','java','python','steam','valve','epic games','riot games','asus','asustek','logitech','dell','hp','lenovo','acer','msi','corsair','razer','adobe','autodesk','unity','node','nodejs','git','npm','nuget','dotnet','.net','updates','update','installer','setup','uninstall','data','config','settings','logs','tools','apps','games','driver','drivers','shared','support')

function ConvertTo-YumCleanProgramName {
    # "Mozilla Firefox (x64 en-US)" -> "Mozilla Firefox"; "7-Zip 24.08 (x64)" -> "7-Zip"; "Discord" -> "Discord".
    param([string]$Name)
    $n=[string]$Name
    $n=$n -replace '\s*\((x64|x86|64-bit|32-bit|amd64|arm64)[^)]*\)',''
    $n=$n -replace '\s+v?\d+(\.\d+){1,3}[a-z]?(\s.*)?$',''
    $n=$n -replace '\s+(x64|x86|64-bit|32-bit)$',''
    return $n.Trim(' ','-','_','.')
}
function ConvertTo-YumCleanPublisher {
    param([string]$Publisher)
    return (([string]$Publisher) -replace '[,]?\s+(Inc\.?|LLC|Ltd\.?|Limited|Corporation|Corp\.?|GmbH|Co\.?|S\.A\.|B\.V\.|AG|Pty)$','' -replace '[,]?\s+(Inc\.?|LLC|Ltd\.?)$','').Trim(' ',',','.')
}

function Get-YumProgramAdvice {
    # Plain advice per program: Careful (other programs or your devices may need it) / Your call.
    param([string]$Name,[string]$Publisher)
    $n=[string]$Name; $p=[string]$Publisher
    if($n -match '(?i)Visual C\+\+|\.NET( |$)|Windows Desktop Runtime|ASP\.NET|DirectX|WebView2|Java\(TM\)|^Java \d|Redistributable|Runtime(\s|$)|Python Launcher|Windows SDK|Windows Software Development Kit|Windows Package Manager|App Installer'){ return @{Advice='Careful';Why='Other programs and games use this. Removing it can stop them from starting - keep it unless you know nothing needs it.'} }
    if($p -match '(?i)NVIDIA|Advanced Micro Devices|^AMD|Intel|Realtek|ASUS|ASUSTeK|Logitech|Synaptics|ELAN|Dolby|Waves|Qualcomm|MediaTek|Broadcom|Killer|Razer|Corsair|SteelSeries|HP Inc|Hewlett|Dell|Lenovo|Acer|MSI|Micro-Star|Microsoft Corporation' -and $n -match '(?i)driver|graphics|audio|chipset|PhysX|HD Audio|Bluetooth|Wireless|Wi-?Fi|LAN|Ethernet|touchpad|armoury|framework|control center|software|G HUB|iCUE|Synapse|firmware|update|management engine|serial io|rapid storage|optimizer|service|MyASUS|Audio Control|Radeon'){ return @{Advice='Careful';Why='Software for your hardware (graphics, sound, keyboard, mouse, Wi-Fi or the laptop itself). Removing it can switch off features or the device - keep it unless you replaced the device.'} }
    if($n -match '(?i)Video Extension|Image Extension|Media Extension|HEIF|HEVC|AV1|Codec|Web Media'){ return @{Advice='Careful';Why='A video or picture format Windows uses to play some videos and open some pictures. Removing it can stop those from playing.'} }
    if($n -match '(?i)Vanguard|Easy Anti-?Cheat|BattlEye|FACEIT|anti-?cheat'){ return @{Advice='Your call';Why='Anti-cheat software: games that need it will not start without it (they usually reinstall it).'} }
    if($n -match '(?i)antivirus|anti-virus|Defender|Kaspersky|Norton|McAfee|Avast|AVG|Bitdefender|ESET|Malwarebytes|Sophos|Trend Micro|Webroot'){ return @{Advice='Your call';Why='Security software. Make sure Windows Defender or another antivirus protects you after removing it.'} }
    return @{Advice='Your call';Why='Remove it if you no longer use it. Its own uninstaller runs, and YUMRAM then looks for what it left behind.'}
}

function Get-YumInstalledPrograms {
    # Windows' installed-programs list (the same entries as Settings > Apps), without Windows parts and updates.
    $out=New-Object System.Collections.Generic.List[object]
    $seen=@{}
    foreach($r in $script:YumUninstallRoots){
        $base=$null; $key=$null
        try{
            $hive=if($r.Hive -eq 'HKLM'){[Microsoft.Win32.RegistryHive]::LocalMachine}else{[Microsoft.Win32.RegistryHive]::CurrentUser}
            $base=[Microsoft.Win32.RegistryKey]::OpenBaseKey($hive,[Microsoft.Win32.RegistryView]$r.View)
            $key=$base.OpenSubKey($r.Path)
            if($null -eq $key){ continue }
            foreach($sub in $key.GetSubKeyNames()){
                $k=$null
                try{
                    $k=$key.OpenSubKey($sub); if($null -eq $k){continue}
                    $name=[string]$k.GetValue('DisplayName'); if([string]::IsNullOrWhiteSpace($name)){continue}
                    if([int]($k.GetValue('SystemComponent',0)) -eq 1){continue}
                    if($null -ne $k.GetValue('ParentKeyName')){continue}
                    $rt=[string]$k.GetValue('ReleaseType'); if($rt -match '(?i)update|hotfix'){continue}
                    if($name -match '^(?i)(Security )?Update for |^Hotfix for |\(KB\d+\)'){continue}
                    $un=[string]$k.GetValue('UninstallString'); $quiet=[string]$k.GetValue('QuietUninstallString')
                    $isMsi=([int]($k.GetValue('WindowsInstaller',0)) -eq 1) -and ($sub -match '^\{[0-9A-Fa-f\-]{36}\}$')
                    if([string]::IsNullOrWhiteSpace($un) -and -not $isMsi){continue}
                    $ver=[string]$k.GetValue('DisplayVersion'); $pub=[string]$k.GetValue('Publisher')
                    $dedupe=('{0}|{1}' -f $name,$ver).ToLowerInvariant(); if($seen.ContainsKey($dedupe)){continue}; $seen[$dedupe]=$true
                    $kb=$k.GetValue('EstimatedSize'); $mb=if($null -ne $kb){[math]::Round([double]$kb/1024,0)}else{$null}
                    $date=$null; $d=[string]$k.GetValue('InstallDate'); if($d -match '^\d{8}$'){ try{ $date=[datetime]::ParseExact($d,'yyyyMMdd',$null) }catch{} }
                    $loc=([string]$k.GetValue('InstallLocation')).Trim().Trim('"').TrimEnd('\')
                    $icon=([string]$k.GetValue('DisplayIcon')) -replace ',\s*-?\d+$','' -replace '"',''
                    $adv=Get-YumProgramAdvice -Name $name -Publisher $pub
                    [void]$out.Add([pscustomobject]@{
                        Kind='Desktop';Name=$name;Publisher=$pub;Version=$ver;SizeMB=$mb;InstallDate=$date;InstallLocation=$loc;DisplayIcon=$icon
                        UninstallString=$un;QuietUninstallString=$quiet;IsMsi=$isMsi;ProductCode=$(if($isMsi){$sub}else{''})
                        Scope=$r.Scope;RegistryPath=('{0}\{1}\{2}' -f $r.Hive,$r.Path,$sub);RegistryView=$r.View;KeyName=$sub
                        Advice=$adv.Advice;Why=$adv.Why;PackageFullName=''})
                }catch{} finally{ if($null -ne $k){$k.Dispose()} }
            }
        }catch{} finally{ if($null -ne $key){$key.Dispose()}; if($null -ne $base){$base.Dispose()} }
    }
    return $out.ToArray()
}

function Get-YumStoreApps {
    # Store apps of this account that can be removed (not frameworks, not part of Windows). Windows' own package
    # manager gives the real names ("Paint 3D", not Microsoft.MSPaint): 158 packages in ~0.1 s on the test PC.
    $out=New-Object System.Collections.Generic.List[object]
    try{
        $pm=[Windows.Management.Deployment.PackageManager,Windows.Management.Deployment,ContentType=WindowsRuntime]::new()
        foreach($p in $pm.FindPackagesForUser('')){
            try{
                if([bool]$p.IsFramework -or [bool]$p.IsResourcePackage -or [bool]$p.IsBundle){continue}
                if([string]$p.SignatureKind -notin @('Store','Developer')){continue}
                $id=[string]$p.Id.Name
                if($id -match '^(?i)Microsoft\.(Windows\.|UI\.|VCLibs|NET\.|DesktopAppInstaller|StorePurchaseApp|WindowsStore|SecHealthUI|Services\.Store|WindowsAppRuntime|WinAppRuntime|Xbox\.?(TCUI|GameOverlay|GamingOverlay|IdentityProvider|SpeechToTextOverlay)|GamingServices|LanguageExperiencePack|ApplicationCompatibilityEnhancements|MicrosoftEdge|Edge\.)'){continue}
                $display=[string]$p.DisplayName; if([string]::IsNullOrWhiteSpace($display) -or $display -match '^ms-resource:'){ $display=$id }
                if($display -match '(?i)DDLM|Runtime|Framework|Language Experience Pack'){continue}
                $pub=[string]$p.PublisherDisplayName
                $date=$null; try{ $date=$p.InstalledDate.LocalDateTime }catch{}
                $loc=''; try{ $loc=[string]$p.InstalledPath }catch{}
                $adv=Get-YumProgramAdvice -Name $display -Publisher $pub
                [void]$out.Add([pscustomobject]@{
                    Kind='Store';Name=$display;Publisher=$pub;Version=('{0}.{1}.{2}.{3}' -f $p.Id.Version.Major,$p.Id.Version.Minor,$p.Id.Version.Build,$p.Id.Version.Revision);SizeMB=$null;InstallDate=$date;InstallLocation=$loc;DisplayIcon=''
                    UninstallString='';QuietUninstallString='';IsMsi=$false;ProductCode='';Scope='This account';RegistryPath='';RegistryView='';KeyName=''
                    Advice=$adv.Advice;Why=$(if($adv.Advice -eq 'Careful'){$adv.Why}else{'A Microsoft Store app. Removing it works like "Uninstall" in Settings > Apps; you can get it back from the Microsoft Store.'});PackageFullName=[string]$p.Id.FullName})
            }catch{}
        }
    }catch{}
    return $out.ToArray()
}
function Split-YumCommandLine {
    # "C:\Program Files\X\uninst.exe" /S  -> exe + args; also unquoted paths with spaces (find the .exe).
    param([string]$Command)
    $c=([string]$Command).Trim()
    if($c.StartsWith('"')){ $e=$c.IndexOf('"',1); if($e -gt 1){ return [pscustomobject]@{File=$c.Substring(1,$e-1);Arguments=$c.Substring($e+1).Trim()} } }
    $m=[regex]::Match($c,'(?i)^(.+?\.(exe|cmd|bat))(\s+(.*))?$')
    if($m.Success){ return [pscustomobject]@{File=$m.Groups[1].Value.Trim();Arguments=$m.Groups[4].Value.Trim()} }
    $sp=$c.IndexOf(' '); if($sp -gt 0){ return [pscustomobject]@{File=$c.Substring(0,$sp);Arguments=$c.Substring($sp+1).Trim()} }
    return [pscustomobject]@{File=$c;Arguments=''}
}

function Get-YumUninstallCommand {
    # What Settings > Apps would run. Windows Installer packages: msiexec /x {code} (not /i, which opens "modify").
    param($Program)
    if([string]$Program.Kind -eq 'Store'){ return $null }
    if([bool]$Program.IsMsi -and [string]$Program.ProductCode){ return [pscustomobject]@{File=(Join-Path $env:windir 'System32\msiexec.exe');Arguments=('/x {0}' -f $Program.ProductCode)} }
    $u=[string]$Program.UninstallString
    if($u -match '(?i)msiexec(\.exe)?["]?\s+/[IX]\s*(\{[0-9A-F\-]{36}\})'){ return [pscustomobject]@{File=(Join-Path $env:windir 'System32\msiexec.exe');Arguments=('/x {0}' -f $Matches[2])} }
    return (Split-YumCommandLine -Command $u)
}

function Test-YumProgramStillInstalled {
    param($Program)
    try{
        if([string]$Program.Kind -eq 'Store'){ return $null -ne (Get-AppxPackage -ErrorAction SilentlyContinue | Where-Object { $_.PackageFullName -eq [string]$Program.PackageFullName } | Select-Object -First 1) }
        $parts=([string]$Program.RegistryPath).Split('\',2)
        $hive=if($parts[0] -eq 'HKLM'){[Microsoft.Win32.RegistryHive]::LocalMachine}else{[Microsoft.Win32.RegistryHive]::CurrentUser}
        $view=if([string]$Program.RegistryView){[Microsoft.Win32.RegistryView][string]$Program.RegistryView}else{[Microsoft.Win32.RegistryView]::Default}
        $base=[Microsoft.Win32.RegistryKey]::OpenBaseKey($hive,$view)
        try{ $k=$base.OpenSubKey($parts[1]); if($null -eq $k){ return $false }; $k.Dispose(); return $true } finally { $base.Dispose() }
    }catch{ return $true }
}

function Start-YumProgramUninstall {
    # Starts the program's own uninstaller (Windows asks for permission when it needs administrator).
    # Returns @{Process; Started; Reason}. Store apps are removed in the background.
    param($Program)
    if([string]$Program.Kind -eq 'Store'){
        $ps=[powershell]::Create()
        [void]$ps.AddScript({ param($Full) Remove-AppxPackage -Package $Full -ErrorAction Stop }).AddArgument([string]$Program.PackageFullName)
        return [pscustomobject]@{Started=$true;Process=$null;Job=@{Ps=$ps;Handle=$ps.BeginInvoke()};Reason='Removing the Store app…'}
    }
    $cmd=Get-YumUninstallCommand -Program $Program
    if($null -eq $cmd -or [string]::IsNullOrWhiteSpace([string]$cmd.File)){ return [pscustomobject]@{Started=$false;Process=$null;Job=$null;Reason='This program has no uninstaller registered with Windows.'} }
    try{
        $file=[Environment]::ExpandEnvironmentVariables([string]$cmd.File)
        if(-not [IO.File]::Exists($file) -and $file -notmatch '(?i)msiexec'){ return [pscustomobject]@{Started=$false;Process=$null;Job=$null;Reason=('Its uninstaller is missing ({0}). The program may already be gone - YUMRAM can still look for leftovers.' -f $file)} }
        $p=if([string]::IsNullOrWhiteSpace([string]$cmd.Arguments)){ Start-Process -FilePath $file -PassThru -ErrorAction Stop }else{ Start-Process -FilePath $file -ArgumentList ([string]$cmd.Arguments) -PassThru -ErrorAction Stop }
        Write-YumLog ('Uninstall: started the uninstaller of {0} ({1} {2}).' -f $Program.Name,$file,$cmd.Arguments)
        return [pscustomobject]@{Started=$true;Process=$p;Job=$null;Reason=('{0}''s uninstaller is open - follow its steps.' -f $Program.Name)}
    }catch{
        $msg=$_.Exception.Message; if($msg -match '(?i)cancel'){ $msg='Windows'' permission prompt was cancelled.' }
        return [pscustomobject]@{Started=$false;Process=$null;Job=$null;Reason=('The uninstaller did not start: {0}' -f $msg)}
    }
}

function Get-YumFolderSizeMB {
    param([string]$Path,[int]$MaxFiles=200000)
    $s=[int64]0;$n=0
    try{ foreach($f in [IO.Directory]::EnumerateFiles($Path,'*',[IO.SearchOption]::AllDirectories)){ try{ $s+=(New-Object IO.FileInfo($f)).Length }catch{}; if(++$n -ge $MaxFiles){break} } }catch{}
    return [math]::Round($s/1MB,1)
}

function Find-YumProgramLeftovers {
    # What an uninstalled program left behind - strict name matches only. Returns rows
    # @{Type=Folder|Shortcut|Registry; Path; Display; SizeMB; Ticked; Note}.
    param($Program,$OtherPrograms=$null)
    $rows=New-Object System.Collections.Generic.List[object]
    $seen=@{}
    $name=ConvertTo-YumCleanProgramName ([string]$Program.Name)
    $pub=ConvertTo-YumCleanPublisher ([string]$Program.Publisher)
    $locLeaf=if([string]$Program.InstallLocation){[IO.Path]::GetFileName(([string]$Program.InstallLocation).TrimEnd('\'))}else{''}
    $names=@(@($name,$locLeaf,([string]$Program.Name)) | Where-Object { $_ -and $_.Length -ge 4 -and $script:YumUninstallNeverNames -notcontains $_.ToLowerInvariant() } | Select-Object -Unique)
    # Short or shared names (Git, Steam) are not searched by name; its registered install folder is still checked.
    if($null -eq $OtherPrograms){ $OtherPrograms=@(Get-YumInstalledPrograms) }
    # Folders still used by programs that remain installed (their install folder, uninstaller or icon lives there).
    $used=New-Object System.Collections.Generic.List[string]
    foreach($o in @($OtherPrograms)){
        if([string]$o.RegistryPath -eq [string]$Program.RegistryPath -and [string]$o.Name -eq [string]$Program.Name){continue}
        foreach($p in @([string]$o.InstallLocation,[string]$o.DisplayIcon,[string](Split-YumCommandLine -Command ([string]$o.UninstallString)).File)){ if($p -and $p.Length -gt 3){ try{ [void]$used.Add(([IO.Path]::GetFullPath($p.Trim('"'))).TrimEnd('\').ToLowerInvariant()) }catch{} } }
    }
    $running=@(); try{ $running=@(Get-Process -ErrorAction SilentlyContinue | ForEach-Object { try{ ([string]$_.Path).ToLowerInvariant() }catch{} } | Where-Object { $_ }) }catch{}
    $forbidden=@($env:windir,$env:SystemDrive+'\',$env:ProgramFiles,${env:ProgramFiles(x86)},$env:ProgramData,$env:APPDATA,$env:LOCALAPPDATA,$env:USERPROFILE,(Join-Path $env:USERPROFILE 'Desktop'),(Join-Path $env:USERPROFILE 'Documents'),(Join-Path $env:USERPROFILE 'Downloads')) | Where-Object { $_ } | ForEach-Object { $_.TrimEnd('\').ToLowerInvariant() }
    $addFolder={ param([string]$Path,[string]$Why)
        try{
            if(-not $Path -or -not [IO.Directory]::Exists($Path)){return}
            $full=([IO.Path]::GetFullPath($Path)).TrimEnd('\'); $low=$full.ToLowerInvariant()
            if($seen.ContainsKey($low)){return}
            if($forbidden -contains $low){return}
            if($low.StartsWith(($env:windir).ToLowerInvariant()+'\')){return}
            if($script:YumUninstallNeverNames -contains ([IO.Path]::GetFileName($full)).ToLowerInvariant()){return}
            try{ if(([IO.File]::GetAttributes($full) -band [IO.FileAttributes]::ReparsePoint) -ne 0){return} }catch{return}
            foreach($u in $used){ if($u -eq $low -or $u.StartsWith($low+'\') -or $low.StartsWith($u+'\')){ return } }
            foreach($r in $running){ if($r.StartsWith($low+'\')){ return } }
            $seen[$low]=$true
            # AppData folders hold its settings and sometimes your own files (templates, saves): listed, not ticked.
            $userData=($low.StartsWith(([string]$env:APPDATA).ToLowerInvariant()+'\') -or $low.StartsWith(([string]$env:LOCALAPPDATA).ToLowerInvariant()+'\') -or $low.StartsWith((Join-Path $env:USERPROFILE 'AppData\LocalLow').ToLowerInvariant()+'\')) -and $Why -ne 'its install folder' -and -not $low.StartsWith((Join-Path $env:LOCALAPPDATA 'Programs').ToLowerInvariant()+'\')
            [void]$rows.Add([pscustomobject]@{Type='Folder';Path=$full;Display=$full;SizeMB=(Get-YumFolderSizeMB -Path $full);Ticked=(-not $userData);Note=$(if($userData){'its settings and data - may include your own files; tick if you are sure'}else{$Why})})
        }catch{}
    }
    if([string]$Program.Kind -ne 'Store' -and [string]$Program.InstallLocation){ & $addFolder ([string]$Program.InstallLocation) 'its install folder' }
    $roots=@($env:ProgramFiles,${env:ProgramFiles(x86)},$env:ProgramData,$env:APPDATA,$env:LOCALAPPDATA,(Join-Path $env:LOCALAPPDATA 'Programs'),(Join-Path $env:USERPROFILE 'AppData\LocalLow')) | Where-Object { $_ } | Select-Object -Unique
    foreach($root in $roots){
        foreach($n in $names){
            & $addFolder (Join-Path $root $n) 'named after it'
            if($pub -and $pub.Length -ge 3 -and $script:YumUninstallNeverNames -notcontains $pub.ToLowerInvariant()){ & $addFolder (Join-Path (Join-Path $root $pub) $n) 'its publisher''s folder for it' }
        }
    }
    # Start menu folders / shortcuts and desktop shortcuts that point into its install folder or carry its name.
    $loc=([string]$Program.InstallLocation).TrimEnd('\').ToLowerInvariant()
    $shell=$null; try{ $shell=New-Object -ComObject WScript.Shell }catch{}
    $menus=@((Join-Path $env:ProgramData 'Microsoft\Windows\Start Menu\Programs'),(Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs'),[Environment]::GetFolderPath('Desktop'),[Environment]::GetFolderPath('CommonDesktopDirectory')) | Where-Object { $_ -and [IO.Directory]::Exists($_) }
    foreach($m in $menus){
        foreach($n in $names){ $d=Join-Path $m $n; if([IO.Directory]::Exists($d)){ & $addFolder $d 'its Start menu folder' } }
        try{
            foreach($lnk in [IO.Directory]::GetFiles($m,'*.lnk',[IO.SearchOption]::AllDirectories)){
                try{
                    if($seen.ContainsKey($lnk.ToLowerInvariant())){continue}
                    $target=''; if($null -ne $shell){ $target=[string]$shell.CreateShortcut($lnk).TargetPath }
                    $base=[IO.Path]::GetFileNameWithoutExtension($lnk)
                    $byTarget=($loc.Length -gt 3 -and $target -and $target.ToLowerInvariant().StartsWith($loc+'\'))
                    $byName=(@($names | Where-Object { $base -ieq $_ }).Count -gt 0) -and ($target -and -not [IO.File]::Exists($target))
                    if($byTarget -or $byName){ $seen[$lnk.ToLowerInvariant()]=$true; [void]$rows.Add([pscustomobject]@{Type='Shortcut';Path=$lnk;Display=$lnk;SizeMB=0;Ticked=$true;Note='a shortcut to it'}) }
                }catch{}
            }
        }catch{}
    }
    # Registry: Software\<name> and Software\<publisher>\<name> (this account and all users), and a stale uninstall entry.
    $keys=New-Object System.Collections.Generic.List[string]
    foreach($n in $names){
        foreach($h in 'HKCU','HKLM'){
            foreach($sw in 'SOFTWARE','SOFTWARE\WOW6432Node'){
                if($h -eq 'HKCU' -and $sw -ne 'SOFTWARE'){continue}
                [void]$keys.Add(('{0}\{1}\{2}' -f $h,$sw,$n))
                if($pub -and $pub.Length -ge 3 -and $script:YumUninstallNeverNames -notcontains $pub.ToLowerInvariant()){ [void]$keys.Add(('{0}\{1}\{2}\{3}' -f $h,$sw,$pub,$n)) }
            }
        }
    }
    foreach($k in @($keys | Select-Object -Unique)){
        try{ if(Test-Path -LiteralPath ('Registry::'+$k.Replace('HKCU\','HKEY_CURRENT_USER\').Replace('HKLM\','HKEY_LOCAL_MACHINE\'))){ [void]$rows.Add([pscustomobject]@{Type='Registry';Path=$k;Display=$k;SizeMB=0;Ticked=$true;Note='its settings in the registry'}) } }catch{}
    }
    if([string]$Program.Kind -ne 'Store' -and (Test-YumProgramStillInstalled -Program $Program)){
        [void]$rows.Add([pscustomobject]@{Type='Registry';Path=[string]$Program.RegistryPath;Display=([string]$Program.RegistryPath+'  (its entry in the installed-programs list)');SizeMB=0;Ticked=$false;Note='still listed as installed - tick only if its uninstaller finished'})
    }
    return $rows.ToArray()
}

function Get-YumUninstallBackupDirectory {
    $d=Join-Path $script:Yum.ConfigDirectory 'uninstall-backups'
    if(-not [IO.Directory]::Exists($d)){ [void][IO.Directory]::CreateDirectory($d) }
    return $d
}

function Remove-YumProgramLeftovers {
    # Folders / shortcuts -> Recycle Bin; registry keys -> exported to a .reg backup, then removed. Returns a report.
    param($Program,$Items)
    Add-Type -AssemblyName Microsoft.VisualBasic
    $stamp=Get-Date -Format 'yyyyMMdd-HHmmss'
    $safe=(([string]$Program.Name) -replace '[^\w\.\- ]','_').Trim(); if($safe.Length -gt 40){$safe=$safe.Substring(0,40)}
    $bdir=Join-Path (Get-YumUninstallBackupDirectory) ('{0} {1}' -f $stamp,$safe)
    $done=New-Object System.Collections.Generic.List[object]
    foreach($it in @($Items)){
        $ok=$false;$why=''
        try{
            switch([string]$it.Type){
                'Folder'   { [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteDirectory([string]$it.Path,[Microsoft.VisualBasic.FileIO.UIOption]::OnlyErrorDialogs,[Microsoft.VisualBasic.FileIO.RecycleOption]::SendToRecycleBin); $ok=$true; $why='moved to the Recycle Bin' }
                'Shortcut' { [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteFile([string]$it.Path,[Microsoft.VisualBasic.FileIO.UIOption]::OnlyErrorDialogs,[Microsoft.VisualBasic.FileIO.RecycleOption]::SendToRecycleBin); $ok=$true; $why='moved to the Recycle Bin' }
                'Registry' {
                    if(-not [IO.Directory]::Exists($bdir)){ [void][IO.Directory]::CreateDirectory($bdir) }
                    $file=Join-Path $bdir (('{0}.reg' -f ($done.Count+1)))
                    $p=Start-Process -FilePath (Join-Path $env:windir 'System32\reg.exe') -ArgumentList @('export',('"{0}"' -f $it.Path),('"{0}"' -f $file),'/y') -WindowStyle Hidden -Wait -PassThru
                    if($p.ExitCode -ne 0 -or -not [IO.File]::Exists($file)){ $why='not removed: the backup could not be made'; break }
                    Remove-Item -LiteralPath ('Registry::'+([string]$it.Path).Replace('HKCU\','HKEY_CURRENT_USER\').Replace('HKLM\','HKEY_LOCAL_MACHINE\')) -Recurse -Force -ErrorAction Stop
                    $ok=$true; $why=('removed (backup: {0})' -f $file)
                }
            }
        }catch{ $why=('not removed: {0}' -f $_.Exception.Message) }
        [void]$done.Add([pscustomobject]@{Type=$it.Type;Path=$it.Path;Removed=$ok;Result=$why})
    }
    try{
        $log=Join-Path $script:Yum.ConfigDirectory 'uninstall-last.txt'
        $lines=@(('YUMRAM - leftovers of {0} removed {1}' -f $Program.Name,(Get-Date -Format 'yyyy-MM-dd HH:mm')),'Folders and shortcuts are in the Recycle Bin; registry backups can be double-clicked to restore.','')+@($done | ForEach-Object { "{0}`t{1}`t{2}" -f $_.Type,$_.Path,$_.Result })
        [IO.File]::WriteAllLines($log,[string[]]$lines)
    }catch{}
    Write-YumLog ('Uninstall: leftovers of {0}: {1} removed, {2} skipped.' -f $Program.Name,@($done | Where-Object Removed).Count,@($done | Where-Object { -not $_.Removed }).Count)
    return $done.ToArray()
}
