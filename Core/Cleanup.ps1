#requires -Version 5.1

function Get-YumPressureDecision {
    param([Parameter(Mandatory)]$Memory,[Parameter(Mandatory)][string]$Mode)
    $target=[double]$script:Yum.Config.MinimumAvailableGB
    $safeTarget=[double]$script:Yum.Config.MinimumAvailableGB
    $emergency=[double]$script:Yum.Config.EmergencyAvailableGB
    $threshold=switch($Mode){'Safe'{[double]$script:Yum.Config.SafePressurePercent};'Aggressive'{[double]$script:Yum.Config.AggressivePressurePercent};default{[double]$script:Yum.Config.BalancedPressurePercent}}
    $below=$Memory.AvailableGB -lt $target
    $secondaryPressureFloor=[math]::Max($target, [double]$Memory.TotalGB * 0.15)
    $high=($Memory.UsedPercent -ge $threshold -and $Memory.AvailableGB -lt $secondaryPressureFloor)
    $emergencyHit=$Memory.AvailableGB -lt $emergency
    # 5.7: the Settings "Target hysteresis" value was saved but never used. Once cleaning starts it now aims
    # this far above the goal (0-2 GB), so memory that creeps back does not re-trigger cleanup seconds later.
    $hyst=0.0;try{$hyst=[math]::Max(0.0,[math]::Min(2.0,[double]$script:Yum.Config['TargetHysteresisGB']))}catch{}
    [pscustomobject]@{ShouldClean=($below -or $high -or $emergencyHit);Emergency=$emergencyHit;Reason=if($emergencyHit){'Emergency available-memory pressure'}elseif($below){'Available RAM below target'}elseif($high){'Memory usage above mode threshold'}else{'Pressure normal'};ThresholdPercent=$threshold;StopTargetGB=([math]::Min([double]$Memory.TotalGB,$safeTarget+$hyst));HysteresisGB=$hyst}
}


function Get-YumModeProfile {
    # 5.3.1 retune, based on measurements on a 16 GB Windows 11 machine:
    # - Candidate score = (WS GB * 45) + idle (0-15) + priority + class bonus (Candidate 12, Safe 20).
    #   A typical idle 300-500 MB app scores 40-50, so the old Safe minimum (65) meant Safe mode
    #   never trimmed anything, and Balanced (38) skipped most mid-size idle apps.
    # - Only ~40% of a trimmed working set shows up as Available RAM, and only after 1-2 s, so the
    #   per-pass budgets were far too small to close a real gap.
    # 5.4: per-pass caps raised (were 4/6/10, which silently overrode larger values set in Settings)
    # and defaults raised to 6/10/16 after the 5.3 field test showed trimming could not keep up.
    switch([string]$script:Yum.Config.Mode){
        'Safe' {
            return [pscustomobject]@{Name='Safe';PassLimit=[math]::Min([int]$script:Yum.Config.SafeProcessesPerPass,10);CandidateScoreMinimum=34.0;OptionalApps=0;OptionalServices=0;FollowUpPasses=10;StepDelayMs=350;MaxPassMilliseconds=2200;MaxTrimMBPerPass=1024}
        }
        'Aggressive' {
            return [pscustomobject]@{Name='Aggressive';PassLimit=[math]::Min([int]$script:Yum.Config.AggressiveProcessesPerPass,24);CandidateScoreMinimum=12.0;OptionalApps=2;OptionalServices=0;FollowUpPasses=24;StepDelayMs=125;MaxPassMilliseconds=3200;MaxTrimMBPerPass=4096}
        }
        default {
            return [pscustomobject]@{Name='Balanced';PassLimit=[math]::Min([int]$script:Yum.Config.BalancedProcessesPerPass,16);CandidateScoreMinimum=24.0;OptionalApps=1;OptionalServices=0;FollowUpPasses=16;StepDelayMs=200;MaxPassMilliseconds=2800;MaxTrimMBPerPass=2048}
        }
    }
}

function Get-YumPassLimit {
    return [int](Get-YumModeProfile).PassLimit
}


function Get-YumGamingCleanupProfile {
    param([Parameter(Mandatory)]$BaseProfile)
    switch([string]$BaseProfile.Name){
        'Safe'      { return [pscustomobject]@{Name='Safe-Gaming';PassLimit=1;CandidateScoreMinimum=$BaseProfile.CandidateScoreMinimum;OptionalApps=0;OptionalServices=0;FollowUpPasses=$BaseProfile.FollowUpPasses;StepDelayMs=[math]::Max(400,[int]$script:Yum.Config.GamingCleanupStepDelayMs+100);MaxPassMilliseconds=[math]::Min(550,[int]$script:Yum.Config.GamingCleanupMaxPassMilliseconds);MaxTrimMBPerPass=[math]::Min(128,[int]$script:Yum.Config.GamingCleanupMaxTrimMBPerPass)} }
        'Aggressive' { return [pscustomobject]@{Name='Aggressive-Gaming';PassLimit=3;CandidateScoreMinimum=$BaseProfile.CandidateScoreMinimum;OptionalApps=0;OptionalServices=0;FollowUpPasses=$BaseProfile.FollowUpPasses;StepDelayMs=[math]::Max(200,[int]$script:Yum.Config.GamingCleanupStepDelayMs-75);MaxPassMilliseconds=[math]::Max(850,[int]$script:Yum.Config.GamingCleanupMaxPassMilliseconds+150);MaxTrimMBPerPass=[math]::Max(384,[int]$script:Yum.Config.GamingCleanupMaxTrimMBPerPass+128)} }
        default     { return [pscustomobject]@{Name='Balanced-Gaming';PassLimit=2;CandidateScoreMinimum=$BaseProfile.CandidateScoreMinimum;OptionalApps=0;OptionalServices=0;FollowUpPasses=$BaseProfile.FollowUpPasses;StepDelayMs=[int]$script:Yum.Config.GamingCleanupStepDelayMs;MaxPassMilliseconds=[int]$script:Yum.Config.GamingCleanupMaxPassMilliseconds;MaxTrimMBPerPass=[int]$script:Yum.Config.GamingCleanupMaxTrimMBPerPass} }
    }
}

