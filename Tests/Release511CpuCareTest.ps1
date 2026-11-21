#requires -Version 5.1
# 5.11 CPU care: machine profile from Windows (no CPU database), levels, and every step is undone.
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'App\Bootstrap.ps1')
Initialize-YumConfig
$script:Yum.Config.Logging=$false
function Assert-That([bool]$Condition,[string]$Message){if(-not $Condition){throw $Message}}

# 1. Machine profile.
$pr=Get-YumCpuProfile
Assert-That ($pr.Cores -ge 1 -and $pr.Logical -ge $pr.Cores) "Profile must report cores/threads: $($pr.Summary)"
$expectedAll=if($pr.Logical -ge 64){[uint64]::MaxValue}else{[uint64]([math]::Pow(2,$pr.Logical)-1)}
Assert-That ([uint64]$pr.AllMask -eq $expectedAll) ("All-cores mask 0x{0:X} must cover {1} logical CPUs." -f [uint64]$pr.AllMask,$pr.Logical)
if($pr.Cores -ge 4){
    Assert-That ([uint64]$pr.HogMask -ne 0 -and [uint64]$pr.HogMask -ne [uint64]$pr.AllMask) 'With 4+ cores a hog must be confined to a strict subset.'
    Assert-That (([uint64]$pr.HogMask -band [uint64]$pr.AllMask) -eq [uint64]$pr.HogMask) 'The hog mask must only contain real logical CPUs.'
    Assert-That ($pr.FreeCores -ge 2) 'Your app must keep at least 2 whole cores.'
    # Whole cores: a core is either fully inside or fully outside the hog mask (never split SMT siblings).
    foreach($c in [YumCpuCareNative]::Cores){ $in=([uint64]$c.Mask -band [uint64]$pr.HogMask); Assert-That ($in -eq 0 -or $in -eq [uint64]$c.Mask) 'Making room must never split a core between your app and a hog.' }
}

# 2. Level.
$script:Yum.Config['CpuCareLevel']='Strong';$script:Yum.Config['CpuCareStrongOnBattery']=$false
Assert-That ((Get-YumCpuCareLevel) -eq 'Strong') 'Configured level must be used.'
$script:Yum.Config['CpuCareLevel']='Nonsense'
Assert-That ((Get-YumCpuCareLevel) -eq 'Balanced') 'Unknown level falls back to Balanced.'

# 3. Every step is undone, only on the same process and only where nobody changed it since.
$tmp=Join-Path $env:TEMP ('yum-care-'+[guid]::NewGuid().ToString('N'));New-Item -ItemType Directory $tmp|Out-Null;$script:Yum.ConfigDirectory=$tmp
$p=Start-Process ping.exe -ArgumentList '-n','30','127.0.0.1' -WindowStyle Hidden -PassThru
try{
    Start-Sleep -Milliseconds 300
    $orig=[uint64][int64]$p.ProcessorAffinity
    $mask=if([uint64]$pr.HogMask -ne 0){[uint64]$pr.HogMask}else{[uint64]1}
    $p.PriorityClass='Idle';$p.ProcessorAffinity=[IntPtr][int64]$mask
    [void][YumCpuCareNative]::EcoQoS($p.Id,$true);[void][YumCpuCareNative]::MemoryPriority($p.Id,2)
    $st=Get-YumCpuBalanceState
    $st.Restrained[$p.Id]=@{Id=$p.Id;Name='PING';Since=Get-Date;StartTicks=$p.StartTime.Ticks;LastPercent=0;CalmTicks=0;AppliedPriority='Idle';RoomMask=$mask;OriginalAffinity=$orig;Eco=$true;Mem=$true;Room=$true}
    Save-YumCpuBalanceRestrained
    Restore-YumCpuBalanceInterrupted    # crash recovery path reads the saved file
    $p.Refresh()
    Assert-That ($p.PriorityClass -eq 'Normal') "Priority must be restored (got $($p.PriorityClass))."
    Assert-That ([uint64][int64]$p.ProcessorAffinity -eq $orig) 'All cores must be given back.'
    # A change by someone else after ours is left alone.
    $p.ProcessorAffinity=[IntPtr][int64]1
    $st.Restrained[$p.Id]=@{Id=$p.Id;Name='PING';Since=Get-Date;StartTicks=$p.StartTime.Ticks;LastPercent=0;CalmTicks=0;AppliedPriority='BelowNormal';RoomMask=$mask;OriginalAffinity=$orig;Eco=$false;Mem=$false;Room=$true}
    if($mask -ne 1){ Restore-YumCpuBalanceProcess -Record $st.Restrained[$p.Id] -Why 'test'; $p.Refresh(); Assert-That ([uint64][int64]$p.ProcessorAffinity -eq 1) 'Cores set by someone else afterwards must be left alone.' }
}finally{try{$p.Kill()}catch{};Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue}

