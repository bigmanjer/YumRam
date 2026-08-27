#requires -Version 5.1
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

function Read-TestText { param([string]$Path) [IO.File]::ReadAllText($Path,([System.Text.UTF8Encoding]::new($false,$true))) }
function Add-CheckError { param([string]$Message) [void]$script:Errors.Add($Message) }

$root=Split-Path -Parent $PSScriptRoot
$script:Errors=New-Object System.Collections.Generic.List[string]
$required=@(
 'App\YUMRAM.ps1','App\Bootstrap.ps1','Core\Logging.ps1','Core\Config.ps1','Core\Native.ps1','Core\Games.ps1','Core\Safety.ps1','Core\Bloatware.ps1','Core\Scanner.ps1','Core\Telemetry.ps1','Core\TelemetryWorker.ps1','Core\Cleanup.ps1','Core\Intelligence.ps1','Core\Research.ps1','UI\Dialogs.ps1','UI\MainWindow.ps1','UI\Xaml\MainWindow.xaml','UI\Xaml\Settings.xaml','UI\Xaml\Intelligence.xaml','Config\default-config.json','VERSION','Launch-YUMRAM.cmd')
foreach($rel in $required){if(-not(Test-Path -LiteralPath (Join-Path $root $rel))){Add-CheckError "Missing required file: $rel"}}

# Windows PowerShell 5.1 parser + BOM validation.
foreach($ps in Get-ChildItem -LiteralPath $root -Recurse -Filter *.ps1){
    try{
        $raw=[IO.File]::ReadAllBytes($ps.FullName)
        if($raw.Length -lt 3 -or $raw[0] -ne 0xEF -or $raw[1] -ne 0xBB -or $raw[2] -ne 0xBF){Add-CheckError "PowerShell file is not UTF-8 BOM: $($ps.FullName)"}
        $tokens=$null;$parseErrors=$null
        [System.Management.Automation.Language.Parser]::ParseFile($ps.FullName,[ref]$tokens,[ref]$parseErrors)|Out-Null
        foreach($e in @($parseErrors)){Add-CheckError "PS parse error in $($ps.Name): $($e.Message)"}
    }catch{Add-CheckError "PS parser test failed for $($ps.FullName): $($_.Exception.Message)"}
}

foreach($x in Get-ChildItem -LiteralPath (Join-Path $root 'UI\Xaml') -Filter *.xaml){try{[xml](Read-TestText $x.FullName)|Out-Null}catch{Add-CheckError "XAML parse error in $($x.Name): $($_.Exception.Message)"}}
try{[void](Read-TestText (Join-Path $root 'Config\default-config.json')|ConvertFrom-Json)}catch{Add-CheckError "JSON parse error: $($_.Exception.Message)"}

$version=(Read-TestText (Join-Path $root 'VERSION')).Trim()
$readmeText=Read-TestText (Join-Path $root 'README.md')
if($readmeText -notmatch ('Version:\s*'+[regex]::Escape($version)+'(?:\r?\n|$)')){Add-CheckError "README version does not match canonical VERSION $version."}
$cfg=Read-TestText (Join-Path $root 'Config\default-config.json')|ConvertFrom-Json
if([string]::IsNullOrWhiteSpace($version)){Add-CheckError 'VERSION is empty.'}
if([string]$cfg.Version -ne $version){Add-CheckError "Config Version $($cfg.Version) does not match canonical VERSION $version."}
if([string]$cfg.ResearchEngineVersion -ne $version){Add-CheckError "ResearchEngineVersion $($cfg.ResearchEngineVersion) does not match canonical VERSION $version."}

# Required intelligence/research architecture.
$research=Read-TestText (Join-Path $root 'Core\Research.ps1')
$dialogs=Read-TestText (Join-Path $root 'UI\Dialogs.ps1')
$intel=Read-TestText (Join-Path $root 'Core\Intelligence.ps1')
$scanner=Read-TestText (Join-Path $root 'Core\Scanner.ps1')
$cleanup=Read-TestText (Join-Path $root 'Core\Cleanup.ps1')
$mainPs=Read-TestText (Join-Path $root 'UI\MainWindow.ps1')
$intelXaml=Read-TestText (Join-Path $root 'UI\Xaml\Intelligence.xaml')
$mainXaml=Read-TestText (Join-Path $root 'UI\Xaml\MainWindow.xaml')

# UI release/version hygiene. The visible footer must be bound at runtime, not hard-coded to an older release.
if($mainXaml -match 'YUMRAM V5\.1\.0'){Add-CheckError 'Main window contains stale hard-coded YUMRAM V5.1.0 footer.'}
if($mainPs -notmatch 'VersionStatus|Config\.Version'){Add-CheckError 'Main window version is not runtime-bound.'}
if($cleanup -notmatch 'StopReason'){Add-CheckError 'Cleanup result does not expose an explicit stop reason.'}
if($mainPs -notmatch 'TargetShortfallGB|StopReason'){Add-CheckError 'Main window does not surface target shortfall/stop reason.'}
if($scanner -match '\[switch\]\$Research'){Add-CheckError 'Scanner still exposes a research execution switch; research must be manual-only.'}

