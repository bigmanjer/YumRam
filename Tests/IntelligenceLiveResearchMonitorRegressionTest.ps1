$ErrorActionPreference='Stop'
# 5.3.0: literal .Contains() checks. The 5.2.x version used double-quoted regexes, so "\$state"
# was expanded by PowerShell before matching and the test always failed.
$root=Split-Path -Parent $PSScriptRoot
$dialogs=Get-Content (Join-Path $root 'UI\Dialogs.ps1') -Raw
$research=Get-Content (Join-Path $root 'Core\Research.ps1') -Raw
$xaml=Get-Content (Join-Path $root 'UI\Xaml\Intelligence.xaml') -Raw
$errors=New-Object System.Collections.Generic.List[string]
function Need([bool]$Condition,[string]$Message){if(-not $Condition){$errors.Add($Message)}}
Need $research.Contains('research-live-results.json') 'Research live checkpoint must use one shared file.'
Need $dialogs.Contains('function Remove-YumOwnedResearchLiveCheckpoint') 'Research checkpoint cleanup must be run-owner safe.'
Need (-not $research.Contains('research-live-results-{0}-{1:D6}')) 'Per-item live checkpoint filenames must be removed.'
Need $dialogs.Contains('function Merge-YumLiveResearchResults') 'Live Research merge function missing.'
Need $dialogs.Contains("Join-Path `$script:Yum.Root 'research-live-results.json'") 'GUI must consume the single live Research checkpoint.'
Need $dialogs.Contains("Add-Member -NotePropertyName ResearchStatus -NotePropertyValue 'Researching'") 'GUI must mark the current item as Researching.'
Need $dialogs.Contains('Merge-YumLiveResearchResults -State $state') 'Opening Intelligence must attach to an existing Research pass.'
Need $dialogs.Contains('Merge-YumLiveResearchResults -State $ctx.State -RunId $ctx.RunId') 'Active Research poll must merge live checkpoints.'
Need $xaml.Contains('x:Name="RunResearch"') 'RUN RESEARCH button missing.'
Need $xaml.Contains('x:Name="ResearchingCount"') 'RESEARCHING counter missing.'
if($errors.Count -gt 0){$errors | ForEach-Object {Write-Host "FAIL: $_"};exit 1}
Write-Host 'PASS: Intelligence live Research monitor contract is present.'
