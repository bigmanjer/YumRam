#requires -Version 5.1
# 5.15.2 (user request: "make sure we manage VRAM properly; can we trim VRAM?"). Research: Windows' video memory
# manager (VidMm) owns all graphics memory and decides residency/eviction; no supported API lets one program free
# another program's VRAM. What really helps, and what YUMRAM does:
#  1. Show which programs hold VRAM on which graphics chip (Windows' "GPU Process Memory" counters, like Task Manager).
#  2. While you play and the gaming chip's VRAM is nearly full, say which background programs hold it and what to do
#     (turn off their hardware acceleration, or move them to the power-saving chip).
#  3. On laptops with two graphics chips: move a background program to the power-saving chip with Windows' own
#     per-app setting (Settings > System > Display > Graphics; HKCU\Software\Microsoft\DirectX\UserGpuPreferences).
#     Its VRAM then stays off the gaming chip. Reversible: YUMRAM remembers the previous value and puts it back.
# The counter's first read takes ~1 s, so a background runspace reads it (every 3 s, only while someone looks).

$script:YumGpuPrefKey='HKCU:\Software\Microsoft\DirectX\UserGpuPreferences'

function Start-YumVramSampler {
    if($null -ne $script:Yum['VramSampler']){return}
    $shared=[hashtable]::Synchronized(@{Users=@();Updated=[datetime]::MinValue;WantedUntil=[datetime]::MinValue;Stop=$false;Error='';NetWantedUntil=[datetime]::MinValue;NetDown=$null;NetUp=$null;NetUpdated=[datetime]::MinValue})
    $ps=[powershell]::Create()
    [void]$ps.AddScript({
        param($S)
        $cat=$null; $names=@{}; $netCat=$null; $netPrev=$null; $lastVram=[datetime]::MinValue
        while(-not $S.Stop){
            # 5.15.5: network download / upload speed (all adapters), like IObit's floating monitor - every second, only
            # while the mini bar or Overview asks for it.
            try{
                if((Get-Date) -lt $S.NetWantedUntil){
                    if($null -eq $netCat){ $netCat=New-Object Diagnostics.PerformanceCounterCategory('Network Interface') }
                    $all=$netCat.ReadCategory(); $rx=$all['Bytes Received/sec']; $tx=$all['Bytes Sent/sec']; $now=@{}
                    foreach($k in @($rx.Keys)){ $now[[string]$k]=@($rx[$k].Sample,$tx[$k].Sample) }
                    if($null -ne $netPrev){
                        $down=0.0;$up=0.0
                        foreach($k in $now.Keys){ if($netPrev.ContainsKey($k)){ $down+=[Diagnostics.CounterSample]::Calculate($netPrev[$k][0],$now[$k][0]); $up+=[Diagnostics.CounterSample]::Calculate($netPrev[$k][1],$now[$k][1]) } }
                        $S.NetDown=$down; $S.NetUp=$up; $S.NetUpdated=Get-Date
                    }
                    $netPrev=$now
                } else { $netPrev=$null }
            }catch{}
            try{
                if((Get-Date) -lt $S.WantedUntil -and ((Get-Date)-$lastVram).TotalSeconds -ge 3){
                    $lastVram=Get-Date
                    if($null -eq $cat){ $cat=New-Object Diagnostics.PerformanceCounterCategory('GPU Process Memory') }
                    $d=$cat.ReadCategory()['dedicated usage']
                    $rows=New-Object System.Collections.Generic.List[object]
                    foreach($k in @($d.Keys)){
                        $v=[double]$d[$k].RawValue
                        if($v -lt 20MB){continue}
                        if([string]$k -notmatch '^pid_(\d+)_(luid_0x[0-9a-f]+_0x[0-9a-f]+)'){continue}
                        $procId=[int]$Matches[1]; $luid=$Matches[2].ToLowerInvariant()
                        if(-not $names.ContainsKey($procId)){ $n='';$p='';try{ $pr=[Diagnostics.Process]::GetProcessById($procId); $n=$pr.ProcessName; try{$p=$pr.MainModule.FileName}catch{} }catch{}; $names[$procId]=@($n,$p) }
                        [void]$rows.Add([pscustomobject]@{Pid=$procId;Name=[string]$names[$procId][0];Path=[string]$names[$procId][1];Luid=$luid;MB=[math]::Round($v/1MB)})
                    }
                    $S.Users=@($rows | Sort-Object MB -Descending); $S.Updated=Get-Date; $S.Error=''
                    if($names.Count -gt 400){ $names=@{} }
                }
            }catch{ $S.Error=$_.Exception.Message }
            Start-Sleep -Milliseconds 1000
        }
    }).AddArgument($shared)
    $h=$ps.BeginInvoke()
    $script:Yum['VramSampler']=@{Shared=$shared;Ps=$ps;Handle=$h}
}