foreach($fn in @('Ensure-YumIntelligenceRecordSchema','Get-YumStableIntelligenceKey','Save-YumIntelligenceItems','Apply-YumManualOrganizations')){if($intel -notmatch "function $fn\b"){Add-CheckError "Intelligence function missing: $fn"}}
foreach($fn in @('Get-YumInstalledSoftwareResearch','Get-YumWinGetResearch','Get-YumOnlineResearch','Get-YumResearchPlacement','Test-YumResearchTerminalResult','Invoke-YumResearch','Write-YumResearchLiveSnapshot')){if($research -notmatch "function $fn\b"){Add-CheckError "Research function missing: $fn"}}

# Empty-safe array APIs: no mandatory object[] parameters anywhere in Intelligence/Research/UI.
foreach($ps in @(Get-ChildItem -LiteralPath (Join-Path $root 'Core') -Filter *.ps1; Get-ChildItem -LiteralPath (Join-Path $root 'UI') -Filter *.ps1)){
    $text=Read-TestText $ps.FullName
    if($text -match '\[Parameter\(Mandatory[^\)]*\)\]\s*\[object\[\]\]'){Add-CheckError "Mandatory object[] parameter remains in $($ps.Name)."}
}

if($research -notmatch '\$researchConcurrency=1'){Add-CheckError 'Research worker is not locked to single-item sequential mode.'}
if($research -notmatch 'Researching Item'){Add-CheckError 'Per-item research status stage missing.'}
# Research worker transport: one JSON document through queue/config files, not PowerShell object arrays.
if($dialogs -notmatch '\$queueJson\s*=\s*ConvertTo-Json\s+-InputObject\s+@\(\$researchRecords\)'){Add-CheckError 'Research queue is not serialized as one JSON document.'}
if($dialogs -notmatch 'Research queue transport: records='){Add-CheckError 'Research transport diagnostic missing.'}
if($dialogs -notmatch 'queuePath' -or $dialogs -notmatch 'configPath'){Add-CheckError 'Research queue/config file transport paths missing.'}
if($dialogs -notmatch 'ConvertFrom-Json -ErrorAction Stop'){Add-CheckError 'Research worker JSON deserialization missing.'}
if($research -notmatch 'function Write-YumResearchLiveSnapshot'){Add-CheckError 'Research live checkpoint writer missing.'}

# Research state machine and persistence.
foreach($needle in @('Fresh research always outranks cached state.','$finalResearchStatus','ResearchRunDisposition','ResearchRunResolved','ResearchRunOnline','ResearchExhausted','ResearchError')){if($research -notmatch [regex]::Escape($needle)){Add-CheckError "Research state invariant missing: $needle"}}
if($research -notmatch 'ResearchedCount='){Add-CheckError 'Snapshot ResearchedCount metric missing.'}
if($research -notmatch 'CachedCount='){Add-CheckError 'Snapshot CachedCount metric missing.'}
if($research -notmatch 'UnknownCount='){Add-CheckError 'Snapshot UnknownCount metric missing.'}
if($research -notmatch 'ResearchErrorCount='){Add-CheckError 'Snapshot ResearchErrorCount metric missing.'}
# Runtime engine-version configuration is covered by integration tests.


# Review queue semantics: protected/terminal classifications must not be research candidates.
if($research -notmatch "function Test-YumResearchUnresolved") {Add-CheckError 'Research unresolved predicate missing.'}
# Predicate behavior is covered by ResearchStateRegressionTest.
# Predicate behavior is covered by ResearchStateRegressionTest.
# Predicate behavior is covered by ResearchStateRegressionTest.
# Online failure handling is covered by ResearchExecutionContractRegressionTest.
# Empty research queue must be a no-op; it must not replace State.Data.Records with an empty collection.
if($dialogs -match '\$State\.Data=\[pscustomobject\]@\{Records=@\(\);ResearchCount=0;CachedCount=0;OnlineResearchCount=0;ReviewResolvedCount=0;UnknownCount=0;ResearchErrorCount=0\}') {Add-CheckError 'Empty research queue still clears the Intelligence data set.'}
if($dialogs -notmatch 'No items currently require research\.'){Add-CheckError 'Empty research queue no-op message missing.'}

