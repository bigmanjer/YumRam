$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$research = Get-Content -LiteralPath (Join-Path $root 'Core\Research.ps1') -Raw
$dialogs = Get-Content -LiteralPath (Join-Path $root 'UI\Dialogs.ps1') -Raw
$failures = New-Object System.Collections.Generic.List[string]

if(-not $research.Contains('Global\YUMRAM-ResearchLiveCheckpoint')){[void]$failures.Add('Research writer does not use the shared checkpoint mutex.')}
if(-not $dialogs.Contains('Global\YUMRAM-ResearchLiveCheckpoint')){[void]$failures.Add('Intelligence checkpoint reader does not use the shared checkpoint mutex.')}
if($research.Contains('research-live-results.{0}.tmp') -or $research.Contains('research-live-results.\{0\}.tmp')){[void]$failures.Add('Writer still creates an orphan-prone unique temp file per checkpoint.')}
if(-not $research.Contains('Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue')){[void]$failures.Add('Writer does not clean the checkpoint temp file in finally.')}
if(-not $dialogs.Contains("research-queue-*.json")){[void]$failures.Add('Startup transport cleanup is missing queue artifact cleanup.')}
if(-not $dialogs.Contains("research-config-*.json")){[void]$failures.Add('Startup transport cleanup is missing config artifact cleanup.')}
if(-not $dialogs.Contains('Research worker transport received: records=')){[void]$failures.Add('Worker transport receipt diagnostic is missing.')}

if($failures.Count -gt 0){$failures | ForEach-Object { Write-Host ('FAIL ' + $_) }; exit 1}
Write-Host 'PASS Research live checkpoint concurrency and transport cleanup contracts'
exit 0
