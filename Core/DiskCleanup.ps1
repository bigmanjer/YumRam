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
    public sealed class Result { public long Bytes; public long Files; public long Skipped; public long Deleted; public long Freed; }
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
    public static Result Walk(string root, string[] patterns, double minAgeHours, bool delete) {
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
                    if (sub != null) { stack.Push(sub); dirs.Add(sub); continue; }
                    var f = (FileInfo)it;
                    if (!Match(f.Name, patterns)) continue;
                    if (f.LastWriteTimeUtc > cutoff) continue;
                    r.Bytes += f.Length; r.Files++;
                    if (delete) {
                        try { if ((f.Attributes & FileAttributes.ReadOnly) != 0) f.Attributes = FileAttributes.Normal; long len = f.Length; f.Delete(); r.Deleted++; r.Freed += len; }
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
        [pscustomobject]@{Key='UserTemp';Name='Temporary files (your account)';Advice='Clean';Admin=$false;Auto=$true;MinAgeHours=24;Patterns=@();Roots=@($env:TEMP)
            Why='Leftover files programs and installers put in your Temp folder and forgot to delete.';Effect='Nothing you will notice. Files from the last 24 hours and files still in use are skipped.'}
        [pscustomobject]@{Key='WindowsTemp';Name='Windows temporary files';Advice='Clean';Admin=$true;Auto=$true;MinAgeHours=24;Patterns=@();Roots=@((Join-Path $win 'Temp'))
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
        [pscustomobject]@{Key='Recycle';Name='Recycle Bin';Advice='YourCall';Admin=$false;Auto=$false;MinAgeHours=0;Patterns=@();Roots=@()
            Why='Files you deleted. They stay in the Recycle Bin until it is emptied.';Effect='Your call: emptying it is permanent - check there is nothing you still want first.'}
    )
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
        else { foreach($r in @($c.Roots)){ if(-not $r){continue}; $w=[YumDiskWalk]::Walk([string]$r,[string[]]@($c.Patterns),[double]$c.MinAgeHours,$false); $bytes+=$w.Bytes; $files+=$w.Files } }
        $locked=([bool]$c.Admin -and -not $admin)
        [pscustomobject]@{Key=$c.Key;Name=$c.Name;Advice=$c.Advice;Why=$c.Why;Effect=$c.Effect;Auto=[bool]$c.Auto;NeedsAdmin=[bool]$c.Admin;Locked=$locked;Bytes=$bytes;Files=$files
            SizeText=(Format-YumBytes $bytes);Selected=($c.Advice -eq 'Clean' -and -not $locked -and $bytes -gt 0)
            SubTitle=$(if($locked){'needs YUMRAM to run as administrator'}elseif($files -gt 0){('{0:N0} files' -f $files)}else{'nothing to clean'})}
    }
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
    $out=foreach($c in @(Get-YumDiskJunkCategories | Where-Object { $Keys -contains $_.Key })){
        if([bool]$c.Admin -and -not $admin){ [pscustomobject]@{Key=$c.Key;Name=$c.Name;Freed=0L;Deleted=0L;Skipped=0L;Note='needs administrator'}; continue }
        $freed=0L;$del=0L;$skip=0L;$note=''
        try{
            if($c.Key -eq 'Recycle'){ $rb=Get-YumRecycleBinSize; Clear-RecycleBin -Force -ErrorAction Stop; $freed=[long]$rb.Bytes; $del=[long]$rb.Files }
            elseif($c.Key -eq 'Delivery' -and (Get-Command Delete-DeliveryOptimizationCache -ErrorAction SilentlyContinue)){
                $before=0L; foreach($r in @($c.Roots)){ $before+=([YumDiskWalk]::Walk([string]$r,[string[]]@(),0,$false)).Bytes }
                Delete-DeliveryOptimizationCache -Force -ErrorAction Stop
                $after=0L; foreach($r in @($c.Roots)){ $after+=([YumDiskWalk]::Walk([string]$r,[string[]]@(),0,$false)).Bytes }
                $freed=[math]::Max(0L,$before-$after) }
            else { foreach($r in @($c.Roots)){ if(-not $r){continue}; $w=[YumDiskWalk]::Walk([string]$r,[string[]]@($c.Patterns),[double]$c.MinAgeHours,$true); $freed+=$w.Freed; $del+=$w.Deleted; $skip+=$w.Skipped } }
        }catch{ $note=$_.Exception.Message }
        [pscustomobject]@{Key=$c.Key;Name=$c.Name;Freed=$freed;Deleted=$del;Skipped=$skip;Note=$note}
    }
    $out=@($out)
    $total=[long](Get-YumSum $out 'Freed')
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
