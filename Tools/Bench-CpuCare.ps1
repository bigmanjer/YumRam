#requires -Version 5.1
<#
Game CPU benchmark for CPU care (5.15). Runs ONLY YUMRAM's own test programs - never touches your real apps.

  yumgame.exe  a CPU-bound "game": every frame, N job threads each do ~4 ms of cache-touching work and the
               main thread ~1 ms; every frame time is recorded (average FPS, 1 % low FPS, p99 frame time,
               frame-time spread).
  yumhog.exe   a background CPU hog: T threads streaming through 8 MB each (pollutes caches like real
               compressors/indexers), steady or bursty (on/off duty cycle).

Matrix: 4 game sizes x (no hog + 3 hog types x CPU care Off / Gentle / Balanced / Strong). CPU care is YUMRAM's
real code (Invoke-YumCpuBalanceTick once a second, game marked as foreground + detected game, as when you play).
Results -> <OutDir>\cpu-bench.json + cpu-bench.md, and a knowledge file (cpu-knowledge.json) that CPU care
reads: which level gave the best 1 % lows for each kind of game and background load on THIS PC.

  powershell -NoProfile -ExecutionPolicy Bypass -STA -File Tools\Bench-CpuCare.ps1 -OutDir $env:TEMP\yum-bench
  -Seconds 12  (per run; first 2 s are warm-up)   -Quick (2 game sizes, 2 hog types: ~6 min)
  -KnowledgeDir <folder>  also write cpu-knowledge.json there (e.g. the installed YUMRAM folder)

Limits (stated in the report): a synthetic game is not a real game engine (no GPU, no driver, no anti-cheat);
laptop temperature drifts during a long run; one PC. Treat results as this PC's tendencies, not universal truth.
#>
param([string]$OutDir=(Join-Path $env:TEMP 'yum-bench'),[int]$Seconds=12,[switch]$Quick,[string]$KnowledgeDir='',[string]$FromResults='',[switch]$Validate,
      [int]$Repeat=3,[ValidateSet('Full','User','Quick')][string]$Profile='Full',[string]$CodeRoot='',[int64]$PerMs=0,[string]$OnlyGame='',[string]$OnlyHog='')
# -FromResults <cpu-bench.json>  rebuild knowledge/report from an earlier run without measuring again
# -Validate  afterwards replay every case where the knowledge picks another level than Balanced, with the
#            user level Balanced and adaptation ON, to check the learned level really helps
# -Repeat N  every case N times, interleaved (rep 1 of everything, then rep 2...), medians reported. Measured:
#            single 12 s runs are too noisy to choose between Balanced and Strong (same case: 12, 16, 54 FPS 1 % low).
# -Profile   Full (4 game sizes x 3 loads), User (3 x 2, Settings button, ~15 min with -Repeat 2), Quick (2 x 2)
# -CodeRoot  run another YUMRAM version's CPU care code (e.g. the previous release) - Tools\Compare-Versions.ps1
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
if($CodeRoot){$root=(Resolve-Path $CodeRoot).Path}
if($Quick){$Profile='Quick'}
New-Item -ItemType Directory -Path $OutDir -Force | Out-Null
$work=Join-Path $OutDir 'bin';New-Item -ItemType Directory -Path $work -Force | Out-Null

