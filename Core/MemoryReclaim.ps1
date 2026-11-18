#requires -Version 5.1
<##
YUMRAM Memory Reclaim Engine

Design goals:
- Actually reclaim RAM, not merely report it.
- Keep reclaim work explicit, measurable, and explainable.
- Use lightweight telemetry in the control loop.
- Reuse the existing Safety/Policy layers for process decisions.
- Never require a configured RAM target for a one-shot reclaim.
- Report estimated/potential versus measured/actual results separately.

The standby-list operations use the native SystemMemoryListInformation call.
This is the same family of Windows memory-list controls used by memory-analysis
utilities such as RAMMap and other open-source memory cleaners. The operations
remain opt-in by reclaim mode because aggressive cache eviction can increase
page faults and I/O immediately afterward.
#>

function Get-YumSafePropertyValue {
    param(
        [Parameter(Mandatory=$true)]$Object,
        [Parameter(Mandatory=$true)][string]$Name,
        $Default=$null
    )
    try {
        if($null -eq $Object){ return $Default }
        $property=$Object.PSObject.Properties[$Name]
        if($null -eq $property -or $null -eq $property.Value){ return $Default }
        return $property.Value
    } catch { return $Default }
}

function Get-YumMemoryReclaimSnapshot {
    # -Fast skips the WMI performance-counter query (100-500 ms). Use it for per-step
    # measurements and UI refreshes; the native calls alone give Available/Cache/Commit.
    param([switch]$Fast)
    $result=[ordered]@{
        Timestamp=Get-Date;TotalGB=0.0;AvailableGB=0.0;UsedGB=0.0;UsedPercent=0.0
        CommitGB=$null;CommitLimitGB=$null;CommitPercent=$null;CacheGB=$null
        KernelGB=$null;KernelPagedGB=$null;KernelNonpagedGB=$null
        AvailableMBytes=0.0;PageReadsPerSec=0.0;PagesPerSec=0.0;HardFaultPressure=0.0
        CollectionOk=$false;MemoryStatusOk=$false;PerformanceInfoOk=$false
        ErrorCategory='';ErrorMessage=''
    }
    try {
        $status=New-Object YumRamNative+MEMORYSTATUSEX
        if([YumRamNative]::GlobalMemoryStatusEx($status)){
            $result.TotalGB=[double]$status.ullTotalPhys/1GB
            $result.AvailableGB=[double]$status.ullAvailPhys/1GB
            $result.UsedGB=[math]::Max(0.0,$result.TotalGB-$result.AvailableGB)
            $result.UsedPercent=if($result.TotalGB -gt 0){$result.UsedGB/$result.TotalGB*100.0}else{0.0}
            $result.MemoryStatusOk=$true
            $result.AvailableMBytes=[double]$status.ullAvailPhys/1MB
        }
    } catch {
        $result.ErrorCategory='GlobalMemoryStatusEx';$result.ErrorMessage=$_.Exception.Message
    }
    try {
        $perf=New-Object YumRamNative+PERFORMANCE_INFORMATION
        if([YumRamNative]::GetPerformanceInfo($perf,[uint32][Runtime.InteropServices.Marshal]::SizeOf($perf))){
            $pageSize=[double]$perf.PageSize
            $result.CommitGB=([double]$perf.CommitTotal*$pageSize)/1GB
            $result.CommitLimitGB=([double]$perf.CommitLimit*$pageSize)/1GB
            if([double]$perf.CommitLimit -gt 0){$result.CommitPercent=($result.CommitGB/$result.CommitLimitGB)*100.0}
            $result.CacheGB=([double]$perf.SystemCache*$pageSize)/1GB
            $result.KernelGB=([double]$perf.KernelTotal*$pageSize)/1GB
            $result.KernelPagedGB=([double]$perf.KernelPaged*$pageSize)/1GB
            $result.KernelNonpagedGB=([double]$perf.KernelNonpaged*$pageSize)/1GB
            $result.PerformanceInfoOk=$true
        }
    } catch {
        if([string]::IsNullOrWhiteSpace([string]$result.ErrorCategory)){$result.ErrorCategory='GetPerformanceInfo';$result.ErrorMessage=$_.Exception.Message}
    }
    if($Fast){
        if($result.MemoryStatusOk){$result.CollectionOk=$true}
        return [pscustomobject]$result
    }
    try {
        $mem=Get-CimInstance Win32_PerfFormattedData_PerfOS_Memory -ErrorAction Stop
        if($null -ne $mem){
            if(-not $result.MemoryStatusOk){$result.AvailableMBytes=[double](Get-YumSafePropertyValue $mem 'AvailableMBytes' 0)}
            $result.PageReadsPerSec=[double](Get-YumSafePropertyValue $mem 'PageReadsPerSec' 0)
            $result.PagesPerSec=[double](Get-YumSafePropertyValue $mem 'PagesPerSec' 0)
            $hard=[math]::Min(100.0,($result.PageReadsPerSec/200.0)*100.0)
            $paging=[math]::Min(100.0,($result.PagesPerSec/1000.0)*100.0)
            $result.HardFaultPressure=[math]::Round(($hard*0.65)+($paging*0.35),1)
            $result.CollectionOk=$true
        }
    } catch {
        if([string]::IsNullOrWhiteSpace([string]$result.ErrorCategory)){$result.ErrorCategory='MemoryPerformanceCounters';$result.ErrorMessage=$_.Exception.Message}
    }
    if($result.MemoryStatusOk){$result.CollectionOk=$true}
    [pscustomobject]$result
}

