#requires -Version 5.1
# 5.7: Startup apps (IObit Startup Optimizer / Task Manager "Startup apps" parity).
#
# YUMRAM turns startup apps on/off exactly the way Windows Task Manager does: it never deletes the Run
# entry or the shortcut, it only writes the "StartupApproved" flag next to it
#   HKCU|HKLM\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\{Run|Run32|StartupFolder}
#   value = 12 bytes: byte 0 even (02) = on, odd (03) = off; bytes 4-11 = FILETIME when it was turned off.
# So every change is reversible, and YUMRAM, Task Manager and Settings > Apps > Startup always agree.
# Verified on Windows 11 (26200): Chrome/Steam/OneDrive turned off in Task Manager read 03 00 00 00 +
# FILETIME; enabled entries read 02 00 ... 00.

$script:YumStartupApprovedRoot='Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved'

function Get-YumStartupExePath {
    # Extracts the program path from a Run command line ("C:\x y\a.exe" --flag  /  C:\a.exe -b).
    param([string]$Command)
    if([string]::IsNullOrWhiteSpace($Command)){return ''}
    $c=[Environment]::ExpandEnvironmentVariables($Command.Trim())
    if($c.StartsWith('"')){ $end=$c.IndexOf('"',1); if($end -gt 1){return $c.Substring(1,$end-1)} ; return $c.Trim('"') }
    $m=[regex]::Match($c,'^(.+?\.(exe|cmd|bat|com|lnk|vbs|ps1))(\s|$)','IgnoreCase')
    if($m.Success){return $m.Groups[1].Value}
    return ($c -split '\s+')[0]
}

function Get-YumShortcutTarget {
    param([string]$Path)
    try{ $sh=New-Object -ComObject WScript.Shell; $l=$sh.CreateShortcut($Path); return [string]$l.TargetPath }catch{ return '' }
}

function Get-YumStartupApprovedState {
    # Returns @{Enabled=bool;DisabledAt=datetime/null}. No value means Windows treats the entry as on.
    param([Microsoft.Win32.RegistryKey]$Hive,[string]$SubKey,[string]$Name)
    $k=$null
    try{
        $k=$Hive.OpenSubKey(('{0}\{1}' -f $script:YumStartupApprovedRoot,$SubKey),$false)
        if($null -eq $k){return [pscustomobject]@{Enabled=$true;DisabledAt=$null}}
        $v=$k.GetValue($Name,$null)
        if($v -isnot [byte[]] -or $v.Length -lt 1){return [pscustomobject]@{Enabled=$true;DisabledAt=$null}}
        $on=(($v[0] -band 1) -eq 0)
        $at=$null
        if(-not $on -and $v.Length -ge 12){ try{ $ft=[BitConverter]::ToInt64($v,4); if($ft -gt 0){$at=[datetime]::FromFileTime($ft)} }catch{} }
        return [pscustomobject]@{Enabled=$on;DisabledAt=$at}
    }catch{ return [pscustomobject]@{Enabled=$true;DisabledAt=$null} }
    finally{ if($null -ne $k){$k.Close()} }
}

function Get-YumStartupSuggestion {
    # Plain-language advice + whether YUMRAM lets you change it.
    param([string]$Name,[string]$ExePath,[string]$Publisher,[string]$Kind)
    $n=('{0} {1} {2}' -f $Name,[IO.Path]::GetFileNameWithoutExtension([string]$ExePath),$Publisher).ToLowerInvariant()
    if($Kind -eq 'Security' -or $n -match 'securityhealth|defender|msmpeng|antivirus|vanguard|vgtray|faceit|easyanticheat|battleye'){
        return [pscustomobject]@{Level='Keep';Text='Keep on. Security or anti-cheat software must start with Windows to protect you (or let your games run).';Locked=$true}
    }
    if($Kind -in @('Drivers','Windows') -or $n -match 'realtek|nvidia|amd|radeon|intel|synaptics|elan|logi|lghub|razer|corsair|steelseries|asus|armoury|msi|dell|hp |lenovo|noisesuppression|audio|hidhide|touchpad'){
        return [pscustomobject]@{Level='Careful';Text='Probably keep on. It belongs to your hardware (sound, mouse, keyboard, lighting or display); features may stop working until you open it yourself.';Locked=$false}
    }
    if($n -match 'onedrive|dropbox|googledrive|google drive|icloud|backup|vpn|proton|nordvpn|expressvpn|warp|cloudflare'){
        return [pscustomobject]@{Level='Your call';Text='Your choice. Syncing, backup or VPN only works while it runs; turn it off if you start it yourself when you need it.';Locked=$false}
    }
    if($n -match 'steam|epic|riot|ubisoft|battle\.net|origin|eadesktop|ea app|gog|overwolf|curseforge|discord|spotify|teams|slack|zoom|skype|whatsapp|telegram|chrome|edge|opera|brave|firefox|update|updater|jusched|idman|utorrent|utweb|bittorrent|ollama|docker|advanced systemcare|smartram|iobit|ccleaner|java'){
        return [pscustomobject]@{Level='Turn off';Text='Safe to turn off. It only saves you a click: you can still open it yourself whenever you want, and it will not use RAM until you do.';Locked=$false}
    }
    return [pscustomobject]@{Level='Your call';Text='Probably safe to turn off if you do not need it the moment you sign in. You can always turn it back on here or in Task Manager.';Locked=$false}
}

