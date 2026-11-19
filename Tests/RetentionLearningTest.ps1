#requires -Version 5.1
# 5.3.2: YUMRAM learns, per PC, how much of a trimmed working set actually becomes Available RAM,
# and estimates the Available RAM that is realistically reachable right now.
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'App\Bootstrap.ps1')
Initialize-YumConfig
$tmp=Join-Path $env:TEMP ('yumram-retention-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tmp -Force | Out-Null
try {
    $script:Yum.ConfigDirectory=$tmp
    $script:Yum.Config.Logging=$false
    $script:Yum.Config.ReclaimLearningEnabled=$true
    $script:Yum.ReclaimLearningLoaded=$false;$script:Yum.GlobalRetention=$null

    if([math]::Abs((Get-YumRetentionRatio)-0.4) -gt 0.001){throw 'Default retention should be 0.4 before any measurement.'}
    Update-YumGlobalRetention -AvailableGainGB 0.05 -TrimmedMB 100     # too small to count
    if($null -ne $script:Yum.GlobalRetention){throw 'A <200 MB sample must be ignored.'}
    Update-YumGlobalRetention -AvailableGainGB (600/1024) -TrimmedMB 1000   # 60 %
    if([math]::Abs((Get-YumRetentionRatio)-0.4) -gt 0.001){throw 'One sample must not replace the default yet.'}
    Update-YumGlobalRetention -AvailableGainGB (600/1024) -TrimmedMB 1000   # 60 % again
    $r=Get-YumRetentionRatio
    if([math]::Abs($r-0.6) -gt 0.001){throw "Learned retention should be 0.6 after two 60% samples, got $r"}
    Update-YumGlobalRetention -AvailableGainGB 5 -TrimmedMB 300            # absurd (>100%) -> clamped to 1.0 sample
    if((Get-YumRetentionRatio) -gt 0.9){throw 'Retention must be capped at 0.9.'}

    # Persists across restart.
    [void](Save-YumReclaimLearning)
    $before=[double]$script:Yum.GlobalRetention.Ratio
    $script:Yum.ReclaimLearningLoaded=$false;$script:Yum.GlobalRetention=$null
    Load-YumReclaimLearning
    if($null -eq $script:Yum.GlobalRetention -or [math]::Abs([double]$script:Yum.GlobalRetention.Ratio-$before) -gt 0.0001){throw 'Learned retention did not survive save/load.'}

    # Trim planner uses the learned ratio: with 0.9+ retention, a 400 MB gap needs ~445+ MB, not 1000 MB.
    $script:Yum.GlobalRetention=@{Ratio=0.8;Samples=5;Updated=''}
    function New-Fake([int]$Id,[int64]$Ws){[pscustomobject]@{Process=[pscustomobject]@{Id=$Id};PID=$Id;WorkingSet=$Ws;CPU=0.0;Score=50}}
    $plan=@(Get-YumTrimPlan -Candidates @((New-Fake 1 300MB),(New-Fake 2 300MB),(New-Fake 3 300MB)) -AvailableGB 3.6 -TargetGB 4.0 -PassLimit 5 -MaxTrimMBPerPass 4096)
    if($plan.Count -ne 2){throw "With 80% learned retention a 410 MB gap should plan 2x300 MB, got $($plan.Count)."}

    # Real estimate on this machine.
    Update-YumSnapshot -Changes @{Memory=(Get-YumMemoryTelemetry);CPU=0.0;GPU3D=0.0;ForegroundProcessId=0;Game=[pscustomobject]@{ProcessId=0;ProcessName=$null;Detected=$false}} -CoreTelemetry
    $est=Get-YumReachableEstimate -Mode 'Balanced'
    if($null -eq $est){throw 'Reachable estimate returned nothing.'}
    if([double]$est.ReachableGB -lt [double]$est.AvailableGB){throw 'Reachable cannot be below current Available.'}
    if([double]$est.ReachableGB -gt [double]$est.TotalGB){throw 'Reachable cannot exceed installed RAM.'}
    Write-Output ('PASS: retention learning works; this PC now: Available {0:N2} GB, reachable ~{1:N2} GB ({2} trimmable processes, {3:N0} MB).' -f $est.AvailableGB,$est.ReachableGB,$est.CandidateCount,$est.CandidateMB)
} finally { Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue }
