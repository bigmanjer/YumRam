#requires -Version 5.1
# 5.15.2 (user request: "automatic disk clean up like BleachBit / CCleaner, and WinDirStat"). Two tools:
#  1. Junk cleanup: only well-known cache / temp folders that programs and Windows rebuild by themselves. Never
#     cookies, passwords, history, documents, downloads or anything a person made. Every category shows its size
#     first; nothing is deleted without a click (or the opt-in weekly automatic clean of the safest categories).
#  2. "What's using my disk": biggest folders (drill down) and biggest files, like WinDirStat / WizTree.
# Safety rules in the walker: never follow junctions / symbolic links (reparse points), skip files in use,
# honour a minimum age (e.g. temp files must be a day old), stay inside the category's own folders.

function Initialize-YumDiskWalkType {
    if('YumDiskWalk' -as [type]){return}
    Add-Type -TypeDefinition @'
using System; using System.IO; using System.Collections.Generic;
public static class YumDiskWalk {
    public sealed class Result { public long Bytes; public long Files; public long Skipped; public long Deleted; public long Freed; public List<string> DeletedPaths = new List<string>(); }
    static bool Match(string name, string[] patterns) {
        if (patterns == null || patterns.Length == 0) return true;
        foreach (var p in patterns) { if (string.IsNullOrEmpty(p) || p == "*") return true;
            if (p.StartsWith("*") && p.EndsWith("*") && p.Length > 2) { if (name.IndexOf(p.Substring(1, p.Length - 2), StringComparison.OrdinalIgnoreCase) >= 0) return true; }
            else if (p.StartsWith("*")) { if (name.EndsWith(p.Substring(1), StringComparison.OrdinalIgnoreCase)) return true; }
            else if (p.EndsWith("*")) { if (name.StartsWith(p.Substring(0, p.Length - 1), StringComparison.OrdinalIgnoreCase)) return true; }
            else if (string.Equals(name, p, StringComparison.OrdinalIgnoreCase)) return true; }
        return false;
    }
    // Measure or clean one root. minAge: files written more recently are left alone. Directories that are
    // reparse points (junctions, symlinks) are never entered, so cleaning can never leave the folder.
    public static Result Walk(string root, string[] patterns, double minAgeHours, bool delete) { return WalkEx(root, patterns, minAgeHours, delete, null, null); }
    // 5.15.3: skipExt = file types never touched here (documents a person may have opened from an e-mail or a zip);
    // skipDirPrefix = folder names never entered (e.g. "Temp1_" = files Windows unpacked when you opened a zip).
    public static Result WalkEx(string root, string[] patterns, double minAgeHours, bool delete, string[] skipExt, string[] skipDirPrefix) {
        var r = new Result();
        if (string.IsNullOrEmpty(root) || !Directory.Exists(root)) return r;
        DateTime cutoff = DateTime.UtcNow.AddHours(-minAgeHours);
        var stack = new Stack<DirectoryInfo>(); stack.Push(new DirectoryInfo(root));
        var dirs = new List<DirectoryInfo>();
        while (stack.Count > 0) {
            var d = stack.Pop();
            FileSystemInfo[] items;
            try { items = d.GetFileSystemInfos(); } catch { r.Skipped++; continue; }
            foreach (var it in items) {
                try {
                    if ((it.Attributes & FileAttributes.ReparsePoint) != 0) continue;
                    var sub = it as DirectoryInfo;
                    if (sub != null) {
                        bool skipDir = false;
                        if (skipDirPrefix != null) foreach (var sp in skipDirPrefix) if (!string.IsNullOrEmpty(sp) && sub.Name.StartsWith(sp, StringComparison.OrdinalIgnoreCase)) { skipDir = true; break; }
                        if (!skipDir) { stack.Push(sub); dirs.Add(sub); }
                        continue;
                    }
                    var f = (FileInfo)it;
                    if (!Match(f.Name, patterns)) continue;
                    if (skipExt != null) { bool keep = false; foreach (var x in skipExt) if (!string.IsNullOrEmpty(x) && f.Name.EndsWith(x, StringComparison.OrdinalIgnoreCase)) { keep = true; break; } if (keep) continue; }
                    if (f.LastWriteTimeUtc > cutoff) continue;
                    r.Bytes += f.Length; r.Files++;
                    if (delete) {
                        // 5.15.3 test on a real PC: Windows lets you delete a file another program still has open (e.g. Chrome's
                        // cache, Explorer's thumbnails); it only disappears - and frees space - when that program closes.
                        // YUMRAM reported 1.7 GB while the drive gained 1.2 GB. Now a file is deleted only if nothing has it
                        // open (exclusive open succeeds); otherwise it is skipped as "in use", so the number is honest and
                        // running programs are left alone.
                        try {
                            if ((f.Attributes & FileAttributes.ReadOnly) != 0) f.Attributes = FileAttributes.Normal;
                            long len = f.Length;
                            using (var probe = new FileStream(f.FullName, FileMode.Open, FileAccess.ReadWrite, FileShare.None)) { }
                            f.Delete(); r.Deleted++; r.Freed += len; if (r.DeletedPaths.Count < 50000) r.DeletedPaths.Add(f.FullName + "\t" + len);
                        }
                        catch { r.Skipped++; }
                    }
                } catch { r.Skipped++; }
            }
        }
        if (delete) { dirs.Reverse(); foreach (var d in dirs) { try { if (d.Exists && d.GetFileSystemInfos().Length == 0) d.Delete(); } catch { } } }
        return r;
    }
    public sealed class Entry { public string Name; public string Path; public long Bytes; public long Files; public bool IsFolder; public DateTime Modified; }
    public sealed class Usage { public List<Entry> Folders = new List<Entry>(); public List<Entry> TopFiles = new List<Entry>(); public long Bytes; public long Files; public long Denied; }
    // What's using a folder: size of each direct child (recursive) and the biggest files anywhere below.
    public static Usage Analyze(string root, int topFiles) {
        var u = new Usage();
        if (string.IsNullOrEmpty(root) || !Directory.Exists(root)) return u;
        var top = new List<Entry>();
        long minTop = 0;
        Action<FileInfo> consider = (f) => {
            if (top.Count < topFiles || f.Length > minTop) {
                top.Add(new Entry { Name = f.Name, Path = f.FullName, Bytes = f.Length, Files = 1, Modified = f.LastWriteTime });
                if (top.Count > topFiles * 2) { top.Sort((a, b) => b.Bytes.CompareTo(a.Bytes)); top.RemoveRange(topFiles, top.Count - topFiles); }
                if (top.Count >= topFiles) { long m = long.MaxValue; foreach (var e in top) if (e.Bytes < m) m = e.Bytes; minTop = m; }
            }
        };
        FileSystemInfo[] first;
        try { first = new DirectoryInfo(root).GetFileSystemInfos(); } catch { u.Denied++; return u; }
        var loose = new Entry { Name = "(files directly in this folder)", Path = root, IsFolder = false };
        foreach (var it in first) {
            try {
                if ((it.Attributes & FileAttributes.ReparsePoint) != 0) continue;
                var dir = it as DirectoryInfo;
                if (dir == null) { var f = (FileInfo)it; loose.Bytes += f.Length; loose.Files++; consider(f); continue; }
                var e = new Entry { Name = dir.Name, Path = dir.FullName, IsFolder = true, Modified = dir.LastWriteTime };
                var stack = new Stack<DirectoryInfo>(); stack.Push(dir);
                while (stack.Count > 0) {
                    var d = stack.Pop(); FileSystemInfo[] items;
                    try { items = d.GetFileSystemInfos(); } catch { u.Denied++; continue; }
                    foreach (var x in items) {
                        try {
                            if ((x.Attributes & FileAttributes.ReparsePoint) != 0) continue;
                            var sd = x as DirectoryInfo; if (sd != null) { stack.Push(sd); continue; }
                            var f = (FileInfo)x; e.Bytes += f.Length; e.Files++; consider(f);
                        } catch { u.Denied++; }
                    }
                }
                u.Folders.Add(e);
            } catch { u.Denied++; }
        }
        if (loose.Files > 0) u.Folders.Add(loose);
        u.Folders.Sort((a, b) => b.Bytes.CompareTo(a.Bytes));
        top.Sort((a, b) => b.Bytes.CompareTo(a.Bytes)); if (top.Count > topFiles) top.RemoveRange(topFiles, top.Count - topFiles);
        u.TopFiles = top;
        foreach (var e in u.Folders) { u.Bytes += e.Bytes; u.Files += e.Files; }
        return u;
    }
}
'@
}

