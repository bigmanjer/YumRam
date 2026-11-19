#requires -Version 5.1
function Get-YumStableIntelligenceKeyFromValues {
    param([string]$Source,[string]$Name,[string]$Path,[string]$Publisher,[string]$PackageFullName='')
    $sourceText=([string]$Source).Trim().ToLowerInvariant();$nameText=([string]$Name).Trim().ToLowerInvariant();$pathText=([string]$Path).Trim().ToLowerInvariant();$publisherText=([string]$Publisher).Trim().ToLowerInvariant();$pkg=([string]$PackageFullName).Trim().ToLowerInvariant()
    if($sourceText -eq 'process' -and -not [string]::IsNullOrWhiteSpace($pathText)){$norm=('process|{0}|{1}' -f $pathText,$nameText)}elseif($sourceText -eq 'service'){$norm=('service|{0}|{1}' -f $nameText,$pathText)}elseif($sourceText -eq 'app'){$norm=('app|{0}' -f $pkg)}elseif($sourceText -eq 'startup'){$norm=('startup|{0}|{1}' -f $nameText,$pathText)}else{$norm=('generic|{0}|{1}|{2}|{3}' -f $sourceText,$nameText,$pathText,$publisherText,$pkg)}
    $sha=[Security.Cryptography.SHA256]::Create();try{return ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($norm))).Replace('-','')).ToLowerInvariant()}finally{$sha.Dispose()}
}

function Get-YumLiveIntelligenceRecordKey {
    param([string]$StableIdentityKey,[string]$Source,[object]$ProcessId)
    $stable=([string]$StableIdentityKey).Trim().ToLowerInvariant()
    $sourceText=([string]$Source).Trim().ToLowerInvariant()
    if($sourceText -eq 'process' -and $null -ne $ProcessId){
        $pidText=[string]$ProcessId
        if($pidText -match '^\d+$' -and [int]$ProcessId -gt 0){
            $norm=('live-process|{0}|{1}' -f $stable,$pidText)
            $sha=[Security.Cryptography.SHA256]::Create();try{return ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($norm))).Replace('-','')).ToLowerInvariant()}finally{$sha.Dispose()}
        }
    }
    return $stable
}

function Get-YumScannerPublisherInfo {
    param([string]$Path)
    $publisher = 'Unknown'
    $company = ''
    $product = ''
    $signature = 'Unknown'
    $signerThumbprint = ''
    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path)) {
        return [pscustomobject]@{ Path=$Path; Publisher=$publisher; Company=$company; Product=$product; Signature=$signature; SignerThumbprint=$signerThumbprint }
    }
    try {
        $vi = [Diagnostics.FileVersionInfo]::GetVersionInfo($Path)
        $company = [string]$vi.CompanyName
        $product = [string]$vi.ProductName
        if (-not [string]::IsNullOrWhiteSpace($company)) { $publisher = $company }
    } catch {}
    try {
        $sig = Get-AuthenticodeSignature -FilePath $Path -ErrorAction Stop
        $signature = [string]$sig.Status
        if($sig.SignerCertificate){
            try{$signerThumbprint=[string]$sig.SignerCertificate.Thumbprint}catch{}
            if(-not [string]::IsNullOrWhiteSpace([string]$sig.SignerCertificate.Subject)){
                $signedPublisher=[string]$sig.SignerCertificate.GetNameInfo([Security.Cryptography.X509Certificates.X509NameType]::SimpleName,$false)
                if(-not [string]::IsNullOrWhiteSpace($signedPublisher) -and $publisher -eq 'Unknown'){$publisher=$signedPublisher}
            }
        }
    } catch {}
    [pscustomobject]@{ Path=$Path; Publisher=$publisher; Company=$company; Product=$product; Signature=$signature; SignerThumbprint=$signerThumbprint }
}

function Test-YumScannerNameMatch {
    param([string]$Name,[string[]]$Names)
    if ([string]::IsNullOrWhiteSpace($Name)) { return $false }
    $clean = $Name -replace '\.exe$',''
    foreach ($candidate in @($Names)) {
        if ($clean -ieq ([string]$candidate -replace '\.exe$','')) { return $true }
    }
    return $false
}

