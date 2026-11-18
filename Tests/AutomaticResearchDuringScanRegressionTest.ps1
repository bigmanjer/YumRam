$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$dialogs=Get-Content (Join-Path $root 'UI/Dialogs.ps1') -Raw
$xaml=Get-Content (Join-Path $root 'UI/Xaml/Intelligence.xaml') -Raw
if($dialogs -notmatch 'Start-YumIntelligenceResearchAsync -State \$ctx\.State -Records \$researchInput'){throw 'RUN SCAN no longer starts automatic research for unresolved records.'}
if($dialogs -notmatch 'automatically researching \{0\} unresolved items'){throw 'Automatic research status message missing.'}
if($xaml -notmatch 'x:Name="Refresh"[^>]*Content="🔍  RUN SCAN"'){throw 'RUN SCAN primary control missing.'}
if($xaml -notmatch 'x:Name="RunResearch"[^>]*Visibility="Collapsed"'){throw 'Separate normal RUN RESEARCH control is still visible.'}
Write-Output 'AutomaticResearchDuringScanRegressionTest: PASS'
