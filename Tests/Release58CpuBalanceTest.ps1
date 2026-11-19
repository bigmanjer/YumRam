#requires -Version 5.1
# 5.8 CPU balance (ProBalance-style): eligibility rules and safe restore.
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'App\Bootstrap.ps1')
Initialize-YumConfig
$script:Yum.Config.Logging=$false
function Assert-That([bool]$Condition,[string]$Message){if(-not $Condition){throw $Message}}
$cfg=Get-YumCpuBalanceSettings
Assert-That ($cfg.Enabled -and $cfg.SystemPercent -eq 70 -and $cfg.ProcessPercent -eq 10) 'Defaults: on, 70% PC, 10% per program.'
function P($Name,$Id=5000,$Session=1,$Prio='Normal'){[pscustomobject]@{Name=$Name;Id=$Id;SessionId=$Session;Priority=$Prio;Path=''}}
Assert-That ((Test-YumCpuBalanceEligible -P (P 'handbrake') -ForegroundPid 1 -ForegroundName 'chrome' -GamePid 0 -Settings $cfg) -eq '') 'A background hog is eligible.'
Assert-That ((Test-YumCpuBalanceEligible -P (P 'handbrake' 1) -ForegroundPid 1 -ForegroundName 'x' -GamePid 0 -Settings $cfg) -ne '') 'The foreground program is never touched.'
Assert-That ((Test-YumCpuBalanceEligible -P (P 'chrome') -ForegroundPid 1 -ForegroundName 'chrome' -GamePid 0 -Settings $cfg) -ne '') 'Other processes of the foreground app are never touched.'
Assert-That ((Test-YumCpuBalanceEligible -P (P 'game' 77) -ForegroundPid 1 -ForegroundName 'x' -GamePid 77 -Settings $cfg) -ne '') 'The game is never touched.'
Assert-That ((Test-YumCpuBalanceEligible -P (P 'svc' 5000 0) -ForegroundPid 1 -ForegroundName 'x' -GamePid 0 -Settings $cfg) -eq 'service') 'Services are never touched.'
Assert-That ((Test-YumCpuBalanceEligible -P (P 'x' 5000 1 'High') -ForegroundPid 1 -ForegroundName 'y' -GamePid 0 -Settings $cfg) -eq 'own priority') 'Programs with their own priority are left alone.'
Assert-That ((Test-YumCpuBalanceEligible -P (P 'dwm') -ForegroundPid 1 -ForegroundName 'y' -GamePid 0 -Settings $cfg) -ne '') 'Windows core processes are never touched.'
Assert-That ((Test-YumCpuBalanceEligible -P (P 'MsMpEng') -ForegroundPid 1 -ForegroundName 'y' -GamePid 0 -Settings $cfg) -ne '') 'Security software is never touched.'
Assert-That ((Test-YumCpuBalanceEligible -P (P 'x' $PID) -ForegroundPid 1 -ForegroundName 'y' -GamePid 0 -Settings $cfg) -ne '') 'YUMRAM never touches itself.'
Assert-That ((Test-YumCpuBalanceEligible -P (P 'powershell') -ForegroundPid 1 -ForegroundName 'chrome' -GamePid 0 -Settings $cfg) -eq '') 'A PowerShell script hog is eligible (YUMRAM is excluded by PID).'
$script:Yum.Config['CpuBalanceExclusions']=@('HandBrake.exe');$cfg2=Get-YumCpuBalanceSettings
Assert-That ((Test-YumCpuBalanceEligible -P (P 'handbrake') -ForegroundPid 1 -ForegroundName 'chrome' -GamePid 0 -Settings $cfg2) -eq 'excluded') 'User exclusions work (case and .exe insensitive).'

# Restore only undoes our own change on the same process instance.
$tmp=Join-Path $env:TEMP ('yum-cpub-'+[guid]::NewGuid().ToString('N'));New-Item -ItemType Directory $tmp|Out-Null;$script:Yum.ConfigDirectory=$tmp
$p=Start-Process ping.exe -ArgumentList '-n','30','127.0.0.1' -WindowStyle Hidden -PassThru
try{
    Start-Sleep -Milliseconds 300
    $p.PriorityClass='BelowNormal'
    $st=Get-YumCpuBalanceState
    $st.Restrained[$p.Id]=@{Id=$p.Id;Name='PING';Since=Get-Date;StartTicks=($p.StartTime.Ticks+1);LastPercent=0;CalmTicks=0}
    Restore-YumCpuBalanceProcess -Record $st.Restrained[$p.Id] -Why 'test'
    $p.Refresh();Assert-That ($p.PriorityClass -eq 'BelowNormal' -and -not $st.Restrained.ContainsKey($p.Id)) 'A different process instance (PID reuse) must not be changed.'
    $st.Restrained[$p.Id]=@{Id=$p.Id;Name='PING';Since=Get-Date;StartTicks=$p.StartTime.Ticks;LastPercent=0;CalmTicks=0}
    Save-YumCpuBalanceRestrained
    Restore-YumCpuBalanceInterrupted
    $p.Refresh();Assert-That ($p.PriorityClass -eq 'Normal') 'Crash recovery must put a held-back program back to Normal.'
    $p.PriorityClass='High'
    $st.Restrained[$p.Id]=@{Id=$p.Id;Name='PING';Since=Get-Date;StartTicks=$p.StartTime.Ticks;LastPercent=0;CalmTicks=0}
    Restore-YumCpuBalanceAll -Why 'test'
    $p.Refresh();Assert-That ($p.PriorityClass -eq 'High') 'A priority someone else changed afterwards must be left alone.'
}finally{try{$p.Kill()}catch{};Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue}
$mw=Get-Content -Raw (Join-Path $root 'UI\MainWindow.ps1')
Assert-That ($mw -match 'Start-YumCpuBalanceWorker' -and $mw -match 'Stop-YumCpuBalanceWorker') 'The worker must start with YUMRAM and stop (restoring everything) when it closes.'
Write-Host 'Release 5.8 CPU balance test passed.'
