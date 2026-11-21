#requires -Version 5.1
<#
Compares the CPU care of two YUMRAM versions with the same game benchmark (Tools\Bench-CpuCare.ps1), so every
release is checked for improvement AND loss against the previous one.

  powershell -NoProfile -ExecutionPolicy Bypass -STA -File Tools\Compare-Versions.ps1 -Old v5.14.0
  -Old   a git tag/commit of this repository (checked out to a temporary worktree) or a folder with a YUMRAM copy
  -New   folder (default: this repository)
  -Passes N  (default 3) passes; each pass runs both versions, alternating which goes first, so laptop heat
             drift does not favour either. Same calibrated workload for both. Medians over passes.

Verdict per case: "better" / "worse" when the median 1 % low (or average FPS) differs by more than the noise
margin (default 10 %); otherwise "same". CPU care "Off" runs identical code in both versions - they are the
control and show how big run-to-run noise is on this PC.
Output: <OutDir>\compare.md and compare.json.
#>
param([Parameter(Mandatory)][string]$Old,[string]$New='',[string]$OutDir=(Join-Path $env:TEMP 'yum-compare'),[int]$Passes=3,[int]$Seconds=12,[ValidateSet('Full','User','Quick')][string]$Profile='Quick',[double]$Margin=10,[string]$OnlyGame='',[string]$OnlyHog='')
$ErrorActionPreference='Stop'
$repo=Split-Path -Parent $PSScriptRoot
if(-not $New){$New=$repo}
New-Item -ItemType Directory -Path $OutDir -Force | Out-Null
$bench=Join-Path $PSScriptRoot 'Bench-CpuCare.ps1'
$oldRoot=$Old;$worktree=$null
if(-not (Test-Path -LiteralPath $Old)){
    $worktree=Join-Path $env:TEMP ('yum-old-'+[guid]::NewGuid().ToString('N'))
    & git -C $repo fetch -q --tags 2>$null
    & git -C $repo worktree add -q --detach $worktree $Old 2>&1 | Out-Null
    if(-not (Test-Path (Join-Path $worktree 'App\Bootstrap.ps1'))){throw ('Could not check out {0}.' -f $Old)}
    $oldRoot=$worktree
}
$oldVer=(Get-Content (Join-Path $oldRoot 'VERSION') -ErrorAction SilentlyContinue | Select-Object -First 1); $newVer=(Get-Content (Join-Path $New 'VERSION') -ErrorAction SilentlyContinue | Select-Object -First 1)
try{
    $perMs=0;$runs=@{Old=New-Object System.Collections.Generic.List[object];New=New-Object System.Collections.Generic.List[object]}
    for($pass=1;$pass -le $Passes;$pass++){
        $order=if($pass % 2){@('Old','New')}else{@('New','Old')}
        foreach($which in $order){
            $root=if($which -eq 'Old'){$oldRoot}else{$New}
            $out=Join-Path $OutDir ('{0}-pass{1}' -f $which,$pass)
            $a=@('-NoProfile','-ExecutionPolicy','Bypass','-STA','-File',$bench,'-OutDir',$out,'-Seconds',[string]$Seconds,'-Repeat','1','-Profile',$Profile,'-CodeRoot',$root)
            if($perMs -gt 0){$a+=@('-PerMs',[string]$perMs)}
            if($OnlyGame){$a+=@('-OnlyGame',$OnlyGame)}; if($OnlyHog){$a+=@('-OnlyHog',$OnlyHog)}
            Write-Host ('pass {0}/{1}: {2} ({3})' -f $pass,$Passes,$which,$root)
            & powershell.exe @a | Out-Null
            $j=Get-Content (Join-Path $out 'cpu-bench.json') -Raw | ConvertFrom-Json
            if($perMs -le 0){$perMs=[int64]$j.Calibration}
            foreach($r in @($j.Results)){ [void]$runs[$which].Add($r) }
        }
    }
    function Get-Med([double[]]$v){ $s=@($v | Sort-Object); if($s.Count -eq 0){return 0}; $k=[int][math]::Floor($s.Count/2); if($s.Count % 2){return $s[$k]}; return ($s[$k-1]+$s[$k])/2 }
    $rows=@()
    foreach($g in @($runs.New | Group-Object Game,Hog,Level)){
        $f=$g.Group[0]
        $o=@($runs.Old | Where-Object { $_.Game -eq $f.Game -and $_.Hog -eq $f.Hog -and $_.Level -eq $f.Level })
        if($o.Count -eq 0){continue}
        $nl=Get-Med @($g.Group|ForEach-Object{[double]$_.Low1Fps});$ol=Get-Med @($o|ForEach-Object{[double]$_.Low1Fps})
        $na=Get-Med @($g.Group|ForEach-Object{[double]$_.AvgFps});$oa=Get-Med @($o|ForEach-Object{[double]$_.AvgFps})
        $dl=if($ol -gt 0){($nl/$ol-1)*100}else{0};$da=if($oa -gt 0){($na/$oa-1)*100}else{0}
        $verdict=if($dl -ge $Margin -or ($da -ge $Margin -and $dl -gt -$Margin)){'better'}elseif($dl -le -$Margin -or $da -le -$Margin){'WORSE'}else{'same'}
        $rows+=[pscustomobject]@{Game=$f.Game;Load=$f.Hog;Level=$f.Level;OldAvg=[math]::Round($oa,1);NewAvg=[math]::Round($na,1);AvgChange=[math]::Round($da,0);OldLow1=[math]::Round($ol,1);NewLow1=[math]::Round($nl,1);Low1Change=[math]::Round($dl,0);Verdict=$verdict;Control=($f.Level -eq 'Off')}
    }
    $ctl=@($rows | Where-Object { $_.Control -and $_.Load -ne 'None' })
    $noise=if($ctl.Count){ [math]::Round((Get-Med @($ctl | ForEach-Object { [math]::Abs([double]$_.Low1Change) })),0) }else{0}
    $better=@($rows | Where-Object { -not $_.Control -and $_.Verdict -eq 'better' }).Count
    $worse=@($rows | Where-Object { -not $_.Control -and $_.Verdict -eq 'WORSE' }).Count
    $md=New-Object System.Text.StringBuilder
    [void]$md.AppendLine(('# YUMRAM {0} ({2}) vs {1} - CPU care game benchmark' -f $newVer,$oldVer,$(if($New -eq $repo){'this repository'}else{$New}))).AppendLine()
    [void]$md.AppendLine(('{0} passes x {1} s per case, alternating order, same workload. Margin {2} %. Control (CPU care Off, identical code): median difference {3} % = run-to-run noise on this PC.' -f $Passes,$Seconds,$Margin,$noise)).AppendLine()
    [void]$md.AppendLine(('**Result: {0} cases better, {1} worse, {2} the same** (CPU care on).' -f $better,$worse,(@($rows | Where-Object { -not $_.Control }).Count-$better-$worse))).AppendLine()
    [void]$md.AppendLine('| Game | Load | CPU care | Avg FPS old → new | 1 % low old → new | Verdict |').AppendLine('|---|---|---|---|---|---|')
    foreach($r in @($rows | Sort-Object Game,Load,Level)){ [void]$md.AppendLine(('| {0} | {1} | {2}{3} | {4} → {5} ({6:+0;-0;0} %) | {7} → {8} ({9:+0;-0;0} %) | {10} |' -f $r.Game,$r.Load,$r.Level,$(if($r.Control){' (control)'}else{''}),$r.OldAvg,$r.NewAvg,$r.AvgChange,$r.OldLow1,$r.NewLow1,$r.Low1Change,$(if($r.Control){'-'}else{$r.Verdict}))) }
    [void]$md.AppendLine().AppendLine('## Every pass').AppendLine().AppendLine('| Version | Game | Load | CPU care | Avg FPS | 1 % low |').AppendLine('|---|---|---|---|---:|---:|')
    foreach($w in 'Old','New'){ foreach($x in @($runs[$w] | Sort-Object Game,Hog,Level)){ [void]$md.AppendLine(('| {0} | {1} | {2} | {3} | {4} | {5} |' -f $w,$x.Game,$x.Hog,$x.Level,$x.AvgFps,$x.Low1Fps)) } }
    Set-Content -LiteralPath (Join-Path $OutDir 'compare.md') -Value $md.ToString() -Encoding UTF8
    [pscustomobject]@{Old=$oldVer;New=$newVer;Passes=$Passes;NoisePercent=$noise;Better=$better;Worse=$worse;Rows=$rows} | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $OutDir 'compare.json') -Encoding UTF8
    Write-Host ('{0} better, {1} worse (noise ~{2} %) -> {3}' -f $better,$worse,$noise,(Join-Path $OutDir 'compare.md'))
}finally{
    if($worktree){ & git -C $repo worktree remove --force $worktree 2>$null | Out-Null }
}