function Get-YumStartupApps {
    # Same places Task Manager lists (Run keys incl. 32-bit, Startup folders). RunOnce entries are one-shot
    # installers and are not shown by Windows either.
    $hkcu=[Microsoft.Win32.Registry]::CurrentUser;$hklm=[Microsoft.Win32.Registry]::LocalMachine
    $sources=@(
        @{Hive=$hkcu;HiveName='HKCU';Key='Software\Microsoft\Windows\CurrentVersion\Run';Approved='Run';Scope='You'},
        @{Hive=$hklm;HiveName='HKLM';Key='Software\Microsoft\Windows\CurrentVersion\Run';Approved='Run';Scope='All users'},
        @{Hive=$hklm;HiveName='HKLM';Key='Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Run';Approved='Run32';Scope='All users'}
    )
    # Process memory by exe path, one row per program (all its processes).
    $byPath=@{}
    try{
        foreach($p in @(Get-Process -ErrorAction SilentlyContinue)){
            $path=$null;try{$path=$p.Path}catch{}
            if([string]::IsNullOrWhiteSpace($path)){continue}
            $key=$path.ToLowerInvariant()
            if(-not $byPath.ContainsKey($key)){$byPath[$key]=[pscustomobject]@{Bytes=[int64]0;Count=0}}
            $byPath[$key].Bytes+=[int64]$p.WorkingSet64;$byPath[$key].Count++
        }
    }catch{}
    $rows=New-Object System.Collections.Generic.List[object]
    $add={
        param($Name,$Command,$ExePath,$Hive,$HiveName,$Approved,$Scope,$Location)
        $state=Get-YumStartupApprovedState -Hive $Hive -SubKey $Approved -Name $Name
        $exe=[string]$ExePath;$publisher='';$friendly='';$exists=$false
        try{ if($exe -and (Test-Path -LiteralPath $exe -PathType Leaf)){ $exists=$true; $vi=[Diagnostics.FileVersionInfo]::GetVersionInfo($exe); $publisher=[string]$vi.CompanyName; $friendly=[string]$vi.FileDescription } }catch{}
        $guide=$null;try{ $base=[IO.Path]::GetFileNameWithoutExtension($exe); if($base -and $script:YumProcessGuide -and $script:YumProcessGuide.ContainsKey($base.ToLowerInvariant())){$guide=$script:YumProcessGuide[$base.ToLowerInvariant()]} }catch{}
        if($null -ne $guide){$friendly=[string]$guide[0]}
        if([string]::IsNullOrWhiteSpace($friendly)){$friendly=$Name}
        $kind='App'
        try{ if(Get-Command Get-YumProcessKind -ErrorAction SilentlyContinue){ $kind=Get-YumProcessKind -Name ([IO.Path]::GetFileNameWithoutExtension($exe)) -Path $exe -Company $publisher -HasWindow:$true -IsGame:$false -Record $null } }catch{}
        $mem=$null;if($exe){$mem=$byPath[$exe.ToLowerInvariant()]}
        $sugg=Get-YumStartupSuggestion -Name $Name -ExePath $exe -Publisher $publisher -Kind $kind
        $needsAdmin=($HiveName -eq 'HKLM')
        [void]$rows.Add([pscustomobject]@{
            Name=[string]$Name;Friendly=[string]$friendly;Publisher=$(if($publisher){$publisher}else{'Unknown publisher'});Command=[string]$Command;ExePath=$exe;FileExists=$exists
            HiveName=$HiveName;ApprovedKey=$Approved;Scope=$Scope;Location=$Location;Enabled=[bool]$state.Enabled;DisabledAt=$state.DisabledAt
            Running=($null -ne $mem);MemoryMB=$(if($null -ne $mem){[math]::Round($mem.Bytes/1MB,0)}else{0});ProcessCount=$(if($null -ne $mem){$mem.Count}else{0})
            Kind=$kind;Suggestion=$sugg.Level;Advice=$sugg.Text;Locked=[bool]$sugg.Locked;NeedsAdmin=$needsAdmin
        })
    }
    foreach($s in $sources){
        $k=$null
        try{
            $k=$s.Hive.OpenSubKey($s.Key,$false); if($null -eq $k){continue}
            foreach($n in $k.GetValueNames()){
                if([string]::IsNullOrWhiteSpace($n)){continue}
                $cmd=[string]$k.GetValue($n,'',[Microsoft.Win32.RegistryValueOptions]::None)
                & $add $n $cmd (Get-YumStartupExePath -Command $cmd) $s.Hive $s.HiveName $s.Approved $s.Scope ('{0}\{1}' -f $s.HiveName,$s.Key)
            }
        }catch{} finally{ if($null -ne $k){$k.Close()} }
    }
    foreach($f in @(@{Path=[Environment]::GetFolderPath('Startup');Hive=$hkcu;HiveName='HKCU';Scope='You'},@{Path=[Environment]::GetFolderPath('CommonStartup');Hive=$hklm;HiveName='HKLM';Scope='All users'})){
        try{
            if(-not (Test-Path -LiteralPath $f.Path)){continue}
            foreach($file in @(Get-ChildItem -LiteralPath $f.Path -File -ErrorAction SilentlyContinue)){
                if($file.Name -ieq 'desktop.ini'){continue}
                $target=if($file.Extension -ieq '.lnk'){Get-YumShortcutTarget -Path $file.FullName}else{$file.FullName}
                & $add $file.Name $file.FullName $target $f.Hive $f.HiveName 'StartupFolder' $f.Scope $f.Path
            }
        }catch{}
    }
    return @($rows.ToArray() | Sort-Object @{Expression={[int](-not $_.Enabled)}},@{Expression={-[double]$_.MemoryMB}},Friendly)
}

