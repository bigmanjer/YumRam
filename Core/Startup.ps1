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
    # 5.15.2: specific well-known programs (VoiceMeeter, ASUS / HP extras...) get their own advice.
    if(Get-Command Get-YumKnownApp -ErrorAction SilentlyContinue){
        $k=$null;try{ $k=Get-YumKnownApp -Name ([IO.Path]::GetFileNameWithoutExtension([string]$ExePath)) -Path ([string]$ExePath) -Publisher '' -DisplayName $Name }catch{}
        if($null -ne $k){
            if($k.Advice -eq 'YourCall'){ return [pscustomobject]@{Level='Your call';Text=('{0}: {1}' -f $k.Label,$k.What);Locked=$false} }
            if($k.Advice -eq 'Keep'){ return [pscustomobject]@{Level='Careful';Text=('Keep on. {0}: {1}' -f $k.Label,$k.What);Locked=$false} }
        }
    }    if($Kind -in @('Drivers','Windows') -or $n -match 'realtek|nvidia|amd|radeon|intel|synaptics|elan|logi|lghub|razer|corsair|steelseries|asus|armoury|msi|dell|hp |lenovo|noisesuppression|audio|hidhide|touchpad'){
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
    # installers and are not shown by Windows either. -SkipExtras: leave out Store apps and sign-in tasks (the
    # Startup page loads those in the background - reading Task Scheduler and the Store can take seconds).
    param([switch]$SkipExtras)
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
    # 5.15 review: Store apps that start with Windows (Task Manager lists them too) and third-party scheduled
    # tasks that run when you sign in (measured on the test PC: 7 Store entries and 13 tasks the page missed,
    # including vendor "sale" pop-up tasks).
    if(-not $SkipExtras){
        try{ foreach($r in @(Get-YumStoreStartupTasks -ByPath $byPath)){ [void]$rows.Add($r) } }catch{}
        try{ foreach($r in @(Get-YumSignInTasks -ByPath $byPath)){ [void]$rows.Add($r) } }catch{}
    }
    return @($rows.ToArray() | Sort-Object @{Expression={[int](-not $_.Enabled)}},@{Expression={-[double]$_.MemoryMB}},Friendly)
}

