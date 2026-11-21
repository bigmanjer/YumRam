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
Assert-That (-not [bool]$script:Yum.Config['DiskAutoClean']) 'Automatic clean is off by default.'
$sw=[Diagnostics.Stopwatch]::StartNew(); $rows=@(Measure-YumDiskJunk); $ms=$sw.ElapsedMilliseconds
Assert-That ($rows.Count -eq $cats.Count) 'Every category is measured.'
$x=[IO.File]::ReadAllText((Join-Path $root 'UI\Xaml\MainWindow.xaml')); Assert-That ($x -match 'x:Name="DiskCleanup"') 'Sidebar has Disk cleanup.'
Write-Host ('DiskCleanupTest passed. Measured {0} categories in {1} ms; this PC could free {2}.' -f $rows.Count,$ms,(Format-YumBytes (Get-YumSum @($rows | Where-Object { -not $_.Locked }) 'Bytes')))
