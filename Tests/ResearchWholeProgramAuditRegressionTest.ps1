$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$research=Get-Content (Join-Path $root 'Core\Research.ps1') -Raw
$dialogs=Get-Content (Join-Path $root 'UI\Dialogs.ps1') -Raw
$config=Get-Content (Join-Path $root 'Config\default-config.json') -Raw | ConvertFrom-Json
$ver=(Get-Content (Join-Path $root 'VERSION') -Raw).Trim()
function Assert-C([bool]$Condition,[string]$Message){if(-not $Condition){throw $Message}}
Assert-C ($ver -eq '5.2.74') 'VERSION must be 5.2.74.'
Assert-C ([string]$config.Version -eq '5.2.74') 'Config Version must be 5.2.74.'
Assert-C ([string]$config.ResearchEngineVersion -eq '5.2.74') 'ResearchEngineVersion must be 5.2.74.'
Assert-C ($research.Contains('$onlineOperationalError=')) 'Online no-match/error distinction missing.'
Assert-C ($research.Contains('$strongIdentityPromotion=')) 'Strong local identity promotion missing.'
Assert-C ($research.Contains("ResearchComplete -NotePropertyValue $true")) 'Terminal worker failure contract missing.'
Assert-C ($dialogs.Contains('Never let a transient status file regress an already terminal record.')) 'UI stale-status guard missing.'
Assert-C ($dialogs.Contains('if($existingTerminal -and $updatedTransient){continue}')) 'Live merge stale-result guard missing.'
Write-Output 'PASS Research whole-program audit contracts.'