function Get-YumReclaimLearningPath {
    $dir=[string]$script:Yum.ConfigDirectory
    if([string]::IsNullOrWhiteSpace($dir)){$dir=[string]$script:Yum.Root}
    Join-Path $dir 'reclaim-learning.json'
}

function Get-YumReclaimLearningKey {
    param([Parameter(Mandatory=$true)]$Process)
    $name='';$path=''
    try{$name=[string]$Process.ProcessName}catch{}
    try{$path=[string]$Process.MainModule.FileName}catch{}
    $norm=('process|{0}|{1}' -f $name.Trim().ToLowerInvariant(),$path.Trim().ToLowerInvariant())
    $sha=[Security.Cryptography.SHA256]::Create()
    try{return ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($norm))).Replace('-','')).ToLowerInvariant()}finally{$sha.Dispose()}
}

function Load-YumReclaimLearning {
    if([bool]$script:Yum.ReclaimLearningLoaded){return}
    $script:Yum.ReclaimLearningLoaded=$true
    $script:Yum.ReclaimLearning=@{}
    try{
        if(-not [bool]$script:Yum.Config.ReclaimLearningEnabled){return}
        $path=Get-YumReclaimLearningPath
        if(-not(Test-Path -LiteralPath $path)){return}
        $obj=(Get-Content -LiteralPath $path -Raw -ErrorAction Stop)|ConvertFrom-Json -ErrorAction Stop
        foreach($p in @($obj.Items.PSObject.Properties)){$script:Yum.ReclaimLearning[[string]$p.Name]=$p.Value}
    }catch{try{Write-YumLogException -Context 'Reclaim learning load failed' -Exception $_.Exception}catch{}}
}

