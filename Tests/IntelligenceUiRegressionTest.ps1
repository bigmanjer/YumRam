#requires -Version 5.1
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$xamlPath=Join-Path $root 'UI\Xaml\Intelligence.xaml'
$dialogPath=Join-Path $root 'UI\Dialogs.ps1'
$researchPath=Join-Path $root 'Core\Research.ps1'
[xml]$xaml=Get-Content -LiteralPath $xamlPath -Raw
$dialog=Get-Content -LiteralPath $dialogPath -Raw
$research=Get-Content -LiteralPath $researchPath -Raw
$buttons=@('Refresh','RunResearch','Close')
foreach($name in $buttons){ if(-not $dialog.Contains("FindName('$name')")){throw "Missing UI control wiring: $name"} }
foreach($name in @('ScannedCount','ReviewCount','ResearchingCount','ResolvedCount','UnknownCount','ProtectedCount','CachedCount','ResearchErrorCount','ResearchProgress','SelectedResearch','SelectedAction')){ if(-not $dialog.Contains("FindName('$name')")){throw "Missing intelligence status control: $name"} }
if($dialog -match "FindName\('Optimize'\)"){throw 'Obsolete Optimize button wiring remains in Intelligence.'}
foreach($needle in @('Review Queue','Needs Research','Researching','Research Errors','Cached / Knowledge','Organized','Unknown','Protected','Games','Apps','Services','Startup','Drivers / Hardware','Processes','All Items','RunResearch')){ if(-not $xaml.OuterXml.Contains($needle)){throw "Expected Intelligence view/action missing: $needle"} }
if(-not $dialog.Contains('$ctx.ForceFreshResearch=$true;$ctx.ResearchPendingManual=$false')){throw 'Research Selected does not force a fresh single-item research run.'}
if(-not $xaml.OuterXml.Contains('VirtualizingStackPanel.VirtualizationMode="Recycling"')){throw 'Intelligence results are missing virtualization/recycling.'}
if(-not $xaml.OuterXml.Contains('VirtualizingStackPanel.IsVirtualizing="True"')){throw 'Intelligence results are not virtualized.'}
# 5.4: the ComboBox templates live in the shared theme (UI\Xaml\Theme.xaml), loaded before every window.
$theme=Get-Content -LiteralPath (Join-Path $root 'UI\Xaml\Theme.xaml') -Raw
if(-not $theme.Contains('TargetType="ComboBoxItem"')){throw 'ComboBox item template is missing from the theme.'}
if(-not $theme.Contains('x:Name="PART_Popup"')){throw 'ComboBox popup template is missing from the theme.'}
if(-not $theme.Contains('TextElement.Foreground="{StaticResource Text}"')){throw 'ComboBox selected text foreground is not explicit in the theme.'}
if($xaml.OuterXml.Contains('TargetType="ComboBox"') -or $xaml.OuterXml.Contains('TargetType="{x:Type ComboBox}"')){throw 'Intelligence.xaml redefines ComboBox styles and would override the theme.'}
if($xaml.OuterXml.Contains('Header="Action"')){throw 'Action column must remain in the selected-item panel.'}
if($dialog -match 'Search.Add_TextChanged\([^)]*Update-YumIntelligenceList'){throw 'Search still rebuilds the list on every keystroke.'}
if($dialog -notmatch 'SearchTimer.*FromMilliseconds\(250\)'){throw 'Search debounce timer missing.'}
if($dialog -notmatch 'FromMilliseconds\(400\)'){throw 'Research polling cadence regression.'}
if($dialog -notmatch '1 at a time'){throw 'Single-item research mode is not visible to the user.'}
if($dialog -match 'OverviewMessage\.Text='){throw 'Title/overview text is being overwritten dynamically.'}
if($research -notmatch '\$researchConcurrency=1'){throw 'Research worker is not locked to single-item mode.'}
if($research -notmatch 'Researching Item'){throw 'Per-item research stage is missing.'}
if($research -match 'ForEach-Object -Parallel|Start-Job|Start-ThreadJob|Task\.Run'){throw 'Parallel research path detected; research must remain single-item.'}
Write-Host 'YUMRAM IntelligenceUiRegressionTest PASSED'

$xamlRaw = (Get-Content -LiteralPath (Join-Path $root 'UI\Xaml\Intelligence.xaml') -Raw) + $theme
if($xamlRaw -match '<ContentPresenter[^>]*\sForeground='){ throw 'Invalid WPF ContentPresenter.Foreground usage detected in Intelligence.xaml or the theme.' }
if($xamlRaw -notmatch 'TextElement\.Foreground="\{TemplateBinding Foreground\}"'){ throw 'ComboBoxItem text foreground binding is missing.' }

if($research -notmatch 'Write-YumResearchDiagnostic'){throw 'Dedicated Research-Diagnostics logging function missing.'}
if($research -notmatch 'Research-Diagnostics\.log'){throw 'Dedicated research diagnostics log path missing.'}
if($dialog -notmatch 'Research worker failure'){throw 'Worker failure preservation/logging path missing.'}
if($dialog -notmatch 'errorRecords'){throw 'Worker failure path does not preserve per-record errors.'}