function Get-YumLiveNetwork {
    # Latest download / upload speed in bytes per second (all network adapters), or $null while warming up.
    try{
        Start-YumVramSampler
        $s=$script:Yum['VramSampler'].Shared
        $s.NetWantedUntil=(Get-Date).AddSeconds(15)
        if($null -eq $s.NetDown -or ((Get-Date)-[datetime]$s.NetUpdated).TotalSeconds -gt 5){ return $null }
        return [pscustomobject]@{Down=[double]$s.NetDown;Up=[double]$s.NetUp}
    }catch{ return $null }
}

function Format-YumNetSpeed {
    param([double]$BytesPerSec)
    $bits=$BytesPerSec*8
    if($bits -ge 1e9){ return ('{0:N1} Gb/s' -f ($bits/1e9)) }
    if($bits -ge 1e6){ return ('{0:N1} Mb/s' -f ($bits/1e6)) }
    if($bits -ge 1e3){ return ('{0:N0} kb/s' -f ($bits/1e3)) }
    return ('{0:N0} b/s' -f $bits)
}

function Stop-YumVramSampler {
    try{ $v=$script:Yum['VramSampler']; if($null -ne $v){ $v.Shared.Stop=$true; try{$v.Ps.Stop()}catch{}; try{$v.Ps.Dispose()}catch{}; $script:Yum['VramSampler']=$null } }catch{}
}

function Get-YumVramUsers {
    # Latest per-program VRAM list (MB per program per graphics chip). Asking for it keeps the sampler running 30 s.
    try{
        Start-YumVramSampler
        $s=$script:Yum['VramSampler'].Shared
        $s.WantedUntil=(Get-Date).AddSeconds(30)
        $adapters=@{}; foreach($a in @(Get-YumGpuAdapters)){ $adapters[([string]$a.Luid).ToLowerInvariant()]=$a }
        $main=@(Get-YumGpuAdapters | Sort-Object DedicatedGB -Descending | Select-Object -First 1)
        $mainLuid=if($main.Count){([string]$main[0].Luid).ToLowerInvariant()}else{''}
        return @($s.Users | ForEach-Object {
            $a=$adapters[$_.Luid]
            [pscustomobject]@{Pid=$_.Pid;Name=$_.Name;Path=$_.Path;MB=$_.MB;Adapter=$(if($a){Get-YumGpuShortName ([string]$a.Name)}else{'graphics chip'});OnMainGpu=($_.Luid -eq $mainLuid)}
        })
    }catch{ return @() }
}

function Get-YumGpuUndoStore {
    # The undo list survives restarts in config.json; JSON brings it back as an object, so normalise it.
    $u=$null; try{ $u=$script:Yum.Config['GpuPreferenceUndo'] }catch{}
    $d=[ordered]@{}
    if($u -is [System.Collections.IDictionary]){ foreach($k in @($u.Keys)){ $d[[string]$k]=[string]$u[$k] } }
    elseif($null -ne $u){ foreach($pp in @($u.PSObject.Properties)){ $d[[string]$pp.Name]=[string]$pp.Value } }
    return $d
}

function Test-YumHybridGraphics { return (@(Get-YumGpuAdapters).Count -ge 2) }

function Get-YumGpuPreference {
    # Windows' per-app graphics choice for an .exe: Default / PowerSaving / HighPerformance.
    param([string]$ExePath)
    try{ $v=[string](Get-ItemProperty -LiteralPath $script:YumGpuPrefKey -Name $ExePath -ErrorAction Stop).$ExePath }catch{ return 'Default' }
    if($v -match 'GpuPreference=1'){return 'PowerSaving'}; if($v -match 'GpuPreference=2'){return 'HighPerformance'}; return 'Default'
}

