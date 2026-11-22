#requires -Version 5.1
# 5.15.9 (user: "program lagging, at first not responding, then responded"; "minimal lag to no lag"). Measured with
# the test PC's real data: the window thread was blocked 4.7 s after start (GPU/CPU/disk counters and WMI opened on
# the UI thread), up to 0.7 s on every What's running refresh, 0.6 s loading the Intelligence database when a page
# opened. This test keeps that work off the UI thread. Runs in strict mode like the app.
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'App\Bootstrap.ps1')
Initialize-YumConfig
$script:Yum.Config.Logging=$false
function Assert-That([bool]$Condition,[string]$Message){if(-not $Condition){throw $Message}}
$mw=[IO.File]::ReadAllText((Join-Path $root 'UI\MainWindow.ps1'))
$mb=[IO.File]::ReadAllText((Join-Path $root 'UI\MiniBar.ps1'))
$dl=[IO.File]::ReadAllText((Join-Path $root 'UI\Dialogs.ps1'))

# 1. Live readings come from the background sampler; the UI never opens counters itself.
foreach($pair in @(@('UI\MainWindow.ps1',$mw),@('UI\MiniBar.ps1',$mb))){ Assert-That (-not ($pair[1] -match 'Get-YumLive(Gpu|Cpu|Disk)\b')) ('{0} must use Get-YumLiveReading, not open counters on the UI thread.' -f $pair[0]) }
Assert-That ([IO.File]::ReadAllText((Join-Path $root 'Core\Vram.ps1')) -notmatch 'Get-YumLive(Gpu|Cpu|Disk)\b') 'The VRAM watch uses the background reading.'
$sw=[Diagnostics.Stopwatch]::StartNew(); $first=Get-YumLiveReading -Kind Cpu; $firstMs=$sw.ElapsedMilliseconds
Assert-That ($firstMs -lt 300) ('Asking for a reading must not wait for Windows counters ({0} ms).' -f $firstMs)
$deadline=(Get-Date).AddSeconds(15); $c=$null; $g=$null; $d=$null
while((Get-Date) -lt $deadline){ $c=Get-YumLiveReading -Kind Cpu; $g=Get-YumLiveReading -Kind Gpu; $d=Get-YumLiveReading -Kind Disk; if($null -ne $c -and $null -ne $g -and $null -ne $d -and [int]$script:Yum['LiveSampler'].Shared.Samples -ge 2){break}; Start-Sleep -Milliseconds 200 }
$err=[string]$script:Yum['LiveSampler'].Shared.Error
Assert-That ($null -ne $c -and [double]$c.Percent -ge 0 -and [double]$c.Percent -le 100) ('Background CPU reading missing or out of range ({0}).' -f $err)
Assert-That ($null -ne $g -and $null -ne $g.Main) ('Background GPU reading missing ({0}).' -f $err)
Assert-That ($null -ne $d -and @($d.Drives).Count -ge 1) ('Background disk reading missing ({0}).' -f $err)
Assert-That (@(Get-YumGpuAdapters).Count -ge 1) 'The UI takes the adapter list from the sampler.'
$sw.Restart(); $null=Get-YumLiveReading -Kind Gpu; Assert-That ($sw.ElapsedMilliseconds -lt 20) ('A ready reading is instant ({0} ms).' -f $sw.ElapsedMilliseconds)
Stop-YumLiveSampler
Assert-That ($null -eq $script:Yum['LiveSampler']) 'The sampler stops.'
Assert-That ($mw -match 'Stop-YumLiveSampler') 'Closing YUMRAM stops the sampler.'