# 5.15.3 (user: "how do you know you're not deleting important things?"): files a person may have opened straight
# from an e-mail or a zip land in Temp. These types and Windows' "opened from a zip" folders are never touched there.
$script:YumTempKeepExt=@('.doc','.docx','.docm','.xls','.xlsx','.xlsm','.ppt','.pptx','.pdf','.odt','.ods','.odp','.rtf','.csv','.txt','.md','.psd','.ai','.indd','.blend','.dwg','.jpg','.jpeg','.png','.heic','.gif','.bmp','.tif','.tiff','.raw','.cr2','.nef','.mp4','.mov','.mkv','.avi','.mp3','.wav','.flac','.m4a','.zip','.rar','.7z','.eml','.msg','.vcf','.ics','.kdbx','.key','.pem','.pfx')
$script:YumTempKeepDirs=@('Temp1_','Temp2_','Temp3_','Rar$','7z')

function Get-YumDiskJunkCategories {
    # Every location is a cache or leftover that Windows or the program recreates. Advice: Clean = safe for
    # everyone; YourCall = safe, but with a small side effect explained in Effect.
    $la=$env:LOCALAPPDATA; $win=$env:windir; $pd=$env:ProgramData
    $chromium=@()
    foreach($b in @(@('Google Chrome','Google\Chrome\User Data'),@('Microsoft Edge','Microsoft\Edge\User Data'),@('Brave','BraveSoftware\Brave-Browser\User Data'),@('Vivaldi','Vivaldi\User Data'),@('Opera','..\Roaming\Opera Software\Opera Stable'),@('Opera GX','..\Roaming\Opera Software\Opera GX Stable'))){
        $base=[IO.Path]::GetFullPath((Join-Path $la $b[1]))
        if(-not (Test-Path -LiteralPath $base)){continue}
        # .NET, not Get-ChildItem: on Chrome's folder Get-ChildItem stopped at a locked sub-folder and returned 3 of 56.
        $sub=@(); try{ $sub=@([IO.Directory]::GetDirectories($base)) }catch{}
        $profiles=@($base)+@($sub | Where-Object { $n=[IO.Path]::GetFileName($_); $n -eq 'Default' -or $n -like 'Profile *' })
        foreach($p in $profiles){ foreach($c in 'Cache','Code Cache','GPUCache'){ $x=Join-Path $p $c; if(Test-Path -LiteralPath $x){ $chromium+=$x } } }
    }
    $firefox=@(); try{ $ff=Join-Path $la 'Mozilla\Firefox\Profiles'; if([IO.Directory]::Exists($ff)){ $firefox=@([IO.Directory]::GetDirectories($ff) | ForEach-Object { Join-Path $_ 'cache2' }) } }catch{}
    @(
        [pscustomobject]@{Key='UserTemp';Name='Temporary files (your account)';Advice='Clean';Admin=$false;Auto=$true;MinAgeHours=24;Patterns=@();SkipExt=$script:YumTempKeepExt;SkipDirs=$script:YumTempKeepDirs;Roots=@($env:TEMP)
            Why='Leftover files programs and installers put in your Temp folder and forgot to delete.';Effect='Nothing you will notice. Never touched here: files from the last 24 hours, files still in use, documents, pictures, videos, music and archives (you may have opened them from an e-mail), and files Windows unpacked when you opened a zip.'}
        [pscustomobject]@{Key='WindowsTemp';Name='Windows temporary files';Advice='Clean';Admin=$true;Auto=$true;MinAgeHours=24;Patterns=@();SkipExt=$script:YumTempKeepExt;SkipDirs=$script:YumTempKeepDirs;Roots=@((Join-Path $win 'Temp'))
            Why='Windows'' own temporary folder (updates, installers, services).';Effect='Nothing you will notice. Recent and in-use files are skipped.'}
        [pscustomobject]@{Key='Browser';Name='Web browser caches';Advice='Clean';Admin=$false;Auto=$false;MinAgeHours=0;Patterns=@();Roots=@($chromium+$firefox)
            Why='Copies of pictures and scripts from websites (Chrome, Edge, Brave, Opera, Vivaldi, Firefox). Only the cache: never cookies, saved passwords, history or open tabs - you stay signed in.';Effect='Websites load a little slower the first time you visit them again. Close the browser first for the biggest result (files in use are skipped).'}
        [pscustomobject]@{Key='Thumbnails';Name='Picture preview cache (thumbnails)';Advice='Clean';Admin=$false;Auto=$false;MinAgeHours=0;Patterns=@('thumbcache_*','iconcache_*');Roots=@((Join-Path $la 'Microsoft\Windows\Explorer'))
            Why='Small previews of your pictures and videos that File Explorer saved.';Effect='Folders with many pictures show previews a bit slower once while Windows rebuilds them. The ones Explorer is using right now are skipped.'}
        [pscustomobject]@{Key='Shaders';Name='Game shader caches (DirectX, NVIDIA, AMD)';Advice='YourCall';Admin=$false;Auto=$false;MinAgeHours=0;Patterns=@();Roots=@((Join-Path $la 'D3DSCache'),(Join-Path $la 'NVIDIA\DXCache'),(Join-Path $la 'NVIDIA\GLCache'),(Join-Path $la 'AMD\DxCache'),(Join-Path $la 'AMD\DxcCache'),(Join-Path $la 'AMD\GLCache'),(Join-Path $la 'AMD\VkCache'))
            Why='Graphics programs your games compiled and saved so they load faster.';Effect='Your call: games rebuild them, so the first minutes of the next game can stutter a little. Worth it when a driver update or a broken cache causes glitches.'}
        [pscustomobject]@{Key='Crash';Name='Crash dumps and error reports';Advice='Clean';Admin=$false;Auto=$true;MinAgeHours=0;Patterns=@();Roots=@((Join-Path $la 'CrashDumps'),(Join-Path $la 'Microsoft\Windows\WER\ReportArchive'),(Join-Path $la 'Microsoft\Windows\WER\ReportQueue'),(Join-Path $pd 'Microsoft\Windows\WER\ReportArchive'),(Join-Path $pd 'Microsoft\Windows\WER\ReportQueue'),(Join-Path $win 'Minidump'),(Join-Path $win 'LiveKernelReports'))
            Why='Memory snapshots and reports saved when a program or Windows crashed.';Effect='Nothing, unless a support person asked you for a crash dump. Some need administrator.'}
        [pscustomobject]@{Key='Update';Name='Windows Update downloads';Advice='Clean';Admin=$true;Auto=$true;MinAgeHours=240;Patterns=@();Roots=@((Join-Path $win 'SoftwareDistribution\Download'))
            Why='Update files Windows already installed. Windows downloads again whatever it still needs.';Effect='Nothing you will notice. Only files older than 10 days, so an update in progress is never touched.'}
        [pscustomobject]@{Key='Delivery';Name='Delivery Optimization cache';Advice='Clean';Admin=$true;Auto=$false;MinAgeHours=0;Patterns=@();Roots=@((Join-Path $win 'ServiceProfiles\NetworkService\AppData\Local\Microsoft\Windows\DeliveryOptimization\Cache'))
            Why='Pieces of Windows and Store updates kept to share with other PCs.';Effect='Nothing you will notice. Windows'' own clean-up command is used (same as Disk Cleanup).'}
        # 5.15.2 (user: "disk cleanup needs to be better, do research"): app caches, driver installer leftovers, old
        # Windows logs, and Windows' own deep clean-up (component store, old drivers, previous Windows) - the same tools
        # Microsoft documents for Disk Cleanup / DISM, never hand-deleting system folders.
        [pscustomobject]@{Key='AppCache';Name='App caches (Discord, Steam, Epic, Teams, VS Code)';Advice='Clean';Admin=$false;Auto=$false;MinAgeHours=0;Patterns=@()
            Roots=@((Join-Path $env:APPDATA 'discord\Cache'),(Join-Path $env:APPDATA 'discord\Code Cache'),(Join-Path $env:APPDATA 'discord\GPUCache'),(Join-Path $la 'Steam\htmlcache\Cache'),(Join-Path $la 'Steam\htmlcache\Code Cache'),(Join-Path $la 'Steam\htmlcache\GPUCache'),(Join-Path $la 'EpicGamesLauncher\Saved\webcache'),(Join-Path $la 'EpicGamesLauncher\Saved\webcache_4430'),(Join-Path $la 'EpicGamesLauncher\Saved\webcache_4147'),(Join-Path $la 'Packages\MSTeams_8wekyb3d8bbwe\LocalCache\Microsoft\MSTeams\EBWebView\Default\Cache'),(Join-Path $env:APPDATA 'Code\Cache'),(Join-Path $env:APPDATA 'Code\CachedData'),(Join-Path $env:APPDATA 'Code\Code Cache'))
            Why='Web pictures and scripts these apps saved to open faster. Only caches: never your messages, logins, downloads, games or settings. (Spotify is left out on purpose: its folder can hold the songs you downloaded for offline listening.)';Effect='The apps load things again the first time. Close the apps first for the biggest result; files in use are skipped.'}
        [pscustomobject]@{Key='DriverSetup';Name='Graphics driver installer leftovers';Advice='YourCall';Admin=$false;Auto=$false;MinAgeHours=24;Patterns=@()
            Roots=@((Join-Path $env:SystemDrive 'NVIDIA'),(Join-Path $env:SystemDrive 'AMD'),(Join-Path $pd 'NVIDIA Corporation\Downloader'))
            Why='Copies of NVIDIA / AMD driver installers that were unpacked or downloaded during driver updates (C:\NVIDIA, C:\AMD).';Effect='Your call: the installed driver is not touched. Use Open folder first - if you ever saved your own files in C:\AMD or C:\NVIDIA, do not clean this.'}
        [pscustomobject]@{Key='Logs';Name='Old Windows log files';Advice='Clean';Admin=$true;Auto=$true;MinAgeHours=720;Patterns=@('*.log','*.cab','*.etl')
            Roots=@((Join-Path $win 'Logs\CBS'),(Join-Path $win 'Logs\DISM'),(Join-Path $win 'Logs\MoSetup'),(Join-Path $win 'Panther\UnattendGC'))
            Why='Logs Windows writes while installing updates and features.';Effect='Nothing you will notice. Only logs older than 30 days.'}
        [pscustomobject]@{Key='WinComponents';Name='Windows Update clean-up (Windows'' own tool)';Advice='Clean';Admin=$true;Auto=$false;MinAgeHours=0;Patterns=@();Roots=@();Special='Dism'
            Why='Old versions of Windows components that newer updates replaced (the WinSxS store). Uses Microsoft''s own command (DISM StartComponentCleanup) - never deleting system files by hand.';Effect='Nothing you will notice; installed updates can still be uninstalled (YUMRAM does not use /ResetBase). Takes a few minutes; Windows works out the size while cleaning.'}
        [pscustomobject]@{Key='OldDrivers';Name='Old driver packages (Windows'' own Disk Cleanup)';Advice='YourCall';Admin=$true;Auto=$false;MinAgeHours=0;Patterns=@();Roots=@();Special='Cleanmgr';Handlers=@('Device Driver Packages')
            Why='Older driver versions Windows keeps after installing newer ones.';Effect='Your call: you can no longer roll a device back to its previous driver in Device Manager. Windows'' own Disk Cleanup does the work.'}
        [pscustomobject]@{Key='PreviousWindows';Name='Previous Windows installation (Windows.old)';Advice='YourCall';Admin=$true;Auto=$false;MinAgeHours=0;Patterns=@();Special='Cleanmgr';Handlers=@('Previous Installations','Upgrade Discarded Files','Windows Upgrade Log Files')
            Roots=@((Join-Path $env:SystemDrive 'Windows.old'),(Join-Path $env:SystemDrive '$Windows.~BT'),(Join-Path $env:SystemDrive '$Windows.~WS'))
            Why='The copy of your old Windows kept after a big Windows upgrade, so you can go back.';Effect='Your call: you can no longer go back to the previous Windows version (Windows removes it by itself after about 10 days). Windows'' own Disk Cleanup does the work.'}
        [pscustomobject]@{Key='Recycle';Name='Recycle Bin';Advice='YourCall';Admin=$false;Auto=$false;MinAgeHours=0;Patterns=@();Roots=@()
            Why='Files you deleted. They stay in the Recycle Bin until it is emptied.';Effect='Your call: emptying it is permanent - check there is nothing you still want first.'}
    )
}

