#requires -Version 5.1
if(-not (Get-Command Add-YumCompiledType -ErrorAction SilentlyContinue)){ . (Join-Path $PSScriptRoot '..\Core\TypeCache.ps1') }   # 5.15.9: compiled-helper cache


function Initialize-YumTheme {
    # 5.4: load UI\Xaml\Theme.xaml once into Application.Resources so every window shares one design
    # system (tokens + control styles). Windows are loaded with XamlReader and never call Application.Run,
    # but WPF still resolves StaticResource/implicit styles through Application.Current.Resources.
    if([bool]$script:YumThemeLoaded){return}
    $themePath=Join-Path $script:Yum.Root 'UI\Xaml\Theme.xaml'
    if(-not(Test-Path -LiteralPath $themePath)){return}
    $app=[System.Windows.Application]::Current
    if($null -eq $app){$app=New-Object System.Windows.Application;$app.ShutdownMode=[System.Windows.ShutdownMode]::OnExplicitShutdown}
    $theme=[Windows.Markup.XamlReader]::Parse([IO.File]::ReadAllText($themePath,[System.Text.UTF8Encoding]::new($false,$true)))
    $app.Resources.MergedDictionaries.Add($theme)
    $script:YumThemeLoaded=$true
}
$script:YumThemeLoaded=$false

function Read-YumXamlText {
    param([Parameter(Mandatory=$true)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        throw "XAML file not found: $Path"
    }
    try { Initialize-YumTheme } catch { try { Write-YumLogException -Context 'Theme load failed; using window styles' -Exception $_.Exception } catch {} }
    $utf8 = [System.Text.UTF8Encoding]::new($false,$true)
    return [System.IO.File]::ReadAllText($Path, $utf8)
}
function Test-YumAdministrator {
    try{$id=[Security.Principal.WindowsIdentity]::GetCurrent();$p=New-Object Security.Principal.WindowsPrincipal($id);return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)}catch{return $false}
}
function Start-YumElevated {
    if(Test-YumAdministrator){return $true}
    # 5.12: no UAC prompt every time. NoPrompt: start through the highest-privilege scheduled task (set up once
    # in Settings). Never: keep running without administrator (admin-only reclaim steps are skipped).
    $mode='Ask';try{$mode=Get-YumElevationMode}catch{}
    if($mode -eq 'Never'){Write-YumLog 'Starting without administrator (Settings: never ask).';return $true}
    if($mode -eq 'NoPrompt' -or (Test-YumElevatedTaskCurrent)){
        if(Start-YumViaElevatedTask){Write-YumLog 'Started the administrator instance through the YUMRAM scheduled task (no prompt).';return $false}
        Write-YumLog 'No-prompt task missing or points elsewhere; asking Windows instead.'
    }
    try{
        $scriptPath=Join-Path $script:Yum.Root 'App\YUMRAM.ps1'
        $powershell=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
        if(-not (Test-Path -LiteralPath $scriptPath)){throw "YUMRAM startup script not found: $scriptPath"}
        $quotedScript='"{0}"' -f ($scriptPath -replace '"','\"')
        $arguments='-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File {0}' -f $quotedScript
        Write-YumLog ('Requesting elevation for: {0}' -f $scriptPath)
        $proc=Start-Process -FilePath $powershell -Verb RunAs -WindowStyle Hidden -ArgumentList $arguments -WorkingDirectory $script:Yum.Root -PassThru -ErrorAction Stop
        if($null -eq $proc){throw 'Windows did not return an elevated process handle.'}
        Write-YumLog ('Elevated process launched successfully. PID={0}' -f $proc.Id)
        return $false
    }catch{
        Write-YumLogException -Context 'Elevation launch failed' -Exception $_.Exception
        try{[System.Windows.MessageBox]::Show(("YUMRAM could not start the elevated instance.`n`n{0}" -f $_.Exception.Message),'YUMRAM - Startup Error','OK','Error')|Out-Null}catch{}
        return $false
    }
}
function Get-YumBrush {param([string]$Hex) if($script:Yum.BrushCache.Contains($Hex)){return $script:Yum.BrushCache[$Hex]} $b=New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.ColorConverter]::ConvertFromString($Hex));try{$b.Freeze()}catch{};$script:Yum.BrushCache[$Hex]=$b;return $b}
function Set-YumFooter {param([string]$Text) try{$script:Yum.Ui.Footer.Text=$Text}catch{}}
function Show-YumToast {
    # 5.14: a clear confirmation that a change was applied (the footer line alone was easy to miss).
    param([string]$Text,[ValidateSet('Ok','Warn')][string]$Kind='Ok',[double]$Seconds=3.0)
    try{
        $w=$script:Yum.Window;if($null -eq $w){return}
        $t=$w.FindName('Toast');if($null -eq $t){return}
        $hex=if($Kind -eq 'Warn'){'#FBBF24'}else{'#86EFAC'}
        $t.BorderBrush=Get-YumBrush $hex;$icon=$w.FindName('ToastIcon');$icon.Foreground=Get-YumBrush $hex;$icon.Text=$(if($Kind -eq 'Warn'){'!'}else{'✓'})
        $w.FindName('ToastText').Text=$Text
        $t.Visibility='Visible'
        $fade=New-Object System.Windows.Media.Animation.DoubleAnimationUsingKeyFrames
        [void]$fade.KeyFrames.Add((New-Object System.Windows.Media.Animation.LinearDoubleKeyFrame(1.0,[System.Windows.Media.Animation.KeyTime]::FromTimeSpan([TimeSpan]::FromMilliseconds(150)))))
        [void]$fade.KeyFrames.Add((New-Object System.Windows.Media.Animation.LinearDoubleKeyFrame(1.0,[System.Windows.Media.Animation.KeyTime]::FromTimeSpan([TimeSpan]::FromSeconds($Seconds)))))
        [void]$fade.KeyFrames.Add((New-Object System.Windows.Media.Animation.LinearDoubleKeyFrame(0.0,[System.Windows.Media.Animation.KeyTime]::FromTimeSpan([TimeSpan]::FromSeconds($Seconds+0.4)))))
        $t.BeginAnimation([System.Windows.UIElement]::OpacityProperty,$fade)
        $script:Yum['LastToast']=$Text
    }catch{}
}
function New-YumGraphText {
    param([string]$Text,[double]$X,[double]$Y,[string]$Hex='#B8A9C9',[double]$Size=10.5)
    $t=New-Object System.Windows.Controls.TextBlock;$t.Text=$Text;$t.FontSize=$Size;$t.Foreground=Get-YumBrush $Hex
    [System.Windows.Controls.Canvas]::SetLeft($t,$X);[System.Windows.Controls.Canvas]::SetTop($t,$Y);return $t
}
# 5.15.9 (CPU use measured: the Overview graph took ~38 ms per redraw, twice a second): the line geometry is
# built in compiled code from two number arrays instead of a PowerShell object per point.
if(-not ('YumGraphGeo' -as [type])){
    Add-YumCompiledType -TypeName 'YumGraphGeo' -ReferencedAssemblies PresentationCore,WindowsBase -Source @'
using System; using System.Windows; using System.Windows.Media;
public static class YumGraphGeo {
    public static StreamGeometry Build(double[] xs, double[] vs, double top, double height, double maxGap) {
        var g = new StreamGeometry();
        using (var c = g.Open()) {
            bool started = false; double prevX = 0;
            for (int i = 0; i < xs.Length && i < vs.Length; i++) {
                double v = Math.Max(0, Math.Min(100, vs[i]));
                var pt = new Point(xs[i], top + height - (v / 100.0) * height);
                if (!started || xs[i] - prevX > maxGap) { c.BeginFigure(pt, false, false); started = true; } else { c.LineTo(pt, true, true); }
                prevX = xs[i];
            }
        }
        g.Freeze();
        return g;
    }
    // 5.16.1: the live 30-second view - newest value at the right edge, one point per sample.
    public static StreamGeometry BuildSeries(System.Collections.IList vals, double x0, double plotW, int limit, double top, double height) {
        var g = new StreamGeometry();
        int n = vals == null ? 0 : vals.Count;
        if (limit < 2) limit = 2;
        double step = plotW / (limit - 1), offset = (limit - n) * step;
        using (var c = g.Open()) {
            bool started = false;
            for (int i = 0; i < n; i++) {
                double v; try { v = Convert.ToDouble(vals[i]); } catch { continue; }
                if (double.IsNaN(v)) continue;
                v = Math.Max(0, Math.Min(100, v));
                var pt = new Point(x0 + offset + i * step, top + height - (v / 100.0) * height);
                if (!started) { c.BeginFigure(pt, false, false); started = true; } else { c.LineTo(pt, true, true); }
            }
        }
        g.Freeze();
        return g;
    }
}
'@
}
function Set-YumGraphPath {
    # Draws one series as a line in a lane; a gap in the data (missing buckets) breaks the line instead of
    # being bridged by a long straight segment. -X/-V (number arrays) use the compiled builder.
    param($Path,[object[]]$Points,[double]$Top,[double]$Height,[double]$MaxGapX,[double[]]$X,[double[]]$V)
    if($null -ne $X -and $null -ne $V){ $Path.Data=[YumGraphGeo]::Build($X,$V,$Top,$Height,$MaxGapX); return }
    $geo=New-Object System.Windows.Media.StreamGeometry
    $ctx=$geo.Open()
    try{
        $prevX=$null
        foreach($p in $Points){
            $y=$Top+$Height-(([math]::Max(0,[math]::Min(100,[double]$p.V))/100.0)*$Height)
            $pt=New-Object System.Windows.Point([double]$p.X,$y)
            if($null -eq $prevX -or ([double]$p.X-$prevX) -gt $MaxGapX){ $ctx.BeginFigure($pt,$false,$false) } else { $ctx.LineTo($pt,$true,$true) }
            $prevX=[double]$p.X
        }
    }finally{$ctx.Close()}
    $geo.Freeze();$Path.Data=$geo
}
function Update-YumGraph {
    # 5.14: two lanes on one time axis instead of four crossing lines on one scale.
    #   Top lane    - Available RAM (0-100 % of total) with a dashed line at your memory goal: below the
    #                 dashed line = below goal. (RAM in use is its mirror image; it has its own bar below.)
    #   Bottom lane - CPU and GPU 3D (0-100 %).
    # Before, Available and In use always crossed near 50 %, and CPU/GPU sat on top of each other at the
    # bottom of the same scale - hard to read in every time range.
    try{
        $canvas=$script:Yum.Ui.Graph
        $w=[double]$canvas.ActualWidth
        $h=[double]$canvas.ActualHeight
        if($w -le 10 -or $h -le 10){return}
        $L=$script:Yum['GraphLayout']
        if($null -eq $L -or [math]::Abs([double]$L.W-$w) -gt 1 -or [math]::Abs([double]$L.H-$h) -gt 1){
            $canvas.Children.Clear()
            $labelW=34.0;$gapH=18.0
            $memTop=14.0;$memH=[math]::Max(20,($h-$gapH-28)*0.58);$cpuTop=$memTop+$memH+$gapH+14;$cpuH=[math]::Max(16,$h-$cpuTop-8)
            $L=@{W=$w;H=$h;X0=$labelW;PlotW=($w-$labelW-4);MemTop=$memTop;MemH=$memH;CpuTop=$cpuTop;CpuH=$cpuH}
            foreach($lane in @(@($memTop,$memH,'Available RAM'),@($cpuTop,$cpuH,'CPU  ·  GPU 3D'))){
                foreach($pc in @(0,50,100)){
                    $y=$lane[0]+$lane[1]-($pc/100.0)*$lane[1]
                    $ln=New-Object System.Windows.Shapes.Line;$ln.X1=$labelW;$ln.X2=$w-4;$ln.Y1=$y;$ln.Y2=$y;$ln.Stroke=Get-YumBrush '#321B42';$ln.StrokeThickness=1;[void]$canvas.Children.Add($ln)
                    [void]$canvas.Children.Add((New-YumGraphText -Text ('{0}%' -f $pc) -X 0 -Y ($y-7) -Hex '#8E7DA3' -Size 9.5))
                }
                [void]$canvas.Children.Add((New-YumGraphText -Text $lane[2] -X ($labelW+2) -Y ($lane[0]-15) -Hex '#B8A9C9' -Size 10.5))
            }
            $goal=New-Object System.Windows.Shapes.Line;$goal.Stroke=Get-YumBrush '#FBBF24';$goal.StrokeThickness=1.2;$goal.StrokeDashArray=New-Object System.Windows.Media.DoubleCollection;[void]$goal.StrokeDashArray.Add(5);[void]$goal.StrokeDashArray.Add(4);$goal.X1=$labelW;$goal.X2=$w-4;$goal.Visibility='Collapsed'
            [void]$canvas.Children.Add($goal);$L.Goal=$goal
            $goalText=New-YumGraphText -Text '' -X 0 -Y 0 -Hex '#FBBF24' -Size 10;$goalText.Visibility='Collapsed';[void]$canvas.Children.Add($goalText);$L.GoalText=$goalText
            foreach($spec in @(@('Avail','#86EFAC'),@('Cpu','#FF9ECD'),@('Gpu',[string]$script:Yum.Config.GPUColor))){
                $path=New-Object System.Windows.Shapes.Path;$path.Stroke=Get-YumBrush $spec[1];$path.StrokeThickness=2;$path.StrokeLineJoin='Round';$path.SnapsToDevicePixels=$true
                [void]$canvas.Children.Add($path);$L[$spec[0]]=$path
            }
            $script:Yum['GraphLayout']=$L
        }
        # Goal line (Available must stay above it).
        try{
            $total=0.0;$snap=Get-YumSnapshotCopy;if($snap -and $snap.Memory){$total=[double]$snap.Memory.TotalGB}
            $goalGB=[double]$script:Yum.Config.CleanupTargetAvailableGB
            if($total -gt 0 -and $goalGB -gt 0){
                $gp=[math]::Min(100,($goalGB/$total)*100);$gy=$L.MemTop+$L.MemH-($gp/100.0)*$L.MemH
                $L.Goal.Y1=$gy;$L.Goal.Y2=$gy;$L.Goal.Visibility='Visible'
                $L.GoalText.Text=('goal {0:0.#} GB' -f $goalGB);[System.Windows.Controls.Canvas]::SetLeft($L.GoalText,[math]::Max($L.X0,$w-74));[System.Windows.Controls.Canvas]::SetTop($L.GoalText,$gy-14);$L.GoalText.Visibility='Visible'
            }else{$L.Goal.Visibility='Collapsed';$L.GoalText.Visibility='Collapsed'}
        }catch{}
        $range=[string]$script:Yum['GraphRange']
        $xs=@{Avail=(New-Object System.Collections.Generic.List[double]);Cpu=(New-Object System.Collections.Generic.List[double]);Gpu=(New-Object System.Collections.Generic.List[double])}
        # 5.16.1 fix: 5.16.0 lost this line, so the graph threw (strict mode) and stayed empty.
        $vs=@{Avail=(New-Object System.Collections.Generic.List[double]);Cpu=(New-Object System.Collections.Generic.List[double]);Gpu=(New-Object System.Collections.Generic.List[double])}
        if($range -and $range -ne '30s'){
            $win=switch($range){'5m'{300.0};'1h'{3600.0};default{43200.0}}
            $nb=$(if($range -eq '5m'){60}else{180})
            foreach($b in (Get-YumHistorySeries -WindowSeconds $win -Buckets $nb)){
                $x=$L.X0+[double]$b.X*$L.PlotW
                foreach($k in 'Avail','Cpu','Gpu'){ $v=[double]$b.$k; if(-not [double]::IsNaN($v)){ $xs[$k].Add($x); $vs[$k].Add($v) } }
            }
            $maxGap=($L.PlotW/$nb)*2.5
        } else {
            # 5.16.1: the live 30-second view is built in one compiled call per line (new data enters from the right).
            $limit=[math]::Max(2,[int]$script:Yum.GraphPointsLimit)
            $L.Avail.Data=[YumGraphGeo]::BuildSeries($script:Yum.GraphMemoryAvailable,$L.X0,$L.PlotW,$limit,$L.MemTop,$L.MemH)
            $L.Cpu.Data=[YumGraphGeo]::BuildSeries($script:Yum.GraphCPU,$L.X0,$L.PlotW,$limit,$L.CpuTop,$L.CpuH)
            $L.Gpu.Data=[YumGraphGeo]::BuildSeries($script:Yum.GraphGPU,$L.X0,$L.PlotW,$limit,$L.CpuTop,$L.CpuH)
            return
        }
        Set-YumGraphPath -Path $L.Avail -X $xs.Avail.ToArray() -V $vs.Avail.ToArray() -Top $L.MemTop -Height $L.MemH -MaxGapX $maxGap
        Set-YumGraphPath -Path $L.Cpu -X $xs.Cpu.ToArray() -V $vs.Cpu.ToArray() -Top $L.CpuTop -Height $L.CpuH -MaxGapX $maxGap
        Set-YumGraphPath -Path $L.Gpu -X $xs.Gpu.ToArray() -V $vs.Gpu.ToArray() -Top $L.CpuTop -Height $L.CpuH -MaxGapX $maxGap
    }catch{Write-YumLogException -Context 'Graph update failed' -Exception $_.Exception}
}
function Get-YumUiSnapshot {return Get-YumSnapshotCopy}