function Test-YumScannerProtectedProcess {
    param([string]$Name,[string]$Path,[string]$Company,[int]$ProcessId,[int]$ForegroundPid,[int]$GamePid)
    if ($ProcessId -gt 0 -and $ProcessId -eq $ForegroundPid) { return @{ Protected=$true; Reason='Foreground application'; Category='Protected' } }
    if ($ProcessId -gt 0 -and $ProcessId -eq $GamePid) { return @{ Protected=$true; Reason='Active game'; Category='Games' } }
    $n=[string]$Name
    $p=([string]$Path).ToLowerInvariant()
    $c=[string]$Company
    if ($n -match '^(Idle|System|Registry|smss|csrss|wininit|services|lsass|svchost|winlogon|dwm|explorer|sihost|ctfmon|RuntimeBroker|StartMenuExperienceHost|SearchHost|SearchIndexer|ShellExperienceHost|fontdrvhost|conhost|spoolsv|dllhost|WmiPrvSE)$') {
        return @{Protected=$true;Reason='Windows core process';Category='Protected'}
    }
    if ($p -like 'c:\windows\*' -or $p -like 'c:\program files\windowsapps\*') {
        if ($c -match 'Microsoft|Windows') { return @{Protected=$true;Reason='Microsoft/Windows component';Category='Protected'} }
    }
    if ($n -match 'MsMpEng|SecurityHealth|Antimalware|Defender|Malwarebytes|CrowdStrike|Sentinel|ESET|Bitdefender|Avast|AVG|Sophos|McAfee|Webroot') {
        return @{Protected=$true;Reason='Security software';Category='Protected'}
    }
    if ($p -match '\\system32\\drivers\\|\\program files\\.*(nvidia|amd|intel|realtek|logitech|corsair)' -or $c -match 'NVIDIA|Advanced Micro Devices|AMD|Intel|Realtek|Logitech|Corsair') {
        return @{Protected=$true;Reason='Driver or hardware component';Category='Protected'}
    }
    return @{Protected=$false;Reason='';Category='Apps'}
}