function Get-YumOpenCacheApps {
    # 5.15.3: programs that are open now and hold caches in the chosen categories (their files in use are skipped).
    param([string[]]$Keys)
    $map=@{
        Browser=@(@('chrome','Chrome'),@('msedge','Edge'),@('brave','Brave'),@('opera','Opera'),@('vivaldi','Vivaldi'),@('firefox','Firefox'))
        AppCache=@(@('discord','Discord'),@('spotify','Spotify'),@('steamwebhelper','Steam'),@('EpicGamesLauncher','Epic Games'),@('ms-teams','Teams'),@('Code','VS Code'))
    }
    $running=@{}; foreach($p in @(Get-Process -ErrorAction SilentlyContinue)){ $running[$p.ProcessName.ToLowerInvariant()]=$true }
    $names=foreach($k in @($Keys)){ foreach($e in @($map[$k])){ if($null -ne $e -and $running.ContainsKey(([string]$e[0]).ToLowerInvariant())){ $e[1] } } }
    return @($names | Select-Object -Unique)
}

function Invoke-YumWindowsDiskCleanup {
    # Runs Windows' own Disk Cleanup (cleanmgr) for exactly these handlers, the documented automation way:
    # StateFlags on the chosen handlers + cleanmgr /sagerun, then the flags are removed again. Needs administrator.
    param([string[]]$Handlers)
    $base='HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VolumeCaches'
    $slot='StateFlags0777'; $set=@()
    try{
        foreach($h in $Handlers){ $k=Join-Path $base $h; if(Test-Path -LiteralPath $k){ Set-ItemProperty -LiteralPath $k -Name $slot -Value 2 -Type DWord; $set+=$k } }
        if($set.Count -eq 0){ return 'Windows has nothing of this kind on this PC.' }
        $p=Start-Process -FilePath (Join-Path $env:windir 'System32\cleanmgr.exe') -ArgumentList '/sagerun:777' -WindowStyle Hidden -PassThru
        if(-not $p.WaitForExit(1800000)){ return 'Windows'' Disk Cleanup is still running in the background.' }
        return ''
    } finally { foreach($k in $set){ try{ Remove-ItemProperty -LiteralPath $k -Name $slot -ErrorAction SilentlyContinue }catch{} } }
}

