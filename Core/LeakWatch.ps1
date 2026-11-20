#requires -Version 5.1
# 5.12: memory-leak alerts.
# Microsoft's guidance for finding a user-mode leak is a process's Private Bytes rising steadily over time;
# a fixed size threshold fires on programs that are simply large. So YUMRAM samples each program's private
# memory (all its processes together) once a minute, keeps 30 minutes, and flags a sustained rise:
#   >= 10 samples, grew >= 400 MB and >= 40 %, >= 80 % of steps went up (5 MB noise allowed), and the
#   latest sample is within 5 % of the peak (still growing). Nothing is ever closed automatically.

$script:YumLeakIgnore=@('system','idle','registry','memory compression','memcompression','secure system','vmmem','vmmemwsl','dwm','csrss','lsass','smss','wininit','services')

function Test-YumLeakTrend {
    # Pure heuristic (unit-tested). $Samples: chronological MB values. Returns $null or @{GrowthMB;FromMB;ToMB}.
    param([double[]]$Samples,[double]$MinGrowthMB=400,[double]$MinGrowthRatio=0.40,[int]$MinSamples=10)
    if($null -eq $Samples -or $Samples.Count -lt $MinSamples){return $null}
    $from=[double]$Samples[0];$to=[double]$Samples[-1]
    $growth=$to-$from
    if($growth -lt $MinGrowthMB -or $growth -lt ($from*$MinGrowthRatio)){return $null}
    $up=0;for($i=1;$i -lt $Samples.Count;$i++){ if([double]$Samples[$i] -ge ([double]$Samples[$i-1]-5)){$up++} }
    if(($up/($Samples.Count-1)) -lt 0.8){return $null}
    $peak=($Samples | Measure-Object -Maximum).Maximum
    if($to -lt ($peak*0.95)){return $null}
    return [pscustomobject]@{GrowthMB=[math]::Round($growth,0);FromMB=[math]::Round($from,0);ToMB=[math]::Round($to,0)}
}

function Update-YumLeakWatch {
    # Called from the CPU care worker tick with the process list it already has (no extra enumeration).
    param([System.Collections.IDictionary]$ById,$State)
    $every=60.0;try{if($script:Yum.Config.Contains('LeakSampleSeconds')){$every=[math]::Max(1.0,[double]$script:Yum.Config['LeakSampleSeconds'])}}catch{}
    $on=$true;try{if($script:Yum.Config.Contains('LeakAlertsEnabled')){$on=[bool]$script:Yum.Config['LeakAlertsEnabled']}}catch{}
    if(-not $on){return}
    $now=[datetime]::UtcNow
    if($null -ne $State['LeakAt'] -and ($now-[datetime]$State['LeakAt']).TotalSeconds -lt $every){return}
    $State['LeakAt']=$now
    if($null -eq $State['LeakHist']){$State['LeakHist']=@{};$State['Growing']=[hashtable]::Synchronized(@{});$State['LeakNotices']=[System.Collections.ArrayList]::Synchronized((New-Object System.Collections.ArrayList));$State['LeakNotified']=@{}}
    $byName=@{}
    foreach($p in $ById.Values){
        try{ $n=([string]$p.ProcessName).ToLowerInvariant(); if($script:YumLeakIgnore -contains $n -or [int]$p.Id -eq $PID){continue}; $byName[$n]=[double]$byName[$n]+[double]$p.PagedMemorySize64/1MB }catch{}
    }
    $keep=30;try{$keep=[math]::Max(10,[int](1800/$every))}catch{}
    $hist=$State['LeakHist']
    foreach($n in $byName.Keys){
        if(-not $hist.ContainsKey($n)){$hist[$n]=New-Object System.Collections.Generic.List[double]}
        $l=$hist[$n];$l.Add([math]::Round($byName[$n],1));while($l.Count -gt $keep){$l.RemoveAt(0)}
        $trend=Test-YumLeakTrend -Samples ($l.ToArray())
        if($null -ne $trend){
            $mins=[math]::Round(($l.Count-1)*$every/60.0,0)
            $State['Growing'][$n]=[pscustomobject]@{Name=$n;GrowthMB=$trend.GrowthMB;FromMB=$trend.FromMB;ToMB=$trend.ToMB;Minutes=$mins}
            if(-not $State['LeakNotified'].ContainsKey($n)){
                $State['LeakNotified'][$n]=$true
                [void]$State['LeakNotices'].Add([pscustomobject]@{Name=$n;GrowthMB=$trend.GrowthMB;ToMB=$trend.ToMB;Minutes=$mins})
                try{Write-YumLog ('Leak watch: {0} grew {1:N0} MB in {2} min ({3:N0} -> {4:N0} MB private) and is still growing - possibly a memory leak.' -f $n,$trend.GrowthMB,$mins,$trend.FromMB,$trend.ToMB)}catch{}
            }
        } elseif($State['Growing'].ContainsKey($n) -and $l.Count -ge 2 -and $l[-1] -lt ($l[-2]*0.8)){
            $State['Growing'].Remove($n)   # it dropped a lot (restarted / freed): no longer flagged
        }
    }
    foreach($n in @($hist.Keys)){ if(-not $byName.ContainsKey($n)){ $hist.Remove($n); if($State['Growing'].ContainsKey($n)){$State['Growing'].Remove($n)} } }
}