# ---------------------------------------------------------------- 5.12 history (5 min / 1 h / 12 h)
# One point every 5 s (also while hidden in the tray), kept for 12 h; saved as 1-minute averages on exit so
# a restart keeps it. Drawn on the same true 0-100 % scale, by time, from oldest (left) to now (right).
function Get-YumHistoryPath { return (Join-Path ([string]$script:Yum.ConfigDirectory) 'history.json') }
function Add-YumHistoryPoint {
    param([double]$Mem,[double]$Avail,[double]$Cpu,[double]$Gpu)
    try{
        if($null -eq $script:Yum['History']){$script:Yum['History']=New-Object System.Collections.Generic.List[object]}
        $now=Get-Date
        if($null -ne $script:Yum['HistoryLast'] -and ($now-[datetime]$script:Yum['HistoryLast']).TotalSeconds -lt 5){return}
        $script:Yum['HistoryLast']=$now
        $h=$script:Yum['History'];$h.Add([pscustomobject]@{T=$now;Mem=$Mem;Avail=$Avail;Cpu=$Cpu;Gpu=$Gpu})
        $cut=$now.AddHours(-12);while($h.Count -gt 0 -and [datetime]$h[0].T -lt $cut){$h.RemoveAt(0)}
    }catch{}
}
function Save-YumHistory {
    try{
        $h=$script:Yum['History'];if($null -eq $h -or $h.Count -eq 0){return}
        $rows=@($h | Group-Object { ([datetime]$_.T).ToString('yyyy-MM-ddTHH:mm') } | ForEach-Object {
            $g=$_.Group;$cpu=@($g|Where-Object{-not [double]::IsNaN([double]$_.Cpu)})
            [pscustomobject]@{T=$_.Name;M=[math]::Round((($g|Measure-Object Mem -Average).Average),1);A=[math]::Round((($g|Measure-Object Avail -Average).Average),1);C=$(if($cpu.Count){[math]::Round((($cpu|Measure-Object Cpu -Average).Average),1)}else{-1});G=[math]::Round((($g|Measure-Object Gpu -Average).Average),1)} })
        ConvertTo-Json -InputObject @($rows) -Compress | Set-Content -LiteralPath (Get-YumHistoryPath) -Encoding UTF8
    }catch{}
}
function Import-YumHistory {
    try{
        $script:Yum['History']=New-Object System.Collections.Generic.List[object]
        $p=Get-YumHistoryPath;if(-not (Test-Path -LiteralPath $p)){return}
        $parsed=Get-Content -LiteralPath $p -Raw | ConvertFrom-Json   # PS 5.1: assign first, then enumerate
        $cut=(Get-Date).AddHours(-12)
        foreach($r in @($parsed)){ try{ $t=[datetime]::ParseExact([string]$r.T,'yyyy-MM-ddTHH:mm',[Globalization.CultureInfo]::InvariantCulture); if($t -ge $cut){ $script:Yum['History'].Add([pscustomobject]@{T=$t;Mem=[double]$r.M;Avail=[double]$r.A;Cpu=$(if([double]$r.C -lt 0){[double]::NaN}else{[double]$r.C});Gpu=[double]$r.G}) } }catch{} }
    }catch{}
}
function Set-YumGraphRange {
    param([string]$Range)
    $script:Yum['GraphRange']=$Range
    $ui=$script:Yum.Ui
    foreach($k in @(@('Range30s','30s'),@('Range5m','5m'),@('Range1h','1h'),@('Range12h','12h'))){ try{ $b=$ui[$k[0]]; if($b){ $b.FontWeight=if($k[1] -eq $Range){'SemiBold'}else{'Normal'}; $b.Opacity=if($k[1] -eq $Range){1.0}else{0.55} } }catch{} }
    try{ $ui.GraphCaption.Text=switch($Range){'5m'{'last 5 minutes'};'1h'{'last hour'};'12h'{'last 12 hours'};default{'last 30 seconds'}} }catch{}
    Update-YumGraph
}
function Get-YumHistorySeries {
    # Averages history into buckets across the window; returns @{X=fraction 0..1; Mem; Avail; Cpu; Gpu} per bucket.
    param([double]$WindowSeconds,[int]$Buckets=180)
    $h=$script:Yum['History'];$out=New-Object System.Collections.Generic.List[object]
    if($null -eq $h){return $out}
    $now=Get-Date;$start=$now.AddSeconds(-$WindowSeconds);$size=$WindowSeconds/$Buckets
    $acc=@{}
    foreach($p in $h){
        $t=[datetime]$p.T;if($t -lt $start){continue}
        $i=[math]::Min($Buckets-1,[int][math]::Floor(($t-$start).TotalSeconds/$size))
        if(-not $acc.ContainsKey($i)){$acc[$i]=@{N=0;M=0.0;A=0.0;C=0.0;CN=0;G=0.0}}
        $a=$acc[$i];$a.N++;$a.M+=[double]$p.Mem;$a.A+=[double]$p.Avail;$a.G+=[double]$p.Gpu
        if(-not [double]::IsNaN([double]$p.Cpu)){$a.C+=[double]$p.Cpu;$a.CN++}
    }
    foreach($i in @($acc.Keys | Sort-Object)){ $a=$acc[$i]; $out.Add([pscustomobject]@{X=($i+0.5)/$Buckets;Mem=$a.M/$a.N;Avail=$a.A/$a.N;Cpu=$(if($a.CN){$a.C/$a.CN}else{[double]::NaN});Gpu=$a.G/$a.N}) }
    return $out
}
function Update-YumRing {
    # 5.11: circular meter (RAM and CPU). Arc from 12 o'clock clockwise; the fill carries severity
    # (series colour -> amber -> red) with the state also written as a word; the track is a light step
    # of the same colour (set in XAML).
    param($Ring,$Label,$StateLabel,$Track,[double]$Percent,[string]$NormalHex,[double]$Warn,[double]$Danger,[string[]]$Words=@('calm','busy','high'))
    try{
        if($null -eq $Ring){return}
        $p=[math]::Min(99.99,[math]::Max(0.0,$Percent))
        if($null -ne $Label){$Label.Text=('{0:N0}%' -f $Percent)}
        # 5.15.9: same value (0.1 %) and colour as last time = nothing to redraw (rings were rebuilt ~7 times a second).
        $hex=if($Percent -ge $Danger){'#F87171'}elseif($Percent -ge $Warn){'#FBBF24'}else{$NormalHex}
        $sig=('{0:F1}|{1}' -f $p,$hex)
        if([string]$Ring.Tag -eq $sig -and $null -ne $Ring.Data){ if($null -ne $StateLabel){$StateLabel.Text=if($Percent -ge $Danger){$Words[2]}elseif($Percent -ge $Warn){$Words[1]}else{$Words[0]}}; return }
        $Ring.Tag=$sig
        $size=[double]$Ring.Parent.Width;if($size -le 0 -or [double]::IsNaN($size)){$size=92.0};$thick=[double]$Ring.StrokeThickness;$r=($size-$thick)/2.0;$c=$size/2.0
        $angle=($p/100.0)*2*[math]::PI
        $fig=New-Object System.Windows.Media.PathFigure;$fig.StartPoint=(New-Object System.Windows.Point($c,($c-$r)));$fig.IsClosed=$false
        $end=New-Object System.Windows.Point(($c+$r*[math]::Sin($angle)),($c-$r*[math]::Cos($angle)))
        [void]$fig.Segments.Add((New-Object System.Windows.Media.ArcSegment($end,(New-Object System.Windows.Size($r,$r)),0.0,($p -gt 50),[System.Windows.Media.SweepDirection]::Clockwise,$true)))
        $geo=New-Object System.Windows.Media.PathGeometry;[void]$geo.Figures.Add($fig);$geo.Freeze();$Ring.Data=$geo
        $hex=if($Percent -ge $Danger){'#F87171'}elseif($Percent -ge $Warn){'#FBBF24'}else{$NormalHex}
        $Ring.Stroke=Get-YumBrush $hex;if($null -ne $Track){$Track.Stroke=Get-YumBrush $hex}
        if($null -ne $StateLabel){$StateLabel.Text=if($Percent -ge $Danger){$Words[2]}elseif($Percent -ge $Warn){$Words[1]}else{$Words[0]}}
    }catch{}
}
function Update-YumGpuRing {
    # 5.15.2: GPU tile ring (user: "give them all circle graphs at the top"). Text is set by the caller.
    param([double]$Percent)
    try{ $u=$script:Yum.Ui; if($null -ne $u['GpuRing']){ Update-YumRing -Ring $u.GpuRing -Label $null -StateLabel $u.GpuRingState -Track $u.GpuRingTrack -Percent $Percent -NormalHex '#B7E3FF' -Warn 70 -Danger 95 -Words @('calm','busy','maxed out') } }catch{}
}
function Update-YumMemoryRing {
    # 5.4: RAM-in-use gauge. Draws an arc from 12 o'clock clockwise, sized to the ring's Grid.
    param([double]$Percent)
    try{ if($null -ne $script:Yum.Ui['MemoryRingTrack']){ Update-YumRing -Ring $script:Yum.Ui.MemoryRing -Label $script:Yum.Ui.MemoryRingText -StateLabel $script:Yum.Ui.MemoryRingState -Track $script:Yum.Ui.MemoryRingTrack -Percent $Percent -NormalHex '#CFA8FF' -Warn 70 -Danger 85 -Words @('comfy','filling up','very full'); return } }catch{}
    try{
        $ring=$script:Yum.Ui.MemoryRing;$label=$script:Yum.Ui.MemoryRingText
        if($null -eq $ring){return}
        $p=[math]::Min(99.99,[math]::Max(0.0,$Percent))
        if($null -ne $label){$label.Text=('{0:N0}%' -f $Percent)}
        $size=104.0;$thick=10.0;$r=($size-$thick)/2.0;$c=$size/2.0
        $angle=($p/100.0)*2*[math]::PI
        $start=New-Object System.Windows.Point($c,($c-$r))
        $end=New-Object System.Windows.Point(($c+$r*[math]::Sin($angle)),($c-$r*[math]::Cos($angle)))
        $fig=New-Object System.Windows.Media.PathFigure;$fig.StartPoint=$start;$fig.IsClosed=$false
        $arc=New-Object System.Windows.Media.ArcSegment($end,(New-Object System.Windows.Size($r,$r)),0.0,($p -gt 50),[System.Windows.Media.SweepDirection]::Clockwise,$true)
        [void]$fig.Segments.Add($arc)
        $geo=New-Object System.Windows.Media.PathGeometry;[void]$geo.Figures.Add($fig);$geo.Freeze()
        $ring.Data=$geo
        # Colour by pressure: calm below 70%, amber to 85%, red above.
        $ring.Stroke=if($Percent -ge 85){Get-YumBrush '#F87171'}elseif($Percent -ge 70){Get-YumBrush '#FBBF24'}else{Get-YumBrush '#CFA8FF'}
    }catch{}
}
function Update-YumTargetUi {
    try {
        $s=Get-YumSnapshotCopy
        if($null -eq $s -or $null -eq $s.Memory -or $null -eq $script:Yum.Ui.TargetBox){return}
        $m=$s.Memory
        $target=[double]$script:Yum.Config.MinimumAvailableGB
        if($target -le 0){$target=0.1}
        $ratio=[math]::Min(100,([double]$m.AvailableGB/$target)*100)
        $text=if([double]$m.AvailableGB -ge $target){'Your goal: {0:N1} GB free - met' -f $target}else{'Your goal: {0:N1} GB free - {1:N1} GB short' -f $target,($target-[double]$m.AvailableGB)}
        # 5.3.2: show what this PC can realistically reach right now (current Available + what the
        # current mode may trim x the retention learned on this machine).
        $est=$script:Yum.ReachableEstimate
        $outOfReach=$false
        if($null -ne $est){
            $reachable=[double]$m.AvailableGB+[double]$est.ReclaimableGB
            $outOfReach=($m.AvailableGB -lt $target -and $reachable -lt ($target-0.1))
            if($m.AvailableGB -lt $target){ $text+=(' • YUMRAM can reach about {0:N1} GB' -f $reachable) }
            $learned=if([int]$est.RetentionSamples -ge 2){'learned on this PC from {0} reclaims' -f [int]$est.RetentionSamples}else{'default until YUMRAM has measured this PC'}
            $script:Yum.Ui.Target.ToolTip=("Reachable now ≈ {0:N1} GB = Available {1:N1} GB + {2:N1} GB that {3} mode may reclaim.`n{4} trimmable processes ({5:N0} MB) × {6:P0} retention ({7}).`nOnly part of trimmed memory becomes Available; Windows needs it for active apps." -f $reachable,$m.AvailableGB,[double]$est.ReclaimableGB,$est.Mode,[int]$est.CandidateCount,[double]$est.CandidateMB,[double]$est.Retention,$learned)
        }
        $script:Yum.Ui.Target.Text=$text
        $script:Yum.Ui.TargetBar.Value=$ratio
        $script:Yum.Ui.TargetStatus.Text=if($m.AvailableGB -ge $target){'On target'}elseif($outOfReach){'Out of reach'}else{'Below goal'}
        if($m.AvailableGB -ge $target){$brush='#86EFAC'}elseif($outOfReach -or $m.AvailableGB -ge ($target*.75)){$brush='#FDE68A'}else{$brush='#FCA5A5'}
        $script:Yum.Ui.TargetStatus.Foreground=Get-YumBrush $brush
        $script:Yum.Ui.TargetBar.Foreground=Get-YumBrush $brush
    } catch { Write-YumLogException -Context 'Target UI update failed' -Exception $_.Exception }
}
function Update-YumUiFromSnapshot {
    try{
        $s=Get-YumUiSnapshot
        if($null -eq $s -or $null -eq $s.Memory){return}
        $newSnapshot=($script:Yum.SnapshotVersion -ne $script:Yum.LastUiSnapshotVersion)
        $m=$s.Memory
        $target=[double]$script:Yum.Config.MinimumAvailableGB
        if($target -le 0){$target=0.1}
        # 5.8.1 (measured: ~24% of one core at idle): draw only what is on screen. Hidden in the tray =
        # tray icon only; another page = sidebar only. History keeps recording, so the graph is whole
        # when you come back. Telemetry reads this flag to skip GPU sampling (display-only, ~0.25 s CPU).
        $windowShown=$false;try{$windowShown=[bool]$script:Yum.Window.IsVisible -and $script:Yum.Window.WindowState -ne [System.Windows.WindowState]::Minimized}catch{}
        $overviewShown=($windowShown -and [string]$script:Yum.CurrentPage -eq 'Overview')
        try{ if($null -ne $script:Yum.TelemetryCache){ $script:Yum.TelemetryCache['UiWantsGpu']=$overviewShown } }catch{}
        if($newSnapshot -and -not $overviewShown){
            $script:Yum.LastUiSnapshotVersion=$script:Yum.SnapshotVersion
            $availablePctH=if([double]$m.TotalGB -gt 0){([double]$m.AvailableGB/[double]$m.TotalGB)*100}else{0}
            foreach($pair in @(@($script:Yum.GraphMemory,[double]$m.UsedPercent),@($script:Yum.GraphMemoryAvailable,[double]$availablePctH),@($script:Yum.GraphCPU,[double]$s.CPU),@($script:Yum.GraphGPU,[double]$s.GPU3D))){[void]$pair[0].Add($pair[1]);while($pair[0].Count -gt $script:Yum.GraphPointsLimit){$pair[0].RemoveAt(0)}}
            Add-YumHistoryPoint -Mem ([double]$m.UsedPercent) -Avail ([double]$availablePctH) -Cpu ([double]$s.CPU) -Gpu ([double]$s.GPU3D)
            Update-YumTray -Percent ([double]$m.UsedPercent) -AvailableGB ([double]$m.AvailableGB)
            if($windowShown){Update-YumSidebarStatus -UsedPercent ([double]$m.UsedPercent) -AvailableGB ([double]$m.AvailableGB) -TotalGB ([double]$m.TotalGB)}
            $script:Yum.UiNeedsFullRefresh=$true
            $newSnapshot=$false
        }
        $forcedRefresh=$false
        if($overviewShown -and [bool]$script:Yum['UiNeedsFullRefresh']){$script:Yum.UiNeedsFullRefresh=$false;$forcedRefresh=(-not $newSnapshot);$newSnapshot=$true}
        if($newSnapshot){
            $script:Yum.LastUiSnapshotVersion=$script:Yum.SnapshotVersion
            $script:Yum.Ui.Available.Text='{0:N2} GB' -f $m.AvailableGB
            $script:Yum.Ui.Memory.Text='{0:N1}%' -f $m.UsedPercent
            $cpuNow=[double]$s.CPU;$gpuNow=[double]$s.GPU3D;$lc=$script:Yum['LiveCpu'];if($null -eq $script:Yum.TelemetryTimer -and $null -ne $lc){$cpuNow=[double]$lc.Percent;$gpuNow=[double]$script:Yum['LiveGpuBusy']}   # 5.15.2: live readings while paused
            $script:Yum.Ui.CPU.Text='{0:N1}%' -f $cpuNow
            $script:Yum.Ui.GPU.Text='{0:N0}%' -f $gpuNow
            Update-YumGpuRing -Percent $gpuNow
            $script:Yum.Ui.Game.Text=if($s.Game.Detected){$s.Game.ProcessName}else{'None'}
            $availablePct=if([double]$m.TotalGB -gt 0){([double]$m.AvailableGB/[double]$m.TotalGB)*100}else{0}
            $script:Yum.Ui.Usage.Text='{0:N2} / {1:N2} GB  •  Available {2:N2} GB ({3:N1}%)' -f $m.UsedGB,$m.TotalGB,$m.AvailableGB,$availablePct
            $script:Yum.Ui.MemoryBar.Value=[math]::Min(100,[math]::Max(0,$m.UsedPercent))
            Update-YumMemoryRing -Percent ([double]$m.UsedPercent)
            Update-YumRing -Ring $script:Yum.Ui.CpuRing -Label $script:Yum.Ui.CpuRingText -StateLabel $script:Yum.Ui.CpuRingState -Track $script:Yum.Ui.CpuRingTrack -Percent $cpuNow -NormalHex '#FF9ECD' -Warn 70 -Danger 90 -Words @('calm','busy','maxed out')
            Update-YumTray -Percent ([double]$m.UsedPercent) -AvailableGB ([double]$m.AvailableGB)
            Update-YumSidebarStatus -UsedPercent ([double]$m.UsedPercent) -AvailableGB ([double]$m.AvailableGB) -TotalGB ([double]$m.TotalGB)
            if(-not $forcedRefresh){[void]$script:Yum.GraphMemory.Add([double]$m.UsedPercent)};while($script:Yum.GraphMemory.Count -gt $script:Yum.GraphPointsLimit){$script:Yum.GraphMemory.RemoveAt(0)}
            if(-not $forcedRefresh){[void]$script:Yum.GraphMemoryAvailable.Add([double]$availablePct)};while($script:Yum.GraphMemoryAvailable.Count -gt $script:Yum.GraphPointsLimit){$script:Yum.GraphMemoryAvailable.RemoveAt(0)}
            if(-not $forcedRefresh){[void]$script:Yum.GraphCPU.Add([double]$s.CPU)};while($script:Yum.GraphCPU.Count -gt $script:Yum.GraphPointsLimit){$script:Yum.GraphCPU.RemoveAt(0)}
            if(-not $forcedRefresh){[void]$script:Yum.GraphGPU.Add([double]$s.GPU3D)};while($script:Yum.GraphGPU.Count -gt $script:Yum.GraphPointsLimit){$script:Yum.GraphGPU.RemoveAt(0)}
            Add-YumHistoryPoint -Mem ([double]$m.UsedPercent) -Avail ([double]$availablePct) -Cpu ([double]$s.CPU) -Gpu ([double]$s.GPU3D)
            Update-YumTargetUi
            $script:Yum.Ui.Mode.Text=$script:Yum.Config.Mode.ToUpperInvariant()
            Update-YumGraph
        }
        $coreTimestamp=$script:Yum.LastCoreTelemetryUpdate
        if($coreTimestamp -eq [datetime]::MinValue){$coreTimestamp=$s.Timestamp}
        $age=((Get-Date)-$coreTimestamp).TotalSeconds
        $gpuAge=if($script:Yum.LastGpuSample -eq [datetime]::MinValue){999}else{((Get-Date)-$script:Yum.LastGpuSample).TotalSeconds}
        $gameAge=if($script:Yum.LastGameSample -eq [datetime]::MinValue){999}else{((Get-Date)-$script:Yum.LastGameSample).TotalSeconds}
        if($null -ne $script:Yum.Ui.TelemetryStatus){$script:Yum.Ui.TelemetryStatus.Text=$(if($age -le 3){'Live readings'}else{'Readings {0:N0} s old' -f $age});$script:Yum.Ui.TelemetryStatus.ToolTip=('Seconds since the last reading - memory/CPU: {0:N1}, graphics: {1:N1}, game check: {2:N1}' -f $age,$gpuAge,$gameAge)};if($null -ne $script:Yum.Ui.QuickMonitorTelemetry){$script:Yum.Ui.QuickMonitorTelemetry.Text=('Last reading {0:N1} s ago' -f $age)}
        # 5.15.2: VRAM always, and CPU % / speed / GPU busy also while monitoring is off (Core\LiveReadings.ps1).
        if($overviewShown){ Update-YumLiveReadingsUi -Paused:($null -eq $script:Yum.TelemetryTimer) }
        # 5.7: monitoring paused is not a fault. It used to show "Telemetry delayed" and a frozen "--%" in the
        # sidebar/tray; now it says Paused and keeps RAM readings live with one cheap read every 2 s.
        if($null -eq $script:Yum.TelemetryTimer){
            $script:Yum.Ui.Status.Text='● Paused';$script:Yum.Ui.Status.Foreground=Get-YumBrush '#FDE68A'
            if(((Get-Date)-[datetime]$script:Yum.LastPausedMemoryRead).TotalSeconds -ge 2){
                $script:Yum.LastPausedMemoryRead=Get-Date
                try{$pm=Get-YumMemoryTelemetry;if($null -ne $pm){Update-YumSidebarStatus -UsedPercent ([double]$pm.UsedPercent) -AvailableGB ([double]$pm.AvailableGB) -TotalGB ([double]$pm.TotalGB);Update-YumTray -Percent ([double]$pm.UsedPercent) -AvailableGB ([double]$pm.AvailableGB);Update-YumMemoryRing -Percent ([double]$pm.UsedPercent);$script:Yum.Ui.Available.Text='{0:N2} GB' -f $pm.AvailableGB;try{Update-YumSnapshotMemory -Memory $pm}catch{};try{Add-YumHistoryPoint -Mem ([double]$pm.UsedPercent) -Avail ([double]$pm.AvailableGB/[math]::Max(0.1,[double]$pm.TotalGB)*100) -Cpu $(if($null -ne $script:Yum['LiveCpu']){[double]$script:Yum['LiveCpu'].Percent}else{[double]::NaN}) -Gpu 0}catch{};$script:Yum.UiNeedsFullRefresh=$true}}catch{}
            }
            if($null -eq $script:Yum['LiveCpu']){ try{$script:Yum.Ui.CpuRingText.Text='--';$script:Yum.Ui.CpuRingState.Text='paused';$script:Yum.Ui.CpuRing.Data=$null;$script:Yum.Ui.CpuRing.ToolTip='CPU is measured while the Overview is open'}catch{} }
            if($null -ne $script:Yum.Ui.TelemetryStatus){$script:Yum.Ui.TelemetryStatus.Text='Monitoring paused'};if($null -ne $script:Yum.Ui.QuickMonitorTelemetry){$script:Yum.Ui.QuickMonitorTelemetry.Text='Automatic care is off.'}
            return
        }
        # 5.8: just started (or resumed) and no new sample yet - say so instead of 'Paused' / 'delayed'.
        $startedAt=[datetime]::MinValue;try{$startedAt=[datetime]$script:Yum['MonitoringStartedAt']}catch{}
        if($script:Yum.LastCoreTelemetryUpdate -lt $startedAt -and ((Get-Date)-$startedAt).TotalSeconds -lt 5){$script:Yum.Ui.Status.Text='● Starting…';$script:Yum.Ui.Status.Foreground=Get-YumBrush '#FDE68A';return}
        if($age -gt 3){$script:Yum.Ui.Status.Text='⚠ Readings late';$script:Yum.Ui.Status.Foreground=Get-YumBrush '#FDE68A';Set-YumFooter ('⚠ Readings are late (last one {0:N1} s ago) - the PC is very busy.' -f $age)}elseif($null -ne $script:Yum.TelemetryTimer -and $script:Yum.LastCoreTelemetryUpdate -ne [datetime]::MinValue){$script:Yum.Ui.Status.Text='● Monitoring';$script:Yum.Ui.Status.Foreground=Get-YumBrush $script:Yum.Config.GPUColor;$pressure=Get-YumPressureDecision -Memory $m -Mode $script:Yum.Config.Mode;if($pressure.Emergency){Set-YumFooter '⚠ RAM is almost full - programs may slow down. Press Free RAM now.'}elseif($m.AvailableGB -lt $target){Set-YumFooter ('💜 Less free RAM than your goal ({0:N1} GB) - YUMRAM is freeing some from idle programs.' -f $target)}elseif($pressure.ShouldClean){Set-YumFooter '💜 RAM is getting full - YUMRAM is keeping an eye on it.'}else{Set-YumFooter ('Everything looks comfy 💜  •  {0:N1} GB free for programs  •  your goal {1:N1} GB' -f $m.AvailableGB,$target)}}else{$script:Yum.Ui.Status.Text='● Paused';$script:Yum.Ui.Status.Foreground=Get-YumBrush '#FDE68A'}
    }catch{Write-YumLogException -Context 'UI refresh failed' -Exception $_.Exception}
}
function Apply-YumUiConfig {
    $script:Yum.SuppressUiEvents=$true
    try{
        $modeTags=@('Safe','Balanced','Aggressive');$modeItems=@($script:Yum.Ui.ModeBox.Items);for($i=0;$i -lt $modeItems.Count;$i++){if([string]$modeItems[$i].Tag -eq [string]$script:Yum.Config.Mode){$script:Yum.Ui.ModeBox.SelectedIndex=$i;break}}
        $priorityDisplay=@('Keep Existing','Normal (Default)','Above Normal (Game Preference)','High (Advanced)')
        $priorityLabel = switch ([string]$script:Yum.Config.GamePriority) {
            'KeepExisting' { 'Keep Existing' }
            'AboveNormal' { 'Above Normal (Game Preference)' }
            'High' { 'High (Advanced)' }
            default { 'Normal (Default)' }
        }
        $script:Yum.Ui.PriorityBox.SelectedIndex=[array]::IndexOf($priorityDisplay,$priorityLabel)
        if($null -ne $script:Yum.Ui.ModeHelp){$script:Yum.Ui.ModeHelp.Text=switch([string]$script:Yum.Config.Mode){'Safe'{'Minimal intervention — low-risk candidates only, up to 8 follow-up passes, no optional apps/services.'};'Aggressive'{'Maximum reclaim — broader known-safe candidates, approved optional apps/services, repeated passes toward the target.'};default{'Recommended balance — moderate candidates and repeated passes toward the target without touching protected/unknown items.'}}}
        $script:Yum.Ui.TargetBox.Text=$script:Yum.Config.MinimumAvailableGB.ToString('0.##',[Globalization.CultureInfo]::InvariantCulture)
        # 5.7: the sidebar Mode badge followed only telemetry ticks, so a mode change in Settings looked ignored.
        if($null -ne $script:Yum.Ui.Mode){$script:Yum.Ui.Mode.Text=([string]$script:Yum.Config.Mode).ToUpperInvariant()}
        $script:Yum.Ui.AutoGame.IsChecked=[bool]$script:Yum.Config.AutoDetectGames
        $script:Yum.Ui.ProtectGame.IsChecked=[bool]$script:Yum.Config.ProtectGame
        $script:Yum.Ui.AutoClean.IsChecked=[bool]$script:Yum.Config.AutoCleanOnGameStart
        if($null -ne $script:Yum.Ui.CpuBalanceToggle){$script:Yum.Ui.CpuBalanceToggle.IsChecked=[bool](Get-YumCpuBalanceSettings).Enabled}
    }finally{$script:Yum.SuppressUiEvents=$false}
}
function Update-YumUpdateUi {
    # 5.10: picks up a finished background update check and shows the banner once something is available.
    try{
        $r=Receive-YumUpdateCheck
        if($null -eq $r){return}
        $ui=$script:Yum.Ui
        if([string]$r.Status -eq 'Available'){
            $ui.UpdateTitle.Text=('YUMRAM {0} is available' -f $r.Latest)
            $ui.UpdateText.Text=('You have {0}. The download is checked against its published SHA-256 before anything is installed; your settings and statistics are kept, and the current version is kept so you can go back.' -f $r.Current)
            if(Test-YumAutoUpdateEnabled){ $ui.UpdateText.Text=('You have {0}. YUMRAM downloads it in the background, checks its SHA-256 and installs it right away - it only waits while you play. Your settings are kept. Or press Install and restart now.' -f $r.Current) }
            $ui.UpdateBanner.Visibility='Visible'
            if(-not $script:Yum.Window.IsVisible -and -not (Test-YumAutoUpdateEnabled)){Show-YumTrayNotice -Title ('YUMRAM {0} is available' -f $r.Latest) -Text 'Open YUMRAM to install it.'}
        } else { $ui.UpdateBanner.Visibility='Collapsed' }
        # About shows the latest status if it is open.
        try{ $a=$script:Yum.Pages['About']; if($null -ne $a){ $a.Window.FindName('UpdateStatus').Text=[string]$r.Message } }catch{}
    }catch{ Write-YumLogException -Context 'Update UI failed' -Exception $_.Exception }
}
function Get-YumUpdateBlocker {
    # 5.15.3: an automatic update only restarts YUMRAM when nothing important is going on. Returns why not, or ''.
    try{ $s=$script:Yum.Snapshot; if($null -ne $s -and $null -ne $s.Game -and [bool]$s.Game.Detected){ return ('a game is running ({0})' -f [string]$s.Game.ProcessName) } }catch{}
    try{ if(Test-YumReclaimBusy){ return 'Free RAM is working' } }catch{}
    try{ $iw=$script:Yum.IntelligenceWindow; if((Test-YumPageAlive -Window $iw) -and $null -ne $iw.Tag -and ([bool]$iw.Tag.Busy -or [bool]$iw.Tag.ResearchBusy)){ return 'an Intelligence scan is running' } }catch{}
    try{ if([bool]$script:Yum['DiskAutoRunning']){ return 'a disk clean is running' }; $dp=$script:Yum.Pages['DiskCleanup']; if($null -ne $dp -and $null -ne $dp.Window.Tag -and [bool]$dp.Window.Tag.Busy){ return 'Disk cleanup is working' } }catch{}
    try{ $b=[int]$script:Yum['CpuBenchPid']; if($b -gt 0 -and (Get-Process -Id $b -ErrorAction SilentlyContinue)){ return 'Measure games is running' } }catch{}
    return ''
}

