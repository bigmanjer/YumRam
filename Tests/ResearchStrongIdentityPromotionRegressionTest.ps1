$ErrorActionPreference='Stop'
$Research=Join-Path (Split-Path -Parent $PSScriptRoot) 'Core\Research.ps1'
$s=Get-Content -LiteralPath $Research -Raw
if($s -match "\$Risk -in @\('Candidate','Safe to Manage'\)") { Write-Host 'FAIL: old Application Risk gate remains'; exit 1 }
if($s -notmatch "\$action=if\(\$confidence -ge 85 -and \$multiSourceProof\)\{''Candidate under memory pressure''\}") { Write-Host 'FAIL: strong Application promotion contract missing'; exit 1 }
Write-Host 'PASS: strong identity promotion is not blocked by initial Risk=Review.'
exit 0
