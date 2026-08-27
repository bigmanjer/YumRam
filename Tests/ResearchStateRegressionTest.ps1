#requires -Version 5.1
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'Core\Research.ps1')
. (Join-Path $root 'Core\Intelligence.ps1')
. (Join-Path $root 'Core\Scanner.ps1')
. (Join-Path $root 'Core\Cleanup.ps1')
$script:Yum=[pscustomobject]@{Config=[pscustomobject]@{ResearchCacheMaxAgeDays=30;EnableOnlineResearch=$false;IntelligenceResearchEnabled=$true;ResearchEngineVersion='test'};Root=$root}
$fail=@()
function Assert-True([bool]$Condition,[string]$Message){if(-not $Condition){$script:fail += $Message}}
function New-Record {
    param([string]$Risk='Review',[string]$Category='Apps',[string]$Status='Not Researched',[string]$Placement='',[string]$Action='Review before management',[bool]$Live=$true)
    [pscustomobject]@{Key=[guid]::NewGuid().ToString('N');StableIdentityKey='';Name='Test';Category=$Category;Risk=$Risk;ResearchStatus=$Status;ResearchComplete=($Status -in @('Organized','Unknown'));ResearchExhausted=($Status -in @('Organized','Unknown'));Placement=$Placement;ActionLane=$Action;ManualOverride=$false;Live=$Live;Path='C:\Test\test.exe';Publisher='Test'}
}
$protected=New-Record -Risk Protected -Category Protected -Status 'Not Researched'
Assert-True (-not (Test-YumResearchUnresolved -Record $protected)) 'Protected terminal record incorrectly queued.'
$protectedReview=New-Record -Risk Protected -Category Protected -Status 'Not Researched' -Placement 'Review Queue' -Action 'Review before management'
Assert-True (Test-YumResearchUnresolved -Record $protectedReview) 'Explicitly reviewed Protected record was not queued.'
$review=New-Record -Risk Review -Category Apps -Status 'Not Researched'
Assert-True (Test-YumResearchUnresolved -Record $review) 'Review record was not queued.'
$organized=New-Record -Risk Candidate -Category Apps -Status Organized -Placement 'Identified Applications' -Action 'Candidate under memory pressure'
Assert-True (-not (Test-YumResearchUnresolved -Record $organized)) 'Organized record remained queued.'
$unknown=New-Record -Risk Unknown -Category 'Unknown / Quarantine' -Status Unknown -Placement 'Unknown / Quarantine for Review' -Action 'Never manage automatically'
Assert-True (-not (Test-YumResearchUnresolved -Record $unknown)) 'Unknown terminal record remained queued.'
$err=New-Record -Risk Review -Category Apps -Status 'Research Error' -Placement 'Review Queue' -Action 'Review before management'
Assert-True (Test-YumResearchUnresolved -Record $err) 'Retryable Research Error was not queued.'
# Stable vs live instance identity: same executable shares StableIdentityKey but unique live Key.
$stable=(Get-YumStableIntelligenceKeyFromValues -Source Process -Name chrome -Path 'C:\Program Files\Google\Chrome\Application\chrome.exe' -Publisher 'Google LLC')
$live1=Get-YumLiveIntelligenceRecordKey -StableIdentityKey $stable -Source Process -ProcessId 1001
$live2=Get-YumLiveIntelligenceRecordKey -StableIdentityKey $stable -Source Process -ProcessId 1002
Assert-True ($live1 -ne $live2) 'Concurrent process live keys collided.'
Assert-True ($stable -ne $live1 -and $stable -ne $live2) 'Live process key did not remain distinct from stable identity.'
# Review header predicate semantics: live unresolved count excludes saved/offline rows.
$rows=@($review,$organized,($review.PSObject.Copy()))
$rows[2].Live=$false
$count=@($rows | Where-Object {$_.Live -and (Test-YumResearchUnresolved -Record $_)}).Count
Assert-True ($count -eq 1) 'Review count predicate includes saved/offline records.'
if($fail.Count -gt 0){$fail|ForEach-Object{Write-Error $_};exit 1}
Write-Host 'YUMRAM ResearchStateRegressionTest PASSED.'