function Get-YumRecycleBinSize {
    try{ $sh=New-Object -ComObject Shell.Application; $rb=$sh.Namespace(10); $b=0L; $n=0; foreach($i in @($rb.Items())){ try{ $b+=[long]$i.Size; $n++ }catch{} }; return [pscustomobject]@{Bytes=$b;Files=$n} }catch{ return [pscustomobject]@{Bytes=0L;Files=0} }
}

function Measure-YumDiskJunk {
    # Read-only: how much each category holds right now (what a click would remove).
    Initialize-YumDiskWalkType
    $admin=$false; try{ $admin=Test-YumIsElevated }catch{}
    foreach($c in Get-YumDiskJunkCategories){
        $bytes=0L;$files=0L
        if($c.Key -eq 'Recycle'){ $rb=Get-YumRecycleBinSize; $bytes=[long]$rb.Bytes; $files=[long]$rb.Files }
        else { foreach($r in @($c.Roots)){ if(-not $r){continue}; $w=[YumDiskWalk]::WalkEx([string]$r,[string[]]@($c.Patterns),[double]$c.MinAgeHours,$false,(Get-YumCatList $c 'SkipExt'),(Get-YumCatList $c 'SkipDirs')); $bytes+=$w.Bytes; $files+=$w.Files } }
        $locked=([bool]$c.Admin -and -not $admin)
        $special=if($c.PSObject.Properties['Special']){[string]$c.Special}else{''}
        $windowsSizes=($special -and @($c.Roots).Count -eq 0)   # Windows works the size out itself while cleaning
        [pscustomobject]@{Key=$c.Key;Name=$c.Name;Advice=$c.Advice;Why=$c.Why;Effect=$c.Effect;Auto=[bool]$c.Auto;NeedsAdmin=[bool]$c.Admin;Locked=$locked;Bytes=$bytes;Files=$files;Special=$special;Roots=@($c.Roots | Where-Object { $_ -and [IO.Directory]::Exists([string]$_) })
            SizeText=$(if($windowsSizes){'Windows checks'}else{Format-YumBytes $bytes});Selected=($c.Advice -eq 'Clean' -and -not $locked -and $bytes -gt 0 -and -not $special)
            SubTitle=$(if($locked){'needs YUMRAM to run as administrator'}elseif($windowsSizes){'Windows'' own tool works out the size while cleaning (a few minutes)'}elseif($files -gt 0){('{0:N0} files' -f $files)}else{'nothing to clean'})}
    }
}