# ---------------------------------------------------------------- test programs
$gameCs=@'
using System;using System.Diagnostics;using System.IO;using System.Threading;
static class G{
  static double Spin(double[] a,long iters,double x){int m=a.Length-1;for(long i=0;i<iters;i++){int j=(int)(i*64)&m;a[j]+=x;x=x*1.0000001+0.5;}return x;}
  static int Main(string[] args){
    if(args[0]=="calibrate"){var a=new double[131072];Spin(a,2000000,1);var sw=Stopwatch.StartNew();Spin(a,20000000,1);Console.WriteLine((long)(20000000/sw.Elapsed.TotalMilliseconds));return 0;}
    int n=int.Parse(args[0]);double secs=double.Parse(args[1],System.Globalization.CultureInfo.InvariantCulture);string outFile=args[2];long perMs=long.Parse(args[3]);
    long jobIters=perMs*4,mainIters=perMs*1;
    var go=new SemaphoreSlim[n];var done=new CountdownEvent(n);bool stop=false;
    for(int t=0;t<n;t++){go[t]=new SemaphoreSlim(0);int k=t;var th=new Thread(()=>{var a=new double[131072];double x=k;while(true){go[k].Wait();if(stop)return;x=Spin(a,jobIters,x);done.Signal();}});th.IsBackground=true;th.Start();}
    var main=new double[131072];double mx=0;var frames=new System.Collections.Generic.List<double>(20000);
    var total=Stopwatch.StartNew();var f=new Stopwatch();
    while(total.Elapsed.TotalSeconds<secs){f.Restart();done.Reset(n);for(int t=0;t<n;t++)go[t].Release();mx=Spin(main,mainIters,mx);done.Wait();frames.Add(f.Elapsed.TotalMilliseconds);}
    stop=true;for(int t=0;t<n;t++)go[t].Release();
    using(var w=new StreamWriter(outFile)){foreach(var ms in frames)w.WriteLine(ms.ToString("R",System.Globalization.CultureInfo.InvariantCulture));}
    GC.KeepAlive(mx);return 0;}}
'@
$hogCs=@'
using System;using System.Diagnostics;using System.Threading;
static class H{static int Main(string[] a){int n=int.Parse(a[0]);double secs=double.Parse(a[1],System.Globalization.CultureInfo.InvariantCulture);int duty=int.Parse(a[2]);int period=int.Parse(a[3]);
  var ts=new Thread[n];for(int t=0;t<n;t++){ts[t]=new Thread(()=>{var b=new long[1<<20];long x=0;var sw=Stopwatch.StartNew();int i=0;
    while(sw.Elapsed.TotalSeconds<secs){ if(duty<100){double ph=(sw.Elapsed.TotalMilliseconds%period)/period*100.0; if(ph>=duty){Thread.Sleep(1);continue;}}
      for(int k=0;k<20000;k++){i=(i+8)&((1<<20)-1);b[i]+=x++;} }
    GC.KeepAlive(b);});ts[t].IsBackground=false;ts[t].Start();}
  foreach(var t in ts)t.Join();return 0;}}
'@
$csc=Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
foreach($pair in @(@('yumgame',$gameCs),@('yumhog',$hogCs))){
    $src=Join-Path $work ($pair[0]+'.cs');Set-Content -LiteralPath $src -Value $pair[1] -Encoding ASCII
    $o=& $csc /nologo /optimize+ /platform:x64 ("/out:{0}" -f (Join-Path $work ($pair[0]+'.exe'))) $src 2>&1
    if($LASTEXITCODE -ne 0){throw ("Compiling {0} failed: {1}" -f $pair[0],($o -join ' '))}
}
$gameExe=Join-Path $work 'yumgame.exe';$hogExe=Join-Path $work 'yumhog.exe'

# ---------------------------------------------------------------- YUMRAM's real CPU care, isolated state
. (Join-Path $root 'App\Bootstrap.ps1')
# The real CPU care worker runs without strict mode (its runspace never sets it); measure the same way, so an
# older version is judged by what its users actually get. (Strict-mode safety is covered by Tests\CpuCareGamesTest.)
Set-StrictMode -Off
Initialize-YumConfig
$cfgDir=Join-Path $OutDir 'config';New-Item -ItemType Directory -Path $cfgDir -Force | Out-Null
$script:Yum.ConfigDirectory=$cfgDir;$script:Yum.ConfigFile=(Join-Path $cfgDir 'config.json')
$script:Yum.Config.LogFileName=(Join-Path $OutDir 'bench.log')
$script:Yum.Config['CpuCareStrongOnBattery']=$false
$script:Yum.Config['CpuBalanceExclusions']=@()
$script:Yum.Config['CpuCareAdaptive']=$false     # measure the levels themselves, not the adaptation
try{[void][YumForegroundHook]}catch{}
# Same as the real CPU care worker (Core\CpuBalance.ps1): one thread a notch above normal, so it can act
# while the PC is saturated. Without this the benchmark loop itself was starved and acted seconds late.
try{ [System.Threading.Thread]::CurrentThread.Priority=[System.Threading.ThreadPriority]::AboveNormal }catch{}
$prof=Get-YumCpuProfile
$logical=[int]$prof.Logical
# Warm up exactly like the CPU care worker does at start (first calls compile and read WMI).
try{ $null=Get-YumCpuCareLevel; $null=Get-YumCpuBalanceSettings; $null=[YumProcTree]::Snapshot(); Invoke-YumCpuBalanceTick; Start-Sleep -Milliseconds 300; Invoke-YumCpuBalanceTick; Restore-YumCpuBalanceAll -Why 'warm-up' }catch{}

