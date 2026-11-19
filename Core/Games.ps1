function Test-YumNameInList {
    param([string]$Name,[string[]]$List)
    if ([string]::IsNullOrWhiteSpace($Name)) { return $false }
    $clean = $Name -replace '\.exe$',''
    foreach ($item in @($List)) { if ($clean -ieq [string]$item) { return $true } }
    return $false
}

function Find-YumGameProcess {
    if (-not [bool]$script:Yum.Config.AutoDetectGames) { return $null }
    try {
        foreach ($p in Get-Process -ErrorAction Stop) {
            try {
                if ($p.Id -eq $PID) { continue }
                if (Test-YumNameInList $p.ProcessName @($script:Yum.Config.KnownGames)) { return $p }
                $path='';try{$path=$p.MainModule.FileName}catch{}
                $lp=[string]$path.ToLowerInvariant()
                # Conservative heuristic: only treat executables inside common game install roots as games.
                # Launchers/helpers are excluded so YUMRAM does not mistake them for the active game.
                $launcher=($p.ProcessName -match 'Steam|EpicGamesLauncher|EpicWebHelper|RiotClient|Battle\.net|UbisoftConnect|EADesktop|GOGGalaxy|XboxPcApp')
                if(-not $launcher -and ($lp -match '\\steamapps\\common\\|\\epic games\\|\\riot games\\|\\games\\')) {
                    return $p
                }
            } catch { }
        }
    } catch { }
    return $null
}

function Get-YumGameSnapshot {
    $game = Find-YumGameProcess
    if ($null -eq $game) {
        return [pscustomobject]@{ ProcessId=0; ProcessName=$null; Detected=$false }
    }
    return [pscustomobject]@{ ProcessId=[int]$game.Id; ProcessName=$game.ProcessName; Detected=$true }
}

function Set-YumGamePriority {
    param([System.Diagnostics.Process]$Process)
    if ($null -eq $Process) { return $false }
    $preference = [string]$script:Yum.Config.GamePriority
    if ($preference -eq 'KeepExisting') { return $true }
    try {
        $priority = switch ($preference) {
            'Normal' { [Diagnostics.ProcessPriorityClass]::Normal }
            'AboveNormal' { [Diagnostics.ProcessPriorityClass]::AboveNormal }
            'High' { [Diagnostics.ProcessPriorityClass]::High }
            default { [Diagnostics.ProcessPriorityClass]::AboveNormal }
        }
        $Process.PriorityClass = $priority
        Write-YumLog ("Game priority set: {0} -> {1}" -f $Process.ProcessName,$preference)
        return $true
    } catch {
        Write-YumLogException 'Game priority failed' $_.Exception
        return $false
    }
}

function Update-YumGameState {
    param([Parameter(Mandatory)]$Snapshot)
    try {
        if($Snapshot.Game.Detected){
            if(-not $script:Yum.GameWasRunning -or $script:Yum.LastGamePid -ne [int]$Snapshot.Game.ProcessId){
                $script:Yum.GameWasRunning=$true
                $script:Yum.LastGamePid=[int]$Snapshot.Game.ProcessId
                Write-YumLog ("Game detected: {0} PID {1}" -f $Snapshot.Game.ProcessName,$Snapshot.Game.ProcessId)
                try{$gp=Get-Process -Id ([int]$Snapshot.Game.ProcessId) -ErrorAction Stop;[void](Set-YumGamePriority -Process $gp)}catch{}
                if([bool]$script:Yum.Config.AutoCleanOnGameStart){[void](Request-YumCleanup -Force)}
            }
        } else {
            if($script:Yum.GameWasRunning){Write-YumLog 'Game closed.'}
            $script:Yum.GameWasRunning=$false;$script:Yum.LastGamePid=0
        }
    } catch {Write-YumLogException -Context 'Game state update failed' -Exception $_.Exception}
}