function Get-YumScannerProcessRows {
    param(
        [int]$MaxItems=80,
        [switch]$SkipParentMap,
        [System.Collections.Generic.List[string]]$ErrorSink=$null,
        [int]$ForegroundPid=0,
        [int]$GamePid=0,
        [string[]]$KnownGames=@(),
        [string[]]$OptionalApps=@()
    )
    $rows=New-Object System.Collections.Generic.List[object]
    $scanErrors=New-Object System.Collections.Generic.List[string]
    $parentMap=@{}
    if(-not $SkipParentMap){
        try {
            foreach($cp in @(Get-CimInstance Win32_Process -ErrorAction Stop)) {
                $parentMap[[int]$cp.ProcessId]=[int]$cp.ParentProcessId
            }
        } catch { [void]$scanErrors.Add(('Parent map: {0}' -f $_.Exception.Message)) }
    }

    # Sample current CPU once for the whole machine. Fall back to lifetime-average CPU if the counter is unavailable.
    $cpuMap=@{}
    try {
        foreach($perf in @(Get-CimInstance Win32_PerfFormattedData_PerfProc_Process -ErrorAction Stop)){
            $cpid=0; try{$cpid=[int]$perf.IDProcess}catch{}
            if($cpid -gt 0){$cpuMap[$cpid]=[math]::Min(100.0,([double]$perf.PercentProcessorTime/[math]::Max(1,[Environment]::ProcessorCount)))}
        }
    } catch { [void]$scanErrors.Add(('CPU sample: {0}' -f $_.Exception.Message)) }

    $processes=@(Get-Process -ErrorAction SilentlyContinue | Sort-Object WorkingSet64 -Descending)
    foreach($p in $processes) {
        if($rows.Count -ge $MaxItems){break}
        try {
            $path=''; try{$path=$p.MainModule.FileName}catch{}
            $meta=Get-YumScannerPublisherInfo -Path $path
            $cpu=0.0
            $cpuTimeSeconds=0.0
            try {
                $cpuTimeSeconds=[double]$p.TotalProcessorTime.TotalSeconds
                $age=1.0
                try{$age=[math]::Max(1.0,((Get-Date)-$p.StartTime).TotalSeconds)}catch{}
                $cpu=[math]::Round([math]::Min(100.0,(($cpuTimeSeconds/[math]::Max(1,[Environment]::ProcessorCount))/$age)*100.0),1)
            } catch {}
            if($cpuMap.ContainsKey([int]$p.Id)){$cpu=[math]::Round([double]$cpuMap[[int]$p.Id],1)}
            $memoryMB=[math]::Round(([double]$p.WorkingSet64/1MB),0)
            $parentPid=0
            if($parentMap.ContainsKey([int]$p.Id)){$parentPid=[int]$parentMap[[int]$p.Id]}
            $game=$false
            if($p.Id -eq $GamePid){$game=$true}
            elseif(Test-YumScannerNameMatch -Name $p.ProcessName -Names $KnownGames){$game=$true}
            elseif(([string]$path).ToLowerInvariant() -match '\\steamapps\\common\\|\\epic games\\|\\riot games\\|\\battle\.net\\|\\ubisoft game launcher\\|\\games\\'){$game=$true}
            $protection=Test-YumScannerProtectedProcess -Name $p.ProcessName -Path $path -Company $meta.Company -ProcessId ([int]$p.Id) -ForegroundPid $ForegroundPid -GamePid $GamePid
            $optional=Test-YumScannerNameMatch -Name $p.ProcessName -Names $OptionalApps
            $risk='Review'
            $category='Apps'
            $reason='Normal user/background process; no automatic action established'
            $score=0.0
            if($protection.Protected) {
                $risk='Protected';$category=[string]$protection.Category;$reason=[string]$protection.Reason;$score=0
                if($game){$category='Games';$risk='Protected';$reason='Game process detected'}
            } elseif($game) {
                $risk='Protected';$category='Games';$reason='Game or game-location indicators detected';$score=0
            } elseif($optional) {
                $category='Apps';$risk='Safe to Manage';$reason='Known optional background application';$score=80
            } elseif($cpu -lt 0.5 -and $memoryMB -ge 250) {
                $category='Apps';$risk='Candidate';$reason='Idle process with meaningful resident memory';$score=[math]::Round([math]::Min(100,40+($memoryMB/100)+20),1)
            } elseif($cpu -lt 2 -and $memoryMB -ge 500) {
                $category='Apps';$risk='Review';$reason='Low recent CPU activity with notable resident memory';$score=55
            } else {
                $category='Apps';$risk='Review';$reason='Active process; review before management';$score=35
            }
            $publisherKnown=(-not [string]::IsNullOrWhiteSpace([string]$meta.Publisher) -and [string]$meta.Publisher -ne 'Unknown')
            $identityUnknown=(-not $protection.Protected -and -not $game -and (
                [string]::IsNullOrWhiteSpace($path) -or
                (([string]$meta.Signature -in @('NotSigned','Unknown','UnknownError','NotTrusted','HashMismatch')) -and -not $publisherKnown)
            ))
            if($identityUnknown) {
                $category='Unknown';$risk='Unknown';$reason=if([string]::IsNullOrWhiteSpace($path)){'Executable identity/path unavailable'}else{'Unsigned or untrusted executable with no verified publisher identity'};$score=10
            }
            [void]$rows.Add([pscustomobject]@{
                Source='Process';Name=[string]$p.ProcessName;Process=[string]$p.ProcessName;PID=[int]$p.Id
                MemoryMB=$memoryMB;CPU=$cpu;CPUTimeSeconds=[math]::Round($cpuTimeSeconds,1);ParentPID=$parentPid;SessionId=$(try{[int]$p.SessionId}catch{0})
                Publisher=[string]$meta.Publisher;Company=[string]$meta.Company;Product=[string]$meta.Product;Signature=[string]$meta.Signature;SignerThumbprint=[string]$meta.SignerThumbprint;Path=[string]$path
                IdentityState=if($risk -eq 'Unknown'){if([string]::IsNullOrWhiteSpace($path)){'Missing'}elseif([string]$meta.Signature -eq 'NotSigned'){'Unsigned'}else{'Untrusted'}}else{'Identified'};IdentityConfidence=if($risk -eq 'Unknown'){25}elseif($risk -eq 'Protected'){98}else{75};UnknownReason=if($risk -eq 'Unknown'){$reason}else{''};AutoResearchEligible=($risk -eq 'Unknown');
                Risk=$risk;Category=$category;Score=$score;Reason=$reason;Foreground=($p.Id -eq $ForegroundPid);Game=$game;Optional=$optional
            })
        } catch { if($scanErrors.Count -lt 25){[void]$scanErrors.Add(('Process {0}: {1}' -f $p.Id,$_.Exception.Message))} }
    }
    if($null -ne $ErrorSink){ foreach($e in $scanErrors.ToArray()){ [void]$ErrorSink.Add([string]$e) } }
    if($rows.Count -eq 0 -and $scanErrors.Count -gt 0){ throw ('Process scan produced no records. First error: {0}' -f $scanErrors[0]) }
    $rows.ToArray()
}

