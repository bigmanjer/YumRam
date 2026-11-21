#requires -Version 5.1
# 5.15 game CPU work: one-call process snapshot, fast and strict-mode-safe CPU care checks, and the learned
# (benchmark-based) level while gaming. Uses only a test hog and a test "game" (ping), never real programs.
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'App\Bootstrap.ps1')      # sets Set-StrictMode -Version Latest, like the app
Initialize-YumConfig
$script:Yum.Config.Logging=$false
function Assert-That([bool]$Condition,[string]$Message){if(-not $Condition){throw $Message}}
$tmp=Join-Path $env:TEMP ('yum-games-'+[guid]::NewGuid().ToString('N'));New-Item -ItemType Directory $tmp|Out-Null
$script:Yum.ConfigDirectory=$tmp;$script:Yum.ConfigFile=(Join-Path $tmp 'config.json')

# 1. Decision rule.
$kn=[pscustomobject]@{Knowledge=@(
    [pscustomobject]@{GameClass='Medium';Hog='Saturating';Low1ByLevel=[pscustomobject]@{Off=3;Gentle=8;Balanced=18;Strong=102}}
    [pscustomobject]@{GameClass='Medium';Hog='Bursty';Low1ByLevel=[pscustomobject]@{Off=6;Gentle=8;Balanced=14;Strong=11}}
    [pscustomobject]@{GameClass='Heavy';Hog='Saturating';Low1ByLevel=[pscustomobject]@{Off=3;Gentle=7;Balanced=22.1;Strong=22.5}}
    [pscustomobject]@{GameClass='Light';Hog='Saturating';Low1ByLevel=[pscustomobject]@{Off=90;Gentle=20;Balanced=21;Strong=20}})}
$a=Get-YumGamingAdvice -Knowledge $kn -CurrentLevel 'Balanced' -GameAloneShare 45 -OtherShare 70
Assert-That ($null -ne $a -and $a.Level -eq 'Strong') 'Medium game + heavy load: Strong was clearly better -> Strong.'
Assert-That ($null -eq (Get-YumGamingAdvice -Knowledge $kn -CurrentLevel 'Balanced' -GameAloneShare 50 -OtherShare 30)) 'Medium game + partial load: Balanced already best (falls back to Bursty data) -> no change.'
Assert-That ($null -eq (Get-YumGamingAdvice -Knowledge $kn -CurrentLevel 'Balanced' -GameAloneShare 70 -OtherShare 70)) 'Heavy: Strong only 2 % better -> under the 5 % margin, no change.'
Assert-That ($null -eq (Get-YumGamingAdvice -Knowledge $kn -CurrentLevel 'Gentle' -GameAloneShare 10 -OtherShare 70) -or (Get-YumGamingAdvice -Knowledge $kn -CurrentLevel 'Gentle' -GameAloneShare 10 -OtherShare 70).Level -ne 'Off') 'Never Off, even when Off measured best.'
Assert-That ($null -eq (Get-YumGamingAdvice -Knowledge $null -CurrentLevel 'Balanced' -GameAloneShare 40 -OtherShare 70)) 'No knowledge file -> no change.'
Assert-That ($null -eq (Get-YumGamingAdvice -Knowledge ([pscustomobject]@{Knowledge=@([pscustomobject]@{GameClass='Medium';Hog='Saturating'})}) -CurrentLevel 'Balanced' -GameAloneShare 40 -OtherShare 70)) 'Old knowledge without per-level results -> no change.'
$g=Get-YumGamingAdvice -Knowledge $kn -CurrentLevel 'Balanced' -GameAloneShare 0 -OtherShare 70
Assert-That ($null -ne $g -and $g.Level -eq 'Strong') 'Unknown game size: uses all heavy-load results (mean says Strong).'