# calibrate on an idle PC: iterations per millisecond of one job thread
$perMs=$(if($PerMs -gt 0){$PerMs}else{[int64](& $gameExe calibrate | Select-Object -Last 1)})   # -PerMs: same workload across runs/versions
if($perMs -le 0){throw 'Calibration failed.'}

$games=@(
    [pscustomobject]@{Name='Light (2 threads)';Key='Light';Threads=2}
    [pscustomobject]@{Name='Medium (4 threads)';Key='Medium';Threads=[math]::Min(4,$logical)}
    [pscustomobject]@{Name='Heavy (8 threads)';Key='Heavy';Threads=[math]::Min(8,[math]::Max(2,$logical-2))}
    [pscustomobject]@{Name=('All cores ({0} threads)' -f $logical);Key='AllCores';Threads=$logical})
$hogs=@(
    [pscustomobject]@{Name='None';Key='None';Threads=0;Duty=100}
    [pscustomobject]@{Name=('Half the CPU ({0} threads)' -f [math]::Max(1,[int]($logical/2)));Key='Half';Threads=[math]::Max(1,[int]($logical/2));Duty=100}
    [pscustomobject]@{Name=('Saturating ({0} threads)' -f ($logical*2));Key='Saturating';Threads=$logical*2;Duty=100}
    [pscustomobject]@{Name=('Bursty ({0} threads, 50 % on)' -f $logical);Key='Bursty';Threads=$logical;Duty=50})
switch($Profile){
    'Quick'{ $games=@($games | Where-Object { $_.Key -in 'Medium','Heavy' }); $hogs=@($hogs | Where-Object { $_.Key -in 'None','Saturating','Bursty' }) }
    'User' { $games=@($games | Where-Object { $_.Key -in 'Light','Medium','Heavy' }); $hogs=@($hogs | Where-Object { $_.Key -in 'None','Saturating','Bursty' }) }
}
# -OnlyGame / -OnlyHog: measure one case (plus the no-load baseline), e.g. a focused re-test.
if($OnlyGame){ $games=@($games | Where-Object { $_.Key -eq $OnlyGame }) }
if($OnlyHog){ $hogs=@($hogs | Where-Object { $_.Key -in @('None',$OnlyHog) }) }
$levels=@('Off','Gentle','Balanced','Strong')

