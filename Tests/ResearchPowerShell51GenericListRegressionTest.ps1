#requires -Version 5.1
Set-StrictMode -Version Latest
$root=Split-Path -Parent $PSScriptRoot
$text=Get-Content -LiteralPath (Join-Path $root 'Core\Research.ps1') -Raw
if($text -match 'EvidenceSources=@\(\$evidence\)'){throw 'Research placement still wraps generic List[string] evidence with @().' }
if($text -match 'VerifiedLinks=@\(\$verified\)'){throw 'Online research still wraps generic List[string] verified links with @().' }
if($text -match 'CommunityContext=@\(\$community\)'){throw 'Online research still wraps generic List[object] community data with @().' }
if($text -match 'BestScore=if\('){throw 'Research result still uses fragile inline if expression for BestScore.'}
if((([regex]::Matches($text,'function Get-YumResearchFileEvidence')).Count) -ne 1){throw 'Research file-evidence provider must have exactly one active function definition.'}
Write-Host 'ResearchPowerShell51GenericListRegressionTest PASSED.'