function Get-YumStorageSenseOn {
    # 5.15.5: is Windows' own Storage Sense turned on? (HKCU ...\StorageSense\Parameters\StoragePolicy, value "01").
    try{ return ([int](Get-ItemProperty -LiteralPath 'HKCU:\Software\Microsoft\Windows\CurrentVersion\StorageSense\Parameters\StoragePolicy' -Name '01' -ErrorAction Stop).'01' -eq 1) }catch{ return $false }
}

function Get-YumCatList {
    param($Category,[string]$Name)
    if($null -ne $Category.PSObject.Properties[$Name]){ return [string[]]@($Category.$Name) }
    return $null
}
function Get-YumDiskCleanupLogPath {
    $dir=if($script:Yum -and $script:Yum.ConfigDirectory){[string]$script:Yum.ConfigDirectory}else{[string]$script:Yum.Root}
    return (Join-Path $dir 'disk-cleanup-last.txt')
}

function Get-YumSum {
    # Strict-mode safe total of one numeric property (Measure-Object has no .Sum on an empty list).
    param($Items,[string]$Property)
    $t=0.0; foreach($i in @($Items)){ if($null -ne $i){ try{ $t+=[double]$i.$Property }catch{} } }; return $t
}
function Format-YumBytes {
    param([double]$Bytes)
    if($Bytes -ge 1GB){ return ('{0:N1} GB' -f ($Bytes/1GB)) }
    if($Bytes -ge 1MB){ return ('{0:N0} MB' -f ($Bytes/1MB)) }
    if($Bytes -ge 1KB){ return ('{0:N0} KB' -f ($Bytes/1KB)) }
    return ('{0:N0} bytes' -f $Bytes)
}