function Measure-YumBenchRun {
    param($Game,$Hog,[string]$Level)
    $script:Yum['CpuBalance']=$null;$script:Yum['CpuProfile']=$prof
    $script:Yum.Config['CpuBalanceEnabled']=($Level -ne 'Off')
    if($Level -ne 'Off'){$script:Yum.Config['CpuCareLevel']=$Level}
    $hogP=$null
    if($Hog.Threads -gt 0){ $hogP=Start-Process -FilePath $hogExe -ArgumentList @([string]$Hog.Threads,[string]($Seconds+6),[string]$Hog.Duty,'400') -PassThru -WindowStyle Hidden; Start-Sleep -Milliseconds 1500 }
    $frames=Join-Path $OutDir ('frames-{0}.txt' -f [guid]::NewGuid().ToString('N'))
    $gameP=Start-Process -FilePath $gameExe -ArgumentList @([string]$Game.Threads,[string]$Seconds,('"{0}"' -f $frames),[string]$perMs) -PassThru -WindowStyle Hidden
    $script:Yum['CpuCareForegroundOverride']=$gameP.Id;$script:Yum['CpuCareGameOverride']=$gameP.Id
    $hogCpu0=$(if($hogP){try{$hogP.TotalProcessorTime.TotalMilliseconds}catch{0}}else{0});$t0=Get-Date
    $tickMs=New-Object System.Collections.Generic.List[double]
    while(-not $gameP.HasExited){ $tw=[Diagnostics.Stopwatch]::StartNew(); try{ Invoke-YumCpuBalanceTick }catch{}; $tickMs.Add($tw.Elapsed.TotalMilliseconds); Start-Sleep -Milliseconds ([math]::Max(50,1000-[int]$tw.Elapsed.TotalMilliseconds)) }
    $firstAct=$null;try{ $fr=@($script:Yum['CpuBalance'].Restrained.Values)[0]; if($fr){ $firstAct=[math]::Round((([datetime]$fr.Since)-$t0).TotalSeconds,1) } }catch{}
    $wall=((Get-Date)-$t0).TotalMilliseconds
    $gameCpu=0.0;try{$gameCpu=$gameP.TotalProcessorTime.TotalMilliseconds}catch{}
    $hogCpu=0.0;if($hogP){try{$hogP.Refresh();$hogCpu=$hogP.TotalProcessorTime.TotalMilliseconds-$hogCpu0}catch{}}
    $st=Get-YumCpuBalanceState
    $acts=[pscustomobject]@{Restrained=[int]$st.TodayCount;RoomKept=[int]$st['RoomHelped'];RoomUndone=[int]$st['RoomUndone']}
    try{ Restore-YumCpuBalanceAll -Why 'benchmark run finished' }catch{}
    $script:Yum['CpuCareForegroundOverride']=0;$script:Yum['CpuCareGameOverride']=0
    if($hogP){ try{ if(-not $hogP.HasExited){$hogP.Kill()} }catch{} }
    $ft=@(Get-Content -LiteralPath $frames | ForEach-Object { [double]::Parse($_,[Globalization.CultureInfo]::InvariantCulture) })
    Remove-Item -LiteralPath $frames -Force -ErrorAction SilentlyContinue
    # drop the 2 s warm-up
    $acc=0.0;$startIdx=0;for($i=0;$i -lt $ft.Count;$i++){ $acc+=$ft[$i]; if($acc -ge 2000){$startIdx=$i+1;break} }
    $ft=@($ft[$startIdx..($ft.Count-1)])
    $avg=($ft | Measure-Object -Average).Average
    $sorted=@($ft | Sort-Object -Descending); $worst=@($sorted | Select-Object -First ([math]::Max(1,[int]($ft.Count/100))))
    $low1=1000.0/(($worst | Measure-Object -Average).Average)
    $p99=$sorted[[math]::Min($sorted.Count-1,[int]($sorted.Count/100))]
    $sd=[math]::Sqrt((($ft | ForEach-Object { ($_-$avg)*($_-$avg) }) | Measure-Object -Average).Average)
    Start-Sleep -Milliseconds 1500   # let the CPU settle between runs
    return [pscustomobject]@{Game=$Game.Key;GameName=$Game.Name;GameThreads=$Game.Threads;Hog=$Hog.Key;HogName=$Hog.Name;Level=$Level
        AvgFps=[math]::Round(1000.0/$avg,1);Low1Fps=[math]::Round($low1,1);P99Ms=[math]::Round($p99,2);FrameSdMs=[math]::Round($sd,2);Frames=$ft.Count
        GameCpuShare=[math]::Round($gameCpu/($wall*$logical)*100,1);HogCpuShare=[math]::Round($hogCpu/($wall*$logical)*100,1)
        Restrained=$acts.Restrained;RoomKept=$acts.RoomKept;RoomUndone=$acts.RoomUndone;TickMsAvg=[math]::Round((($tickMs | Measure-Object -Average).Average),0);ActedAfterS=$firstAct}
}

