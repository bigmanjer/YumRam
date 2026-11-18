$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$p=Join-Path $root 'UI\Dialogs.ps1'
$t=Get-Content -LiteralPath $p -Raw
$m=[regex]::Match($t,'(?ms)^function Start-YumOptionalBackgroundScanAsync\s*\{.*?^function Show-YumBloatManager\s*\{')
if(-not $m.Success){throw 'Optional background scan worker boundaries are missing.'}
$block=$m.Value
if($block -notmatch '\.AddScript\(\{param\(\$root,\$config,\$fg,\$gamePid\)'){throw 'Worker AddScript block is missing.'}
if($block -notmatch '\$async=\$worker\.BeginInvoke\(\)'){throw 'Worker BeginInvoke is missing.'}
if($block -notmatch '\}\)\.AddArgument\(\$root\)'){throw 'Worker AddScript closing boundary is missing.'}
'PASS — optional background scan worker structure'
