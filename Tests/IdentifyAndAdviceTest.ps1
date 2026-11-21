#requires -Version 5.1
# 5.15.2 (user report): VoiceMeeter / Roblox beta / ASUS / HP not recognised, no "open file location", scan easy
# to miss, and advice hard to read (recommended / your call / keep). Light checks only; reads this PC, changes nothing.
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'App\Bootstrap.ps1')
Initialize-YumConfig
$script:Yum.Config.Logging=$false
function Assert-That([bool]$Condition,[string]$Message){if(-not $Condition){throw $Message}}

# 1. Catalog.
$k=Get-YumKnownApp -Name 'RobloxPlayerBeta'
Assert-That ($null -ne $k -and $k.Label -eq 'Roblox' -and $k.Category -eq 'Games') 'RobloxPlayerBeta is Roblox (a game).'
Assert-That ((Get-YumKnownApp -Name 'x' -Path 'C:\Users\a\AppData\Local\Roblox\Versions\version-1\RobloxPlayerBeta.exe').Label -eq 'Roblox') 'Roblox matched by its folder too.'
Assert-That ((Get-YumKnownApp -Name 'voicemeeter8x64').Advice -eq 'Keep') 'VoiceMeeter Potato: keep.'
Assert-That ((Get-YumKnownApp -Name 'voicemeeterpro.exe').Label -like 'VoiceMeeter*') 'VoiceMeeter Banana with .exe.'
Assert-That ((Get-YumKnownApp -Name 'AsusSystemAnalysis').Advice -eq 'YourCall') 'ASUS diagnostics are optional.'
Assert-That ((Get-YumKnownApp -Name 'AsusPTPService').Advice -eq 'Keep') 'ASUS touchpad is kept.'
Assert-That ((Get-YumKnownApp -Name 'HpTouchpointAnalyticsClientService').Advice -eq 'YourCall') 'HP analytics is optional.'
Assert-That ((Get-YumKnownApp -Name 'something' -Publisher 'HP Inc.').Label -eq 'HP software') 'Other HP software is recognised by publisher.'
Assert-That ($null -eq (Get-YumKnownApp -Name 'notepad' -Publisher 'Microsoft Corporation')) 'Unrelated programs are not matched.'

# 2. A name alone never makes an unidentified file trusted.
$row=[pscustomobject]@{Risk='Unknown';Category='Unknown';Reason='Unsigned or untrusted executable with no verified publisher identity';IdentityState='Unsigned'}
Set-YumScannerKnownApp -Row $row -Name 'voicemeeter' -Path 'C:\Temp\voicemeeter.exe' -Publisher 'Unknown'
Assert-That ($row.Risk -eq 'Unknown' -and $row.Reason -match 'Named like VoiceMeeter') 'Unsigned look-alike stays Unknown with a hint.'
$row=[pscustomobject]@{Risk='Review';Category='Apps';Reason='Active process';IdentityState='Identified'}
Set-YumScannerKnownApp -Row $row -Name 'AsusSystemDiagnosis' -Path 'C:\x\AsusSystemDiagnosis.exe' -Publisher 'ASUSTeK COMPUTER INC.'
Assert-That ($row.KnownApp -like 'ASUS System*' -and $row.Advice -eq 'YourCall') 'Identified ASUS helper gets its label and advice.'
$row=[pscustomobject]@{Risk='Protected';Category='Games';Reason='Active game';IdentityState='Identified'}
Set-YumScannerKnownApp -Row $row -Name 'AsusSystemDiagnosis' -Path 'C:\x\a.exe' -Publisher 'ASUSTeK'
Assert-That ($row.Risk -eq 'Protected') 'Active-game / foreground protection is never lowered.'