function Invoke-YumDiskCleanup {
    # Cleans the given categories. Returns one row per category with what was freed and what was skipped.
    param([string[]]$Keys,[switch]$Automatic)
    Initialize-YumDiskWalkType
    $admin=$false; try{ $admin=Test-YumIsElevated }catch{}
    $free0=0L; try{ $free0=[long](New-Object IO.DriveInfo ($env:SystemDrive)).AvailableFreeSpace }catch{}
    $deletedList=New-Object System.Collections.Generic.List[string]
    $out=foreach($c in @(Get-YumDiskJunkCategories | Where-Object { $Keys -contains $_.Key })){
        if([bool]$c.Admin -and -not $admin){ [pscustomobject]@{Key=$c.Key;Name=$c.Name;Freed=0L;Deleted=0L;Skipped=0L;Note='needs administrator'}; continue }
        $freed=0L;$del=0L;$skip=0L;$note=''
        try{
            $special=if($c.PSObject.Properties['Special']){[string]$c.Special}else{''}
            if($special -in @('Dism','Cleanmgr')){
                # Windows' own tools; what they freed = the Windows drive's free space before vs after.
                $d0=[long](New-Object IO.DriveInfo ($env:SystemDrive)).AvailableFreeSpace
                if($special -eq 'Dism'){
                    $p=Start-Process -FilePath (Join-Path $env:windir 'System32\Dism.exe') -ArgumentList '/Online','/Cleanup-Image','/StartComponentCleanup','/Quiet' -WindowStyle Hidden -PassThru -Wait
                    if($p.ExitCode -ne 0){ $note=('Windows'' tool ended with code {0}' -f $p.ExitCode) }
                } else { $note=Invoke-YumWindowsDiskCleanup -Handlers @($c.Handlers) }
                $freed=[math]::Max(0L,[long](New-Object IO.DriveInfo ($env:SystemDrive)).AvailableFreeSpace-$d0)
            }
            elseif($c.Key -eq 'Recycle'){ $rb=Get-YumRecycleBinSize; Clear-RecycleBin -Force -ErrorAction Stop; $freed=[long]$rb.Bytes; $del=[long]$rb.Files }
            elseif($c.Key -eq 'Delivery' -and (Get-Command Delete-DeliveryOptimizationCache -ErrorAction SilentlyContinue)){
                $before=0L; foreach($r in @($c.Roots)){ $before+=([YumDiskWalk]::Walk([string]$r,[string[]]@(),0,$false)).Bytes }
                Delete-DeliveryOptimizationCache -Force -ErrorAction Stop
                $after=0L; foreach($r in @($c.Roots)){ $after+=([YumDiskWalk]::Walk([string]$r,[string[]]@(),0,$false)).Bytes }
                $freed=[math]::Max(0L,$before-$after) }
            else { foreach($r in @($c.Roots)){ if(-not $r){continue}; $w=[YumDiskWalk]::WalkEx([string]$r,[string[]]@($c.Patterns),[double]$c.MinAgeHours,$true,(Get-YumCatList $c 'SkipExt'),(Get-YumCatList $c 'SkipDirs')); $freed+=$w.Freed; $del+=$w.Deleted; $skip+=$w.Skipped; foreach($dp in $w.DeletedPaths){ [void]$deletedList.Add(('{0}	{1}' -f $c.Name,$dp)) } } }
        }catch{ $note=$_.Exception.Message }
        [pscustomobject]@{Key=$c.Key;Name=$c.Name;Freed=$freed;Deleted=$del;Skipped=$skip;Note=$note}
    }
    $out=@($out)
    $total=[long](Get-YumSum $out 'Freed')
    # 5.15.3: an exact list of what was deleted (category, file, size) - Disk cleanup > "See what was deleted".
    try{
        $tab=[string][char]9
        $head=@(('YUMRAM disk cleanup {0}  -  freed {1}{2}' -f (Get-Date).ToString('yyyy-MM-dd HH:mm'),(Format-YumBytes $total),$(if($Automatic){' (automatic weekly clean)'}else{''})),('Category'+$tab+'File'+$tab+'Bytes'),'')
        $tools=@($out | Where-Object { $_.Freed -gt 0 -and $_.Deleted -eq 0 } | ForEach-Object { [string]$_.Name+$tab+'done by Windows'' own tool'+$tab+[string]$_.Freed })
        [IO.File]::WriteAllLines((Get-YumDiskCleanupLogPath),[string[]]($head+$tools+@($deletedList)),(New-Object Text.UTF8Encoding($true)))
    }catch{}
    $free1=0L; try{ $free1=[long](New-Object IO.DriveInfo ($env:SystemDrive)).AvailableFreeSpace }catch{}
    try{
        $script:Yum.Config['DiskCleanupLast']=(Get-Date).ToString('o')
        $script:Yum.Config['DiskCleanupFreedTotal']=[double]$script:Yum.Config['DiskCleanupFreedTotal']+$total
        [void](Save-YumConfig)
        Write-YumLog ('Disk cleanup{0}: freed {1} ({2}); Windows drive free {3} -> {4}.' -f $(if($Automatic){' (automatic)'}else{''}),(Format-YumBytes $total),(($out | Where-Object { $_.Freed -gt 0 } | ForEach-Object { '{0} {1}' -f $_.Name,(Format-YumBytes $_.Freed) }) -join ', '),(Format-YumBytes $free0),(Format-YumBytes $free1))
    }catch{}
    return [pscustomobject]@{Rows=$out;Freed=$total;DriveFreeBefore=$free0;DriveFreeAfter=$free1}
}