$results=New-Object System.Collections.Generic.List[object]
$runs=@(); for($rep=1;$rep -le [math]::Max(1,$Repeat);$rep++){ foreach($g in $games){ foreach($h in $hogs){ if($h.Key -eq 'None'){$runs+=,@($g,$h,'Off',$rep)} else { foreach($l in $levels){$runs+=,@($g,$h,$l,$rep)} } } } }
if($FromResults){
    $prev=Get-Content -LiteralPath $FromResults -Raw | ConvertFrom-Json
    foreach($x in @($prev.Results)){ if($x.Level -notlike '*learned*'){ [void]$results.Add($x) } }
    $games=@($games | Where-Object { $_.Key -in @($results | ForEach-Object { $_.Game }) })
    $hogs=@($hogs | Where-Object { $_.Key -in @($results | ForEach-Object { $_.Hog }) })
    $runs=@()
}
$i=0
foreach($r in $runs){
    $i++
    $m=Measure-YumBenchRun -Game $r[0] -Hog $r[1] -Level $r[2]
    $m | Add-Member -NotePropertyName Rep -NotePropertyValue $r[3] -Force
    [void]$results.Add($m)
    Write-Host ('[{0}/{1}] rep {10}: {2} + {3} / {4}: {5} FPS avg, {6} FPS 1% low, p99 {7} ms (game {8}% / hog {9}% of CPU)' -f $i,$runs.Count,$m.GameName,$m.HogName,$m.Level,$m.AvgFps,$m.Low1Fps,$m.P99Ms,$m.GameCpuShare,$m.HogCpuShare,$r[3])
}
# Medians per case (game x load x level) over the repetitions; everything below uses these.
function Get-YumMedian([double[]]$v){ $s=@($v | Sort-Object); if($s.Count -eq 0){return 0}; $k=[int][math]::Floor($s.Count/2); if($s.Count % 2){return $s[$k]}; return ($s[$k-1]+$s[$k])/2 }
$raw=@($results.ToArray())
$results=New-Object System.Collections.Generic.List[object]
foreach($grp in @($raw | Group-Object Game,Hog,Level)){
    $f=$grp.Group[0]
    [void]$results.Add([pscustomobject]@{Game=$f.Game;GameName=$f.GameName;GameThreads=$f.GameThreads;Hog=$f.Hog;HogName=$f.HogName;Level=$f.Level;Runs=$grp.Count
        AvgFps=[math]::Round((Get-YumMedian @($grp.Group|ForEach-Object{[double]$_.AvgFps})),1);Low1Fps=[math]::Round((Get-YumMedian @($grp.Group|ForEach-Object{[double]$_.Low1Fps})),1)
        Low1Min=[math]::Round((@($grp.Group|ForEach-Object{[double]$_.Low1Fps})|Measure-Object -Minimum).Minimum,1);Low1Max=[math]::Round((@($grp.Group|ForEach-Object{[double]$_.Low1Fps})|Measure-Object -Maximum).Maximum,1)
        P99Ms=[math]::Round((Get-YumMedian @($grp.Group|ForEach-Object{[double]$_.P99Ms})),2);FrameSdMs=[math]::Round((Get-YumMedian @($grp.Group|ForEach-Object{[double]$_.FrameSdMs})),2)
        GameCpuShare=[math]::Round((Get-YumMedian @($grp.Group|ForEach-Object{[double]$_.GameCpuShare})),1);HogCpuShare=[math]::Round((Get-YumMedian @($grp.Group|ForEach-Object{[double]$_.HogCpuShare})),1)
        Restrained=[int](Get-YumMedian @($grp.Group|ForEach-Object{[double]$_.Restrained}));RoomKept=[int](Get-YumMedian @($grp.Group|ForEach-Object{[double]$_.RoomKept}));RoomUndone=[int](Get-YumMedian @($grp.Group|ForEach-Object{[double]$_.RoomUndone}))})
}