function Get-YumTrimPlan {
    param(
        [object[]]$Candidates=@(),
        [Parameter(Mandatory)][double]$AvailableGB,
        [Parameter(Mandatory)][double]$TargetGB,
        [Parameter(Mandatory)][int]$PassLimit,
        [Parameter(Mandatory)][int]$MaxTrimMBPerPass,
        [switch]$FallbackMode
    )
    $gapMB=[math]::Max(0,($TargetGB-$AvailableGB)*1024.0)
    if($gapMB -le 0){ return @() }
    # 5.3.1: plan in working-set MB, not Available MB. Measured: trimming 726 MB of working set
    # raised Available RAM by ~280-315 MB (~40%) after it settled, so planning working-set MB equal
    # to the Available gap always under-trimmed and the controller stalled into fallback churn.
    # 5.3.2: use the ratio learned on this PC (Get-YumRetentionRatio) when available.
    $retention=0.4; try{ if($null -ne $script:Yum.Config['CleanupExpectedRetention']){ $retention=[double]$script:Yum.Config['CleanupExpectedRetention'] } }catch{}
    try{ if(Get-Command Get-YumRetentionRatio -ErrorAction SilentlyContinue){ $retention=Get-YumRetentionRatio } }catch{}
    $retention=[math]::Min(1.0,[math]::Max(0.15,$retention))
    $gapMB=$gapMB/$retention
    $selected=New-Object System.Collections.Generic.List[object]
    $plannedMB=0.0

    $selectionStrategy=[string]$script:Yum.Config.CleanupSelectionStrategy
    $useAdaptive=(-not $FallbackMode -and ([string]::IsNullOrWhiteSpace($selectionStrategy) -or $selectionStrategy -eq 'AdaptiveSmallestFirstThenLegacyFallback'))

    if(-not $useAdaptive){
        # Legacy/strong fallback: use the older broad ranking once the adaptive
        # path has stalled. Safety filtering still occurs before this planner.
        $ranked=@($Candidates | ForEach-Object {
            $item=$_
            $wsMB=[math]::Max(0,[double]$item.WorkingSet/1MB)
            if($wsMB -le 0){return}
            $cpu=[double]$item.CPU
            $idleBonus=[math]::Max(0,[math]::Min(25,15-$cpu))
            $sizeCenter=[math]::Max(160,[math]::Min(512,([double]$MaxTrimMBPerPass*0.75)))
            $sizeDistance=[math]::Abs($wsMB-$sizeCenter)/$sizeCenter
            $sizeBonus=[math]::Max(0,18-(18*$sizeDistance))
            $largePenalty=if($wsMB -gt 768){[math]::Min(22,($wsMB-768)/128)}else{0}
            $priority=[double]$item.Score + $idleBonus + $sizeBonus - $largePenalty
            [pscustomobject]@{Candidate=$item;Priority=$priority;WorkingSetMB=$wsMB}
        } | Sort-Object Priority -Descending)
    } else {
        # Adaptive path: prefer the smallest reclaimable working sets first,
        # then use safety/idle quality as tie-breakers. This reduces the chance
        # of evicting a large hot working set when several smaller candidates
        # can satisfy the same portion of the target gap.
        $ranked=@($Candidates | ForEach-Object {
            $item=$_
            $wsMB=[math]::Max(0,[double]$item.WorkingSet/1MB)
            if($wsMB -le 0){return}
            $cpu=[double]$item.CPU
            $idleScore=[math]::Max(0,15-[math]::Min(15,$cpu))
            $safety=[double]$item.Score
            [pscustomobject]@{Candidate=$item;Priority=$safety+$idleScore;WorkingSetMB=$wsMB}
        } | Sort-Object WorkingSetMB,@{Expression='Priority';Descending=$true})
        # 5.3.0: was "Sort-Object WorkingSetMB,Priority -Ascending"; -Ascending does not exist, so every
        # adaptive trim plan threw and automatic cleanup could never select a process.
    }

    foreach($entry in @($ranked)){
        if($selected.Count -ge $PassLimit -or $plannedMB -ge $gapMB){break}
        $wsMB=[double]$entry.WorkingSetMB
        if(($plannedMB + $wsMB) -gt $MaxTrimMBPerPass){continue}
        # Do not require the process working set to fit entirely inside the
        # remaining gap. A working-set trim is a request, not a promise to
        # reclaim the full working set, and refusing the only eligible
        # candidate can make the target mathematically unreachable.
        # Permit the first eligible candidate to exceed the remaining gap,
        # provided it stays inside the per-pass safety budget. After that,
        # keep the normal gap-aware selection rule to limit overshoot.
        $overshootMB=128.0; try{$overshootMB=[math]::Max(32,[double]$script:Yum.Config.CleanupTargetOvershootMB)}catch{}
        # 5.3.0: the first candidate is bounded only by the per-pass safety budget, as described above.
        # Previously it was also capped at gap+overshoot, so one large idle process could never be
        # chosen when Available RAM was only slightly below target.
        $allowedMB=if($selected.Count -eq 0){[double]$MaxTrimMBPerPass}else{[math]::Min([double]$MaxTrimMBPerPass,$gapMB+$overshootMB)}
        if(($plannedMB + $wsMB) -gt $allowedMB){continue}
        $already=$false
        foreach($x in $selected.ToArray()){
            try { if([int]$x.Process.Id -eq [int]$entry.Candidate.Process.Id){$already=$true;break} } catch {}
        }
        if($already){continue}
        [void]$selected.Add($entry.Candidate)
        $plannedMB += $wsMB
    }
    return $selected.ToArray()
}

