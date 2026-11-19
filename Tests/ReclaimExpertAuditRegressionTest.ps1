#requires -Version 5.1
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$expectedYumramVersion = (Get-Content -LiteralPath (Join-Path $root 'VERSION') -Raw).Trim()
$memory=Get-Content -LiteralPath (Join-Path $root 'Core\MemoryReclaim.ps1') -Raw
$dialogs=Get-Content -LiteralPath (Join-Path $root 'UI\Dialogs.ps1') -Raw
$xaml=Get-Content -LiteralPath (Join-Path $root 'UI\Xaml\MemoryReclaim.xaml') -Raw
$config=Get-Content -LiteralPath (Join-Path $root 'Config\default-config.json') -Raw | ConvertFrom-Json
$version=(Get-Content -LiteralPath (Join-Path $root 'VERSION') -Raw).Trim()
if($version -ne $expectedYumramVersion){throw ('Canonical VERSION is not {0}.' -f $expectedYumramVersion)}
if([string]$config.Version -ne $version){throw 'Config Version does not match canonical VERSION.'}
if([string]$config.ResearchEngineVersion -ne $version){throw 'ResearchEngineVersion does not match canonical VERSION.'}
if($config.ReclaimLearningEnabled -ne $true){throw 'Reclaim learning must be enabled.'}
if($memory -match 'Get-YumMemoryReclaimPreview|\[switch\]\$Preview|if\(\$Preview\)'){throw 'Lag-prone memory reclaim preview path is still present.'}
$center=$dialogs.Substring($dialogs.IndexOf('function Show-YumMemoryReclaim'))
if($center -match 'Get-YumMemoryReclaimPreview|FindName\(.Refresh.\)'){throw 'RAM Reclaim Center still contains a preview/refresh dependency.'}
if($memory -notmatch 'Get-YumReclaimLearningForProcess'){throw 'Reclaim learning lookup missing.'}
if($memory -notmatch 'Update-YumReclaimLearning'){throw 'Reclaim learning update missing.'}
if($memory -notmatch 'HistoricalBonus'){throw 'Historical reclaim effectiveness is not part of candidate scoring.'}
if(-not $memory.Contains('ReclaimSystemWorkingSet -and $Force -and -not $gameActive')){throw 'System working-set pass is not controlled by ReclaimSystemWorkingSet.'}
if($memory -match 'ReclaimModifiedPageList -and \$Force -and -not \$gameActive\)\{\s*\$r2=Invoke-YumNativeMemoryCommand -Command EmptyWorkingSets'){throw 'System working-set pass is incorrectly tied to ReclaimModifiedPageList.'}
if($memory -notmatch 'if\(\$r\.Success\)\{\$used\+\+\}'){throw 'Failed process actions still consume successful-action quota.'}
if($memory -notmatch 'systemBefore=Get-YumMemoryReclaimSnapshot' -or $memory -notmatch 'systemAfter=Get-YumMemoryReclaimSnapshot'){throw 'Per-process available-RAM verification missing.'}
foreach($label in @('💜 FREE RAM NOW','💜 DEEP RAM RECLAIM')){if($xaml -notmatch [regex]::Escape($label)){throw "Missing requested label: $label"}}
if($xaml -notmatch 'No preview scan'){throw 'RAM Reclaim Center does not document preview removal.'}
if($xaml -match 'x:Name="Refresh"'){throw 'Refresh control regressed.'}
Write-Host 'ReclaimExpertAuditRegressionTest PASSED.'