# ---------------------------------------------------------------- knowledge: best level per game size x load
function Get-YumBenchClass {
    param([double]$GameShare,[double]$HogShare)
    $g=if($GameShare -lt 30){'Light'}elseif($GameShare -lt 60){'Medium'}else{'Heavy'}
    return $g
}
$knowledge=New-Object System.Collections.Generic.List[object]
foreach($g in $games){
    $base=@($results | Where-Object { $_.Game -eq $g.Key -and $_.Hog -eq 'None' })[0]
    foreach($h in @($hogs | Where-Object { $_.Key -ne 'None' })){
        $set=@($results | Where-Object { $_.Game -eq $g.Key -and $_.Hog -eq $h.Key })
        $off=@($set | Where-Object { $_.Level -eq 'Off' })[0]
        $best=@($set | Sort-Object @{Expression='Low1Fps';Descending=$true},@{Expression='AvgFps';Descending=$true})[0]
        $bal=@($set | Where-Object { $_.Level -eq 'Balanced' })[0]
        $gen=@($set | Where-Object { $_.Level -eq 'Gentle' })[0]
        [void]$knowledge.Add([pscustomobject]@{
            GameClass=(Get-YumBenchClass -GameShare $base.GameCpuShare -HogShare 0);GameShareNoHog=$base.GameCpuShare;GameKey=$g.Key;Hog=$h.Key
            BestLevel=$best.Level;BestLow1Fps=$best.Low1Fps;OffLow1Fps=$off.Low1Fps;NoHogLow1Fps=$base.Low1Fps
            # Does making room (Balanced) beat priority alone (Gentle) for this kind of game? 5 % margin.
            RoomHelps=([double]$bal.Low1Fps -ge [double]$gen.Low1Fps*1.05);RoomHurts=([double]$bal.Low1Fps -le [double]$gen.Low1Fps*0.95)
            StrongHelps=([double]@($set | Where-Object { $_.Level -eq 'Strong' })[0].Low1Fps -ge [double]$bal.Low1Fps*1.05)
            Low1ByLevel=[pscustomobject]@{Off=$off.Low1Fps;Gentle=$gen.Low1Fps;Balanced=$bal.Low1Fps;Strong=@($set | Where-Object { $_.Level -eq 'Strong' })[0].Low1Fps}
            AvgByLevel=[pscustomobject]@{Off=$off.AvgFps;Gentle=$gen.AvgFps;Balanced=$bal.AvgFps;Strong=@($set | Where-Object { $_.Level -eq 'Strong' })[0].AvgFps}})
    }
}

# Validation: user level Balanced, adaptation ON, knowledge from this run. Does the learned level help?
$validation=New-Object System.Collections.Generic.List[object]
if($Validate){
    $knFile=[pscustomobject]@{Version=1;Machine=$prof.Summary;Logical=$logical;Knowledge=@($knowledge.ToArray())}
    $knFile | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $cfgDir 'cpu-knowledge.json') -Encoding UTF8
    foreach($k in $knowledge){
        $adv=Get-YumGamingAdvice -Knowledge $knFile -CurrentLevel 'Balanced' -GameAloneShare ([double]$k.GameShareNoHog) -OtherShare $(if($k.Hog -eq 'Saturating'){70}else{30})
        if($null -eq $adv){continue}
        $g=@($games | Where-Object { $_.Key -eq $k.GameKey })[0];$h=@($hogs | Where-Object { $_.Key -eq $k.Hog })[0]
        $script:Yum.Config['CpuCareAdaptive']=$true
        $m=Measure-YumBenchRun -Game $g -Hog $h -Level 'Balanced'
        $script:Yum.Config['CpuCareAdaptive']=$false
        $m.Level='Balanced + learned'
        [void]$validation.Add([pscustomobject]@{Game=$k.GameKey;Hog=$k.Hog;Learned=$adv.Level;BalancedLow1=[double]$k.Low1ByLevel.Balanced;LearnedLevelLow1=[double]$k.Low1ByLevel.($adv.Level);AdaptiveLow1=$m.Low1Fps;AdaptiveAvg=$m.AvgFps})
        Write-Host ('validate {0} + {1}: Balanced {2} -> learned {3} ({4}) -> adaptive run {5} FPS 1% low' -f $k.GameKey,$k.Hog,$k.Low1ByLevel.Balanced,$adv.Level,$k.Low1ByLevel.($adv.Level),$m.Low1Fps)
    }
}
$doc=[pscustomobject]@{Version=1;Created=(Get-Date).ToString('s');Machine=$prof.Summary;Logical=$logical;Laptop=[bool]$prof.Laptop;OnBattery=[bool](Get-YumOnBattery);SecondsPerRun=$Seconds;Calibration=$perMs;Results=@($results.ToArray());Raw=@($raw);Repeat=$Repeat;Profile=$Profile;CodeRoot=$root;Knowledge=@($knowledge.ToArray());Validation=@($validation.ToArray())}
$doc | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $OutDir 'cpu-bench.json') -Encoding UTF8
$kn=[pscustomobject]@{Version=1;Created=$doc.Created;Machine=$doc.Machine;Logical=$logical;Knowledge=$doc.Knowledge}
$kn | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $OutDir 'cpu-knowledge.json') -Encoding UTF8
if($KnowledgeDir){ $kn | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $KnowledgeDir 'cpu-knowledge.json') -Encoding UTF8 }

