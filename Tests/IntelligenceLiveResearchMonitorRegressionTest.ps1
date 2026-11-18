$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$dialogs=Get-Content (Join-Path $root 'UI\Dialogs.ps1') -Raw
$research=Get-Content (Join-Path $root 'Core\Research.ps1') -Raw
$xaml=Get-Content (Join-Path $root 'UI\Xaml\Intelligence.xaml') -Raw
$errors=New-Object System.Collections.Generic.List[string]
if($research -notmatch "research-live-results\.json"){$errors.Add('Research live checkpoint must use one shared file.')}
if($dialogs -notmatch 'function Remove-YumOwnedResearchLiveCheckpoint'){$errors.Add('Research checkpoint cleanup must be run-owner safe.')}
if($research -match "research-live-results-\{0\}-\{1:D6\}"){ $errors.Add('Per-item live checkpoint filenames must be removed.')}
if($dialogs -notmatch "function Merge-YumLiveResearchResults"){$errors.Add('Live Research merge function missing.')}
if($dialogs -notmatch "Join-Path \$script:Yum.Root 'research-live-results\.json'"){$errors.Add('GUI must consume the single live Research checkpoint.')}
if($dialogs -notmatch "Add-Member -NotePropertyName ResearchStatus -NotePropertyValue 'Researching'"){$errors.Add('GUI must mark the current item as Researching.')}
if($dialogs -notmatch "Merge-YumLiveResearchResults -State \$state"){$errors.Add('Opening Intelligence must attach to an existing Research pass.')}
if($dialogs -notmatch "Merge-YumLiveResearchResults -State \$ctx.State -RunId \$ctx.RunId"){$errors.Add('Active Research poll must merge live checkpoints.')}
if($xaml -notmatch 'x:Name="RunResearch"'){$errors.Add('RUN RESEARCH button missing.')}
if($xaml -notmatch 'x:Name="ResearchingCount"'){$errors.Add('RESEARCHING counter missing.')}
if($errors.Count -gt 0){$errors | ForEach-Object {Write-Host "FAIL: $_"};exit 1}
Write-Host 'PASS: Intelligence live Research monitor contract is present.'