function Update-YumAutoUpdate {
    # 5.15.3 (user: "whenever an update becomes available it gets updated"). Called by the UI timer:
    #  - asks GitHub every 30 min whether a check is due (every 6 h),
    #  - downloads and verifies a new version in the background,
    #  - installs it at the first moment nothing important is going on, then YUMRAM restarts (hidden again if it was).
    try{
        if(((Get-Date)-[datetime]$script:Yum['LastAutoUpdateTick']).TotalSeconds -lt 5){return}
        $script:Yum['LastAutoUpdateTick']=Get-Date
        if(((Get-Date)-[datetime]$script:Yum['LastUpdateCheckAsk']).TotalMinutes -ge 5){ $script:Yum['LastUpdateCheckAsk']=Get-Date; try{ Start-YumUpdateCheck }catch{} }
        if(-not (Test-YumAutoUpdateEnabled)){return}
        $info=$script:Yum['UpdateInfo']; if($null -eq $info -or [string]$info.Status -ne 'Available'){return}
        $done=Receive-YumUpdateDownload
        if($null -ne $done){
            if([bool]$done.Success){ $script:Yum['UpdateStaged']=[string]$done.Staging; $script:Yum['UpdateStagedVersion']=[string]$info.Latest; Write-YumLog ('Automatic update: {0} downloaded and verified; installing now unless a game is running.' -f $info.Latest) }
            else { $script:Yum['UpdateFailures']=[int]$script:Yum['UpdateFailures']+1; Write-YumLog ('Automatic update download failed: {0}' -f [string]$done.Message); try{ $script:Yum.Ui.UpdateText.Text=('Automatic update could not be downloaded: {0}. It is tried again later; Install and restart works too.' -f $done.Message) }catch{} }
        }
        $staged=[string]$script:Yum['UpdateStaged']
        if(-not $staged -or [string]$script:Yum['UpdateStagedVersion'] -ne [string]$info.Latest -or -not (Test-Path -LiteralPath $staged)){
            if($null -eq $script:Yum['UpdateDownloadPs'] -and [int]$script:Yum['UpdateFailures'] -lt 3){ Start-YumUpdateDownload -Info $info }
            return
        }
        $why=Get-YumUpdateBlocker
        if($why){ $script:Yum['UpdateHeadsUpAt']=[datetime]::MinValue; try{ $script:Yum.Ui.UpdateText.Text=('YUMRAM {0} is downloaded and checked. It installs automatically as soon as {1} has finished - or press Install and restart.' -f $info.Latest,$why) }catch{}; return }
        # 5.15.6: no waiting for "a quiet moment" any more - only gaming (and YUMRAM's own work) delays it. If the window
        # is open, a 10-second heads-up first so nobody is surprised mid-click.
        if($script:Yum.Window.IsVisible){
            $hu=[datetime]$script:Yum['UpdateHeadsUpAt']
            if($hu -eq [datetime]::MinValue){ $script:Yum['UpdateHeadsUpAt']=Get-Date; try{ Show-YumToast -Text ('Updating YUMRAM to {0} in a few seconds - back right after with your settings.' -f $info.Latest) -Seconds 8 }catch{}; return }
            if(((Get-Date)-$hu).TotalSeconds -lt 10){ return }
        }
        $hidden=-not $script:Yum.Window.IsVisible
        Update-YumConfigValue -Name StartHiddenOnce -Value $hidden
        Write-YumLog ('Automatic update: installing {0} now (YUMRAM restarts{1}).' -f $info.Latest,$(if($hidden){' hidden in the tray'}else{''}))
        try{ Show-YumTrayNotice -Title ('Updating YUMRAM to {0}' -f $info.Latest) -Text 'Back in a few seconds with your settings kept. What''s new: About > Check for updates, or the GitHub release page.' }catch{}
        Invoke-YumApplyStagedUpdate -Staging $staged
        Exit-YumApp
    }catch{ Write-YumLogException -Context 'Automatic update failed' -Exception $_.Exception }
}

