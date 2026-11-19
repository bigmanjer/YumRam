#requires -Version 5.1
# Behavioral test for the RAM reclaim engine (no real system changes: the native memory-list
# command and the per-process working-set trim are replaced with fakes after loading).
# Regression: 5.2.90 passed "-TopN (if(...){16}else{10})", which PowerShell executes as a command
# named 'if', so FREE RAM NOW / DEEP RAM RECLAIM always threw before trimming anything.
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'App\Bootstrap.ps1')
Initialize-YumConfig
$script:Yum.Config.Logging=$false
$script:Yum.Config.ReclaimLearningEnabled=$false
$script:Yum.Config.ReclaimSettleMilliseconds=0

$script:FakeCalls=New-Object System.Collections.Generic.List[string]
function Invoke-YumNativeMemoryCommand { param([string]$Command) $script:FakeCalls.Add("native:$Command"); [pscustomobject]@{Success=$true;Command=$Command;Status=0;Reason='fake';ErrorCategory=''} }
function Invoke-YumEmptyWorkingSet { param($Process) $script:FakeCalls.Add("trim:$($Process.Id)"); [pscustomobject]@{Success=$true;Before=200MB;After=50MB;Reduced=150MB;Win32Error=0;Reason='fake'} }

foreach($mode in 'Quick','Deep'){
    $script:FakeCalls.Clear()
    $r=Invoke-YumMemoryReclaim -Mode $mode -Force
    if($null -eq $r){throw "$mode reclaim returned nothing."}
    if($r.PSObject.Properties['Reason'] -and [string]$r.Reason -match "term 'if'"){throw "$mode reclaim still hits the (if ...) command bug."}
    if(-not $r.PSObject.Properties['Summary']){throw "$mode reclaim failed: $($r.Reason)"}
    if($r.Skipped){throw "$mode reclaim was unexpectedly skipped: $($r.Reason)"}
    if($null -eq $r.PSObject.Properties['VerificationStartedUtc']){throw "$mode reclaim did not arm verification."}
    if($script:Yum.ReclaimRunning){throw 'ReclaimRunning flag left set.'}
}

# Verification is sampled lazily (the 5.2.90 System.Timers.Timer verifier never ran).
$last=$script:Yum.LastReclaim
$last.VerificationStartedUtc=[datetime]::UtcNow.AddSeconds(-31)
if(-not (Update-YumReclaimVerification)){throw 'Verification did not sample after 30 seconds.'}
if([string]$last.VerificationStatus -ne 'Complete'){throw "Verification status is '$($last.VerificationStatus)', expected Complete."}
if($null -eq $last.RetainedGainGB){throw 'Retained gain was not recorded.'}
if(Update-YumReclaimVerification){throw 'Completed verification sampled again.'}

# Reclaim Center view must expose verification fields (5.2.90 used reflection on a PSCustomObject and always showed Pending).
$view=Get-YumLastReclaimView
if([string]$view.VerificationStatus -ne 'Complete'){throw 'Reclaim view does not surface verification status.'}

# 5.3.1 regression: Get-YumSafePropertyValue had a Mandatory $Object, so a process with no learning
# history threw, every candidate was skipped, and Free RAM / Deep Reclaim never trimmed anything.
if((Get-YumSafePropertyValue -Object $null -Name 'Samples' -Default 7) -ne 7){throw 'Get-YumSafePropertyValue does not accept $null.'}
$script:Yum.ReclaimLearningLoaded=$true;$script:Yum.ReclaimLearning=@{}
$noHistory=Get-YumReclaimLearningForProcess -Process (Get-Process -Id $PID)
if([int]$noHistory.Samples -ne 0 -or [double]$noHistory.HistoricalBonus -ne 0){throw 'Learning lookup for a process with no history is wrong.'}
$realCandidates=@(Get-YumFastReclaimCandidates -TopN 40 -MinimumWorkingSetMB 1)
if($realCandidates.Count -eq 0){
    # CI runners have no idle desktop apps, so an empty list is legitimate there.
    if($env:GITHUB_ACTIONS -eq 'true' -or $env:CI -eq 'true'){Write-Warning 'No reclaim candidates on this CI runner; real-candidate check skipped.'}
    else{throw 'Free RAM NOW found no candidates at all on this machine (candidate loop is swallowing errors).'}
}
if(@($realCandidates | Where-Object { $_.ProcessName -in @('MsMpEng','explorer','csrss','lsass','dwm') }).Count -gt 0){throw 'Free RAM NOW selected a protected/core process.'}

# NTSTATUS failures are negative; formatting them must not throw.
$hex='0x{0:X8}' -f [BitConverter]::ToUInt32([BitConverter]::GetBytes([int32]-1073741727),0)
if($hex -ne '0xC0000061'){throw "NTSTATUS formatting wrong: $hex"}
Write-Output 'PASS: Quick/Deep reclaim complete, verification samples, NTSTATUS formatting is safe.'
