#requires -Version 5.1

function Test-YumNameMatchesAny {
    param([string]$Name,[string[]]$Names)
    if ([string]::IsNullOrWhiteSpace($Name)) { return $false }
    $clean = $Name -replace '\.exe$',''
    foreach($n in @($Names)) { if($clean -ieq ([string]$n -replace '\.exe$','')) { return $true } }
    return $false
}

function Get-YumIntelligenceClassification {
    param(
        [Parameter(Mandatory=$true)]$Process,
        [object]$Identity,
        [int]$ForegroundPid=0,
        [int]$GamePid=0,
        [double]$Cpu=0,
        [double]$MemoryMB=0,
        [switch]$ServiceContext
    )
    $name=[string]$Process.ProcessName
    $path=[string](Get-YumSafePropertyValue -Object $Identity -Name 'Path' -Default '')
    $company=[string](Get-YumSafePropertyValue -Object $Identity -Name 'Company' -Default '')
    $signature=[string](Get-YumSafePropertyValue -Object $Identity -Name 'Signature' -Default '')
    $product=[string](Get-YumSafePropertyValue -Object $Identity -Name 'Product' -Default '')
    $publisher=[string](Get-YumSafePropertyValue -Object $Identity -Name 'Publisher' -Default '')
    $hasPath=(-not [string]::IsNullOrWhiteSpace($path) -and (Test-Path -LiteralPath $path -PathType Leaf))
    $hasPublisher=(-not [string]::IsNullOrWhiteSpace($publisher) -and $publisher -ne 'Unknown')
    $signatureKnown=($signature -in @('Valid','NotSigned','HashMismatch','Unknown','NotTrusted','UnknownError'))
    $lowerPath=$path.ToLowerInvariant()
    $isProtected=$false
    try { $isProtected=Test-YumProtectedProcess -Process $Process -ForegroundPid $ForegroundPid -GamePid $GamePid } catch { $isProtected=$true }
    $isGame=($GamePid -gt 0 -and [int]$Process.Id -eq $GamePid)
    $knownGame=Test-YumNameMatchesAny -Name $name -Names @($script:Yum.Config.KnownGames)
    $gamePath=($lowerPath -match '\\steamapps\\common\\|\\epic games\\|\\riot games\\|\\battle\.net\\|\\ubisoft game launcher\\|\\games\\')
    $gameCompany=($company -match 'Valve|Epic Games|Riot Games|Ubisoft|Electronic Arts|EA|Activision|Blizzard|Bethesda|CD PROJEKT|Rockstar|Take-Two|Bungie|Respawn|NVIDIA')
    $isGameRelated=($isGame -or $knownGame -or $gamePath -or ($gameCompany -and $product -match 'Game|Launcher|Client'))
    $isOptional=Test-YumOptionalBackgroundProcess -Name $name
    $windowsCore=($company -match '^Microsoft' -or $company -match 'Microsoft Corporation' -or $lowerPath -like 'c:\\windows\\*')
    $security=($name -match 'MsMpEng|SecurityHealth|Defender|Malwarebytes|CrowdStrike|Sentinel|ESET|Bitdefender|Avast|AVG|Sophos|McAfee|Webroot' -or $company -match 'Microsoft.*Security|Microsoft Defender|CrowdStrike|SentinelOne|ESET|Bitdefender|Sophos|McAfee')
    $driverOrHardware=($lowerPath -match '\\system32\\drivers\\|\\program files\\.*(nvidia|amd|intel|realtek|logitech)' -or $company -match 'NVIDIA|Advanced Micro Devices|AMD|Intel|Realtek|Logitech|Corsair')
    $launcher=($name -match 'Steam|Epic|EADesktop|Battle\.net|RiotClient|Ubisoft|GOGGalaxy|GalaxyClient|XboxPcApp|GameBar')
    $identityMissing=(-not $hasPath -and -not $hasPublisher -and $signature -eq 'Unknown')
    $unsignedUnknown=($hasPath -and -not $hasPublisher -and ($signature -in @('NotSigned','Unknown','UnknownError')))
    $invalidSignature=($hasPath -and -not $hasPublisher -and ($signature -in @('HashMismatch','NotTrusted')))
    $unknown=($identityMissing -or $unsignedUnknown -or $invalidSignature)

    if($isProtected -or $security -or $driverOrHardware -or $windowsCore) {
        return [pscustomobject]@{Category=if($security){'Security'}elseif($driverOrHardware){'Driver / Hardware'}else{'Windows System'};Risk='Protected';Recommendation='Never manage automatically';Confidence=98;Reason=if($security){'Security component detected'}elseif($driverOrHardware){'Driver or hardware component detected'}else{'Windows/system component detected'}}
    }
    if($isGameRelated -or $launcher) {
        return [pscustomobject]@{Category=if($isGameRelated -and $isGame){'Active Game'}elseif($launcher){'Game Launcher'}else{'Game Related'};Risk='Protected';Recommendation=if($isGame){'Protect while running'}else{'Leave available for gaming'};Confidence=95;Reason='Game or game-launcher indicators detected'}
    }
    if($isOptional) {
        return [pscustomobject]@{Category='Apps';Risk='Safe to Manage';Recommendation='Manage when RAM pressure is high';Confidence=92;Reason='Known optional background application'}
    }
    if($unknown) {
        $reason='Identity evidence is insufficient for automatic cleanup'
        if($unsignedUnknown){$reason='Executable is unsigned and publisher identity is unavailable'}
        elseif($invalidSignature){$reason='Executable signature is not trusted or does not match publisher evidence'}
        elseif($identityMissing){$reason='Executable path, publisher, and signature identity are unavailable'}
        return [pscustomobject]@{Category='Unknown';Risk='Unknown';Recommendation='Research before automatic cleanup';Confidence=25;Reason=$reason;IdentityState='Unknown';AutoResearchEligible=$true}
    }
    if($signature -eq 'NotSigned' -and -not $hasPublisher) {
        return [pscustomobject]@{Category='Unknown';Risk='Unknown';Recommendation='Research before automatic cleanup';Confidence=30;Reason='Unsigned executable with no publisher identity';IdentityState='Unsigned';AutoResearchEligible=$true}
    }
    if($ServiceContext) {
        return [pscustomobject]@{Category='Windows Service';Risk='Review';Recommendation='Require explicit approval';Confidence=70;Reason='Running service requires dependency-aware review'}
    }
    $idle=($Cpu -lt 0.5)
    $largeMemory=($MemoryMB -ge 250)
    if($idle -and $largeMemory) {
        return [pscustomobject]@{Category='Apps';Risk='Candidate';Recommendation='Manage only when needed';Confidence=80;Reason='Idle process with meaningful working-set usage'}
    }
    return [pscustomobject]@{Category='Apps';Risk='Review';Recommendation='Leave running unless user-approved';Confidence=75;Reason='Normal user application; no safe automatic action established'}
}


