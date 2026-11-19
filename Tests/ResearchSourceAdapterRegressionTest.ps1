$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'Core\Research.ps1')
foreach($name in @('Get-YumResearchParentFolderEvidence','Get-YumInstalledSoftwareResearch','Get-YumAppxResearch','Get-YumServiceResearch','Get-YumOnlineResearch')){if($null -eq (Get-Command $name -ErrorAction SilentlyContinue)){throw "Missing function: $name"}}
$services=(Get-Command Get-YumServiceResearch).ScriptBlock.ToString()
if($services -match 'Select-Object -First 5'){throw 'Legacy service research implementation remained active.'}
# 5.2.x wrote "@($s=Get-Command ...)" which yields nothing (assignment has no output), so Count was always 0.
$definitions=([regex]::Matches((Get-Content -LiteralPath (Join-Path $root 'Core\Research.ps1') -Raw),'(?m)^\s*function\s+Get-YumServiceResearch\b')).Count
if($definitions -ne 1){throw "Duplicate service research command surface ($definitions definitions)."}
Write-Output 'ResearchSourceAdapterRegressionTest: PASS'
