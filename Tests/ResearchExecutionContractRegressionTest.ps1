$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$research=Get-Content (Join-Path $root 'Core\Research.ps1') -Raw
$dialogs=Get-Content (Join-Path $root 'UI\Dialogs.ps1') -Raw
$config=Get-Content (Join-Path $root 'Config\default-config.json') -Raw | ConvertFrom-Json

$checks=@(
    @($dialogs -match 'MANUAL RESEARCH ACCEPTED:', 'Manual button must log acceptance.'),
    @($dialogs -match 'RESEARCH WORKER STARTED:', 'Worker must log actual startup.'),
    @($dialogs -match 'RESEARCH WORKER FINISHED:', 'Worker must log actual completion.'),
    @($dialogs -match 'RESEARCH WORKER ERROR STREAM:', 'Worker error stream must be captured.'),
    @($dialogs -match 'statusPath=Join-Path \$script:Yum.Root', 'UI and worker must share research status path.'),
    @($research -match 'RESEARCH EXECUTION: item', 'Each research item must log execution.'),
    @($research -match 'ONLINE RESEARCH EXECUTION: item', 'Online research must have explicit execution logging.'),
    @($research -match 'function Ensure-YumResearchRecordSchema', 'Research record schema helper is required before strict-mode access.'),
    @($research -match 'Config\.OnlineResearchProvider', 'Canonical online research provider injection path is missing.'),
    @($research -match 'Get-YumResearchSafeProperty -Object \$_ -Name .ResearchRunDisposition.', 'Live snapshot must safely read optional research-run properties.'),
    @([string]$config.ResearchEngineVersion -eq '5.2.74', 'Research engine version must match release.'),
    @([string]$config.Version -eq '5.2.74', 'Config version must match release.')
)
foreach($c in $checks){ if(-not $c[0]){ throw $c[1] } }
if($dialogs -notmatch 'Ensure-YumIntelligenceRecordSchema -Record \$r'){ throw 'Selection handler must normalize the selected record schema.' }

$schema = Get-Content (Join-Path $root 'Core\Intelligence.ps1') -Raw
if($schema -notmatch 'Signature=.Unknown.') { throw 'Intelligence schema must define Signature fallback.' }
if($schema -notmatch 'function Get-YumSafePropertyValue') { throw 'Safe property accessor missing.' }
Write-Host 'ResearchExecutionContractRegressionTest: PASS'

