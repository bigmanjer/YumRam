#requires -Version 5.1
# 5.15 audit fixes: F1 no automatic modified-list flush (assist every 10 min), F2 automatic care closes
# programs only when the user opts in, F3 stale-PID guard before trimming.
$ErrorActionPreference='Stop'
$repoRoot=Split-Path -Parent $PSScriptRoot
function Assert-That([bool]$Condition,[string]$Message){if(-not $Condition){throw $Message}}
$tmp=Join-Path $env:TEMP ('yum-515-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path (Join-Path $tmp 'Config') -Force | Out-Null
try{
    # --- config migration with a 5.14 user config (45 s assist, no AutoCloseOptionalApps key) ---
    Copy-Item (Join-Path $repoRoot 'Config\default-config.json') (Join-Path $tmp 'Config\default-config.json')
    Copy-Item (Join-Path $repoRoot 'VERSION') (Join-Path $tmp 'VERSION')
    $user=Get-Content (Join-Path $repoRoot 'Config\default-config.json') -Raw | ConvertFrom-Json
    $user.AutoMemoryAreaAssistSeconds=45
    $user.PSObject.Properties.Remove('AutoCloseOptionalApps')
    $user.Logging=$false
    $user | ConvertTo-Json -Depth 8 | Set-Content (Join-Path $tmp 'config.json') -Encoding UTF8
    . (Join-Path $repoRoot 'App\Bootstrap.ps1')
    $script:Root=$tmp
    Initialize-YumConfig
    $c=$script:Yum.Config
    Assert-That ([double]$c.AutoMemoryAreaAssistSeconds -eq 600) ('Old default 45 s should migrate to 600 s, got {0}.' -f $c.AutoMemoryAreaAssistSeconds)
    Assert-That ($c.Contains('AutoCloseOptionalApps') -and -not [bool]$c.AutoCloseOptionalApps) 'Existing users get AutoCloseOptionalApps = false.'

    # A value the user chose themselves is kept.
    $user.AutoMemoryAreaAssistSeconds=300
    $user | ConvertTo-Json -Depth 8 | Set-Content (Join-Path $tmp 'config.json') -Encoding UTF8
    Initialize-YumConfig
    Assert-That ([double]$script:Yum.Config.AutoMemoryAreaAssistSeconds -eq 300) 'A custom assist interval must survive migration.'
    $script:Yum.Config.Logging=$false

    # --- F1: automatic assist does not flush the modified list; Deep reclaim still can ---
    $cleanup=[IO.File]::ReadAllText((Join-Path $repoRoot 'Core\Cleanup.ps1'))
    $assist=$cleanup.Substring($cleanup.IndexOf('memory-area assist:'))
    $assist=$assist.Substring(0,$assist.IndexOf('Phase 2: legacy/strong fallback'))
    Assert-That ($assist -notmatch 'FlushModifiedList') 'Automatic memory-area assist must not flush the modified page list.'
    Assert-That ($assist -match '\$assistEvery=600\.0' -and $assist -match 'Max\(120\.0') 'Assist interval default 600 s, minimum 120 s.'
    Assert-That ([IO.File]::ReadAllText((Join-Path $repoRoot 'Core\MemoryReclaim.ps1')) -match 'FlushModifiedList') 'Deep reclaim keeps the modified-list flush.'

    # --- F2: closing listed programs is opt-in ---
    Assert-That ($cleanup -match '\$autoClose=\$false;try\{\$autoClose=\[bool\]\$script:Yum\.Config\[''AutoCloseOptionalApps''\]\}' -and $cleanup -match 'if\(\$allowOptional -and \$autoClose') 'Automatic care closes apps only with AutoCloseOptionalApps.'
    $def=Get-Content (Join-Path $repoRoot 'Config\default-config.json') -Raw | ConvertFrom-Json
    Assert-That (-not [bool]$def.AutoCloseOptionalApps) 'Default is off.'
    Assert-That ([IO.File]::ReadAllText((Join-Path $repoRoot 'UI\Xaml\BloatManager.xaml')) -match 'x:Name="Enable"[^>]*IsChecked="False"') 'The on-screen switch starts off.'

    # --- F3: stale-PID guard with a real process ---
    $p=Start-Process -FilePath (Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe') -ArgumentList '-NoProfile','-Command','Start-Sleep 30' -PassThru -WindowStyle Hidden
    try{
        Start-Sleep -Milliseconds 800
        $ticks=Get-YumProcessStartTicks (Get-Process -Id $p.Id)
        Assert-That ($ticks -gt 0) 'Start time is readable for our own child process.'
        Assert-That (Test-YumSameProcess -ProcessId $p.Id -StartTicks $ticks) 'Same process is recognised.'
        Assert-That (-not (Test-YumSameProcess -ProcessId $p.Id -StartTicks ($ticks+10000000))) 'A different start time (PID reused) is rejected.'
    }finally{ try{$p.Kill()}catch{} }
    Start-Sleep -Milliseconds 500
    Assert-That (-not (Test-YumSameProcess -ProcessId $p.Id -StartTicks $ticks)) 'An exited process is rejected.'
    Assert-That ($cleanup -match 'Test-YumSameProcess -ProcessId \(\[int\]\$item\.Process\.Id\) -StartTicks \$tk') 'The trim loop checks the process before acting.'
    $safety=[IO.File]::ReadAllText((Join-Path $repoRoot 'Core\Safety.ps1'))
    Assert-That (([regex]::Matches($safety,'StartTicks=\(Get-YumProcessStartTicks \$p\)')).Count -ge 2) 'Both candidate paths record the start time.'
    Assert-That ($safety -match 'PID reused by another process') 'The cached candidate path rejects reused PIDs.'
    # --- busy-state gap: request taken by the worker but reclaim not yet flagged running ---
    $script:Yum.ReclaimRequest=$null;$script:Yum.ReclaimRunning=$false;$script:Yum.ReclaimTaken=$true
    Assert-That (Test-YumReclaimBusy) 'A taken request counts as busy (Free RAM button stays disabled).'
    Assert-That (-not (Request-YumMemoryReclaim -Mode Quick)) 'A second Free RAM click is refused while the first is being taken.'
    $script:Yum.ReclaimTaken=$false;$script:Yum.ReclaimRequest=$null
    $ctl=[IO.File]::ReadAllText((Join-Path $repoRoot 'Core\Controller.ps1'))
    Assert-That ($ctl -match '\$script:Yum\.ReclaimRequest=\$null;if\(\$null -ne \$reclaimMode\)\{\$script:Yum\.ReclaimTaken=\$true\}' -and $ctl -match 'finally\{ \$script:Yum\.ReclaimTaken=\$false') 'Worker sets and clears the taken flag around the reclaim.'
}finally{ try{ if($null -ne $script:Yum.ControllerStop){$script:Yum.ControllerStop.Set()} }catch{}; Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue }
Write-Host 'Release515Test passed.'
