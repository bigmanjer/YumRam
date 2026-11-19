#requires -Version 5.1
# 5.5 behaviour: plain-language process guide, manual decisions resolve items, stale research status is
# ignored, protected processes are identified without a readable path, stronger reclaim wiring.
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'App\Bootstrap.ps1')
Initialize-YumConfig
. (Join-Path $root 'Core\Research.ps1')
$script:Yum.Config.Logging=$false
function Assert-That([bool]$Condition,[string]$Message){if(-not $Condition){throw $Message}}

# 1. Process guide
Assert-That ((Get-YumProcessKind -Name 'svchost' -Path '' -Company '' -HasWindow:$false -IsGame:$false -Record $null) -eq 'Windows') 'svchost should be Windows.'
Assert-That ((Get-YumProcessKind -Name 'MsMpEng' -Path '' -Company '' -HasWindow:$false -IsGame:$false -Record $null) -eq 'Security') 'Defender should be Security.'
Assert-That ((Get-YumProcessKind -Name 'somegame' -Path 'D:\Games\x.exe' -Company 'X' -HasWindow:$true -IsGame:$true -Record $null) -eq 'Game') 'The detected game should be Game.'
Assert-That ((Get-YumProcessKind -Name 'unknownthing' -Path 'C:\Tools\u.exe' -Company 'Acme' -HasWindow:$true -IsGame:$false -Record $null) -eq 'App') 'A windowed program should be App.'
Assert-That ((Get-YumProcessKind -Name 'ghost' -Path '' -Company '' -HasWindow:$false -IsGame:$false -Record $null) -eq 'Unknown') 'No path and no company should be Unknown.'
$x=Get-YumProcessExplanation -Name 'chrome' -Description '' -Company 'Google LLC' -Path 'C:\x\chrome.exe' -Kind 'App' -Protected $false -MemoryMB 2048 -Count 12 -TotalRamGB 16
Assert-That ($x.Title -eq 'Google Chrome') 'Friendly title missing.'
Assert-That ($x.Memory -match '2\.0 GB' -and $x.Memory -match '12 processes' -and $x.Memory -match 'a lot') "Memory sentence wrong: $($x.Memory)"
Assert-That ($x.Safe -match '^Yes') 'An app should be safe to close.'
$w=Get-YumProcessExplanation -Name 'csrss' -Description '' -Company '' -Path '' -Kind 'Windows' -Protected $true -MemoryMB 10 -TotalRamGB 16
Assert-That ($w.Safe -match '^No' -and $w.Yumram -match 'never touches') 'Windows processes must say No / never touched.'

# 2. Manual decisions resolve the item; Review Queue does not pin it
$rec=[pscustomobject]@{Name='x';Risk='Unknown';ResearchStatus='Unknown';ResearchComplete=$false;ResearchConfidence=0}
[void](Set-YumManualDecisionState -Record $rec -Risk 'Candidate' -Category 'User Background Apps')
Assert-That ($rec.ResearchStatus -eq 'Organized' -and $rec.Risk -eq 'Candidate' -and [bool]$rec.ResearchComplete) 'A manual decision must resolve the item.'
$rec2=[pscustomobject]@{Name='y';Risk='Unknown';ResearchStatus='Unknown'}
[void](Set-YumManualDecisionState -Record $rec2 -Risk 'Unknown' -Category 'Unknown / Quarantine')
Assert-That ($rec2.ResearchStatus -eq 'Unknown') 'Quarantine keeps the item Unknown.'

# 3. Research status from another process is never "live"
Assert-That (-not (Test-YumResearchStatusLive -Status ([pscustomobject]@{Stage='Researching Local'}))) 'A status without a process id must not be live.'
Assert-That (-not (Test-YumResearchStatusLive -Status ([pscustomobject]@{Stage='Researching Local';Pid=($PID+1)}))) 'A status from another process must not be live.'
Assert-That (Test-YumResearchStatusLive -Status ([pscustomobject]@{Stage='Researching Local';Pid=$PID})) 'A status from this process is live.'

# 4. Protected processes are identified without a readable path
$a=Get-YumPathlessProcessIdentity -Name 'audiodg'
Assert-That ($null -ne $a -and $a.Microsoft -and $a.UnderWindows) 'audiodg should be found in System32 and verified as Microsoft.'
$p=Get-YumResearchPlacement -Name 'audiodg' -Path '' -Publisher 'Unknown' -Product '' -Signature '' -Category 'Unknown' -Risk 'Unknown' -Reason 'Executable identity/path unavailable'
Assert-That ($p.Placement -eq 'Windows System Components') "audiodg should place as Windows System Components, got $($p.Placement)"
$pkg=Get-YumResearchPlacement -Name 'MicrosoftCorporationII.WinAppRuntime.Main.1.3' -Path 'MicrosoftCorporationII.WinAppRuntime.Main.1.3_3000.934.1904.0_x64__8wekyb3d8bbwe' -Publisher 'Microsoft Corporation' -Product '' -Signature '' -Category 'Review Queue' -Risk 'Review' -Reason ''
Assert-That ($pkg.Placement -eq 'Windows System Components') "A Microsoft package filed under Review Queue should still resolve, got $($pkg.Placement)"

# 5. Reclaim wiring and mode caps
$script:Yum.Config.Mode='Balanced';$script:Yum.Config.BalancedProcessesPerPass=12
Assert-That ((Get-YumModeProfile).PassLimit -eq 12) 'Balanced must honour 12 processes per pass (was silently capped at 6).'
$mr=Get-Content -Raw (Join-Path $root 'Core\MemoryReclaim.ps1')
Assert-That ($mr -match "runMemoryArea 'TrimSystemFileCache'") 'Free RAM Now must trim the system file cache.'
Assert-That ($mr -match '\$topN=24') 'Free RAM Now must consider 24 processes.'
$cl=Get-Content -Raw (Join-Path $root 'Core\Cleanup.ps1')
Assert-That ($cl -match 'Memory-area assist') 'Automatic maintenance must include the memory-area assist.'
Write-Host 'Release 5.5 behaviour test passed.'