# markdown report
$md=New-Object System.Text.StringBuilder
[void]$md.AppendLine('# CPU care game benchmark').AppendLine().AppendLine(('{0} • {1} • {2} s per run (2 s warm-up dropped), {4} run(s) per case, medians (1 % low range in brackets) • {3}' -f $prof.Summary,$(if($doc.OnBattery){'on battery'}else{'plugged in'}),$Seconds,$doc.Created,$Repeat)).AppendLine()
foreach($g in $games){
    [void]$md.AppendLine(('## {0}' -f $g.Name)).AppendLine().AppendLine('| Background load | CPU care | Avg FPS | 1 % low FPS | p99 frame (ms) | Frame spread (ms) | Game / hog CPU % | Actions |').AppendLine('|---|---|---:|---:|---:|---:|---|---|')
    foreach($m in @($results | Where-Object { $_.Game -eq $g.Key })){ [void]$md.AppendLine(('| {0} | {1} | {2} | {3} | {4} | {5} | {6} / {7} | held {8}, room kept {9}, undone {10} |' -f $m.HogName,$m.Level,$m.AvgFps,$(if($null -ne $m.PSObject.Properties['Low1Min'] -and [int]$m.Runs -gt 1){'{0} ({1}–{2})' -f $m.Low1Fps,$m.Low1Min,$m.Low1Max}else{$m.Low1Fps}),$m.P99Ms,$m.FrameSdMs,$m.GameCpuShare,$m.HogCpuShare,$m.Restrained,$m.RoomKept,$m.RoomUndone)) }
    [void]$md.AppendLine()
}
[void]$md.AppendLine('## What CPU care learned on this PC').AppendLine().AppendLine('| Game | Load | Best level (1 % lows) | Best / Off / no-hog 1 % low | Room helps? | Room hurts? |').AppendLine('|---|---|---|---|---|---|')
foreach($k in $knowledge){ [void]$md.AppendLine(('| {0} ({1}% CPU alone) | {2} | **{3}** | {4} / {5} / {6} | {7} | {8} |' -f $k.GameKey,$k.GameShareNoHog,$k.Hog,$k.BestLevel,$k.BestLow1Fps,$k.OffLow1Fps,$k.NoHogLow1Fps,$k.RoomHelps,$k.RoomHurts)) }
if($validation.Count){
    [void]$md.AppendLine().AppendLine('## Validation: your level Balanced, adaptation on').AppendLine().AppendLine('| Game | Load | Learned level | Balanced 1 % low | Learned level 1 % low (matrix) | Adaptive run 1 % low |').AppendLine('|---|---|---|---:|---:|---:|')
    foreach($v in $validation){ [void]$md.AppendLine(('| {0} | {1} | {2} | {3} | {4} | **{5}** |' -f $v.Game,$v.Hog,$v.Learned,$v.BalancedLow1,$v.LearnedLevelLow1,$v.AdaptiveLow1)) }
}
[void]$md.AppendLine().AppendLine('Limits: synthetic game (CPU only, no GPU/driver/anti-cheat), laptop temperature drifts over a long run, one PC. These are tendencies for this PC.')
Set-Content -LiteralPath (Join-Path $OutDir 'cpu-bench.md') -Value $md.ToString() -Encoding UTF8
Write-Host ('Done: {0}' -f (Join-Path $OutDir 'cpu-bench.md'))
