function New-YumRamRuntime {
    [ordered]@{
        Root = $script:Root
        ConfigDirectory = $script:Root
        ConfigFile = $null
        StateFile = $null
        IntelligenceDbFile = $null
        IntelligenceDb = $null
        IntelligenceIdentityCache = @{}
        IntelligenceViewRevision = 0
        ManualOrganizationsCache = $null
        ManualOrganizationsCachePath = ''
        ManualOrganizationsCacheStampUtc = [datetime]::MinValue
        Config = $null
        Window = $null
        Ui = $null
        IntelligenceWindow = $null
        TelemetryTimer = $null
        GpuTimer = $null
        GameTimer = $null
        ControllerTimer = $null
        UiTimer = $null
        StopRequested = $false
        LastCleanup = [datetime]::MinValue
        LastGamePid = 0
        GameWasRunning = $false
        CleanCount = 0
        TotalWorkingSetReduced = [int64]0
        TotalAvailableImprovement = [double]0
        Snapshot = $null
        SnapshotVersion = 0
        GraphMemory = New-Object System.Collections.Generic.List[double]
        GraphMemoryAvailable = New-Object System.Collections.Generic.List[double]
        GraphCPU = New-Object System.Collections.Generic.List[double]
        GraphGPU = New-Object System.Collections.Generic.List[double]
        GraphPointsLimit = 60
        SyncRoot = New-Object object
        SuppressUiEvents = $false
        LastGpuSample = [datetime]::MinValue
        LastGameSample = [datetime]::MinValue
        CleanupRunning = $false
        CleanupCandidateSnapshot = @()
        CleanupCandidateSnapshotKey = ''
        CleanupCandidateSnapshotUtc = [datetime]::MinValue
        SingleInstanceMutex = $null
        SingleInstanceOwned = $false
        StoppedOptionalServices = New-Object System.Collections.Generic.List[string]
        CacheLock = New-Object object
        LogLock = New-Object object
        CleanupLock = New-Object object
        RequestLock = New-Object object
        CleanupRequested = $false
        CleanupForceRequested = $false
        CleanupSafeOnlyRequested = $false
        CleanupOneShotController = $false
        CleanupResult = $null
        CleanupResultVersion = 0
        LastControllerClean = [datetime]::MinValue
        LastTelemetryUpdate = [datetime]::MinValue
        LastCoreTelemetryUpdate = [datetime]::MinValue
        LastTelemetryCycle = [datetime]::MinValue
        TelemetryErrorCount = 0
        TelemetrySuccessCount = 0
        ScanResult = $null
        ScanResultVersion = 0
        CpuCounter = $null
        BrushCache = @{}
        GPUColor = '#B7E3FF'
        GraphInitialized = $false
        GraphMemoryLine = $null
        GraphMemoryAvailableLine = $null
        GraphCPULine = $null
        GraphGPULine = $null
        LastUiCleanupResultVersion = 0
        LastUiSnapshotVersion = 0
        ProcessCleanupTimes = @{}
        ProcessCpuMapCache = @{}
        ProcessCpuMapTimestamp = [datetime]::MinValue
        TelemetryCache = [System.Collections.Hashtable]::Synchronized(@{ Snapshot = $null; SnapshotVersion = 0; LastCore = [datetime]::MinValue; LastGpu = [datetime]::MinValue; LastGame = [datetime]::MinValue; CoreCount = 0; AuxCount = 0; ErrorCount = 0; LastError = '' })
        ScanRunspace = $null
        ScanPowerShell = $null
        ScanAsync = $null
        TelemetryCoreRunspace = $null
        TelemetryCorePowerShell = $null
        TelemetryCoreAsync = $null
        TelemetryAuxRunspace = $null
        TelemetryAuxPowerShell = $null
        TelemetryAuxAsync = $null
        TelemetryStopEvent = $null
    }
}

function Get-YumDefaultConfigPath {
    Join-Path $script:Root 'Config\default-config.json'
}

