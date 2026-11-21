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
        ControllerPowerShell = $null
        ControllerAsync = $null
        ControllerRunspace = $null
        ControllerStopEvent = $null
        ControllerHeartbeatUtc = [datetime]::MinValue
        MonitoringActive = $false
        ControllerBackoffSeconds = 0.0
        GlobalRetention = $null
        ReachableEstimate = $null
        ReachableEstimateUtc = [datetime]::MinValue
        ControllerWakeEvent = (New-Object System.Threading.AutoResetEvent($false))
        ReclaimRequest = $null
        ReclaimRequestedAt = [datetime]::MinValue
        ReclaimTaken = $false   # 5.15: request taken by the worker, reclaim not yet flagged running (closes a busy-state gap)
        MainFrame = $null
        TrayIcon = $null
        TrayMenu = $null
        TrayMenuMonitor = $null
        TrayMenuFreeRam = $null
        TrayIconHandle = [IntPtr]::Zero
        TrayLastKey = ''
        TrayHintShown = $false
        TrayReclaimPending = $false
        Pages = @{}
        CurrentPage = 'Overview'
        PageFrame = $null
        PendingPage = $null
        NavLoopDepth = 0
        SidebarCompact = $false
        SidebarPinnedByUser = $false
        Hotkey = $null
        HotkeyText = ''
        HotkeyStatus = 'Off'
        FreedStats = $null
        LastStatReclaimKey = ''
        LastPausedMemoryRead = [datetime]::MinValue
        LastLiveReadingsRead = [datetime]::MinValue
        LiveCpu = $null
        LiveGpuBusy = 0.0
        LastSideScanRead = [datetime]::MinValue
        LastDiskAutoCheck = [datetime]::MinValue
        DiskAutoRunning = $false
        LastUiReclaimResultVersion = 0
        ReclaimVerificationTimer = $null
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
        ShowSignal = $null
        ExitRequested = $false
        CloseHintShown = $false
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
        LastMemoryAreaAssist = [datetime]::MinValue
        LastTelemetryUpdate = [datetime]::MinValue
        LastCoreTelemetryUpdate = [datetime]::MinValue
        LastTelemetryCycle = [datetime]::MinValue
        TelemetryErrorCount = 0
        TelemetrySuccessCount = 0
        ReclaimLock = New-Object object
        ReclaimRunning = $false
        LastReclaim = $null
        ReclaimResult = $null
        ReclaimResultVersion = 0
        ReclaimHistory = New-Object System.Collections.Generic.Queue[object]
        ReclaimLearning = @{}
        ReclaimLearningLoaded = $false
        ResearchState = [pscustomobject]@{Phase='Idle';Stage='Idle';Index=0;Total=0;Key='';Name='';Message='';Confidence=0;Completed=$true;Updated=Get-Date;Error=''}
        LastAutoStandbyPurge = [datetime]::MinValue
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
        # 5.15 review: every key a background thread writes exists from the start. $script:Yum is an ordered
        # dictionary shared by the UI thread and 4 runspaces; adding a NEW key changes its internal structure,
        # which is not safe while another thread reads it. Updating an existing key's value is a simple swap.
        CpuBalance = $null
        CpuBalanceAsync = $null
        CpuBalancePowerShell = $null
        CpuBalanceRunspace = $null
        CpuBalanceStop = $null
        CpuProfile = $null
        CpuKnowledge = $null
        CpuBenchPid = 0
        CpuBenchStart = [int64]0
        CpuCareForegroundOverride = 0
        CpuCareGameOverride = 0
        CommunityKnowledge = $null
        CommunityPromptPending = $false
        CommunityFetchPs = $null
        CommunityFetchAsync = $null
        LastMemoryCombine = $null
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
    # 5.3.1: was [hashtable]. The config is an [ordered] dictionary, and binding it to a [hashtable]
    # parameter makes PowerShell pass a *converted copy*, so every saved user setting was merged into
    # a throwaway object and the app started on defaults at every launch (e.g. target back to 4 GB).
    param([System.Collections.IDictionary]$Base,[System.Collections.IDictionary]$Override)
    foreach ($key in @($Override.Keys)) {
        if ($Base.Contains($key) -and $Base[$key] -is [System.Collections.IDictionary] -and $Override[$key] -is [System.Collections.IDictionary]) {
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
    if(-not $script:Yum.Config.Contains('AutoCloseOptionalApps')){$script:Yum.Config.AutoCloseOptionalApps=$false}   # 5.15 audit F2
    if(-not $script:Yum.Config.Contains('IntelligentServiceStopThresholdGB')){$script:Yum.Config.IntelligentServiceStopThresholdGB=0.75}
    if(-not $script:Yum.Config.Contains('IntelligentServiceMaxStopsPerSession')){$script:Yum.Config.IntelligentServiceMaxStopsPerSession=2}
    if(-not $script:Yum.Config.Contains('AutoRestoreSessionStoppedServices')){$script:Yum.Config.AutoRestoreSessionStoppedServices=$true}
    # 5.3.1 migration: raise values that are still at the old (too timid) defaults. Anything the
    # user changed away from the old default is left alone.
    # Each entry: @(new value, old default, older default...). 5.4 raised the per-pass defaults again.
    $oldDefaults=@{AutoMemoryAreaAssistSeconds=@(600,45);SafeProcessesPerPass=@(6,2,3);BalancedProcessesPerPass=@(10,3,5);AggressiveProcessesPerPass=@(16,5,8);MinimumCleanIntervalSeconds=@(15,30);ReclaimMaxProcessActions=@(8,3);GPUIntervalSeconds=@(5.0,3.0);ResearchInterItemDelayMs=@(50,250)}
    foreach($k in $oldDefaults.Keys){
        try{
            if(-not $script:Yum.Config.Contains($k)){continue}
            $entry=@($oldDefaults[$k]);$current=[double]$script:Yum.Config[$k]
            foreach($old in @($entry[1..($entry.Count-1)])){ if($current -eq [double]$old){ $script:Yum.Config[$k]=$entry[0]; break } }
        }catch{}
    }
    $versionPath=Join-Path $script:Yum.Root 'VERSION'
    $runtimeVersion=''
    if(Test-Path -LiteralPath $versionPath){try{$candidateVersion=(Get-Content -LiteralPath $versionPath -Raw -ErrorAction Stop).Trim();if($candidateVersion -match '^\d+\.\d+\.\d+$'){$runtimeVersion=$candidateVersion}}catch{}}
    $script:Yum.Config.Version=$runtimeVersion
    # 5.5: the research engine version follows VERSION, so an upgrade re-checks Unknown results even when
    # config.json still carries the older value.
    if(-not [string]::IsNullOrWhiteSpace($runtimeVersion)){$script:Yum.Config.ResearchEngineVersion=$runtimeVersion}
    # 5.3.3: honour the Settings checkbox. It defaults to off (default-config.json), but 5.2.x forced it
    # off here on every launch, so the "Start monitoring automatically" option never worked.
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