# 3. One advice vocabulary everywhere.
Assert-That ((Get-YumRecordAdvice -Record ([pscustomobject]@{Risk='Unknown';Category='Unknown';Name='x'})).Label -eq 'Careful') 'Unknown -> Careful.'
Assert-That ((Get-YumRecordAdvice -Record ([pscustomobject]@{Risk='Protected';Category='Windows System';Name='dwm'})).Label -eq 'Keep') 'Protected -> Keep.'
Assert-That ((Get-YumRecordAdvice -Record ([pscustomobject]@{Risk='Candidate';Category='Apps';Name='foo'})).Label -eq 'Turn off is fine') 'Candidate -> Turn off is fine.'
Assert-That ((Get-YumRecordAdvice -Record ([pscustomobject]@{Risk='Review';Category='Apps';Name='AsusSwitch';Publisher='ASUSTeK'})).Label -eq 'Your call') 'Optional ASUS helper -> Your call.'
Assert-That ((Get-YumKindAdvice -Kind 'Hardware' -Name 'voicemeeter8x64').Label -eq 'Keep') "What's running: VoiceMeeter -> Keep."
Assert-That ((Get-YumKindAdvice -Kind 'Background' -Name 'AsusSoftwareManager').Label -eq 'Your call') "What's running: ASUS updater -> Your call."
Assert-That ((Get-YumKindAdvice -Kind 'Unknown' -Name 'zzz').Label -eq 'Careful') "What's running: unknown -> Careful."
Assert-That ((Get-YumStartupSuggestion -Name 'MyASUS Switch' -ExePath 'C:\x\AsusSwitch.exe' -Publisher 'ASUSTeK' -Kind 'App').Level -eq 'Your call') 'Startup: optional ASUS helper -> Your call.'
Assert-That ((Get-YumStartupSuggestion -Name 'RtkAudUService' -ExePath 'C:\x\RtkAudUService64.exe' -Publisher 'Realtek' -Kind 'App').Level -eq 'Careful') 'Startup: hardware stays "Keep on (device)".'

# 4. Classic installed programs + file location (read-only).
$progs=@(Get-YumScannerProgramRows -MaxItems 500)
Assert-That ($progs.Count -ge 5) ('Installed programs should be listed, found {0}.' -f $progs.Count)
$withPath=@($progs | Where-Object { $_.Path } | Select-Object -First 1)
if($withPath.Count -gt 0){ $loc=Resolve-YumRecordLocation -Record ([pscustomobject]@{Source='Program';Path=$withPath[0].Path}); Assert-That ($loc -and (Test-Path -LiteralPath $loc)) ('File location not resolved for {0}.' -f $withPath[0].Name) }
Assert-That ((Resolve-YumRecordLocation -Record ([pscustomobject]@{Source='Service';Path='"C:\Windows\System32\svchost.exe" -k netsvcs'})) -ieq 'C:\Windows\System32\svchost.exe') 'Service command line -> file.'
Assert-That ((Resolve-YumRecordLocation -Record ([pscustomobject]@{Source='Process';Path=''})) -eq '') 'No path -> empty, no error.'