function Get-YumManualOrganizationPath {
    if($null -ne $script:Yum -and $null -ne $script:Yum.ConfigDirectory){return (Join-Path $script:Yum.ConfigDirectory 'manual-organizations.json')}
    return (Join-Path $script:Yum.Root 'manual-organizations.json')
}
function Get-YumRecordIdentityFields {
    param([Parameter(Mandatory=$true)]$Item)
    $fileHash='';$signerThumbprint=''
    try {if($null -ne $Item.PSObject.Properties['FileHash']){$fileHash=[string]$Item.FileHash}} catch {}
    try {if($null -ne $Item.PSObject.Properties['SignerThumbprint']){$signerThumbprint=[string]$Item.SignerThumbprint}} catch {}
    return [pscustomobject]@{FileHash=$fileHash;SignerThumbprint=$signerThumbprint}
}
function Get-YumManualOrganizationKey {
    param([string]$Name,[string]$Path,[string]$Publisher,[string]$FileHash='', [string]$SignerThumbprint='')
    $identityPath=([string]$Path).Trim().ToLowerInvariant();$hash=([string]$FileHash).Trim().ToLowerInvariant();$signer=([string]$SignerThumbprint).Trim().ToLowerInvariant();$nameText=([string]$Name).Trim().ToLowerInvariant();$publisherText=([string]$Publisher).Trim().ToLowerInvariant()
    if(-not [string]::IsNullOrWhiteSpace($hash) -or -not [string]::IsNullOrWhiteSpace($signer)){$norm=('exe|{0}|{1}|{2}|{3}' -f $identityPath,$hash,$signer,$nameText)}else{$norm=('legacy|{0}|{1}|{2}' -f $nameText,$identityPath,$publisherText)}
    $sha=[System.Security.Cryptography.SHA256]::Create();try{return ([System.BitConverter]::ToString($sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($norm))).Replace('-','')).ToLowerInvariant()}finally{$sha.Dispose()}
}
function Get-YumManualOrganizationsFromObject {
    param($Object)
    $h=@{}
    try {
        $items=$null
        if($null -ne $Object -and $null -ne $Object.PSObject.Properties['Items']) {
            $items=$Object.Items
        } elseif($null -ne $Object) {
            $items=$Object
        }
        if($items -is [hashtable]) { foreach($k in $items.Keys){$h[[string]$k]=$items[$k]} }
        else { foreach($p in @($items.PSObject.Properties)){ $h[[string]$p.Name]=$p.Value } }
    } catch {}
    return $h
}
function Load-YumManualOrganizations {
    param([switch]$Force)
    try {
        $path=Get-YumManualOrganizationPath
        $stamp=[datetime]::MinValue
        if(Test-Path -LiteralPath $path){$stamp=(Get-Item -LiteralPath $path -ErrorAction Stop).LastWriteTimeUtc}
        if(-not $Force -and $null -ne $script:Yum.ManualOrganizationsCache -and [string]$script:Yum.ManualOrganizationsCachePath -eq [string]$path -and $script:Yum.ManualOrganizationsCacheStampUtc -eq $stamp){return $script:Yum.ManualOrganizationsCache}
        if(Test-Path -LiteralPath $path){
            $raw=Get-Content -LiteralPath $path -Raw -ErrorAction Stop
            $obj=$raw|ConvertFrom-Json -ErrorAction Stop
            $h=Get-YumManualOrganizationsFromObject -Object $obj
            $script:Yum.ManualOrganizationsCache=$h
            $script:Yum.ManualOrganizationsCachePath=$path
            $script:Yum.ManualOrganizationsCacheStampUtc=$stamp
            return $h
        }
        $script:Yum.ManualOrganizationsCache=@{}
        $script:Yum.ManualOrganizationsCachePath=$path
        $script:Yum.ManualOrganizationsCacheStampUtc=$stamp
        return $script:Yum.ManualOrganizationsCache
    } catch {try{Write-YumLogException -Context 'Manual organization load failed' -Exception $_.Exception}catch{}}
    return @{}
}
function Save-YumManualOrganizations {
    param([hashtable]$Organizations)
    try{
        $path=Get-YumManualOrganizationPath
        $dir=Split-Path -Parent $path
        if(-not(Test-Path -LiteralPath $dir)){New-Item -ItemType Directory -Path $dir -Force|Out-Null}
        $tmp="$path.tmp"
        [ordered]@{Version='1';Updated=(Get-Date).ToString('o');Items=$Organizations}|ConvertTo-Json -Depth 8|Set-Content -LiteralPath $tmp -Encoding UTF8
        Move-Item -LiteralPath $tmp -Destination $path -Force
        $script:Yum.ManualOrganizationsCache=@{}; foreach($k in $Organizations.Keys){$script:Yum.ManualOrganizationsCache[[string]$k]=$Organizations[$k]}
        $script:Yum.ManualOrganizationsCachePath=$path
        $script:Yum.ManualOrganizationsCacheStampUtc=(Get-Item -LiteralPath $path -ErrorAction SilentlyContinue).LastWriteTimeUtc
        if($script:Yum.PSObject.Properties['IntelligenceViewRevision']){$script:Yum.IntelligenceViewRevision++}
        return $true
    }catch{try{Write-YumLogException -Context 'Manual organization save failed' -Exception $_.Exception}catch{};return $false}
}
function Set-YumManualOrganization {
    param([Parameter(Mandatory)]$Item,[Parameter(Mandatory)][string]$Category,[Parameter(Mandatory)][string]$Placement,[Parameter(Mandatory)][string]$ActionLane)
    $orgs=Load-YumManualOrganizations
    $identity=Get-YumRecordIdentityFields -Item $Item;$key=Get-YumManualOrganizationKey -Name ([string]$Item.Name) -Path ([string]$Item.Path) -Publisher ([string]$Item.Publisher) -FileHash $identity.FileHash -SignerThumbprint $identity.SignerThumbprint
    $risk=switch($Category){'Security'{'Protected'};'Drivers / Hardware'{'Protected'};'Games / Gaming'{'Protected'};'Unknown / Quarantine'{'Unknown'};'Review Queue'{'Review'};'Startup Inventory'{'Review'};default{'Candidate'}}
    $org=[pscustomobject]@{Key=$key;Name=[string]$Item.Name;Path=[string]$Item.Path;Publisher=[string]$Item.Publisher;Category=$Category;Placement=$Placement;ActionLane=$ActionLane;Risk=$risk;Updated=(Get-Date).ToString('o');Source='Manual User Organization'}
    $orgs[$key]=$org
    if(-not (Save-YumManualOrganizations -Organizations $orgs)){throw 'Manual organization could not be saved.'}
    return $org
}
function Get-YumManualOrganization {
    param([Parameter(Mandatory)]$Item)
    $orgs=Load-YumManualOrganizations;$identity=Get-YumRecordIdentityFields -Item $Item;$key=Get-YumManualOrganizationKey -Name ([string]$Item.Name) -Path ([string]$Item.Path) -Publisher ([string]$Item.Publisher) -FileHash $identity.FileHash -SignerThumbprint $identity.SignerThumbprint
    if($orgs.ContainsKey($key)){return $orgs[$key]}
    # Migrate a legacy name/path/publisher override when a stronger executable identity is now available.
    $legacyKey=Get-YumManualOrganizationKey -Name ([string]$Item.Name) -Path ([string]$Item.Path) -Publisher ([string]$Item.Publisher)
    if($orgs.ContainsKey($legacyKey)) {
        $legacy=$orgs[$legacyKey];$orgs[$key]=$legacy;$orgs.Remove($legacyKey);[void](Save-YumManualOrganizations -Organizations $orgs);return $legacy
    }
    return $null
}
function Apply-YumManualOrganizationToRecord {
    param([Parameter(Mandatory)]$Record)
    $org=Get-YumManualOrganization -Item $Record
    if($null -eq $org){return $Record}
    foreach($pair in @(@('Category',[string]$org.Category),@('Placement',[string]$org.Placement),@('ActionLane',[string]$org.ActionLane),@('Risk',[string]$org.Risk),@('ManualOverride',$true),@('ManualOrganizationUpdated',[string]$org.Updated),@('Recommendation',[string]$org.ActionLane))){try{if($null -eq $Record.PSObject.Properties[$pair[0]]){$Record|Add-Member -NotePropertyName $pair[0] -NotePropertyValue $pair[1]}else{$Record.($pair[0])=$pair[1]}}catch{}}
    return $Record
}
function Ensure-YumIntelligenceRecordSchema {
    param([Parameter(Mandatory=$true)]$Record)
    $defaults=[ordered]@{
        Key=''
        StableIdentityKey=''
        Name=''
        Category='Apps'
        Placement=''
        Risk='Review'
        Recommendation='Leave running unless user-approved'
        ActionLane='Review before management'
        ManualOverride=$false
        ManualOrganizationUpdated=''
        ResearchStatus='Not Researched'
        ResearchComplete=$false
        ResearchPerformed=$false
        ResearchExhausted=$false
        ResearchConfidence=0
        ResearchSources=@()
        ResearchLinks=@()
        ResearchReason='Awaiting manual research.'
        ResearchErrorState=''
        ResearchStarted=''
        ResearchCompleted=''
        OnlineResearchPerformed=$false
        ResearchRunDisposition='Unchanged'
        ResearchRunResolved=$false
        ResearchRunOnline=$false
        Publisher='Unknown'
        Path=''
        Product=''
        Version=''
        FileHash=''
        SignerThumbprint=''
        Signature='Unknown'
        IdentityState='Unknown'
        IdentityConfidence=0
        UnknownReason=''
        AutoResearchEligible=$false
        Confidence=0
        ConfidenceText='0%'
        StateText='LIVE'
        Source='Process'
        LastSeen=''
        Live=$true
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

function Apply-YumManualOrganizations {
    param([object[]]$Records=@())
    foreach($record in @($Records)){if($null -ne $record){[void](Apply-YumManualOrganizationToRecord -Record $record)}}
    return @($Records)
}


function Get-YumIntelligenceDbPath {
    if($null -ne $script:Yum -and $null -ne $script:Yum.IntelligenceDbFile){return [string]$script:Yum.IntelligenceDbFile}
    return (Join-Path $script:Yum.Root 'intelligence-db.json')
}

function Load-YumIntelligenceDb {
    try {
        $path=Get-YumIntelligenceDbPath
        if(Test-Path -LiteralPath $path){
            $raw=Get-Content -LiteralPath $path -Raw -ErrorAction Stop
            if(-not [string]::IsNullOrWhiteSpace($raw)){
                $obj=$raw | ConvertFrom-Json -ErrorAction Stop
                $items=$null
                if($null -ne $obj){
                    $prop=$obj.PSObject.Properties['Items']
                    if($null -ne $prop){
                        $items=$prop.Value
                    } elseif($obj -is [System.Collections.IEnumerable] -and -not ($obj -is [string])) {
                        $items=$obj
                    }
                }
                if($null -ne $items){
                    $h=@{}
                    foreach($i in @($items)){
                        try {
                            if($null -eq $i){continue}
                            [void](Ensure-YumIntelligenceRecordSchema -Record $i)
                            $key=Get-YumStableIntelligenceKey -Record $i
                            if([string]::IsNullOrWhiteSpace($key)){$key=[string]$i.Key}
                            if(-not [string]::IsNullOrWhiteSpace($key)){$i.Key=$key;$h[$key]=$i}
                        } catch {
                            try { Write-YumLogException -Context 'Intelligence database record normalization failed' -Exception $_.Exception } catch {}
                        }
                    }
                    $script:Yum.IntelligenceDb=$h
                    return $h
                }
            }
        }
    } catch { try { Write-YumLogException -Context 'Intelligence database load failed' -Exception $_.Exception } catch {} }
    $script:Yum.IntelligenceDb=@{}
    return $script:Yum.IntelligenceDb
}

function Clear-YumIntelligenceDb {
    try {
        $path=Get-YumIntelligenceDbPath
        $script:Yum.IntelligenceDb=@{}
        if(Test-Path -LiteralPath $path){Remove-Item -LiteralPath $path -Force -ErrorAction Stop}
        if($script:Yum.PSObject.Properties['IntelligenceViewRevision']){$script:Yum.IntelligenceViewRevision++}
        return $true
    } catch {
        try { Write-YumLogException -Context 'Intelligence database clear failed' -Exception $_.Exception } catch {}
        return $false
    }
}

function Save-YumIntelligenceDb {
    param([hashtable]$Database)
    try {
        $path=Get-YumIntelligenceDbPath
        $dir=Split-Path -Parent $path
        if(-not (Test-Path -LiteralPath $dir)){New-Item -ItemType Directory -Path $dir -Force | Out-Null}
        $payload=[ordered]@{Version='1';Updated=(Get-Date).ToString('o');Items=@($Database.Values)}
        $tmp="$path.tmp"
        $payload | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $tmp -Encoding UTF8
        Move-Item -LiteralPath $tmp -Destination $path -Force
        if($script:Yum.PSObject.Properties['IntelligenceViewRevision']){$script:Yum.IntelligenceViewRevision++}
        return $true
    } catch { try { Write-YumLogException -Context 'Intelligence database save failed' -Exception $_.Exception } catch {}; return $false }
}

function Get-YumStableIntelligenceKey {
    param([Parameter(Mandatory=$true)]$Record)
    try {
        if($null -ne $Record.PSObject.Properties['StableIdentityKey'] -and -not [string]::IsNullOrWhiteSpace([string]$Record.StableIdentityKey)){
            return ([string]$Record.StableIdentityKey).Trim().ToLowerInvariant()
        }
    } catch {}
    $source=([string]$Record.Source).Trim().ToLowerInvariant()
    $name=([string]$Record.Name).Trim().ToLowerInvariant()
    $path=([string]$Record.Path).Trim().ToLowerInvariant()
    $publisher=([string]$Record.Publisher).Trim().ToLowerInvariant()
    $package='';$fileHash='';$signer=''
    try{if($null -ne $Record.PSObject.Properties['PackageFullName']){$package=[string]$Record.PackageFullName}}catch{}
    try{if($null -ne $Record.PSObject.Properties['FileHash']){$fileHash=[string]$Record.FileHash}}catch{}
    try{if($null -ne $Record.PSObject.Properties['SignerThumbprint']){$signer=[string]$Record.SignerThumbprint}}catch{}
    $package=$package.Trim().ToLowerInvariant();$fileHash=$fileHash.Trim().ToLowerInvariant();$signer=$signer.Trim().ToLowerInvariant()
    if($source -eq 'process' -and -not [string]::IsNullOrWhiteSpace($path)){
        $norm=('process|{0}|{1}' -f $path,$name)
    } elseif($source -eq 'service') {
        $norm=('service|{0}|{1}' -f $name,$path)
    } elseif($source -eq 'app' -and -not [string]::IsNullOrWhiteSpace($package)) {
        $norm=('app|{0}' -f $package)
    } elseif($source -eq 'startup' -or $source -eq 'startup inventory') {
        $norm=('startup|{0}|{1}' -f $name,$path)
    } else {
        $norm=('generic|{0}|{1}|{2}|{3}|{4}|{5}' -f $source,$name,$path,$publisher,$package,$fileHash)
    }
    $sha=[Security.Cryptography.SHA256]::Create(); try{return ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($norm))).Replace('-','')).ToLowerInvariant()} finally {$sha.Dispose()}
}