function Get-YumScannerServiceRows {
    param([int]$MaxItems=80,[System.Collections.Generic.List[string]]$ErrorSink=$null)
    $protectedNames=@('EventLog','RpcSs','DcomLaunch','RpcEptMapper','PlugPlay','Power','ProfSvc','SamSs','Schedule','W32Time','Winmgmt','BITS','wuauserv','WinDefend','SecurityHealthService','LanmanWorkstation','LanmanServer','Dhcp','Dnscache','NlaSvc','Netman','AudioSrv','Audiosrv','Spooler','CryptSvc','Winlogon')
    $rows=New-Object System.Collections.Generic.List[object]
    $serviceErrors=New-Object System.Collections.Generic.List[string]
    $cimByName=@{}
    try {
        foreach($svcCim in @(Get-CimInstance Win32_Service -ErrorAction Stop)){$cimByName[[string]$svcCim.Name]=$svcCim}
    } catch { [void]$serviceErrors.Add(('Service inventory: {0}' -f $_.Exception.Message)) }
    foreach($svc in @(Get-Service -ErrorAction SilentlyContinue | Where-Object {$_.Status -eq 'Running'})) {
        if($rows.Count -ge $MaxItems){break}
        try {
            $cim=$null;if($cimByName.ContainsKey([string]$svc.Name)){$cim=$cimByName[[string]$svc.Name]}
            $dependents=@($svc.DependentServices | Where-Object {$_.Status -eq 'Running'})
            $risk='Review';$reason='Running service requires dependency-aware review';$score=20
            if($protectedNames -contains [string]$svc.Name){$risk='Protected';$reason='Protected Windows/security service';$score=0}
            elseif(-not $svc.CanStop){$risk='Protected';$reason='Service reports it cannot be stopped';$score=0}
            elseif($dependents.Count -gt 0){$risk='Review';$reason='Running dependent services exist';$score=5}
            $path='';$startMode='Unknown';$company='Unknown'
            if($null -ne $cim){$path=[string]$cim.PathName;$startMode=[string]$cim.StartMode}
            if(-not [string]::IsNullOrWhiteSpace($path)){
                $exe=$path -replace '^[\"]*([^\"]+?\.exe).*$','$1'
                $meta=Get-YumScannerPublisherInfo -Path $exe
                if($meta.Company){$company=$meta.Company}
            }
            [void]$rows.Add([pscustomobject]@{Source='Service';Name=[string]$svc.DisplayName;ServiceName=[string]$svc.Name;DisplayName=[string]$svc.DisplayName;StartMode=$startMode;CanStop=[bool]$svc.CanStop;Dependents=$dependents.Count;Path=$path;Publisher=$company;Risk=$risk;Category='Services';Score=$score;Reason=$reason})
        } catch { if($serviceErrors.Count -lt 25){[void]$serviceErrors.Add(('Service {0}: {1}' -f $svc.Name,$_.Exception.Message))} }
    }
    if($null -ne $ErrorSink){ foreach($e in $serviceErrors.ToArray()){ [void]$ErrorSink.Add([string]$e) } }
    $rows.ToArray()
}

