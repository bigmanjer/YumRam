#requires -Version 5.1
Set-StrictMode -Version Latest

# Per-run evidence inventories (reset by Invoke-YumResearch). Declared here so the helpers also work when
# called on their own under StrictMode, where reading an unset script variable throws.
$script:YumResearchRegistryInventory=$null
$script:YumResearchAppxInventory=$null
$script:YumResearchServiceInventory=$null
$script:YumResearchWinGetInventory=$null

function Get-YumResearchSafeProperty {
    param([object]$Object,[string]$Name,[object]$Default='')
    if($null -eq $Object -or [string]::IsNullOrWhiteSpace($Name)){ return $Default }
    try {
        $prop=$Object.PSObject.Properties[$Name]
        if($null -ne $prop -and $null -ne $prop.Value){ return $prop.Value }
    } catch {}
    return $Default
}

function Ensure-YumResearchRecordSchema {
    param([Parameter(Mandatory=$true)]$Record)
    $defaults=[ordered]@{
        Key=''
        Name=''
        Category='Apps'
        Placement='Review Queue'
        Risk='Review'
        Recommendation='Review before management'
        ActionLane='Review before management'
        ManualOverride=$false
        ResearchStatus='Not Researched'
        ResearchComplete=$false
        ResearchPerformed=$false
        ResearchExhausted=$false
        ResearchConfidence=0
        ResearchSources=@()
        ResearchLinks=@()
        ResearchReason='Awaiting research.'
        ResearchErrorState=''
        ResearchStarted=''
        ResearchCompleted=''
        ResearchCompletedAt=''
        ResearchDecision=''
        OnlineResearchPerformed=$false
        OnlineMatchConfidence=0
        VerifiedSourceCount=0
        ResearchRunDisposition='Unchanged'
        ResearchRunResolved=$false
        ResearchRunOnline=$false
        ResearchEvidenceFingerprint=''
        Publisher='Unknown'
        Path=''
        Product=''
        Version=''
        FileHash=''
        SignerThumbprint=''
        Signature='Unknown'
    }
    foreach($name in $defaults.Keys){
        try {
            $prop=$Record.PSObject.Properties[$name]
            if($null -eq $prop){$Record|Add-Member -NotePropertyName $name -NotePropertyValue $defaults[$name] -Force}
            elseif($null -eq $prop.Value){$prop.Value=$defaults[$name]}
        } catch {}
    }
    return $Record
}

function Get-YumResearchOnlineProvider {
    # Canonical injection path: Config.OnlineResearchProvider.
    # Top-level Yum.OnlineResearchProvider remains a compatibility fallback for older callers.
    $provider=$null
    try {
        if($null -ne $script:Yum -and $null -ne $script:Yum.Config){
            $prop=$script:Yum.Config.PSObject.Properties['OnlineResearchProvider']
            if($null -ne $prop -and $null -ne $prop.Value){$provider=$prop.Value}
        }
    } catch {}
    if($null -eq $provider){
        try {
            if($null -ne $script:Yum){
                $prop=$script:Yum.PSObject.Properties['OnlineResearchProvider']
                if($null -ne $prop -and $null -ne $prop.Value){$provider=$prop.Value}
            }
        } catch {}
    }
    return $provider
}

function Invoke-YumResearchOnlineProvider {
    param([Parameter(Mandatory=$true)]$Provider,[string]$Name,[string]$Publisher,[string]$Product)
    if($Provider -is [scriptblock]){
        return & $Provider $Name $Publisher $Product
    }
    try {
        $invoke=$Provider.PSObject.Methods['Invoke']
        if($null -ne $invoke){ return $invoke.Invoke(@($Name,$Publisher,$Product)) }
    } catch {}
    throw 'Configured OnlineResearchProvider is not invokable.'
}

function Get-YumResearchStatusPath {
    if($null -ne $script:Yum -and $script:Yum.ConfigDirectory){return (Join-Path $script:Yum.ConfigDirectory 'research-status.json')}
    return (Join-Path $script:Yum.Root 'research-status.json')
}
function Write-YumResearchDiagnostic {
    param([string]$RunId,[string]$Stage,[string]$Message,[string]$Name='', [string]$Key='', [System.Exception]$Exception=$null)
    try {
        $root=[string]$script:Yum.Root
        if([string]::IsNullOrWhiteSpace($root)) { $root=(Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) }
        $dir=Join-Path $root 'Runtime'
        if(-not(Test-Path -LiteralPath $dir)){New-Item -ItemType Directory -Path $dir -Force|Out-Null}
        $path=Join-Path $dir 'Research-Diagnostics.log'
        $type='';$detail=''
        if($null -ne $Exception){$type=$Exception.GetType().FullName;$detail=$Exception.ToString()}
        $line='[{0}] Run={1} Stage={2} Name={3} Key={4} Message={5}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'),$RunId,$Stage,($Name -replace '[\r\n]',' '),$Key,($Message -replace '[\r\n]',' ')
        if($type){$line += ' ExceptionType=' + $type + ' Exception=' + ($detail -replace '[\r\n]',' | ')}
        [System.IO.File]::AppendAllText($path,$line+[Environment]::NewLine,([System.Text.UTF8Encoding]::new($false)))
    } catch {
        # Diagnostic logging must never interfere with research execution.
    }
}

function Set-YumResearchStatus {
    param([string]$Key,[string]$Name,[string]$Stage,[int]$Index,[int]$Total,[string]$Message='', [int]$Confidence=0, [string]$Placement='', [string]$Error='')
    try {
        $path=Get-YumResearchStatusPath
        $dir=Split-Path -Parent $path
        if(-not (Test-Path -LiteralPath $dir)){New-Item -ItemType Directory -Path $dir -Force | Out-Null}
        $completed=($Stage -in @('Organized','Unknown','Research Error','Error','Skipped','Complete'))
        $status=[ordered]@{Version='1';Pid=$PID;EngineVersion=[string]$script:Yum.Config.ResearchEngineVersion;Updated=(Get-Date).ToString('o');Key=$Key;Name=$Name;Stage=$Stage;Index=$Index;Total=$Total;Message=$Message;Confidence=$Confidence;Placement=$Placement;Error=$Error;Completed=$completed}
        try {
            if($null -ne $script:Yum -and $null -ne $script:Yum.ResearchState){
                $script:Yum.ResearchState.Phase=if($completed){'Complete'}else{'Researching'}
                $script:Yum.ResearchState.Stage=$Stage
                $script:Yum.ResearchState.Index=$Index
                $script:Yum.ResearchState.Total=$Total
                $script:Yum.ResearchState.Key=$Key
                $script:Yum.ResearchState.Name=$Name
                $script:Yum.ResearchState.Message=$Message
                $script:Yum.ResearchState.Confidence=$Confidence
                $script:Yum.ResearchState.Completed=$completed
                $script:Yum.ResearchState.Updated=Get-Date
                $script:Yum.ResearchState.Error=$Error
            }
        } catch {}
        $tmp="$path.tmp"
        $status | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $tmp -Encoding UTF8
        Move-Item -LiteralPath $tmp -Destination $path -Force
    } catch {}
}

function Get-YumResearchCachePath {
    if($script:Yum -and $script:Yum.ConfigDirectory){return (Join-Path $script:Yum.ConfigDirectory 'research-cache.json')}
    return (Join-Path $script:Yum.Root 'research-cache.json')
}

function Load-YumResearchCache {
    try {
        $path=Get-YumResearchCachePath
        if(Test-Path -LiteralPath $path){
            $raw=Get-Content -LiteralPath $path -Raw -ErrorAction Stop
            if(-not [string]::IsNullOrWhiteSpace($raw)){
                $obj=$raw|ConvertFrom-Json -ErrorAction Stop
                $h=@{}
                foreach($p in $obj.PSObject.Properties){$h[[string]$p.Name]=$p.Value}
                return $h
            }
        }
    } catch { try{Write-YumLogException -Context 'Research cache load failed' -Exception $_.Exception}catch{} }
    return @{}
}

function Save-YumResearchCache {
    param([hashtable]$Cache)
    try {
        $path=Get-YumResearchCachePath;$dir=Split-Path -Parent $path
        if(-not(Test-Path -LiteralPath $dir)){New-Item -ItemType Directory -Path $dir -Force|Out-Null}
        $tmp="$path.tmp"
        $payload=[ordered]@{Version='2';EngineVersion=([string]$script:Yum.Config.ResearchEngineVersion);Updated=(Get-Date).ToString('o');Items=$Cache}
        $payload|ConvertTo-Json -Depth 10|Set-Content -LiteralPath $tmp -Encoding UTF8
        Move-Item -LiteralPath $tmp -Destination $path -Force
        return $true
    } catch {try{Write-YumLogException -Context 'Research cache save failed' -Exception $_.Exception}catch{};return $false}
}

function Clear-YumResearchCache {
    try {
        $path=Get-YumResearchCachePath
        if(Test-Path -LiteralPath $path){Remove-Item -LiteralPath $path -Force -ErrorAction Stop}
        return $true
    } catch {
        try { Write-YumLogException -Context 'Research cache clear failed' -Exception $_.Exception } catch {}
        return $false
    }
}

function Get-YumResearchKey {
    param([string]$Name,[string]$Path,[string]$Publisher,[string]$Product,[string]$Version,[string]$FileHash='', [string]$SignerThumbprint='')
    $text=('{0}|{1}|{2}|{3}|{4}|{5}|{6}' -f $Name,$Path,$Publisher,$Product,$Version,$FileHash,$SignerThumbprint).ToLowerInvariant()
    $sha=[Security.Cryptography.SHA256]::Create()
    try{return ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($text))).Replace('-','')).ToLowerInvariant()}finally{$sha.Dispose()}
}

function Get-YumResearchSignature {
    param([string]$Path)
    $filePath=Get-YumResearchExecutablePath -Path $Path
    if([string]::IsNullOrWhiteSpace($filePath)){return $null}
    try {
        $sig=Get-AuthenticodeSignature -FilePath $filePath -ErrorAction Stop
        return [pscustomobject]@{Status=[string]$sig.Status;Signer=if($null -ne $sig.SignerCertificate){[string]$sig.SignerCertificate.Subject}else{''};Thumbprint=if($null -ne $sig.SignerCertificate){[string]$sig.SignerCertificate.Thumbprint}else{''}}
    } catch { return $null }
}

function Get-YumStartupRows {
    param([int]$MaxItems=120,[System.Collections.Generic.List[string]]$ErrorSink=$null)
    $rows=New-Object System.Collections.Generic.List[object];$errors=New-Object System.Collections.Generic.List[string]
    $locations=@(
        @{Scope='Current User';Kind='Registry Run';Path='Registry::HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Run'},
        @{Scope='Current User';Kind='Registry RunOnce';Path='Registry::HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\RunOnce'},
        @{Scope='All Users';Kind='Registry Run';Path='Registry::HKEY_LOCAL_MACHINE\Software\Microsoft\Windows\CurrentVersion\Run'},
        @{Scope='All Users';Kind='Registry RunOnce';Path='Registry::HKEY_LOCAL_MACHINE\Software\Microsoft\Windows\CurrentVersion\RunOnce'},
        @{Scope='Current User';Kind='Startup Folder';Path=[Environment]::GetFolderPath('Startup')},
        @{Scope='All Users';Kind='Startup Folder';Path=[Environment]::GetFolderPath('CommonStartup')}
    )
    foreach($loc in $locations){
        if($rows.Count -ge $MaxItems){break}
        try {
            if($loc.Kind -like 'Registry*'){
                if(-not(Test-Path -LiteralPath $loc.Path)){continue}
                $item=Get-ItemProperty -LiteralPath $loc.Path -ErrorAction Stop
                foreach($prop in $item.PSObject.Properties){
                    if($prop.Name -like 'PS*' -or $rows.Count -ge $MaxItems){continue}
                    $command=[string]$prop.Value
                    $name=[string]$prop.Name
                    $risk='Review';$category='Startup App';$reason='Startup command requires identity review';$confidence=60
                    if($command -match '(?i)\\(windows|system32)\\' -or $name -match '(?i)security|defender|antivirus'){ $risk='Protected';$category='Security / System';$reason='System/security startup indicator';$confidence=90 }
                    elseif($command -match '(?i)steam|epic|riot|ubisoft|battle\.net|ea|xbox|game'){ $risk='Protected';$category='Game / Launcher';$reason='Gaming startup indicator; protect from automatic management';$confidence=90 }
                    [void]$rows.Add([pscustomobject]@{Source='Startup';Name=$name;Command=$command;Scope=$loc.Scope;Kind=$loc.Kind;Path=$command;Publisher='Unknown';Category=$category;Risk=$risk;Confidence=$confidence;Reason=$reason;Placement='Startup Inventory';Recommendation=if($risk -eq 'Protected'){'Protect; do not manage automatically'}else{'Review before startup changes'};LastSeen=(Get-Date).ToString('o')})
                }
            } else {
                if(-not(Test-Path -LiteralPath $loc.Path)){continue}
                foreach($file in @(Get-ChildItem -LiteralPath $loc.Path -File -ErrorAction SilentlyContinue | Select-Object -First ($MaxItems-$rows.Count))){
                    $ext=$file.Extension.ToLowerInvariant();$risk=if($ext -in @('.exe','.lnk','.cmd','.bat')){'Review'}else{'Unknown'}
                    $reason=if($ext -eq '.lnk'){'Startup shortcut requires target identity review'}else{'Startup file requires identity review'}
                    [void]$rows.Add([pscustomobject]@{Source='Startup';Name=$file.Name;Command=$file.FullName;Scope=$loc.Scope;Kind=$loc.Kind;Path=$file.FullName;Publisher='Unknown';Category='Startup App';Risk=$risk;Confidence=if($risk -eq 'Review'){55}else{30};Reason=$reason;Placement='Startup Inventory';Recommendation='Review before startup changes';LastSeen=(Get-Date).ToString('o')})
                }
            }
        } catch { if($errors.Count -lt 15){[void]$errors.Add(('{0}: {1}' -f $loc.Kind,$_.Exception.Message))} }
    }
    if($null -ne $ErrorSink){foreach($e in $errors){[void]$ErrorSink.Add([string]$e)}}
    return $rows.ToArray()
}

function Convert-YumResearchText {
    # 5.4: HashSet de-duplication. 'Select-Object -Unique' is quadratic in Windows PowerShell 5.1 and took
    # over a minute on a single vendor web page once online verification started working.
    param([AllowNull()][string]$Text)
    if([string]::IsNullOrWhiteSpace($Text)){ return @() }
    $clean=($Text.ToLowerInvariant() -replace '[^a-z0-9\._+-]+',' ').Trim()
    if([string]::IsNullOrWhiteSpace($clean)){ return @() }
    $set=New-Object 'System.Collections.Generic.HashSet[string]'
    $ordered=New-Object System.Collections.Generic.List[string]
    foreach($tok in $clean.Split(' ',[StringSplitOptions]::RemoveEmptyEntries)){ if($tok.Length -ge 2 -and $set.Add($tok)){ $ordered.Add($tok) } }
    $ordered.ToArray()   # callers wrap in @(); a leading comma here would nest the array
}

