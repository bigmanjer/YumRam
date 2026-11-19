$ErrorActionPreference='Stop'
$Research=Join-Path (Split-Path -Parent $PSScriptRoot) 'Core\Research.ps1'
$s=Get-Content -LiteralPath $Research -Raw
if($s.Contains('$Risk -in @(''Candidate'',''Safe to Manage'')')){ Write-Host 'FAIL: old Application Risk gate remains'; exit 1 }
# Strong local identity, or >=85 confidence with multi-source proof, promotes an Application even if its initial Risk was Review.
if(-not $s.Contains('$action=if($strongIdentityPromotion -or ($confidence -ge 85 -and $multiSourceProof)){''Candidate under memory pressure''}')){ Write-Host 'FAIL: strong Application promotion contract missing'; exit 1 }
Write-Host 'PASS: strong identity promotion is not blocked by initial Risk=Review.'
exit 0
