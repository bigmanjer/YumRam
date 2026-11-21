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

# 5.15.2: one signature check per file per scan (it was repeated for every copy of a program: ~280 ms each, 39 s
# for 240 items measured) and checked 6 at a time up front (77 files in 4.7 s measured). This made it possible
# to scan every process/service/app instead of only the top 80 by RAM, which hid small programs (VoiceMeeter).
$script:YumScannerMetaCache=@{}
function Initialize-YumScannerPublisherCache {
    param([string[]]$Paths)
    $todo=@($Paths | Where-Object { -not [string]::IsNullOrWhiteSpace($_) -and -not $script:YumScannerMetaCache.ContainsKey(([string]$_).ToLowerInvariant()) } | Select-Object -Unique)
    if($todo.Count -eq 0){return}
    $pool=$null;$jobs=@()
    try{
        $pool=[runspacefactory]::CreateRunspacePool(1,6);$pool.Open()
        $n=[math]::Min(6,$todo.Count)
        for($k=0;$k -lt $n;$k++){
            $part=@(for($i=$k;$i -lt $todo.Count;$i+=$n){$todo[$i]})
            $ps=[powershell]::Create();$ps.RunspacePool=$pool
            [void]$ps.AddScript({param($files)
                foreach($f in $files){
                    $publisher='Unknown';$company='';$product='';$signature='Unknown';$thumb=''
                    if(Test-Path -LiteralPath $f){
                        try{$vi=[Diagnostics.FileVersionInfo]::GetVersionInfo($f);$company=[string]$vi.CompanyName;$product=[string]$vi.ProductName;if(-not [string]::IsNullOrWhiteSpace($company)){$publisher=$company}}catch{}
                        try{$sig=Get-AuthenticodeSignature -FilePath $f -ErrorAction Stop;$signature=[string]$sig.Status;if($sig.SignerCertificate){try{$thumb=[string]$sig.SignerCertificate.Thumbprint}catch{};$sn=[string]$sig.SignerCertificate.GetNameInfo([Security.Cryptography.X509Certificates.X509NameType]::SimpleName,$false);if($sn -and $publisher -eq 'Unknown'){$publisher=$sn}}}catch{}
                    }
                    [pscustomobject]@{Path=$f;Publisher=$publisher;Company=$company;Product=$product;Signature=$signature;SignerThumbprint=$thumb}
                }
            }).AddArgument($part)
            $jobs+=@{PS=$ps;Handle=$ps.BeginInvoke()}
        }
        foreach($j in $jobs){ try{ foreach($m in @($j.PS.EndInvoke($j.Handle))){ if($null -ne $m){ $script:YumScannerMetaCache[([string]$m.Path).ToLowerInvariant()]=$m } } }catch{} finally{ try{$j.PS.Dispose()}catch{} } }
    }catch{} finally{ if($null -ne $pool){ try{$pool.Close();$pool.Dispose()}catch{} } }
}
function Get-YumScannerPublisherInfo {
    param([string]$Path)
    if(-not [string]::IsNullOrWhiteSpace($Path)){ $ck=$Path.ToLowerInvariant(); if($script:YumScannerMetaCache.ContainsKey($ck)){ return $script:YumScannerMetaCache[$ck] } }
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
    $meta=[pscustomobject]@{ Path=$Path; Publisher=$publisher; Company=$company; Product=$product; Signature=$signature; SignerThumbprint=$signerThumbprint }
    $script:YumScannerMetaCache[$Path.ToLowerInvariant()]=$meta
    $meta
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
    # 5.15.2: background services running as SYSTEM hide their path from a non-admin YUMRAM (ASUS, AMD, NVIDIA,
    # Realtek, Steam service... 46 "Unknown" on the test PC). Their service entry names the file; the same file
    # is then signature-checked like any other (same method as Get-YumPathlessProcessIdentity in Research).
    $serviceExe=@{}
    try{ foreach($sv in @(Get-CimInstance Win32_Service -ErrorAction Stop)){ $exe=([string]$sv.PathName) -replace '^[\"]*([^\"]+?\.exe).*$','$1'; if($exe -match '(?i)\.exe$'){ $b=[IO.Path]::GetFileNameWithoutExtension($exe).ToLowerInvariant(); if(-not $serviceExe.ContainsKey($b) -and $b -ne 'svchost'){ $serviceExe[$b]=$exe } } } }catch{}
    $pathOf=@{}
    foreach($pp in @($processes | Select-Object -First $MaxItems)){ $f='';try{$f=$pp.MainModule.FileName}catch{}; if(-not $f){ $b=([string]$pp.ProcessName).ToLowerInvariant(); if($serviceExe.ContainsKey($b) -and (Test-Path -LiteralPath $serviceExe[$b] -PathType Leaf)){ $f=$serviceExe[$b] } }; $pathOf[[int]$pp.Id]=$f }
    try{ Initialize-YumScannerPublisherCache -Paths @($pathOf.Values) }catch{}
    foreach($p in $processes) {
        if($rows.Count -ge $MaxItems){break}
        try {
            $path=''; if($pathOf.ContainsKey([int]$p.Id)){$path=[string]$pathOf[[int]$p.Id]}else{try{$path=$p.MainModule.FileName}catch{}}
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
            try{ Set-YumScannerKnownApp -Row $rows[$rows.Count-1] -Name ([string]$p.ProcessName) -Path ([string]$path) -Publisher ([string]$meta.Publisher) }catch{}
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
    try{ Initialize-YumScannerPublisherCache -Paths @($cimByName.Values | Where-Object { [string]$_.State -eq 'Running' } | ForEach-Object { ([string]$_.PathName) -replace '^[\"]*([^\"]+?\.exe).*$','$1' }) }catch{}
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
            try{ if($risk -ne 'Protected' -or $reason -notmatch 'Protected Windows'){ Set-YumScannerKnownApp -Row $rows[$rows.Count-1] -Name ([string]$svc.Name) -Path ([string]$svc.DisplayName) -Publisher ([string]$company) } }catch{}
        } catch { if($serviceErrors.Count -lt 25){[void]$serviceErrors.Add(('Service {0}: {1}' -f $svc.Name,$_.Exception.Message))} }
    }
    if($null -ne $ErrorSink){ foreach($e in $serviceErrors.ToArray()){ [void]$ErrorSink.Add([string]$e) } }
    $rows.ToArray()
}

