#requires -Version 5.1

function Test-YumProtectedProcess {
    param([System.Diagnostics.Process]$Process,[int]$ForegroundPid=0,[int]$GamePid=0)
    if($null -eq $Process){return $true}
    try {
        if($Process.Id -eq $PID){return $true}
        if(Test-YumNameInList -Name $Process.ProcessName -List @($script:Yum.Config.ProtectedProcesses)){return $true}
        if([bool]$script:Yum.Config.ProtectForegroundProcess -and $ForegroundPid -gt 0 -and $Process.Id -eq $ForegroundPid){return $true}
        if([bool]$script:Yum.Config.ProtectGame -and $GamePid -gt 0 -and $Process.Id -eq $GamePid){return $true}
        if($Process.PriorityClass -eq [Diagnostics.ProcessPriorityClass]::RealTime){return $true}
    } catch {return $true}
    return $false
}

function Get-YumCandidateProcesses {
    param([int]$ForegroundPid=0,[int]$GamePid=0,[string]$Mode='Balanced')
    $rows=New-Object System.Collections.Generic.List[object]
    $cacheKey=('fg={0}|game={1}|mode={2}|rev={3}' -f $ForegroundPid,$GamePid,$Mode,[int]$script:Yum.IntelligenceViewRevision)
    try {
        $cacheAge=if($null -ne $script:Yum.CleanupCandidateSnapshotUtc){((Get-Date).ToUniversalTime()-[datetime]$script:Yum.CleanupCandidateSnapshotUtc).TotalSeconds}else{9999}
        if([bool]$script:Yum.CleanupRunning -and [string]$script:Yum.CleanupCandidateSnapshotKey -eq $cacheKey -and $cacheAge -le 1.5 -and @($script:Yum.CleanupCandidateSnapshot).Count -gt 0){
            foreach($base in @($script:Yum.CleanupCandidateSnapshot)){
                try {
                    $p=Get-Process -Id ([int]$base.PID) -ErrorAction Stop
                    if(Test-YumProtectedProcess -Process $p -ForegroundPid $ForegroundPid -GamePid $GamePid){continue}
                    $ws=[int64]$p.WorkingSet64
                    if($ws -lt 100MB){continue}
                    $cpu=[double]$base.CPU
                    $priorityWeight=[double]$base.PriorityWeight
                    $optionalBonus=[double]$base.OptionalBonus
                    $classificationBonus=[double]$base.ClassificationBonus
                    $score=($ws/1GB)*45.0 + [math]::Max(0,15-[math]::Min(15,$cpu)) + $priorityWeight + $optionalBonus + $classificationBonus
                    [void]$rows.Add([pscustomobject]@{Process=$p;WorkingSet=$ws;CPU=$cpu;Score=$score;Optional=$optionalBonus -gt 0;Classification=[string]$base.Classification;Risk=[string]$base.Risk;Recommendation=[string]$base.Recommendation;IdentityState=[string]$base.IdentityState;IdentityConfidence=[int]$base.IdentityConfidence;UnknownReason=[string]$base.UnknownReason;AutoResearchEligible=[bool]$base.AutoResearchEligible;PID=[int]$p.Id})
                } catch {}
            }
            return @($rows | Sort-Object Score -Descending)
        }

        $cpuMap=@{}
        try { if(Get-Command Get-YumProcessCpuMap -ErrorAction SilentlyContinue){$cpuMap=Get-YumProcessCpuMap} } catch {}
        foreach($p in Get-Process -ErrorAction Stop){
            try {
                if(Test-YumProtectedProcess -Process $p -ForegroundPid $ForegroundPid -GamePid $GamePid){continue}
                $ws=[int64]$p.WorkingSet64
                if($ws -lt 100MB){continue}
                $path='';try{$path=$p.MainModule.FileName}catch{}
                if(Get-Command Get-YumCachedExecutableIdentity -ErrorAction SilentlyContinue){$identity=Get-YumCachedExecutableIdentity -Path $path -VerifySignature}else{$identity=Get-YumExecutableIdentity -Path $path -VerifySignature}
                $memoryMB=[math]::Round($ws/1MB,0)
                $cpu=0.0
                if($cpuMap.Contains([int]$p.Id)){ $cpu=[double]$cpuMap[[int]$p.Id] }
                else { try {$cpuSeconds=[double]$p.TotalProcessorTime.TotalSeconds;$ageSeconds=1.0;try{$ageSeconds=[math]::Max(1.0,((Get-Date)-$p.StartTime).TotalSeconds)}catch{};$cpu=[math]::Min(100.0,(($cpuSeconds/[math]::Max(1,[Environment]::ProcessorCount))/$ageSeconds)*100.0)} catch {} }
                $priorityWeight = switch ($p.PriorityClass) {'Idle'{5};'BelowNormal'{3};'Normal'{1};'AboveNormal'{-2};'High'{-5};default{0}}
                $classification=Get-YumIntelligenceClassification -Process $p -Identity $identity -ForegroundPid $ForegroundPid -GamePid $GamePid -Cpu $cpu -MemoryMB $memoryMB
                try {
                    if(Get-Command Get-YumManualOrganization -ErrorAction SilentlyContinue){
                        $manualItem=[pscustomobject]@{Name=$p.ProcessName;Path=$path;Publisher=if($identity){[string]$identity.Company}else{''};FileHash=if($identity){[string]$identity.FileHash}else{''};SignerThumbprint=if($identity){[string]$identity.SignerThumbprint}else{''}}
                        $manual=Get-YumManualOrganization -Item $manualItem
                        if($null -ne $manual){$classification=[pscustomobject]@{Category=[string]$manual.Category;Risk=[string]$manual.Risk;Recommendation=[string]$manual.ActionLane;Confidence=99;Reason='Manual organization override'}}
                    }
                } catch {}
                if($classification.Risk -eq 'Protected' -or $classification.Risk -eq 'Unknown'){continue}
                if($Mode -eq 'Safe' -and $classification.Risk -notin @('Safe to Manage','Candidate')){continue}
                if($Mode -eq 'Balanced' -and $classification.Risk -notin @('Safe to Manage','Candidate')){continue}
                if($Mode -eq 'Aggressive' -and $classification.Risk -eq 'Review'){if($identity.Signature -eq 'Unknown' -and [string]::IsNullOrWhiteSpace($identity.Company)){continue}}
                $optionalBonus=if(Test-YumOptionalBackgroundProcess -Name $p.ProcessName){10}else{0}
                $classificationBonus=switch($classification.Risk){'Safe to Manage'{20};'Candidate'{12};'Review'{3};default{0}}
                $score=($ws/1GB)*45.0 + [math]::Max(0,15-[math]::Min(15,$cpu)) + $priorityWeight + $optionalBonus + $classificationBonus
                [void]$rows.Add([pscustomobject]@{Process=$p;PID=[int]$p.Id;WorkingSet=$ws;CPU=$cpu;Score=$score;Optional=$optionalBonus -gt 0;PriorityWeight=$priorityWeight;OptionalBonus=$optionalBonus;ClassificationBonus=$classificationBonus;Classification=$classification.Category;Risk=$classification.Risk;Recommendation=$classification.Recommendation;IdentityState=if($classification.PSObject.Properties['IdentityState']){[string]$classification.IdentityState}else{''};IdentityConfidence=if($classification.PSObject.Properties['Confidence']){[int]$classification.Confidence}else{0};UnknownReason=if($classification.PSObject.Properties['Reason']){[string]$classification.Reason}else{''};AutoResearchEligible=if($classification.PSObject.Properties['AutoResearchEligible']){[bool]$classification.AutoResearchEligible}else{$classification.Risk -eq 'Review'}})
            } catch {}
        }
        if([bool]$script:Yum.CleanupRunning){
            $script:Yum.CleanupCandidateSnapshot=@($rows | ForEach-Object {[pscustomobject]@{PID=$_.PID;CPU=$_.CPU;PriorityWeight=$_.PriorityWeight;OptionalBonus=$_.OptionalBonus;ClassificationBonus=$_.ClassificationBonus;Classification=$_.Classification;Risk=$_.Risk;Recommendation=$_.Recommendation;IdentityState=$_.IdentityState;IdentityConfidence=$_.IdentityConfidence;UnknownReason=$_.UnknownReason;AutoResearchEligible=$_.AutoResearchEligible}})
            $script:Yum.CleanupCandidateSnapshotKey=$cacheKey
            $script:Yum.CleanupCandidateSnapshotUtc=(Get-Date).ToUniversalTime()
        }
    } catch {Write-YumLogException -Context 'Candidate enumeration failed' -Exception $_.Exception}
    return @($rows | Sort-Object Score -Descending)
}