function Get-YumIntelligentServiceCandidates {
    param([double]$AvailableGB,[double]$TargetGB,[int]$MaxStops=2)
    if(-not [bool]$script:Yum.Config.IntelligentServiceCleanupEnabled){return @()}
    if(($TargetGB-$AvailableGB) -lt [double]$script:Yum.Config.IntelligentServiceStopThresholdGB){return @()}
    $rows=New-Object System.Collections.Generic.List[object]
    try {
        foreach($svc in @(Get-Service -ErrorAction SilentlyContinue|Where-Object{$_.Status -eq 'Running'})){
            if($rows.Count -ge $MaxStops){break}
            if($svc.Name -in @('EventLog','RpcSs','DcomLaunch','RpcEptMapper','PlugPlay','Power','ProfSvc','SamSs','Schedule','Winmgmt','BITS','wuauserv','WinDefend','SecurityHealthService','LanmanWorkstation','LanmanServer','Dhcp','Dnscache','NlaSvc','Netman','AudioSrv','Audiosrv','CryptSvc','Winlogon','W32Time')){continue}
            if(-not $svc.CanStop){continue}
            if(@($svc.DependentServices|Where-Object{$_.Status -eq 'Running'}).Count -gt 0){continue}
            $cim=Get-CimInstance Win32_Service -Filter ("Name='{0}'" -f $svc.Name.Replace("'","''")) -ErrorAction SilentlyContinue
            if($null -eq $cim -or [string]$cim.StartMode -ne 'Manual'){continue}
            $path=[string]$cim.PathName;$exe='';if($path -match '^"([^"]+\.exe)'){ $exe=$Matches[1] }elseif($path -match '^([^\s]+\.exe)'){ $exe=$Matches[1] }
            if([string]::IsNullOrWhiteSpace($exe)-or-not(Test-Path -LiteralPath $exe -PathType Leaf)){continue}
            $vi=(Get-Item -LiteralPath $exe -ErrorAction SilentlyContinue).VersionInfo;$company=[string]$vi.CompanyName;$product=[string]$vi.ProductName
            if($company -match '(?i)Microsoft|Windows|NVIDIA|AMD|Intel|Realtek|Qualcomm|Broadcom|Valve|Epic|Riot|Ubisoft|EA|Blizzard|EAC|BattlEye|Discord'){continue}
            [void]$rows.Add([pscustomobject]@{Service=$svc;Name=$svc.Name;DisplayName=$svc.DisplayName;ExecutablePath=$exe;Company=$company;Product=$product;Reason='Manual-start third-party service; no running dependents; not core/security/driver/game vendor.'})
        }
    }catch{}
    $rows.ToArray()
}
function Invoke-YumIntelligentServiceStops {
    param([double]$AvailableGB,[double]$TargetGB)
    $max=2;try{$max=[math]::Max(0,[int]$script:Yum.Config.IntelligentServiceMaxStopsPerSession)}catch{};$count=0
    if($max -le 0 -or -not [bool]$script:Yum.Config.IntelligentServiceCleanupEnabled){return 0}
    foreach($item in @(Get-YumIntelligentServiceCandidates -AvailableGB $AvailableGB -TargetGB $TargetGB -MaxStops $max)){
        $result=Invoke-YumIntelligentStopService -Service $item.Service
        if($result.Success){$count++;Write-YumLog ("Intelligent target cleanup stopped service {0} ({1}) — {2}" -f $item.Name,$item.DisplayName,$item.Reason)}
        if($count -ge $max){break}
    }
    $count
}

