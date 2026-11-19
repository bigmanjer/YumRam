#requires -Version 5.1
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$dialogs=Get-Content -LiteralPath (Join-Path $root 'UI\Dialogs.ps1') -Raw
$assign=$dialogs.IndexOf('$researchInput=@($ctx.State.Data.Records | Where-Object')
$complete=$dialogs.IndexOf('$ctx.State.ActivityStatus.Text=''SCAN COMPLETE''')
if($assign -lt 0){throw 'Scan completion does not build the unresolved research queue.'}
if($complete -lt 0){throw 'Scan completion UI state is missing.'}
if($assign -gt $complete){throw 'Regression: scan completion uses $researchInput before assigning it.'}
if(-not $dialogs.Contains('$ctx.State.ActivityStatus.Text=''SCAN ERROR''')){throw 'Scan exception path does not clear SCANNING state.'}
if(-not $dialogs.Contains('$ctx.State.ActivityStatus.Text=''SCAN TIMEOUT''')){throw 'Scan timeout path does not clear SCANNING state.'}
$busyPos=$dialogs.IndexOf('$ctx.State.Busy=$false')
$researchEnablePos=$dialogs.IndexOf('$ctx.State.RunResearch.IsEnabled=$hasRecords')
if($busyPos -lt 0 -or $researchEnablePos -lt $busyPos){throw 'Regression: Run Research is not re-enabled after Busy is cleared.'}
Write-Host 'YUMRAM IntelligenceScanCompletionRegressionTest PASSED.'
