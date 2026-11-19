#Requires -Version 5.1
$ErrorActionPreference='Stop'
# 5.3.0: behaviour checks only. UI copy (tooltip wording) and the retired AutoResearchAfterScan
# key are no longer asserted; research during scan is unconditional in the current design.
$fail=@()
function Assert-True([bool]$Condition,[string]$Message){if(-not $Condition){$script:fail += $Message}}
$dialogs=Get-Content -LiteralPath (Join-Path $PSScriptRoot '..\UI\Dialogs.ps1') -Raw
$xaml=Get-Content -LiteralPath (Join-Path $PSScriptRoot '..\UI\Xaml\Intelligence.xaml') -Raw
Assert-True ($dialogs.Contains('ResearchPendingManual=$false')) 'ResearchPendingManual state is not initialized.'
Assert-True ($dialogs.Contains('$ctx.ResearchPendingManual=$true')) 'Manual research while busy does not queue a retry.'
Assert-True ($dialogs.Contains('$all|Where-Object{Test-YumResearchUnresolved -Record $_}')) 'Run Research does not include saved unresolved records.'
Assert-True ($dialogs.Contains('automatically researching')) 'Scan does not research unresolved items automatically.'
Assert-True ($xaml.Contains('x:Name="RunResearch"')) 'Run Research button missing.'
Assert-True (-not $dialogs.Contains('Run Research remains manual; current scan results remain usable')) 'Stale manual-only research messaging remains.'
if($fail.Count -gt 0){$fail|ForEach-Object{Write-Error $_};exit 1}
Write-Host 'YUMRAM IntelligenceResearchInteractionRegressionTest PASSED.'