# Gradual memory reclaim plan: small-first, target-aware, mode-limited.
$script:Yum.Config.SafeProcessesPerPass=2
$script:Yum.Config.BalancedProcessesPerPass=3
$script:Yum.Config.AggressiveProcessesPerPass=5
$profileSafe=Get-YumModeProfile
Assert-True ($profileSafe.PassLimit -eq 2) 'Safe profile pass limit not capped at 2.'
$trimCandidates=@(
    [pscustomobject]@{WorkingSet=120MB;Score=12},
    [pscustomobject]@{WorkingSet=180MB;Score=10},
    [pscustomobject]@{WorkingSet=300MB;Score=40},
    [pscustomobject]@{WorkingSet=700MB;Score=95}
)
$smallFirst=@(Get-YumTrimPlan -Candidates $trimCandidates -AvailableGB 3.60 -TargetGB 4.00 -PassLimit 2 -MaxTrimMBPerPass 384)
Assert-True ($smallFirst.Count -eq 2) 'Gradual trim plan did not respect pass limit.'
Assert-True ([double]$smallFirst[0].WorkingSet -le [double]$smallFirst[1].WorkingSet) 'Trim plan did not select smallest working sets first.'
$noOvershoot=@(Get-YumTrimPlan -Candidates @([pscustomobject]@{WorkingSet=700MB;Score=99}) -AvailableGB 3.70 -TargetGB 4.00 -PassLimit 2 -MaxTrimMBPerPass 1024)
Assert-True ($noOvershoot.Count -eq 1) 'Adaptive trim plan failed to select the first eligible candidate when it exceeded the remaining target gap but fit the safety budget.'

# Gaming cleanup profile: capped actions, longer pacing, no oversized intentional reclaim.
$script:Yum.Config.Mode='Balanced'
$profileBalanced=Get-YumModeProfile
Assert-True ($profileBalanced.PassLimit -eq 3) 'Balanced cleanup pass limit is not 3.'
Assert-True ($profileBalanced.StepDelayMs -ge 200) 'Balanced cleanup pacing is too aggressive.'
$script:Yum.Config.Mode='Aggressive'
$profileAgg=Get-YumModeProfile
Assert-True ($profileAgg.PassLimit -eq 5) 'Aggressive cleanup pass limit is not capped at 5.'
Assert-True ($profileAgg.StepDelayMs -lt $profileBalanced.StepDelayMs) 'Aggressive mode did not increase cleanup speed relative to Balanced.'

$script:Yum.Config.Mode='Safe';$gameSafe=Get-YumGamingCleanupProfile -BaseProfile (Get-YumModeProfile)
$script:Yum.Config.Mode='Balanced';$gameBalanced=Get-YumGamingCleanupProfile -BaseProfile (Get-YumModeProfile)
$script:Yum.Config.Mode='Aggressive';$gameAgg=Get-YumGamingCleanupProfile -BaseProfile (Get-YumModeProfile)
Assert-True ($gameSafe.PassLimit -eq 1 -and $gameBalanced.PassLimit -eq 2 -and $gameAgg.PassLimit -eq 3) 'Gaming mode caps do not scale with active cleanup mode.'
Assert-True ($gameSafe.StepDelayMs -gt $gameBalanced.StepDelayMs -and $gameBalanced.StepDelayMs -gt $gameAgg.StepDelayMs) 'Gaming pacing does not get gradually more aggressive by mode.'
Assert-True ($gameSafe.OptionalApps -eq 0 -and $gameBalanced.OptionalApps -eq 0 -and $gameAgg.OptionalApps -eq 0) 'Gaming profile still permits optional background shutdown.'