function Get-YumIntelligenceDbKey {
    param([string]$Name,[string]$Path,[string]$Publisher)
    $norm=('{0}|{1}|{2}' -f ([string]$Name).ToLowerInvariant(),([string]$Path).ToLowerInvariant(),([string]$Publisher).ToLowerInvariant()).Trim()
    $sha=[System.Security.Cryptography.SHA256]::Create()
    try { return ([System.BitConverter]::ToString($sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($norm))).Replace('-','')).ToLowerInvariant() } finally {$sha.Dispose()}
}

function Save-YumIntelligenceItems {
    param([object[]]$Items=@())
    try {
        if($null -eq $script:Yum.IntelligenceDb){[void](Load-YumIntelligenceDb)}
        $db=$script:Yum.IntelligenceDb
        foreach($i in @($Items)){
            $key=''
            try { $key=Get-YumStableIntelligenceKey -Record $i } catch {}
            if([string]::IsNullOrWhiteSpace($key)){$key=[string]$i.Key}
            if([string]::IsNullOrWhiteSpace($key)){continue}
            $db[$key]=$i
        }
        [void](Save-YumIntelligenceDb -Database $db)
    } catch { try { Write-YumLogException -Context 'Intelligence item save failed' -Exception $_.Exception } catch {} }
}