# 4. Rules found by measurement stay in place.
$cb=Get-Content -Raw (Join-Path $root 'Core\CpuBalance.ps1')
Assert-That ($cb -match '\$pcCalm=\(\$total -lt \((\$cfg\.SystemPercent|\$busyAt)-20\)\) -and \(\[uint64\]\$r\.RoomMask -eq 0\)')   # 5.15.2: threshold is $busyAt (50 % while gaming) 'With room made, only the hog calming down may restore it (no flip-flop).'
Assert-That ($cb -match 'undid room for' -and $cb -match 'FgBefore') 'Making room must be checked and undone if your app got less CPU.'
Assert-That ($cb -match 'YumForegroundHook' -and $cb -match 'WaitAny') 'App switches must wake CPU care at once.'
Assert-That ($cb -match '\$gaming=') 'Games must get room right away.'
# 5. Display honesty (user report: Deep said +2.90 GB but "free" jumped more) and the CPU card.
$lists=Get-YumMemoryListsGB
Assert-That ($null -ne $lists -and [double]$lists.FreeGB -ge 0 -and [double]$lists.StandbyGB -ge 0) 'Free and Standby must be measurable.'
$mr=Get-Content -Raw (Join-Path $root 'Core\MemoryReclaim.ps1')
Assert-That ($mr -match 'standby cache was emptied' -and $mr -match 'FreeJumpGB' -and $mr -match 'PeakGainGB') 'Reclaim must explain a Free jump and report a gain that kept rising.'
Assert-That ($mr -match "'Skipped'") 'Admin-only steps must show as Skipped, not Failed.'
$mw=Get-Content -Raw (Join-Path $root 'UI\MainWindow.ps1')
Assert-That ($mw -notmatch 'auto-scaled range') 'All graph lines must share one 0-100 % scale.'
Assert-That ($mw -notmatch "'\[OK\]'") 'Status pills use words, not [BRACKETS].'
Assert-That ($mw -match 'function Update-YumCpuCardUi' -and $mw -match 'Update-YumRing -Ring \$script:Yum.Ui.CpuRing') 'The Overview must show CPU like RAM (ring + card).'
[xml]$x=Get-Content -Raw (Join-Path $root 'UI\Xaml\MainWindow.xaml')
$names=@($x.SelectNodes('//*[@*[local-name()="Name"]]') | ForEach-Object { $_.GetAttribute('Name','http://schemas.microsoft.com/winfx/2006/xaml') })
foreach($n in 'CpuRing','CpuRingTrack','CpuRingText','CpuRingState','CpuSpeed','CpuDetails','CpuBusiest','CpuCareStatus','MemoryRingTrack','MemoryRingState'){Assert-That ($names -contains $n) "Overview is missing $n"}
$tw=Get-Content -Raw (Join-Path $root 'Core\TelemetryWorker.ps1')
Assert-That ($tw -match "% Processor Performance" -and $tw -match "'System','Threads'") 'CPU speed, processes and threads come from Windows counters.'
Write-Host ('Release 5.11 CPU care test passed ({0}).' -f $pr.Summary)
