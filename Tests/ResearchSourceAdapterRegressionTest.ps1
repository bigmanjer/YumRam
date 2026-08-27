$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'Core\Research.ps1')
foreach($name in @('Get-YumResearchParentFolderEvidence','Get-YumInstalledSoftwareResearch','Get-YumAppxResearch','Get-YumServiceResearch','Get-YumOnlineResearch')){if($null -eq (Get-Command $name -ErrorAction SilentlyContinue)){throw "Missing function: $name"}}
$services=(Get-Command Get-YumServiceResearch).ScriptBlock.ToString()
if($services -match 'Select-Object -First 5'){throw 'Legacy service research implementation remained active.'}
if((@($s=Get-Command Get-YumServiceResearch)).Count -ne 1){throw 'Duplicate service research command surface.'}
Write-Output 'ResearchSourceAdapterRegressionTest: PASS'
