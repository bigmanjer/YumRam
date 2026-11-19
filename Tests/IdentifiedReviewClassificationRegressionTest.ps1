#requires -Version 5.1
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'Core\Research.ps1')
$identified=[pscustomobject]@{Placement='Identified Applications';ActionLane='Review until identity is corroborated'}
if(-not (Test-YumResearchTerminalResult -PlacementResult $identified)){throw 'An identified application with a review-only action must complete research rather than be relabeled Unknown.'}
$unknown=[pscustomobject]@{Placement='Unknown / Quarantine for Review';ActionLane='Never manage automatically'}
if(-not (Test-YumResearchTerminalResult -PlacementResult $unknown)){throw 'Unknown placement must remain terminally quarantined.'}
Write-Host 'PASS identified review results remain identified and safe.'