function Save-YumReclaimLearning {
    try{
        if(-not [bool]$script:Yum.Config.ReclaimLearningEnabled){return $false}
        $path=Get-YumReclaimLearningPath;$dir=Split-Path -Parent $path
        if(-not(Test-Path -LiteralPath $dir)){New-Item -ItemType Directory -Path $dir -Force|Out-Null}
        $max=[int](Get-YumSafePropertyValue -Object $script:Yum.Config -Name 'ReclaimLearningHistoryLimit' -Default 250)
        $items=@{}
        foreach($k in @($script:Yum.ReclaimLearning.Keys)){$items[$k]=$script:Yum.ReclaimLearning[$k]}
        if($items.Count -gt $max){
            $ordered=@($items.GetEnumerator()|Sort-Object @{Expression={try{[datetime]$_.Value.LastUpdatedUtc}catch{[datetime]::MinValue}}})
            $removeCount=$items.Count-$max
            for($i=0;$i -lt $removeCount;$i++){[void]$items.Remove([string]$ordered[$i].Key)}
        }
        $tmp="$path.tmp"
        [ordered]@{Version='1';Updated=(Get-Date).ToString('o');Items=$items}|ConvertTo-Json -Depth 8|Set-Content -LiteralPath $tmp -Encoding UTF8
        Move-Item -LiteralPath $tmp -Destination $path -Force
        return $true
    }catch{try{Write-YumLogException -Context 'Reclaim learning save failed' -Exception $_.Exception}catch{};return $false}
}

function Get-YumReclaimLearningForProcess {
    param([Parameter(Mandatory=$true)]$Process)
    Load-YumReclaimLearning
    $key=Get-YumReclaimLearningKey -Process $Process
    $entry=$null
    if($script:Yum.ReclaimLearning.ContainsKey($key)){$entry=$script:Yum.ReclaimLearning[$key]}
    $samples=[int](Get-YumSafePropertyValue -Object $entry -Name 'Samples' -Default 0)
    $ratio=[double](Get-YumSafePropertyValue -Object $entry -Name 'EwmaGainRatio' -Default 0.0)
    $gainMB=[double](Get-YumSafePropertyValue -Object $entry -Name 'EwmaGainMB' -Default 0.0)
    $bonus=0.0
    $minSamples=[int](Get-YumSafePropertyValue -Object $script:Yum.Config -Name 'ReclaimLearningMinSamples' -Default 2)
    if($samples -ge $minSamples){
        if($ratio -ge 0.50){$bonus=15.0}elseif($ratio -ge 0.25){$bonus=10.0}elseif($ratio -ge 0.10){$bonus=5.0}elseif($ratio -lt 0.03){$bonus=-8.0}
    }
    [pscustomobject]@{Key=$key;Samples=$samples;EwmaGainRatio=$ratio;EwmaGainMB=$gainMB;HistoricalBonus=$bonus}
}

function Update-YumReclaimLearning {
    param([Parameter(Mandatory=$true)]$Process,[double]$AvailableGainGB=0.0,[double]$WorkingSetReducedMB=0.0)
    try{
        if(-not [bool]$script:Yum.Config.ReclaimLearningEnabled){return}
        Load-YumReclaimLearning
        $key=Get-YumReclaimLearningKey -Process $Process
        $entry=$null;if($script:Yum.ReclaimLearning.ContainsKey($key)){$entry=$script:Yum.ReclaimLearning[$key]}
        $samples=[int](Get-YumSafePropertyValue -Object $entry -Name 'Samples' -Default 0)
        $oldRatio=[double](Get-YumSafePropertyValue -Object $entry -Name 'EwmaGainRatio' -Default 0.0)
        $oldGain=[double](Get-YumSafePropertyValue -Object $entry -Name 'EwmaGainMB' -Default 0.0)
        $gainMB=[math]::Max(0.0,$AvailableGainGB*1024.0)
        $ratio=if($WorkingSetReducedMB -gt 0){[math]::Min(1.0,$gainMB/$WorkingSetReducedMB)}else{0.0}
        $alpha=0.35
        $newRatio=if($samples -eq 0){$ratio}else{($alpha*$ratio)+((1.0-$alpha)*$oldRatio)}
        $newGain=if($samples -eq 0){$gainMB}else{($alpha*$gainMB)+((1.0-$alpha)*$oldGain)}
        $script:Yum.ReclaimLearning[$key]=[pscustomobject]@{Samples=($samples+1);EwmaGainRatio=[math]::Round($newRatio,4);EwmaGainMB=[math]::Round($newGain,1);LastUpdatedUtc=(Get-Date).ToUniversalTime().ToString('o');ProcessName=[string]$Process.ProcessName}
    }catch{}
}

