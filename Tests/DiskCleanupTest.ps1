#requires -Version 5.1
# 5.15.2 disk cleanup safety. Cleaning runs ONLY on a throwaway folder made here; on the real PC it only measures.
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'App\Bootstrap.ps1')
Initialize-YumConfig
$script:Yum.Config.Logging=$false
function Assert-That([bool]$Condition,[string]$Message){if(-not $Condition){throw $Message}}
Initialize-YumDiskWalkType

$box=Join-Path $env:TEMP ('yum-disktest-'+[guid]::NewGuid().ToString('N'))
$precious=Join-Path $env:TEMP ('yum-precious-'+[guid]::NewGuid().ToString('N'))
try{
    New-Item -ItemType Directory -Path (Join-Path $box 'sub\deeper') -Force | Out-Null
    New-Item -ItemType Directory -Path $precious -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $precious 'keep-me.txt') -Value 'precious'
    # A junction inside the junk folder that points at a folder with a precious file: it must never be followed.
    cmd /c mklink /J (Join-Path $box 'link-to-precious') $precious | Out-Null
    $old=(Get-Date).AddDays(-3)
    foreach($f in 'a.tmp','sub\b.tmp','sub\deeper\c.log','thumbcache_1.db','other.db'){ $p=Join-Path $box $f; Set-Content -LiteralPath $p -Value ('x'*1000); (Get-Item -LiteralPath $p).LastWriteTime=$old }
    Set-Content -LiteralPath (Join-Path $box 'new.tmp') -Value 'fresh'   # written now: younger than the age limit

    $m=[YumDiskWalk]::Walk($box,[string[]]@(),24,$false)
    Assert-That ($m.Files -eq 5) ('Measure should count the 5 old files (not the new one, not behind the junction), got {0}' -f $m.Files)
    $p=[YumDiskWalk]::Walk($box,[string[]]@('thumbcache_*'),0,$false)
    Assert-That ($p.Files -eq 1) ('Pattern thumbcache_* should match 1 file, got {0}' -f $p.Files)

    $c=[YumDiskWalk]::Walk($box,[string[]]@(),24,$true)
    Assert-That ($c.Deleted -eq 5) ('Clean should delete the 5 old files, deleted {0}' -f $c.Deleted)
    Assert-That (Test-Path -LiteralPath (Join-Path $precious 'keep-me.txt')) 'A file behind a junction was deleted - the walker followed a link!'
    Assert-That (Test-Path -LiteralPath (Join-Path $box 'new.tmp')) 'A file younger than the age limit was deleted.'
    Assert-That (-not (Test-Path -LiteralPath (Join-Path $box 'sub\deeper'))) 'Emptied sub-folders should be removed.'
    Assert-That (Test-Path -LiteralPath $box) 'The category folder itself must stay.'

    # File in use is skipped, not an error.
    $lockFile=Join-Path $box 'locked.tmp'; Set-Content -LiteralPath $lockFile -Value 'x'; (Get-Item $lockFile).LastWriteTime=$old
    $fs=[IO.File]::Open($lockFile,'Open','Read','None')
    try{ $c2=[YumDiskWalk]::Walk($box,[string[]]@(),24,$true); Assert-That ($c2.Skipped -ge 1 -and (Test-Path -LiteralPath $lockFile)) 'A file in use must be skipped.' }finally{ $fs.Dispose() }
    # 5.15.3 real-PC test: a file open the way Chrome opens its cache (others may read, write AND delete) used to be
    # "deleted" while still open - its space only came back when Chrome closed, so YUMRAM over-reported. Must be skipped.
    $shared=Join-Path $box 'chrome-style.tmp'; Set-Content -LiteralPath $shared -Value ('x'*5000); (Get-Item $shared).LastWriteTime=$old
    $fs2=New-Object IO.FileStream($shared,[IO.FileMode]::Open,[IO.FileAccess]::Read,([IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete))
    try{ $c3=[YumDiskWalk]::Walk($box,[string[]]@('chrome-style.tmp'),24,$true); Assert-That ($c3.Deleted -eq 0 -and $c3.Freed -eq 0 -and $c3.Skipped -ge 1) 'A file another program has open (sharing delete) must be skipped, not counted as freed.' }finally{ $fs2.Dispose() }
    Assert-That (-not (Test-Path -LiteralPath $shared) -or (Get-Item -LiteralPath $shared).Length -gt 0) 'The open file must be left alone.'
    $c4=[YumDiskWalk]::Walk($box,[string[]]@('chrome-style.tmp'),24,$true); Assert-That ($c4.Deleted -eq 1) 'Once the program closes the file, it is cleaned.'

    # 5.15.3 ("how do you know you're not deleting important things?"): in Temp, documents / pictures / archives a
    # person may have opened from an e-mail, and files Windows unpacked from a zip ("Temp1_..."), are never touched.
    $tbox=Join-Path $box 'tempcheck'; New-Item -ItemType Directory -Path (Join-Path $tbox 'Temp1_holiday.zip') -Force | Out-Null
    foreach($f in 'report.docx','photo.jpg','invoice.pdf','Temp1_holiday.zip\note.txt','setup-leftover.tmp','cache.bin'){ $p=Join-Path $tbox $f; Set-Content -LiteralPath $p -Value 'x'; (Get-Item -LiteralPath $p).LastWriteTime=$old }
    $userTemp=@(Get-YumDiskJunkCategories | Where-Object Key -eq 'UserTemp')[0]
    $wx=[YumDiskWalk]::WalkEx($tbox,[string[]]@(),24,$true,[string[]]$userTemp.SkipExt,[string[]]$userTemp.SkipDirs)
    Assert-That ($wx.Deleted -eq 2) ('Only the 2 real leftovers may go, deleted {0}' -f $wx.Deleted)
    foreach($f in 'report.docx','photo.jpg','invoice.pdf','Temp1_holiday.zip\note.txt'){ Assert-That (Test-Path -LiteralPath (Join-Path $tbox $f)) ("A file a person may want was deleted from Temp: $f") }
    Assert-That (@($wx.DeletedPaths).Count -eq 2) 'The clean must record exactly what it deleted.'

    # Folder analysis.
    $u=Get-YumDiskUsage -Path $root -TopFiles 5
    Assert-That (@($u.Folders).Count -ge 3 -and [double]$u.Bytes -gt 0 -and @($u.TopFiles).Count -ge 1) 'Folder analysis returns folders, a total and biggest files.'
    Assert-That (@($u.Folders)[0].Bytes -ge @($u.Folders)[-1].Bytes) 'Folders are sorted biggest first.'
}finally{
    try{ cmd /c rmdir (Join-Path $box 'link-to-precious') 2>$null | Out-Null }catch{}
    Remove-Item -LiteralPath $box -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $precious -Recurse -Force -ErrorAction SilentlyContinue
}

