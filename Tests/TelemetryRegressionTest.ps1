#requires -Version 5.1
[CmdletBinding()]
param([string]$Root)
if([string]::IsNullOrWhiteSpace($Root)){$Root=Split-Path -Parent $PSScriptRoot}
$errors = New-Object System.Collections.Generic.List[string]
$worker = Get-Content -LiteralPath (Join-Path $Root 'Core\TelemetryWorker.ps1') -Raw
$telemetry = Get-Content -LiteralPath (Join-Path $Root 'Core\Telemetry.ps1') -Raw
$config = Get-Content -LiteralPath (Join-Path $Root 'Core\Config.ps1') -Raw
if ($worker -notmatch "SnapshotVersion.*\+1") { [void]$errors.Add('TelemetryWorker does not increment SnapshotVersion.') }
if ($telemetry -notmatch "SnapshotVersion.*TelemetryCache") { [void]$errors.Add('Telemetry UI snapshot path does not read SnapshotVersion.') }
if ($config -notmatch 'SnapshotVersion = 0') { [void]$errors.Add('Telemetry cache missing SnapshotVersion.') }
if ($errors.Count -gt 0) { $errors | ForEach-Object { Write-Error $_ }; exit 1 }
'PASS: telemetry snapshot version contract is wired.'