function Get-YumFastReclaimCandidates {
    param(
        [int]$TopN=12,
        [int]$ForegroundPid=0,
        [int]$GamePid=0,
        [int]$MinimumWorkingSetMB=128
    )
    $rows=New-Object System.Collections.Generic.List[object]
    $protectedNames=@($script:Yum.Config.ProtectedProcesses | ForEach-Object {([string]$_ -replace '\.exe$','').ToLowerInvariant()})
    $optionalNames=@($script:Yum.Config.OptionalBackgroundProcesses | ForEach-Object {([string]$_ -replace '\.exe$','').ToLowerInvariant()})
    $coreNames=@('system','registry','smss','csrss','wininit','services','lsass','winlogon','svchost','dwm','explorer','fontdrvhost','wmiPrvSE','spoolsv','dllhost','conhost','audiodg','taskhostw','runtimebroker','searchhost','startmenuexperiencehost','shellexperiencehost')
    try {
        $processes=@(Get-Process -ErrorAction SilentlyContinue | Sort-Object WorkingSet64 -Descending | Select-Object -First ([math]::Max($TopN*4,$TopN)))
        foreach($p in $processes){
            try {
                $name=([string]$p.ProcessName -replace '\.exe$','')
                $nameKey=$name.ToLowerInvariant()
                $ws=[int64]$p.WorkingSet64
                $wsMB=[double]$ws/1MB
                if($wsMB -lt $MinimumWorkingSetMB){continue}
                if($p.Id -eq $PID -or $p.Id -eq $ForegroundPid -or $p.Id -eq $GamePid){continue}
                if($protectedNames -contains $nameKey -or $coreNames -contains $nameKey){continue}
                $cpu=0.0
                try {
                    $cpuSeconds=[double]$p.TotalProcessorTime.TotalSeconds
                    $age=1.0
                    try{$age=[math]::Max(1.0,((Get-Date)-$p.StartTime).TotalSeconds)}catch{}
                    $cpu=[math]::Min(100.0,(($cpuSeconds/[math]::Max(1,[Environment]::ProcessorCount))/$age)*100.0)
                } catch {}
                $manual=''
                try {
                    if(Get-Command Get-YumManualOrganization -ErrorAction SilentlyContinue){
                        $path='';try{$path=$p.MainModule.FileName}catch{}
                        $item=[pscustomobject]@{Name=$p.ProcessName;Path=$path;Publisher='';FileHash='';SignerThumbprint=''}
                        $org=Get-YumManualOrganization -Item $item
                        if($org){$manual=[string](Get-YumSafePropertyValue $org 'Category' '')}
                    }
                } catch {}
                if($manual -match '(?i)security|driver|gaming|games|protected|unknown|quarantine'){continue}
                $idleScore=[math]::Max(0,20.0-[math]::Min(20.0,$cpu))
                $sizeScore=[math]::Min(45.0,$wsMB/64.0)
                $optionalBonus=if($optionalNames -contains $nameKey){15.0}else{0.0}
                $learning=Get-YumReclaimLearningForProcess -Process $p
                $score=[math]::Round($sizeScore+$idleScore+$optionalBonus+[double]$learning.HistoricalBonus,1)
                $reason=if($learning.Samples -ge 2 -and $learning.EwmaGainRatio -ge 0.25){'Historical reclaim effectiveness is good; prior trims returned useful available RAM'}elseif($learning.Samples -ge 2 -and $learning.EwmaGainRatio -lt 0.03){'Historical reclaim effectiveness is poor; candidate is deprioritized'}elseif($optionalBonus -gt 0){'Approved optional background process; meaningful resident memory'}elseif($cpu -lt 1){'Low CPU activity with meaningful resident working set'}else{'Large resident working set; eligible for one-shot reclaim review'}
                [void]$rows.Add([pscustomobject]@{Process=$p;PID=[int]$p.Id;ProcessName=[string]$p.ProcessName;WorkingSetBytes=$ws;WorkingSetMB=[math]::Round($wsMB,0);CPU=[math]::Round($cpu,1);Score=$score;Optional=($optionalBonus -gt 0);Reason=$reason;Policy=if($optionalBonus -gt 0){'Candidate'}else{'Review'};HistoricalSamples=$learning.Samples;HistoricalEffectiveness=[math]::Round($learning.EwmaGainRatio,3);HistoricalGainMB=[math]::Round($learning.EwmaGainMB,1);HistoricalBonus=$learning.HistoricalBonus})
                if($rows.Count -ge $TopN){break}
            } catch {}
        }
    } catch {}
    @($rows | Sort-Object Score -Descending)
}