function New-YumStartupRow {
    param([string]$Name,[string]$Friendly,[string]$Publisher,[string]$Command,[string]$ExePath,[string]$HiveName,[string]$ApprovedKey,[string]$Scope,[string]$Location,[bool]$Enabled,[bool]$NeedsAdmin,$ByPath,[string]$MemoryPrefix='',[bool]$Locked=$false,[string]$LockedWhy='')
    $exists=$false;try{ $exists=($ExePath -and (Test-Path -LiteralPath $ExePath -PathType Leaf)) }catch{}
    if(-not $Publisher -and $exists){ try{ $Publisher=[string]([Diagnostics.FileVersionInfo]::GetVersionInfo($ExePath)).CompanyName }catch{} }
    $bytes=[int64]0;$count=0
    if($MemoryPrefix){ $pre=$MemoryPrefix.TrimEnd('\').ToLowerInvariant()+'\'; foreach($k in @($ByPath.Keys)){ if(([string]$k).StartsWith($pre)){ $bytes+=[int64]$ByPath[$k].Bytes;$count+=[int]$ByPath[$k].Count } } }
    elseif($ExePath){ $m=$ByPath[$ExePath.ToLowerInvariant()]; if($null -ne $m){$bytes=[int64]$m.Bytes;$count=[int]$m.Count} }
    $sugg=Get-YumStartupSuggestion -Name $Name -ExePath $ExePath -Publisher $Publisher -Kind 'App'
    if($Locked){ $sugg=[pscustomobject]@{Level='Keep';Text=$LockedWhy;Locked=$true} }
    return [pscustomobject]@{
        Name=$Name;Friendly=$(if($Friendly){$Friendly}else{$Name});Publisher=$(if($Publisher){$Publisher}else{'Unknown publisher'});Command=$Command;ExePath=$ExePath;FileExists=$exists
        HiveName=$HiveName;ApprovedKey=$ApprovedKey;Scope=$Scope;Location=$Location;Enabled=$Enabled;DisabledAt=$null
        Running=($count -gt 0);MemoryMB=[math]::Round($bytes/1MB,0);ProcessCount=$count
        Kind='App';Suggestion=$sugg.Level;Advice=$sugg.Text;Locked=[bool]$sugg.Locked;NeedsAdmin=$NeedsAdmin}
}

$script:YumStoreStartupRoot='Software\Classes\Local Settings\Software\Microsoft\Windows\CurrentVersion\AppModel\SystemAppData'

function Get-YumStoreStartupTasks {
    # Store/MSIX apps declare a "startup task"; its per-user state is the value Task Manager flips:
    # 0 off (default), 1 off by you, 2 on, 3 off by policy, 4 on by policy.
    param($ByPath=@{})
    $rows=New-Object System.Collections.Generic.List[object]
    $root=[Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($script:YumStoreStartupRoot,$false)
    if($null -eq $root){return @()}
    try{
        $pk=@{};try{ foreach($p in @(Get-AppxPackage -ErrorAction Stop)){ $pk[[string]$p.PackageFamilyName]=$p } }catch{}
        foreach($pfn in $root.GetSubKeyNames()){
            $pkey=$root.OpenSubKey($pfn,$false); if($null -eq $pkey){continue}
            try{
                foreach($task in $pkey.GetSubKeyNames()){
                    $tk=$pkey.OpenSubKey($task,$false); if($null -eq $tk){continue}
                    try{
                        $state=$tk.GetValue('State',$null); if($null -eq $state){continue}
                        $state=[int]$state; if($state -eq 0){continue}   # never set to start: Task Manager does not list it either
                        $pkg=$pk[$pfn];$loc='';$friendly='';$pub=''
                        if($null -ne $pkg){ $loc=[string]$pkg.InstallLocation; $pub=$(if([string]$pkg.Publisher -match 'CN=([^,]+)'){$Matches[1]}else{''}); try{ $props=(Get-AppxPackageManifest -Package $pkg.PackageFullName).Package.Properties; $dn=[string]$props.DisplayName; if($dn -and $dn -notmatch '^ms-resource:'){$friendly=$dn}; $pd=[string]$props.PublisherDisplayName; if($pd -and $pd -notmatch '^ms-resource:'){$pub=$pd} }catch{}; if($pub -match '^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-'){$pub=''} }
                        if(-not $friendly){ $friendly=(($pfn -split '_')[0] -split '\.')[-1] }
                        $policy=($state -in 3,4)
                        [void]$rows.Add((New-YumStartupRow -Name ('{0}|{1}' -f $pfn,$task) -Friendly $friendly -Publisher $pub -Command ('Store app startup task "{0}"' -f $task) -ExePath '' -HiveName 'HKCU' -ApprovedKey 'StoreTask' -Scope 'You' -Location 'Store app' -Enabled ($state -in 2,4) -NeedsAdmin $false -ByPath $ByPath -MemoryPrefix $loc -Locked $policy -LockedWhy 'Your organisation (a Windows policy) decides whether this starts.'))
                    }finally{$tk.Close()}
                }
            }finally{$pkey.Close()}
        }
    }finally{$root.Close()}
    return @($rows.ToArray())
}

function Get-YumSignInTasks {
    # Third-party scheduled tasks that run when you sign in (not under \Microsoft\). Disabled, never deleted.
    param($ByPath=@{})
    $rows=New-Object System.Collections.Generic.List[object]
    $me=[Security.Principal.WindowsIdentity]::GetCurrent().Name
    foreach($t in @(Get-ScheduledTask -ErrorAction SilentlyContinue)){
        try{
            if([string]$t.TaskPath -like '\Microsoft\*'){continue}
            if([string]$t.TaskName -eq 'YUMRAM' -and [string]$t.TaskPath -eq '\'){continue}   # YUMRAM's own no-prompt task: Settings > General
            $logon=@($t.Triggers | Where-Object { $null -ne $_ -and [string]$_.CimClass.CimClassName -eq 'MSFT_TaskLogonTrigger' })
            if($logon.Count -eq 0){continue}
            $act=@($t.Actions | Where-Object { $null -ne $_ -and $_.PSObject.Properties['Execute'] })[0]
            $exe='';$cmd=''
            if($null -ne $act){ $exe=[Environment]::ExpandEnvironmentVariables(([string]$act.Execute).Trim('"')); $cmd=('{0} {1}' -f $act.Execute,$act.Arguments).Trim() }
            $uid=[string]$t.Principal.UserId
            $mine=($uid -and ($uid -ieq $me -or $uid -ieq ($me -split '\\')[-1]))
            $needsAdmin=(-not $mine) -or ([string]$t.Principal.RunLevel -eq 'Highest')
            # 5.16.3: per-user tasks carry the account's security ID (e.g. GHelper_S-1-5-21-...); shown without it
            # (an account identifier, and unreadable). The real task name is kept for turning it on/off.
            $shownName=([string]$t.TaskName -replace '[_ -]?S-1-5-21(-\d+)+','').Trim(); if(-not $shownName){ $shownName=[string]$t.TaskName }
            $friendly=$shownName; try{ if($exe -and (Test-Path -LiteralPath $exe -PathType Leaf)){ $d=[string]([Diagnostics.FileVersionInfo]::GetVersionInfo($exe)).FileDescription; if($d){ $friendly=$(if($d -ieq $shownName){$d}else{'{0} ({1})' -f $d,$shownName}) } } }catch{}
            [void]$rows.Add((New-YumStartupRow -Name ('{0}{1}' -f $t.TaskPath,$t.TaskName) -Friendly $friendly -Publisher '' -Command $cmd -ExePath $exe -HiveName 'Task' -ApprovedKey 'ScheduledTask' -Scope $(if($mine){'You'}else{'All users'}) -Location ('Task Scheduler {0}' -f $t.TaskPath) -Enabled ([string]$t.State -ne 'Disabled') -NeedsAdmin $needsAdmin -ByPath $ByPath))
        }catch{}
    }
    return @($rows.ToArray())
}

function Set-YumStartupAppEnabled {
    # Writes the same StartupApproved flag as Task Manager. Never deletes the Run entry or shortcut.
    param([Parameter(Mandatory=$true)]$App,[Parameter(Mandatory=$true)][bool]$Enabled)
    if([bool]$App.Locked -and -not $Enabled){return [pscustomobject]@{Success=$false;Reason=('{0} is security or anti-cheat software; YUMRAM will not stop it from starting.' -f $App.Friendly)}}
    if([bool]$App.NeedsAdmin -and -not (Test-YumIsElevated)){return [pscustomobject]@{Success=$false;Reason=$(if([string]$App.ApprovedKey -eq 'ScheduledTask'){'{0} is a task for all users or one that runs with administrator rights, so changing it needs YUMRAM to run as administrator.' -f $App.Friendly}else{'{0} starts for all users, so changing it needs YUMRAM to run as administrator.' -f $App.Friendly})}}
    if([string]$App.ApprovedKey -eq 'StoreTask'){
        # Same per-user value Task Manager writes: 2 = on, 1 = off by you.
        $parts=([string]$App.Name) -split '\|',2
        $k=$null
        try{
            $k=[Microsoft.Win32.Registry]::CurrentUser.OpenSubKey(('{0}\{1}\{2}' -f $script:YumStoreStartupRoot,$parts[0],$parts[1]),$true)
            if($null -eq $k){ return [pscustomobject]@{Success=$false;Reason='This Store app no longer has a startup entry.'} }
            $k.SetValue('State',$(if($Enabled){2}else{1}),[Microsoft.Win32.RegistryValueKind]::DWord)
            try{ Write-YumLog ('Startup app {0}: Store app {1} (same switch as Task Manager).' -f $(if($Enabled){'turned ON'}else{'turned OFF'}),$App.Name) }catch{}
            return [pscustomobject]@{Success=$true;Reason=$(if($Enabled){'{0} will start with Windows again.' -f $App.Friendly}else{'{0} will no longer start with Windows. It is still installed.' -f $App.Friendly})}
        }catch{ return [pscustomobject]@{Success=$false;Reason=('Windows refused the change: {0}' -f $_.Exception.Message)} }
        finally{ if($null -ne $k){$k.Close()} }
    }
    if([string]$App.ApprovedKey -eq 'ScheduledTask'){
        # Disable / enable only - the task is never deleted, so its program can still run it on demand later.
        try{
            $full=[string]$App.Name; $i=$full.LastIndexOf('\'); $tp=$full.Substring(0,$i+1); $tn=$full.Substring($i+1)
            if($Enabled){ Enable-ScheduledTask -TaskPath $tp -TaskName $tn -ErrorAction Stop | Out-Null } else { Disable-ScheduledTask -TaskPath $tp -TaskName $tn -ErrorAction Stop | Out-Null }
            try{ Write-YumLog ('Startup app {0}: scheduled task {1} (disabled/enabled, never deleted).' -f $(if($Enabled){'turned ON'}else{'turned OFF'}),$full) }catch{}
            return [pscustomobject]@{Success=$true;Reason=$(if($Enabled){'{0} runs at sign-in again.' -f $App.Friendly}else{'{0} will no longer run when you sign in. The task is kept (turned off), so you can turn it back on here.' -f $App.Friendly})}
        }catch{ return [pscustomobject]@{Success=$false;Reason=$(if($_.Exception.Message -match 'denied'){'This task belongs to all users or runs with administrator rights; run YUMRAM as administrator to change it.'}else{('Windows refused the change: {0}' -f $_.Exception.Message)})} }
    }
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
