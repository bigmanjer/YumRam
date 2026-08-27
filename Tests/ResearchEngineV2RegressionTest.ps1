# YUMRAM v5.2.49 Research Engine regression checks
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$research=Get-Content (Join-Path $root 'Core\Research.ps1') -Raw
$dialogs=Get-Content (Join-Path $root 'UI\Dialogs.ps1') -Raw
$config=Get-Content (Join-Path $root 'Config\default-config.json') -Raw | ConvertFrom-Json

if($research -match '\.ParsedHtml\.title'){throw 'Research engine must not depend on ParsedHtml.title in Windows PowerShell 5.1.'}
if([bool]$config.AutoResearchAfterScan){throw 'AutoResearchAfterScan must be disabled.'}
if([bool]$config.UnknownAutoResearchEnabled){throw 'UnknownAutoResearchEnabled must be disabled.'}
if($research -notmatch 'Get-YumResearchEvidenceFingerprint'){throw 'Evidence fingerprint persistence missing.'}
if($research -notmatch 'Get-YumServiceResearch'){throw 'Service evidence collection missing.'}
if($research -notmatch 'ResearchEvidenceFingerprint'){throw 'Research evidence fingerprint field missing.'}
if($research -notmatch "ResearchStatus='Organized'"){Write-Output 'Note: terminal Organized state is generated dynamically.'}
if($dialogs -notmatch 'Live record merging was intentionally retired in 5.2.49'){throw 'Live research merge retirement marker missing.'}
if($dialogs -match 'Merge-YumLiveResearchResults -State'){throw 'Live research merge invocation remains in UI timer.'}
if($dialogs -match 'Start-YumIntelligenceResearchAsync -State \$ctx -Records \$researchInput' -and $dialogs -match 'AutoResearchAfterScan'){throw 'Scan path still contains automatic research invocation.'}
Write-Output 'ResearchEngineV2RegressionTest: PASS'
