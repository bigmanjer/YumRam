$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$dialogs=Get-Content (Join-Path $root 'UI\Dialogs.ps1') -Raw
$errors=@()
if($dialogs -notmatch 'RunResearch\.Add_Click'){ $errors+='RunResearch click handler missing.' }
if($dialogs -notmatch 'RunResearch\.IsEnabled=\(-not \$State\.Busy -and -not \$State\.ResearchBusy -and \$all\.Count -gt 0\)'){ $errors+='Research button should remain enabled whenever records are loaded.' }
if($dialogs -match 'unresolved items will be researched automatically'){ $errors+='Stale automatic research wording remains in Dialogs.ps1.' }
if($errors.Count){ $errors | ForEach-Object { Write-Error $_ }; exit 1 }
Write-Host 'Research button regression test PASS.'