function Set-YumGpuPreference {
    # PowerSaving = the built-in / power-saving graphics chip. -Undo puts back exactly what was there before YUMRAM.
    param([string]$ExePath,[switch]$Undo)
    if([string]::IsNullOrWhiteSpace($ExePath) -or -not (Test-Path -LiteralPath $ExePath -PathType Leaf)){ return [pscustomobject]@{Success=$false;Reason='The program''s file was not found.'} }
    try{
        if(-not (Test-Path -LiteralPath $script:YumGpuPrefKey)){ New-Item -Path $script:YumGpuPrefKey -Force | Out-Null }
        $undoStore=Get-YumGpuUndoStore
        $old=$null; try{ $old=[string](Get-ItemProperty -LiteralPath $script:YumGpuPrefKey -Name $ExePath -ErrorAction Stop).$ExePath }catch{}
        if($Undo){
            if(-not $undoStore.Contains($ExePath)){ return [pscustomobject]@{Success=$false;Reason='YUMRAM did not change this program.'} }
            $prev=$undoStore[$ExePath]
            if([string]::IsNullOrEmpty([string]$prev)){ Remove-ItemProperty -LiteralPath $script:YumGpuPrefKey -Name $ExePath -ErrorAction SilentlyContinue } else { Set-ItemProperty -LiteralPath $script:YumGpuPrefKey -Name $ExePath -Value ([string]$prev) }
            $undoStore.Remove($ExePath)
            $msg='Put back. The program uses its previous graphics choice the next time it starts.'
        } else {
            if(-not $undoStore.Contains($ExePath)){ $undoStore[$ExePath]=[string]$old }
            $new=if($old -match 'GpuPreference=\d;'){ $old -replace 'GpuPreference=\d;','GpuPreference=1;' }elseif($old){ 'GpuPreference=1;'+$old }else{ 'GpuPreference=1;' }
            Set-ItemProperty -LiteralPath $script:YumGpuPrefKey -Name $ExePath -Value $new
            $msg='Done. Restart the program and it will use the power-saving graphics chip, leaving the gaming chip''s memory for your games. Undo is available here.'
        }
        $script:Yum.Config['GpuPreferenceUndo']=$undoStore; [void](Save-YumConfig)
        try{ Write-YumLog ('Graphics preference {0}: {1}' -f $(if($Undo){'restored'}else{'power-saving'}),$ExePath) }catch{}
        return [pscustomobject]@{Success=$true;Reason=$msg}
    }catch{ return [pscustomobject]@{Success=$false;Reason=$_.Exception.Message} }
}

function Test-YumGpuPreferenceChangedByYumram {
    param([string]$ExePath)
    return (Get-YumGpuUndoStore).Contains($ExePath)
}

function Get-YumVramAdvice {
    # Plain advice for one program holding VRAM.
    param([string]$Name)
    $n=([string]$Name).ToLowerInvariant()
    $where=switch -Regex ($n){
        '^(chrome|msedge|brave|opera|vivaldi|firefox)$' {'Settings > System > "Use graphics acceleration when available" (Firefox: Settings > Performance)'}
        '^discord$' {'Discord: User Settings > Advanced > Hardware Acceleration'}
        '^steamwebhelper$|^steam$' {'Steam: Settings > Interface > "Enable GPU accelerated rendering in web views"'}
        '^spotify$' {'Spotify: Settings > Compatibility > "Enable hardware acceleration"'}
        '^(ms-?teams|teams)$' {'Teams: Settings > General > turn off GPU hardware acceleration'}
        '^code$' {'VS Code: run "Preferences: Configure Runtime Arguments" and set "disable-hardware-acceleration": true'}
        '^wallpaper(32|64)$|^wallpaperengine' {'Wallpaper Engine: Settings > Performance > "Other application focused/fullscreen: Pause"'}
        default {''}
    }
    return $where
}

function Invoke-YumVramWatch {
    # UI timer, every 10 s: while a game runs and the gaming chip's VRAM is >= 90 % full, say once per game which
    # background programs hold it and what to do. Reads only while a game is detected.
    try{
        if(((Get-Date)-[datetime]$script:Yum['LastVramWatch']).TotalSeconds -lt 10){return}
        $script:Yum['LastVramWatch']=Get-Date
        $s=$script:Yum.Snapshot; if($null -eq $s -or $null -eq $s.Game -or -not [bool]$s.Game.Detected){return}
        $gamePid=[int]$s.Game.ProcessId
        if([int]$script:Yum['VramWarnedPid'] -eq $gamePid){return}
        $g=Get-YumLiveReading -Kind Gpu; if($null -eq $g -or $null -eq $g.Main -or $null -eq $g.Main.VramUsedGB -or [double]$g.Main.VramTotalGB -le 0){return}
        $pct=100*[double]$g.Main.VramUsedGB/[double]$g.Main.VramTotalGB
        $users=@(Get-YumVramUsers | Where-Object { $_.OnMainGpu -and $_.Pid -ne $gamePid -and $_.Name -notin @('dwm','csrss','System','Idle','') -and $_.MB -ge 100 } | Select-Object -First 4)
        if($pct -lt 90 -or $users.Count -eq 0){return}
        $script:Yum['VramWarnedPid']=$gamePid
        $list=($users | ForEach-Object { '{0} {1:N1} GB' -f $_.Name,($_.MB/1024) }) -join ', '
        $text=('{0} graphics memory is {1:N0}% full while you play. Background programs using it: {2}. Turn off their hardware acceleration{3}, or close them.' -f (Get-YumGpuShortName ([string]$g.Main.Name)),$pct,$list,$(if(Test-YumHybridGraphics){' or move them to the power-saving chip (What''s running)'}else{''}))
        Show-YumTrayNotice -Title 'YUMRAM - graphics memory nearly full' -Text $text
        Write-YumLog ('VRAM watch: {0}' -f $text)
    }catch{}
}