function Get-YumScannerAppRows {
    param([int]$MaxItems=80,[System.Collections.Generic.List[string]]$ErrorSink=$null)
    $rows=New-Object System.Collections.Generic.List[object]
    $appErrors=New-Object System.Collections.Generic.List[string]
    try {
        $packages=@(Get-AppxPackage -ErrorAction SilentlyContinue | Select-Object -First $MaxItems Name,PackageFullName,PublisherId,IsFramework)
        foreach($app in $packages){
            try {
                $name=[string]$app.Name;$full=[string]$app.PackageFullName;$publisherId=[string]$app.PublisherId;$framework=[bool]$app.IsFramework
                $game=($name -match 'Xbox|Gaming|GameBar|Game|Steam|Epic|Riot|Ubisoft|EA|Battle|Blizzard' -or $publisherId -match 'Xbox|Gaming|Valve|Epic|Riot|Ubisoft|ElectronicArts|Activision|Blizzard')
                $category=if($framework){'Protected'}elseif($game){'Games'}else{'Apps'}
                $risk=if($framework -or $game){'Protected'}else{'Review'}
                $reason=if($framework){'Windows framework package'}elseif($game){'Gaming package indicators detected'}else{'Installed application package'}
                [void]$rows.Add([pscustomobject]@{Source='App';Name=$name;PackageFullName=$full;PublisherId=$publisherId;Path=$full;Publisher=$publisherId;Category=$category;Risk=$risk;Score=if($framework -or $game){0}else{20};Confidence=if($framework -or $game){96}else{70};Reason=$reason})
            } catch { if($appErrors.Count -lt 25){[void]$appErrors.Add(('App {0}: {1}' -f $app.Name,$_.Exception.Message))} }
        }
    } catch { [void]$appErrors.Add(('App inventory: {0}' -f $_.Exception.Message)) }
    if($null -ne $ErrorSink){ foreach($e in $appErrors.ToArray()){ [void]$ErrorSink.Add([string]$e) } }
    $rows.ToArray()
}