function Invoke-YumNativeMemoryCommand {
    param([Parameter(Mandatory)][ValidateSet('EmptyWorkingSets','FlushModifiedList','PurgeStandby','PurgeLowPriorityStandby')][string]$Command)
    $map=@{EmptyWorkingSets=2;FlushModifiedList=3;PurgeStandby=4;PurgeLowPriorityStandby=5}
    try {
        if($Command -ne 'EmptyWorkingSets'){
            $priv=Enable-YumNativePrivilege -Privilege 'SeProfileSingleProcessPrivilege'
            if(-not $priv.Success){return [pscustomobject]@{Success=$false;Command=$Command;Status=$priv.Error;Reason=('Required privilege was not enabled (Win32 {0}).' -f $priv.Error);ErrorCategory='Privilege'}}
        }
        $r=Invoke-YumSetSystemMemoryListCommand -Command $map[$Command]
        $reason=if($r.Success){'Native memory-list command completed.'}else{'NtSetSystemInformation returned NTSTATUS 0x{0:X8}.' -f [BitConverter]::ToUInt32([BitConverter]::GetBytes([int32]$r.Status),0)}
        [pscustomobject]@{Success=$r.Success;Command=$Command;Status=$r.Status;Reason=$reason;ErrorCategory=if($r.Success){''}else{'NativeMemoryCommand'}}
    } catch {
        [pscustomobject]@{Success=$false;Command=$Command;Status=-1;Reason=$_.Exception.Message;ErrorCategory='NativeMemoryCommand'}
    }
}

function Start-YumReclaimEffectivenessMonitor {
    # 5.3.0: the 5.2.90 System.Timers.Timer verifier never ran under Windows PowerShell 5.1.
    # Verification is now sampled lazily by Update-YumReclaimVerification, which the main UI
    # timer and the RAM Reclaim Center refresh call; no background timer is needed.
    param([Parameter(Mandatory)]$Result)
    try {
        $Result | Add-Member -NotePropertyName Verification5sGB -NotePropertyValue $null -Force
        $Result | Add-Member -NotePropertyName Verification15sGB -NotePropertyValue $null -Force
        $Result | Add-Member -NotePropertyName Verification30sGB -NotePropertyValue $null -Force
        $Result | Add-Member -NotePropertyName RetainedGainGB -NotePropertyValue $null -Force
        $Result | Add-Member -NotePropertyName VerificationStatus -NotePropertyValue 'Pending' -Force
        $Result | Add-Member -NotePropertyName EffectivenessRatio -NotePropertyValue $null -Force
        $Result | Add-Member -NotePropertyName VerificationStartedUtc -NotePropertyValue ([datetime]::UtcNow) -Force
    } catch {try{$Result.VerificationStatus='Verification unavailable'}catch{}}
}

