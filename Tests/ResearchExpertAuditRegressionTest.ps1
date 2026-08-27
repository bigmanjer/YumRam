$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$cfg=Get-Content (Join-Path $root 'Config\default-config.json') -Raw | ConvertFrom-Json
if([string]$cfg.Version -ne '5.2.74'){throw 'Config version mismatch.'}
if([string]$cfg.ResearchEngineVersion -ne '5.2.74'){throw 'Research engine version mismatch.'}
$ver=(Get-Content (Join-Path $root 'VERSION') -Raw).Trim()
if($ver -ne '5.2.74'){throw 'VERSION file mismatch.'}
$intel=Get-Content (Join-Path $root 'Core\Intelligence.ps1') -Raw
$research=Get-Content (Join-Path $root 'Core\Research.ps1') -Raw
$dialogs=Get-Content (Join-Path $root 'UI\Dialogs.ps1') -Raw
if($intel -notmatch 'function Ensure-YumIntelligenceRecordSchema'){throw 'Record schema function missing.'}
if($intel -notmatch "Signature='Unknown'"){throw 'Signature fallback missing.'}
if($research -notmatch 'function Get-YumResearchSafeProperty'){throw 'Research safe property helper missing.'}
if($research -match '\$cached\.Signature\b'){throw 'Unsafe cached Signature access remains.'}
if($dialogs -match '\$r\.Signature\b'){throw 'Unsafe UI Signature access remains.'}
if($dialogs -notmatch 'Ensure-YumIntelligenceRecordSchema -Record \$r'){throw 'Selection normalization missing.'}
if($dialogs -notmatch 'RUN RESEARCH is executing'){throw 'Manual research execution UI contract missing.'}
Write-Host 'ResearchExpertAuditRegressionTest: PASS'
