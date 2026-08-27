#requires -Version 5.1
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$dialogs=Get-Content -LiteralPath (Join-Path $root 'UI\Dialogs.ps1') -Raw
if($dialogs -match '(?m)^[^$]*\(if\s*\('){throw 'Invalid parenthesized if expression remains in UI/Dialogs.ps1.'}
if($dialogs -notmatch '\$cachedCount\s*=\s*0'){throw 'Research cached-count normalization is missing.'}
if($dialogs -notmatch '\$timeoutFooter\s*=\s*if'){throw 'Research timeout footer normalization is missing.'}
Write-Host 'YUMRAM ResearchResultUiPowerShell51RegressionTest PASSED.'