function Invoke-YumCleanupCore {
    param([switch]$Force,[switch]$FollowUp,[switch]$SafeOnly,[switch]$FallbackMode)
    $entered=$false
    try {
        [System.Threading.Monitor]::Enter($script:Yum.CleanupLock,[ref]$entered)
        if($script:Yum.CleanupRunning){return [pscustomobject]@{Success=$true;Skipped=$true;Reason='Cleanup already running'}}
        $script:Yum.CleanupRunning=$true
        $snapshot=Get-YumSnapshotCopy
        if($null -eq $snapshot -or $null -eq $snapshot.Memory){return [pscustomobject]@{Success=$false;Reason='No telemetry available'}}
        $now=Get-Date
        if(-not $Force -and -not $FollowUp -and (($now-$script:Yum.LastCleanup).TotalSeconds -lt [double]$script:Yum.Config.MinimumCleanIntervalSeconds)){return [pscustomobject]@{Success=$true;Skipped=$true;Reason='Cooldown'}}
        if($SafeOnly){$effectiveMode='Safe'}else{$effectiveMode=[string]$script:Yum.Config.Mode}
        $decision=Get-YumPressureDecision -Memory $snapshot.Memory -Mode $effectiveMode
        if(-not $decision.Emergency -and [double]$snapshot.CPU -ge [double]$script:Yum.Config.MaxCPUPercent){return [pscustomobject]@{Success=$true;Skipped=$true;Reason='CPU safety limit'}}
        if(-not $Force -and -not $decision.ShouldClean){return [pscustomobject]@{Success=$true;Skipped=$true;Reason=$decision.Reason}}

        $before=[double]$snapshot.Memory.AvailableGB
        $fg=[int]$snapshot.ForegroundProcessId
        if($snapshot.Game.Detected){$gamePid=[int]$snapshot.Game.ProcessId}else{$gamePid=0}
        $candidates=Get-YumCandidateProcesses -ForegroundPid $fg -GamePid $gamePid -Mode $effectiveMode
        if($SafeOnly){$profile=[pscustomobject]@{Name='Safe';PassLimit=2;CandidateScoreMinimum=35.0;OptionalApps=0;OptionalServices=0;FollowUpPasses=8;StepDelayMs=[math]::Max(300,[int]$script:Yum.Config.CleanupStepDelayMs+150);MaxPassMilliseconds=[math]::Min(600,[int]$script:Yum.Config.CleanupMaxPassMilliseconds);MaxTrimMBPerPass=[math]::Min(192,[int]$script:Yum.Config.CleanupMaxTrimMBPerPass)}}else{$profile=Get-YumModeProfile}
        if($snapshot.Game.Detected){$profile=Get-YumGamingCleanupProfile -BaseProfile $profile}
        if($FallbackMode -and -not $SafeOnly){
            $fallbackPassLimit=[int]$script:Yum.Config.FallbackProcessesPerPass
            $fallbackMaxTrim=[int]$script:Yum.Config.FallbackMaxTrimMBPerPass
            $fallbackMinScore=[double]$script:Yum.Config.FallbackCandidateScoreMinimum
            if($decision.Emergency){$fallbackPassLimit=[math]::Min($fallbackPassLimit+1,6);$fallbackMaxTrim=[math]::Max($fallbackMaxTrim,768)}
            $limit=$fallbackPassLimit
            $maxTrimForPass=$fallbackMaxTrim
            $scoreFloor=$fallbackMinScore
        } else {
            $limit=$profile.PassLimit
            if($decision.Emergency){$limit=[math]::Min($limit+1,6)}
            $maxTrimForPass=[int]$profile.MaxTrimMBPerPass
            $scoreFloor=[double]$profile.CandidateScoreMinimum
        }
        $eligible=@($candidates | Where-Object {$_.Score -ge $scoreFloor})
        # 5.3.1: per-process cooldown. 5.2.x checked ProcessCleanupTimes but never wrote it, and
        # skipped the check on follow-up passes, so a hot process (e.g. a busy browser tab) was
        # trimmed on every pass, faulted straight back in, and the user felt it as lag.
        # Keyed by PID (not name) so one cooling chrome.exe does not block every other chrome.exe.
        # A user-forced first pass may ignore the cooldown; automatic and follow-up passes never do.
        $cooldownSeconds=60.0;try{$cooldownSeconds=[math]::Max(5.0,[double]$script:Yum.Config.ProcessCooldownSeconds)}catch{}
        $nowCool=Get-Date
        foreach($k in @($script:Yum.ProcessCleanupTimes.Keys)){ if((($nowCool-[datetime]$script:Yum.ProcessCleanupTimes[$k]).TotalSeconds) -ge $cooldownSeconds){ $script:Yum.ProcessCleanupTimes.Remove($k) } }
        if(-not ($Force -and -not $FollowUp)){
            $eligible=@($eligible | Where-Object { -not $script:Yum.ProcessCleanupTimes.ContainsKey([string][int]$_.Process.Id) })
        }
        $selected=@(Get-YumTrimPlan -Candidates $eligible -AvailableGB $before -TargetGB ([double]$decision.StopTargetGB) -PassLimit $limit -MaxTrimMBPerPass $maxTrimForPass -FallbackMode:$FallbackMode)
        if($SafeOnly -and $selected.Count -eq 0){return [pscustomobject]@{Success=$true;Skipped=$false;Reason='Safe optimization found no eligible low-risk working sets within the gradual reclaim budget.';Candidates=@();BeforeAvailableGB=$before;AfterAvailableGB=$before;AvailableImprovementGB=0.0;WorkingSetReduced=0;Processes=0}}
        $gameActive=[bool]$snapshot.Game.Detected
        $allowOptional=(-not $gameActive -and -not $SafeOnly)
        $remainingGapMB=[math]::Max(0,([double]$decision.StopTargetGB-$before)*1024.0)
        if($allowOptional -and $remainingGapMB -gt 0 -and [bool]$script:Yum.Config.EnableOptionalBackgroundCleanup){
            $optionalApps=@(Get-YumOptionalBackgroundProcessCandidates -ForegroundPid $fg -GamePid $gamePid | Where-Object {[double]$_.WorkingSet/1MB -le $remainingGapMB} | Sort-Object WorkingSet -Descending | Select-Object -First $profile.OptionalApps)
        }else{$optionalApps=@()}
        # Optional services are intentionally excluded from target reclaim; stopping a service has no reliable WorkingSet estimate and can overshoot the target.
        $optionalServices=@()
        $rows=New-Object System.Collections.Generic.List[object]

        $reduced=[int64]0;$used=0;$passStarted=Get-Date
        foreach($svc in $optionalServices){
            if((((Get-Date)-$passStarted).TotalMilliseconds) -ge [double]$profile.MaxPassMilliseconds){break}
            $current=Get-YumSnapshotCopy
            if($current -and $current.Memory.AvailableGB -ge [double]$decision.StopTargetGB){break}
            $r=Invoke-YumStopOptionalService -Service $svc.Service
            if($r.Success){$used++;[void]$rows.Add([pscustomobject]@{Time=(Get-Date).ToString('HH:mm:ss.fff');Type='Service';PID=0;Process=$svc.Name;BeforeMB=0;AfterMB=0;ReducedMB=0;Action='Stopped approved service';Result=if($r.Success){'Completed'}else{'Failed'};Reason=$r.Reason})}
            Start-Sleep -Milliseconds ([int]$profile.StepDelayMs)
            $fresh=Get-YumMemoryTelemetry
            if($fresh){Update-YumSnapshotMemory -Memory $fresh}
            if($fresh -and $fresh.AvailableGB -ge [double]$decision.StopTargetGB){break}
        }
        foreach($app in $optionalApps){
            if((((Get-Date)-$passStarted).TotalMilliseconds) -ge [double]$profile.MaxPassMilliseconds){break}
            $current=Get-YumSnapshotCopy
            if($current -and $current.Memory.AvailableGB -ge [double]$decision.StopTargetGB){break}
            if($current){
                $gapMB=[math]::Max(0,([double]$decision.StopTargetGB-[double]$current.Memory.AvailableGB)*1024.0)
                if(([double]$app.WorkingSet/1MB) -gt $gapMB){break}
            }
            $r=Invoke-YumStopOptionalBackgroundProcess -Process $app.Process
            if($r.Success){$used++;[void]$rows.Add([pscustomobject]@{Time=(Get-Date).ToString('HH:mm:ss.fff');Type='Optional App';PID=$app.Process.Id;Process=$app.Process.ProcessName;BeforeMB=[math]::Round($app.WorkingSet/1MB);AfterMB=0;ReducedMB=0;Action='Closed cooperatively';Result=if($r.Success){'Completed'}else{'Failed'};Reason=$r.Reason})}
            Start-Sleep -Milliseconds ([int]$profile.StepDelayMs)
            $fresh=Get-YumMemoryTelemetry
            if($fresh){Update-YumSnapshotMemory -Memory $fresh}
            if($fresh -and $fresh.AvailableGB -ge [double]$decision.StopTargetGB){break}
        }
        foreach($item in $selected){
            if((((Get-Date)-$passStarted).TotalMilliseconds) -ge [double]$profile.MaxPassMilliseconds){break}
            $current=Get-YumSnapshotCopy
            if($current -and $current.Memory.AvailableGB -ge [double]$decision.StopTargetGB){break}
            $r=Invoke-YumEmptyWorkingSet -Process $item.Process
            # Record the attempt (success or failure) so neither a hot process nor one we cannot
            # open is retried on every pass.
            try{$script:Yum.ProcessCleanupTimes[[string][int]$item.Process.Id]=Get-Date}catch{}
            if($r.Success){$reduced+=[int64]$r.Reduced;$used++;[void]$rows.Add([pscustomobject]@{Time=(Get-Date).ToString('HH:mm:ss.fff');Type='Process';PID=$item.Process.Id;Process=$item.Process.ProcessName;BeforeMB=[math]::Round($r.Before/1MB);AfterMB=[math]::Round($r.After/1MB);ReducedMB=[math]::Round($r.Reduced/1MB);Action='Trimmed';Result=if($r.Success){'Completed'}else{'Failed'}});Write-YumLog ("Trimmed {0} PID {1}: {2:N0} MB -> {3:N0} MB; reduced {4:N0} MB" -f $item.Process.ProcessName,$item.Process.Id,($r.Before/1MB),($r.After/1MB),($r.Reduced/1MB))}else{Write-YumLog ("Trim failed for {0} PID {1}; Win32Error={2}" -f $item.Process.ProcessName,$item.Process.Id,$r.Win32Error)}
            Start-Sleep -Milliseconds ([int]$profile.StepDelayMs)
            $fresh=Get-YumMemoryTelemetry
            if($fresh){Update-YumSnapshotMemory -Memory $fresh}
        }
        $afterSnapshot=Get-YumSnapshotCopy
        if($afterSnapshot){$after=[double]$afterSnapshot.Memory.AvailableGB}else{$after=$before}
        $improvement=[math]::Max(0,$after-$before)
        $script:Yum.LastCleanup=$now;$script:Yum.CleanCount++;$script:Yum.TotalWorkingSetReduced+=$reduced;$script:Yum.TotalAvailableImprovement+=$improvement
        [pscustomobject]@{Success=$true;Skipped=$false;Preview=$false;Reason=$decision.Reason;BeforeAvailableGB=$before;AfterAvailableGB=$after;TargetGB=[double]$decision.StopTargetGB;TargetReached=($after -ge [double]$decision.StopTargetGB);AvailableImprovementGB=$improvement;WorkingSetReduced=$reduced;Processes=$used;Candidates=$rows.ToArray()}
    } catch { Write-YumLogException -Context 'Cleanup failed' -Exception $_.Exception; return [pscustomobject]@{Success=$false;Skipped=$false;Reason=$_.Exception.Message} }
    finally { if($script:Yum){$script:Yum.CleanupRunning=$false}; if($entered){[System.Threading.Monitor]::Exit($script:Yum.CleanupLock)} }
}