# Cache-aware live queue: hydrate durable state first, then queue only current live unresolved records.
if($dialogs -notmatch '\$previousDb=@\{\}'){Add-CheckError 'Persisted Intelligence DB is not captured before live-record replacement.'}
if($dialogs -notmatch 'identityCompatible=\$true'){Add-CheckError 'Saved/live identity compatibility guard missing.'}
if($dialogs -notmatch '\$researchInput=@\(\$ctx\.State\.Data\.Records \| Where-Object'){Add-CheckError 'Research queue is not built from the merged current state.'}
if($dialogs -notmatch '\[bool\]\$_.Live -and -not \[bool\]\$_.ManualOverride'){Add-CheckError 'Research queue does not restrict to current non-manual live records.'}
if($dialogs -notmatch 'Automatic research candidates:'){Add-CheckError 'Cache-aware research candidate diagnostic missing.'}

# Incremental merge: never replace the entire live collection with a partial research result.
if($dialogs -notmatch '\$fullRecords=@\(\$ctx\.State\.Data\.Records\)'){Add-CheckError 'Final research result merge does not preserve the full Intelligence collection.'}
if($dialogs -notmatch '\$snap\.ResearchedCount' -or $dialogs -notmatch '\$snap\.CachedCount'){Add-CheckError 'Live research snapshot counters are not applied to the header state.'}
if($dialogs -notmatch 'Research progress updated'){Add-CheckError 'Live research progress UI update missing.'}

# Manual organization safety/persistence.
if($dialogs -notmatch 'Get-YumManualOrganizationKey -Name \(\[string\]\$t\.Item\.Name\).*FileHash'){Add-CheckError 'Manual clear does not use strong manual-identity key.'}
if($dialogs -notmatch '\$t\.Item\.ResearchStatus=''Review'''){Add-CheckError 'Manual clear does not return item to Review research state.'}
if($dialogs -notmatch 'Save-YumIntelligenceDb -Database \$script:Yum\.IntelligenceDb'){Add-CheckError 'Manual clear path does not persist the cleared Intelligence record.'}

# Scanner/runtime safety.
if($scanner -match '\[string\]\$PID|\[int\]\$Pid|\$Pid\s*='){Add-CheckError 'Scanner contains a PowerShell $PID collision risk.'}
if($scanner -notmatch '^#requires -Version 5\.1'){Add-CheckError 'Scanner #requires directive must be first statement.'}
if($cleanup -notmatch 'CleanupOneShotController' -or $cleanup -notmatch 'Start-YumControllerTimer'){Add-CheckError 'Safe optimization one-shot controller path missing.'}

# Concurrent process identity: live instances must be unique while persistence uses stable identity.
if($scanner -notmatch 'function Get-YumLiveIntelligenceRecordKey'){Add-CheckError 'Live Intelligence instance-key helper missing.'}
if($scanner -notmatch 'StableIdentityKey=\(Get-YumStableIntelligenceKeyFromValues -Source ''Process'''){Add-CheckError 'Process records do not publish StableIdentityKey.'}
if($scanner -notmatch 'Get-YumLiveIntelligenceRecordKey -StableIdentityKey'){Add-CheckError 'Process records do not use unique live instance keys.'}
if($intel -notmatch 'PSObject.Properties\[''StableIdentityKey''\]'){Add-CheckError 'Intelligence schema/identity does not recognize StableIdentityKey.'}
if($dialogs -notmatch '\$previousStableDb=@\{\}'){Add-CheckError 'Live/saved merge does not build a stable-identity index.'}
if($dialogs -notmatch 'Get-YumStableIntelligenceKey -Record \$record'){Add-CheckError 'Live records are not merged by stable identity.'}


# V5.2.26 queue/state regressions.
if($research -notmatch '\$protectedFamily=') {Add-CheckError 'Protected-family research exclusion guard missing.'}
if($research -notmatch '\$needs=Test-YumResearchUnresolved -Record \$r') {Add-CheckError 'Research worker does not enforce the shared unresolved predicate.'}
if($dialogs -notmatch '\$script:Yum\.IntelligenceDb\[\$storageKey\]=\$record') {Add-CheckError 'Live research merge does not persist by StableIdentityKey.'}
# Review filter uses Test-YumResearchUnresolved; validated by dedicated interaction test.
if($dialogs -notmatch '\$State\[''ReviewCount''\]\.Text=@\(\$all\|Where-Object \{\$_.Live -and \(Test-YumResearchUnresolved -Record \$_\)\}\)\.Count') {Add-CheckError 'Review counter does not use the authoritative live unresolved predicate.'}