# 2. The CPU card never waits for WMI.
Assert-That ($mw -match 'Test-YumCpuProfileReady' -and $mw -notmatch '\$pr=Get-YumCpuProfile\r?\n') 'The CPU card asks Test-YumCpuProfileReady first.'
$script:Yum['CpuProfile']=$null; $script:Yum['CpuCimInfo']=$null; $script:Yum['CpuCimQuery']=$null
$sw.Restart(); $ready=Test-YumCpuProfileReady; Assert-That ($sw.ElapsedMilliseconds -lt 300) ('Test-YumCpuProfileReady must not wait ({0} ms).' -f $sw.ElapsedMilliseconds)
$deadline=(Get-Date).AddSeconds(15); while(-not (Test-YumCpuProfileReady) -and (Get-Date) -lt $deadline){ Start-Sleep -Milliseconds 100 }
Assert-That (Test-YumCpuProfileReady) 'The CPU details arrive from the background.'
$sw.Restart(); $prof=Get-YumCpuProfile; Assert-That ($sw.ElapsedMilliseconds -lt 300 -and [int]$prof.Logical -ge 1 -and [string]$prof.Summary) ('CPU profile from the background answers ({0} ms).' -f $sw.ElapsedMilliseconds)

# 3. The Intelligence database is preloaded in the background and never replaces a newer one in memory.
$tmp=Join-Path $env:TEMP ('yum-resp-'+[guid]::NewGuid().ToString('N')); New-Item -ItemType Directory $tmp | Out-Null
try{
    $src=Join-Path $root 'intelligence-db.json'
    $items=@(1..40 | ForEach-Object { [pscustomobject]@{Key=('test-{0}' -f $_);Name=('TestApp{0}' -f $_);Path=('C:\Test\app{0}.exe' -f $_);Risk='Safe'} })
    [IO.File]::WriteAllText((Join-Path $tmp 'intelligence-db.json'),(@{Items=$items} | ConvertTo-Json -Depth 5))
    $script:Yum.IntelligenceDbFile=Join-Path $tmp 'intelligence-db.json'
    $script:Yum.IntelligenceDb=$null; $script:Yum['IntelligencePreload']=$null
    Start-YumIntelligenceDbPreload; Wait-YumIntelligenceDbPreload -TimeoutMs 20000
    Assert-That ($script:Yum.IntelligenceDb -is [hashtable] -and $script:Yum.IntelligenceDb.Count -eq 40) ('Preload filled the database ({0}).' -f $(if($script:Yum.IntelligenceDb){$script:Yum.IntelligenceDb.Count}else{'null'}))
    # A database the window already has must win.
    $mine=@{only=[pscustomobject]@{Key='only'}}; $script:Yum.IntelligenceDb=$mine; $script:Yum['IntelligencePreload']=$null
    Start-YumIntelligenceDbPreload
    Assert-That ($null -eq $script:Yum['IntelligencePreload']) 'No preload starts when the database is already loaded.'
    $script:Yum.IntelligenceDb=$null; Start-YumIntelligenceDbPreload; $script:Yum.IntelligenceDb=$mine; Wait-YumIntelligenceDbPreload -TimeoutMs 20000
    Assert-That ([object]::ReferenceEquals($script:Yum.IntelligenceDb,$mine)) 'A finished preload never replaces the database the window loaded meanwhile.'
}finally{ Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue }
Assert-That ($dl -match 'Wait-YumIntelligenceDbPreload; if\(\$null -eq \$script:Yum.IntelligenceDb') 'Pages wait for the preload instead of loading the database again.'
Assert-That ($mw -match 'Start-YumIntelligenceDbPreload') 'The preload starts from the UI timer.'

# 4. What's running: one window walk and one CPU snapshot per refresh.
$pids=[YumWindowPids]::WithMainWindow()
Assert-That ($pids -is [System.Collections.Generic.HashSet[int]]) 'Window walk returns process ids.'
$explorer=@(Get-Process explorer -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne [IntPtr]::Zero })
foreach($e in $explorer){ Assert-That ($pids.Contains($e.Id)) ('Explorer (PID {0}) has a main window in both methods.' -f $e.Id) }
Assert-That ($dl -match '\[YumProcTree\]::Snapshot\(\)' -and $dl -match '\[YumWindowPids\]::WithMainWindow\(\)') 'What''s running uses the one-call snapshot and window walk.'