function Update-YumSnapshotMemory {
    param([Parameter(Mandatory)]$Memory)
    [System.Threading.Monitor]::Enter($script:Yum.CacheLock)
    try {
        # 5.3.0: readers use Get-YumSnapshotCopy, which prefers TelemetryCache['Snapshot'].
        # Writing only $script:Yum.Snapshot was immediately overwritten by the stale cache copy.
        $base=$script:Yum.TelemetryCache['Snapshot'];if($null -eq $base){$base=$script:Yum.Snapshot}
        if($null -ne $base){
            $next=[pscustomobject]@{Timestamp=Get-Date;Memory=$Memory;CPU=$base.CPU;GPU3D=$base.GPU3D;ForegroundProcessId=$base.ForegroundProcessId;Game=$base.Game}
        } else {
            $next=[pscustomobject]@{Timestamp=Get-Date;Memory=$Memory;CPU=0.0;GPU3D=0.0;ForegroundProcessId=0;Game=[pscustomobject]@{ProcessId=0;ProcessName=$null;Detected=$false}}
        }
        $script:Yum.Snapshot=$next;$script:Yum.SnapshotVersion++
        $script:Yum.TelemetryCache['Snapshot']=$next
    } finally {[System.Threading.Monitor]::Exit($script:Yum.CacheLock)}
}



function Request-YumCleanup {
    param([switch]$Force,[switch]$SafeOnly)
    [System.Threading.Monitor]::Enter($script:Yum.RequestLock)
    try {$script:Yum.CleanupRequested=$true;$script:Yum.CleanupForceRequested=([bool]$Force);$script:Yum.CleanupSafeOnlyRequested=([bool]$SafeOnly)} finally {[System.Threading.Monitor]::Exit($script:Yum.RequestLock)}
    return [pscustomobject]@{Queued=$true;Success=$true;SafeOnly=[bool]$SafeOnly}
}

function Request-YumSafeOptimization {
    [System.Threading.Monitor]::Enter($script:Yum.RequestLock)
    try {
        $script:Yum.CleanupRequested=$true
        $script:Yum.CleanupForceRequested=$true
        $script:Yum.CleanupSafeOnlyRequested=$true
    } finally {[System.Threading.Monitor]::Exit($script:Yum.RequestLock)}
    # The controller worker runs for the whole app session (started with the main UI), so a
    # one-shot controller is no longer needed. Start it defensively if it is not running.
    try { Start-YumControllerWorker } catch { Write-YumLogException -Context 'Safe optimization controller start failed' -Exception $_.Exception }
    return [pscustomobject]@{Queued=$true;Success=$true;SafeOnly=$true;OneShotController=$false}
}

function Invoke-YumCleanup {
    param([switch]$Force)
    return Request-YumCleanup -Force:$Force
}

