#requires -Version 5.1
# Regression (present since 5.2.x): Merge-YumHashtable took [hashtable] parameters. The config is an
# [ordered] dictionary, so PowerShell passed a converted copy and every saved user setting was lost:
# the app started on defaults at every launch (e.g. a 10 GB target came back as 4 GB).
$ErrorActionPreference='Stop'
$repoRoot=Split-Path -Parent $PSScriptRoot  # not $root: Bootstrap sets $script:Root, the same variable
$tmp=Join-Path $env:TEMP ('yumram-config-test-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path (Join-Path $tmp 'Config') -Force | Out-Null
try {
    Copy-Item (Join-Path $repoRoot 'Config\default-config.json') (Join-Path $tmp 'Config\default-config.json')
    Copy-Item (Join-Path $repoRoot 'VERSION') (Join-Path $tmp 'VERSION')
    $user=Get-Content (Join-Path $repoRoot 'Config\default-config.json') -Raw | ConvertFrom-Json
    $user.MinimumAvailableGB=7.5
    $user.Mode='Safe'
    $user.Logging=$false
    $user.SafeProcessesPerPass=4      # custom (not the old default 2) -> must survive migration
    $user.BalancedProcessesPerPass=3  # old default -> must be migrated to 5
    $user.StartMonitoringAutomatically=$true   # 5.2.x forced this off on every launch
    $user.EnableOnlineResearch=$false          # privacy switch in Settings must stick
    $user | ConvertTo-Json -Depth 8 | Set-Content (Join-Path $tmp 'config.json') -Encoding UTF8

    . (Join-Path $repoRoot 'App\Bootstrap.ps1')
    $script:Root=$tmp
    Initialize-YumConfig
    $c=$script:Yum.Config
    if([double]$c.MinimumAvailableGB -ne 7.5){throw "Saved target was not loaded: got $($c.MinimumAvailableGB)"}
    if([string]$c.Mode -ne 'Safe'){throw "Saved mode was not loaded: got $($c.Mode)"}
    if([int]$c.SafeProcessesPerPass -ne 4){throw "Custom SafeProcessesPerPass was overwritten: $($c.SafeProcessesPerPass)"}
    if([int]$c.BalancedProcessesPerPass -ne 10){throw "Old-default BalancedProcessesPerPass was not migrated to the 5.5 default 10: $($c.BalancedProcessesPerPass)"}
    if(-not [bool]$c.StartMonitoringAutomatically){throw 'StartMonitoringAutomatically was forced off at startup.'}
    if([bool]$c.EnableOnlineResearch){throw 'EnableOnlineResearch=false was not honoured.'}
    # And the change must persist through a save + reload.
    Update-YumConfigValue -Name MinimumAvailableGB -Value 9
    Initialize-YumConfig
    if([double]$script:Yum.Config.MinimumAvailableGB -ne 9){throw "Changed target did not persist across restart: $($script:Yum.Config.MinimumAvailableGB)"}
} finally {
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
}

# Fresh download: config.json is not in the repository; the first launch must create it from defaults.
$fresh=Join-Path $env:TEMP ('yumram-fresh-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path (Join-Path $fresh 'Config') -Force | Out-Null
try {
    Copy-Item (Join-Path $repoRoot 'Config\default-config.json') (Join-Path $fresh 'Config\default-config.json')
    Copy-Item (Join-Path $repoRoot 'VERSION') (Join-Path $fresh 'VERSION')
    $script:Root=$fresh
    Initialize-YumConfig
    if(-not (Test-Path -LiteralPath (Join-Path $fresh 'config.json'))){throw 'First launch did not create config.json.'}
    $defaults=Get-Content (Join-Path $repoRoot 'Config\default-config.json') -Raw | ConvertFrom-Json
    if([double]$script:Yum.Config.MinimumAvailableGB -ne [double]$defaults.MinimumAvailableGB){throw 'Fresh config does not use the default target.'}
    if([string]$script:Yum.Config.Version -ne (Get-Content (Join-Path $repoRoot 'VERSION') -Raw).Trim()){throw 'Fresh config version does not match VERSION.'}
} finally { Remove-Item -LiteralPath $fresh -Recurse -Force -ErrorAction SilentlyContinue }
Write-Output 'PASS: saved settings load at startup, persist across restart, only old defaults migrate, and a fresh download creates its config.'
