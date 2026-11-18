#requires -Version 5.1
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$intelligence = Join-Path $root 'Core\Intelligence.ps1'
$scanner = Join-Path $root 'Core\Scanner.ps1'
$safety = Join-Path $root 'Core\Safety.ps1'
foreach($p in @($intelligence,$scanner,$safety)){if(-not(Test-Path -LiteralPath $p)){throw "Missing required source: $p"}}
$i = Get-Content -LiteralPath $intelligence -Raw
$s = Get-Content -LiteralPath $scanner -Raw
$sf = Get-Content -LiteralPath $safety -Raw
$checks = @([bool]($i -match "IdentityState='Unknown'"),[bool]($i -match "Research before automatic cleanup"),[bool]($i -match "AutoResearchEligible=\$true"),[bool]($s -match "\$classification\.Risk -eq 'Protected' -or \$classification\.Risk -eq 'Unknown'"),[bool]($s -match 'AutoResearchEligible'),[bool]($s -match 'UnknownReason'),[bool]($s -match 'IdentityConfidence'),[bool]($sf -match 'Unknown'))
if(@($checks|Where-Object{$_ -eq $false}).Count -gt 0){throw 'Unknown identity regression contract failed.'}
Write-Host 'Unknown identity regression test passed.'
