#requires -Version 5.1
$ErrorActionPreference='Stop'
# 5.3.0: rewritten for the current scan flow (RUN SCAN researches unresolved items automatically;
# the Run Research button is labelled AUTOMATIC RESEARCH). The 5.2.x regexes contained a literal
# newline inside a character class and expected RUN SCAN on both buttons.
$root=Split-Path -Parent $PSScriptRoot
[xml]$xaml=Get-Content -LiteralPath (Join-Path $root 'UI\Xaml\Intelligence.xaml') -Raw
$xamlText=$xaml.OuterXml
$dialogs=Get-Content -LiteralPath (Join-Path $root 'UI\Dialogs.ps1') -Raw
$scanner=Get-Content -LiteralPath (Join-Path $root 'Core\Scanner.ps1') -Raw
function Get-ButtonContent([string]$Name){
    $node=$xaml.SelectSingleNode("//*[local-name()='Button' and @*[local-name()='Name']='$Name']")
    if($null -eq $node){return $null}
    return [string]$node.GetAttribute('Content')
}
$scan=Get-ButtonContent 'Refresh'
if($null -eq $scan -or $scan -notmatch 'RUN SCAN'){ throw "RUN SCAN button missing (Refresh content: '$scan')." }
if($null -eq (Get-ButtonContent 'RunResearch')){ throw 'Run Research button missing.' }
foreach($forbidden in @('FreshScan','ClearResearchCache','ClearKnowledge','ClearRescan','RetryResearch')) { if($xamlText.Contains('Name="'+$forbidden+'"')) { throw ('Forbidden Intelligence control remains: '+$forbidden) } }
if($scanner -match '\[switch\]\$Research') { throw 'Scanner still exposes a research execution switch; research must be orchestrated by the Intelligence layer.' }
if($scanner -match 'if\(-not \$SkipResearch\)') { throw 'Scanner still defaults into research.' }
if(-not $dialogs.Contains('automatically researching')){ throw 'Scan path does not automatically queue unresolved research.' }
'PASS'
