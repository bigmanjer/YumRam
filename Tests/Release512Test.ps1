#requires -Version 5.1
# 5.12: leak alerts (heuristic + a real leaking process), memory combining, 12 h history, no-prompt
# elevation choices, per-program rules.
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'App\Bootstrap.ps1')
Initialize-YumConfig
$script:Yum.Config.Logging=$false
function Assert-That([bool]$Condition,[string]$Message){if(-not $Condition){throw $Message}}
$tmp=Join-Path $env:TEMP ('yum-512-'+[guid]::NewGuid().ToString('N'));New-Item -ItemType Directory $tmp|Out-Null
$script:Yum.ConfigDirectory=$tmp;$script:Yum.ConfigFile=(Join-Path $tmp 'config.json')
try{
# 1. Leak heuristic.
$steady=[double[]](0..11 | ForEach-Object { 300+$_*50 })
Assert-That ($null -ne (Test-YumLeakTrend -Samples $steady)) 'Steady growth 300 -> 850 MB must be flagged.'
Assert-That ($null -eq (Test-YumLeakTrend -Samples ([double[]](1..12 | ForEach-Object { 2000 })))) 'A big but stable program is not a leak.'
Assert-That ($null -eq (Test-YumLeakTrend -Samples ([double[]](300,900,300,900,300,900,300,900,300,900,300,950)))) 'Up-and-down usage is not a leak.'
Assert-That ($null -eq (Test-YumLeakTrend -Samples ([double[]](0..11 | ForEach-Object { 300+$_*20 })))) 'Growth under 400 MB is not flagged.'
Assert-That ($null -eq (Test-YumLeakTrend -Samples ([double[]]((0..10 | ForEach-Object { 300+$_*60 })+@(400))))) 'A program that already dropped back is not flagged.'

# 2. A real leaking process is flagged (sampling sped up to 1 s for the test).
$src=Join-Path $tmp 'yumleak.cs'
Set-Content -LiteralPath $src -Encoding ASCII -Value 'using System;using System.Collections.Generic;using System.Threading;static class L{static void Main(){var k=new List<byte[]>();for(int i=0;i<40;i++){var b=new byte[40*1024*1024];for(int j=0;j<b.Length;j+=4096)b[j]=1;k.Add(b);Thread.Sleep(400);}Thread.Sleep(30000);GC.KeepAlive(k);}}'
& (Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe') /nologo /out:"$(Join-Path $tmp 'yumleak.exe')" $src | Out-Null
$leak=Start-Process -FilePath (Join-Path $tmp 'yumleak.exe') -PassThru -WindowStyle Hidden
try{
    $script:Yum.Config['LeakSampleSeconds']=1
    $st=@{}
    for($i=0;$i -lt 16;$i++){
        $byId=@{};foreach($p in @(Get-Process -ErrorAction SilentlyContinue)){$byId[[int]$p.Id]=$p}
        Update-YumLeakWatch -ById $byId -State $st
        Start-Sleep -Milliseconds 1050
    }
    Assert-That ($st['Growing'].ContainsKey('yumleak')) ('The leaking test program must be flagged; samples: {0}' -f (($st['LeakHist']['yumleak']) -join ','))
    Assert-That (@($st['LeakNotices'] | Where-Object { $_.Name -eq 'yumleak' }).Count -eq 1) 'Exactly one notice per program.'
}finally{try{$leak.Kill()}catch{}}

# 3. Memory combining is wired and safe without administrator.
$c=Invoke-YumCombineMemory
Assert-That ($null -ne $c -and $c.PSObject.Properties['PagesCombined']) 'Combining must return a result.'
if(-not (Test-YumIsElevated)){Assert-That (-not $c.Success) 'Without administrator Windows must refuse (and YUMRAM must not crash).'}
$mr=Get-Content -Raw (Join-Path $root 'Core\MemoryReclaim.ps1')
Assert-That ($mr -match 'Invoke-YumCombineMemory' -and $mr -match "TotalMinutes -ge 15") 'Deep always / Free RAM now every 15 min must combine.'

# 4. History: 12 h window, saved as 1-minute averages and read back.
. (Join-Path $root 'UI\MainWindow.ps1')
$script:Yum['History']=$null;$script:Yum['HistoryLast']=$null
Add-YumHistoryPoint -Mem 60 -Avail 40 -Cpu 10 -Gpu 1
$script:Yum['HistoryLast']=(Get-Date).AddSeconds(-6); Add-YumHistoryPoint -Mem 62 -Avail 38 -Cpu 20 -Gpu 2
Assert-That ($script:Yum['History'].Count -eq 2) 'History must record a point every 5 s.'
$script:Yum['History'].Insert(0,[pscustomobject]@{T=(Get-Date).AddHours(-13);Mem=1;Avail=1;Cpu=1;Gpu=1})
Save-YumHistory; Import-YumHistory
Assert-That ($script:Yum['History'].Count -ge 1 -and @($script:Yum['History'] | Where-Object { [datetime]$_.T -lt (Get-Date).AddHours(-12) }).Count -eq 0) 'History older than 12 h must be dropped; the rest survives a restart.'
$b=Get-YumHistorySeries -WindowSeconds 300 -Buckets 60
Assert-That (@($b).Count -ge 1 -and [double]@($b)[0].Mem -gt 50) 'History must bucket into the 5-minute view.'
$xaml=Get-Content -Raw (Join-Path $root 'UI\Xaml\MainWindow.xaml')
Assert-That ($xaml -match 'x:Name="Range12h"' -and $xaml -notmatch 'Range24h') 'Ranges are 30 s / 5 min / 1 h / 12 h.'

# 5. Administrator choices.
Assert-That ((Get-YumElevationMode) -eq 'Ask') 'Default is to ask.'
if((Get-YumElevatedTask) -and -not (Test-YumIsElevated)){
    # The PC's own (installed) YUMRAM has the no-prompt task: removing it needs administrator, and the test must
    # never change the user's real setup. Check that YUMRAM says so clearly instead.
    $r=Set-YumElevationChoice -Mode 'Never' -StartWithWindows $false
    Assert-That (-not $r.Success -and [string]$r.Message -match 'administrator') 'Without administrator, removing an existing no-prompt task is refused with a clear reason.'
    Write-Host 'Note: a no-prompt task from the installed YUMRAM exists; the "Never" switch was checked for its clear refusal only.'
} else {
    $r=Set-YumElevationChoice -Mode 'Never' -StartWithWindows $false
    Assert-That ($r.Success -and (Get-YumElevationMode) -eq 'Never') 'Never must apply without administrator.'
}
$man=Get-Content -Raw (Join-Path $root 'Launcher\YUMRAM.manifest')
Assert-That ($man -match 'level="asInvoker"') 'YUMRAM.exe must not force a UAC prompt; YUMRAM decides (task / ask / never).'
$mw=Get-Content -Raw (Join-Path $root 'UI\MainWindow.ps1')
Assert-That ($mw -match 'Start-YumViaElevatedTask' -and $mw -match "-eq 'Never'") 'Startup must use the no-prompt task or skip elevation when asked to.'

# 6. Per-program rules are wired.
$dl=Get-Content -Raw (Join-Path $root 'UI\Dialogs.ps1')
Assert-That ($dl -match 'RuleNeverTrim' -and $dl -match "'ProtectedProcesses'" -and $dl -match "'CpuBalanceExclusions'") 'Never trim / never hold back rules must save to the lists the engines read.'
Write-Host 'Release 5.12 test passed (leak flagged, combining wired, 12 h history, elevation choices, rules).'
}finally{
    try{ $k=[Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Software\Microsoft\Windows\CurrentVersion\Run',$true); if($k){ $v=[string]$k.GetValue('YUMRAM',''); if($v -like ('*{0}*' -f $root)){$k.DeleteValue('YUMRAM',$false)}; $k.Close() } }catch{}
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
}