function Get-YumResearchTokenOverlap {
    param([string]$Left,[string]$Right)
    # Only the left (identity) side needs to be a list; the right side is looked up in a HashSet.
    if($null -ne $Right -and $Right.Length -gt 300000){ $Right=$Right.Substring(0,300000) }  # page head carries the identity
    $a=@(Convert-YumResearchText $Left)
    if($a.Count -eq 0 -or [string]::IsNullOrWhiteSpace($Right)){return 0}
    # ::new, not New-Object: New-Object spreads an array argument into separate constructor arguments.
    $b=[System.Collections.Generic.HashSet[string]]::new([string[]]@(Convert-YumResearchText $Right))
    if($b.Count -eq 0){return 0}
    $hits=0
    foreach($t in $a){ if($b.Contains($t)){$hits++} }
    [int][math]::Round(($hits / [double]$a.Count) * 100,0)
}

function Get-YumResearchExecutablePath {
    param([string]$Path)
    if([string]::IsNullOrWhiteSpace($Path)){return ''}
    try {
        $expanded=[Environment]::ExpandEnvironmentVariables([string]$Path).Trim()
        if($expanded.IndexOfAny([IO.Path]::GetInvalidPathChars()) -lt 0){
            try{if(Test-Path -LiteralPath $expanded -PathType Leaf){return $expanded}}catch{}
        }
        # Windows service/startup BinaryPathName values may contain an executable plus arguments.
        # Extract only the executable token before any argument text; never pass the full command
        # line to Test-Path/Get-Item/Get-AuthenticodeSignature. Microsoft documents that service
        # BinaryPathName may legitimately include arguments.
        if($expanded -match '^\s*"([^"]+\.(?:exe|com|sys))"(?:\s|$)'){
            $candidate=$Matches[1]
            if(Test-Path -LiteralPath $candidate -PathType Leaf){return $candidate}
        }
        if($expanded -match '^\s*([A-Za-z]:\\.*?\.(?:exe|com|sys))(?:\s|$)'){
            $candidate=$Matches[1]
            if(Test-Path -LiteralPath $candidate -PathType Leaf){return $candidate}
        }
        if($expanded -match '^(?:\\SystemRoot|SystemRoot)(\\[^\s]+\.(?:exe|com|sys))'){
            $candidate=Join-Path $env:windir ($Matches[1].TrimStart('\'))
            if(Test-Path -LiteralPath $candidate -PathType Leaf){return $candidate}
        }
        return ''
    }catch{return ''}
}
function Get-YumResearchParentFolderEvidence {
    param([string]$Path)
    $exe=Get-YumResearchExecutablePath -Path $Path
    if([string]::IsNullOrWhiteSpace($exe)){return $null}
    try{$item=Get-Item -LiteralPath $exe -ErrorAction Stop;$dir=$item.Directory;$hash='';try{$hash=(Get-FileHash -LiteralPath $exe -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant()}catch{};[pscustomobject]@{ExecutablePath=$item.FullName;FolderPath=[string]$dir.FullName;FolderName=[string]$dir.Name;Company=[string]$item.VersionInfo.CompanyName;Product=[string]$item.VersionInfo.ProductName;Version=[string]$item.VersionInfo.ProductVersion;FileHash=$hash}}catch{return $null}
}
function Test-YumResearchHasDurableIdentity {
    param([string]$Name,[string]$Path,[string]$Publisher,[string]$Product,[object]$FileEvidence=$null,[object]$SignatureEvidence=$null,[object[]]$ServiceEvidence=@())
    $exe=Get-YumResearchExecutablePath -Path $Path
    if($FileEvidence -and (-not [string]::IsNullOrWhiteSpace([string]$FileEvidence.Hash) -or -not [string]::IsNullOrWhiteSpace([string]$FileEvidence.Product) -or -not [string]::IsNullOrWhiteSpace([string]$FileEvidence.Company))){return $true}
    if($SignatureEvidence -and -not [string]::IsNullOrWhiteSpace([string]$SignatureEvidence.Thumbprint)){return $true}
    if(-not [string]::IsNullOrWhiteSpace($Publisher) -and $Publisher -ne 'Unknown'){return $true}
    if(-not [string]::IsNullOrWhiteSpace($Product)){return $true}
    if(-not [string]::IsNullOrWhiteSpace($exe)){return $true}
    if(@($ServiceEvidence|Where-Object{-not [string]::IsNullOrWhiteSpace([string]$_.PathName)}).Count -gt 0){return $true}
    return $false
}

function Get-YumResearchFileEvidence {
    param([string]$Path)
    $filePath=Get-YumResearchExecutablePath -Path $Path
    if([string]::IsNullOrWhiteSpace($filePath)){return $null}
    try {
        $item=Get-Item -LiteralPath $filePath -ErrorAction Stop
        $versionInfo=$item.VersionInfo
        $hash=''
        try{$hash=(Get-FileHash -LiteralPath $filePath -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant()}catch{}
        [pscustomobject]@{FileVersion=[string]$versionInfo.FileVersion;Product=[string]$versionInfo.ProductName;Company=[string]$versionInfo.CompanyName;Description=[string]$versionInfo.FileDescription;Hash=$hash}
    } catch {return $null}
}




function Get-YumInstalledSoftwareResearch {
    param([string]$Name,[string]$Publisher='',[string]$Path='')
    if($null -eq $script:YumResearchRegistryInventory){
        $script:YumResearchRegistryInventory=New-Object System.Collections.Generic.List[object]
        $paths=@(
          'Registry::HKEY_LOCAL_MACHINE\Software\Microsoft\Windows\CurrentVersion\Uninstall\*',
          'Registry::HKEY_LOCAL_MACHINE\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
          'Registry::HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Uninstall\*'
        )
        foreach($p in $paths){try{foreach($item in @(Get-ItemProperty -Path $p -ErrorAction SilentlyContinue)){
            $dn=[string]$item.DisplayName;if([string]::IsNullOrWhiteSpace($dn)){continue}
            [void]$script:YumResearchRegistryInventory.Add([pscustomobject]@{Name=$dn;Version=[string]$item.DisplayVersion;Publisher=[string]$item.Publisher;InstallLocation=[string]$item.InstallLocation;DisplayIcon=[string]$item.DisplayIcon;UninstallString=[string]$item.UninstallString;CandidateExes=@(@([string]$item.InstallLocation,[string]$item.DisplayIcon,[string]$item.UninstallString)|Where-Object{$_}|ForEach-Object{$x=Get-YumResearchExecutablePath -Path $_;if($x){$x.ToLowerInvariant()}else{''}})})  # 5.4: resolved once per run
        }}catch{}}
    }
    $rows=New-Object System.Collections.Generic.List[object]
    $targetExe=Get-YumResearchExecutablePath -Path $Path
    $targetFull=if($targetExe){$targetExe.ToLowerInvariant()}else{''}
    $targetDir='';if($targetExe){try{$targetDir=(Split-Path -Parent $targetExe).ToLowerInvariant()}catch{}}
    $nameNorm=([string]$Name).Trim();$publisherNorm=([string]$Publisher).Trim()
    foreach($item in $script:YumResearchRegistryInventory.ToArray()){
        $pathScore=0
        foreach($cNorm in @($item.CandidateExes)){
            if($targetFull -and $cNorm -and $cNorm -eq $targetFull){$pathScore=[math]::Max($pathScore,100)}
            elseif($targetDir -and $item.InstallLocation -and $targetDir.StartsWith(([string]$item.InstallLocation).TrimEnd('\').ToLowerInvariant())){$pathScore=[math]::Max($pathScore,85)}
            elseif($targetDir -and $cNorm -and (Split-Path -Parent $cNorm) -eq $targetDir){$pathScore=[math]::Max($pathScore,80)}
        }
        $nScore=if($nameNorm){Get-YumResearchTokenOverlap -Left $nameNorm -Right $item.Name}else{0}
        $pScore=if($publisherNorm){Get-YumResearchTokenOverlap -Left $publisherNorm -Right $item.Publisher}else{0}
        $score=[int][math]::Min(100,$pathScore+($nScore*0.45)+($pScore*0.20)+5)
        if($score -ge 35){[void]$rows.Add([pscustomobject]@{Name=$item.Name;Version=$item.Version;Publisher=$item.Publisher;InstallLocation=$item.InstallLocation;DisplayIcon=$item.DisplayIcon;UninstallString=$item.UninstallString;Score=$score;NameOverlap=$nScore;PublisherOverlap=$pScore;PathMatchScore=$pathScore;Source='Windows Registry';ExactPathMatch=($pathScore -ge 100);ParentFolderMatch=($pathScore -ge 80)})}
    }
    @($rows|Sort-Object Score,PathMatchScore,NameOverlap -Descending|Select-Object -First 8)
}
function Get-YumWinGetInventory {
    # 5.4: one 'winget list' per research run (~2.5 s for ~200 programs) instead of one winget.exe
    # process per researched item (~3.5 s each). Parsed from the fixed-width table by header columns.
    # Get-Variable instead of a direct read: under StrictMode an unset script variable throws, which the
    # caller's try/catch turned into "no WinGet evidence" without any error.
    $existing=Get-Variable -Scope Script -Name YumResearchWinGetInventory -ValueOnly -ErrorAction SilentlyContinue
    if($null -ne $existing){return ,$existing}
    $inv=New-Object System.Collections.Generic.List[object]
    $script:YumResearchWinGetInventory=$inv
    try {
        $cmd=Get-Command winget.exe -ErrorAction SilentlyContinue
        if($null -eq $cmd){return ,$inv}
        # Capture raw lines; Out-String would re-wrap the wide table to the console width and break the columns.
        $lines=@(& $cmd.Source list --accept-source-agreements --disable-interactivity 2>$null | ForEach-Object { ([string]$_ -split "`r")[-1] })
        $h=-1;for($i=0;$i -lt $lines.Count;$i++){if($lines[$i] -match '^\s*Name\s+Id\s+Version'){$h=$i;break}}
        if($h -lt 0){return ,$inv}
        $header=$lines[$h] -replace '^.*?(Name\s)','$1'
        $offset=$lines[$h].Length-$header.Length
        $colId=$header.IndexOf('Id ');$colVer=$header.IndexOf('Version');$colSrc=$header.IndexOf('Source')
        foreach($line in $lines[($h+2)..($lines.Count-1)]){
            if($line.Length -lt $offset+$colVer -or $line -notmatch '\S'){continue}
            $l=$line.Substring($offset)
            # End position [int]::MaxValue = "to end of line" (a bare -1 argument is ambiguous in command mode).
            $cut={param([int]$a,[int]$b) if($l.Length -le $a){''}elseif($l.Length -le $b){$l.Substring($a).Trim()}else{$l.Substring($a,[math]::Max(0,$b-$a)).Trim()}}
            $n=(& $cut 0 $colId) -replace '…$',''
            if([string]::IsNullOrWhiteSpace($n)){continue}
            [void]$inv.Add([pscustomobject]@{Name=$n;Truncated=((& $cut 0 $colId) -match '…$');Id=(& $cut $colId $colVer);Version=(& $cut $colVer $(if($colSrc -gt 0){$colSrc}else{[int]::MaxValue}));SourceName=$(if($colSrc -gt 0){& $cut $colSrc ([int]::MaxValue)}else{''})})
        }
    } catch {}
    return ,$inv
}

function Get-YumWinGetResearch {
    param([string]$Name,[string]$Publisher='')
    try {
        $safeName=($Name -replace '[\r\n\t]',' ').Trim()
        if([string]::IsNullOrWhiteSpace($safeName)){return $null}
        $inv=Get-YumWinGetInventory
        if($inv.Count -eq 0){return $null}
        $best=$null;$bestScore=-1;$exact=$false
        foreach($e in $inv.ToArray()){
            $isExact=($e.Name -ieq $safeName) -or ($e.Truncated -and $safeName.StartsWith($e.Name,[StringComparison]::OrdinalIgnoreCase))
            $s=if($isExact){100}else{Get-YumResearchTokenOverlap -Left $safeName -Right ($e.Name+' '+$e.Id)}
            if($isExact){$best=$e;$bestScore=100;$exact=$true;break}  # an exact name always wins over a token overlap of 100
            if($s -gt $bestScore){$best=$e;$bestScore=$s}
        }
        if($null -eq $best -or $bestScore -lt 30){return $null}
        $publisherScore=if([string]::IsNullOrWhiteSpace($Publisher)){0}else{Get-YumResearchTokenOverlap -Left $Publisher -Right ($best.Name+' '+$best.Id)}
        $match=[int][math]::Round(($bestScore*0.7)+($publisherScore*0.3),0)
        if($exact){$match=[math]::Min(100,$match+15)}
        [pscustomobject]@{Source='WinGet Local Catalog';Text=('{0} | {1} | {2}' -f $best.Name,$best.Id,$best.Version);Name=$best.Name;Id=$best.Id;Version=$best.Version;Publisher='';SourceName=$best.SourceName;MatchScore=$match;ExactName=[bool]$exact}
    } catch { return $null }
}

function Get-YumAppxResearch {
    param([string]$Name,[string]$Publisher='',[string]$Path='')
    if($null -eq $script:YumResearchAppxInventory){
        $script:YumResearchAppxInventory=New-Object System.Collections.Generic.List[object]
        $pkgs=@();try{$pkgs=@(Get-AppxPackage -AllUsers -ErrorAction Stop)}catch{try{$pkgs=@(Get-AppxPackage -ErrorAction Stop)}catch{}}  # -AllUsers needs admin
        foreach($pkg in $pkgs){[void]$script:YumResearchAppxInventory.Add([pscustomobject]@{Name=[string]$pkg.Name;PackageFullName=[string]$pkg.PackageFullName;Publisher=[string]$pkg.Publisher;Version=[string]$pkg.Version;InstallLocation=[string]$pkg.InstallLocation;SignatureKind=[string]$pkg.SignatureKind})}
    }
    $rows=New-Object System.Collections.Generic.List[object]
    $targetExe=Get-YumResearchExecutablePath -Path $Path;$targetDir='';if($targetExe){try{$targetDir=(Split-Path -Parent $targetExe).ToLowerInvariant()}catch{}}
    $nameNorm=([string]$Name).Trim()
    foreach($pkg in $script:YumResearchAppxInventory.ToArray()){
        $n=if($nameNorm){Get-YumResearchTokenOverlap -Left $nameNorm -Right ($pkg.Name+' '+$pkg.PackageFullName)}else{0};$p=if($Publisher){Get-YumResearchTokenOverlap -Left $Publisher -Right $pkg.Publisher}else{0}
        $pathScore=0;if($targetDir -and $pkg.InstallLocation -and $targetDir.StartsWith($pkg.InstallLocation.TrimEnd('\').ToLowerInvariant())){$pathScore=100}
        # 5.4: an exact package identity in Windows' own package store is definitive (Store packages have
        # no .exe path, so the name/publisher blend alone capped them at ~60 and they stayed Unknown).
        $exactPackage=($nameNorm -and ($pkg.Name -ieq $nameNorm -or $pkg.PackageFullName -ieq $nameNorm -or $pkg.PackageFullName -ieq ([string]$Path).Trim()))
        $score=if($exactPackage){100}else{[int][math]::Min(100,$pathScore+($n*0.45)+($p*0.15))}
        if($score -ge 35){[void]$rows.Add([pscustomobject]@{Name=$pkg.Name;PackageFullName=$pkg.PackageFullName;Publisher=$pkg.Publisher;Version=$pkg.Version;InstallLocation=$pkg.InstallLocation;SignatureKind=$pkg.SignatureKind;ExactPackage=[bool]$exactPackage;Score=$score;NameOverlap=$n;PublisherOverlap=$p;PathMatchScore=$pathScore;Source='AppX';ExactPathMatch=($pathScore -ge 100)})}
    }
    @($rows|Sort-Object Score,PathMatchScore,NameOverlap -Descending|Select-Object -First 8)
}
function Get-YumResearchHistoryPath {
    if($null -ne $script:Yum -and $script:Yum.ConfigDirectory){return (Join-Path $script:Yum.ConfigDirectory 'research-history.json')}
    return (Join-Path $script:Yum.Root 'research-history.json')
}
function Add-YumResearchHistory {
    param([string]$Key,[string]$Name,[string]$Stage,[string]$Message='', [int]$Confidence=0,[string]$Placement='',[string]$Error='')
    try {
        $path=Get-YumResearchHistoryPath; $dir=Split-Path -Parent $path
        if(-not(Test-Path -LiteralPath $dir)){New-Item -ItemType Directory -Path $dir -Force|Out-Null}
        $db=@{}
        if(Test-Path -LiteralPath $path){
            try {
                $raw=Get-Content -LiteralPath $path -Raw -ErrorAction Stop
                if($raw){
                    $obj=$raw|ConvertFrom-Json -ErrorAction Stop
                    $items=$null
                    if($null -ne $obj.PSObject.Properties['Items']){$items=$obj.Items}else{$items=$obj}
                    if($items -is [hashtable]){
                        foreach($prop in $items.Keys){
                            if([string]$prop -in @('Version','Updated','Items')){continue}
                            $db[[string]$prop]=@($items[$prop])
                        }
                    } else {
                        foreach($prop in @($items.PSObject.Properties)){
                            if([string]$prop.Name -in @('Version','Updated','Items')){continue}
                            $db[[string]$prop.Name]=@($prop.Value)
                        }
                    }
                }
            } catch {}
        }
        if(-not $db.ContainsKey($Key)){$db[$Key]=@()}
        $db[$Key]=@($db[$Key]+[pscustomobject]@{Time=(Get-Date).ToString('o');Name=$Name;Stage=$Stage;Message=$Message;Confidence=$Confidence;Placement=$Placement;Error=$Error})
        if($db[$Key].Count -gt 12){$db[$Key]=@($db[$Key]|Select-Object -Last 12)}
        $tmp="$path.tmp"; [ordered]@{Version='1';Updated=(Get-Date).ToString('o');Items=$db}|ConvertTo-Json -Depth 10|Set-Content -LiteralPath $tmp -Encoding UTF8; Move-Item -LiteralPath $tmp -Destination $path -Force
    } catch {}
}

function Test-YumKnownSystemIdentity {
    param([string]$Name)
    $n=([string]$Name).Trim().ToLowerInvariant()
    return $n -in @('memory compression','system','system idle process','registry','smss','csrss','wininit','services','lsass','winlogon','svchost','fontdrvhost','dwm','secure system','system interrupts')
}

function Test-YumResearchIdentityAnchor {
    param([string]$Name,[string]$Path,[string]$Publisher,[string]$Product,[object]$FileEvidence=$null,[object]$SignatureEvidence=$null,[object[]]$RegistryEvidence=@(),[object]$WingetEvidence=$null,[object[]]$AppxEvidence=@(),[object[]]$ServiceEvidence=@())
    $normalizedPath=Get-YumResearchExecutablePath -Path $Path
    $hasPath=-not [string]::IsNullOrWhiteSpace($normalizedPath)
    $hasFile=$null -ne $FileEvidence -and (-not [string]::IsNullOrWhiteSpace([string]$FileEvidence.Hash) -or -not [string]::IsNullOrWhiteSpace([string]$FileEvidence.Product) -or -not [string]::IsNullOrWhiteSpace([string]$FileEvidence.Company))
    $hasSigner=$null -ne $SignatureEvidence -and [string]$SignatureEvidence.Status -eq 'Valid' -and -not [string]::IsNullOrWhiteSpace([string]$SignatureEvidence.Thumbprint)
    $hasPublisher=-not [string]::IsNullOrWhiteSpace($Publisher)
    $hasProduct=-not [string]::IsNullOrWhiteSpace($Product)
    $strongRegistry=@($RegistryEvidence|Where-Object{[int]$_.Score -ge 60}).Count -gt 0
    $strongWinget=$null -ne $WingetEvidence -and [bool]$WingetEvidence.ExactName -and [int]$WingetEvidence.MatchScore -ge 75
    $strongAppx=@($AppxEvidence|Where-Object{[int]$_.Score -ge 75}).Count -gt 0
    $strongService=@($ServiceEvidence|Where-Object{[int]$_.Score -ge 70}).Count -gt 0
    return ($hasPath -or $hasFile -or $hasSigner -or ($hasPublisher -and ($hasProduct -or $hasFile)) -or $strongRegistry -or $strongWinget -or $strongAppx -or $strongService)
}

function Get-YumResearchSourceTrust {
    # 5.4: was "$host = ...": $host is read-only in PowerShell, so this function always hit its catch and
    # returned 0. No online source was ever trusted, so online verification never succeeded.
    param([string]$Url,[string]$Publisher='')
    try {
        $u=[Uri]$Url
        if($u.Scheme -notin @('http','https')){return 0}
        $urlHost=$u.Host.ToLowerInvariant().TrimEnd('.')
        if([string]::IsNullOrWhiteSpace($urlHost)){return 0}
        # Search engines are discovery only; never count their result pages as authoritative evidence.
        if($urlHost -eq 'bing.com' -or $urlHost.EndsWith('.bing.com') -or $urlHost -eq 'search.yahoo.com' -or $urlHost.EndsWith('.search.yahoo.com') -or $urlHost -eq 'duckduckgo.com' -or $urlHost.EndsWith('.duckduckgo.com') -or $urlHost -eq 'yandex.com' -or $urlHost.EndsWith('.yandex.com') -or $urlHost -eq 'baidu.com' -or $urlHost.EndsWith('.baidu.com')){return 0}
        if($urlHost -in @('google.com','www.google.com') -and $u.AbsolutePath -match '^/(?:$|/$|search|webhp|url)'){return 0}
        $authoritative=@(
            'microsoft.com','learn.microsoft.com','support.microsoft.com',
            'github.com','githubusercontent.com','nvidia.com','amd.com','intel.com',
            'apple.com','google.com','mozilla.org','adobe.com','oracle.com',
            'redhat.com','canonical.com','docker.com','valvesoftware.com',
            'steampowered.com','epicgames.com','riotgames.com','ubisoft.com',
            'ea.com','blizzard.com','xbox.com','playstation.com','cisco.com',
            'cloudflare.com','vmware.com','paloaltonetworks.com','crowdstrike.com',
            'sentinelone.com','eset.com','bitdefender.com','malwarebytes.com','sophos.com'
        )
        foreach($d in $authoritative){ if($urlHost -eq $d -or $urlHost.EndsWith('.'+$d)){return 96} }
        # 5.4: the publisher's own site (e.g. logitechg.com for 'Logitech') is authoritative for its products.
        if(-not [string]::IsNullOrWhiteSpace($Publisher)){
            $site=($urlHost -replace '^(www|m|en)\.','') -split '\.' | Select-Object -First 1
            foreach($tok in @(([string]$Publisher).ToLowerInvariant() -split '[^a-z0-9]+' | Where-Object { $_.Length -ge 4 -and $_ -notin @('corporation','company','incorporated','limited','software','technologies','technology','systems','group','games','studio','studios') })){
                if($site.StartsWith($tok) -or ($tok.Length -ge 5 -and $site.Contains($tok))){return 88}
            }
        }
        if($urlHost -match '(^|\.)gov(\.[a-z]{2})?$'){return 92}
        if($urlHost -match '(^|\.)edu(\.[a-z]{2})?$|(^|\.)ac\.[a-z]{2}$'){return 82}
        if($urlHost -match '(^|\.)org$'){return 55}
        if($urlHost -match '(^|\.)com$'){return 42}
        if($urlHost -match '(^|\.)net$'){return 30}
        return 15
    } catch { return 0 }
}

function Get-YumOnlineResearch {
    param([string]$Name,[string]$Publisher,[string]$Product)
    $empty=[pscustomobject]@{Success=$false;Disabled=$false;Error='';BestScore=0;Results=@();Titles=@();Links=@();VerifiedLinks=@();VerifiedCount=0;GitHubCount=0;RedditCount=0;CommunityContext=@()}
    if($null -eq $script:Yum.Config -or -not [bool]$script:Yum.Config.EnableOnlineResearch){$empty.Disabled=$true;$empty.Error='Online research disabled';return $empty}
    try {
        $provider=Get-YumResearchOnlineProvider
        if($null -ne $provider){
            $provided=Invoke-YumResearchOnlineProvider -Provider $provider -Name $Name -Publisher $Publisher -Product $Product
            if($null -eq $provided){throw 'Configured OnlineResearchProvider returned no result.'}
            # Normalize injected results to the same contract used by the real web adapter.
            $bestScore=0;try{$bestScore=[int](Get-YumResearchSafeProperty -Object $provided -Name 'BestScore' -Default 0)}catch{}
            $verifiedLinks=@(Get-YumResearchSafeProperty -Object $provided -Name 'VerifiedLinks' -Default @())
            $results=@(Get-YumResearchSafeProperty -Object $provided -Name 'Results' -Default @())
            $titles=@(Get-YumResearchSafeProperty -Object $provided -Name 'Titles' -Default @())
            $links=@(Get-YumResearchSafeProperty -Object $provided -Name 'Links' -Default @())
            $community=@(Get-YumResearchSafeProperty -Object $provided -Name 'CommunityContext' -Default @())
            if($titles.Count -eq 0){$titles=@($results|ForEach-Object{Get-YumResearchSafeProperty -Object $_ -Name 'Title' -Default ''}|Where-Object{$_})}
            if($links.Count -eq 0){$links=@($results|ForEach-Object{Get-YumResearchSafeProperty -Object $_ -Name 'Link' -Default ''}|Where-Object{$_})}
            $verifiedCount=0;try{$verifiedCount=[int](Get-YumResearchSafeProperty -Object $provided -Name 'VerifiedCount' -Default $verifiedLinks.Count)}catch{ $verifiedCount=$verifiedLinks.Count }
            $githubCount=0;try{$githubCount=[int](Get-YumResearchSafeProperty -Object $provided -Name 'GitHubCount' -Default 0)}catch{}
            $redditCount=0;try{$redditCount=[int](Get-YumResearchSafeProperty -Object $provided -Name 'RedditCount' -Default 0)}catch{}
            $success=$true;try{$success=[bool](Get-YumResearchSafeProperty -Object $provided -Name 'Success' -Default $true)}catch{}
            $errorText='';try{$errorText=[string](Get-YumResearchSafeProperty -Object $provided -Name 'Error' -Default '')}catch{}
            return [pscustomobject]@{Success=$success;Disabled=$false;Error=$errorText;Query=($Name);Results=$results;BestScore=$bestScore;Titles=$titles;Links=$links;VerifiedLinks=$verifiedLinks;VerifiedCount=$verifiedCount;GitHubCount=$githubCount;RedditCount=$redditCount;CommunityContext=$community;ResearchedAt=(Get-Date).ToString('o');Provider='Injected'}
        }
        $identity=@(@($Publisher,$Product,$Name)|Where-Object{ -not [string]::IsNullOrWhiteSpace($_)}|ForEach-Object{$_.Trim()}|Select-Object -Unique)
        if($identity.Count -eq 0){$empty.Success=$true;$empty.Error='No searchable identity terms';return $empty}
        $version='';try{$version=[string]$script:Yum.Config.Version}catch{}
        $timeout=[int]$script:Yum.Config.ResearchRequestTimeoutSeconds
        $queries=@(
            @{Kind='Authority';Query=(($identity -join ' ')+' official software')},
            @{Kind='GitHub';Query=(('site:github.com '+($identity -join ' ')+' repository'))},
            @{Kind='Reddit';Query=(('site:reddit.com '+($identity -join ' ')+' Windows'))}
        )
        $results=New-Object System.Collections.Generic.List[object]
        # 5.4: start all three searches at once and wait for them together (was strictly sequential,
        # up to 3 x timeout per item).
        $pending=New-Object System.Collections.Generic.List[object]
        foreach($qdef in $queries){
            try{
                $q=[Uri]::EscapeDataString([string]$qdef.Query)
                $wc=New-Object Net.WebClient
                $wc.Headers['User-Agent']="YUMRAM/$version"
                $wc.Encoding=[Text.Encoding]::UTF8
                [void]$pending.Add([pscustomobject]@{Def=$qdef;Client=$wc;Task=$wc.DownloadStringTaskAsync("https://www.bing.com/search?q=$q&format=rss")})
            }catch{}
        }
        $deadline=[DateTime]::UtcNow.AddMilliseconds([math]::Max(1000,$timeout*1000))
        foreach($pq in $pending.ToArray()){
            $qdef=$pq.Def
            try{
                $left=[int][math]::Max(0,($deadline-[DateTime]::UtcNow).TotalMilliseconds)
                if(-not $pq.Task.Wait($left)){continue}
                $xml=[xml]$pq.Task.Result
                foreach($item in @($xml.rss.channel.item|Select-Object -First 5)){
                    $title=[string]$item.title;$description=[string]$item.description;$link=[string]$item.link;$text=($title+' '+$description).Trim()
                    $n=if($Name){Get-YumResearchTokenOverlap -Left $Name -Right $text}else{0}
                    $p=if($Publisher){Get-YumResearchTokenOverlap -Left $Publisher -Right $text}else{0}
                    $pr=if($Product){Get-YumResearchTokenOverlap -Left $Product -Right $text}else{0}
                    $match=[int][math]::Round(($n*0.45)+($p*0.30)+($pr*0.25),0)
                    $trust=Get-YumResearchSourceTrust -Url $link -Publisher $Publisher
                    # 5.4: was '$host', which is PowerShell's read-only automatic variable, so the
                    # assignment silently failed and GitHub/Reddit results were never recognized.
                    $linkHost='';try{$linkHost=([Uri]$link).Host.ToLowerInvariant()}catch{}
                    # Label by the real site: Bing RSS ignores 'site:' so every query returns similar pages.
                    $lane=if($linkHost -match '(^|\.)github\.com$'){'GitHub'}elseif($linkHost -match '(^|\.)reddit\.com$'){'Reddit'}else{'Authority'}
                    [void]$results.Add([pscustomobject]@{Lane=$lane;Title=$title;Description=$description;Link=$link;MatchScore=$match;SourceTrust=$trust;Verified=$false;VerifiedScore=0})
                }
            }catch{}
        }
        foreach($pq in $pending.ToArray()){try{$pq.Client.Dispose()}catch{}}
        $dedup=@($results|Where-Object{$_.Link}|Group-Object Link|ForEach-Object{$_.Group|Sort-Object MatchScore -Descending|Select-Object -First 1})
        $verify=@($dedup|Where-Object{$_.Lane -ne 'Reddit' -and $_.SourceTrust -ge 80}|Sort-Object MatchScore -Descending|Select-Object -First 4)
        $verified=New-Object System.Collections.Generic.List[string];$community=New-Object System.Collections.Generic.List[object];$verifiedCount=0
        # 5.4: fetch the candidate pages in parallel (was one Invoke-WebRequest after another).
        $fetches=New-Object System.Collections.Generic.List[object]
        foreach($result in $verify){
            try{$wc=New-Object Net.WebClient;$wc.Headers['User-Agent']="YUMRAM/$version";$wc.Encoding=[Text.Encoding]::UTF8;[void]$fetches.Add([pscustomobject]@{Result=$result;Client=$wc;Task=$wc.DownloadStringTaskAsync([string]$result.Link)})}catch{}
        }
        $deadline=[DateTime]::UtcNow.AddMilliseconds([math]::Max(2000,$timeout*1000))
        foreach($f in $fetches.ToArray()){
            $result=$f.Result
            try{
                $left=[int][math]::Max(0,($deadline-[DateTime]::UtcNow).TotalMilliseconds)
                if(-not $f.Task.Wait($left)){continue}
                $content=[string]$f.Task.Result
                $m=[regex]::Match($content,'(?is)<title[^>]*>(.*?)</title>');$pageTitle='';if($m.Success){$pageTitle=[System.Net.WebUtility]::HtmlDecode(($m.Groups[1].Value -replace '<[^>]+>',' '))}
                $body=(($pageTitle+' '+$content)-replace '\s+',' ')
                $n=if($Name){Get-YumResearchTokenOverlap -Left $Name -Right $body}else{0}
                $p=if($Publisher){Get-YumResearchTokenOverlap -Left $Publisher -Right $body}else{0}
                $pr=if($Product){Get-YumResearchTokenOverlap -Left $Product -Right $body}else{0}
                $githubBoost=if($result.Lane -eq 'GitHub' -and ($body -match '(?i)README|release|repository') -and ($n -ge 50 -or $p -ge 50 -or $pr -ge 60)){10}else{0}
                $vScore=[int][math]::Min(100,[math]::Round((($n*0.45)+($p*0.30)+($pr*0.25))*0.9 + ($result.SourceTrust*0.1) + $githubBoost,0))
                $identityMatch=(($n -ge 65 -and $p -ge 55) -or ($n -ge 80 -and $pr -ge 60) -or ($p -ge 75 -and $pr -ge 65) -or ($result.Lane -eq 'GitHub' -and $n -ge 75 -and ($p -ge 50 -or $pr -ge 60)))
                if($result.SourceTrust -ge 80 -and $identityMatch -and $vScore -ge 55){$result.Verified=$true;$result.VerifiedScore=$vScore;$result.MatchScore=[math]::Max([int]$result.MatchScore,$vScore);$verifiedCount++;[void]$verified.Add([string]$result.Link)}
            }catch{}
        }
        foreach($f in $fetches.ToArray()){try{$f.Client.Dispose()}catch{}}
        foreach($r in @($dedup|Where-Object{$_.Lane -eq 'Reddit'}|Sort-Object MatchScore -Descending|Select-Object -First 3)){[void]$community.Add([pscustomobject]@{Title=$r.Title;Link=$r.Link;MatchScore=[int]$r.MatchScore;UseAsIdentityEvidence=$false})}
        $best=@($dedup|Sort-Object @{Expression={if($_.Verified){1}else{0}};Descending=$true},MatchScore -Descending)
        $officialBest=@($best|Where-Object{$_.Lane -ne 'Reddit'}|Select-Object -First 1)
        $bestScore=0
        if($officialBest.Count -gt 0){$bestScore=[int]$officialBest[0].MatchScore}
        # Convert generic collections explicitly. PowerShell 5.1 can throw
        # 'Argument types do not match' when a generic List is wrapped in @().
        $verifiedLinks=@($verified.ToArray())
        $communityContext=@($community.ToArray())
        [pscustomobject]@{
            Success=$true;Disabled=$false;Error='';Query=($identity -join ' ');Results=$best;BestScore=$bestScore;
            Titles=@($best|ForEach-Object{$_.Title}|Where-Object{$_});Links=@($best|ForEach-Object{$_.Link}|Where-Object{$_});VerifiedLinks=$verifiedLinks;
            VerifiedCount=$verifiedCount;Count=$best.Count;GitHubCount=@($dedup|Where-Object{$_.Lane -eq 'GitHub'}).Count;RedditCount=@($dedup|Where-Object{$_.Lane -eq 'Reddit'}).Count;
            CommunityContext=$communityContext;ResearchedAt=(Get-Date).ToString('o')
        }
    } catch { try{Write-YumLogException -Context 'Online research failed' -Exception $_.Exception}catch{}; $empty.Success=$false;$empty.Error=$_.Exception.Message;return $empty }
}

function Get-YumPathlessProcessIdentity {
    # 5.5: Windows hides the executable path of protected processes (audiodg, sppsvc, NVIDIA containers,
    # gaming services...) from programs that are not elevated, so these used to end up Unknown. Find the
    # binary another way and let Windows verify its signature:
    #   1. a Windows service whose executable has this name (any folder);
    #   2. a file with this name in System32 / the Windows folder.
    # Store-package binaries under WindowsApps that belong to Microsoft's package ID count as Microsoft.
    param([string]$Name)
    if([string]::IsNullOrWhiteSpace($Name)){return $null}
    try{[void](Get-YumServiceResearch -Name $Name)}catch{}
    $candidates=New-Object System.Collections.Generic.List[object]
    $inventory=if($null -ne $script:YumResearchServiceInventory){$script:YumResearchServiceInventory.ToArray()}else{@()}
    foreach($svc in $inventory){
        $exe=[string]$svc.ExePath
        if($exe -and [System.IO.Path]::GetFileNameWithoutExtension($exe) -ieq $Name){$candidates.Add([pscustomobject]@{Path=$exe;How=('service {0}' -f $svc.Name)})}
    }
    foreach($dir in @((Join-Path $env:SystemRoot 'System32'),$env:SystemRoot)){
        $f=Join-Path $dir ($Name+'.exe')
        if(Test-Path -LiteralPath $f){$candidates.Add([pscustomobject]@{Path=$f;How='Windows folder'})}
    }
    $seen=@{}
    foreach($c in $candidates){
        if($seen.ContainsKey($c.Path.ToLowerInvariant())){continue};$seen[$c.Path.ToLowerInvariant()]=$true
        $underWindows=($c.Path -match '(?i)^[a-z]:\\windows\\')
        if($c.Path -match '(?i)\\WindowsApps\\[^\\]+_(8wekyb3d8bbwe|cw5n1h2txyewy)\\'){return [pscustomobject]@{Path=$c.Path;Signer='Microsoft Corporation';Microsoft=$true;UnderWindows=$false;How=$c.How+', Microsoft Store package'}}
        try{
            $sig=Get-AuthenticodeSignature -LiteralPath $c.Path -ErrorAction Stop
            if([string]$sig.Status -eq 'Valid' -and $null -ne $sig.SignerCertificate){
                $subject=[string]$sig.SignerCertificate.Subject
                $org=if($subject -match 'O="([^"]+)"'){$Matches[1]}elseif($subject -match 'O=([^,]+)'){$Matches[1].Trim()}else{''}
                return [pscustomobject]@{Path=$c.Path;Signer=$org;Microsoft=($org -match '(?i)^Microsoft');UnderWindows=$underWindows;How=$c.How}
            }
        }catch{}
    }
    return $null
}

function Get-YumServiceResearch {
    param([string]$Name,[string]$Path='')
    if($null -eq $script:YumResearchServiceInventory){
        $script:YumResearchServiceInventory=New-Object System.Collections.Generic.List[object]
        try{foreach($svc in @(Get-CimInstance Win32_Service -ErrorAction Stop)){[void]$script:YumResearchServiceInventory.Add([pscustomobject]@{Name=[string]$svc.Name;DisplayName=[string]$svc.DisplayName;PathName=[string]$svc.PathName;StartMode=[string]$svc.StartMode;State=[string]$svc.State;ExePath=(Get-YumResearchExecutablePath -Path ([string]$svc.PathName))})}}catch{}  # 5.4: resolve each service's executable once per run
    }
    $rows=New-Object System.Collections.Generic.List[object]
    $targetExe=Get-YumResearchExecutablePath -Path $Path;$targetFull=if($targetExe){$targetExe.ToLowerInvariant()}else{''}
    foreach($svc in $script:YumResearchServiceInventory.ToArray()){
        $exe=[string]$svc.ExePath;$exeNorm=if($exe){$exe.ToLowerInvariant()}else{''}
        $nameScore=if($Name){Get-YumResearchTokenOverlap -Left $Name -Right ($svc.Name+' '+$svc.DisplayName)}else{0};$pathScore=0
        if($targetFull -and $exeNorm -and $targetFull -eq $exeNorm){$pathScore=100}elseif($targetFull -and $exeNorm -and (Split-Path -Parent $targetFull) -eq (Split-Path -Parent $exeNorm)){$pathScore=85}elseif($Path -and $svc.PathName -and $svc.PathName -like ('*'+$Name+'*')){$pathScore=45}
        $score=[int][math]::Max($nameScore,$pathScore)
        if($score -ge 30){$folder=Get-YumResearchParentFolderEvidence -Path $exe;[void]$rows.Add([pscustomobject]@{Name=$svc.Name;DisplayName=$svc.DisplayName;PathName=$svc.PathName;ExecutablePath=$exe;ParentFolder=if($folder){$folder.FolderPath}else{''};ParentFolderName=if($folder){$folder.FolderName}else{''};Company=if($folder){$folder.Company}else{''};Product=if($folder){$folder.Product}else{''};Version=if($folder){$folder.Version}else{''};FileHash=if($folder){$folder.FileHash}else{''};StartMode=$svc.StartMode;State=$svc.State;Score=$score;PathMatchScore=$pathScore;ExactPathMatch=($pathScore -ge 100)})}
    }
    @($rows|Sort-Object Score,PathMatchScore -Descending|Select-Object -First 8)
}
function Get-YumResearchEvidenceFingerprint {
    param([object]$FileEvidence,[object]$SignatureEvidence,[object[]]$RegistryEvidence=@(),[object]$WingetEvidence=$null,[object[]]$AppxEvidence=@(),[object]$OnlineEvidence=$null,[object[]]$ServiceEvidence=@())
    try {
        $parts=New-Object System.Collections.Generic.List[string]
        if($null -ne $FileEvidence){[void]$parts.Add(('file|{0}|{1}|{2}|{3}' -f [string]$FileEvidence.Hash,[string]$FileEvidence.FileVersion,[string]$FileEvidence.Company,[string]$FileEvidence.Product))}
        if($null -ne $SignatureEvidence){[void]$parts.Add(('sig|{0}|{1}' -f [string]$SignatureEvidence.Status,[string]$SignatureEvidence.Thumbprint))}
        foreach($r in @($RegistryEvidence)){[void]$parts.Add(('reg|{0}|{1}|{2}' -f [string]$r.Name,[string]$r.Publisher,[string]$r.Version))}
        if($null -ne $WingetEvidence){[void]$parts.Add(('winget|{0}|{1}|{2}|{3}' -f [string]$WingetEvidence.Name,[string]$WingetEvidence.Id,[string]$WingetEvidence.Version,[string]$WingetEvidence.Publisher))}
        foreach($a in @($AppxEvidence)){[void]$parts.Add(('appx|{0}|{1}|{2}|{3}' -f [string]$a.Name,[string]$a.PackageFullName,[string]$a.Version,[string]$a.Publisher))}
        foreach($s in @($ServiceEvidence)){[void]$parts.Add(('svc|{0}|{1}|{2}' -f [string]$s.Name,[string]$s.DisplayName,[string]$s.PathName))}
        if($null -ne $OnlineEvidence){foreach($r in @($OnlineEvidence.Results|Where-Object{[bool]$_.Verified}|Select-Object -First 3)){[void]$parts.Add(('web|{0}|{1}|{2}' -f [string]$r.Title,[string]$r.Link,[int]$r.VerifiedScore))}}
        $sha=[Security.Cryptography.SHA256]::Create();try{return ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes(($parts -join "`n")))).Replace('-','')).ToLowerInvariant()}finally{$sha.Dispose()}
    } catch { return '' }
}

function Get-YumResearchPlacement {
    param(
        [string]$Name,[string]$Path,[string]$Publisher,[string]$Product,[string]$Signature,
        [string]$Category,[string]$Risk,[string]$Reason,[object[]]$RegistryEvidence=@(),
        [object]$WingetEvidence=$null,[object[]]$AppxEvidence=@(),[object]$OnlineEvidence=$null,[object]$SignatureEvidence=$null,[object]$FileEvidence=$null,[object[]]$ServiceEvidence=@()
    )
    $baseName=([string]$Name).Trim()
    $lower=($baseName+' '+[string]$Path+' '+[string]$Publisher+' '+[string]$Product).ToLowerInvariant()
    $scores=@{Protected=0;Security=0;Drivers=0;Gaming=0;Background=0;Application=0;Startup=0;System=0;Unknown=0}
    $evidence=New-Object System.Collections.Generic.List[string]
    $whyParts=New-Object System.Collections.Generic.List[string]
    if(Test-YumKnownSystemIdentity -Name $Name){
        [void]$evidence.Add('Known Windows system identity')
        return [pscustomobject]@{Placement='Security';ActionLane='Protect; never manage automatically';Confidence=99;ResearchReason=('Known Windows system identity: {0}' -f $Name);EvidenceSources=@('Known Windows system identity');ResearchLinks=@();Scores=$scores;OnlineMatchConfidence=0;VerifiedSourceCount=0}
    }

    # Safety is an explicit signal, but only security/system evidence gets the hard protected lane.
    if($Risk -eq 'Protected'){$scores.Security+=45;[void]$evidence.Add('Existing protected classification')}
    if($Category -match '(?i)startup'){$scores.Startup+=25;[void]$evidence.Add('Startup inventory source')}

    if($lower -match '(?i)\\windows\\system32\\drivers\\|\\driverstore\\|\\drivers\\'){$scores.Drivers+=45;[void]$evidence.Add('Windows driver path')}
    if($lower -match '(?i)defender|antimalware|securityhealth|crowdstrike|sentinelone|eset|bitdefender|malwarebytes|sophos|mcafee'){$scores.Security+=45;[void]$evidence.Add('Security software identity pattern')}
    if($lower -match '(?i)steam|epic|riot|ubisoft|battle\.net|xbox|valorant|fortnite|minecraft|apex|overwatch|warframe|gta5'){$scores.Gaming+=35;[void]$evidence.Add('Gaming software identity pattern')}
    if($lower -match '(?i)onedrive|dropbox|googledrive|icloud|megasyn|teams|slack|discord|zoom|spotify|adobe|creative cloud'){$scores.Background+=25;[void]$evidence.Add('Background application identity pattern')}

    foreach($reg in @($RegistryEvidence)){
        $match=[int]$reg.Score
        if($match -ge 60){$scores.Application+=35;[void]$evidence.Add('Strong installed-software registry match')}
        elseif($match -ge 45){$scores.Application+=25;[void]$evidence.Add('Installed-software registry match')}
        elseif($match -ge 30){$scores.Application+=15}
        if([string]$reg.Publisher -and [string]$Publisher){
            if((Get-YumResearchTokenOverlap -Left ([string]$reg.Publisher) -Right $Publisher) -ge 80){$scores.Application+=10;[void]$evidence.Add('Publisher corroborated by registry')}
        }
    }

    if($null -ne $SignatureEvidence){
        $status=[string]$SignatureEvidence.Status
        $signer=[string]$SignatureEvidence.Signer
        if($status -eq 'Valid' -and -not [string]::IsNullOrWhiteSpace($signer)){
            $scores.Application+=20;[void]$evidence.Add('Valid Authenticode signature')
            if(-not [string]::IsNullOrWhiteSpace($Publisher) -and (Get-YumResearchTokenOverlap -Left $signer -Right $Publisher) -ge 50){
                $scores.Application+=15;[void]$evidence.Add('Signer matches publisher evidence')
            }
            if($signer -match '(?i)Microsoft Corporation|Microsoft Windows'){$scores.Security+=10}
        } elseif($status -eq 'NotSigned') {[void]$evidence.Add('Executable is unsigned')}
    } elseif(-not [string]::IsNullOrWhiteSpace($Signature) -and $Signature -ne 'Unknown'){$scores.Application+=10;[void]$evidence.Add('Signer metadata available')}

    if($null -ne $WingetEvidence){
        $wscore=[int]$WingetEvidence.MatchScore
        if($wscore -ge 75){$scores.Application+=30;[void]$evidence.Add('Strong WinGet catalog match')}
        elseif($wscore -ge 50){$scores.Application+=20;[void]$evidence.Add('WinGet catalog corroboration')}
        elseif($wscore -ge 30){$scores.Application+=10}
    }

    foreach($appx in @($AppxEvidence)){
        $ascore=[int]$appx.Score
        if($ascore -ge 75){$scores.Application+=30;[void]$evidence.Add('Strong AppX package identity match')}elseif($ascore -ge 50){$scores.Application+=20;[void]$evidence.Add('AppX package corroboration')}elseif($ascore -ge 30){$scores.Application+=10}
        if([int]$appx.PathMatchScore -ge 90){$scores.Application+=15;[void]$evidence.Add('AppX install location matches executable parent folder')}
    }

    if($null -ne $OnlineEvidence){
        $oscore=[int]$OnlineEvidence.BestScore
        if($oscore -ge 80){$scores.Application+=25;[void]$evidence.Add('Strong online corroboration')}
        elseif($oscore -ge 60){$scores.Application+=18;[void]$evidence.Add('Online corroboration')}
        elseif($oscore -ge 40){$scores.Application+=8;[void]$evidence.Add('Weak online corroboration')}
        if([int]$OnlineEvidence.VerifiedCount -gt 0){$scores.Application+=10;[void]$evidence.Add('Verified source page corroboration')}
    }
    if($null -ne $FileEvidence){
        $fpCompany=[string]$FileEvidence.Company; $fpProduct=[string]$FileEvidence.Product
        if(-not [string]::IsNullOrWhiteSpace($Publisher) -and -not [string]::IsNullOrWhiteSpace($fpCompany) -and (Get-YumResearchTokenOverlap -Left $Publisher -Right $fpCompany) -ge 60){$scores.Application+=20;[void]$evidence.Add('File company matches publisher')}
        if(-not [string]::IsNullOrWhiteSpace($Name) -and -not [string]::IsNullOrWhiteSpace($fpProduct) -and (Get-YumResearchTokenOverlap -Left $Name -Right $fpProduct) -ge 60){$scores.Application+=15;[void]$evidence.Add('File product matches application name')}
    }
    # Service metadata corroborates identity for service-backed applications and drivers.
    # Windows system services/components are identifiable enough to protect even when
    # the service is hosted by svchost and therefore has no unique executable signature.
    $isWindowsSystemService=($Category -match '(?i)service') -and ($Publisher -match '(?i)^Microsoft Corporation$|^Microsoft Windows$') -and (($Path -match '(?i)\\Windows\\System32\\|\\svchost\.exe') -or (@($ServiceEvidence).Count -gt 0))
    # 5.4: the scanner now records the real publisher name; keep accepting the old publisher-ID form for saved records.
    $isWindowsAppxComponent=($Category -match '(?i)app|installed|protected') -and ($Publisher -match '(?i)^(8wekyb3d8bbwe|cw5n1h2txyewy|Microsoft Corporation|Microsoft Windows)$') -and ($Name -match '(?i)^Microsoft|^[0-9a-f]{8}-[0-9a-f]{4}-')
    # 5.4: a package full name ending in Microsoft's own publisher IDs is a Microsoft package whatever
    # category it was filed under (a manual "Review Queue" choice used to hide this rule).
    $microsoftPackageId=($Path -match '(?i)_(8wekyb3d8bbwe|cw5n1h2txyewy)$')
    if($microsoftPackageId -and ($Name -match '(?i)^Microsoft|^[0-9a-f]{8}-[0-9a-f]{4}-|^Windows')){$isWindowsAppxComponent=$true}
    foreach($appxV in @($AppxEvidence|Where-Object{$null -ne $_.PSObject.Properties['ExactPackage'] -and [bool]$_.ExactPackage -and [string]$_.SignatureKind -in @('Store','System')})){
        $scores.Application+=25;[void]$evidence.Add(('Package signature verified by Windows ({0})' -f $appxV.SignatureKind));break
    }
    if($isWindowsSystemService){$scores.System+=45;[void]$evidence.Add('Windows system service identity')}
    if($isWindowsAppxComponent){$scores.System+=45;[void]$evidence.Add('Windows system component identity')}
    if($microsoftPackageId -and $isWindowsAppxComponent){$scores.System+=20;[void]$evidence.Add('Published under Microsoft''s own package ID')}

    if($null -ne $ServiceEvidence){
        $strongSvc=@($ServiceEvidence|Where-Object{[int]$_.Score -ge 70}).Count -gt 0
        $svc=@($ServiceEvidence)
        if($strongSvc){$scores.Application+=20;[void]$evidence.Add('Windows service metadata corroborates identity')}
        if(@($svc|Where-Object{([string]$_.StartMode -match '(?i)auto') -and ([string]$_.PathName -match '(?i)\\windows\\system32|\\drivers\\')}).Count -gt 0){$scores.Drivers+=20;[void]$evidence.Add('Service is backed by Windows driver/system path')}
    }
    # 5.4: protected Windows processes (e.g. sppsvc, Software Protection) hide their path from other
    # programs, so the scanner sees no executable. If the matching Windows service runs a binary in
    # System32 that Windows verifies as Microsoft-signed, that is the identity.
    $windowsServiceBinary=$null
    if([string]::IsNullOrWhiteSpace($Path) -and -not [string]::IsNullOrWhiteSpace($baseName)){
        $hidden=Get-YumPathlessProcessIdentity -Name $baseName
        if($null -ne $hidden){
            $windowsServiceBinary=$hidden.Path
            if($hidden.Path -match '(?i)\\DriverStore\\'){$scores.Drivers+=70;[void]$evidence.Add(('Protected driver process: {0} (Windows driver store, {1})' -f $hidden.Path,$hidden.How))}
            elseif($hidden.Microsoft -and $hidden.UnderWindows){$scores.System+=70;[void]$evidence.Add(('Protected Windows process: {0}, signed by Microsoft ({1})' -f $hidden.Path,$hidden.How))}
            elseif($hidden.Microsoft){$scores.System+=60;[void]$evidence.Add(('Protected Microsoft process: {0} ({1})' -f $hidden.Path,$hidden.How))}
            elseif($hidden.UnderWindows -or $hidden.Signer -match '(?i)nvidia|advanced micro devices|amd|intel|realtek|logitech|corsair|razer|asus|msi|dolby|dts|synaptics|elan|qualcomm|broadcom|killer|rivet'){$scores.Drivers+=60;[void]$evidence.Add(('Protected hardware/driver process: {0}, signed by {1} ({2})' -f $hidden.Path,$hidden.Signer,$hidden.How))}
            else{$scores.Application+=45;[void]$evidence.Add(('Protected process: {0}, signed by {1} ({2})' -f $hidden.Path,$hidden.Signer,$hidden.How))}
            if([string]::IsNullOrWhiteSpace($Publisher) -or $Publisher -eq 'Unknown'){$Publisher=$hidden.Signer}
        }
    }

    $ordered=@($scores.GetEnumerator()|Sort-Object Value -Descending)
    $winner=$ordered[0].Key;$top=[int]$ordered[0].Value;$second=[int]$ordered[1].Value
    $confidence=[math]::Min(99,[math]::Max(0,50+$top-$second))
    $registryStrong=(@($RegistryEvidence|Where-Object{[int]$_.Score -ge 60})).Count -gt 0
    $signatureStrong=($null -ne $SignatureEvidence -and [string]$SignatureEvidence.Status -eq 'Valid' -and -not [string]::IsNullOrWhiteSpace([string]$SignatureEvidence.Thumbprint))
    $signerMatches=($signatureStrong -and -not [string]::IsNullOrWhiteSpace($Publisher) -and (Get-YumResearchTokenOverlap -Left ([string]$SignatureEvidence.Signer) -Right $Publisher) -ge 50)
    $wingetStrong=($null -ne $WingetEvidence -and [bool]$WingetEvidence.ExactName -and [int]$WingetEvidence.MatchScore -ge 75)
    $appxStrong=(@($AppxEvidence|Where-Object{[int]$_.Score -ge 75}).Count -gt 0)
    # 5.4: Windows verifies Store/System package signatures itself; an exact package match with that
    # signature is equivalent to a valid Authenticode signer match for an .exe.
    $appxVerified=(@($AppxEvidence|Where-Object{$null -ne $_.PSObject.Properties['ExactPackage'] -and [bool]$_.ExactPackage -and [string]$_.SignatureKind -in @('Store','System')}).Count -gt 0)
    if($appxVerified){$signerMatches=$true}
    if($null -ne $windowsServiceBinary -or ($microsoftPackageId -and $isWindowsAppxComponent)){$signerMatches=$true;$appxStrong=$appxStrong -or $microsoftPackageId}
    $onlineStrong=($null -ne $OnlineEvidence -and [bool]$OnlineEvidence.Success -and [int]$OnlineEvidence.BestScore -ge 70 -and [int]$OnlineEvidence.VerifiedCount -gt 0)
    $fileStrong=($null -ne $FileEvidence -and ((-not [string]::IsNullOrWhiteSpace($Publisher) -and -not [string]::IsNullOrWhiteSpace([string]$FileEvidence.Company) -and (Get-YumResearchTokenOverlap -Left $Publisher -Right ([string]$FileEvidence.Company)) -ge 60) -or (-not [string]::IsNullOrWhiteSpace($Name) -and -not [string]::IsNullOrWhiteSpace([string]$FileEvidence.Product) -and (Get-YumResearchTokenOverlap -Left $Name -Right ([string]$FileEvidence.Product)) -ge 60)))
    $identitySignals=@( @($registryStrong,$signerMatches,$wingetStrong,$appxStrong,$onlineStrong,$fileStrong,(@($ServiceEvidence|Where-Object{[int]$_.Score -ge 70}).Count -gt 0)) | Where-Object { $_ } )
    $strongProof=($identitySignals.Count -ge 1)
    $multiSourceProof=($identitySignals.Count -ge 2)
    # Online corroboration is supplemental. Two independent local identity anchors can safely promote an item.
    $strongIdentityPromotion=(
        ($signerMatches -and ($fileStrong -or $wingetStrong -or $registryStrong -or $appxStrong)) -or
        ($wingetStrong -and ($fileStrong -or $registryStrong -or $appxStrong)) -or
        ($registryStrong -and ($fileStrong -or $appxStrong)) -or
        ($appxStrong -and $fileStrong)
    )
    $corroborated=$onlineStrong -or $wingetStrong -or $registryStrong -or $signerMatches
    if($multiSourceProof){$confidence=[math]::Min(99,$confidence+12)}
    elseif($strongProof){$confidence=[math]::Min(89,$confidence+4)}
    else{$confidence=[math]::Min(69,$confidence)}
    if($top -lt 35){$winner='Unknown';$confidence=[math]::Min($confidence,45)}

    switch($winner){
        'Security' {$placement='Security';$action='Protect; never manage automatically'}
        'Drivers' {$placement='Drivers / Hardware';$action='Protect; never manage automatically'}
        'Gaming' {$placement='Games / Gaming';$action='Protect during gaming'}
        'Background' {
            $placement='User Background Apps'
            # Strong post-research identity evidence overrides the scanner's initial Review state.
            $action=if($strongIdentityPromotion -or ($confidence -ge 85 -and $multiSourceProof)){'Candidate only under memory pressure'}else{'Review until identity is corroborated'}
        }
        'Startup' {$placement='Startup Inventory';$action='Review startup behavior before changes'}
        'System' {$placement='Windows System Components';$action='Protect; never manage automatically'}
        'Application' {
            $placement='Identified Applications'
            # Research evidence is authoritative after the scan; a pre-research Risk=Review flag
            # must not block promotion when multiple independent identity signals agree.
            $action=if($strongIdentityPromotion -or ($confidence -ge 85 -and $multiSourceProof)){'Candidate under memory pressure'}else{'Review until identity is corroborated'}
        }
        default {$placement='Unknown / Quarantine for Review';$action='Never manage automatically';$confidence=[math]::Min($confidence,45)}
    }
    if($Risk -eq 'Protected' -and $winner -in @('Security','Drivers')){$confidence=[math]::Max($confidence,92)}
    if($evidence.Count -eq 0){[void]$evidence.Add('No corroborating research evidence')}
    if(-not [string]::IsNullOrWhiteSpace($Reason)){[void]$whyParts.Add($Reason)}
    [void]$whyParts.Add(('Evidence score: {0} ({1})' -f $top,$winner))
    [void]$whyParts.Add(($evidence -join ', '))
    if($null -ne $OnlineEvidence){[void]$whyParts.Add(('Best online match: {0}%; verified sources: {1}' -f ([int]$OnlineEvidence.BestScore),[int]$OnlineEvidence.VerifiedCount))}
    $evidenceSources=@($evidence.ToArray())
    $researchLinks=@()
    $onlineMatchConfidence=0
    $verifiedSourceCount=0
    if($null -ne $OnlineEvidence){
        $researchLinks=@($OnlineEvidence.VerifiedLinks)
        $onlineMatchConfidence=[int]$OnlineEvidence.BestScore
        $verifiedSourceCount=[int]$OnlineEvidence.VerifiedCount
    }
    [pscustomobject]@{Placement=$placement;ActionLane=$action;Confidence=[int]$confidence;ResearchReason=($whyParts -join '; ');EvidenceSources=$evidenceSources;ResearchLinks=$researchLinks;Scores=$scores;OnlineMatchConfidence=$onlineMatchConfidence;VerifiedSourceCount=$verifiedSourceCount}
}



function Test-YumResearchTerminalResult {
    param([Parameter(Mandatory=$true)]$PlacementResult)
    $placement=[string]$PlacementResult.Placement
    $action=[string]$PlacementResult.ActionLane
    if([string]::IsNullOrWhiteSpace($placement) -or $placement -eq 'Review Queue'){return $false}
    if($placement -eq 'Unknown / Quarantine for Review'){return $true}
    # Startup Inventory and protected categories may intentionally retain a conservative
    # action lane (for example, review startup behavior) while still being fully identified.
    # A known placement may still require a human decision. That is an identified, completed result—not an unknown identity. The ActionLane continues to prevent automatic management.
    return $true
}

function Write-YumResearchLiveSnapshot {
    param(
        [Parameter(Mandatory=$true)][string]$RunId,
        [Parameter(Mandatory=$true)][int]$Completed,
        [Parameter(Mandatory=$true)][int]$Total,
        [object[]]$Records=@()
    )
    try {
        # One atomic live checkpoint is enough. The UI reads the finished destination while the
        # worker writes a unique temporary file, then atomically replaces the destination.
        # This keeps the Research workspace to one live-results file instead of one file per item.
        $path=Join-Path $script:Yum.Root 'research-live-results.json'
        $tmp=Join-Path $script:Yum.Root 'research-live-results.tmp'
        $mutexName='Global\YUMRAM-ResearchLiveCheckpoint'
        $mutex=$null;$lockTaken=$false
        $payload=[pscustomobject]@{
            RunId=$RunId
            UpdatedAt=(Get-Date).ToString('o')
            Completed=$Completed
            Total=$Total
            Records=@($Records)
            ResearchedCount=@($Records|Where-Object{[string](Get-YumResearchSafeProperty -Object $_ -Name 'ResearchRunDisposition' -Default '') -eq 'Researched'}).Count
            CachedCount=@($Records|Where-Object{[string](Get-YumResearchSafeProperty -Object $_ -Name 'ResearchRunDisposition' -Default '') -eq 'Cached'}).Count
            ReviewResolvedCount=@($Records|Where-Object{[bool](Get-YumResearchSafeProperty -Object $_ -Name 'ResearchRunResolved' -Default $false)}).Count
            OnlineResearchCount=@($Records|Where-Object{[bool](Get-YumResearchSafeProperty -Object $_ -Name 'ResearchRunOnline' -Default $false)}).Count
            UnknownCount=@($Records|Where-Object{[string](Get-YumResearchSafeProperty -Object $_ -Name 'ResearchStatus' -Default '') -eq 'Unknown' -and [string](Get-YumResearchSafeProperty -Object $_ -Name 'ResearchRunDisposition' -Default '') -eq 'Researched'}).Count
            ResearchErrorCount=@($Records|Where-Object{[string](Get-YumResearchSafeProperty -Object $_ -Name 'ResearchStatus' -Default '') -eq 'Research Error'}).Count
        }
        $json=$payload|ConvertTo-Json -Depth 15 -Compress
        try{
            $mutex=New-Object System.Threading.Mutex($false,$mutexName)
            $lockTaken=$mutex.WaitOne([TimeSpan]::FromSeconds(10))
            if(-not $lockTaken){throw 'Timed out waiting for the Research live checkpoint lock.'}
            [System.IO.File]::WriteAllText($tmp,$json,([System.Text.UTF8Encoding]::new($false)))
            # The UI acquires the same named mutex before reading. This removes the Windows
            # PowerShell 5.1 file-share race that previously produced Access Denied and orphaned
            # a new .tmp file for every research item.
            Move-Item -LiteralPath $tmp -Destination $path -Force
        } finally {
            if($lockTaken){try{$mutex.ReleaseMutex()}catch{}}
            if($null -ne $mutex){try{$mutex.Dispose()}catch{}}
            try{if(Test-Path -LiteralPath $tmp){Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue}}catch{}
        }
    } catch {
        try{Write-YumLog ('Research live snapshot write failed: {0}' -f $_.Exception.Message)}catch{}
    }
}


function Test-YumResearchUnresolved {
    param($Record)
    if($null -eq $Record){return $false}
    if($null -ne $Record.PSObject.Properties['ManualOverride'] -and [bool]$Record.ManualOverride){return $false}
    $status='Not Researched'
    if($null -ne $Record.PSObject.Properties['ResearchStatus']){$status=[string]$Record.ResearchStatus}
    if($status -eq 'Organized'){return $false}
    if($status -eq 'Unknown'){
        # 5.4: Unknown is final only for the engine version that decided it. Unknowns from an older engine
        # (or with no stamp) get one fresh attempt; afterwards they are stamped and final again.
        $decidedBy='';if($null -ne $Record.PSObject.Properties['ResearchEngineVersion']){$decidedBy=[string]$Record.ResearchEngineVersion}
        $current='';try{$current=[string]$script:Yum.Config.ResearchEngineVersion}catch{}
        if([string]::IsNullOrWhiteSpace($current) -or $decidedBy -eq $current){return $false}
        return $true
    }
    $risk=[string]$Record.Risk
    $category=[string]$Record.Category
    $placement=[string]$Record.Placement
    $action=[string]$Record.ActionLane
    # Protected/security/driver classifications are not research candidates unless explicitly put back into Review.
    $protectedFamily=($risk -eq 'Protected' -or $category -in @('Protected','Security','Drivers / Hardware'))
    $explicitReview=(($action -match '(?i)\bReview\b') -or ($placement -in @('Review Queue','Unknown / Quarantine for Review')))
    if($protectedFamily -and -not $explicitReview){return $false}
    if($status -eq 'Research Error'){return $true}
    return (
        $risk -in @('Review','Candidate','Unknown') -or
        $action -match '(?i)\bReview\b' -or
        $placement -in @('','Review Queue','Unknown / Quarantine for Review') -or
        (-not [bool]$Record.ResearchComplete -and $category -notin @('Protected','Security','Drivers / Hardware'))
    )
}

function Invoke-YumResearch {
    param([object[]]$Records=@(),[string]$RunId='',[switch]$ForceFreshResearch)
    $script:YumResearchRegistryInventory=$null
    $script:YumResearchAppxInventory=$null
    $script:YumResearchServiceInventory=$null
    $script:YumResearchWinGetInventory=$null
    # Research is intentionally single-item sequential. This prevents concurrent evidence lookups, UI contention, and network bursts.
    $researchConcurrency=1 # hard safety contract: one research item at a time
    # Normalize null/empty input defensively. Empty research queues are valid no-ops.
    $Records=@($Records | Where-Object { $null -ne $_ })
    if($Records.Count -eq 0){
        if([string]::IsNullOrWhiteSpace($RunId)){$RunId=[guid]::NewGuid().ToString('N')}
        Set-YumResearchStatus -Key '' -Name 'Review Research Queue' -Stage 'Idle' -Index 0 -Total 0 -Message 'No researchable records were queued.'
        Write-YumResearchLiveSnapshot -RunId $RunId -Completed 0 -Total 0 -Records @()
        return [pscustomobject]@{Records=@();ResearchedCount=0;OnlineResearchCount=0;ReviewResolvedCount=0;UnknownCount=0;CacheCount=0;ResearchErrorCount=0;OnlineEnabled=[bool]$script:Yum.Config.IntelligenceResearchEnabled;LocalClassificationComplete=$true;Errors=@();RunId=$RunId}
    }

    $cache=Load-YumResearchCache
    $changed=$false
    $onlineLimit=8 # bounded web corroboration slots per manual run
    $currentEngine=''
    try {
        if($null -ne $script:Yum.Config.PSObject.Properties['ResearchEngineVersion'] -and -not [string]::IsNullOrWhiteSpace([string]$script:Yum.Config.ResearchEngineVersion)){
            $currentEngine=[string]$script:Yum.Config.ResearchEngineVersion
        }
    } catch {}
    if([string]::IsNullOrWhiteSpace($currentEngine)){try{$vp=Join-Path $script:Yum.Root 'VERSION';if(Test-Path -LiteralPath $vp){$currentEngine=(Get-Content -LiteralPath $vp -Raw -ErrorAction Stop).Trim()}}catch{}}
    if($null -ne $script:Yum.Config.PSObject.Properties['ResearchMaxOnlineItemsPerScan']){
        $onlineLimit=[int]$script:Yum.Config.ResearchMaxOnlineItemsPerScan
    } elseif($null -ne $script:Yum.Config.PSObject.Properties['ResearchMaxItemsPerScan']){
        $onlineLimit=[int]$script:Yum.Config.ResearchMaxItemsPerScan
    }
    if($onlineLimit -lt 0){$onlineLimit=0}

    $onlineCount=0
    $researchedCount=0
    $cachedCount=0
    $reviewResolvedCount=0
    $unknownCount=0
    $out=New-Object System.Collections.Generic.List[object]
    if([string]::IsNullOrWhiteSpace($RunId)){$RunId=[guid]::NewGuid().ToString('N')}
    $totalRecords=@($Records).Count
    Write-YumResearchDiagnostic -RunId $RunId -Stage 'QueueStarted' -Message ('Research queue started with {0} records.' -f $totalRecords)
    $queueIndex=0
    Set-YumResearchStatus -Key '' -Name 'Review Research Queue' -Stage 'Started' -Index 0 -Total $totalRecords -Message ('Research queue started with {0} records.' -f $totalRecords)
    Write-YumResearchLiveSnapshot -RunId $RunId -Completed 0 -Total $totalRecords -Records @()

    foreach($r in @($Records)){
        $queueIndex++
        try {
            [void](Ensure-YumResearchRecordSchema -Record $r)
            Set-YumResearchStatus -Key ([string]$r.Key) -Name ([string]$r.Name) -Stage 'Researching Item' -Index $queueIndex -Total $totalRecords -Message ('Researching item {0} of {1} (1 at a time).' -f $queueIndex,$totalRecords)

            $beforeResearchStatus=[string]$r.ResearchStatus
            if([string]::IsNullOrWhiteSpace($beforeResearchStatus)){
                if([bool]$r.ResearchComplete -and [string]$r.Placement -notin @('', 'Review Queue', 'Unknown / Quarantine for Review')){$beforeResearchStatus='Organized'}
                elseif([string]$r.Risk -eq 'Unknown'){$beforeResearchStatus='Unknown'}
                else{$beforeResearchStatus='Review'}
            }
            $manual=$false
            if($null -ne $r.PSObject.Properties['ManualOverride']){$manual=[bool]$r.ManualOverride}
            $actionText=[string]$r.ActionLane
            $placementOnRecord=[string]$r.Placement
            # Defense-in-depth: the worker must enforce the same authoritative queue predicate as the UI.
            $needs=Test-YumResearchUnresolved -Record $r
            if(-not $needs){
                $r|Add-Member -NotePropertyName ResearchRunDisposition -NotePropertyValue 'Unchanged' -Force
                $r|Add-Member -NotePropertyName ResearchRunResolved -NotePropertyValue $false -Force
                $r|Add-Member -NotePropertyName ResearchRunOnline -NotePropertyValue $false -Force
                [void]$out.Add($r)
                Write-YumResearchLiveSnapshot -RunId $RunId -Completed $queueIndex -Total $totalRecords -Records $out.ToArray()
                continue
            }
            $fileEvidenceForKey=Get-YumResearchFileEvidence -Path ([string]$r.Path)
            $signatureForKey=Get-YumResearchSignature -Path ([string]$r.Path)
            $fileHashForKey=''; $signerThumbForKey=''; $productForKey=''; $versionForKey=''
            if($null -ne $fileEvidenceForKey){$fileHashForKey=[string]$fileEvidenceForKey.Hash;$versionForKey=[string]$fileEvidenceForKey.FileVersion;$productForKey=[string]$fileEvidenceForKey.Product}
            if($null -ne $signatureForKey){$signerThumbForKey=[string]$signatureForKey.Thumbprint}
            if($null -ne $r.PSObject.Properties['Product'] -and -not [string]::IsNullOrWhiteSpace([string]$r.Product)){$productForKey=[string]$r.Product}
            if($null -ne $r.PSObject.Properties['Version'] -and -not [string]::IsNullOrWhiteSpace([string]$r.Version)){$versionForKey=[string]$r.Version}
            $key=Get-YumResearchKey -Name ([string]$r.Name) -Path ([string]$r.Path) -Publisher ([string]$r.Publisher) -Product $productForKey -Version $versionForKey -FileHash $fileHashForKey -SignerThumbprint $signerThumbForKey
            $legacyKey=Get-YumResearchKey -Name ([string]$r.Name) -Path ([string]$r.Path) -Publisher ([string]$r.Publisher) -Product ([string]$r.Category) -Version '' -FileHash $fileHashForKey -SignerThumbprint $signerThumbForKey
            $cached=$null
            if($cache.ContainsKey($key)){$cached=$cache[$key]}
            elseif($cache.ContainsKey($legacyKey)){
                $legacy=$cache[$legacyKey]
                # Migrate legacy cache entries when the executable identity still matches.
                $legacyHash='';$legacySigner=''
                try{$legacyHash=[string]$legacy.FileHash;$legacySigner=[string]$legacy.SignerThumbprint}catch{}
                if(($fileHashForKey -eq '' -or $legacyHash -eq '' -or $legacyHash -eq $fileHashForKey) -and ($signerThumbForKey -eq '' -or $legacySigner -eq '' -or $legacySigner -eq $signerThumbForKey)){
                    $cached=$legacy;$cache[$key]=$legacy;$changed=$true
                }
            }
            $fresh=$false
            $cachedStatus=''
            $cacheExpired=$false
            if($null -ne $cached){
                try {
                    $engine=[string]$cached.EngineVersion
                    $cachedPlacement=[string]$cached.Placement
                    $cachedAction=[string]$cached.ActionLane
                    $cachedStatus=[string]$cached.ResearchStatus
                    $cacheAgeDays=((Get-Date)-([datetime]$cached.ResearchedAt)).TotalDays
                    $cacheExpired=($cacheAgeDays -gt [double]$script:Yum.Config.ResearchCacheMaxAgeDays)
                    $cachedResolved=($cachedStatus -in @('Organized','Unknown'))
                    if($cachedStatus -eq 'Organized') {
                        try { $cachedResolved=Test-YumResearchTerminalResult -PlacementResult $cached } catch { $cachedResolved=($cachedPlacement -notin @('','Review Queue','Unknown / Quarantine for Review') -and $cachedAction -notmatch '(?i)\bReview\b') }
                    }
                    $cachedTerminal=$cachedResolved
                    $fresh=($engine -eq $currentEngine) -and $cachedTerminal -and (-not $cacheExpired)
                } catch {
                    $fresh=$false
                }
            }

            # A valid completed cache result is authoritative for a fresh scan.
            # Do not let the scanner's default Review/Candidate state force a duplicate
            # research pass. Only explicit invalidation conditions should re-research.
            if($ForceFreshResearch){$fresh=$false;$cacheExpired=$false;$cachedStatus=''}
            $forceResearch=$false
            # The worker is invoked only for records that the UI explicitly queued for research.
            # Therefore an unresolved item with no valid terminal cache MUST actually enter the
            # research pipeline regardless of whether Scanner labeled it Candidate, Unknown, or Review.
            # The previous implementation only researched Risk=Review/Action=Review records, which
            # made the Research button appear to run while silently skipping Candidate/Unknown items.
            if(-not $manual -and -not $fresh){
                $forceResearch=$true
            }

            $placement=$null
            $didResearch=$false
            $researchErrorState=$false
            if($fresh -and -not $manual){
                $placement=$cached
                Set-YumResearchStatus -Key $key -Name ([string]$r.Name) -Stage 'Cached' -Index $queueIndex -Total $totalRecords -Confidence ([int]$cached.Confidence) -Placement ([string]$cached.Placement) -Message 'Using valid cached research; no new research required.'
                Add-YumResearchHistory -Key $key -Name ([string]$r.Name) -Stage 'Cached' -Message 'Valid cached research reused; re-research suppressed.' -Confidence ([int]$cached.Confidence) -Placement ([string]$cached.Placement)
                $cachedCount++
                $r|Add-Member -NotePropertyName ResearchRunDisposition -NotePropertyValue 'Cached' -Force
                $r|Add-Member -NotePropertyName ResearchRunResolved -NotePropertyValue ([bool]($beforeResearchStatus -in @('Review','Research Error') -and [string]$cached.ResearchStatus -in @('Organized','Unknown'))) -Force
                $r|Add-Member -NotePropertyName ResearchRunOnline -NotePropertyValue $false -Force
            }
            if($needs -and -not $fresh -and ($forceResearch -or [bool]$script:Yum.Config.IntelligenceResearchEnabled)){
                # Stage 1: local evidence is always attempted first.
                $didResearch=$true
                try{Write-YumLog ('RESEARCH EXECUTION: item {0}/{1} -> {2}' -f $queueIndex,$totalRecords,[string]$r.Name)}catch{}
                Set-YumResearchStatus -Key $key -Name ([string]$r.Name) -Stage 'Researching Local' -Index $queueIndex -Total $totalRecords -Message 'Collecting Registry, signature, file metadata, and WinGet evidence.'
                if($forceResearch){try{Write-YumLog ('Review research started: {0}' -f [string]$r.Name)}catch{}}
                $parentFolderEvidence=Get-YumResearchParentFolderEvidence -Path ([string]$r.Path)
                $effectivePublisher=[string]$r.Publisher
                $effectiveProduct=$productForKey
                if($null -ne $parentFolderEvidence){
                    if(($effectivePublisher -eq 'Unknown' -or [string]::IsNullOrWhiteSpace($effectivePublisher)) -and -not [string]::IsNullOrWhiteSpace([string]$parentFolderEvidence.Company)){$effectivePublisher=[string]$parentFolderEvidence.Company}
                    if([string]::IsNullOrWhiteSpace($effectiveProduct) -and -not [string]::IsNullOrWhiteSpace([string]$parentFolderEvidence.Product)){$effectiveProduct=[string]$parentFolderEvidence.Product}
                }
                $registry=@(Get-YumInstalledSoftwareResearch -Name ([string]$r.Name) -Publisher $effectivePublisher -Path ([string]$r.Path))
                $appx=@(Get-YumAppxResearch -Name ([string]$r.Name) -Publisher $effectivePublisher -Path ([string]$r.Path))
                $winget=Get-YumWinGetResearch -Name ([string]$r.Name) -Publisher $effectivePublisher
                $services=@(Get-YumServiceResearch -Name ([string]$r.Name) -Path ([string]$r.Path))
                $signature=$signatureForKey
                $fileEvidence=$fileEvidenceForKey
                $signatureText=''
                if($null -ne $signature -and -not [string]::IsNullOrWhiteSpace([string]$signature.Signer)){$signatureText=[string]$signature.Signer}

                $placement=Get-YumResearchPlacement -Name ([string]$r.Name) -Path ([string]$r.Path) -Publisher $effectivePublisher -Product $effectiveProduct -Signature $signatureText -Category ([string]$r.Category) -Risk ([string]$r.Risk) -Reason ([string]$r.Reason) -RegistryEvidence $registry -WingetEvidence $winget -AppxEvidence $appx -OnlineEvidence $null -SignatureEvidence $signature -FileEvidence $fileEvidence -ServiceEvidence $services

                # Stage 2: Review is a research queue, not a terminal classification.
                # Any non-manual item still in Review receives online corroboration regardless of the normal online cap.
                $stillReview=(([string]$placement.Placement -eq 'Review Queue') -or ([string]$placement.ActionLane -match '(?i)\bReview\b'))
                $online=$null
                $onlineWasAttempted=$false
                $onlineSucceeded=$false
                $onlineError=''
                $researchProduct=$productForKey
                if([string]::IsNullOrWhiteSpace($researchProduct) -and $null -ne $fileEvidence -and -not [string]::IsNullOrWhiteSpace([string]$fileEvidence.Product)){$researchProduct=[string]$fileEvidence.Product}
                $identityAnchor=Test-YumResearchIdentityAnchor -Name ([string]$r.Name) -Path ([string]$r.Path) -Publisher ([string]$r.Publisher) -Product $researchProduct -FileEvidence $fileEvidence -SignatureEvidence $signature -RegistryEvidence $registry -WingetEvidence $winget -AppxEvidence $appx -ServiceEvidence $services
                if([bool]$script:Yum.Config.EnableOnlineResearch -and $onlineCount -lt $onlineLimit -and $identityAnchor -and -not (Test-YumKnownSystemIdentity -Name ([string]$r.Name))){
                    $onlineWasAttempted=$true
                    Set-YumResearchStatus -Key $key -Name ([string]$r.Name) -Stage 'Researching Online' -Index $queueIndex -Total $totalRecords -Message 'Local evidence collected; performing web corroboration.'
                    Add-YumResearchHistory -Key $key -Name ([string]$r.Name) -Stage 'Researching Online' -Message 'Performing web corroboration against configured authority sources.'
                    try{Write-YumLog ('ONLINE RESEARCH EXECUTION: item {0}/{1} -> {2} (online slot {3}/{4})' -f $queueIndex,$totalRecords,[string]$r.Name,($onlineCount+1),$onlineLimit)}catch{}
                    $online=Get-YumOnlineResearch -Name ([string]$r.Name) -Publisher ([string]$r.Publisher) -Product $researchProduct
                    if($null -ne $online){$onlineSucceeded=[bool]$online.Success;$onlineError=[string]$online.Error;if($onlineSucceeded){$onlineCount++}}
                    Start-Sleep -Milliseconds 250
                }

                $placement=Get-YumResearchPlacement -Name ([string]$r.Name) -Path ([string]$r.Path) -Publisher $effectivePublisher -Product $effectiveProduct -Signature $signatureText -Category ([string]$r.Category) -Risk ([string]$r.Risk) -Reason ([string]$r.Reason) -RegistryEvidence $registry -WingetEvidence $winget -AppxEvidence $appx -OnlineEvidence $online -SignatureEvidence $signature -FileEvidence $fileEvidence -ServiceEvidence $services

                # Only convert to Unknown when research completed successfully but remained inconclusive.
                $onlineOperationalError=($onlineWasAttempted -and -not $onlineSucceeded -and -not [string]::IsNullOrWhiteSpace($onlineError))
                # No online match is a valid research outcome; only an explicit error is an operational failure.
                $researchErrorState=($onlineOperationalError -and $stillReview)
                if([string]$placement.Placement -eq 'Review Queue' -and -not $researchErrorState -and (-not $identityAnchor -or $onlineWasAttempted -or -not [bool]$script:Yum.Config.EnableOnlineResearch)){
                    $unknownReason = if(-not $identityAnchor){'{0}; No durable identity anchor exists; web research intentionally skipped.' -f [string]$placement.ResearchReason}else{'{0}; Research completed without sufficient corroboration.' -f [string]$placement.ResearchReason}
                    $placement=[pscustomobject]@{
                        Placement='Unknown / Quarantine for Review'
                        ActionLane='Never manage automatically'
                        Confidence=[math]::Min(45,[int]$placement.Confidence)
                        ResearchReason=$unknownReason
                        EvidenceSources=@($placement.EvidenceSources)+'Research completed; identity unresolved'
                        ResearchLinks=if($null -ne $online){if(@($online.VerifiedLinks).Count -gt 0){@($online.VerifiedLinks)}else{@()}}else{@()}
                        Scores=$placement.Scores
                        OnlineMatchConfidence=if($null -ne $online){[int]$online.BestScore}else{0}
                        VerifiedSourceCount=if($null -ne $online){[int]$online.VerifiedCount}else{0}
                    }
                    $unknownCount++
                } elseif($researchErrorState -and [string]$placement.Placement -eq 'Review Queue'){
                    Set-YumResearchStatus -Key $key -Name ([string]$r.Name) -Stage 'Research Error' -Index $queueIndex -Total $totalRecords -Confidence ([int]$placement.Confidence) -Placement 'Unknown / Quarantine for Review' -Message ('Research service failed; item was terminally quarantined for retry/diagnostics: {0}' -f $onlineError) -Error $onlineError
                    Add-YumResearchHistory -Key $key -Name ([string]$r.Name) -Stage 'Research Error' -Message 'Online research failed; item was quarantined instead of remaining in the active Review queue.' -Placement 'Unknown / Quarantine for Review' -Error $onlineError
                    $placement=[pscustomobject]@{
                        Placement='Unknown / Quarantine for Review'
                        ActionLane='Never manage automatically'
                        Confidence=[math]::Min(45,[int]$placement.Confidence)
                        ResearchReason=('Online research failed: {0}' -f $onlineError)
                        EvidenceSources=@($placement.EvidenceSources)+'Online research failed; quarantined'
                        ResearchLinks=@()
                        Scores=$placement.Scores
                        OnlineMatchConfidence=if($null -ne $online){[int]$online.BestScore}else{0}
                        VerifiedSourceCount=if($null -ne $online){[int]$online.VerifiedCount}else{0}
                    }
                } elseif(-not $researchErrorState -and -not (Test-YumResearchTerminalResult -PlacementResult $placement)){
                    # A completed automatic Research pass must never leave a record in an active Review queue.
                    # Preserve the evidence/placement for diagnostics, but make the operational state terminal.
                    $placement=[pscustomobject]@{
                        Placement='Unknown / Quarantine for Review'
                        ActionLane='Never manage automatically'
                        Confidence=[math]::Min(60,[int]$placement.Confidence)
                        ResearchReason=('Research completed but corroboration remained insufficient. Original placement: {0}.' -f [string]$placement.Placement)
                        EvidenceSources=@($placement.EvidenceSources)+'Research completed; corroboration insufficient; quarantined'
                        ResearchLinks=if($null -ne $online){if(@($online.VerifiedLinks).Count -gt 0){@($online.VerifiedLinks)}else{@()}}else{@()
                        }
                        Scores=$placement.Scores
                        OnlineMatchConfidence=if($null -ne $online){[int]$online.BestScore}else{0}
                        VerifiedSourceCount=if($null -ne $online){[int]$online.VerifiedCount}else{0}
                    }
                    $unknownCount++
                    Set-YumResearchStatus -Key $key -Name ([string]$r.Name) -Stage 'Unknown' -Index $queueIndex -Total $totalRecords -Confidence ([int]$placement.Confidence) -Placement 'Unknown / Quarantine for Review' -Message 'Research completed but corroboration was insufficient; item was quarantined instead of remaining queued.'
                }

                # One authoritative final-state calculation. Fresh research always outranks cached state.
                $finalResearchStatus='Not Researched'
                if($didResearch){
                    if($researchErrorState){$finalResearchStatus='Research Error'}
                    elseif([string]$placement.Placement -eq 'Unknown / Quarantine for Review'){$finalResearchStatus='Unknown'}
                    elseif(Test-YumResearchTerminalResult -PlacementResult $placement){$finalResearchStatus='Organized'}
                    else{$finalResearchStatus='Review'}
                } elseif($fresh -and $null -ne $cached -and $null -ne $cached.PSObject.Properties['ResearchStatus']) {
                    $finalResearchStatus=[string]$cached.ResearchStatus
                } elseif($null -ne $cached -and $cachedStatus -in @('Organized','Unknown','Research Error','Review')) {
                    $finalResearchStatus=$cachedStatus
                } elseif([string]$placement.Placement -eq 'Unknown / Quarantine for Review'){$finalResearchStatus='Unknown'}
                elseif(Test-YumResearchTerminalResult -PlacementResult $placement){$finalResearchStatus='Organized'}
                else{$finalResearchStatus='Review'}
                $researchTerminal=($finalResearchStatus -in @('Organized','Unknown','Research Error'))
                $researchRunResolved=([bool]$needs -and $finalResearchStatus -in @('Organized','Unknown'))

                $cached=[pscustomobject]@{
                    ResearchedAt=(Get-Date).ToString('o')
                    EngineVersion=([string]$script:Yum.Config.ResearchEngineVersion)
                    Name=$r.Name
                    Publisher=$effectivePublisher
                    Product=$effectiveProduct
                    ParentFolder=if($null -ne $parentFolderEvidence){[string]$parentFolderEvidence.FolderPath}else{''}
                    Placement=$placement.Placement
                    ActionLane=$placement.ActionLane
                    Confidence=$placement.Confidence
                    ResearchReason=$placement.ResearchReason
                    EvidenceSources=$placement.EvidenceSources
                    Scores=$placement.Scores
                    Registry=@($registry)
                    Appx=@($appx)
                    Winget=$winget
                    Online=$online
                    Signature=$signature
                    FileEvidence=$fileEvidence
                    ServiceEvidence=@($services)
                    EvidenceFingerprint=(Get-YumResearchEvidenceFingerprint -FileEvidence $fileEvidence -SignatureEvidence $signature -RegistryEvidence $registry -WingetEvidence $winget -AppxEvidence $appx -OnlineEvidence $online -ServiceEvidence $services)
                    FileHash=if($null -ne $fileEvidence){[string]$fileEvidence.Hash}else{''}
                    SignerThumbprint=if($null -ne $signature){[string]$signature.Thumbprint}else{''}
                    ResearchStatus=$finalResearchStatus
                    ResearchLinks=if($null -ne $online){if(@($online.VerifiedLinks).Count -gt 0){@($online.VerifiedLinks)}else{@()}}else{@()}
                    OnlineResearched=($null -ne $online -and [bool]$online.Success)
                    OnlineMatchConfidence=if($null -ne $online){[int]$online.BestScore}else{0}
                    VerifiedSourceCount=if($null -ne $online){[int]$online.VerifiedCount}else{0}
                    ResearchExhausted=$researchTerminal
                }
                $cache[$key]=$cached
                $changed=$true
                $researchedCount++
                if($researchRunResolved){$reviewResolvedCount++}
                $r|Add-Member -NotePropertyName ResearchRunDisposition -NotePropertyValue 'Researched' -Force
                $r|Add-Member -NotePropertyName ResearchRunResolved -NotePropertyValue ([bool]$researchRunResolved) -Force
                $r|Add-Member -NotePropertyName ResearchRunOnline -NotePropertyValue ([bool]$onlineSucceeded) -Force
                if($researchErrorState) {
                    # Error state was recorded above; do not claim Unknown or Organized.
                } elseif([string]$placement.Placement -eq 'Unknown / Quarantine for Review') {
                    Set-YumResearchStatus -Key $key -Name ([string]$r.Name) -Stage 'Unknown' -Index $queueIndex -Total $totalRecords -Confidence ([int]$placement.Confidence) -Placement ([string]$placement.Placement) -Message 'Research completed without enough evidence to safely identify the item.'
                    Add-YumResearchHistory -Key $key -Name ([string]$r.Name) -Stage 'Unknown' -Message 'Research completed but identity remained unresolved.' -Confidence ([int]$placement.Confidence) -Placement ([string]$placement.Placement)
                } elseif(Test-YumResearchTerminalResult -PlacementResult $placement) {
                    Set-YumResearchStatus -Key $key -Name ([string]$r.Name) -Stage 'Organized' -Index $queueIndex -Total $totalRecords -Confidence ([int]$placement.Confidence) -Placement ([string]$placement.Placement) -Message ('Automatically organized as {0}.' -f [string]$placement.Placement)
                    Add-YumResearchHistory -Key $key -Name ([string]$r.Name) -Stage 'Organized' -Message ('Automatically organized as {0}.' -f [string]$placement.Placement) -Confidence ([int]$placement.Confidence) -Placement ([string]$placement.Placement)
                } else {
                    # Automatic Research is terminal: never leave a completed record in the active Review queue.
                    $placement=[pscustomobject]@{
                        Placement='Unknown / Quarantine for Review'
                        ActionLane='Never manage automatically'
                        Confidence=[int][math]::Min(45,[int]$placement.Confidence)
                        ResearchReason=('Research completed but corroboration remained insufficient; original placement: {0}.' -f [string]$placement.Placement)
                        EvidenceSources=@($placement.EvidenceSources)+'Research completed; corroboration insufficient; quarantined'
                        ResearchLinks=@($placement.ResearchLinks)
                        Scores=$placement.Scores
                    }
                    $r|Add-Member -NotePropertyName Placement -NotePropertyValue $placement.Placement -Force
                    $r|Add-Member -NotePropertyName ActionLane -NotePropertyValue $placement.ActionLane -Force
                    $r|Add-Member -NotePropertyName ResearchConfidence -NotePropertyValue $placement.Confidence -Force
                    $r|Add-Member -NotePropertyName ResearchStatus -NotePropertyValue 'Unknown' -Force
                    $r|Add-Member -NotePropertyName ResearchComplete -NotePropertyValue $true -Force
                    $r|Add-Member -NotePropertyName ResearchExhausted -NotePropertyValue $true -Force
                    $r|Add-Member -NotePropertyName ResearchRunResolved -NotePropertyValue $false -Force
                    $r|Add-Member -NotePropertyName ResearchReason -NotePropertyValue $placement.ResearchReason -Force
                    Set-YumResearchStatus -Key $key -Name ([string]$r.Name) -Stage 'Unknown' -Index $queueIndex -Total $totalRecords -Confidence ([int]$placement.Confidence) -Placement $placement.Placement -Message 'Research completed but corroboration was insufficient; item was terminally quarantined.'
                    Add-YumResearchHistory -Key $key -Name ([string]$r.Name) -Stage 'Unknown' -Message 'Research completed but corroboration was insufficient; item was terminally quarantined instead of remaining queued.' -Confidence ([int]$placement.Confidence) -Placement $placement.Placement
                }
                $delayMs=125
                try{if($null -ne $script:Yum.Config.PSObject.Properties['ResearchInterItemDelayMs']){$delayMs=[math]::Max(0,[int]$script:Yum.Config.ResearchInterItemDelayMs)}}catch{}
                if($delayMs -gt 0 -and $queueIndex -lt $totalRecords){Start-Sleep -Milliseconds $delayMs}
            }

            if($null -eq $placement){
                if($null -ne $cached){$placement=$cached}
                else{$placement=Get-YumResearchPlacement -Name ([string]$r.Name) -Path ([string]$r.Path) -Publisher ([string]$r.Publisher) -Product '' -Signature '' -AppxEvidence @() -Category ([string]$r.Category) -Risk ([string]$r.Risk) -Reason ([string]$r.Reason)}
            }

            foreach($p in @('Placement','ActionLane','ResearchReason')){
                if($null -ne $placement.PSObject.Properties[$p]){$r|Add-Member -NotePropertyName $p -NotePropertyValue ([string]$placement.$p) -Force}
            }
            if($null -ne $placement.PSObject.Properties['Confidence']){$r|Add-Member -NotePropertyName ResearchConfidence -NotePropertyValue ([int]$placement.Confidence) -Force}
            if($null -ne $placement.PSObject.Properties['EvidenceSources']){$r|Add-Member -NotePropertyName ResearchSources -NotePropertyValue @($placement.EvidenceSources) -Force}
            if($null -ne $placement.PSObject.Properties['ResearchLinks']){$r|Add-Member -NotePropertyName ResearchLinks -NotePropertyValue @($placement.ResearchLinks) -Force}
            elseif($null -ne $cached -and $null -ne $cached.PSObject.Properties['ResearchLinks']){$r|Add-Member -NotePropertyName ResearchLinks -NotePropertyValue @($cached.ResearchLinks) -Force}
            # Keep the UI-facing signature field explicit.  The raw signer object is not a stable UI contract.
            $signatureDisplay='Unknown'
            try {
                $sigObj=$signature
                if($null -eq $sigObj -and $null -ne $cached -and $null -ne $cached.PSObject.Properties['Signature']){$sigObj=Get-YumResearchSafeProperty -Object $cached -Name 'Signature' -Default $null}
                if($null -ne $sigObj){
                    $sigStatus=[string]$sigObj.Status
                    $sigSigner=[string]$sigObj.Signer
                    if(-not [string]::IsNullOrWhiteSpace($sigSigner) -and -not [string]::IsNullOrWhiteSpace($sigStatus)){$signatureDisplay=('{0} — {1}' -f $sigStatus,$sigSigner)}
                    elseif(-not [string]::IsNullOrWhiteSpace($sigStatus)){$signatureDisplay=$sigStatus}
                    elseif(-not [string]::IsNullOrWhiteSpace([string]$sigObj)){$signatureDisplay=[string]$sigObj}
                }
            } catch {}
            $r|Add-Member -NotePropertyName Signature -NotePropertyValue $signatureDisplay -Force

            # Manual overrides always win. Automatic research may change only non-manual classifications.
            if(-not $manual -and $null -ne $placement.PSObject.Properties['Placement']){
                $newRisk='Unknown'
                $newPlacement=[string]$placement.Placement
                switch($newPlacement){
                    'Security' {$newRisk='Protected'}
                    'Windows System Components' {$newRisk='Protected'}
                    'Drivers / Hardware' {$newRisk='Protected'}
                    'Games / Gaming' {$newRisk='Protected'}
                    'User Background Apps' { if([int]$placement.Confidence -ge 80 -and ([string]$placement.ActionLane -notmatch 'Review')){$newRisk='Candidate'}else{$newRisk='Review'} }
                    'Identified Applications' { if([int]$placement.Confidence -ge 80 -and ([string]$placement.ActionLane -notmatch 'Review')){$newRisk='Candidate'}else{$newRisk='Review'} }
                    'Startup Inventory' {$newRisk='Review'}
                    'Review Queue' {$newRisk='Review'}
                    'Unknown / Quarantine for Review' {$newRisk='Unknown'}
                    default {$newRisk='Unknown'}
                }
                $r|Add-Member -NotePropertyName Risk -NotePropertyValue $newRisk -Force
            }

            # Make the UI/inventory section follow the research decision, not only the display Placement.
            if(-not $manual -and $null -ne $placement -and $null -ne $placement.PSObject.Properties['Placement']){
                $resolvedCategory=[string]$placement.Placement
                switch($resolvedCategory){
                    'Security' {$resolvedCategory='Security'}
                    'Windows System Components' {$resolvedCategory='Windows System Components'}
                    'Drivers / Hardware' {$resolvedCategory='Drivers / Hardware'}
                    'Games / Gaming' {$resolvedCategory='Games / Gaming'}
                    'User Background Apps' {$resolvedCategory='User Background Apps'}
                    'Identified Applications' {$resolvedCategory='Identified Applications'}
                    'Startup Inventory' {$resolvedCategory='Startup Inventory'}
                    'Unknown / Quarantine for Review' {$resolvedCategory='Unknown / Quarantine'}
                    'Review Queue' {$resolvedCategory='Review Queue'}
                    default {$resolvedCategory='Unknown / Quarantine'}
                }
                $r|Add-Member -NotePropertyName Category -NotePropertyValue $resolvedCategory -Force
            }
            # Publish the single authoritative research state to the record before persistence/UI merge.
            $r|Add-Member -NotePropertyName ResearchComplete -NotePropertyValue ([bool]$researchTerminal) -Force
            $r|Add-Member -NotePropertyName ResearchPerformed -NotePropertyValue ([bool]($didResearch -or ($null -ne $cached))) -Force
            $r|Add-Member -NotePropertyName ResearchStatus -NotePropertyValue $finalResearchStatus -Force
            $r|Add-Member -NotePropertyName OnlineResearchPerformed -NotePropertyValue ([bool]($onlineSucceeded -or ($null -ne $cached -and $cached.PSObject.Properties['OnlineResearched'] -and [bool]$cached.OnlineResearched))) -Force
            $r|Add-Member -NotePropertyName ResearchExhausted -NotePropertyValue ([bool]$researchTerminal) -Force
            if($null -ne $cached -and $null -ne $cached.PSObject.Properties['EvidenceFingerprint']){$r|Add-Member -NotePropertyName ResearchEvidenceFingerprint -NotePropertyValue ([string]$cached.EvidenceFingerprint) -Force}
            $r|Add-Member -NotePropertyName ResearchCompletedAt -NotePropertyValue $(if($researchTerminal){(Get-Date).ToString('o')}else{''}) -Force
            # 5.4: remember which engine decided this, so a better engine can revisit old Unknown results.
            if($researchTerminal){$r|Add-Member -NotePropertyName ResearchEngineVersion -NotePropertyValue ([string]$script:Yum.Config.ResearchEngineVersion) -Force}
            $r|Add-Member -NotePropertyName ResearchDecision -NotePropertyValue ([string]$placement.Placement) -Force
            if($null -ne $placement.PSObject.Properties['OnlineMatchConfidence']){$r|Add-Member -NotePropertyName OnlineMatchConfidence -NotePropertyValue ([int]$placement.OnlineMatchConfidence) -Force}
            if($null -ne $placement.PSObject.Properties['VerifiedSourceCount']){$r|Add-Member -NotePropertyName VerifiedSourceCount -NotePropertyValue ([int]$placement.VerifiedSourceCount) -Force}
        } catch {
            $errText=[string]$_.Exception.Message
            $errType=[string]$_.Exception.GetType().FullName
            $stageText='Research pipeline'
            try{if($null -ne $script:Yum.ResearchStatus -and $script:Yum.ResearchStatus.Stage){$stageText=[string]$script:Yum.ResearchStatus.Stage}}catch{}
            try{Write-YumLogException -Context ('Research item failed [{0}] for {1}' -f $stageText,[string]$r.Name) -Exception $_.Exception}catch{}
            Write-YumResearchDiagnostic -RunId $RunId -Stage $stageText -Name ([string]$r.Name) -Key ([string]$r.Key) -Message 'Research item failed' -Exception $_.Exception
            try{Set-YumResearchStatus -Key $key -Name ([string]$r.Name) -Stage 'Research Error' -Index $queueIndex -Total $totalRecords -Message ('Research failed in {0}; item remains queued for retry.' -f $stageText) -Error $errText}catch{}
            # Preserve the best known placement rather than blanking the record.
            try {
                if($null -eq $placement){
                    $placement=[pscustomobject]@{Placement='Review Queue';ActionLane='Review before management';Confidence=[int]$r.ResearchConfidence;ResearchReason=('Research failed in {0}: {1}' -f $stageText,$errText);EvidenceSources=@();ResearchLinks=@();Scores=@{}}
                }
                $r|Add-Member -NotePropertyName Placement -NotePropertyValue 'Unknown / Quarantine for Review' -Force
                $r|Add-Member -NotePropertyName ActionLane -NotePropertyValue 'Never manage automatically' -Force
                $r|Add-Member -NotePropertyName ResearchConfidence -NotePropertyValue ([int]$placement.Confidence) -Force
                $r|Add-Member -NotePropertyName ResearchSources -NotePropertyValue @($placement.EvidenceSources) -Force
                $r|Add-Member -NotePropertyName ResearchLinks -NotePropertyValue @($placement.ResearchLinks) -Force
                $r|Add-Member -NotePropertyName ResearchStatus -NotePropertyValue 'Research Error' -Force
                $r|Add-Member -NotePropertyName ResearchComplete -NotePropertyValue $true -Force
                $r|Add-Member -NotePropertyName ResearchPerformed -NotePropertyValue ([bool]$didResearch) -Force
                $r|Add-Member -NotePropertyName ResearchExhausted -NotePropertyValue $true -Force
                $r|Add-Member -NotePropertyName ResearchReason -NotePropertyValue ('Research failed in {0} [{1}]: {2}; item was terminally quarantined for diagnostics/retry.' -f $stageText,$errType,$errText) -Force
                $r|Add-Member -NotePropertyName ResearchErrorState -NotePropertyValue (('{0}: {1}' -f $errType,$errText)) -Force
                $r|Add-Member -NotePropertyName ResearchRunDisposition -NotePropertyValue 'Error' -Force
            } catch {}
        }
        # Final object contract: the UI must never receive a record without research-state properties.
        try {
            if($null -eq $r.PSObject.Properties['ResearchStatus']){$r|Add-Member -NotePropertyName ResearchStatus -NotePropertyValue 'Not Researched' -Force}
            if($null -eq $r.PSObject.Properties['ResearchErrorState']){$r|Add-Member -NotePropertyName ResearchErrorState -NotePropertyValue '' -Force}
            if($null -eq $r.PSObject.Properties['ResearchComplete']){$r|Add-Member -NotePropertyName ResearchComplete -NotePropertyValue $false -Force}
            if($null -eq $r.PSObject.Properties['ResearchPerformed']){$r|Add-Member -NotePropertyName ResearchPerformed -NotePropertyValue ([bool]$didResearch) -Force}
            if($null -eq $r.PSObject.Properties['ResearchExhausted']){$r|Add-Member -NotePropertyName ResearchExhausted -NotePropertyValue $false -Force}
            if($null -eq $r.PSObject.Properties['ResearchConfidence']){$r|Add-Member -NotePropertyName ResearchConfidence -NotePropertyValue 0 -Force}
            if($null -eq $r.PSObject.Properties['ResearchSources']){$r|Add-Member -NotePropertyName ResearchSources -NotePropertyValue @() -Force}
            if($null -eq $r.PSObject.Properties['ResearchLinks']){$r|Add-Member -NotePropertyName ResearchLinks -NotePropertyValue @() -Force}
            if($null -eq $r.PSObject.Properties['ResearchRunDisposition']){$r|Add-Member -NotePropertyName ResearchRunDisposition -NotePropertyValue 'Unchanged' -Force}
            if($null -eq $r.PSObject.Properties['ResearchRunResolved']){$r|Add-Member -NotePropertyName ResearchRunResolved -NotePropertyValue $false -Force}
            if($null -eq $r.PSObject.Properties['ResearchRunOnline']){$r|Add-Member -NotePropertyName ResearchRunOnline -NotePropertyValue $false -Force}
            if($null -eq $r.PSObject.Properties['ResearchEvidenceFingerprint']){$r|Add-Member -NotePropertyName ResearchEvidenceFingerprint -NotePropertyValue '' -Force}
            if($null -eq $r.PSObject.Properties['ResearchCompletedAt']){$r|Add-Member -NotePropertyName ResearchCompletedAt -NotePropertyValue '' -Force}
            if($null -eq $r.PSObject.Properties['ResearchDecision']){$r|Add-Member -NotePropertyName ResearchDecision -NotePropertyValue '' -Force}
        } catch {}
        [void]$out.Add($r)
        if($changed){[void](Save-YumResearchCache -Cache $cache);$changed=$false}
        Write-YumResearchLiveSnapshot -RunId $RunId -Completed $queueIndex -Total $totalRecords -Records $out.ToArray()
    }
    if($changed){[void](Save-YumResearchCache -Cache $cache);$changed=$false}
    Write-YumResearchDiagnostic -RunId $RunId -Stage 'QueueComplete' -Message ('Research queue complete: researched={0}; cached={1}; resolved={2}; unknown={3}; errors={4}' -f $researchedCount,$cachedCount,$reviewResolvedCount,$unknownCount,@($out|Where-Object{[string]$_.ResearchStatus -eq 'Research Error'}).Count)
    Set-YumResearchStatus -Key '' -Name 'Review Research Queue' -Stage 'Complete' -Index $totalRecords -Total $totalRecords -Message ('Research queue complete: {0} researched; {1} resolved from Review; {2} unresolved → Unknown; {3} research errors pending retry.' -f $researchedCount,$reviewResolvedCount,$unknownCount,@($out|Where-Object{[string]$_.ResearchStatus -eq 'Research Error'}).Count)
    [pscustomobject]@{
        Records=$out.ToArray()
        ResearchedCount=$researchedCount
        CachedCount=$cachedCount
        OnlineResearchCount=$onlineCount
        ReviewResolvedCount=$reviewResolvedCount
        UnknownCount=$unknownCount
        ResearchErrorCount=@($out|Where-Object{[string]$_.ResearchStatus -eq 'Research Error'}).Count
        CacheCount=$cache.Count
        OnlineEnabled=[bool]$script:Yum.Config.EnableOnlineResearch
        LocalClassificationComplete=$true
        ReviewQueueCompleted=$true
    }
}