function Update-YumReclaimVerification {
    param($Result=$script:Yum.LastReclaim)
    try {
        if($null -eq $Result -or $null -eq $Result.PSObject.Properties['VerificationStartedUtc']){return $false}
        if([string]$Result.VerificationStatus -eq 'Complete'){return $false}
        $age=([datetime]::UtcNow-[datetime]$Result.VerificationStartedUtc).TotalSeconds
        $before=[double]$Result.Before.AvailableGB
        $changed=$false
        $sample={ [math]::Max(0.0,[double](Get-YumMemoryReclaimSnapshot -Fast).AvailableGB-$before) }
        if($age -ge 5 -and $null -eq $Result.Verification5sGB){$Result.Verification5sGB=& $sample;$Result.VerificationStatus='5s measured';$changed=$true}
        if($age -ge 15 -and $null -eq $Result.Verification15sGB){$Result.Verification15sGB=& $sample;$Result.VerificationStatus='15s measured';$changed=$true}
        if($age -ge 30 -and $null -eq $Result.Verification30sGB){
            $Result.Verification30sGB=& $sample
            $Result.RetainedGainGB=$Result.Verification30sGB
            $Result.EffectivenessRatio=if([double]$Result.WorkingSetReducedMB -gt 0){[math]::Round((([double]$Result.RetainedGainGB*1024)/[double]$Result.WorkingSetReducedMB),3)}else{$null}
            $Result.VerificationStatus='Complete'
            $changed=$true
            try{Write-YumLog ('RAM reclaim verification: retained +{0:N2} GB after 30s (5s: +{1:N2}, 15s: +{2:N2}).' -f $Result.RetainedGainGB,$Result.Verification5sGB,$Result.Verification15sGB)}catch{}
        }
        if($changed){$script:Yum.ReclaimResultVersion++}
        return $changed
    } catch {try{$Result.VerificationStatus='Verification error: '+$_.Exception.Message}catch{};return $false}
}

function Invoke-YumReclaimProcessPass {
    param(
        [int]$TopN=8,
        [int]$MaxActions=3,
        [int]$MinimumWorkingSetMB=128,
        [switch]$AllowActive
    )
    $before=Get-YumMemoryReclaimSnapshot
    $snapshot=Get-YumSnapshotCopy
    $fg=if($snapshot){[int]$snapshot.ForegroundProcessId}else{Get-YumForegroundProcessId}
    $game=if($snapshot -and $snapshot.Game -and $snapshot.Game.Detected){[int]$snapshot.Game.ProcessId}else{0}
    $candidates=@(Get-YumFastReclaimCandidates -TopN $TopN -ForegroundPid $fg -GamePid $game -MinimumWorkingSetMB $MinimumWorkingSetMB)
    $rows=New-Object System.Collections.Generic.List[object]
    $used=0
    foreach($candidate in $candidates){
        if($used -ge $MaxActions){break}
        $p=$candidate.Process
        try {
            if(Test-YumProtectedProcess -Process $p -ForegroundPid $fg -GamePid $game){continue}
            if(-not $AllowActive -and [double]$candidate.CPU -ge 5.0){continue}
            $systemBefore=Get-YumMemoryReclaimSnapshot -Fast
            $start=[int64]$p.WorkingSet64
            $r=Invoke-YumEmptyWorkingSet -Process $p
            $after=[int64]$start
            try{$p.Refresh();$after=[int64]$p.WorkingSet64}catch{}
            $systemAfter=Get-YumMemoryReclaimSnapshot -Fast
            $reduced=[math]::Max(0,$start-$after)
            $availableGain=[math]::Max(0.0,[double]$systemAfter.AvailableGB-[double]$systemBefore.AvailableGB)
            if($r.Success){$used++}
            if($r.Success){Update-YumReclaimLearning -Process $p -AvailableGainGB $availableGain -WorkingSetReducedMB ($reduced/1MB)}
            [void]$rows.Add([pscustomobject]@{
                Type='Process';PID=[int]$p.Id;Process=[string]$p.ProcessName;BeforeMB=[math]::Round($start/1MB,0);AfterMB=[math]::Round($after/1MB,0);ReducedMB=[math]::Round($reduced/1MB,0);AvailableGainMB=[math]::Round($availableGain*1024,0);Action='Trim working set';Result=if($r.Success){'Completed'}else{'Failed'};Reason=if($r.Success){$candidate.Reason}else{$r.Reason};CPU=$candidate.CPU;Score=$candidate.Score;HistoricalEffectiveness=$candidate.HistoricalEffectiveness;HistoricalSamples=$candidate.HistoricalSamples
            })
        } catch {
            [void]$rows.Add([pscustomobject]@{Type='Process';PID=$candidate.PID;Process=$candidate.ProcessName;BeforeMB=$candidate.WorkingSetMB;AfterMB='—';ReducedMB=0;Action='Trim working set';Result='Failed';Reason=$_.Exception.Message;CPU=$candidate.CPU;Score=$candidate.Score})
        }
    }
    $afterSnap=Get-YumMemoryReclaimSnapshot
    $actualAvailable=[math]::Max(0.0,$afterSnap.AvailableGB-$before.AvailableGB)
    # Plain loop: Measure-Object on an empty pipeline has no .Sum under StrictMode.
    $actualWorkingSet=0.0
    foreach($row in $rows.ToArray()){try{$actualWorkingSet+=[double]$row.ReducedMB}catch{}}
    [pscustomobject]@{Before=$before;After=$afterSnap;Candidates=$candidates;Rows=$rows.ToArray();Actions=$used;WorkingSetReducedMB=[double]$actualWorkingSet;AvailableGainedGB=$actualAvailable}
}

