#Requires -Version 5.1
$ErrorActionPreference='Stop'
$fail=@()
function Assert-True([bool]$Condition,[string]$Message){if(-not $Condition){$script:fail += $Message}}
$dialogs=Get-Content -LiteralPath (Join-Path $PSScriptRoot '..\UI\Dialogs.ps1') -Raw
$xaml=Get-Content -LiteralPath (Join-Path $PSScriptRoot '..\UI\Xaml\Intelligence.xaml') -Raw
Assert-True ($dialogs -match 'ResearchPendingManual=\$false') 'ResearchPendingManual state is not initialized.'
Assert-True ($dialogs -match '\$ctx\.ResearchPendingManual=\$true') 'Manual research while busy does not queue a retry.'
Assert-True ($dialogs -match '\$all\|Where-Object\{Test-YumResearchUnresolved -Record \$_\}') 'Run Research does not include saved unresolved records.'
Assert-True ($dialogs -match 'AutoResearchAfterScan') 'Automatic research-after-scan configuration is not referenced.'
Assert-True ($xaml -match 'saved unresolved items') 'Run Research tooltip does not explain saved unresolved research.'
Assert-True ($xaml -match 'automatically queues research after the scan') 'Intelligence help text does not describe automatic research after scan.'
Assert-True ($dialogs -notmatch 'Run Research remains manual; current scan results remain usable') 'Stale manual-only research messaging remains.'
if($fail.Count -gt 0){$fail|ForEach-Object{Write-Error $_};exit 1}
Write-Host 'YUMRAM IntelligenceResearchInteractionRegressionTest PASSED.'