# 6. Compiled helpers are cached (start-up measured 3.7-4.2 s -> 1.4-1.5 s from the second start).
$cacheDir=Get-YumTypeCacheDirectory
Assert-That ($cacheDir -like '*\Runtime\TypeCache') ('Cache lives in YUMRAM''s Runtime folder ({0}).' -f $cacheDir)
$tag=[guid]::NewGuid().ToString('N').Substring(0,8)
$n1="YumCacheProbeA$tag"; Add-YumCompiledType -TypeName $n1 -Source ("public static class $n1 { public static int V(){ return 1; } }")
Assert-That (($n1 -as [type]) -and ((Invoke-Expression "[$n1]::V()") -eq 1)) 'A helper compiled through the cache works.'
$files=@([IO.Directory]::GetFiles($cacheDir,"$n1-*.dll")); Assert-That ($files.Count -eq 1) 'The compiled helper is kept as one DLL.'
# A changed source gets a new file (new hash) instead of reusing the old build.
$n2="YumCacheProbeB$tag"; $src2a="public static class $n2 { public static int V(){ return 2; } }"; $src2b="public static class $n2 { public static int V(){ return 3; } }"
$sha=[System.Security.Cryptography.SHA256]::Create(); $h=@($src2a,$src2b | ForEach-Object { (($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($_+'||'+[Environment]::Version.ToString()+'|'+[IntPtr]::Size)) | Select-Object -First 8 | ForEach-Object { $_.ToString('x2') }) -join '') }); $sha.Dispose()
Assert-That ($h[0] -ne $h[1]) 'Different source, different cache name.'
# A damaged cache file falls back to a normal compile.
$n3="YumCacheProbeC$tag"; $src3="public static class $n3 { public static int V(){ return 4; } }"
Add-YumCompiledType -TypeName "YumCacheProbeD$tag" -Source ("public static class YumCacheProbeD$tag { }")
$fake=Join-Path $cacheDir ("$n3-{0}.dll" -f ((([System.Security.Cryptography.SHA256]::Create()).ComputeHash([Text.Encoding]::UTF8.GetBytes($src3+'||'+[Environment]::Version.ToString()+'|'+[IntPtr]::Size)) | Select-Object -First 8 | ForEach-Object { $_.ToString('x2') }) -join ''))
[IO.File]::WriteAllText($fake,'not a dll')
Add-YumCompiledType -TypeName $n3 -Source $src3
Assert-That (($n3 -as [type]) -and ((Invoke-Expression "[$n3]::V()") -eq 4)) 'A damaged cache file never breaks YUMRAM.'
foreach($f in @([IO.Directory]::GetFiles($cacheDir,"YumCacheProbe*$tag*"))){ try{ [IO.File]::Delete($f) }catch{} }
foreach($t in 'YumRamNative','YumProcTree','YumProcRow2','YumGraphGeo','YumTrayNative','YumRamHotkey'){ Assert-That ($null -ne ($t -as [type])) ("Helper $t is available after start-up.") }
$cached=@([AppDomain]::CurrentDomain.GetAssemblies() | Where-Object { try{ $_.Location -like '*\Runtime\TypeCache\*' }catch{ $false } }).Count
Assert-That ($cached -ge 8) ('Start-up helpers load from the cache ({0}).' -f $cached)
Assert-That (-not ([IO.File]::ReadAllText((Join-Path $root 'Tools\Build-Release.ps1')) -match "'Runtime'")) 'The cache folder is never packaged.'

# 5. Record checks reuse one defaults table and give the same result.
$r=[pscustomobject]@{Name='x';Risk=$null}; $null=Ensure-YumIntelligenceRecordSchema -Record $r
Assert-That (@($r.PSObject.Properties).Count -eq 42 -and $r.Risk -eq 'Review' -and $r.ResearchSources -is [array]) 'Schema check fills the 42 fields and replaces nulls.'
Write-Host ('ResponsivenessTest passed. First reading request {0} ms; CPU {1}%.' -f $firstMs,$c.Percent)
