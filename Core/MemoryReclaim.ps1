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
        # 5.3.1: was Mandatory, which rejects $null before the function body runs. Every process
        # with no reclaim-learning history therefore threw, was skipped, and Free RAM / Deep Reclaim
        # never trimmed a single process (so learning history was never created either).
        [AllowNull()]$Object,
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
        if($null -ne $obj.PSObject.Properties['Global'] -and $null -ne $obj.Global){
            $script:Yum.GlobalRetention=@{Ratio=[double]$obj.Global.Ratio;Samples=[int]$obj.Global.Samples;Updated=[string]$obj.Global.Updated}
        }
    }catch{try{Write-YumLogException -Context 'Reclaim learning load failed' -Exception $_.Exception}catch{}}
}

# 5.3.2: per-PC learned retention. Only part of a trimmed working set becomes Available RAM, and how
# much depends on the machine (memory compression, pagefile speed, what the apps are doing).
# Measured 0.38-0.40 on a 16 GB Windows 11 PC. Every settled reclaim/cleanup pass that trims a
# meaningful amount (>= 200 MB) updates an EWMA, so the trim planner and the "reachable" estimate
# adapt to whatever PC YUMRAM runs on.
function Get-YumRetentionRatio {
    $fallback=0.4
    try{ if($null -ne $script:Yum.Config['CleanupExpectedRetention']){ $fallback=[double]$script:Yum.Config['CleanupExpectedRetention'] } }catch{}
    try{
        Load-YumReclaimLearning
        $g=$script:Yum.GlobalRetention
        if($null -ne $g -and [int]$g.Samples -ge 2){ return [math]::Min(0.9,[math]::Max(0.15,[double]$g.Ratio)) }
    }catch{}
    return [math]::Min(0.9,[math]::Max(0.15,$fallback))
}

function Update-YumGlobalRetention {
    param([double]$AvailableGainGB,[double]$TrimmedMB)
    try{
        if($TrimmedMB -lt 200){return}
        Load-YumReclaimLearning
        $ratio=[math]::Min(1.0,[math]::Max(0.0,($AvailableGainGB*1024.0)/$TrimmedMB))
        $g=$script:Yum.GlobalRetention
        if($null -eq $g -or [int]$g.Samples -le 0){$new=$ratio;$n=1}else{$new=(0.3*$ratio)+(0.7*[double]$g.Ratio);$n=[int]$g.Samples+1}
        $script:Yum.GlobalRetention=@{Ratio=[math]::Round($new,4);Samples=$n;Updated=(Get-Date).ToString('o')}
        try{Write-YumLog ('Learned retention sample: {0:N0} MB trimmed -> +{1:N0} MB Available ({2:P0}); running estimate {3:P0} over {4} samples.' -f $TrimmedMB,($AvailableGainGB*1024),$ratio,$new,$n)}catch{}
    }catch{}
}