function Invoke-YumInstallUpdate {
    $info=$script:Yum['UpdateInfo']
    if($null -eq $info -or [string]$info.Status -ne 'Available'){return}
    $script:Yum.Ui.UpdateInstall.IsEnabled=$false;$script:Yum.Ui.UpdateText.Text='Downloading and verifying…'
    Set-YumFooter 'Downloading the update…'
    $script:Yum.Window.Dispatcher.Invoke([action]{},[System.Windows.Threading.DispatcherPriority]::Background)
    $r=Install-YumUpdate -Info $info
    if($r.Success){Set-YumFooter ([string]$r.Message);$script:Yum.Ui.UpdateText.Text=[string]$r.Message;Exit-YumApp}
    else{$script:Yum.Ui.UpdateInstall.IsEnabled=$true;$script:Yum.Ui.UpdateText.Text=('Not installed: {0}' -f $r.Message);Set-YumFooter ('⚠ Update not installed: '+[string]$r.Message)}
}
function Update-YumNoticesUi {
    # 5.12: leak alerts (queued by the CPU care worker) and a low-RAM warning, shown as tray notices.
    # 5.15: after "Measure games" finishes, share (opted in) or ask once.
    try{ if([bool]$script:Yum['CommunityPromptPending']){ $script:Yum['CommunityPromptPending']=$false; Invoke-YumCommunityAfterBenchmark } }catch{}
    try{
        $st=Get-YumCpuBalanceState
        $q=$st['LeakNotices']
        if($null -ne $q -and $q.Count -gt 0){
            $n=$q[0];$q.RemoveAt(0)
            $msg=('{0} has grown by {1:N1} GB in {2} minutes and is still growing (now {3:N1} GB). That usually means a memory leak - closing and reopening it gives the memory back.' -f $n.Name,([double]$n.GrowthMB/1024),[int]$n.Minutes,([double]$n.ToMB/1024))
            Show-YumTrayNotice -Title ('{0} keeps using more RAM' -f $n.Name) -Text $msg
            Set-YumFooter ('⚠ '+$msg)
        }
        # Low RAM: Available under the goal by 1 GB+ for 2 minutes and automatic care is off or cannot fix it.
        $s=Get-YumSnapshotCopy;if($null -eq $s -or $null -eq $s.Memory){return}
        $goal=[double]$script:Yum.Config.MinimumAvailableGB
        $low=([double]$s.Memory.AvailableGB -lt ($goal-1.0))
        $alertOn=$true;try{if($script:Yum.Config.Contains('LowRamAlertEnabled')){$alertOn=[bool]$script:Yum.Config['LowRamAlertEnabled']}}catch{}
        if(-not $low -or -not $alertOn){$script:Yum['LowRamSince']=$null;return}
        if($null -eq $script:Yum['LowRamSince']){$script:Yum['LowRamSince']=Get-Date;return}
        $helpless=($null -eq $script:Yum.TelemetryTimer) -or ([double]$script:Yum.ControllerBackoffSeconds -gt 0)
        $last=[datetime]::MinValue;try{if($script:Yum['LowRamNoticeAt']){$last=[datetime]$script:Yum['LowRamNoticeAt']}}catch{}
        if($helpless -and ((Get-Date)-[datetime]$script:Yum['LowRamSince']).TotalMinutes -ge 2 -and ((Get-Date)-$last).TotalMinutes -ge 60){
            $script:Yum['LowRamNoticeAt']=Get-Date
            $why=if($null -eq $script:Yum.TelemetryTimer){'Automatic care is off.'}else{'Nothing more can be trimmed right now.'}
            Show-YumTrayNotice -Title ('RAM is low: {0:N1} GB available' -f [double]$s.Memory.AvailableGB) -Text ('Your goal is {0:N1} GB. {1} Open "What''s running" to see what is using it.' -f $goal,$why)
        }
    }catch{}
}
function Update-YumLiveReadingsUi {
    # 5.15.2 (user report: "-- GHz" and a frozen GPU while monitoring was off; "GPU 3D" unexplained, no VRAM).
    # Every 2 s while the Overview is on screen: VRAM always; CPU %, speed and GPU busy too when monitoring is off.
    # Cheap: opened counters + one GPU-engine read (~10-25 ms measured), nothing while hidden or on another page.
    param([switch]$Paused)
    try{
        # Every 2 s; while a background reading is still missing (first seconds) every tick.
        $haveAll=($null -ne $script:Yum['LiveSampler'] -and $null -ne $script:Yum['LiveSampler'].Shared.Gpu -and $null -ne $script:Yum['LiveSampler'].Shared.Disk)
        if($haveAll -and ((Get-Date)-[datetime]$script:Yum['LastLiveReadingsRead']).TotalSeconds -lt 2){return}
        $script:Yum['LastLiveReadingsRead']=Get-Date
        $ui=$script:Yum.Ui
        # 5.15.9: latest background reading (no waiting); $null for a moment right after start.
        $g=Get-YumLiveReading -Kind Gpu
        if($null -ne $ui['GpuVram'] -and $null -ne $g){
            $ui.GpuVram.Text=Format-YumVram $g
            $ui.GpuVram.ToolTip=((@($g.Adapters) | ForEach-Object { if($null -ne $_.VramUsedGB){'{0}: {1:N0} % busy, VRAM {2:N2} / {3:N1} GB' -f $_.Name,$_.ThreeD,$_.VramUsedGB,$_.VramTotalGB}else{'{0}: {1:N0} % busy, {2:N1} GB VRAM' -f $_.Name,$_.ThreeD,$_.VramTotalGB} }) -join [Environment]::NewLine)
            if($null -ne $ui['GpuName'] -and $null -ne $g.Main){ $ui.GpuName.Text=Get-YumGpuShortName ([string]$g.Main.Name); $ui.GpuName.ToolTip=[string]$g.Main.Name }
            # 5.15.2: who holds graphics memory (read in the background; see Core\Vram.ps1).
            try{ $vu=@(Get-YumVramUsers | Select-Object -First 6); if($vu.Count){ $ui.GpuVram.ToolTip=[string]$ui.GpuVram.ToolTip+[Environment]::NewLine+[Environment]::NewLine+'Biggest users of graphics memory:'+[Environment]::NewLine+(($vu | ForEach-Object { '  {0}  {1:N0} MB on {2}' -f $_.Name,$_.MB,$_.Adapter }) -join [Environment]::NewLine)+[Environment]::NewLine+'Click a program in What''s running to see how to free it.' } }catch{}
        }
        # 5.16.2: temperatures next to the card titles (Core\LiveReadings.ps1 Get-YumLiveTemps).
        try{
            $tp=Get-YumLiveReading -Kind Temps
            if($null -ne $tp){
                foreach($pair in @(@('CpuTemp',$tp.CpuC,80,90,('CPU area, from Windows'' thermal zone ({0}). Laptops often run 80-95°C under load; above 95°C the CPU slows itself down.' -f $tp.CpuSource)),@('GpuTemp',$tp.GpuC,80,87,'Graphics chip, from the NVIDIA driver.'),@('DiskTemp',$tp.DiskC,50,60,'Hottest drive, from Windows'' drive health data (administrator only). SSDs slow down above about 70°C.'))){
                    $el=$ui[$pair[0]]; if($null -eq $el){continue}
                    $f=Format-YumTemp $pair[1] $pair[2] $pair[3]
                    if($null -ne $f){ $el.Text=$f.Text; $el.Foreground=Get-YumBrush $f.Hex; $el.ToolTip=$pair[4] }
                    elseif($pair[0] -eq 'GpuTemp' -and [bool]$tp.GpuAsleep){ $el.Text='asleep'; $el.Foreground=Get-YumBrush '#8E7DA3'; $el.ToolTip='The NVIDIA chip is asleep (saving battery). YUMRAM does not wake it just to read its temperature.' }
                    else{ $el.Text='' }
                }
            }
        }catch{}
        $d=Get-YumLiveReading -Kind Disk
        if($null -ne $ui['DiskBusy'] -and $null -ne $d){
            $ui.DiskBusy.Text=if($null -ne $d.Busiest){'{0:N0}%' -f $d.Busiest}else{'--%'}
            if($null -ne $d.Busiest -and $null -ne $ui['DiskRing']){ Update-YumRing -Ring $ui.DiskRing -Label $null -StateLabel $ui.DiskRingState -Track $ui.DiskRingTrack -Percent ([double]$d.Busiest) -NormalHex '#7DD3FC' -Warn 60 -Danger 90 -Words @('calm','busy','maxed out') }
            $ui.DiskSpeed.Text=('Read {0} · Write {1}' -f (Format-YumDiskSpeed $d.ReadMBs),(Format-YumDiskSpeed $d.WriteMBs))
            $ui.DiskDetail.Text=Format-YumDiskLines $d -SkipDrive $env:SystemDrive
            if($null -ne $ui['DiskCard']){ $ui.DiskCard.ToolTip=("Busy = how much of the time your disk is working (Task Manager calls it 'Active time'). Near 100 % for a long time means programs wait for the disk. ms = how long the disk takes to answer (lower is better).`n`n{0}" -f (Format-YumDiskLines $d)) }
            $c0=@($d.Drives | Where-Object { $_.Letter -eq ($env:SystemDrive) } | Select-Object -First 1)
            if($c0.Count -and [double]$c0[0].TotalGB -gt 0){ $usedPct=100*(1-[double]$c0[0].FreeGB/[double]$c0[0].TotalGB); $ui.DiskSpaceBar.Value=$usedPct
                $ui.DiskSpaceBar.Foreground=Get-YumBrush $(if($usedPct -ge 90){'#F87171'}elseif($usedPct -ge 80){'#FBBF24'}else{'#7DD3FC'})
                if($null -ne $ui['DiskFree']){ $ui.DiskFree.Text=('{0:N0} GB free' -f [double]$c0[0].FreeGB) }
                $ui.DiskSpaceText.Text=('of {0:N0} GB on {1}{2}' -f [double]$c0[0].TotalGB,$c0[0].Letter,$(if($usedPct -ge 90){' - almost full'}else{''}))
                $ui.DiskSpaceText.Foreground=Get-YumBrush $(if($usedPct -ge 90){'#F87171'}else{'#B8A9C9'})
                $ui.DiskSpaceText.ToolTip=$(if($usedPct -ge 90){'The Windows drive is over 90 % full. Windows needs free space for updates and its page file; delete or move large files (Settings > System > Storage).'}else{$null}) }
        }
        if(-not $Paused){ $script:Yum['LiveCpu']=$null; return }
        $c=Get-YumLiveReading -Kind Cpu
        $script:Yum['LiveCpu']=$c
        if($null -ne $g){
            $script:Yum['LiveGpuBusy']=[double]$g.Busiest
            $ui.GPU.Text='{0:N0}%' -f [double]$g.Busiest
            Update-YumGpuRing -Percent ([double]$g.Busiest)
        }
        if($null -ne $c){
            $ui.CPU.Text='{0:N1}%' -f [double]$c.Percent
            Update-YumRing -Ring $ui.CpuRing -Label $ui.CpuRingText -StateLabel $ui.CpuRingState -Track $ui.CpuRingTrack -Percent ([double]$c.Percent) -NormalHex '#FF9ECD' -Warn 70 -Danger 90 -Words @('calm','busy','maxed out')
            $ui.CpuRing.ToolTip='Live CPU use (monitoring is off, so CPU care and automatic RAM care are not acting).'
        }
        Update-YumCpuCardUi
    }catch{ Write-YumLogException -Context 'Live readings failed' -Exception $_.Exception }
}
function Update-YumCpuCardUi {
    # 5.11: the Overview CPU card (same layout as RAM): speed, processes/threads, busiest, CPU care state.
    try{
        $ui=$script:Yum.Ui;if($null -eq $ui -or $null -eq $ui['CpuSpeed']){return}
        $c=$script:Yum.TelemetryCache
        $paused=($null -eq $script:Yum.TelemetryTimer)
        $mhz=0.0;try{$mhz=[double]$c['CpuMHz']}catch{}
        $base=0.0;try{$base=[double]$c['CpuBaseMHz']}catch{}
        $live=$script:Yum['LiveCpu']
        if($paused -and $null -ne $live){ $mhz=[double]$live.MHz; if([double]$live.BaseMHz -gt 0){$base=[double]$live.BaseMHz} }
        if($mhz -le 0){$ui.CpuSpeed.Text='-- GHz'}else{$ui.CpuSpeed.Text=('{0:N2} GHz' -f ($mhz/1000.0))}
        $ui.CpuSpeed.ToolTip=if($base -gt 0){'Current effective speed across all cores. Base speed {0:N2} GHz; above it = boost, below it = saving power or held back by heat.' -f ($base/1000.0)}else{'Current effective speed across all cores.'}
        # 5.15.9: never wait for WMI here; for the first second show what .NET knows.
        $pr=if(Test-YumCpuProfileReady){Get-YumCpuProfile}else{[pscustomobject]@{Cores='…';Logical=[Environment]::ProcessorCount;Summary='Reading CPU details…'}}
        $procs=0;$threads=0;try{$procs=[int]$c['Processes'];$threads=[int]$c['Threads']}catch{}
        $ui.CpuDetails.Text=if($paused -or $procs -le 0){'{0} cores • {1} threads' -f $pr.Cores,$pr.Logical}else{'{0:N0} processes • {1:N0} threads • {2} cores / {3} logical' -f $procs,$threads,$pr.Cores,$pr.Logical}
        $ui.CpuDetails.ToolTip=$pr.Summary
        $st=Get-YumCpuBalanceState
        $top=@();try{$top=@($st['Top'])}catch{}
        $ui.CpuBusiest.Text=if($top.Count -gt 0){'Busiest: '+($top -join ', ')}else{''}
        $cfg=Get-YumCpuBalanceSettings
        $held=@($st.Restrained.Values).Count
        $status=if(-not $cfg.Enabled){'Care off'}elseif([bool]$st['Gaming']){'Gaming'}elseif($held -gt 0){'Holding back {0}' -f $held}else{'Watching'}
        $ui.CpuCareStatus.Text=$status
        $ui.CpuCareStatus.Foreground=if(-not $cfg.Enabled){Get-YumBrush '#FDE68A'}elseif($held -gt 0){Get-YumBrush '#FBBF24'}else{Get-YumBrush '#86EFAC'}
    }catch{}
}
function Update-YumCpuBalanceUi {
    param([switch]$Force)
    # 5.15.9 (CPU use measured: the window thread used ~21% of a core on the Overview): the CPU cards only change
    # when the CPU care worker ticks (1/s), so they are drawn at most once a second and not while hidden.
    # -Force (the on/off switch) draws right away.
    try{
        if(-not $Force){
            $shown=[bool]$script:Yum.Window.IsVisible -and $script:Yum.Window.WindowState -ne [System.Windows.WindowState]::Minimized
            if(-not $shown){return}
            if(((Get-Date)-[datetime]$script:Yum['LastCpuBalanceUi']).TotalMilliseconds -lt 950){return}
        }
        $script:Yum['LastCpuBalanceUi']=Get-Date
    }catch{}
    try{ Update-YumCpuCardUi }catch{}
    try{
        $ui=$script:Yum.Ui;if($null -eq $ui -or $null -eq $ui['CpuBalanceText']){return}
        $s=Get-YumCpuBalanceSummary
        $ui.CpuBalanceText.Text=[string]$s.Text
        $ui.CpuBalanceCount.Text=if(-not $s.Count){''}elseif([string]$s.Count -match '^0 '){'Has not needed to step in today.'}else{'Stepped in '+[string]$s.Count+'.'}
        $ui.CpuBalancePill.Visibility=if($s.Active){'Visible'}else{'Collapsed'}
        try{$cst=Get-YumCpuBalanceState;$lv=[string]$cst['Level'];if(-not $lv){$lv=Get-YumCpuCareLevel};$ui.CpuCareTitle.Text=('CPU CARE · {0}{1}' -f $lv.ToUpperInvariant(),$(if([bool]$cst['Gaming']){' · GAMING'}else{''}));if(Test-YumCpuProfileReady){$ui.CpuCareTitle.ToolTip=(Get-YumCpuProfile).Summary}}catch{}
    }catch{}
}
function Start-YumMonitoring {
    if($null -ne $script:Yum.TelemetryTimer){return}
    $script:Yum.StopRequested=$false
    Start-YumTelemetry
    $script:Yum.MonitoringActive=$true
    $script:Yum['MonitoringStartedAt']=Get-Date
    Start-YumControllerTimer;$script:Yum.Ui.Monitor.Content='■ Stop Monitoring';$script:Yum.Ui.Status.Text='● Monitoring';if($null -ne $script:Yum.Ui.QuickMonitorStatus){$script:Yum.Ui.QuickMonitorStatus.Text='ACTIVE';$script:Yum.Ui.QuickMonitorStatus.Foreground=Get-YumBrush $script:Yum.Config.GPUColor};$script:Yum.Ui.Status.Foreground=Get-YumBrush $script:Yum.Config.GPUColor;Write-YumLog 'Monitoring started.'
}
function Stop-YumMonitoring {
    $script:Yum.MonitoringActive=$false
    Stop-YumTelemetry;$script:Yum.Ui.Monitor.Content='▶ Start Monitoring';$script:Yum.Ui.Status.Text='● Paused';if($null -ne $script:Yum.Ui.QuickMonitorStatus){$script:Yum.Ui.QuickMonitorStatus.Text='PAUSED';$script:Yum.Ui.QuickMonitorStatus.Foreground=Get-YumBrush '#FDE68A'};$script:Yum.Ui.Status.Foreground=Get-YumBrush '#FDE68A';Write-YumLog 'Monitoring stopped.'
}
function Invoke-YumApplyTarget {
    try{$v=0.0;$ok=[double]::TryParse($script:Yum.Ui.TargetBox.Text.Trim(),[Globalization.NumberStyles]::Float,[Globalization.CultureInfo]::InvariantCulture,[ref]$v);if(-not $ok -or $v -le 0){Show-YumMessage -Message 'Enter a valid Available RAM target greater than 0 GB.' -Title 'YUMRAM - Invalid Target' -Buttons 'OK' -Icon 'Warning';return};$s=Get-YumSnapshotCopy;$m=if($s){$s.Memory}else{Get-YumMemoryTelemetry};if($null -eq $m -or $v -gt $m.TotalGB){Show-YumMessage -Message 'The target must be greater than 0 and no more than installed RAM.' -Title 'YUMRAM - Invalid Target' -Buttons 'OK' -Icon 'Warning';return};$v=[math]::Round($v,1);Update-YumConfigValue -Name MinimumAvailableGB -Value $v;Update-YumConfigValue -Name CleanupTargetAvailableGB -Value $v;$script:Yum.Ui.TargetBox.Text=$v.ToString('0.##');$script:Yum.ControllerBackoffSeconds=0.0;Update-YumTargetUi;$est=$script:Yum.ReachableEstimate;if($null -ne $est -and $v -gt ([double]$m.AvailableGB+[double]$est.ReclaimableGB+0.1)){Set-YumFooter ("Target set to {0} GB 💜 — note: about {1:N1} GB is reachable right now on this PC; YUMRAM will keep working toward it and back off between attempts." -f $v,([double]$m.AvailableGB+[double]$est.ReclaimableGB));Show-YumToast -Kind Warn -Text ("Memory goal set to {0} GB. About {1:N1} GB is reachable right now - YUMRAM keeps working toward it." -f $v,([double]$m.AvailableGB+[double]$est.ReclaimableGB))}else{Set-YumFooter "Target updated to $v GB 💜";Show-YumToast -Text ("Memory goal set to {0} GB." -f $v)};Write-YumLog "Minimum Available RAM target changed to $v GB."}catch{Write-YumLogException -Context 'Target apply failed' -Exception $_.Exception}
}
function Test-YumSingleInstance {try{$mutex=New-Object System.Threading.Mutex($false,'Local\YUMRAM-V5-SingleInstance');$owned=$false;try{$owned=$mutex.WaitOne(0)}catch [System.Threading.AbandonedMutexException]{$owned=$true};if(-not $owned){$mutex.Dispose();$shown=$false;try{$ev=[System.Threading.EventWaitHandle]::OpenExisting('Local\YUMRAM-V5-ShowWindow');[void]$ev.Set();$ev.Dispose();$shown=$true}catch{};if(-not $shown){[System.Windows.MessageBox]::Show('YUMRAM is already running. Look for its icon near the clock.','YUMRAM','OK','Information')|Out-Null};return $false};try{$script:Yum['ShowSignal']=New-Object System.Threading.EventWaitHandle($false,[System.Threading.EventResetMode]::AutoReset,'Local\YUMRAM-V5-ShowWindow')}catch{};$script:Yum.SingleInstanceMutex=$mutex;$script:Yum.SingleInstanceOwned=$true;return $true}catch{Write-YumLogException -Context 'Single instance check failed' -Exception $_.Exception;return $true}}
function Stop-YumSingleInstance {try{if($script:Yum.SingleInstanceOwned -and $script:Yum.SingleInstanceMutex){try{$script:Yum.SingleInstanceMutex.ReleaseMutex()}catch{};$script:Yum.SingleInstanceMutex.Dispose()}}catch{}finally{$script:Yum.SingleInstanceMutex=$null;$script:Yum.SingleInstanceOwned=$false}}
function Start-YumApplicationUi {
    $path=Join-Path $script:Yum.Root 'UI\Xaml\MainWindow.xaml';if(-not(Test-Path -LiteralPath $path)){throw "Missing main window XAML: $path"};[xml]$xaml=Read-YumXamlText -Path $path;$reader=New-Object System.Xml.XmlNodeReader $xaml;$script:Yum.Window=[Windows.Markup.XamlReader]::Load($reader);$script:Yum.Ui=[ordered]@{};foreach($n in @('Intelligence','TelemetryStatus','QuickMonitorStatus','QuickMonitorTelemetry','ModeHelp','Mode','Status','Available','Memory','CPU','GPU','GpuVram','MiniBarButton','GpuName','CpuTemp','GpuTemp','DiskTemp','GpuRing','GpuRingTrack','GpuRingState','DiskCard','DiskRing','DiskRingTrack','DiskRingState','DiskFree','DiskBusy','DiskSpeed','DiskDetail','DiskSpaceBar','DiskSpaceText','SideScanPanel','SideScanText','SideScanBar','Game','Usage','MemoryBar','Target','TargetStatus','TargetBar','Graph','FreeRam','DeepReclaim','ReclaimCenter','ReclaimStatus','Monitor','ModeBox','TargetBox','Apply','AutoGame','ProtectGame','AutoClean','PriorityBox','Processes','Settings','About','Footer','VersionStatus','MemoryRing','MemoryRingText','MemoryRingTrack','MemoryRingState','CpuRing','CpuRingText','CpuRingTrack','CpuRingState','CpuSpeed','CpuDetails','CpuBusiest','CpuCareStatus','Range30s','Range5m','Range1h','Range12h','GraphCaption','NavOverview','Startup','WindowsBloat','DiskCleanup','PageHost','OverviewPage','Sidebar','SidebarToggle','SideBrand','SideVersion','SideStatusPanel','SideRamText','SideRamBar','SideRamCompact','HotkeyHint','FreedToday','FreedTodayRuns','FreedTotal','FreedTotalRuns','CpuBalanceToggle','CpuBalanceText','CpuBalanceCount','CpuBalancePill','CpuCareTitle','UpdateBanner','UpdateNotes','UpdateInstall','UpdateTitle','UpdateText')){$script:Yum.Ui[$n]=$script:Yum.Window.FindName($n)};Apply-YumUiConfig;if($null -ne $script:Yum.Ui.VersionStatus){$script:Yum.Ui.VersionStatus.Text=('YUMRAM V{0}' -f [string]$script:Yum.Config.Version)};if($null -ne $script:Yum.Ui.SideVersion){$script:Yum.Ui.SideVersion.Text=('version {0} beta' -f [string]$script:Yum.Config.Version)}
    # 5.16.2: YUMRAM's own taskbar identity and window look (not PowerShell's).
    try{ Set-YumProcessIdentity; Register-YumWindowLook }catch{}
    # 5.15.9: start the background live readings now so the Overview has numbers when it first draws.
    try{ Start-YumLiveSampler }catch{}
    # 5.6: one window - the sidebar opens every tool as a page (UI\Shell.ps1).
    Initialize-YumShell
    try{ $script:Yum.Ui.SideScanPanel.Add_MouseLeftButtonUp({ try{ Open-YumPage -Key 'Intelligence' }catch{} }) }catch{}
    # 5.12: history graph ranges; history survives restarts as 1-minute averages.
    try{ Import-YumHistory }catch{}
    foreach($rk in @(@('Range30s','30s'),@('Range5m','5m'),@('Range1h','1h'),@('Range12h','12h'))){ try{ $btn=$script:Yum.Ui[$rk[0]]; $btn.Tag=$rk[1]; $btn.Add_Click({param($s,$e) Set-YumGraphRange -Range ([string]$s.Tag)}) }catch{} }
    try{ Set-YumGraphRange -Range '30s' }catch{}
    # 5.3.1: reclaim runs on the controller worker; the UI timer shows the result (Update-YumReclaimResultUI).
    $script:Yum.Ui.FreeRam.Add_Click({try{if(Request-YumMemoryReclaim -Mode Quick){Set-YumFooter '💜 Freeing RAM now… (window stays responsive)';$script:Yum.Ui.ReclaimStatus.Text='Freeing RAM… results appear in a few seconds.'}else{Set-YumFooter '💜 A reclaim is already running.'};Update-YumReclaimButtons}catch{Write-YumLogException -Context 'Free RAM action failed' -Exception $_.Exception;Set-YumFooter '⚠ Free RAM failed — check YUMRAM.log.'}})
    $script:Yum.Ui.DeepReclaim.Add_Click({try{if(Request-YumMemoryReclaim -Mode Deep){Set-YumFooter '💜 Deep reclaim running… (window stays responsive)';$script:Yum.Ui.ReclaimStatus.Text='Deep reclaim running… results appear in a few seconds.'}else{Set-YumFooter '💜 A reclaim is already running.'};Update-YumReclaimButtons}catch{Write-YumLogException -Context 'Deep RAM reclaim failed' -Exception $_.Exception;Set-YumFooter '⚠ Deep reclaim failed — check YUMRAM.log.'}})
    $script:Yum.Ui.Monitor.Add_Click({if($null -eq $script:Yum.TelemetryTimer){Start-YumMonitoring}else{Stop-YumMonitoring}})
    $script:Yum.Ui.Apply.Add_Click({Invoke-YumApplyTarget})
    $script:Yum.Ui.TargetBox.Add_KeyDown({param($s,$e)if($e.Key -eq [System.Windows.Input.Key]::Enter){Invoke-YumApplyTarget;$e.Handled=$true}})
    $script:Yum.Ui.ModeBox.Add_PreviewMouseWheel({param($s,$e)if(-not $s.IsDropDownOpen){$e.Handled=$true}})
    $script:Yum.Ui.PriorityBox.Add_PreviewMouseWheel({param($s,$e)if(-not $s.IsDropDownOpen){$e.Handled=$true}})
    $script:Yum.Ui.ModeBox.Add_SelectionChanged({
        if(-not $script:Yum.SuppressUiEvents -and $script:Yum.Ui.ModeBox.SelectedItem){
            $mode = [string]$script:Yum.Ui.ModeBox.SelectedItem.Tag
            if($mode -in @('Safe','Balanced','Aggressive')){
                Update-YumConfigValue -Name Mode -Value $mode
                $profile = Get-YumModeProfile
                Show-YumToast -Text ('Mode set to {0}: up to {1} programs per pass.' -f $mode,[int]$profile.PassLimit)

                if($null -ne $script:Yum.Ui.ModeHelp){
                    switch($mode){
                        'Safe' {
                            $script:Yum.Ui.ModeHelp.Text = 'Minimal intervention - low-risk candidates only, up to 8 follow-up passes, no optional apps/services.'
                        }
                        'Aggressive' {
                            $script:Yum.Ui.ModeHelp.Text = 'Maximum reclaim - broader known-safe candidates, approved optional apps/services, repeated passes toward the target.'
                        }
                        default {
                            $script:Yum.Ui.ModeHelp.Text = 'Recommended balance - moderate candidates and repeated passes toward the target without touching protected/unknown items.'
                        }
                    }
                }

                Set-YumFooter ('Mode: {0} - up to {1} process trim candidates per pass; {2} follow-up pass(es).' -f $profile.Name,$profile.PassLimit,$profile.FollowUpPasses)
            }
        }
    })
    $script:Yum.Ui.PriorityBox.Add_SelectionChanged({if(-not $script:Yum.SuppressUiEvents -and $script:Yum.Ui.PriorityBox.SelectedItem){$choice=[string]$script:Yum.Ui.PriorityBox.SelectedItem.Content;if($choice -like 'High*'){$answer=[System.Windows.MessageBox]::Show($script:Yum.Window,"High priority gives the game more CPU scheduling preference. It does not increase RAM or GPU capacity, and Microsoft recommends using High with care because a CPU-bound high-priority process can consume most available CPU time.`n`nApply High priority to detected games?",'YUMRAM - Game Priority','YesNo','Warning');if($answer -ne [System.Windows.MessageBoxResult]::Yes){$script:Yum.SuppressUiEvents=$true;try{$script:Yum.Ui.PriorityBox.SelectedIndex=0}catch{}finally{$script:Yum.SuppressUiEvents=$false};Update-YumConfigValue -Name GamePriority -Value 'KeepExisting';return}}$stored=switch -Regex ($choice){'^Keep Existing'{'KeepExisting'};'^Above Normal'{'AboveNormal'};'^High'{'High'};default{'Normal'}};Update-YumConfigValue -Name GamePriority -Value $stored}})
    $script:Yum.Ui.AutoGame.Add_Click({if(-not $script:Yum.SuppressUiEvents){Update-YumConfigValue -Name AutoDetectGames -Value ([bool]$script:Yum.Ui.AutoGame.IsChecked)}})
    $script:Yum.Ui.ProtectGame.Add_Click({if(-not $script:Yum.SuppressUiEvents){Update-YumConfigValue -Name ProtectGame -Value ([bool]$script:Yum.Ui.ProtectGame.IsChecked)}})
    $script:Yum.Ui.UpdateInstall.Add_Click({Invoke-YumInstallUpdate})
    if($null -ne $script:Yum.Ui['MiniBarButton']){ $script:Yum.Ui.MiniBarButton.Add_Click({ Show-YumMiniBar }) }
    $script:Yum.Ui.UpdateNotes.Add_Click({try{$i=$script:Yum['UpdateInfo'];if($i -and $i.PageUrl -match '^https://github\.com/'){Start-Process ([string]$i.PageUrl)}}catch{}})
    $script:Yum.Ui.CpuBalanceToggle.Add_Click({if(-not $script:Yum.SuppressUiEvents){Update-YumConfigValue -Name CpuBalanceEnabled -Value ([bool]$script:Yum.Ui.CpuBalanceToggle.IsChecked);Update-YumCpuBalanceUi -Force;Set-YumFooter $(if([bool]$script:Yum.Ui.CpuBalanceToggle.IsChecked){'CPU balance on 💜'}else{'CPU balance off - anything YUMRAM held back is put back now.'})}})
    $script:Yum.Ui.AutoClean.Add_Click({if(-not $script:Yum.SuppressUiEvents){Update-YumConfigValue -Name AutoCleanOnGameStart -Value ([bool]$script:Yum.Ui.AutoClean.IsChecked)}})
    $script:Yum.Window.Add_SizeChanged({Update-YumGraph})
    # 5.4: the main window runs with Show() + a DispatcherFrame instead of ShowDialog(), because hiding a
    # ShowDialog window (minimize to tray) ends the dialog and would quit YUMRAM.
    $script:Yum.MainFrame=New-Object System.Windows.Threading.DispatcherFrame
    $script:Yum.Window.Add_Closed({try{Save-YumHistory}catch{};try{if($null -ne $script:Yum.PageFrame){$script:Yum.PageFrame.Continue=$false}}catch{};try{if($null -ne $script:Yum.Hotkey){$script:Yum.Hotkey.Dispose();$script:Yum.Hotkey=$null}}catch{};try{Remove-YumTray}catch{};try{Close-YumMiniBar}catch{};try{Stop-YumVramSampler}catch{};try{Stop-YumLiveSampler}catch{};$script:Yum.StopRequested=$true;Stop-YumMonitoring;try{Stop-YumControllerWorker}catch{};try{[YumForegroundHook]::Stop()}catch{};try{Stop-YumCpuBalanceWorker}catch{};try{if($null -ne $script:Yum.UiTimer){$script:Yum.UiTimer.Stop()}}catch{};Restart-YumOptionalServices;Write-YumLog 'YUMRAM closed.';Stop-YumSingleInstance;try{$script:Yum.MainFrame.Continue=$false}catch{}})
    # 5.15.2: X keeps YUMRAM running in the background; Windows signing out / shutting down still quits cleanly.
    $script:Yum.Window.Add_Closing({ param($s,$e) try{ if(Test-YumCloseToBackground){ $e.Cancel=$true; Invoke-YumCloseToBackground } }catch{} })
    try{
        $script:Yum.Window.Add_SourceInitialized({
            try{ Set-YumWindowLook -Window $script:Yum.Window -Main }catch{}   # 5.16.2: icon, taskbar identity, dark title bar
            try{ $src=[System.Windows.Interop.HwndSource]::FromHwnd((New-Object System.Windows.Interop.WindowInteropHelper($script:Yum.Window)).Handle)
                 $src.AddHook([System.Windows.Interop.HwndSourceHook]{ param($h,$msg,$wp,$lp,[ref]$handled) if($msg -eq 0x11 -or $msg -eq 0x16){ $script:Yum['ExitRequested']=$true }; [IntPtr]::Zero }) }catch{}
        })
    }catch{}
    $script:Yum.Window.Add_StateChanged({
        try{
            if($script:Yum.Window.WindowState -eq [System.Windows.WindowState]::Minimized){
                if(Test-YumMiniBarPreferred){ Show-YumMiniBar }   # 5.15.2: floating mini bar instead of disappearing
                elseif($null -ne $script:Yum.TrayIcon -and [bool]$script:Yum.Config['MinimizeToTray']){ Hide-YumToTray }
            }
        }catch{}
    })
    if([bool]$script:Yum.Config['ShowTrayIcon']){ try{ Initialize-YumTray }catch{ Write-YumLogException -Context 'Tray icon failed; continuing without it' -Exception $_.Exception } }
    $timer=New-Object System.Windows.Threading.DispatcherTimer;$timer.Interval=[TimeSpan]::FromSeconds([double]$script:Yum.Config.UIRefreshIntervalSeconds);$timer.Add_Tick({param($tm,$te)try{$want=if($script:Yum.Window.IsVisible){[TimeSpan]::FromSeconds([double]$script:Yum.Config.UIRefreshIntervalSeconds)}else{[TimeSpan]::FromSeconds(1)};if($tm.Interval -ne $want){$tm.Interval=$want}}catch{};try{ $sig=$script:Yum['ShowSignal']; if($null -ne $sig -and $sig.WaitOne(0)){ Show-YumMainWindow } }catch{};Update-YumUiFromSnapshot;Update-YumCpuBalanceUi;Update-YumUpdateUi;Update-YumNoticesUi;Update-YumSideScanUi;Invoke-YumDiskAutoCleanIfDue;Invoke-YumVramWatch;Update-YumAutoUpdate;try{Start-YumIntelligenceDbPreload}catch{};try{Start-YumProcessMetaWarmup}catch{};Update-YumCleanupResultUI;try{[void](Update-YumReclaimVerification)}catch{};Update-YumReclaimResultUI});$script:Yum.UiTimer=$timer;$timer.Start()
    try{$initialMemory=Get-YumMemoryTelemetry;if($null -ne $initialMemory){Update-YumSnapshot -Changes @{Memory=$initialMemory;CPU=0.0;GPU3D=0.0;ForegroundProcessId=0;Game=[pscustomobject]@{ProcessId=0;ProcessName=$null;Detected=$false}} -CoreTelemetry}}catch{Write-YumLogException -Context 'Initial memory telemetry failed' -Exception $_.Exception}
    # 5.10: the first snapshot does not bump the version counter; ask for one full draw (paused start showed '--').
    $script:Yum.UiNeedsFullRefresh=$true
    Update-YumUiFromSnapshot
    # The controller worker lives for the whole session so queued requests (safe optimization,
    # auto-clean on game start) are processed; automatic maintenance still waits for monitoring.
    try{Start-YumControllerWorker}catch{Write-YumLogException -Context 'Controller worker start failed' -Exception $_.Exception}
    # 5.8: CPU balance runs on its own worker (independent of memory monitoring, like ProBalance).
    try{Start-YumCpuBalanceWorker}catch{Write-YumLogException -Context 'CPU balance worker start failed' -Exception $_.Exception}
    try{ if(-not [YumForegroundHook]::Start()){Write-YumLog 'Foreground hook unavailable; CPU care checks app switches every second.'} }catch{}
    if([bool]$script:Yum.Config.StartMonitoringAutomatically){Start-YumMonitoring}
    $script:Yum.Window.Show()
    # 5.15.3: after an automatic update YUMRAM comes back the way it was - hidden in the tray (or the mini bar) if it was hidden.
    try{ if([bool]$script:Yum.Config['StartHiddenOnce']){ Update-YumConfigValue -Name StartHiddenOnce -Value $false; if(Test-YumMiniBarPreferred){ Show-YumMiniBar } elseif($null -ne $script:Yum.TrayIcon){ $script:Yum.TrayHintShown=$true; Hide-YumToTray } } }catch{}
    try{ $script:Yum.Window.Add_PreviewMouseDown({ $script:Yum['LastUserInput']=Get-Date }); $script:Yum.Window.Add_PreviewKeyDown({ $script:Yum['LastUserInput']=Get-Date }) }catch{}
    try{ Register-YumGlobalHotkey }catch{}
    try{ Update-YumFreedStatsUi }catch{}
    # 5.10: once-a-day GitHub release check in the background (Settings > General to turn off).
    try{ Start-YumUpdateCheck }catch{ Write-YumLogException -Context 'Update check start failed' -Exception $_.Exception }
    try{ Start-YumCommunityFetch }catch{}   # 5.15: shared game results (weekly, public file, sends nothing about you)
    [System.Windows.Threading.Dispatcher]::PushFrame($script:Yum.MainFrame)   # returns when the window closes
}
function Update-YumReclaimButtons {
    try{
        $busy=Test-YumReclaimBusy
        $script:Yum.Ui.FreeRam.IsEnabled=-not $busy
        $script:Yum.Ui.DeepReclaim.IsEnabled=-not $busy
    }catch{}
}
function Update-YumReclaimResultUI {
    # Shows the result of a reclaim the controller worker finished (and later verification updates).
    try{
        Update-YumReclaimButtons
        $v=[int]$script:Yum.ReclaimResultVersion
        if($v -eq [int]$script:Yum.LastUiReclaimResultVersion){return}
        $script:Yum.LastUiReclaimResultVersion=$v
        $r=$script:Yum.LastReclaim
        if($null -eq $r -or $null -eq $r.PSObject.Properties['Summary']){return}
        $text=[string]$r.Summary
        # 5.6: count the measured Available gain once per reclaim (verification updates reuse the version counter).
        try{$key=if($r.PSObject.Properties['Timestamp']){([datetime]$r.Timestamp).Ticks.ToString()}else{$text};if($key -ne [string]$script:Yum.LastStatReclaimKey -and $r.PSObject.Properties['AvailableGainGB']){$script:Yum.LastStatReclaimKey=$key;Add-YumFreedStat -GainGB ([double]$r.AvailableGainGB) -Source 'Reclaim'}}catch{}
        # 5.11: Available often keeps rising for a few seconds after the result; show the highest gain and
        # count the extra in the "RAM freed" card once.
        try{
            if($r.PSObject.Properties['PeakGainGB'] -and [double]$r.PeakGainGB -gt ([double]$r.AvailableGainGB+0.15)){
                $text+=(' It kept rising to +{0:N2} GB after {1} s as Windows finished.' -f [double]$r.PeakGainGB,[int]$r.PeakGainAtSeconds)
                $peakKey=([string]$script:Yum.LastStatReclaimKey)+'|peak'
                if([string]$script:Yum['LastStatPeakKey'] -ne $peakKey -or [double]$script:Yum['LastStatPeakGB'] -lt [double]$r.PeakGainGB){
                    $already=if([string]$script:Yum['LastStatPeakKey'] -eq $peakKey){[double]$script:Yum['LastStatPeakGB']}else{[double]$r.AvailableGainGB}
                    $extra=[double]$r.PeakGainGB-$already
                    if($extra -gt 0.01){Add-YumFreedStat -GainGB $extra -Source 'Reclaim (kept rising)' -SameReclaim}
                    $script:Yum['LastStatPeakKey']=$peakKey;$script:Yum['LastStatPeakGB']=[double]$r.PeakGainGB
                }
            }
        }catch{}
        if($r.PSObject.Properties['RetainedGainGB'] -and $null -ne $r.RetainedGainGB){$text+=(' Retained after 30s: +{0:N2} GB.' -f [double]$r.RetainedGainGB)}
        $script:Yum.Ui.ReclaimStatus.Text=$text
        $script:Yum.Ui.ReclaimStatus.ToolTip=$text
        Set-YumFooter ('💜 '+$text)
        # A reclaim started from the tray reports back there while the window is hidden.
        if([bool]$script:Yum.TrayReclaimPending -and -not (Test-YumReclaimBusy)){
            $script:Yum.TrayReclaimPending=$false
            if(-not $script:Yum.Window.IsVisible){
                $gain=if($r.PSObject.Properties['AvailableGainGB']){[double]$r.AvailableGainGB}else{0.0}
                Show-YumTrayNotice -Title 'YUMRAM freed RAM' -Text ('Available RAM +{0:N2} GB. {1}' -f $gain,[string]$r.Summary)
            }
        }
    }catch{Write-YumLogException -Context 'Reclaim result UI failed' -Exception $_.Exception}
}
function Update-YumCleanupResultUI {
    $v=0;$r=$null;[System.Threading.Monitor]::Enter($script:Yum.CacheLock);try{$v=$script:Yum.CleanupResultVersion;$r=$script:Yum.CleanupResult}finally{[System.Threading.Monitor]::Exit($script:Yum.CacheLock)}
    if($v -le $script:Yum.LastUiCleanupResultVersion -or $null -eq $r){return};$script:Yum.LastUiCleanupResultVersion=$v
    try{if($r.Success -and $r.PSObject.Properties['AvailableImprovementGB']){Add-YumFreedStat -GainGB ([double]$r.AvailableImprovementGB) -Source 'Automatic'}}catch{}
    if($r.Success -and $r.TargetReached){$suffix=if($r.PSObject.Properties['StopReason']){' • '+[string]$r.StopReason}else{''};Set-YumFooter ('🎯 Target reached: {0:N2} GB available | reclaimed {1:N0} MB | Available +{2:N2} GB{3}' -f $r.AfterAvailableGB,(($r.WorkingSetReduced)/1MB),[double]$r.AvailableImprovementGB,$suffix)}elseif($r.Success -and $r.WorkingSetReduced -gt 0){$suffix=if($r.PSObject.Properties['StopReason']){' • '+[string]$r.StopReason}else{''};Set-YumFooter ('✨ Cleanup: {0:N0} MB WS reduced | Available +{1:N2} GB | Target {2:N2} GB | Shortfall {3:N2} GB{4}' -f (($r.WorkingSetReduced)/1MB),$r.AvailableImprovementGB,$r.TargetGB,[double]$r.TargetShortfallGB,$suffix)}elseif($r.Skipped){Set-YumFooter "Cleanup skipped — $($r.Reason)."}elseif($r.Success){$suffix=if($r.PSObject.Properties['StopReason']){' • '+[string]$r.StopReason}else{''};Set-YumFooter ('Cleanup completed — target shortfall {0:N2} GB{1}' -f [double]$r.TargetShortfallGB,$suffix)}else{Set-YumFooter "Cleanup failed — $($r.Reason)."}
}
function Start-YumRamApplication {
    Write-YumLog 'Startup phase: initializing configuration.'
    Initialize-YumConfig
    Write-YumLog 'Startup phase: configuration initialized.'

    try {
        $researchPath = Join-Path $script:Yum.Root 'Core\Research.ps1'
        if(Test-Path -LiteralPath $researchPath){
            . $researchPath
            Write-YumLog 'Startup phase: intelligence research module loaded.'
        }
        else {
            Write-YumLog 'Startup phase: research module not present; continuing without online research.'
        }
    }
    catch {
        Write-YumLogException -Context 'Startup research module load failed' -Exception $_.Exception
    }

    Write-YumLog 'Startup phase: restoring interrupted state.'
    Restore-YumInterruptedServiceStops
    Write-YumLog 'Startup phase: interrupted state restored.'
    Write-YumLog 'Startup phase: elevation check.'

    if(-not (Start-YumElevated)){
        Write-YumLog 'Startup phase: elevation relaunch requested; exiting unelevated instance.'
        return
    }

    Write-YumLog 'Startup phase: single-instance check.'
    if(-not (Test-YumSingleInstance)){
        return
    }

    Write-YumLog ("YUMRAM {0} starting." -f $script:Yum.Config.Version)
    Write-YumLog 'Startup phase: loading main UI.'
    Start-YumApplicationUi
}
