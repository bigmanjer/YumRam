#requires -Version 5.1
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$xaml=Get-Content -LiteralPath (Join-Path $root 'UI\Xaml\Intelligence.xaml') -Raw
$dialogs=Get-Content -LiteralPath (Join-Path $root 'UI\Dialogs.ps1') -Raw
$scanner=Get-Content -LiteralPath (Join-Path $root 'Core\Scanner.ps1') -Raw
if($xaml -notmatch 'x:Name="Refresh" Content="[^"
]*RUN SCAN') { throw 'RUN SCAN button missing.' }
if($xaml -notmatch 'x:Name="RunResearch" Content="[^"
]*RUN RESEARCH') { throw 'RUN RESEARCH button missing.' }
foreach($forbidden in @('FreshScan','ClearResearchCache','ClearKnowledge','ClearRescan','RetryResearch')) { if($xaml -match ('x:Name="'+$forbidden+'"')) { throw ('Forbidden Intelligence control remains: '+$forbidden) } }
if($dialogs -match 'Start-YumIntelligenceScanAsync -State $ctx\s*\)\s*\}\)\s*\n\s*\$timer') { throw 'Automatic Intelligence timer path remains.' }
if($scanner -match '\[switch\]\$Research') { throw 'Scanner still exposes a research execution switch; research must be orchestrated by the Intelligence layer.' }
if($scanner -match 'if\(-not \$SkipResearch\)') { throw 'Scanner still defaults into research.' }
'PASS'

$dialogs = Get-Content -LiteralPath (Join-Path $root 'UI\Dialogs.ps1') -Raw
if($dialogs -notmatch 'automatically researching'){throw 'Scan path does not automatically queue unresolved research'}
if($dialogs -notmatch 'Run Research remains available for retry'){throw 'Manual Run Research retry path is not documented in the scan flow'}