# Categories: only known cache / temp folders, nothing personal.
$cats=@(Get-YumDiskJunkCategories)
Assert-That ($cats.Count -ge 8) 'Expected the cleanup categories.'
$bad=@($cats | ForEach-Object { @($_.Roots) } | Where-Object { $_ -match '(?i)\\(Documents|Desktop|Downloads|Pictures|Music|Videos)(\\|$)|Cookies|Login Data|History|Bookmarks' })
Assert-That ($bad.Count -eq 0) ('A category points at personal data: {0}' -f ($bad -join ', '))
foreach($c in $cats){ Assert-That ([string]$c.Why -and [string]$c.Effect -and $c.Advice -in @('Clean','YourCall')) ('Category {0} needs a plain explanation and advice.' -f $c.Key) }
Assert-That (@($cats | Where-Object { $_.Auto -and $_.Key -in @('Recycle','Browser','Shaders') }).Count -eq 0) 'The weekly automatic clean never empties the Recycle Bin, browser or game caches.'
# 5.16.2: checked against the shipped defaults - a developer's local config.json may have it on.
$dflt=Get-Content (Join-Path $root 'Config\default-config.json') -Raw | ConvertFrom-Json
Assert-That ($null -eq $dflt.PSObject.Properties['DiskAutoClean'] -or -not [bool]$dflt.DiskAutoClean) 'Automatic clean is off by default.'
Assert-That (@($cats | Where-Object { @($_.Roots) -match '(?i)spotify' }).Count -eq 0) 'Spotify is left out: its folder can hold downloaded songs.'
Assert-That ((@($cats | Where-Object Key -eq 'DriverSetup')[0]).Advice -eq 'YourCall') 'Driver installer folders are your call, not ticked by default.'
Assert-That ((@($cats | Where-Object Key -eq 'UserTemp')[0]).SkipExt -contains '.docx') 'Temp cleaning skips documents.'
# 5.15.8 additions: never what Windows needs to repair/uninstall apps, never package stores projects link to.
$allRoots=@($cats | ForEach-Object { @($_.Roots) } | ForEach-Object { [string]$_ })
Assert-That (@($allRoots | Where-Object { $_ -match '(?i)\\Package Cache(\\|$)|\\Installer(\\|$)|\$PatchCache\$|\\pnpm\\store|\\go\\pkg\\mod|\\\.m2\\|\\\.gradle\\' }).Count -eq 0) 'Never the installer caches Windows needs to repair or uninstall apps, nor package stores projects use.'
foreach($k in 'StoreTemp','DevCaches','UpdaterDownloads'){ $c=@($cats | Where-Object Key -eq $k)[0]; Assert-That ($null -ne $c -and -not $c.Auto) ('New category {0} exists and is not part of the weekly automatic clean.' -f $k) }
Assert-That (@(@($cats | Where-Object Key -eq 'StoreTemp')[0].Roots | Where-Object { $_ -notmatch '(?i)\\AC\\(Temp|INetCache)$' }).Count -eq 0) 'Store apps: only their Temp and web-cache folders.'
$ud=@($cats | Where-Object Key -eq 'UpdaterDownloads')[0]; Assert-That ($ud.Admin -and $ud.MinAgeHours -ge 168) 'Updater downloads: administrator and only files older than 7 days.'
Assert-That ((@($cats | Where-Object Key -eq 'DevCaches')[0]).Advice -eq 'YourCall') 'Developer caches are your call (the next build is slower once).'
$logTmp=Join-Path $env:TEMP ('yum-dlog-'+[guid]::NewGuid().ToString('N')); New-Item -ItemType Directory $logTmp | Out-Null
$oldDir=$script:Yum.ConfigDirectory; $script:Yum.ConfigDirectory=$logTmp
try{ [void](Invoke-YumDiskCleanup -Keys @()); Assert-That (Test-Path -LiteralPath (Get-YumDiskCleanupLogPath)) 'Each clean writes the "what was deleted" list.' }finally{ $script:Yum.ConfigDirectory=$oldDir; Remove-Item -LiteralPath $logTmp -Recurse -Force -ErrorAction SilentlyContinue }
$dx=[IO.File]::ReadAllText((Join-Path $root 'UI\Xaml\DiskCleanup.xaml')); Assert-That ($dx -match 'x:Name="OpenFolder"' -and $dx -match 'x:Name="SeeDeleted"') 'Disk cleanup lets you look first and see what was deleted.'
Assert-That ((Get-YumStorageSenseOn) -is [bool]) 'Storage Sense status is read.'
Assert-That ([IO.File]::ReadAllText((Join-Path $root 'UI\Xaml\DiskCleanup.xaml')) -match 'x:Name="StorageSense"') 'Disk cleanup shows Windows Storage Sense.'
$sw=[Diagnostics.Stopwatch]::StartNew(); $rows=@(Measure-YumDiskJunk); $ms=$sw.ElapsedMilliseconds
Assert-That ($rows.Count -eq $cats.Count) 'Every category is measured.'
$x=[IO.File]::ReadAllText((Join-Path $root 'UI\Xaml\MainWindow.xaml')); Assert-That ($x -match 'x:Name="DiskCleanup"') 'Sidebar has Disk cleanup.'
Write-Host ('DiskCleanupTest passed. Measured {0} categories in {1} ms; this PC could free {2}.' -f $rows.Count,$ms,(Format-YumBytes (Get-YumSum @($rows | Where-Object { -not $_.Locked }) 'Bytes')))
