#requires -Version 5.1
# 5.10 end to end: build a real "9.9.9" release package from this tree, install it over a temporary
# YUMRAM copy through the real checker + verifier + YUMRAM.exe updater, then roll back. Also proves that
# a tampered download is refused and that user data is never touched. Uses -AsInvoker builds (no UAC).
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
function Assert-That([bool]$Condition,[string]$Message){if(-not $Condition){throw $Message}}
$work=Join-Path $env:TEMP ('yum-update-test-'+[guid]::NewGuid().ToString('N'))
$installed=Join-Path $work 'installed';$dist=Join-Path $work 'dist'
New-Item -ItemType Directory -Path $installed,$dist -Force | Out-Null
try{
    # 1. A "current" install (this tree) with user data in it.
    foreach($d in 'App','Config','Core','UI','Launcher','Tools'){Copy-Item -LiteralPath (Join-Path $root $d) -Destination (Join-Path $installed $d) -Recurse}
    Copy-Item -LiteralPath (Join-Path $root 'VERSION') -Destination $installed
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root 'Tools\Build-Launcher.ps1') -AsInvoker -Out (Join-Path $installed 'YUMRAM.exe') | Out-Null
    $userConfig='{"MinimumAvailableGB": 9.0, "Marker": "keep-me"}'
    [IO.File]::WriteAllText((Join-Path $installed 'config.json'),$userConfig)
    [IO.File]::WriteAllText((Join-Path $installed 'stats.json'),'{"TotalGB": 42.0}')
    $currentVersion=([IO.File]::ReadAllText((Join-Path $installed 'VERSION'))).Trim()

    # 2. The release package for 9.9.9 + a GitHub-shaped "latest release" document.
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root 'Tools\Build-Release.ps1') -Version '9.9.9' -OutDir $dist -AsInvoker | Out-Null
    $zip=Join-Path $dist 'YUMRAM-9.9.9.zip'
    Assert-That (Test-Path $zip) 'Release zip was not built.'
    $sums=[IO.File]::ReadAllText((Join-Path $dist 'SHA256SUMS.txt'))
    Assert-That ($sums -match '^[0-9a-f]{64}  YUMRAM-9\.9\.9\.zip') "SHA256SUMS format wrong: $sums"
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $entries=@([IO.Compression.ZipFile]::OpenRead($zip).Entries | ForEach-Object { $_.FullName })
    Assert-That ($entries -contains 'YUMRAM.exe' -and $entries -contains 'App\YUMRAM.ps1' -or $entries -contains 'App/YUMRAM.ps1') 'The package must contain YUMRAM.exe and App\YUMRAM.ps1.'
    Assert-That (-not ($entries | Where-Object { $_ -match '(^|[\\/])(config|stats|intelligence-db)\.json$' })) 'The package must never contain user data.'
    $feed=Join-Path $dist 'latest.json'
    $zipUri=([uri]$zip).AbsoluteUri;$sumsUri=([uri](Join-Path $dist 'SHA256SUMS.txt')).AbsoluteUri
    [IO.File]::WriteAllText($feed,(@{tag_name='v9.9.9';body='Test notes';html_url='https://github.com/bigmanjer/YumRam/releases/tag/v9.9.9';assets=@(@{name='YUMRAM-9.9.9.zip';browser_download_url=$zipUri},@{name='SHA256SUMS.txt';browser_download_url=$sumsUri})} | ConvertTo-Json -Depth 4))

    # 3. Check + tampered install + real install, inside the installed copy (as YUMRAM would).
    $driver=Join-Path $work 'driver.ps1'
    @'