# 5. Wiring.
$ix=[IO.File]::ReadAllText((Join-Path $root 'UI\Xaml\Intelligence.xaml'))
foreach($n in 'ActivityCard','ActivityPercent','SelectedAdvice','OpenLocation','SearchOnline'){ Assert-That ($ix -match ('x:Name="{0}"' -f $n)) "Intelligence is missing $n" }
Assert-That ($ix -match 'x:Name="ActivityProgress"[^>]*Height="14"') 'Scan progress bar is big.'
$mx=[IO.File]::ReadAllText((Join-Path $root 'UI\Xaml\MainWindow.xaml'))
Assert-That ($mx -match 'x:Name="SideScanPanel"') 'Sidebar shows a running scan on every page.'
$sc=[IO.File]::ReadAllText((Join-Path $root 'Core\Scanner.ps1'))
Assert-That ($sc -match '\$wide=\[math\]::Max\(\$MaxItems,500\)') 'Scan covers every item, not the first 80.'
Assert-That ((Get-YumResearchStageWords -Stage 'Researching Online') -match 'online') 'Research stage in plain words.'
foreach($x in 'Startup.xaml','WindowsBloat.xaml','TopProcesses.xaml'){ $t=[IO.File]::ReadAllText((Join-Path $root ('UI\Xaml\'+$x))); Assert-That ($t -match 'Our advice|OUR ADVICE') "$x shows 'Our advice'" }
# 6. Plain words (user: "make sure the user will be able to understand everything"). Labels people see.
$intel=[IO.File]::ReadAllText((Join-Path $root 'UI\Xaml\Intelligence.xaml'))
foreach($w in 'Text="RESOLVED"','Text="CACHED"','Header="Risk"','Header="Status"'){ Assert-That (-not $intel.Contains($w)) "Intelligence still shows jargon: $w" }
foreach($w in 'Header="Our advice"','Text="NOT CHECKED YET"','Value="Turn off is fine"','Value="Careful"'){ Assert-That ($intel.Contains($w)) "Intelligence is missing plain label: $w" }
$rc=[IO.File]::ReadAllText((Join-Path $root 'UI\Xaml\MemoryReclaim.xaml'))
foreach($w in 'TRIMMED LAST RUN','Before MB','Trimmed MB','STANDBY CACHE'){ Assert-That (-not $rc.Contains($w)) "Reclaim Center still shows jargon: $w" }
$mr=[IO.File]::ReadAllText((Join-Path $root 'Core\MemoryReclaim.ps1'))
Assert-That ($mr -notmatch 'Process working sets reduced' -and $mr -notmatch 'Historical reclaim effectiveness is') 'Reclaim summary and reasons in plain words.'
$mwp=[IO.File]::ReadAllText((Join-Path $root 'UI\MainWindow.ps1'))
Assert-That ($mwp -notmatch "'Telemetry: \{0" -and $mwp -notmatch 'Below configured target') 'Status bar / footer in plain words.'

# 7. Research sees every installed program (5.15.2 fix: a strict-mode error dropped whole registry hives - this PC
#    had 3 of ~265 entries, so WinRAR, Git, GPU-Z and the NVIDIA driver ended "Unknown" on a first scan).
. (Join-Path $root 'Core\Research.ps1')
$script:YumResearchRegistryInventory=$null
$someProg=@($progs | Where-Object { $_.Publisher -and $_.Publisher -ne 'Unknown' } | Select-Object -First 3)
foreach($pg in $someProg){ $m=@(Get-YumInstalledSoftwareResearch -Name $pg.Name -Publisher $pg.Publisher -Path $pg.Path); Assert-That ($m.Count -ge 1 -and [int]$m[0].Score -ge 60) ('Installed program not matched by research: {0}' -f $pg.Name) }
Assert-That ($script:YumResearchRegistryInventory.Count -ge [math]::Floor($progs.Count*0.8)) ('Research registry list too short: {0} for {1} programs' -f $script:YumResearchRegistryInventory.Count,$progs.Count)
Assert-That ((Get-YumResearchOverlapFast ([string[]]@(Convert-YumResearchText 'Google Chrome')) (Get-YumResearchTokenSet 'Chrome browser by Google')) -eq (Get-YumResearchTokenOverlap -Left 'Google Chrome' -Right 'Chrome browser by Google')) 'Fast overlap gives the same score.'
$drv=Get-YumResearchPlacement -Name 'NVIDIA Graphics Driver 617.42' -Publisher 'NVIDIA Corporation' -Category 'Apps' -Risk 'Review' -RegistryEvidence @([pscustomobject]@{Score=70;Publisher='NVIDIA Corporation'})
Assert-That ($drv.Placement -eq 'Drivers / Hardware') ('Driver package placed as {0}' -f $drv.Placement)

# 8. Signer / publisher check (5.15.2 fix: the old check compared the wrong way round and never matched).
Assert-That (Test-YumSignerMatchesPublisher -Signer 'CN=Discord Inc., O=Discord Inc., L=San Francisco, S=California, C=US' -Publisher 'Discord Inc.') 'Discord signer matches Discord publisher.'
Assert-That (Test-YumSignerMatchesPublisher -Signer 'CN="Anthropic, PBC", O="Anthropic, PBC", L=San Francisco, S=California, C=US' -Publisher 'Anthropic, PBC') 'Quoted certificate names are read.'
Assert-That (-not (Test-YumSignerMatchesPublisher -Signer 'CN=Evil Corp, O=Evil Corp, C=US' -Publisher 'Discord Inc.')) 'A different signer never matches.'
Assert-That (-not (Test-YumSignerMatchesPublisher -Signer 'CN=Acme Inc., O=Acme Inc.' -Publisher 'Inc.')) 'Generic words alone ("Inc.") never match.'
Assert-That (-not (Test-YumSignerMatchesPublisher -Signer 'CN=Acme, O=Acme' -Publisher 'Unknown')) 'Unknown publisher never matches.'

# 9. Every sidebar button is registered, so clicking it opens its page (5.15.2: Disk cleanup's button did nothing).
$shell=[IO.File]::ReadAllText((Join-Path $root 'UI\Shell.ps1'))
$navList=[regex]::Match($shell,"foreach\(\`$k in @\(('[^)]*')\)\)").Groups[1].Value -split ',' | ForEach-Object { $_.Trim().Trim("'") }
$uiList=[regex]::Match($mwp,"foreach\(\`$n in @\(('Intelligence'[^)]*)\)\)").Groups[1].Value
foreach($k in $navList){ Assert-That ($uiList -match ("'{0}'" -f [regex]::Escape($k))) ("Sidebar button {0} is not registered in the main window control list - clicking it would do nothing." -f $k) }

Write-Host ('IdentifyAndAdviceTest passed. {0} installed programs read.' -f $progs.Count)