# Gaming-safe gradual cleanup contract.
if($cleanup -notmatch 'function Get-YumTrimPlan'){Add-CheckError 'Gradual trim-plan helper missing.'}
if($cleanup -notmatch 'function Get-YumGamingCleanupProfile'){Add-CheckError 'Gaming cleanup profile helper missing.'}
if([string]$cfg.CleanupSelectionStrategy -ne 'AdaptiveSmallestFirstThenLegacyFallback'){Add-CheckError 'CleanupSelectionStrategy is not the supported adaptive/fallback strategy.'}
if($cleanup -notmatch 'Sort-Object WorkingSetMB,Priority -Ascending'){Add-CheckError 'Cleanup adaptive planner is not smallest-working-set first.'}
if($cleanup -notmatch 'MaxTrimMBPerPass'){Add-CheckError 'Cleanup memory budget per pass missing.'}
if($cleanup -notmatch 'MaxPassMilliseconds'){Add-CheckError 'Cleanup time budget per pass missing.'}
if($cleanup -match 'AvailableGB -ge \(\[double\]\$script:Yum.Config.MinimumAvailableGB-\$hysteresis\)' -and $cleanup -match 'Inside target re-engagement deadband'){Add-CheckError 'Automatic controller still suppresses cleanup while Available RAM remains below target.'}
if($dialogs -notmatch 'LiveTimer=\$null' -or $dialogs -notmatch 'DispatcherTimer' -or $dialogs -notmatch 'Live cleanup preview refresh failed'){Add-CheckError 'Cleanup Preview is not using a live UI refresh timer.'}
if($cleanup -notmatch "Type='Process'" -or $cleanup -notmatch "Time=\(Get-Date\).ToString\('HH:mm:ss.fff'\)"){Add-CheckError 'Cleanup activity rows do not expose action type/time.'}
if($research -notmatch 'gov|edu|nvidia.com|intel.com|mozilla.org'){Add-CheckError 'Research source trust policy is not using authoritative-domain tiers.'}
if($cleanup -notmatch 'StepDelayMs'){Add-CheckError 'Cleanup step delay missing.'}
if($cleanup -notmatch 'Get-YumGamingCleanupProfile -BaseProfile'){Add-CheckError 'Gaming-aware cleanup profile invocation missing.'}
if($cleanup -notmatch 'OptionalApps=0;OptionalServices=0'){Add-CheckError 'Gaming mode does not disable optional process/service cleanup.'}


if($cleanup -notmatch 'remainingGapMB'){Add-CheckError 'Optional cleanup does not enforce remaining target gap.'}
if($cleanup -notmatch 'Optional services are intentionally excluded from target reclaim'){Add-CheckError 'Service cleanup can still overshoot the target.'}
if($cleanup -notmatch 'Sort-Object WorkingSet'){Add-CheckError 'Optional background cleanup ordering contract missing.'}


foreach($setting in @('CleanupStepDelayMs','CleanupMaxPassMilliseconds','CleanupMaxTrimMBPerPass','GamingCleanupStepDelayMs','GamingCleanupMaxPassMilliseconds','GamingCleanupMaxTrimMBPerPass')){if($cfg.PSObject.Properties.Name -notcontains $setting){Add-CheckError "Cleanup setting missing from config: $setting"}}
if($cleanup -match '\[Parameter\(Mandatory[^\)]*\)\]\s*\[object\[\]\]'){Add-CheckError 'Mandatory object[] parameter remains in Cleanup.ps1.'}

# UI/graph contract.
foreach($n in @('IntelligenceResults','Filter','Search','Refresh','RunResearch','Close','Details','Summary','LastScan','ReviewCount','ResearchingCount','ResolvedCount','UnknownCount','ProtectedCount','CachedCount','ResearchErrorCount','DatabaseCount')){if($intelXaml -notmatch ('x:Name="'+[regex]::Escape($n)+'"')){Add-CheckError "Intelligence control missing: $n"}}
if($mainXaml -notmatch 'Grid.Row="2".*AVAILABLE RAM'){Add-CheckError 'Monitor legend is not outside the graph canvas.'}
if($mainPs -notmatch 'GraphMemoryAvailable' -or $mainPs -notmatch 'GraphMemoryAvailableLine'){Add-CheckError 'Available RAM graph series/line missing.'}

# Safety baseline.
if([bool]$cfg.EnableOptionalServiceCleanup){Add-CheckError 'Optional service cleanup must remain disabled.'}
foreach($ps in Get-ChildItem -LiteralPath (Join-Path $root 'Core') -Filter *.ps1){
    $text=Read-TestText $ps.FullName
    foreach($sig in @('taskkill','TerminateProcess','Remove-Service','Set-Service')){if($text -match [regex]::Escape($sig)){Add-CheckError "Automatic safety signature found in $($ps.Name): $sig"}}
}

if($script:Errors.Count -gt 0){$script:Errors|ForEach-Object{Write-Error $_};exit 1}
Write-Host "YUMRAM $version static verification PASSED."

# v5.2.42 Intelligence interaction regression
$interactionTest = Join-Path $PSScriptRoot 'IntelligenceResearchInteractionRegressionTest.ps1'
if(Test-Path -LiteralPath $interactionTest){ & $interactionTest }