function Get-YumDiskUsage {
    # What's using a folder (WinDirStat-style): its biggest sub-folders and biggest files.
    param([string]$Path,[int]$TopFiles=40)
    Initialize-YumDiskWalkType
    $sw=[Diagnostics.Stopwatch]::StartNew()
    $u=[YumDiskWalk]::Analyze($Path,$TopFiles)
    $total=[math]::Max([double]1,[double]$u.Bytes)
    $folders=@($u.Folders | Select-Object -First 60 | ForEach-Object { [pscustomobject]@{Name=$_.Name;Path=$_.Path;IsFolder=$_.IsFolder;Bytes=$_.Bytes;SizeText=(Format-YumBytes $_.Bytes);Share=[math]::Round(100*$_.Bytes/$total,1);ShareText=('{0:N0}%' -f (100*$_.Bytes/$total));Files=$_.Files;FilesText=$(if([long]$_.Files -eq 1){'1 file'}else{'{0:N0} files' -f $_.Files})} })
    $files=@($u.TopFiles | ForEach-Object { [pscustomobject]@{Name=$_.Name;Path=$_.Path;Folder=[IO.Path]::GetDirectoryName($_.Path);Bytes=$_.Bytes;SizeText=(Format-YumBytes $_.Bytes);Modified=$_.Modified.ToString('yyyy-MM-dd')} })
    [pscustomobject]@{Path=$Path;Folders=$folders;TopFiles=$files;Bytes=$u.Bytes;Files=$u.Files;Denied=$u.Denied;Seconds=[math]::Round($sw.Elapsed.TotalSeconds,1)}
}

function Test-YumDiskAutoCleanDue {
    try{
        if(-not [bool]$script:Yum.Config['DiskAutoClean']){return $false}
        $last=[string]$script:Yum.Config['DiskCleanupLast']
        if([string]::IsNullOrWhiteSpace($last)){return $true}
        return (((Get-Date)-[datetime]$last).TotalDays -ge 7)
    }catch{ return $false }
}