function Get-YumReachableEstimate {
    # Realistic Available RAM right now = current Available + (working sets this mode is allowed to trim
    # x learned retention). Uses the same safety filter and score floor as automatic cleanup.
    param([string]$Mode=[string]$script:Yum.Config.Mode)
    $m=Get-YumMemoryTelemetry
    if($null -eq $m){return $null}
    $snap=Get-YumSnapshotCopy
    $fg=if($snap){[int]$snap.ForegroundProcessId}else{0}
    $gamePid=if($snap -and $snap.Game -and $snap.Game.Detected){[int]$snap.Game.ProcessId}else{0}
    $profile=Get-YumModeProfile
    $eligible=@(Get-YumCandidateProcesses -ForegroundPid $fg -GamePid $gamePid -Mode $Mode | Where-Object {$_.Score -ge $profile.CandidateScoreMinimum})
    $wsMB=0.0;foreach($c in $eligible){$wsMB+=[double]$c.WorkingSet/1MB}
    $retention=Get-YumRetentionRatio
    $samples=0;try{if($null -ne $script:Yum.GlobalRetention){$samples=[int]$script:Yum.GlobalRetention.Samples}}catch{}
    $reclaimGB=($wsMB*$retention)/1024.0
    # 5.4: with administrator rights the memory-area assist can also move the system file cache's working
    # set and the modified list into Available. Counted at 80% (some is re-touched immediately).
    $areaGB=0.0
    if(Test-YumIsElevated){
        try{$pm=Get-CimInstance -ClassName Win32_PerfRawData_PerfOS_Memory -Property SystemCacheResidentBytes,ModifiedPageListBytes -ErrorAction Stop
            $areaGB=0.8*(([double]$pm.SystemCacheResidentBytes+[double]$pm.ModifiedPageListBytes)/1GB)}catch{}
    }
    $reclaimGB+=$areaGB
    [pscustomobject]@{Timestamp=Get-Date;Mode=$Mode;AvailableGB=[double]$m.AvailableGB;TotalGB=[double]$m.TotalGB;CandidateCount=$eligible.Count;CandidateMB=[math]::Round($wsMB);Retention=$retention;RetentionSamples=$samples;MemoryAreaGB=[math]::Round($areaGB,2);ReclaimableGB=[math]::Round($reclaimGB,2);ReachableGB=[math]::Round([double]$m.AvailableGB+$reclaimGB,2)}
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
        [ordered]@{Version='1';Updated=(Get-Date).ToString('o');Global=$script:Yum.GlobalRetention;Items=$items}|ConvertTo-Json -Depth 8|Set-Content -LiteralPath $tmp -Encoding UTF8
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
    $protectedNames=@($script:Yum.Config.ProtectedProcesses | ForEach-Object {([string]$_ -replace '\.exe$','').ToLowerInvariant()})+@($script:YumTuningToolNames)   # 5.16.1: + overclock / undervolt tools
    $optionalNames=@($script:Yum.Config.OptionalBackgroundProcesses | ForEach-Object {([string]$_ -replace '\.exe$','').ToLowerInvariant()})
    $coreNames=@('system','registry','smss','csrss','wininit','services','lsass','winlogon','svchost','dwm','explorer','fontdrvhost','wmiPrvSE','spoolsv','dllhost','conhost','audiodg','taskhostw','runtimebroker','searchhost','startmenuexperiencehost','shellexperiencehost')
    try {
        $processes=@(Get-Process -ErrorAction SilentlyContinue | Sort-Object WorkingSet64 -Descending | Select-Object -First ([math]::Max($TopN*4,$TopN)))
        foreach($p in $processes){
            try {
                $path=''
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
                # 5.3.1: apply the same Intelligence classification automatic cleanup uses. Before this,
                # Free RAM / Deep Reclaim only checked a name list and trimmed e.g. steamwebhelper,
                # which Intelligence classifies as a Protected game launcher (overlay hitches).
                # Identity results are cached per executable, and this now runs on the worker thread.
                if([string]::IsNullOrWhiteSpace($manual) -and (Get-Command Get-YumIntelligenceClassification -ErrorAction SilentlyContinue)){
                    try {
                        if(-not $path){try{$path=$p.MainModule.FileName}catch{}}
                        $identity=if(Get-Command Get-YumCachedExecutableIdentity -ErrorAction SilentlyContinue){Get-YumCachedExecutableIdentity -Path $path -VerifySignature}else{$null}
                        $cls=Get-YumIntelligenceClassification -Process $p -Identity $identity -ForegroundPid $ForegroundPid -GamePid $GamePid -Cpu $cpu -MemoryMB ([math]::Round($wsMB))
                        if([string]$cls.Risk -in @('Protected','Unknown')){continue}
                        if([string]$cls.Category -match '(?i)security|driver|hardware|game|launcher|overlay|anti-?cheat'){continue}
                    } catch {}
                }
                $idleScore=[math]::Max(0,20.0-[math]::Min(20.0,$cpu))
                $sizeScore=[math]::Min(45.0,$wsMB/64.0)
                $optionalBonus=if($optionalNames -contains $nameKey){15.0}else{0.0}
                $learning=Get-YumReclaimLearningForProcess -Process $p
                $score=[math]::Round($sizeScore+$idleScore+$optionalBonus+[double]$learning.HistoricalBonus,1)
                $reason=if($learning.Samples -ge 2 -and $learning.EwmaGainRatio -ge 0.25){'Freeing it worked well before on this PC'}elseif($learning.Samples -ge 2 -and $learning.EwmaGainRatio -lt 0.03){'Freeing it barely helped before, so it goes last'}elseif($optionalBonus -gt 0){'Optional background program holding a lot of RAM'}elseif($cpu -lt 1){'Idle right now and holding a lot of RAM'}else{'Holding a lot of RAM'}
                [void]$rows.Add([pscustomobject]@{Process=$p;PID=[int]$p.Id;ProcessName=[string]$p.ProcessName;WorkingSetBytes=$ws;WorkingSetMB=[math]::Round($wsMB,0);CPU=[math]::Round($cpu,1);Score=$score;Optional=($optionalBonus -gt 0);Reason=$reason;Policy=if($optionalBonus -gt 0){'Candidate'}else{'Review'};HistoricalSamples=$learning.Samples;HistoricalEffectiveness=[math]::Round($learning.EwmaGainRatio,3);HistoricalGainMB=[math]::Round($learning.EwmaGainMB,1);HistoricalBonus=$learning.HistoricalBonus})
                if($rows.Count -ge $TopN){break}
            } catch {}
        }
    } catch {}
    @($rows | Sort-Object Score -Descending)
}