function ConvertTo-YumHashtable {
    param($Object)
    if ($Object -is [System.Management.Automation.PSCustomObject]) {
        $h = [ordered]@{}
        foreach ($p in $Object.PSObject.Properties) { $h[$p.Name] = ConvertTo-YumHashtable $p.Value }
        return $h
    }
    if ($Object -is [System.Collections.IEnumerable] -and -not ($Object -is [string])) {
        $list = New-Object System.Collections.ArrayList
        foreach ($item in $Object) { [void]$list.Add((ConvertTo-YumHashtable $item)) }
        return $list.ToArray()
    }
    return $Object
}

function New-YumConfigFromDefaults {
    $defaultPath = Get-YumDefaultConfigPath
    if (-not (Test-Path -LiteralPath $defaultPath)) { throw "Default configuration not found: $defaultPath" }
    $json = Get-Content -LiteralPath $defaultPath -Raw | ConvertFrom-Json
    ConvertTo-YumHashtable $json
}

function Merge-YumHashtable {
    param([hashtable]$Base,[hashtable]$Override)
    foreach ($key in $Override.Keys) {
        if ($Base.Contains($key) -and $Base[$key] -is [hashtable] -and $Override[$key] -is [hashtable]) {
            Merge-YumHashtable -Base $Base[$key] -Override $Override[$key]
        } else { $Base[$key] = $Override[$key] }
    }
}

function Save-YumConfig {
    try {
        if (-not (Test-Path -LiteralPath $script:Yum.ConfigDirectory)) {
            New-Item -ItemType Directory -Path $script:Yum.ConfigDirectory -Force | Out-Null
        }
        $json = $script:Yum.Config | ConvertTo-Json -Depth 8
        $tmp = "$($script:Yum.ConfigFile).tmp"
        Set-Content -LiteralPath $tmp -Value $json -Encoding UTF8
        Move-Item -LiteralPath $tmp -Destination $script:Yum.ConfigFile -Force
        return $true
    } catch {
        Write-YumLogException 'Config save failed' $_.Exception
        return $false
    }
}

function Initialize-YumConfig {
    $script:Yum = New-YumRamRuntime
    $script:Yum.ConfigFile = Join-Path $script:Yum.ConfigDirectory 'config.json'
    $script:Yum.StateFile = Join-Path $script:Yum.ConfigDirectory 'state.json'

    $defaults = New-YumConfigFromDefaults
    $loaded = $false
    if (Test-Path -LiteralPath $script:Yum.ConfigFile) {
        try {
            $current = ConvertTo-YumHashtable ((Get-Content -LiteralPath $script:Yum.ConfigFile -Raw) | ConvertFrom-Json)
            Merge-YumHashtable -Base $defaults -Override $current
            $loaded = $true
        } catch {
            Write-YumLogException 'Config load failed; defaults used' $_.Exception
        }
    }
    $script:Yum.Config = $defaults
    # Release migration: keep one canonical RAM target and one version source.
    if($script:Yum.Config.Contains('SmartScanRefreshSeconds')){$legacyRefresh=[double]$script:Yum.Config.SmartScanRefreshSeconds;if($script:Yum.Config.Contains('IntelligenceRefreshSeconds') -and [double]$script:Yum.Config.IntelligenceRefreshSeconds -eq 20.0){$script:Yum.Config.IntelligenceRefreshSeconds=$legacyRefresh};$script:Yum.Config.Remove('SmartScanRefreshSeconds')}
    # 20 seconds was the historical Intelligence default. Migrate only that old default so custom user values remain untouched.
    if($script:Yum.Config.Contains('IntelligenceRefreshSeconds') -and [double]$script:Yum.Config.IntelligenceRefreshSeconds -eq 20.0){$script:Yum.Config.IntelligenceRefreshSeconds=60.0}
    if(-not $script:Yum.Config.Contains('ResearchConcurrency')){$script:Yum.Config.ResearchConcurrency=1}
    if(-not $script:Yum.Config.Contains('ResearchInterItemDelayMs')){$script:Yum.Config.ResearchInterItemDelayMs=125}
    if(-not $script:Yum.Config.Contains('AutoResearchAfterScan')){$script:Yum.Config.AutoResearchAfterScan=$false}

    if(-not $script:Yum.Config.Contains('ServiceScanMaxItems')){$script:Yum.Config.ServiceScanMaxItems=300}
    if(-not $script:Yum.Config.Contains('AppScanMaxItems')){$script:Yum.Config.AppScanMaxItems=250}
    if(-not $script:Yum.Config.Contains('TargetMaintenanceEnabled')){$script:Yum.Config.TargetMaintenanceEnabled=$true}
    if(-not $script:Yum.Config.Contains('TargetMaintenanceHysteresisGB')){$script:Yum.Config.TargetMaintenanceHysteresisGB=0.3}
    if(-not $script:Yum.Config.Contains('TargetMaintenanceMinimumIntervalSeconds')){$script:Yum.Config.TargetMaintenanceMinimumIntervalSeconds=15}
    if(-not $script:Yum.Config.Contains('IntelligentServiceCleanupEnabled')){$script:Yum.Config.IntelligentServiceCleanupEnabled=$false}
    if(-not $script:Yum.Config.Contains('IntelligentServiceStopThresholdGB')){$script:Yum.Config.IntelligentServiceStopThresholdGB=0.75}
    if(-not $script:Yum.Config.Contains('IntelligentServiceMaxStopsPerSession')){$script:Yum.Config.IntelligentServiceMaxStopsPerSession=2}
    if(-not $script:Yum.Config.Contains('AutoRestoreSessionStoppedServices')){$script:Yum.Config.AutoRestoreSessionStoppedServices=$true}
    $versionPath=Join-Path $script:Yum.Root 'VERSION'
    $runtimeVersion=''
    if(Test-Path -LiteralPath $versionPath){try{$candidateVersion=(Get-Content -LiteralPath $versionPath -Raw -ErrorAction Stop).Trim();if($candidateVersion -match '^\d+\.\d+\.\d+$'){$runtimeVersion=$candidateVersion}}catch{}}
    $script:Yum.Config.Version=$runtimeVersion
    # Monitoring remains user-started by design; keep background telemetry off at launch.
    $script:Yum.Config.StartMonitoringAutomatically=$false
    $script:Yum.Config.CleanupTargetAvailableGB=[double]$script:Yum.Config.MinimumAvailableGB
    $dbName = if($script:Yum.Config.Contains('IntelligenceDatabaseFileName')){[string]$script:Yum.Config.IntelligenceDatabaseFileName}else{'intelligence-db.json'}
    if ([string]::IsNullOrWhiteSpace($dbName)) { $dbName = 'intelligence-db.json' }
    $script:Yum.IntelligenceDbFile = Join-Path $script:Yum.ConfigDirectory $dbName
    [void](Save-YumConfig)
}

