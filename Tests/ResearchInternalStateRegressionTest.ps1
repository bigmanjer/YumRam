#requires -Version 5.1
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$config=Get-Content -LiteralPath (Join-Path $root 'Config\default-config.json') -Raw | ConvertFrom-Json
$runtime=Get-Content -LiteralPath (Join-Path $root 'Core\Config.ps1') -Raw
$research=Get-Content -LiteralPath (Join-Path $root 'Core\Research.ps1') -Raw
if($runtime -notmatch 'ResearchState\s*=\s*\[pscustomobject\]'){throw 'Runtime ResearchState object missing.'}
foreach($field in @('Phase','Stage','Index','Total','Key','Name','Message','Confidence','Completed','Updated','Error')){if($runtime -notmatch ('ResearchState\s*=.*?'+[regex]::Escape($field)+'=')){throw "ResearchState field missing: $field"}}
if($research -notmatch '\$script:Yum\.ResearchState\.Phase'){throw 'ResearchState phase is not updated by research status publishing.'}
if($research -notmatch '\$script:Yum\.ResearchState\.Stage'){throw 'ResearchState stage is not updated by research status publishing.'}
if($research -notmatch '\$script:Yum\.ResearchState\.Confidence'){throw 'ResearchState confidence is not updated by research status publishing.'}
if($config.AutoResearchAfterScan -ne $true){throw 'Automatic research after scan is not enabled in the audited default configuration.'}
if($config.UnknownAutoResearchEnabled -ne $true){throw 'Automatic unknown-process research is not enabled in the audited default configuration.'}
Write-Host 'ResearchInternalStateRegressionTest PASSED.'