function Invoke-YumNativeMemoryCommand {
    param([Parameter(Mandatory)][ValidateSet('EmptyWorkingSets','FlushModifiedList','PurgeStandby','PurgeLowPriorityStandby','TrimSystemFileCache')][string]$Command)
    $map=@{EmptyWorkingSets=2;FlushModifiedList=3;PurgeStandby=4;PurgeLowPriorityStandby=5}
    if($Command -eq 'TrimSystemFileCache'){ $r=Invoke-YumTrimSystemFileCache; return [pscustomobject]@{Success=$r.Success;Command=$Command;Status=$r.Status;Reason=$r.Reason;ErrorCategory=$r.ErrorCategory} }
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

function Get-YumMemoryListsGB {
    # 5.11: Windows' own breakdown. "Free" (free + zeroed pages) is what Resource Monitor calls Free;
    # "Available" = Free + Standby (cached files/pages that can be handed out at once). Deep empties the
    # standby cache, so Free jumps by GBs - but that cache already counted as Available.
    try{
        $o=Get-CimInstance Win32_PerfRawData_PerfOS_Memory -ErrorAction Stop
        $standby=[double]$o.StandbyCacheCoreBytes+[double]$o.StandbyCacheNormalPriorityBytes+[double]$o.StandbyCacheReserveBytes
        return [pscustomobject]@{FreeGB=[math]::Round([double]$o.FreeAndZeroPageListBytes/1GB,3);StandbyGB=[math]::Round($standby/1GB,3);ModifiedGB=[math]::Round([double]$o.ModifiedPageListBytes/1GB,3)}
    }catch{ return $null }
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
        # 5.11: Available often keeps rising for a few seconds after a reclaim (Windows finishes writing out
        # and compressing). Keep the highest gain seen so the result can say so.
        try{
            $peak=[double]$Result.AvailableGainGB;$peakAt=0
            foreach($pair in @(@(5,$Result.Verification5sGB),@(15,$Result.Verification15sGB))){ if($null -ne $pair[1] -and [double]$pair[1] -gt $peak){$peak=[double]$pair[1];$peakAt=[int]$pair[0]} }
            $Result | Add-Member -NotePropertyName PeakGainGB -NotePropertyValue $peak -Force
            $Result | Add-Member -NotePropertyName PeakGainAtSeconds -NotePropertyValue $peakAt -Force
        }catch{}
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
    $trimmed=New-Object System.Collections.Generic.List[object]
    $used=0
    foreach($candidate in $candidates){
        if($used -ge $MaxActions){break}
        $p=$candidate.Process
        try {
            if(Test-YumProtectedProcess -Process $p -ForegroundPid $fg -GamePid $game){continue}
            if(-not $AllowActive -and [double]$candidate.CPU -ge 5.0){continue}
            $start=[int64]$p.WorkingSet64
            $r=Invoke-YumEmptyWorkingSet -Process $p
            $after=[int64]$start
            try{$p.Refresh();$after=[int64]$p.WorkingSet64}catch{}
            $reduced=[math]::Max(0,$start-$after)
            $row=[pscustomobject]@{
                Type='Process';PID=[int]$p.Id;Process=[string]$p.ProcessName;BeforeMB=[math]::Round($start/1MB,0);AfterMB=[math]::Round($after/1MB,0);ReducedMB=[math]::Round($reduced/1MB,0);AvailableGainMB=0;Action='Trim working set';Result=if($r.Success){'Completed'}else{'Failed'};Reason=if($r.Success){$candidate.Reason}else{$r.Reason};CPU=$candidate.CPU;Score=$candidate.Score;HistoricalEffectiveness=$candidate.HistoricalEffectiveness;HistoricalSamples=$candidate.HistoricalSamples
            }
            [void]$rows.Add($row)
            if($r.Success){$used++;[void]$trimmed.Add([pscustomobject]@{Process=$p;Start=$start;AfterTrim=$after;Row=$row})}
        } catch {
            [void]$rows.Add([pscustomobject]@{Type='Process';PID=$candidate.PID;Process=$candidate.ProcessName;BeforeMB=$candidate.WorkingSetMB;AfterMB='—';ReducedMB=0;Action='Trim working set';Result='Failed';Reason=$_.Exception.Message;CPU=$candidate.CPU;Score=$candidate.Score})
        }
    }
    # 5.3.1: measure after the trimmed pages settle (~1-2 s on Windows 10/11; memory compression and
    # the modified-page writer move them into Available). Per-process learning records how much of
    # each trim was still trimmed after settling: hot processes that immediately fault their pages
    # back in get deprioritized. The old per-trim Available delta was ~0 for every process, which
    # made learning penalize everything after two samples.
    if($trimmed.Count -gt 0){
        $settleMs=1500;try{if($null -ne $script:Yum.Config['ReclaimSettleMilliseconds']){$settleMs=[int]$script:Yum.Config['ReclaimSettleMilliseconds']}}catch{}
        Start-Sleep -Milliseconds ([math]::Min(5000,[math]::Max(0,$settleMs)))
        foreach($t in $trimmed.ToArray()){
            try{
                $t.Process.Refresh();$nowWs=[int64]$t.Process.WorkingSet64
                $trimmedBytes=[math]::Max(1,[double]($t.Start-$t.AfterTrim))
                $retainedBytes=[math]::Max(0.0,[math]::Min($trimmedBytes,[double]($t.Start-$nowWs)))
                $t.Row.AvailableGainMB=[math]::Round($retainedBytes/1MB,0)
                Update-YumReclaimLearning -Process $t.Process -AvailableGainGB ($retainedBytes/1GB) -WorkingSetReducedMB ($trimmedBytes/1MB)
            }catch{}
        }
    }
    $afterSnap=Get-YumMemoryReclaimSnapshot
    $actualAvailable=[math]::Max(0.0,$afterSnap.AvailableGB-$before.AvailableGB)
    if($trimmed.Count -gt 0){
        $trimmedMBTotal=0.0;foreach($t in $trimmed.ToArray()){$trimmedMBTotal+=[math]::Max(0.0,[double]($t.Start-$t.AfterTrim)/1MB)}
        Update-YumGlobalRetention -AvailableGainGB ([double]$afterSnap.AvailableGB-[double]$before.AvailableGB) -TrimmedMB $trimmedMBTotal
    }
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
        $listsBefore=Get-YumMemoryListsGB
        $rows=New-Object System.Collections.Generic.List[object]
        $notes=New-Object System.Collections.Generic.List[string]
        $gameActive=$false
        try{$s=Get-YumSnapshotCopy;$gameActive=[bool]($s -and $s.Game -and $s.Game.Detected)}catch{}

        # 5.3.1 order: low-priority standby -> trim processes (and let them settle) -> Deep only:
        # flush the modified list (turns trimmed dirty pages into Available) -> purge standby ->
        # system working sets. 5.2.x flushed/purged *before* trimming, so the pages released by the
        # trims were never flushed, and purging standby first does not raise Available at all
        # (standby pages already count as Available).
        $runMemoryArea = {
            param([string]$Command,[string]$Label)
            $areaBefore=Get-YumMemoryReclaimSnapshot -Fast
            $r=Invoke-YumNativeMemoryCommand -Command $Command
            Start-Sleep -Milliseconds 80
            $areaAfter=Get-YumMemoryReclaimSnapshot -Fast
            $gain=[math]::Max(0.0,[double]$areaAfter.AvailableGB-[double]$areaBefore.AvailableGB)
            # 5.11: a step that needs administrator is 'Skipped', not a red 'Failed'.
            $areaResult=if($r.Success){'Completed'}elseif(-not (Test-YumIsElevated) -or [string]$r.Reason -match '(?i)privilege'){'Skipped'}else{'Failed'}
            $areaReason=if($areaResult -eq 'Skipped'){'Needs YUMRAM to run as administrator.'}else{[string]$r.Reason}
            [void]$rows.Add([pscustomobject]@{Type='Memory Area';PID='—';Process=$Label;BeforeMB=[math]::Round([double]$areaBefore.AvailableGB*1024,0);AfterMB=[math]::Round([double]$areaAfter.AvailableGB*1024,0);ReducedMB=[math]::Round($gain*1024,0);Action='Purge';Result=$areaResult;Reason=$areaReason;CPU='—';Score=0})
            if(-not $r.Success -and $areaResult -ne 'Skipped'){[void]$notes.Add(('{0} was unavailable or denied.' -f $Label))}
        }
        if([bool]$script:Yum.Config.ReclaimLowPriorityStandby){ & $runMemoryArea 'PurgeLowPriorityStandby' 'Old cache (low priority)' }

        # 5.3.0: was "-TopN (if(...){16}else{10})" which PowerShell runs as a command named 'if'.
        $maxActions=[math]::Max(1,[int]$script:Yum.Config.ReclaimMaxProcessActions)
        # 5.4: Free RAM Now considers more processes (24 / 12 actions, was 16 / 8).
        if($Mode -eq 'Deep'){$topN=32;$maxActions=[math]::Max(16,$maxActions*2)}else{$topN=24;$maxActions=[math]::Max(12,$maxActions)}
        $processPass=Invoke-YumReclaimProcessPass -TopN $topN -MaxActions $maxActions -MinimumWorkingSetMB ([int]$script:Yum.Config.ReclaimMinimumWorkingSetMB) -AllowActive:($Force -and $Mode -eq 'Deep')
        foreach($r in @($processPass.Rows)){[void]$rows.Add($r)}

        # 5.4: both modes now trim the system file cache and flush the modified list (no cache is lost:
        # pages move to standby, which counts as Available). Previously only Deep did any of this, which
        # is why Deep gained 3-4x more. Deep still alone purges standby and empties every working set.
        $elevated=Test-YumIsElevated
        $assistOk=($elevated -and -not $gameActive -and ($Force -or $Mode -eq 'Deep'))
        if($assistOk -and $(if($script:Yum.Config.Contains('ReclaimSystemFileCache')){[bool]$script:Yum.Config['ReclaimSystemFileCache']}else{$true})){ & $runMemoryArea 'TrimSystemFileCache' 'System file cache' }
        if($assistOk -and [bool]$script:Yum.Config.ReclaimModifiedPageList){ & $runMemoryArea 'FlushModifiedList' 'Changes waiting to be saved' }
        # 5.12: memory combining (identical pages kept once). Measured here: first run +0.26 GB Available (261 MB
        # combined, 3.5 s); repeats within minutes find only 10-16 MB. Deep always; Free RAM now every 15 min.
        $combineOn=$true;try{if($script:Yum.Config.Contains('ReclaimCombineMemory')){$combineOn=[bool]$script:Yum.Config['ReclaimCombineMemory']}}catch{}
        $lastCombine=[datetime]::MinValue;try{if($null -ne $script:Yum['LastMemoryCombine']){$lastCombine=[datetime]$script:Yum['LastMemoryCombine']}}catch{}
        if($assistOk -and $combineOn -and ($Mode -eq 'Deep' -or ((Get-Date)-$lastCombine).TotalMinutes -ge 15)){
            $cb=Invoke-YumCombineMemory;$script:Yum['LastMemoryCombine']=Get-Date
            [void]$rows.Add([pscustomobject]@{Type='Memory Area';PID='—';Process='Duplicate memory combined';BeforeMB='—';AfterMB='—';ReducedMB=[math]::Round([double]$cb.SavedMB,0);Action='Combine';Result=$(if($cb.Success){'Completed'}else{'Skipped'});Reason=[string]$cb.Reason;CPU='—';Score=0})
        }
        if(-not $elevated){[void]$notes.Add('Not running as administrator: the system file cache and Windows memory lists were skipped (process trimming only).')}
        if($Mode -eq 'Deep' -and [bool]$script:Yum.Config.ReclaimStandbyList){ & $runMemoryArea 'PurgeStandby' 'All cache (standby)' }

        # A manual deep reclaim can optionally clear system working sets last.
        # It is intentionally not part of automatic monitoring because it is more
        # likely to cause immediate page faults in active applications.
        if($Mode -eq 'Deep' -and [bool]$script:Yum.Config.ReclaimSystemWorkingSet -and $Force -and -not $gameActive){
            $r2=Invoke-YumNativeMemoryCommand -Command EmptyWorkingSets
            [void]$rows.Add([pscustomobject]@{Type='Memory Area';PID='—';Process='Every program''s memory';BeforeMB='—';AfterMB='—';ReducedMB='—';Action='Empty working sets';Result=if($r2.Success){'Completed'}else{'Failed'};Reason=$r2.Reason;CPU='—';Score=0})
            # 5.6 (measured as administrator): emptying every working set parks ~4 GB of changed pages on the
            # modified list; Windows only writes them out (-> Available) 3-5 s later, so Deep reported +1.4 GB
            # while the real gain 5 s later was +3.5 GB. A forced flush fixed the number but took ~13 s of
            # synchronous writes; Windows' own writer drains the list in under 5 s. So wait (max 6 s) for the
            # modified list to drain, then measure. Pages stay in standby (cached), they are not discarded.
            if($r2.Success){
                $drainStart=Get-Date;$drainedMB=0.0;$startMB=$null
                while(((Get-Date)-$drainStart).TotalMilliseconds -lt 6000){
                    $modMB=$null;try{$modMB=[double](Get-CimInstance Win32_PerfRawData_PerfOS_Memory -Property ModifiedPageListBytes -ErrorAction Stop).ModifiedPageListBytes/1MB}catch{break}
                    if($null -eq $startMB){$startMB=$modMB}
                    if($modMB -le 512){break}
                    Start-Sleep -Milliseconds 250
                }
                if($null -ne $startMB -and $null -ne $modMB){$drainedMB=[math]::Max(0.0,$startMB-$modMB)}
                [void]$notes.Add(('Waited {0:N1} s for Windows to write out {1:N0} MB of changed memory before measuring.' -f ((Get-Date)-$drainStart).TotalSeconds,$drainedMB))
            }
        }

        $after=Get-YumMemoryReclaimSnapshot
        $availableGain=[math]::Max(0.0,$after.AvailableGB-$before.AvailableGB)
        $wsReduced=[double]$processPass.WorkingSetReducedMB
        # 5.7: say why nothing was trimmed instead of a bare "0 actions completed".
        if($wsReduced -le 0 -and @($rows|Where-Object{$_.Type -ne 'Memory Area' -and $_.Result -eq 'Completed'}).Count -eq 0){
            [void]$notes.Add(('Nothing left to trim: no idle program above {0} MB right now (automatic care may already have trimmed them, or they are protected).' -f [int]$script:Yum.Config.ReclaimMinimumWorkingSetMB))
        }
        $success=($availableGain -gt 0.0 -or $wsReduced -gt 0.0 -or @($rows|Where-Object{$_.Result -eq 'Completed'}).Count -gt 0)
        # 5.11 (user report: "Deep said 2.90 GB but free RAM jumped a lot more"): also measure Windows' Free
        # list. Emptying the standby cache moves GBs from Standby to Free, which Resource Monitor shows as a big
        # jump in "Free" - but standby already counted as Available, so it is not extra room. Say so.
        $listsAfter=Get-YumMemoryListsGB
        $freeJump=0.0;$freeNote=''
        if($null -ne $listsBefore -and $null -ne $listsAfter){
            $freeJump=[math]::Round([double]$listsAfter.FreeGB-[double]$listsBefore.FreeGB,2)
            if($freeJump -gt ($availableGain+0.5)){
                $freeNote=(' Windows'' "Free" memory went up +{0:N1} GB because the standby cache was emptied; that cache already counted as available, so the real extra room is the +{1:N2} GB above.' -f $freeJump,$availableGain)
                [void]$notes.Add($freeNote.Trim())
            }
        }
        $result=[pscustomobject]@{
            Success=$success;Skipped=$false;Mode=$Mode;Before=$before;After=$after;AvailableGainGB=$availableGain;WorkingSetReducedMB=$wsReduced;Actions=$rows.Count;Rows=$rows.ToArray();Notes=$notes.ToArray();Timestamp=Get-Date
            FreeBeforeGB=$(if($listsBefore){$listsBefore.FreeGB}else{$null});FreeAfterGB=$(if($listsAfter){$listsAfter.FreeGB}else{$null});FreeJumpGB=$freeJump
            StandbyBeforeGB=$(if($listsBefore){$listsBefore.StandbyGB}else{$null});StandbyAfterGB=$(if($listsAfter){$listsAfter.StandbyGB}else{$null})
            Summary=('Free RAM {0:N2} → {1:N2} GB (+{2:N2} GB). Took {3:N0} MB back from idle programs. {4} done.{5}{6}' -f $before.AvailableGB,$after.AvailableGB,$availableGain,$wsReduced,$($doneCount=@($rows|Where-Object{$_.Result -eq 'Completed'}).Count;if($doneCount -eq 1){'1 action'}else{'{0} actions' -f $doneCount}),$(if($wsReduced -le 0){' Nothing left to trim right now - idle programs were already trimmed.'}else{''}),$freeNote)
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
