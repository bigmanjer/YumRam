#requires -Version 5.1
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$dialogs=Get-Content -LiteralPath (Join-Path $root 'UI\Dialogs.ps1') -Raw
if($dialogs.Contains('Live record merging was intentionally retired')){throw 'Live Research snapshot merge is still disabled.'}
if(-not $dialogs.Contains('function Merge-YumLiveResearchResults')){throw 'Live Research snapshot merge function is missing.'}
if(-not $dialogs.Contains("Join-Path `$script:Yum.Root 'research-live-results.json'")){throw 'GUI does not consume the shared Research live snapshot file.'}
if($dialogs.Contains('research-live-results-{0}-*.json')){throw 'GUI still expects legacy per-item Research snapshot files.'}
if(-not $dialogs.Contains('ConvertFrom-Json -ErrorAction Stop')){throw 'GUI live snapshot JSON parsing is missing.'}
if(-not $dialogs.Contains('Update-YumIntelligenceList -State $State -Force')){throw 'GUI live snapshot merge does not force the Intelligence view refresh.'}
if(-not $dialogs.Contains('Merge-YumLiveResearchResults -State $ctx.State -RunId $ctx.RunId')){throw 'Research UI poller does not consume live snapshots while the worker runs.'}
Write-Host 'ResearchGuiLiveRefreshRegressionTest PASSED.'
