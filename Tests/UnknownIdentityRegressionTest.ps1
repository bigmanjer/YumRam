#requires -Version 5.1
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$i = Get-Content -LiteralPath (Join-Path $root 'Core\Intelligence.ps1') -Raw
$s = Get-Content -LiteralPath (Join-Path $root 'Core\Scanner.ps1') -Raw
$sf = Get-Content -LiteralPath (Join-Path $root 'Core\Safety.ps1') -Raw
$checks = [ordered]@{
    'Intelligence defines Unknown identity state' = $i.Contains("IdentityState='Unknown'")
    'Unknown identities require research before cleanup' = $i.Contains('Research before automatic cleanup')
    'Unknown identities are auto-research eligible' = $i.Contains('AutoResearchEligible=$true')
    # The Protected/Unknown cleanup exclusion lives in the candidate selector (Safety.ps1).
    'Cleanup skips Protected and Unknown' = $sf.Contains('$classification.Risk -eq ''Protected'' -or $classification.Risk -eq ''Unknown''')
    'Scanner carries AutoResearchEligible' = $s.Contains('AutoResearchEligible')
    'Scanner carries UnknownReason' = $s.Contains('UnknownReason')
    'Scanner carries IdentityConfidence' = $s.Contains('IdentityConfidence')
}
$failed = @($checks.GetEnumerator() | Where-Object { -not $_.Value } | ForEach-Object { $_.Key })
if($failed.Count -gt 0){throw ('Unknown identity regression contract failed: ' + ($failed -join '; '))}
Write-Host 'Unknown identity regression test passed.'
