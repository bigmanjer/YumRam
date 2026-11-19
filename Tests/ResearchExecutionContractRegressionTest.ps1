$version=(Get-Content -LiteralPath (Join-Path (Split-Path -Parent $PSScriptRoot) 'VERSION') -Raw).Trim()
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$research=Get-Content (Join-Path $root 'Core\Research.ps1') -Raw
$dialogs=Get-Content (Join-Path $root 'UI\Dialogs.ps1') -Raw
$config=Get-Content (Join-Path $root 'Config\default-config.json') -Raw | ConvertFrom-Json

$checks=@(
    @(([bool]($dialogs -match 'MANUAL RESEARCH ACCEPTED:')), 'Manual button must log acceptance.'),
    @(([bool]($dialogs -match 'RESEARCH WORKER STARTED:')), 'Worker must log actual startup.'),
    @(([bool]($dialogs -match 'RESEARCH WORKER FINISHED:')), 'Worker must log actual completion.'),
    @(([bool]($dialogs -match 'RESEARCH WORKER ERROR STREAM:')), 'Worker error stream must be captured.'),
    @(([bool]($dialogs -match 'statusPath=Get-YumResearchStatusPath')), 'UI and worker must share research status path (Get-YumResearchStatusPath).'),
    @(([bool]($research -match 'RESEARCH EXECUTION: item')), 'Each research item must log execution.'),
    @(([bool]($research -match 'ONLINE RESEARCH EXECUTION: item')), 'Online research must have explicit execution logging.'),
    @(([bool]($research -match 'function Ensure-YumResearchRecordSchema')), 'Research record schema helper is required before strict-mode access.'),
    @(([bool]($research -match 'Config\.OnlineResearchProvider')), 'Canonical online research provider injection path is missing.'),
    @(([bool]($research -match 'Get-YumResearchSafeProperty -Object \$_ -Name .ResearchRunDisposition.')), 'Live snapshot must safely read optional research-run properties.'),
    @(([bool]([string]$config.ResearchEngineVersion -eq $version)), 'Research engine version must match release.'),
    @(([bool]([string]$config.Version -eq $version)), 'Config version must match release.')
)
foreach($c in $checks){ if(-not $c[0]){ throw $c[1] } }
if($dialogs -notmatch 'Ensure-YumIntelligenceRecordSchema -Record \$r'){ throw 'Selection handler must normalize the selected record schema.' }

$schema = Get-Content (Join-Path $root 'Core\Intelligence.ps1') -Raw
if($schema -notmatch 'Signature=.Unknown.') { throw 'Intelligence schema must define Signature fallback.' }
$reclaimSrc = Get-Content (Join-Path $root 'Core\MemoryReclaim.ps1') -Raw
if(($schema + $reclaimSrc) -notmatch 'function Get-YumSafePropertyValue') { throw 'Safe property accessor missing.' }
Write-Host 'ResearchExecutionContractRegressionTest: PASS'