function Invoke-YumNewSystemScan {
    param(
        [int]$MaxItems=80,
        [switch]$SkipParentMap,
        [System.Collections.Generic.List[string]]$ErrorSink=$null,
        [int]$ForegroundPid=0,
        [int]$GamePid=0,
        [string[]]$KnownGames=@(),
        [string[]]$OptionalApps=@()
    )
    $started=Get-Date
    $errors=New-Object System.Collections.Generic.List[string]
    $processErrors=New-Object System.Collections.Generic.List[string]
    $serviceErrors=New-Object System.Collections.Generic.List[string]
    $appErrors=New-Object System.Collections.Generic.List[string]
    $startupErrors=New-Object System.Collections.Generic.List[string]
    $processes=@();$services=@();$apps=@();$startup=@()
    try {$processes=@(Get-YumScannerProcessRows -MaxItems $MaxItems -SkipParentMap:$SkipParentMap -ErrorSink $processErrors -ForegroundPid $ForegroundPid -GamePid $GamePid -KnownGames $KnownGames -OptionalApps $OptionalApps)} catch {$errors.Add(('Processes: {0}' -f $_.Exception.Message))}
    try {$services=@(Get-YumScannerServiceRows -MaxItems $MaxItems -ErrorSink $serviceErrors)} catch {$errors.Add(('Services: {0}' -f $_.Exception.Message))}
    try {$apps=@(Get-YumScannerAppRows -MaxItems $MaxItems -ErrorSink $appErrors)} catch {$errors.Add(('Apps: {0}' -f $_.Exception.Message))}
    try { if(Get-Command Get-YumStartupRows -ErrorAction SilentlyContinue){$startup=@(Get-YumStartupRows -MaxItems ([int]$script:Yum.Config.StartupMaxItems) -ErrorSink $startupErrors)} } catch {$errors.Add(('Startup: {0}' -f $_.Exception.Message))}
    foreach($e in $processErrors.ToArray()){[void]$errors.Add(('Process detail: {0}' -f $e))}
    foreach($e in $serviceErrors.ToArray()){[void]$errors.Add(('Service detail: {0}' -f $e))}
    foreach($e in $appErrors.ToArray()){[void]$errors.Add(('App detail: {0}' -f $e))}
    foreach($e in $startupErrors.ToArray()){[void]$errors.Add(('Startup detail: {0}' -f $e))}
    if($processes.Count -eq 0){[void]$errors.Add('Processes: scanner returned zero records. Check YUMRAM.log for detailed stage information.')}
    if($services.Count -eq 0){[void]$errors.Add('Services: scanner returned zero running-service records.')}
    if($apps.Count -eq 0){[void]$errors.Add('Apps: scanner returned zero AppX records (this may be expected on systems without AppX enumeration).')}
    $records=New-Object System.Collections.Generic.List[object]
    foreach($r in @($processes)){
        try {
            $confidence=if($r.Risk -eq 'Protected'){98}elseif($r.Risk -eq 'Safe to Manage' -or $r.Risk -eq 'Candidate'){88}elseif($r.Risk -eq 'Review'){70}else{35}
            [void]$records.Add([pscustomobject]@{StableIdentityKey=(Get-YumStableIntelligenceKeyFromValues -Source 'Process' -Name ([string]$r.Name) -Path ([string]$r.Path) -Publisher ([string]$r.Publisher));Key=(Get-YumLiveIntelligenceRecordKey -StableIdentityKey (Get-YumStableIntelligenceKeyFromValues -Source 'Process' -Name ([string]$r.Name) -Path ([string]$r.Path) -Publisher ([string]$r.Publisher)) -Source 'Process' -ProcessId $r.PID);Name=$r.Name;Category=$r.Category;Memory=('{0:N0} MB' -f [double]$r.MemoryMB);CPU=('{0:N1}%' -f [double]$r.CPU);Risk=$r.Risk;Confidence=$confidence;ConfidenceText=('{0}%' -f $confidence);Recommendation=if($r.Risk -eq 'Protected'){'Never manage automatically'}elseif($r.Risk -eq 'Safe to Manage' -or $r.Risk -eq 'Candidate'){'Manage only when needed to reach target'}elseif($r.Risk -eq 'Unknown'){'Do not manage automatically'}else{'Review before management'};Reason=$r.Reason;Publisher=$r.Publisher;Path=$r.Path;PID=$r.PID;Source='Process';Live=$true;LastSeen=(Get-Date).ToString('o');StateText='LIVE';Placement='';ActionLane='';ResearchReason=$r.Reason;ResearchConfidence=$confidence;ResearchSources=@()})
        } catch {}
    }
    foreach($s in @($services)){
        try {
            $conf=if($s.Risk -eq 'Protected'){98}else{70}
            [void]$records.Add([pscustomobject]@{StableIdentityKey=(Get-YumStableIntelligenceKeyFromValues -Source 'Service' -Name ([string]$s.DisplayName) -Path ([string]$s.Path) -Publisher ([string]$s.Publisher));Key=(Get-YumStableIntelligenceKeyFromValues -Source 'Service' -Name ([string]$s.DisplayName) -Path ([string]$s.Path) -Publisher ([string]$s.Publisher));Name=$s.DisplayName;Category='Services';Memory='—';CPU='—';Risk=$s.Risk;Confidence=$conf;ConfidenceText=('{0}%' -f $conf);Recommendation=if($s.Risk -eq 'Protected'){'Never manage automatically'}else{'Require explicit approval; check dependencies'};Reason=$s.Reason;Publisher=$s.Publisher;Path=$s.Path;PID='—';Source='Service';Live=$true;LastSeen=(Get-Date).ToString('o');StateText='LIVE';Placement='';ActionLane='';ResearchReason=$s.Reason;ResearchConfidence=$conf;ResearchSources=@()})
        } catch {}
    }
    foreach($a in @($apps)){
        try {
            [void]$records.Add([pscustomobject]@{StableIdentityKey=(Get-YumStableIntelligenceKeyFromValues -Source 'App' -Name ([string]$a.Name) -Path ([string]$a.Path) -Publisher ([string]$a.Publisher) -PackageFullName ([string]$a.PackageFullName));Key=(Get-YumStableIntelligenceKeyFromValues -Source 'App' -Name ([string]$a.Name) -Path ([string]$a.Path) -Publisher ([string]$a.Publisher) -PackageFullName ([string]$a.PackageFullName));Name=$a.Name;Category=$a.Category;Memory='—';CPU='—';Risk=$a.Risk;Confidence=$a.Confidence;ConfidenceText=('{0}%' -f $a.Confidence);Recommendation=if($a.Risk -eq 'Protected'){'Leave available; framework or game package'}else{'Leave installed; app runtime management is conditional'};Reason=$a.Reason;Publisher=$a.Publisher;Path=$a.Path;PID='—';Source='App';Live=$true;LastSeen=(Get-Date).ToString('o');StateText='LIVE';Placement='';ActionLane='';ResearchReason=$a.Reason;ResearchConfidence=$a.Confidence;ResearchSources=@()})
        } catch {}
    }
    foreach($st in @($startup)) {
        try {
            $key=('startup|{0}|{1}' -f [string]$st.Scope,[string]$st.Name).ToLowerInvariant()
            [void]$records.Add([pscustomobject]@{StableIdentityKey=$key;Key=$key;Name=$st.Name;Category=$st.Category;Memory='—';CPU='—';Risk=$st.Risk;Confidence=$st.Confidence;ConfidenceText=('{0}%' -f $st.Confidence);Recommendation=$st.Recommendation;Reason=$st.Reason;Publisher=$st.Publisher;Path=$st.Path;PID='—';Source='Startup';Live=$true;LastSeen=$st.LastSeen;StateText='LIVE';Placement=$st.Placement;ActionLane=$st.Recommendation;ResearchReason=$st.Reason;ResearchConfidence=$st.Confidence;ResearchSources=@()})
        } catch {}
    }
    $elapsed=[int]((Get-Date)-$started).TotalMilliseconds
    $nonAppErrorCount=@($errors.ToArray() | Where-Object {$_ -notmatch '^Apps: scanner returned zero'}).Count
    $status=if($processes.Count -eq 0 -and $nonAppErrorCount -gt 0){'Failed'}elseif($errors.Count -gt 0){'CompletedWithWarnings'}else{'Completed'}
    [pscustomobject]@{Status=$status;Timestamp=Get-Date;DurationMs=$elapsed;Processes=$processes;Services=$services;Apps=$apps;Startup=$startup;Records=$records.ToArray();Errors=$errors.ToArray();ProcessCount=$processes.Count;ServiceCount=$services.Count;AppCount=$apps.Count;StartupCount=$startup.Count;RecordCount=$records.Count;ResearchCount=@($records|Where-Object{$null -ne $_.PSObject.Properties['ResearchPerformed'] -and [bool]$_.ResearchPerformed}).Count}
}