function Invoke-YumMemoryReclaim {
    param(
        [ValidateSet('Quick','Deep')][string]$Mode='Quick',
        [switch]$Force
    )
    $lockEntered=$false
    try {
        [System.Threading.Monitor]::Enter($script:Yum.ReclaimLock,[ref]$lockEntered)
        if($script:Yum.ReclaimRunning){return [pscustomobject]@{Success=$true;Skipped=$true;Reason='Reclaim already running.'}}
        $script:Yum.ReclaimRunning=$true
        $before=Get-YumMemoryReclaimSnapshot
        $rows=New-Object System.Collections.Generic.List[object]
        $notes=New-Object System.Collections.Generic.List[string]
        $gameActive=$false
        try{$s=Get-YumSnapshotCopy;$gameActive=[bool]($s -and $s.Game -and $s.Game.Detected)}catch{}

        # Manual Quick and Deep reclaim both use the lowest-priority standby lane
        # first. Quick then trims only low-activity process working sets; Deep can
        # continue to full standby/modified-page reclamation.
        $runMemoryArea = {
            param([string]$Command,[string]$Label)
            $areaBefore=Get-YumMemoryReclaimSnapshot -Fast
            $r=Invoke-YumNativeMemoryCommand -Command $Command
            Start-Sleep -Milliseconds 80
            $areaAfter=Get-YumMemoryReclaimSnapshot -Fast
            $gain=[math]::Max(0.0,[double]$areaAfter.AvailableGB-[double]$areaBefore.AvailableGB)
            [void]$rows.Add([pscustomobject]@{Type='Memory Area';PID='—';Process=$Label;BeforeMB=[math]::Round([double]$areaBefore.AvailableGB*1024,0);AfterMB=[math]::Round([double]$areaAfter.AvailableGB*1024,0);ReducedMB=[math]::Round($gain*1024,0);Action='Purge';Result=if($r.Success){'Completed'}else{'Failed'};Reason=$r.Reason;CPU='—';Score=0})
            if(-not $r.Success){[void]$notes.Add(('{0} was unavailable or denied.' -f $Label))}
        }
        if([bool]$script:Yum.Config.ReclaimLowPriorityStandby){ & $runMemoryArea 'PurgeLowPriorityStandby' 'Low-priority standby list' }
        if($Mode -eq 'Deep' -and [bool]$script:Yum.Config.ReclaimStandbyList){ & $runMemoryArea 'PurgeStandby' 'Standby list' }
        if($Mode -eq 'Deep' -and [bool]$script:Yum.Config.ReclaimModifiedPageList -and $Force -and -not $gameActive){ & $runMemoryArea 'FlushModifiedList' 'Modified page list' }

        # 5.3.0: was "-TopN (if(...){16}else{10})" which PowerShell runs as a command named 'if',
        # so every Free RAM / Deep Reclaim threw here before trimming any process.
        $topN=if($Mode -eq 'Deep'){16}else{10}
        $processPass=Invoke-YumReclaimProcessPass -TopN $topN -MaxActions ([int]$script:Yum.Config.ReclaimMaxProcessActions) -MinimumWorkingSetMB ([int]$script:Yum.Config.ReclaimMinimumWorkingSetMB) -AllowActive:($Force -and $Mode -eq 'Deep')
        foreach($r in @($processPass.Rows)){[void]$rows.Add($r)}

        # A manual deep reclaim can optionally clear system working sets last.
        # It is intentionally not part of automatic monitoring because it is more
        # likely to cause immediate page faults in active applications.
        if($Mode -eq 'Deep' -and [bool]$script:Yum.Config.ReclaimSystemWorkingSet -and $Force -and -not $gameActive){
            $r2=Invoke-YumNativeMemoryCommand -Command EmptyWorkingSets
            [void]$rows.Add([pscustomobject]@{Type='Memory Area';PID='—';Process='System/user working sets';BeforeMB='—';AfterMB='—';ReducedMB='—';Action='Empty working sets';Result=if($r2.Success){'Completed'}else{'Failed'};Reason=$r2.Reason;CPU='—';Score=0})
        }

        $after=Get-YumMemoryReclaimSnapshot
        $availableGain=[math]::Max(0.0,$after.AvailableGB-$before.AvailableGB)
        $wsReduced=[double]$processPass.WorkingSetReducedMB
        $success=($availableGain -gt 0.0 -or $wsReduced -gt 0.0 -or @($rows|Where-Object{$_.Result -eq 'Completed'}).Count -gt 0)
        $result=[pscustomobject]@{
            Success=$success;Skipped=$false;Mode=$Mode;Before=$before;After=$after;AvailableGainGB=$availableGain;WorkingSetReducedMB=$wsReduced;Actions=$rows.Count;Rows=$rows.ToArray();Notes=$notes.ToArray();Timestamp=Get-Date
            Summary=('Available RAM {0:N2} → {1:N2} GB (+{2:N2} GB). Process working sets reduced {3:N0} MB. {4} actions completed.' -f $before.AvailableGB,$after.AvailableGB,$availableGain,$wsReduced,(@($rows|Where-Object{$_.Result -eq 'Completed'}).Count))
        }
        try {
            $script:Yum.LastReclaim=$result
            $script:Yum.ReclaimHistory.Enqueue($result)
            while($script:Yum.ReclaimHistory.Count -gt [int]$script:Yum.Config.ReclaimHistoryLimit){[void]$script:Yum.ReclaimHistory.Dequeue()}
            $script:Yum.CleanCount++
            $script:Yum.TotalWorkingSetReduced += [int64]($wsReduced*1MB)
            $script:Yum.TotalAvailableImprovement += [double]$availableGain
            $script:Yum.ReclaimResult=$result
            $script:Yum.ReclaimResultVersion++
        } catch {}
        try{Save-YumReclaimLearning|Out-Null}catch{}
        Start-YumReclaimEffectivenessMonitor -Result $result
        Write-YumLog ('RAM reclaim {0}: {1}' -f $Mode,$result.Summary)
        return $result
    } catch {
        Write-YumLogException -Context 'Memory reclaim failed' -Exception $_.Exception
        return [pscustomobject]@{Success=$false;Skipped=$false;Mode=$Mode;Reason=$_.Exception.Message;Rows=@();Notes=@('Reclaim engine exception');AvailableGainGB=0.0;WorkingSetReducedMB=0.0;Actions=0}
    } finally {
        if($lockEntered){[System.Threading.Monitor]::Exit($script:Yum.ReclaimLock)}
        try{$script:Yum.ReclaimRunning=$false}catch{}
    }
}

function Invoke-YumFreeRamNow { Invoke-YumMemoryReclaim -Mode Quick -Force }
function Invoke-YumDeepRamReclaim { Invoke-YumMemoryReclaim -Mode Deep -Force }