# 2. One-call snapshot matches .NET for this process.
$snap=[YumProcTree]::Snapshot()
Assert-That ($null -ne $snap -and $snap.Count -gt 20) 'Snapshot lists processes.'
$me=Get-Process -Id $PID
Assert-That ([math]::Abs($snap[$PID].CpuMs - $me.TotalProcessorTime.TotalMilliseconds) -lt 1500) 'CPU time matches .NET.'
Assert-That ($snap[$PID].Session -eq $me.SessionId) 'Session matches.'
Assert-That ([datetime]::FromFileTime($snap[$PID].CreateTime).ToString('s') -eq $me.StartTime.ToString('s')) 'Start time matches.'
$sw=[Diagnostics.Stopwatch]::StartNew(); 1..10 | ForEach-Object { $null=[YumProcTree]::Snapshot() }
Assert-That (($sw.Elapsed.TotalMilliseconds/10) -lt 60) ('Snapshot should take a few ms, took {0:N0} ms.' -f ($sw.Elapsed.TotalMilliseconds/10))

# 3. Real checks in strict mode against a test hog: it is held back, room is made for the "game", no errors.
$src=Join-Path $tmp 'hog.cs'
Set-Content -LiteralPath $src -Encoding ASCII -Value 'using System;using System.Threading;static class H{static void Main(){int n=Environment.ProcessorCount*2;for(int t=0;t<n;t++){new Thread(()=>{long x=0;var sw=System.Diagnostics.Stopwatch.StartNew();while(sw.Elapsed.TotalSeconds<25){x++;}GC.KeepAlive(x);}).Start();}}}'
& (Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe') /nologo /out:"$(Join-Path $tmp 'hog.exe')" $src | Out-Null
$game=Start-Process ping.exe -ArgumentList '-n','40','127.0.0.1' -WindowStyle Hidden -PassThru
$hog=Start-Process (Join-Path $tmp 'hog.exe') -WindowStyle Hidden -PassThru
try{
    try{ [System.Threading.Thread]::CurrentThread.Priority=[System.Threading.ThreadPriority]::AboveNormal }catch{}
    $script:Yum.Config['CpuBalanceEnabled']=$true;$script:Yum.Config['CpuCareLevel']='Balanced';$script:Yum.Config['CpuCareStrongOnBattery']=$false
    $script:Yum['CpuCareForegroundOverride']=$game.Id;$script:Yum['CpuCareGameOverride']=$game.Id
    $ms=@()
    for($i=0;$i -lt 7;$i++){ $sw=[Diagnostics.Stopwatch]::StartNew(); Invoke-YumCpuBalanceTick; $ms+=$sw.Elapsed.TotalMilliseconds; Start-Sleep -Milliseconds ([math]::Max(50,1000-[int]$sw.Elapsed.TotalMilliseconds)) }
    $st=Get-YumCpuBalanceState
    Assert-That ($st.Restrained.ContainsKey($hog.Id)) 'The test hog is held back.'
    $r=$st.Restrained[$hog.Id]
    $prof=Get-YumCpuProfile
    if([uint64]$prof.HogMask -ne 0){ Assert-That ([bool]$r.Room -and [uint64]$r.RoomMask -ne 0) 'Room is made for the game (no strict-mode error on the record).' }
    $steady=@($ms | Select-Object -Last 3 | Measure-Object -Maximum).Maximum
    Assert-That ($steady -lt 600) ('Steady checks under full load should be well under 1 s, worst was {0:N0} ms.' -f $steady)
}finally{
    try{ Restore-YumCpuBalanceAll -Why 'test' }catch{}
    foreach($p in $hog,$game){ try{$p.Kill()}catch{} }
    $script:Yum['CpuCareForegroundOverride']=0;$script:Yum['CpuCareGameOverride']=0
    Start-Sleep -Milliseconds 300
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
}

# 4. Wiring.
$cb=[IO.File]::ReadAllText((Join-Path $root 'Core\CpuBalance.ps1'))
Assert-That ($cb -notmatch 'Get-CimInstance Win32_Process\b') 'No per-program WMI query in CPU care any more.'
Assert-That ($cb -match 'warm up while the PC is') 'The worker warms up at start.'
Assert-That ($cb -match '\$strong=\(\$effLevel -eq ''Strong''\)') 'Holding back uses the effective (learned) level.'
Write-Host 'CpuCareGamesTest passed.'