param([string]$Installed,[string]$Feed,[string]$Mode)
. (Join-Path $Installed 'App\Bootstrap.ps1'); Initialize-YumConfig
$script:Yum.Config.Logging=$true
$script:Yum.Config['UpdateFeedUrl']=([uri]$Feed).AbsoluteUri
$i=Get-YumUpdateInfo
"STATUS=$($i.Status);LATEST=$($i.Latest);SHA=$($i.Sha256)"
if($Mode -eq 'tamper'){ $i.Sha256=('0'*64); $r=Install-YumUpdate -Info $i -NoRestart; "TAMPER=$($r.Success);$($r.Message)"; exit }
if($Mode -eq 'auto'){
    # 5.15.3 automatic update path: on by default, every 6 h, never while a game runs, background download + verify.
    "AUTOON=$(Test-YumAutoUpdateEnabled)"
    $script:Yum.Config['UpdateLastCheck']=(Get-Date).AddMinutes(-16).ToString('o'); "DUE7=$(Test-YumUpdateCheckDue)"
    $script:Yum.Config['UpdateLastCheck']=(Get-Date).AddMinutes(-10).ToString('o'); "DUE5=$(Test-YumUpdateCheckDue)"
    "BLOCKIDLE=[$(Get-YumUpdateBlocker)]"
    $script:Yum.Snapshot=[pscustomobject]@{Game=[pscustomobject]@{Detected=$true;ProcessName='testgame';ProcessId=1}}; "BLOCKGAME=[$(Get-YumUpdateBlocker)]"; $script:Yum.Snapshot=$null
    $script:Yum.Config['UpdateAutoInstall']=$false; "AUTOOFF=$(Test-YumAutoUpdateEnabled)"; $script:Yum.Config['UpdateAutoInstall']=$true
    $sw=[Diagnostics.Stopwatch]::StartNew(); Start-YumUpdateDownload -Info $i; "STARTMS=$($sw.ElapsedMilliseconds)"
    $d=$null; $t=(Get-Date).AddSeconds(90); while($null -eq $d -and (Get-Date) -lt $t){ Start-Sleep -Milliseconds 300; $d=Receive-YumUpdateDownload }
    "STAGED=$($d.Success)"
    Invoke-YumApplyStagedUpdate -Staging ([string]$d.Staging) -NoRestart
    "INSTALL=True"; exit
}
$r=Install-YumUpdate -Info $i -NoRestart
"INSTALL=$($r.Success);$($r.Message)"
'@ | Set-Content -LiteralPath $driver -Encoding UTF8
    $out=& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $driver -Installed $installed -Feed $feed -Mode tamper
    Assert-That (($out -join "`n") -match 'STATUS=Available;LATEST=9\.9\.9;SHA=[0-9A-F]{64}') "Checker did not find the update via SHA256SUMS: $out"
    Assert-That (($out -join "`n") -match 'TAMPER=False;The download does not match') "A tampered download must be refused: $out"
    Assert-That ((([IO.File]::ReadAllText((Join-Path $installed 'VERSION'))).Trim()) -eq $currentVersion) 'Nothing may change after a refused download.'
    # YUMRAM's own start-up merges new defaults into config.json; the updater must not change it after that.
    $userConfig=[IO.File]::ReadAllText((Join-Path $installed 'config.json'))
    $cfgObj=$userConfig | ConvertFrom-Json
    Assert-That ([double]$cfgObj.MinimumAvailableGB -eq 9.0) 'The user goal must survive YUMRAM start-up.'

    $out=& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $driver -Installed $installed -Feed $feed -Mode auto
    $o=($out -join "`n")
    Assert-That ($o -match 'AUTOON=True') "Automatic install must be on by default: $o"
    Assert-That ($o -match 'DUE7=True' -and $o -match 'DUE5=False') "Checks must be due every 15 minutes: $o"
    Assert-That ($o -match 'BLOCKIDLE=\[\]') "Nothing should block an update on an idle PC: $o"
    Assert-That ($o -match 'BLOCKGAME=\[a game is running') "An update must never install while a game runs: $o"
    Assert-That ($o -match 'AUTOOFF=False') "The Settings switch must turn automatic install off: $o"
    Assert-That ($o -match 'STARTMS=(\d+)' -and [int]$Matches[1] -lt 2000) "The download must run in the background: $o"
    Assert-That ($o -match 'STAGED=True') "Background download + SHA-256 check failed: $o"
    Assert-That ($o -match 'INSTALL=True') "Install did not start: $out"
    $deadline=(Get-Date).AddSeconds(60)
    while((Get-Date) -lt $deadline -and (([IO.File]::ReadAllText((Join-Path $installed 'VERSION'))).Trim()) -ne '9.9.9'){Start-Sleep -Milliseconds 500}
    Start-Sleep -Seconds 2
    Assert-That ((([IO.File]::ReadAllText((Join-Path $installed 'VERSION'))).Trim()) -eq '9.9.9') 'The update was not applied.'
    Assert-That ([IO.File]::ReadAllText((Join-Path $installed 'config.json')) -eq $userConfig) 'config.json must survive an update unchanged.'
    Assert-That ([IO.File]::ReadAllText((Join-Path $installed 'stats.json')) -eq '{"TotalGB": 42.0}') 'stats.json must survive an update unchanged.'
    Assert-That ((([IO.File]::ReadAllText((Join-Path $installed '.previous\VERSION'))).Trim()) -eq $currentVersion) 'The previous version must be kept in .previous.'
    Assert-That ((Get-Content (Join-Path $installed 'YUMRAM.log') -Raw) -match 'Updater: update applied') 'The updater must log what it did.'

    # 4. Rollback.
    $p=Start-Process -FilePath (Join-Path $installed 'YUMRAM.exe') -ArgumentList '--rollback','--no-restart' -PassThru -Wait
    Assert-That ((([IO.File]::ReadAllText((Join-Path $installed 'VERSION'))).Trim()) -eq $currentVersion) 'Rollback must restore the previous version.'
    Assert-That ([IO.File]::ReadAllText((Join-Path $installed 'config.json')) -eq $userConfig) 'Rollback must not touch config.json.'
    Write-Host ('Release 5.10 update test passed ({0} -> 9.9.9 -> {0}; tampered download refused; user data kept).' -f $currentVersion)
}finally{
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}
