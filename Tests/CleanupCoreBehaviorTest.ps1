#requires -Version 5.1
# Behavioral test for one automatic cleanup pass (Invoke-YumCleanupCore). Candidates and the
# working-set trim are faked, so nothing on the machine is touched.
# Regressions covered (all present in 5.2.90):
#  - Get-YumTrimPlan used "Sort-Object ... -Ascending" (no such parameter) and threw every time.
#  - The first candidate was capped at gap+overshoot, so one large idle process could never be picked.
#  - "-f $name,$id,$r.Before/1MB,..." divided an array (comma binds tighter than /), so the log line
#    after every successful trim threw and aborted the pass.
#  - @($genericList) "Argument types do not match" inside the trim plan.
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'App\Bootstrap.ps1')
Initialize-YumConfig
$script:Yum.Config.Logging=$true
$script:Yum.Config.LogFileName=(Join-Path $env:TEMP 'yumram-cleanup-core-test.log')
Remove-Item -LiteralPath $script:Yum.Config.LogFileName -ErrorAction SilentlyContinue
$script:Yum.Config.Mode='Balanced'
$script:Yum.Config.MinimumAvailableGB=4.0
$script:Yum.Config.EnableOptionalBackgroundCleanup=$false

$fakeMemory=[pscustomobject]@{TotalBytes=[uint64]16GB;AvailableBytes=[uint64]3.7GB;UsedBytes=[uint64]12.3GB;TotalGB=16.0;UsedGB=12.3;AvailableGB=3.7;UsedPercent=76.9}
Update-YumSnapshot -Changes @{Memory=$fakeMemory;CPU=5.0;GPU3D=0.0;ForegroundProcessId=0;Game=[pscustomobject]@{ProcessId=0;ProcessName=$null;Detected=$false}} -CoreTelemetry

function New-FakeCandidate([int]$Id,[string]$Name,[int64]$WorkingSet,[double]$Score){
    [pscustomobject]@{Process=[pscustomobject]@{Id=$Id;ProcessName=$Name};PID=$Id;WorkingSet=$WorkingSet;CPU=0.2;Score=$Score;Optional=$false;Classification='Apps';Risk='Candidate';Recommendation='Candidate under memory pressure'}
}
function Get-YumCandidateProcesses { param($ForegroundPid,$GamePid,$Mode) @((New-FakeCandidate 9001 'bigidle' 700MB 80),(New-FakeCandidate 9002 'smallidle' 150MB 70)) }
$script:Trimmed=New-Object System.Collections.Generic.List[int]
function Invoke-YumEmptyWorkingSet { param($Process) $script:Trimmed.Add([int]$Process.Id); [pscustomobject]@{Success=$true;Before=300MB;After=100MB;Reduced=200MB;Win32Error=0;Reason='fake'} }
function Get-YumMemoryTelemetry { $fakeMemory }

# Plan: smallest first, and a single large candidate must still be selectable when the gap is small.
$plan=@(Get-YumTrimPlan -Candidates @(New-FakeCandidate 1 'big' 700MB 90) -AvailableGB 3.7 -TargetGB 4.0 -PassLimit 2 -MaxTrimMBPerPass 1024)
if($plan.Count -ne 1){throw "Single large candidate was not selected (got $($plan.Count))."}
$plan2=@(Get-YumTrimPlan -Candidates @((New-FakeCandidate 1 'big' 300MB 90),(New-FakeCandidate 2 'small' 120MB 10)) -AvailableGB 3.0 -TargetGB 4.0 -PassLimit 1 -MaxTrimMBPerPass 1024)
if([int]$plan2[0].PID -ne 2){throw 'Trim plan did not prefer the smallest working set first.'}

$r=Invoke-YumCleanupCore -Force
if(-not $r.Success){throw "Cleanup pass failed: $($r.Reason)"}
if([int]$r.Processes -lt 1 -or $script:Trimmed.Count -lt 1){throw 'Cleanup pass did not trim any candidate.'}
$log=Get-Content -LiteralPath $script:Yum.Config.LogFileName -Raw
if($log -notmatch 'Trimmed \S+ PID \d+: 300 MB -> 100 MB; reduced 200 MB'){throw "Trim log line was not written correctly. Log: $log"}
if($log -match 'Cleanup failed'){throw "Cleanup logged a failure: $log"}
Remove-Item -LiteralPath $script:Yum.Config.LogFileName -ErrorAction SilentlyContinue
Write-Output ('PASS: cleanup pass trimmed {0} process(es); trim plan and trim logging work.' -f $script:Trimmed.Count)
