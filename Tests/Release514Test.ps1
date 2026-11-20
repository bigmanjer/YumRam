#requires -Version 5.1
# 5.14 (beta): big programs trimmed in chunks, CPU care no longer pauses or misleads RAM care, two-lane
# graph, "applied" confirmations.
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'App\Bootstrap.ps1')
Initialize-YumConfig
$script:Yum.Config.Logging=$false
function Assert-That([bool]$Condition,[string]$Message){if(-not $Condition){throw $Message}}
$tmp=Join-Path $env:TEMP ('yum-514-'+[guid]::NewGuid().ToString('N'));New-Item -ItemType Directory $tmp|Out-Null
$src=Join-Path $tmp 'yumbig.cs'
Set-Content -LiteralPath $src -Encoding ASCII -Value 'using System;using System.Threading;static class B{static void Main(){var k=new byte[16][];for(int i=0;i<16;i++){k[i]=new byte[100*1024*1024];for(int j=0;j<k[i].Length;j+=4096)k[i][j]=1;}Thread.Sleep(60000);GC.KeepAlive(k);}}'
& (Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe') /nologo /out:"$(Join-Path $tmp 'yumbig.exe')" $src | Out-Null
$p=Start-Process -FilePath (Join-Path $tmp 'yumbig.exe') -PassThru -WindowStyle Hidden
try{
    Start-Sleep -Seconds 5; $p.Refresh()
    Assert-That ($p.WorkingSet64 -gt 1400MB) ('Test program should hold ~1.6 GB, has {0:N0} MB.' -f ($p.WorkingSet64/1MB))

    # 1. Plan: a program over the per-pass budget is trimmed partly when small ones cannot close the gap.
    $fake=@([pscustomobject]@{Process=$p;WorkingSet=$p.WorkingSet64;Score=130;CPU=1},[pscustomobject]@{Process=[pscustomobject]@{Id=1};WorkingSet=150MB;Score=40;CPU=0})
    $plan=@(Get-YumTrimPlan -Candidates $fake -AvailableGB 2.0 -TargetGB 3.0 -PassLimit 10 -MaxTrimMBPerPass 1024)
    $part=@($plan | Where-Object { $_.PSObject.Properties['TrimMB'] })
    Assert-That ($part.Count -eq 1 -and [int]$part[0].Process.Id -eq $p.Id) 'Big program is planned as a partial trim.'
    Assert-That ([double]$part[0].TrimMB -le 1024 -and [double]$part[0].TrimMB -ge 128) ('Partial trim stays within the budget ({0} MB).' -f $part[0].TrimMB)
    $planBig=@(Get-YumTrimPlan -Candidates $fake -AvailableGB 2.0 -TargetGB 3.0 -PassLimit 10 -MaxTrimMBPerPass 4096)
    Assert-That (@($planBig | Where-Object { $_.PSObject.Properties['TrimMB'] }).Count -eq 0) 'Within budget it is trimmed whole, not partly.'

    # 2. Partial trim takes exactly about that much and leaves no hard limit.
    $before=$p.WorkingSet64
    $r=Invoke-YumReduceWorkingSet -Process $p -ReduceBytes 600MB
    Assert-That $r.Success ('Partial trim failed: {0}' -f $r.Reason)
    $took=($before-$r.After)/1MB
    Assert-That ($took -ge 450 -and $took -le 750) ('Partial trim took {0:N0} MB, wanted ~600 MB (not the whole program).' -f $took)
    $mn=[UIntPtr]::Zero;$mx=[UIntPtr]::Zero;$fl=[uint32]0;[void][YumRamWorkingSet]::GetProcessWorkingSetSizeEx($p.Handle,[ref]$mn,[ref]$mx,[ref]$fl)
    Assert-That (($fl -band 4) -eq 0) 'No hard working-set maximum is left on the program.'

    # 3. CPU care: a held-back program gets no "low priority = idle" trim bonus.
    $p.PriorityClass='BelowNormal'
    $script:Yum.Config.ProtectedProcesses=@()
    $scoreOf={ $c=@(Get-YumCandidateProcesses -ForegroundPid 0 -GamePid 0 -Mode Aggressive | Where-Object { [int]$_.Process.Id -eq $p.Id }); if($c.Count){[double]$c[0].PriorityWeight}else{$null} }
    $w1=& $scoreOf
    if($null -ne $w1){
        $script:Yum['CpuBalance']=[hashtable]::Synchronized(@{Restrained=[hashtable]::Synchronized(@{([int]$p.Id)=@{Id=[int]$p.Id;LastPercent=50.0}})})
        $script:Yum.CleanupCandidateSnapshot=$null
        $w2=& $scoreOf
        Assert-That ($w1 -eq 3 -and $w2 -eq 0) ('Priority weight: own BelowNormal {0}, CPU-care BelowNormal {1} (want 3 and 0).' -f $w1,$w2)
    } else {
        # Unsigned test programs are "Unknown" and never candidates; check the rule in the source instead.
        Assert-That ([IO.File]::ReadAllText((Join-Path $root 'Core\Safety.ps1')) -match 'Restrained\.ContainsKey\(\[int\]\$p\.Id\)\)\{ \$priorityWeight=0') 'CPU-care priority gives no trim bonus.'
    }
}finally{ try{$p.Kill()}catch{}; Start-Sleep -Milliseconds 500; Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue }

# 4. CPU safety limit ignores CPU used by held-back programs.
$cleanup=[IO.File]::ReadAllText((Join-Path $root 'Core\Cleanup.ps1'))
Assert-That ($cleanup -match '\$cpuForSafety-\$held' -and $cleanup -match '\$cpuForSafety -ge') 'CPU safety limit subtracts held-back CPU.'
Assert-That ($cleanup -match 'Invoke-YumReduceWorkingSet') 'Cleanup uses the partial trim.'

# 5. Graph: two lanes, goal line, gaps break lines.
$main=[IO.File]::ReadAllText((Join-Path $root 'UI\MainWindow.ps1'))
foreach($s in 'Set-YumGraphPath -Path \$L\.Avail','Set-YumGraphPath -Path \$L\.Cpu','Set-YumGraphPath -Path \$L\.Gpu','goal \{0:0\.#\} GB','BeginFigure'){ Assert-That ($main -match $s) ("Graph code missing: {0}" -f $s) }
Assert-That ($main -notmatch 'function Update-YumGraphLegacy') 'Old graph code removed.'

# 6. Confirmations.
$xaml=[IO.File]::ReadAllText((Join-Path $root 'UI\Xaml\MainWindow.xaml'))
Assert-That ($xaml -match 'x:Name="Toast"' -and $xaml -match 'x:Name="ToastText"') 'Toast exists in the main window.'
Assert-That ($main -match 'Show-YumToast -Text \(\x27Memory goal set' -or $main -match "Show-YumToast -Text \(""Memory goal set" -or $main -match 'Memory goal set to \{0\} GB\.') 'Memory goal Apply confirms.'
Assert-That ($main -match "Show-YumToast -Text \('Mode set to") 'Mode change confirms.'
Assert-That ([IO.File]::ReadAllText((Join-Path $root 'UI\Dialogs.ps1')) -match 'Show-YumToast -Text \(\[string\]\$u\.Validation\.Text\)') 'Settings Apply confirms.'

# 7. Beta.
Assert-That ([IO.File]::ReadAllText((Join-Path $root 'README.md')) -match 'stage-beta') 'README says beta.'
Assert-That ($main -match "version \{0\} beta") 'Sidebar says beta.'

Write-Host 'Release514Test passed.'