function Get-YumExecutableIdentity {
    param([Parameter(Mandatory=$true)][string]$Path,[switch]$VerifySignature,[switch]$HashFile)
    $publisher='Unknown';$company='';$product='';$signature='Unknown';$signerThumbprint='';$fileHash=''
    if([string]::IsNullOrWhiteSpace($Path) -or -not(Test-Path -LiteralPath $Path)){return [pscustomobject]@{Path=$Path;Publisher=$publisher;Company=$company;Product=$product;Signature=$signature;SignerThumbprint=$signerThumbprint;FileHash=$fileHash}}
    try{
        $vi=[Diagnostics.FileVersionInfo]::GetVersionInfo($Path)
        $company=[string]$vi.CompanyName;$product=[string]$vi.ProductName
        if(-not [string]::IsNullOrWhiteSpace($company)){$publisher=$company}
    }catch{}
    if($VerifySignature -or $signature -eq 'Unknown'){
        try{
            $sig=Get-AuthenticodeSignature -FilePath $Path -ErrorAction Stop
            $signature=[string]$sig.Status
            if($sig.SignerCertificate){
                if(-not [string]::IsNullOrWhiteSpace([string]$sig.SignerCertificate.Subject)){$publisher=[string]$sig.SignerCertificate.GetNameInfo([Security.Cryptography.X509Certificates.X509NameType]::SimpleName,$false)}
                try{$signerThumbprint=[string]$sig.SignerCertificate.Thumbprint}catch{}
            }
        }catch{}
    }
    if($HashFile){try{$fileHash=(Get-FileHash -LiteralPath $Path -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant()}catch{}}
    [pscustomobject]@{Path=$Path;Publisher=$publisher;Company=$company;Product=$product;Signature=$signature;SignerThumbprint=$signerThumbprint;FileHash=$fileHash}
}

function Get-YumCachedExecutableIdentity {
    param([string]$Path,[switch]$VerifySignature)
    if([string]::IsNullOrWhiteSpace($Path)){return [pscustomobject]@{Path=$Path;Publisher='Unknown';Signature='Unknown';Product='';Company='';SignerThumbprint='';FileHash=''}}
    $key=$null
    try {
        $info=Get-Item -LiteralPath $Path -ErrorAction Stop
        $stamp='{0}|{1}|{2}' -f $Path.ToLowerInvariant(),$info.Length,$info.LastWriteTimeUtc.Ticks
        $key=$stamp
        if($null -eq $script:Yum.IntelligenceIdentityCache){$script:Yum.IntelligenceIdentityCache=@{}}
        if($script:Yum.IntelligenceIdentityCache.Contains($key)){
            $cached=$script:Yum.IntelligenceIdentityCache[$key]
            if(-not $VerifySignature -or [string](Get-YumSafePropertyValue -Object $cached -Name 'Signature' -Default 'Unknown') -ne 'Unknown'){return $cached}
        }
        $id=Get-YumExecutableIdentity -Path $Path -VerifySignature:$VerifySignature
        $script:Yum.IntelligenceIdentityCache[$key]=$id
        return $id
    } catch { return Get-YumExecutableIdentity -Path $Path -VerifySignature:$VerifySignature }
}