function Get-YumProcessSnapshotRows {
    param([int]$MaxItems=40,[switch]$VerifySignatures,[switch]$SkipParentMap,[int]$ForegroundPid=0,[int]$GamePid=0)
    return @(Get-YumScannerProcessRows -MaxItems $MaxItems -SkipParentMap:$SkipParentMap -ForegroundPid $ForegroundPid -GamePid $GamePid)
}

function Get-YumServiceScanRows {
    param([int]$MaxItems=80)
    return @(Get-YumScannerServiceRows -MaxItems $MaxItems)
}

function Get-YumSystemScan {
    param([int]$MaxItems=80)
    $scan=Invoke-YumNewSystemScan -MaxItems $MaxItems
    $safe=@($scan.Processes | Where-Object {$_.Risk -eq 'Safe to Manage' -or $_.Risk -eq 'Candidate'})
    $review=@($scan.Processes | Where-Object {$_.Risk -eq 'Review'})
    $protected=@($scan.Processes | Where-Object {$_.Risk -eq 'Protected'})
    $sum=0; $m=$safe | Measure-Object -Property MemoryMB -Sum; if($null -ne $m.Sum){$sum=[double]$m.Sum}
    $scan | Add-Member -NotePropertyName LowRiskCount -NotePropertyValue $safe.Count -Force
    $scan | Add-Member -NotePropertyName ReviewCount -NotePropertyValue $review.Count -Force
    $scan | Add-Member -NotePropertyName ProtectedCount -NotePropertyValue $protected.Count -Force
    $scan | Add-Member -NotePropertyName CandidateWorkingSetGB -NotePropertyValue ([math]::Round($sum/1024,2)) -Force
    return $scan
}