function Get-YumAppxPublisherName {
    # Turns a package publisher DN ("CN=Microsoft Corporation, O=Microsoft Corporation, ...") into a name.
    # Store re-signed packages often have CN=<GUID>; then the package name prefix ("DTSInc.DTSXUltra"
    # -> "DTSInc") is the best readable publisher Windows gives us.
    param([string]$PublisherDn,[string]$PackageName)
    $o=[regex]::Match($PublisherDn,'(?:^|,\s*)O=("?)([^,"]+)\1')
    if($o.Success -and $o.Groups[2].Value.Trim()){return $o.Groups[2].Value.Trim()}
    $cn=[regex]::Match($PublisherDn,'(?:^|,\s*)CN=("?)([^,"]+)\1')
    if($cn.Success -and $cn.Groups[2].Value.Trim() -notmatch '^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-'){return $cn.Groups[2].Value.Trim()}
    if($PackageName -match '^([A-Za-z][A-Za-z0-9]+)\.'){return $Matches[1]}
    return ''
}

function Get-YumScannerAppRows {
    param([int]$MaxItems=80,[System.Collections.Generic.List[string]]$ErrorSink=$null)
    $rows=New-Object System.Collections.Generic.List[object]
    $appErrors=New-Object System.Collections.Generic.List[string]
    try {
        # 5.4: read Windows' own package metadata. 5.3.x stored the publisher *ID hash* (e.g. 8wekyb3d8bbwe)
        # as the publisher name and ignored SignatureKind, so built-in Windows components and Store apps
        # could not be identified and ended up Unknown.
        $packages=@(Get-AppxPackage -ErrorAction SilentlyContinue | Select-Object -First $MaxItems Name,PackageFullName,PublisherId,Publisher,SignatureKind,IsFramework,NonRemovable,InstallLocation)
        foreach($app in $packages){
            try {
                $name=[string]$app.Name;$full=[string]$app.PackageFullName;$publisherId=[string]$app.PublisherId;$framework=[bool]$app.IsFramework
                $signatureKind=[string]$app.SignatureKind
                $systemPackage=($signatureKind -eq 'System' -or [bool]$app.NonRemovable)
                $publisherName=Get-YumAppxPublisherName -PublisherDn ([string]$app.Publisher) -PackageName $name
                $friendly=$name
                if($name -match '^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-' -and -not [string]::IsNullOrWhiteSpace([string]$app.InstallLocation)){
                    # GUID-named packages: the install folder carries the readable name (e.g. Microsoft.Windows.FilePicker).
                    $friendly=((Split-Path -Leaf ([string]$app.InstallLocation)) -replace '_[a-z0-9]{13}$','')
                }
                $game=(-not $systemPackage) -and ($name -match '(?i)xbox|gaming|gamebar|\bgame|steam|epicgames|riotgames|ubisoft|electronicarts|\bEA\b|battle\.?net|blizzard' -or $publisherName -match '(?i)xbox|valve|epic games|riot games|ubisoft|electronic arts|activision|blizzard')
                $category=if($framework -or $systemPackage){'Protected'}elseif($game){'Games'}else{'Apps'}
                $risk=if($framework -or $systemPackage -or $game){'Protected'}else{'Review'}
                $reason=if($systemPackage){'Built-in Windows component ({0}; signature kind {1})' -f $friendly,$signatureKind}elseif($framework){'Windows framework package'}elseif($game){'Gaming package indicators detected'}elseif($signatureKind -eq 'Store'){'Microsoft Store-signed package from {0}' -f $publisherName}else{'Installed application package ({0}-signed)' -f $signatureKind}
                $confidence=if($framework -or $game -or $systemPackage){96}elseif($signatureKind -eq 'Store' -and $publisherName){88}else{70}
                [void]$rows.Add([pscustomobject]@{Source='App';Name=$name;DisplayName=$friendly;PackageFullName=$full;PublisherId=$publisherId;Path=$full;Publisher=$publisherName;SignatureKind=$signatureKind;Category=$category;Risk=$risk;Score=if($framework -or $game -or $systemPackage){0}else{20};Confidence=$confidence;Reason=$reason})
                try{ if(-not $systemPackage -and -not $framework){ Set-YumScannerKnownApp -Row $rows[$rows.Count-1] -Name $name -Path $friendly -Publisher $publisherName } }catch{}
            } catch { if($appErrors.Count -lt 25){[void]$appErrors.Add(('App {0}: {1}' -f $app.Name,$_.Exception.Message))} }
        }
    } catch { [void]$appErrors.Add(('App inventory: {0}' -f $_.Exception.Message)) }
    if($null -ne $ErrorSink){ foreach($e in $appErrors.ToArray()){ [void]$ErrorSink.Add([string]$e) } }
    $rows.ToArray()
}

