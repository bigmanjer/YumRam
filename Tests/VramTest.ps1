#requires -Version 5.1
# 5.15.2 VRAM: per-program graphics memory is read in the background (never on the UI thread), the power-saving chip
# setting is Windows' own per-app value and is undone exactly. The setting is only tried on a dummy file made here.
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'App\Bootstrap.ps1')
Initialize-YumConfig
$script:Yum.Config.Logging=$false
function Assert-That([bool]$Condition,[string]$Message){if(-not $Condition){throw $Message}}
$tmp=Join-Path $env:TEMP ('yum-vram-'+[guid]::NewGuid().ToString('N')); New-Item -ItemType Directory $tmp | Out-Null
$script:Yum.ConfigDirectory=$tmp; $script:Yum.ConfigFile=(Join-Path $tmp 'config.json')
try{
    # 1. Background reading: the call returns at once; data arrives within a few seconds.
    [void](Get-YumGpuAdapters)   # loaded at start-up in the app (Overview GPU tile)
    $sw=[Diagnostics.Stopwatch]::StartNew(); $first=@(Get-YumVramUsers); $callMs=$sw.ElapsedMilliseconds
    Assert-That ($callMs -lt 300) ('Get-YumVramUsers must not block the UI ({0} ms).' -f $callMs)
    $users=@(); for($i=0;$i -lt 20 -and $users.Count -eq 0;$i++){ Start-Sleep -Milliseconds 500; $users=@(Get-YumVramUsers) }
    Assert-That ($users.Count -ge 1) 'No program reported graphics memory (Windows itself always uses some).'
    Assert-That (@($users | Where-Object { $_.MB -lt 20 -or -not $_.Adapter }).Count -eq 0) 'Rows need a size of at least 20 MB and a graphics chip name.'
    Write-Host ('VRAM users: ' + (($users | Select-Object -First 4 | ForEach-Object { '{0} {1} MB on {2}' -f $_.Name,$_.MB,$_.Adapter }) -join '; '))

    # 2. Power-saving chip setting on a dummy program only, then undone exactly.
    $exe=Join-Path $tmp 'yum-dummy-app.exe'; [IO.File]::WriteAllBytes($exe,[byte[]](0x4D,0x5A))
    Assert-That ((Get-YumGpuPreference -ExePath $exe) -eq 'Default') 'A new program starts with the Windows default.'
    $r=Set-YumGpuPreference -ExePath $exe
    Assert-That ($r.Success -and (Get-YumGpuPreference -ExePath $exe) -eq 'PowerSaving') ('Power-saving chip not set: {0}' -f $r.Reason)
    Assert-That (Test-YumGpuPreferenceChangedByYumram -ExePath $exe) 'YUMRAM must remember what it changed.'
    $saved=Get-Content -Raw $script:Yum.ConfigFile | ConvertFrom-Json
    $script:Yum.Config['GpuPreferenceUndo']=$saved.GpuPreferenceUndo   # as after a restart (JSON object, not a hashtable)
    Assert-That (Test-YumGpuPreferenceChangedByYumram -ExePath $exe) 'The undo list must survive a restart.'
    $u=Set-YumGpuPreference -ExePath $exe -Undo
    Assert-That ($u.Success -and (Get-YumGpuPreference -ExePath $exe) -eq 'Default') 'Undo must remove the value YUMRAM added.'
    $none=$null; try{ $none=(Get-ItemProperty -LiteralPath 'HKCU:\Software\Microsoft\DirectX\UserGpuPreferences' -Name $exe -ErrorAction Stop).$exe }catch{}
    Assert-That ($null -eq $none) 'No leftover registry value after undo.'
    Assert-That (-not (Set-YumGpuPreference -ExePath (Join-Path $tmp 'missing.exe')).Success) 'A missing program file is refused.'

    # 5.15.5: network speed in the background (mini bar), never on the UI thread.
    $sw=[Diagnostics.Stopwatch]::StartNew(); [void](Get-YumLiveNetwork); Assert-That ($sw.ElapsedMilliseconds -lt 300) 'Network speed must not block the UI.'
    $net=$null; for($i=0;$i -lt 20 -and $null -eq $net;$i++){ Start-Sleep -Milliseconds 500; $net=Get-YumLiveNetwork }
    Assert-That ($null -ne $net -and $net.Down -ge 0 -and $net.Up -ge 0) 'Network download / upload speed is read.'
    Assert-That ((Format-YumNetSpeed 1250000) -eq '10.0 Mb/s' -and (Format-YumNetSpeed 0) -eq '0 b/s') 'Network speed shown in bits per second like speed tests.'
    Write-Host ('Network now: down {0}, up {1}' -f (Format-YumNetSpeed $net.Down),(Format-YumNetSpeed $net.Up))

    # 3. Advice and wiring.
    Assert-That ((Get-YumVramAdvice -Name 'discord') -match 'Hardware Acceleration') 'Discord advice says where the switch is.'
    Assert-That ((Get-YumVramAdvice -Name 'chrome') -match 'graphics acceleration') 'Browser advice says where the switch is.'
    $x=[IO.File]::ReadAllText((Join-Path $root 'UI\Xaml\TopProcesses.xaml')); Assert-That ($x -match 'x:Name="ExplainVram"' -and $x -match 'x:Name="GpuSaver"') "What's running shows VRAM and the power-saving chip button."
    $mw=[IO.File]::ReadAllText((Join-Path $root 'UI\MainWindow.ps1')); Assert-That ($mw -match 'Invoke-YumVramWatch' -and $mw -match 'Stop-YumVramSampler') 'VRAM watch runs and the reader stops on exit.'
    Write-Host 'VramTest passed.'
}finally{
    try{ Remove-ItemProperty -LiteralPath 'HKCU:\Software\Microsoft\DirectX\UserGpuPreferences' -Name (Join-Path $tmp 'yum-dummy-app.exe') -ErrorAction SilentlyContinue }catch{}
    Stop-YumVramSampler
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
}