function Invoke-YumCleanupToTarget {
    param([switch]$Force,[switch]$SafeOnly)
    $snapshot=Get-YumSnapshotCopy
    if($null -eq $snapshot -or $null -eq $snapshot.Memory){return [pscustomobject]@{Success=$false;Reason='No telemetry available';TargetReached=$false;BeforeAvailableGB=0;AfterAvailableGB=0;TargetGB=[double]$script:Yum.Config.MinimumAvailableGB;WorkingSetReduced=0;AvailableImprovementGB=0;Processes=0;Candidates=@()}}
    $target=[double]$script:Yum.Config.MinimumAvailableGB
    $before=[double]$snapshot.Memory.AvailableGB
    $safeOnlyRequested=([bool]$SafeOnly -or [bool]$script:Yum.CleanupSafeOnlyRequested)
    if($safeOnlyRequested){$profile=[pscustomobject]@{Name='Safe';PassLimit=[int]$script:Yum.Config.SafeProcessesPerPass;CandidateScoreMinimum=65.0;OptionalApps=0;OptionalServices=0;FollowUpPasses=1}}else{$profile=Get-YumModeProfile}
    if($before -ge $target -and -not $safeOnlyRequested){return [pscustomobject]@{Success=$true;Skipped=$true;Preview=$false;Reason='Target already reached';BeforeAvailableGB=$before;AfterAvailableGB=$before;TargetGB=$target;TargetReached=$true;TargetShortfallGB=0;AvailableImprovementGB=0;WorkingSetReduced=0;Processes=0;Candidates=@()}}

    $previous=$before
    $stalled=0
    $stopReason='Target not yet reached.'
    $allRows=New-Object System.Collections.Generic.List[object]
    $totalReduced=[int64]0
    $totalProcesses=0
    $adaptivePasses=[int]$profile.FollowUpPasses
    $fallbackUsed=$false
    $fallbackReducedSession=[int64]0
    $serviceStops=0
    if(-not $safeOnlyRequested -and [bool]$script:Yum.Config.IntelligentServiceCleanupEnabled -and ($target-$before) -ge [double]$script:Yum.Config.IntelligentServiceStopThresholdGB){
        $serviceStops=Invoke-YumIntelligentServiceStops -AvailableGB $before -TargetGB $target
        if($serviceStops -gt 0){$freshSvc=Get-YumMemoryTelemetry;if($freshSvc){Update-YumSnapshotMemory -Memory $freshSvc;$beforeSvc=[double]$freshSvc.AvailableGB}else{$beforeSvc=$before};if($beforeSvc -ge $target){return [pscustomobject]@{Success=$true;Skipped=$false;Preview=$false;Reason='Target reached after intelligent optional-service reclamation';StopReason='Target reached';TargetShortfallGB=0;BeforeAvailableGB=$before;AfterAvailableGB=$beforeSvc;TargetGB=$target;TargetReached=$true;AvailableImprovementGB=[math]::Max(0,$beforeSvc-$before);WorkingSetReduced=0;Processes=0;ServiceStops=$serviceStops;FallbackUsed=$false;Candidates=@()}}}
    }

    # Phase 1: low-stutter adaptive cleanup.
    for($pass=0;$pass -lt $adaptivePasses;$pass++){
        # 5.7 (found by the full UI test): a Free RAM / Deep / hotkey request waited behind every remaining
        # automatic pass (up to minutes with an out-of-reach goal). Yield to it immediately.
        if($null -ne $script:Yum.ReclaimRequest){$stopReason='Stopped early so Free RAM now / Deep reclaim can run.';break}
        $last=Invoke-YumCleanupCore -Force:$Force -FollowUp:($pass -gt 0) -SafeOnly:$safeOnlyRequested -FallbackMode:$false
        if($last -and $last.Candidates){foreach($r in @($last.Candidates)){[void]$allRows.Add($r)}}
        if($last){$totalReduced += [int64]$last.WorkingSetReduced;$totalProcesses += [int]$last.Processes}
        if($null -eq $last -or -not $last.Success){break}
        if($last -and [int]$last.Processes -eq 0 -and @($last.Candidates).Count -eq 0){break}
        # 5.3.1: let trimmed pages settle before judging the pass. Measured on Windows 11: a trim
        # shows +41 MB Available immediately but +290 MB after ~2 s. Measuring immediately made
        # every pass look like a stall and pushed the controller into fallback churn.
        if([int]$last.Processes -gt 0){
            $settleMs=1500;try{if($null -ne $script:Yum.Config['CleanupSettleMilliseconds']){$settleMs=[int]$script:Yum.Config['CleanupSettleMilliseconds']}}catch{}
            Start-Sleep -Milliseconds ([math]::Min(5000,[math]::Max(0,$settleMs)))
        }
        $fresh=Get-YumMemoryTelemetry
        if($fresh){Update-YumSnapshotMemory -Memory $fresh}
        $current=if($fresh){[double]$fresh.AvailableGB}else{$previous}
        if([int]$last.Processes -gt 0 -and (Get-Command Update-YumGlobalRetention -ErrorAction SilentlyContinue)){Update-YumGlobalRetention -AvailableGainGB ($current-$previous) -TrimmedMB ([double]$last.WorkingSetReduced/1MB)}
        # Aim for goal + hysteresis while passes are still gaining; the fallback/assist below only engage
        # when Available is under the goal itself.
        $aim=$target;try{$aim=$target+[math]::Max(0.0,[math]::Min(2.0,[double]$script:Yum.Config['TargetHysteresisGB']))}catch{}
        if($current -ge $aim){$stopReason='Target reached during adaptive cleanup.';break}
        if($current -ge $target -and ($current-$previous) -le 0.01){$stopReason='Target reached; no further gain toward the hysteresis margin.';break}
        $gain=$current-$previous
        if($gain -le 0.01){$stalled++}else{$stalled=0}
        if($stalled -ge [int]$script:Yum.Config.FallbackStallPasses){$stopReason='Adaptive cleanup stalled; entering configured fallback.';break}
        $previous=$current
        if($pass -lt ($adaptivePasses-1)){Start-Sleep -Milliseconds ([int][math]::Max(75,([double]$script:Yum.Config.ControllerNoGainBackoffSeconds*100)))}
    }

    $fresh=Get-YumMemoryTelemetry
    if($fresh){Update-YumSnapshotMemory -Memory $fresh}
    $afterAdaptive=if($fresh){[double]$fresh.AvailableGB}else{$previous}

    # 5.4 memory-area assist: trimming alone could not keep up with memory regrowth after a Deep reclaim
    # (log: "Target not reachable" every 30-120 s at 8.5-8.9 GB of a 9 GB goal). Trimming the system file
    # cache and flushing the modified list moves cached/dirty pages into Available without dropping the
    # cache. Administrator only, never while a game runs, at most once per AutoMemoryAreaAssistSeconds.
    $assistGainGB=0.0
    if($afterAdaptive -lt $target -and -not $safeOnlyRequested -and $null -eq $script:Yum.ReclaimRequest){
        $assistEnabled=$true;try{if($script:Yum.Config.Contains('AutoMemoryAreaAssist')){$assistEnabled=[bool]$script:Yum.Config['AutoMemoryAreaAssist']}}catch{}
        $assistEvery=45.0;try{if($script:Yum.Config.Contains('AutoMemoryAreaAssistSeconds')){$assistEvery=[math]::Max(15.0,[double]$script:Yum.Config['AutoMemoryAreaAssistSeconds'])}}catch{}
        $lastAssist=[datetime]::MinValue;try{if($script:Yum.Contains('LastMemoryAreaAssist')){$lastAssist=[datetime]$script:Yum.LastMemoryAreaAssist}}catch{}
        $gameNow=$false;try{$sg=Get-YumSnapshotCopy;$gameNow=[bool]($sg -and $sg.Game -and $sg.Game.Detected)}catch{}
        if($assistEnabled -and -not $gameNow -and ((Get-Date)-$lastAssist).TotalSeconds -ge $assistEvery -and (Test-YumIsElevated)){
            $script:Yum.LastMemoryAreaAssist=Get-Date
            $assistBefore=$afterAdaptive
            $c1=Invoke-YumNativeMemoryCommand -Command TrimSystemFileCache
            $c2=$null;if([bool]$script:Yum.Config.ReclaimModifiedPageList){$c2=Invoke-YumNativeMemoryCommand -Command FlushModifiedList}
            Start-Sleep -Milliseconds 400
            $fresh=Get-YumMemoryTelemetry
            if($fresh){Update-YumSnapshotMemory -Memory $fresh;$afterAdaptive=[double]$fresh.AvailableGB}
            $assistGainGB=[math]::Max(0.0,$afterAdaptive-$assistBefore)
            try{Write-YumLog ('Memory-area assist: system file cache {0}, modified list {1}; Available {2:N2} -> {3:N2} GB (+{4:N2} GB).' -f $(if($c1.Success){'trimmed'}else{'skipped'}),$(if($null -ne $c2 -and $c2.Success){'flushed'}else{'skipped'}),$assistBefore,$afterAdaptive,$assistGainGB)}catch{}
            [void]$allRows.Add([pscustomobject]@{Name='System file cache + modified list';PID='—';Process='Memory areas';Score=0;Action='Memory-area assist';Result=$(if($c1.Success){'Completed'}else{'Skipped'});Reason=$c1.Reason;WorkingSetMB=0;ReducedMB=[math]::Round($assistGainGB*1024,0)})
            if($afterAdaptive -ge $target){$stopReason='Target reached with memory-area assist.'}
        }
    }

    # Phase 2: legacy/strong fallback. This is target-driven, not a new
    # automatic-cleaning policy: it is entered only after the adaptive path
    # stalls and only while the requested target is still unmet.
    if($afterAdaptive -lt $target -and -not $safeOnlyRequested -and [bool]$script:Yum.Config.EnableTargetFallbackCleanup -and $null -eq $script:Yum.ReclaimRequest){
        $fallbackUsed=$true
        $fallbackPasses=[int]$script:Yum.Config.FallbackFollowUpPasses
        $fallbackPrevious=$afterAdaptive
        $fallbackStalled=0
        $stopReason='Legacy fallback active.'
        $fallbackSessionCapMB=3072.0; try{$fallbackSessionCapMB=[math]::Max(512,[double]$script:Yum.Config.FallbackMaxTrimPerSessionMB)}catch{}
        for($pass=0;$pass -lt $fallbackPasses;$pass++){
            if($null -ne $script:Yum.ReclaimRequest){$stopReason='Stopped early so Free RAM now / Deep reclaim can run.';break}
            if(($fallbackReducedSession/1MB) -ge $fallbackSessionCapMB){$stopReason='Legacy fallback session cap reached; stopping to avoid excessive working-set churn.';break}
            $last=Invoke-YumCleanupCore -Force:$true -FollowUp:$true -SafeOnly:$false -FallbackMode:$true
            if($last -and $last.Candidates){foreach($r in @($last.Candidates)){[void]$allRows.Add($r)}}
            if($last){$totalReduced += [int64]$last.WorkingSetReduced;$totalProcesses += [int]$last.Processes;$fallbackReducedSession += [int64]$last.WorkingSetReduced}
            if($null -eq $last -or -not $last.Success){break}
            if([int]$last.Processes -eq 0){$stopReason='No eligible processes left outside their cooldown; stopping fallback.';break}
            $settleMs=1500;try{if($null -ne $script:Yum.Config['CleanupSettleMilliseconds']){$settleMs=[int]$script:Yum.Config['CleanupSettleMilliseconds']}}catch{}
            Start-Sleep -Milliseconds ([math]::Min(5000,[math]::Max(0,$settleMs)))
            $fresh=Get-YumMemoryTelemetry
            if($fresh){Update-YumSnapshotMemory -Memory $fresh}
            $current=if($fresh){[double]$fresh.AvailableGB}else{$fallbackPrevious}
            if($current -ge $target){$stopReason='Target reached during legacy fallback.';break}
            $gain=$current-$fallbackPrevious
            if($gain -le 0.005){$fallbackStalled++}else{$fallbackStalled=0}
            if($fallbackStalled -ge [int]$script:Yum.Config.FallbackStallPasses){$stopReason='Legacy fallback stalled; no additional measurable Available RAM gain.';break}
            $fallbackPrevious=$current
            Start-Sleep -Milliseconds 100
        }
    }

    $final=Get-YumMemoryTelemetry
    if($final){Update-YumSnapshotMemory -Memory $final}
    $after=if($final){[double]$final.AvailableGB}else{$previous}
    if($totalProcesses -gt 0){try{if(Get-Command Save-YumReclaimLearning -ErrorAction SilentlyContinue){[void](Save-YumReclaimLearning)}}catch{}}
    $reason=if($after -ge $target){if($fallbackUsed){'Target reached using adaptive cleanup + legacy fallback'}else{'Target reached'}}elseif($fallbackUsed){'Target not reached after adaptive cleanup and legacy fallback; no meaningful further reclaim was observed'}else{'Adaptive cleanup stalled before target'}
    $shortfall=[math]::Max(0,$target-$after)
    return [pscustomobject]@{Success=$true;Skipped=$false;Preview=$false;Reason=$reason;StopReason=$stopReason;TargetShortfallGB=$shortfall;BeforeAvailableGB=$before;AfterAvailableGB=$after;TargetGB=$target;TargetReached=($after -ge $target);AvailableImprovementGB=[math]::Max(0,$after-$before);WorkingSetReduced=$totalReduced;Processes=$totalProcesses;ServiceStops=$serviceStops;FallbackUsed=$fallbackUsed;Candidates=$allRows.ToArray()}
}