function Update-YumConfigValue {
    param([Parameter(Mandatory)][string]$Name,$Value)
    $script:Yum.Config[$Name] = $Value
    [void](Save-YumConfig)
}

function Add-YumConfiguredName {
    param(
        [ValidateSet('KnownGames','ProtectedProcesses','OptionalBackgroundProcesses')][string]$List,
        [Parameter(Mandatory)][string]$Name
    )

    $value = ($Name -replace '\.exe$','').Trim()
    if ([string]::IsNullOrWhiteSpace($value)) { return $false }

    # Process names only — never accept a path or wildcard/special filename syntax.
    if ($value -match '[\\/:*?"<>|]') { return $false }
    if ($value.Length -gt 128) { return $false }

    $current = @($script:Yum.Config[$List])
    foreach ($existing in $current) {
        if ([string]$existing -ieq $value) {
            return $true
        }
    }

    $script:Yum.Config[$List] = @($current + $value)
    [void](Save-YumConfig)
    Write-YumLog ("{0} added: {1}" -f $List,$value)
    return $true
}

function Remove-YumConfiguredName {
    param(
        [ValidateSet('KnownGames','ProtectedProcesses','OptionalBackgroundProcesses')][string]$List,
        [Parameter(Mandatory)][string[]]$Names
    )

    $keep = New-Object System.Collections.Generic.List[string]
    foreach ($existing in @($script:Yum.Config[$List])) {
        $remove = $false
        foreach ($name in $Names) {
            if ([string]$existing -ieq [string]$name) { $remove = $true; break }
        }
        if (-not $remove) { [void]$keep.Add([string]$existing) }
    }

    $script:Yum.Config[$List] = $keep.ToArray()
    [void](Save-YumConfig)
}

function Get-YumOptionalServices {
    @($script:Yum.Config.OptionalServices)
}