# 5.15.2: well-known programs YUMRAM used to miss or file as "Identified Applications" (user report: VoiceMeeter,
# Roblox beta, ASUS and HP software). Matched on name, file path, publisher or installed-program name.
# Advice: Keep = needed for the PC or your devices; YourCall = optional extra, fine to turn off; Game = protected.
$script:YumKnownApps=@(
    @{M='(?i)^roblox(playerbeta|playerlauncher|player|studiobeta|studiolauncherbeta|studio|crashhandler)?$|\\roblox\\versions\\|^roblox player|^roblox studio';L='Roblox';C='Games';R='Protected';A='Game';W='The Roblox game client. "RobloxPlayerBeta.exe" is simply the normal Roblox player''s file name, not a test version.'}
    @{M='(?i)^(bloxstrap|fishstrap|voidstrap)\b';L='Roblox launcher (Bloxstrap / Fishstrap)';C='Games';R='Protected';A='Game';W='A community launcher that starts Roblox with extra settings.'}
    @{M='(?i)^voicemeeter|\\vb\\voicemeeter\\|vb-audio voicemeeter|^voicemeeter';L='VoiceMeeter (VB-Audio)';C='Drivers / Hardware';R='Protected';A='Keep';W='A virtual audio mixer that routes your microphone and speakers. Closing it cuts your sound until you open it again.'}
    @{M='(?i)vb-audio virtual cable|^vbcable|vb-cable|\\vb\\cable\\';L='VB-Audio Virtual Cable';C='Drivers / Hardware';R='Protected';A='Keep';W='A virtual audio cable driver used by streaming and voice apps.'}
    @{M='(?i)^armourycrate|armoury crate';L='ASUS Armoury Crate';C='Drivers / Hardware';R='Protected';A='Keep';W='ASUS control for fan speed, performance modes, lighting and the keyboard keys.'}
    @{M='(?i)^asusptpservice$|asus precision touchpad';L='ASUS Touchpad';C='Drivers / Hardware';R='Protected';A='Keep';W='Makes the touchpad gestures work.'}
    @{M='(?i)^asushotkey$|^asusosd$|^hkeyservice|asus hotkey|^atkosd|^hcontrol$';L='ASUS Fn keys and on-screen display';C='Drivers / Hardware';R='Protected';A='Keep';W='Makes the Fn keys work (volume, brightness, keyboard light) and shows their pop-up on screen.'}
    @{M='(?i)^asusoptimization|asus optimization';L='ASUS Optimization (MyASUS)';C='Drivers / Hardware';R='Protected';A='Keep';W='Battery care, fan profiles and other MyASUS hardware settings.'}
    @{M='(?i)^asussystemanalysis$|^asussystemdiagnosis$|asus system (analysis|diagnosis)';L='ASUS System Analysis / Diagnosis (MyASUS)';C='Apps';R='Review';A='YourCall';W='MyASUS health checks that run in the background. Optional: the PC works the same without them.'}
    @{M='(?i)^asussoftwaremanager(agent)?$|asus software manager';L='ASUS Software Manager (MyASUS)';C='Apps';R='Review';A='YourCall';W='Checks for ASUS app and driver updates. Optional: Windows Update also delivers ASUS drivers.'}
    @{M='(?i)^asusappservice$|asus app service';L='ASUS App Service (MyASUS)';C='Apps';R='Review';A='YourCall';W='Background service for the MyASUS app.'}
    @{M='(?i)^asusswitch$|asus switch';L='ASUS Switch (MyASUS Link)';C='Apps';R='Review';A='YourCall';W='Connects your phone or another ASUS PC through MyASUS. Optional if you do not use that.'}
    @{M='(?i)^asuswifismartconnect|wifi smart connect';L='ASUS WiFi SmartConnect';C='Apps';R='Review';A='YourCall';W='Switches to the strongest Wi-Fi automatically. Optional.'}
    @{M='(?i)^refreshrateservice$|asus smart display control|^asussplendid|splendid';L='ASUS display settings';C='Drivers / Hardware';R='Protected';A='Keep';W='Screen colour and refresh-rate switching (for example lower refresh rate on battery).'}
    @{M='(?i)asuspcassistant|^myasus';L='MyASUS';C='Apps';R='Review';A='YourCall';W='ASUS support app: warranty, updates, battery and fan settings.'}
    @{M='(?i)^lightingservice$|aura (sync|service)|^asus_framework';L='ASUS Aura lighting';C='Drivers / Hardware';R='Review';A='YourCall';W='Controls RGB lighting. Needed only if you use lighting effects.'}
    @{M='(?i)^asuscertservice$|^asusupdatecheck|^asusmsgcenter|^asusnotification';L='ASUS helper';C='Apps';R='Review';A='YourCall';W='A small ASUS helper (certificates, update checks or notifications). Optional.'}
    @{M='(?i)hptouchpointanalytics|hp insights analytics|^hpinsights';L='HP Insights Analytics';C='Apps';R='Review';A='YourCall';W='Sends usage and health data to HP. Optional; turning it off does not affect the PC.'}
    @{M='(?i)^(sysinfocap|apphelpercap|diagscap|networkcap)$|hp app helper hsa|hp system info hsa|hp diagnostics hsa|hp network hsa';L='HP system info helpers (HSA)';C='Apps';R='Review';A='YourCall';W='HP background helpers that collect system information for HP support apps. Optional.'}
    @{M='(?i)hpsupportassistant|hp support assistant|^hpsa_service|^hpsupportsolutions';L='HP Support Assistant';C='Apps';R='Review';A='YourCall';W='HP updates and diagnostics. Optional: Windows Update also delivers HP drivers.'}
    @{M='(?i)^hpaudioswitch|hp audio switch';L='HP Audio Switch';C='Drivers / Hardware';R='Review';A='YourCall';W='Switches between speakers and headsets. Needed only if you use it.'}
    @{M='(?i)^hphotkeymonitor|^hotkeyserviceuwp|hp hotkey|^hpqwmiex|hp wmi';L='HP Fn keys';C='Drivers / Hardware';R='Protected';A='Keep';W='Makes the Fn keys work (volume, brightness, keyboard light).'}
    @{M='(?i)^omen(commandcenter|cap|installmonitor)|omen gaming hub|^overlayhelper$|\\hp\\omen';L='OMEN Gaming Hub (HP)';C='Drivers / Hardware';R='Protected';A='Keep';W='HP OMEN control for fans, performance modes and lighting.'}
    @{M='(?i)hpjumpstart|hp jumpstart';L='HP JumpStart';C='Apps';R='Review';A='YourCall';W='First-start tips and offers from HP. Safe to turn off.'}
    @{M='(?i)hpprintscandoctor|hp smart|hpprintercontrol|^hpnetworkcommunicator|hp network communicator';L='HP printer software';C='Apps';R='Review';A='YourCall';W='HP printer apps and helpers. Needed only if you print with an HP printer.'}
    @{M='(?i)hp wolf security|^br(service|console|ui)$|bromium|^uiwatchdog';L='HP Wolf Security';C='Security';R='Protected';A='Keep';W='HP security software that isolates risky files and web pages. Keep it unless you remove it on purpose.'}
    @{M='(?i)^hp (sure|connection optimizer|presence)|^hpcommrecovery|hp comm recovery';L='HP system helper';C='Apps';R='Review';A='YourCall';W='An HP helper for a specific feature (recovery, Wi-Fi optimisation or camera presence). Optional.'}
)
function Get-YumKnownApp {
    param([string]$Name,[string]$Path='',[string]$Publisher='',[string]$DisplayName='')
    foreach($text in @($Name,$DisplayName,$Path)){
        if([string]::IsNullOrWhiteSpace($text)){continue}
        $t=($text -replace '\.exe$','')
        foreach($k in $script:YumKnownApps){ if($t -match $k.M){ return [pscustomobject]@{Label=$k.L;Category=$k.C;Risk=$k.R;Advice=$k.A;What=$k.W} } }
    }
    if($Publisher -match '(?i)^ASUSTeK'){ return [pscustomobject]@{Label='ASUS software';Category='Drivers / Hardware';Risk='Review';Advice='YourCall';What='Software from ASUS, your PC''s maker. Hardware parts (fans, keys, touchpad) are protected; extras like diagnostics and update checkers are optional.'} }
    if($Publisher -match '(?i)^(HP Inc|Hewlett[- ]Packard)'){ return [pscustomobject]@{Label='HP software';Category='Drivers / Hardware';Risk='Review';Advice='YourCall';What='Software from HP, your PC''s maker. Hardware parts are protected; extras like analytics and support apps are optional.'} }
    return $null
}
function Get-YumRecordAdvice {
    # 5.15.2 (user report: "hard to find out what is recommended / your call / keep"). One plain answer per item,
    # same words and colours on every page: Keep (pink) / Turn off is fine (green) / Your call (blue) / Careful (red).
    param($Record)
    $g={param([string]$p) try{ if($null -ne $Record.PSObject.Properties[$p]){[string]$Record.$p}else{''} }catch{''} }
    $risk=& $g 'Risk';$cat=& $g 'Category';$advice=& $g 'Advice'
    if(-not $advice){ $k=$null; try{ $k=Get-YumKnownApp -Name (& $g 'Name') -Path (& $g 'Path') -Publisher (& $g 'Publisher') -DisplayName (& $g 'DisplayName') }catch{}; if($null -ne $k -and $risk -ne 'Unknown'){ $advice=$k.Advice } }
    if($risk -eq 'Unknown' -or $cat -eq 'Unknown'){ return [pscustomobject]@{Label='Careful';Color='#F87171';Why='Not identified yet. Leave it alone until it is researched, or look it up online / open its file location to see what it is.'} }
    if($advice -eq 'Game' -or $cat -match '(?i)game'){ return [pscustomobject]@{Label='Keep';Color='#F9A8D4';Why='A game or game launcher. Protected while you play.'} }
    if($advice -eq 'Keep'){ return [pscustomobject]@{Label='Keep';Color='#F9A8D4';Why='Needed for your devices or the PC to work normally.'} }
    if($advice -eq 'YourCall'){ return [pscustomobject]@{Label='Your call';Color='#7DD3FC';Why='Optional extra. The PC works the same without it; turn it off if you do not use it.'} }
    if($risk -eq 'Protected'){ return [pscustomobject]@{Label='Keep';Color='#F9A8D4';Why='Part of Windows, your security or your hardware. YUMRAM never touches it.'} }
    if($risk -in @('Safe to Manage','Candidate')){ return [pscustomobject]@{Label='Turn off is fine';Color='#4ADE80';Why='Safe to close when you are not using it. YUMRAM may trim its memory when RAM is short.'} }
    return [pscustomobject]@{Label='Your call';Color='#7DD3FC';Why='A normal program. Keep it if you use it; YUMRAM only trims it with your approval.'}
}
function Resolve-YumRecordLocation {
    # 5.15.2: the file (or folder) behind an Intelligence record, for "Open file location".
    param($Record)
    $g={param([string]$p) try{ if($null -ne $Record.PSObject.Properties[$p]){[string]$Record.$p}else{''} }catch{''} }
    $src=& $g 'Source';$path=& $g 'Path'
    if($src -eq 'App'){
        $pkg=$path;try{ $a=Get-AppxPackage -ErrorAction Stop | Where-Object { $_.PackageFullName -eq $pkg -or $_.Name -eq (& $g 'Name') } | Select-Object -First 1; if($a -and $a.InstallLocation){ return [string]$a.InstallLocation } }catch{}
        return ''
    }
    if([string]::IsNullOrWhiteSpace($path)){ return '' }
    $p=[Environment]::ExpandEnvironmentVariables($path.Trim())
    if(Test-Path -LiteralPath $p){ return $p }
    $m=[regex]::Match($p,'^\s*"([^"]+)"');if($m.Success -and (Test-Path -LiteralPath $m.Groups[1].Value)){ return $m.Groups[1].Value }
    $m=[regex]::Match($p,'^(.+?\.(exe|dll|cmd|bat|lnk))(\s|,|$)','IgnoreCase');if($m.Success -and (Test-Path -LiteralPath $m.Groups[1].Value)){ return $m.Groups[1].Value }
    return ''
}
function Get-YumScannerProgramRows {
    # 5.15.2: classic installed programs (Settings > Apps), not only Store apps. VoiceMeeter, Roblox and HP
    # Support Assistant install this way and were never listed. Read-only registry access.
    param([int]$MaxItems=500,[System.Collections.Generic.List[string]]$ErrorSink=$null)
    $rows=New-Object System.Collections.Generic.List[object];$seen=@{}
    foreach($root in @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall','HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall','HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall')){
        try{
            foreach($k in @(Get-ChildItem -LiteralPath $root -ErrorAction SilentlyContinue)){
                if($rows.Count -ge $MaxItems){break}
                try{
                    $v=Get-ItemProperty -LiteralPath $k.PSPath -ErrorAction Stop
                    $gv={param([string]$n) if($null -ne $v.PSObject.Properties[$n]){[string]$v.$n}else{''}}   # strict-mode safe
                    $name=& $gv 'DisplayName'
                    if([string]::IsNullOrWhiteSpace($name)){continue}
                    if(($v.PSObject.Properties['SystemComponent'] -and [int]$v.SystemComponent -eq 1) -or $v.PSObject.Properties['ParentKeyName'] -or $v.PSObject.Properties['ReleaseType']){continue}
                    if($seen.ContainsKey($name.ToLowerInvariant())){continue};$seen[$name.ToLowerInvariant()]=$true
                    $pub=& $gv 'Publisher'
                    $loc=& $gv 'InstallLocation'
                    if([string]::IsNullOrWhiteSpace($loc) -and $v.PSObject.Properties['DisplayIcon']){ $ic=((& $gv 'DisplayIcon') -replace ',\s*-?\d+$','').Trim('"'); if($ic -and (Test-Path -LiteralPath $ic -PathType Leaf)){$loc=$ic} }
                    $known=Get-YumKnownApp -Name $name -Path $loc -Publisher $pub -DisplayName $name
                    $windows=($pub -match '^Microsoft' -and $name -match '(?i)visual c\+\+|\.net|windows|edge webview|runtime|redistributable|update health|sdk')
                    $category=if($known){$known.Category}elseif($windows){'Protected'}else{'Apps'}
                    $risk=if($known){$known.Risk}elseif($windows){'Protected'}else{'Review'}
                    $reason=if($known){'{0}: {1}' -f $known.Label,$known.What}elseif($windows){'Microsoft runtime or component other programs need'}elseif($pub){'Installed program from {0}' -f $pub}else{'Installed program'}
                    [void]$rows.Add([pscustomobject]@{Source='Program';Name=$name;DisplayName=$name;Publisher=$(if($pub){$pub}else{'Unknown'});Path=$loc;Version=(& $gv 'DisplayVersion');Scope=$(if($root -like 'HKCU:*'){'User'}else{'Machine'});Category=$category;Risk=$risk;Confidence=$(if($known -or $windows){95}elseif($pub){80}else{55});Reason=$reason;KnownApp=$(if($known){$known.Label}else{''});Advice=$(if($known){$known.Advice}else{''})})
                }catch{ if($null -ne $ErrorSink -and $ErrorSink.Count -lt 25){[void]$ErrorSink.Add(('Program {0}: {1}' -f $k.PSChildName,$_.Exception.Message))} }
            }
        }catch{}
    }
    $rows.ToArray()
}
function Set-YumScannerKnownApp {
    # Applies the catalog to a scanner row (keeps Windows-core / foreground / active-game protection).
    param($Row,[string]$Name,[string]$Path,[string]$Publisher)
    $known=Get-YumKnownApp -Name $Name -Path $Path -Publisher $Publisher
    if($null -eq $known){return}
    # A name alone proves nothing: an unidentified (unsigned / no publisher) file only gets a hint and stays
    # Unknown (never managed automatically, still researched).
    if([string]$Row.Risk -eq 'Unknown'){ $Row.Reason=('Named like {0}, but the file''s publisher could not be verified. {1}' -f $known.Label,[string]$Row.Reason); return }
    if(-not ([string]$Row.Risk -eq 'Protected' -and [string]$Row.Reason -match 'Foreground|Active game|Windows core')){
        $Row.Category=$known.Category;$Row.Risk=$known.Risk
    }
    $Row.Reason=('{0}: {1}' -f $known.Label,$known.What)
    $Row|Add-Member -NotePropertyName KnownApp -NotePropertyValue $known.Label -Force
    $Row|Add-Member -NotePropertyName Advice -NotePropertyValue $known.Advice -Force
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
    $processes=@();$services=@();$apps=@();$startup=@();$programs=@()
    # 5.15.2: every item, not the first 80 (Settings' old 80 left out ~60 % of this PC: small programs such as
    # VoiceMeeter, most services and apps). 500 per kind is only a safety cap.
    $wide=[math]::Max($MaxItems,500)
    try {$processes=@(Get-YumScannerProcessRows -MaxItems $wide -SkipParentMap:$SkipParentMap -ErrorSink $processErrors -ForegroundPid $ForegroundPid -GamePid $GamePid -KnownGames $KnownGames -OptionalApps $OptionalApps)} catch {$errors.Add(('Processes: {0}' -f $_.Exception.Message))}
    try {$services=@(Get-YumScannerServiceRows -MaxItems $wide -ErrorSink $serviceErrors)} catch {$errors.Add(('Services: {0}' -f $_.Exception.Message))}
    try {$apps=@(Get-YumScannerAppRows -MaxItems $wide -ErrorSink $appErrors)} catch {$errors.Add(('Apps: {0}' -f $_.Exception.Message))}
    try {$programs=@(Get-YumScannerProgramRows -MaxItems $wide -ErrorSink $appErrors)} catch {$errors.Add(('Programs: {0}' -f $_.Exception.Message))}
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
            [void]$records.Add([pscustomobject]@{StableIdentityKey=(Get-YumStableIntelligenceKeyFromValues -Source 'Process' -Name ([string]$r.Name) -Path ([string]$r.Path) -Publisher ([string]$r.Publisher));Key=(Get-YumLiveIntelligenceRecordKey -StableIdentityKey (Get-YumStableIntelligenceKeyFromValues -Source 'Process' -Name ([string]$r.Name) -Path ([string]$r.Path) -Publisher ([string]$r.Publisher)) -Source 'Process' -ProcessId $r.PID);Name=$r.Name;Category=$r.Category;Memory=('{0:N0} MB' -f [double]$r.MemoryMB);CPU=('{0:N1}%' -f [double]$r.CPU);Risk=$r.Risk;Confidence=$confidence;ConfidenceText=('{0}%' -f $confidence);Recommendation=if($r.Risk -eq 'Protected'){'Never manage automatically'}elseif($r.Risk -eq 'Safe to Manage' -or $r.Risk -eq 'Candidate'){'Manage only when needed to reach target'}elseif($r.Risk -eq 'Unknown'){'Do not manage automatically'}else{'Review before management'};Reason=$r.Reason;Publisher=$r.Publisher;Path=$r.Path;PID=$r.PID;Source='Process';Live=$true;LastSeen=(Get-Date).ToString('o');StateText='LIVE';Placement='';ActionLane='';KnownApp=$(if($r.PSObject.Properties['KnownApp']){[string]$r.KnownApp}else{''});Advice=$(if($r.PSObject.Properties['Advice']){[string]$r.Advice}else{''});ResearchReason=$r.Reason;ResearchConfidence=$confidence;ResearchSources=@()})
        } catch {}
    }
    foreach($s in @($services)){
        try {
            $conf=if($s.Risk -eq 'Protected'){98}else{70}
            [void]$records.Add([pscustomobject]@{StableIdentityKey=(Get-YumStableIntelligenceKeyFromValues -Source 'Service' -Name ([string]$s.DisplayName) -Path ([string]$s.Path) -Publisher ([string]$s.Publisher));Key=(Get-YumStableIntelligenceKeyFromValues -Source 'Service' -Name ([string]$s.DisplayName) -Path ([string]$s.Path) -Publisher ([string]$s.Publisher));Name=$s.DisplayName;Category='Services';Memory='—';CPU='—';Risk=$s.Risk;Confidence=$conf;ConfidenceText=('{0}%' -f $conf);Recommendation=if($s.Risk -eq 'Protected'){'Never manage automatically'}else{'Require explicit approval; check dependencies'};Reason=$s.Reason;Publisher=$s.Publisher;Path=$s.Path;PID='—';Source='Service';Live=$true;LastSeen=(Get-Date).ToString('o');StateText='LIVE';Placement='';ActionLane='';KnownApp=$(if($s.PSObject.Properties['KnownApp']){[string]$s.KnownApp}else{''});Advice=$(if($s.PSObject.Properties['Advice']){[string]$s.Advice}else{''});ResearchReason=$s.Reason;ResearchConfidence=$conf;ResearchSources=@()})
        } catch {}
    }
    foreach($a in @($apps)){
        try {
            [void]$records.Add([pscustomobject]@{StableIdentityKey=(Get-YumStableIntelligenceKeyFromValues -Source 'App' -Name ([string]$a.Name) -Path ([string]$a.Path) -Publisher ([string]$(if($a.PSObject.Properties['PublisherId'] -and $a.PublisherId){$a.PublisherId}else{$a.Publisher})) -PackageFullName ([string]$a.PackageFullName));Key=(Get-YumStableIntelligenceKeyFromValues -Source 'App' -Name ([string]$a.Name) -Path ([string]$a.Path) -Publisher ([string]$(if($a.PSObject.Properties['PublisherId'] -and $a.PublisherId){$a.PublisherId}else{$a.Publisher})) -PackageFullName ([string]$a.PackageFullName));Name=$a.Name;Category=$a.Category;Memory='—';CPU='—';Risk=$a.Risk;Confidence=$a.Confidence;ConfidenceText=('{0}%' -f $a.Confidence);Recommendation=if($a.Risk -eq 'Protected'){'Leave available; framework or game package'}else{'Leave installed; app runtime management is conditional'};Reason=$a.Reason;Publisher=$a.Publisher;DisplayName=$(if($a.PSObject.Properties['DisplayName']){$a.DisplayName}else{$a.Name});SignatureKind=$(if($a.PSObject.Properties['SignatureKind']){$a.SignatureKind}else{''});Path=$a.Path;PID='—';Source='App';Live=$true;LastSeen=(Get-Date).ToString('o');StateText='LIVE';Placement='';ActionLane='';KnownApp=$(if($a.PSObject.Properties['KnownApp']){[string]$a.KnownApp}else{''});Advice=$(if($a.PSObject.Properties['Advice']){[string]$a.Advice}else{''});ResearchReason=$a.Reason;ResearchConfidence=$a.Confidence;ResearchSources=@()})
        } catch {}
    }
    foreach($pr in @($programs)){
        try {
            $key=Get-YumStableIntelligenceKeyFromValues -Source 'Program' -Name ([string]$pr.Name) -Path ([string]$pr.Scope) -Publisher ([string]$pr.Publisher)
            [void]$records.Add([pscustomobject]@{StableIdentityKey=$key;Key=$key;Name=$pr.Name;Category=$pr.Category;Memory='—';CPU='—';Risk=$pr.Risk;Confidence=$pr.Confidence;ConfidenceText=('{0}%' -f $pr.Confidence);Recommendation=if($pr.Risk -eq 'Protected'){'Leave installed; needed by the PC or a device'}else{'Installed program; YUMRAM only acts on it while it runs'};Reason=$pr.Reason;Publisher=$pr.Publisher;DisplayName=$pr.DisplayName;Product=$pr.Name;Version=$pr.Version;Path=$pr.Path;PID='—';Source='Program';Live=$true;LastSeen=(Get-Date).ToString('o');StateText='INSTALLED';Placement='';ActionLane='';ResearchReason=$pr.Reason;ResearchConfidence=$pr.Confidence;ResearchSources=@();KnownApp=$pr.KnownApp;Advice=$pr.Advice;IdentityState='Identified';AutoResearchEligible=$false})
        } catch {}
    }    foreach($st in @($startup)) {
        try {
            $key=('startup|{0}|{1}' -f [string]$st.Scope,[string]$st.Name).ToLowerInvariant()
            [void]$records.Add([pscustomobject]@{StableIdentityKey=$key;Key=$key;Name=$st.Name;Category=$st.Category;Memory='—';CPU='—';Risk=$st.Risk;Confidence=$st.Confidence;ConfidenceText=('{0}%' -f $st.Confidence);Recommendation=$st.Recommendation;Reason=$st.Reason;Publisher=$st.Publisher;Path=$st.Path;PID='—';Source='Startup';Live=$true;LastSeen=$st.LastSeen;StateText='LIVE';Placement=$st.Placement;ActionLane=$st.Recommendation;ResearchReason=$st.Reason;ResearchConfidence=$st.Confidence;ResearchSources=@()})
        } catch {}
    }
    $elapsed=[int]((Get-Date)-$started).TotalMilliseconds
    $nonAppErrorCount=@($errors.ToArray() | Where-Object {$_ -notmatch '^Apps: scanner returned zero'}).Count
    $status=if($processes.Count -eq 0 -and $nonAppErrorCount -gt 0){'Failed'}elseif($errors.Count -gt 0){'CompletedWithWarnings'}else{'Completed'}
    [pscustomobject]@{Status=$status;Timestamp=Get-Date;DurationMs=$elapsed;Processes=$processes;Services=$services;Apps=$apps;Startup=$startup;Records=$records.ToArray();Errors=$errors.ToArray();ProcessCount=$processes.Count;ServiceCount=$services.Count;AppCount=$apps.Count;ProgramCount=$programs.Count;Programs=$programs;StartupCount=$startup.Count;RecordCount=$records.Count;ResearchCount=@($records|Where-Object{$null -ne $_.PSObject.Properties['ResearchPerformed'] -and [bool]$_.ResearchPerformed}).Count}
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
