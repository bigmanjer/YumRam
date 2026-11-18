#requires -Version 5.1
$ErrorActionPreference = "Stop"
# Regression: PowerShell 5.1 collapses a pipeline result to a scalar when exactly one object matches.
$single = @([pscustomobject]@{Score=70} | Where-Object { $_.Score -ge 60 })
$multiple = @([pscustomobject]@{Score=70},[pscustomobject]@{Score=80} | Where-Object { $_.Score -ge 60 })
$empty = @([pscustomobject]@{Score=20} | Where-Object { $_.Score -ge 60 })
if($single.Count -ne 1){throw "Single-match materialization regression."}
if($multiple.Count -ne 2){throw "Multi-match materialization regression."}
if($empty.Count -ne 0){throw "Empty-match materialization regression."}
$research = Get-Content -LiteralPath (Join-Path $PSScriptRoot '..\Core\Research.ps1') -Raw
if($research -match '\(@\(\$RegistryEvidence\)\|Where-Object\{\[int\]\$_.Score -ge 60\}\)\.Count'){throw "Unsafe scalar pipeline Count pattern remains in Research.ps1."}
if($research -notmatch '@\(\$RegistryEvidence\|Where-Object\{\[int\]\$_.Score -ge 60\}\)\.Count'){throw "Registry evidence count is not array-materialized."}


# Regression: PowerShell 5.1 collapses a single Where-Object result to a scalar.
$signals0 = @($false,$false,$false,$false,$false) | Where-Object { $_ }
$signals1 = @($true,$false,$false,$false,$false) | Where-Object { $_ }
$signalsN = @($true,$true,$false,$false,$false) | Where-Object { $_ }
if(@($signals0).Count -ne 0){throw "Identity-signal zero-match regression."}
if(@($signals1).Count -ne 1){throw "Identity-signal single-match regression."}
if(@($signalsN).Count -ne 2){throw "Identity-signal multi-match regression."}
if($research -notmatch '\$identitySignals=@\(@\(\$registryStrong,\$signerMatches,\$wingetStrong,\$onlineStrong,\$fileStrong\)\|Where-Object\{\$_\}\)'){throw "Identity signals are not array-materialized before Count."}
if($research -match '\$identitySignals=@\(\$registryStrong,\$signerMatches,\$wingetStrong,\$onlineStrong,\$fileStrong\)\|Where-Object\{\$_\}'){throw "Unsafe identitySignals scalar pipeline remains in Research.ps1."}


# Regression: the online-search term set must stay array-backed for 0, 1, or many unique terms.
$terms0 = @('', $null, '   ') | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique
$terms1 = @('', $null, 'Chrome') | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique
$termsN = @('Google', 'Chrome', 'Browser') | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique
if(@($terms0).Count -ne 0){throw "Research-term zero-match regression."}
if(@($terms1).Count -ne 1){throw "Research-term single-match regression."}
if(@($termsN).Count -ne 3){throw "Research-term multi-match regression."}
if($research -notmatch '\$terms=@\(@\(\$Publisher,\$Product,\$Name\)\|Where-Object\{ -not \[string\]::IsNullOrWhiteSpace\(\$_\)\}\|Select-Object -Unique\)'){throw "Research terms are not array-materialized before Count."}
if($research -match '\$terms=@\(\$Publisher,\$Product,\$Name\)\|Where-Object\{ -not \[string\]::IsNullOrWhiteSpace\(\$_\)\}\|Select-Object -Unique'){throw "Unsafe research-term scalar pipeline remains in Research.ps1."}


# Regression: a function returning exactly one trim-plan object must remain count-safe at its caller.
$cleanup = Get-Content -LiteralPath (Join-Path $PSScriptRoot '..\Core\Cleanup.ps1') -Raw
if($cleanup -notmatch '\$selected=@\(Get-YumTrimPlan'){throw "Cleanup trim-plan result is not array-materialized before Count."}
if($cleanup -match '\$selected=Get-YumTrimPlan'){throw "Unsafe trim-plan scalar assignment remains in Cleanup.ps1."}

Write-Host 'ResearchScalarCountRegressionTest: PASS'
