# Requires: Windows PowerShell 5.1
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'Core\Research.ps1')

$system=Get-YumResearchPlacement -Name 'Memory Compression' -Path '' -Publisher 'Unknown' -Product '' -Signature '' -Category 'Processes' -Risk 'Unknown' -Reason 'Executable identity/path unavailable'
if($system.Placement -ne 'Security'){throw "System identity was not protected: $($system.Placement)"}
if($system.ResearchLinks.Count -ne 0){throw 'System identity unexpectedly produced web evidence.'}

$anchor = Test-YumResearchIdentityAnchor -Name 'chrome' -Path 'C:\Program Files\Google\Chrome\Application\chrome.exe' -Publisher 'Google LLC' -Product 'Google Chrome' -FileEvidence ([pscustomobject]@{Hash='abc';Product='Google Chrome';Company='Google LLC'}) -SignatureEvidence ([pscustomobject]@{Status='Valid';Thumbprint='abc'})
if(-not $anchor){throw 'Valid executable identity anchor was rejected.'}

$searchTrust=Get-YumResearchSourceTrust 'https://www.google.com/?hl=en'
if($searchTrust -ne 0){throw "Search engine page incorrectly trusted: $searchTrust"}

$cached=[pscustomobject]@{Placement='Unknown / Quarantine for Review';ActionLane='Never manage automatically'}
if(-not (Test-YumResearchTerminalResult $cached)){throw 'Unknown is not treated as terminal.'}
Write-Host 'ResearchQualityRegressionTest: PASS'