function Invoke-YumBackgroundController {
    try {
        $request=$false;$force=$false
        [System.Threading.Monitor]::Enter($script:Yum.RequestLock)
        try {$request=$script:Yum.CleanupRequested;$force=$script:Yum.CleanupForceRequested;$safeOnly=[bool]$script:Yum.CleanupSafeOnlyRequested;$script:Yum.CleanupRequested=$false;$script:Yum.CleanupForceRequested=$false;$script:Yum.CleanupSafeOnlyRequested=$false} finally {[System.Threading.Monitor]::Exit($script:Yum.RequestLock)}
        if($request){
            # Explicit requests run even while monitoring is paused, so refresh memory first
            # instead of acting on a stale telemetry snapshot.
            try{$fresh=Get-YumMemoryTelemetry;if($fresh){Update-YumSnapshotMemory -Memory $fresh}}catch{}
            $result=Invoke-YumCleanupToTarget -Force:$force -SafeOnly:$safeOnly
            Publish-YumCleanupResult -Result $result
            return
        }
        # Automatic target maintenance only while the user has monitoring switched on.
        if(-not [bool]$script:Yum.MonitoringActive){return}
        if($script:Yum.Config.Contains('TargetMaintenanceEnabled') -and -not [bool]$script:Yum.Config.TargetMaintenanceEnabled){return}
        $snapshot=Get-YumSnapshotCopy
        if($null -eq $snapshot -or $null -eq $snapshot.Memory){return}
        $decision=Get-YumPressureDecision -Memory $snapshot.Memory -Mode $script:Yum.Config.Mode
        $profile=Get-YumModeProfile
        # Below-target memory is a cleanup condition. Hysteresis is retained as a
        # configuration value for re-engagement tuning, but it must never suppress
        # a target-driven cleanup while Available RAM is actually below target.
        $interval=[double]$script:Yum.Config.ControllerMinIntervalSeconds
        if($snapshot.Memory.TotalGB -gt 0){$distance=[math]::Max(0,$script:Yum.Config.MinimumAvailableGB-$snapshot.Memory.AvailableGB);$ratio=[math]::Min(1,$distance/[math]::Max(1,$snapshot.Memory.TotalGB*0.15));$interval=[double]$script:Yum.Config.ControllerMaxIntervalSeconds-(([double]$script:Yum.Config.ControllerMaxIntervalSeconds-$interval)*$ratio)}
        if($script:Yum.LastControllerClean -eq [datetime]::MinValue){$elapsed=99999}else{$elapsed=((Get-Date)-$script:Yum.LastControllerClean).TotalSeconds}
        # 5.3.1: no-progress backoff. With an unreachable target the controller used to restart a
        # full cleanup (process enumeration + classification) every 1-4 s indefinitely.
        $backoff=0.0;try{if($script:Yum.Contains('ControllerBackoffSeconds')){$backoff=[double]$script:Yum.ControllerBackoffSeconds}}catch{}
        $interval=[math]::Max($interval,$backoff)
        if($decision.ShouldClean -and $elapsed -ge $interval){
            $script:Yum.LastControllerClean=Get-Date
            $lastResult=Invoke-YumCleanupToTarget -Force:$false
            Publish-YumCleanupResult -Result $lastResult
            $madeProgress=([bool]$lastResult.TargetReached -or [double]$lastResult.AvailableImprovementGB -ge 0.05)
            if($madeProgress){$script:Yum.ControllerBackoffSeconds=0.0}
            else{
                $nextBackoff=if($backoff -le 0){30.0}else{[math]::Min(120.0,$backoff*2)}
                if($nextBackoff -ne $backoff){try{Write-YumLog ('Target not reachable right now (Available {0:N2} GB, target {1:N2} GB); next automatic attempt in {2:N0}s.' -f [double]$lastResult.AfterAvailableGB,[double]$lastResult.TargetGB,$nextBackoff)}catch{}}
                $script:Yum.ControllerBackoffSeconds=$nextBackoff
            }
        }
    } catch {Write-YumLogException -Context 'Background controller failed' -Exception $_.Exception}
}

function Publish-YumCleanupResult {
    param([Parameter(Mandatory)]$Result)
    [System.Threading.Monitor]::Enter($script:Yum.CacheLock)
    try {$script:Yum.CleanupResult=$Result;$script:Yum.CleanupResultVersion++} finally {[System.Threading.Monitor]::Exit($script:Yum.CacheLock)}
}