function Set-YumStartupAppEnabled {
    # Writes the same StartupApproved flag as Task Manager. Never deletes the Run entry or shortcut.
    param([Parameter(Mandatory=$true)]$App,[Parameter(Mandatory=$true)][bool]$Enabled)
    if([bool]$App.Locked -and -not $Enabled){return [pscustomobject]@{Success=$false;Reason=('{0} is security or anti-cheat software; YUMRAM will not stop it from starting.' -f $App.Friendly)}}
    if([bool]$App.NeedsAdmin -and -not (Test-YumIsElevated)){return [pscustomobject]@{Success=$false;Reason=('{0} starts for all users, so changing it needs YUMRAM to run as administrator.' -f $App.Friendly)}}
    $hive=if($App.HiveName -eq 'HKLM'){[Microsoft.Win32.Registry]::LocalMachine}else{[Microsoft.Win32.Registry]::CurrentUser}
    $k=$null
    try{
        $k=$hive.CreateSubKey(('{0}\{1}' -f $script:YumStartupApprovedRoot,[string]$App.ApprovedKey))
        $bytes=New-Object byte[] 12
        if($Enabled){ $bytes[0]=2 } else { $bytes[0]=3; [Array]::Copy([BitConverter]::GetBytes([datetime]::Now.ToFileTime()),0,$bytes,4,8) }
        $k.SetValue([string]$App.Name,$bytes,[Microsoft.Win32.RegistryValueKind]::Binary)
        try{ Write-YumLog ('Startup app {0}: {1} ({2}\{3}). Same flag as Task Manager; the entry itself was not removed.' -f $(if($Enabled){'turned ON'}else{'turned OFF'}),$App.Name,$App.HiveName,$App.ApprovedKey) }catch{}
        return [pscustomobject]@{Success=$true;Reason=$(if($Enabled){'{0} will start with Windows again.' -f $App.Friendly}else{'{0} will no longer start with Windows. It is still installed - open it yourself whenever you want.' -f $App.Friendly})}
    }catch{
        return [pscustomobject]@{Success=$false;Reason=('Windows refused the change: {0}' -f $_.Exception.Message)}
    }finally{ if($null -ne $k){$k.Close()} }
}
