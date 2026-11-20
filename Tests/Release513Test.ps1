#requires -Version 5.1
# 5.13: Report a problem (details, privacy scrubbing, URL size), safer uninstall, standard zip paths,
# valid issue forms.
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'App\Bootstrap.ps1')
Initialize-YumConfig
$script:Yum.Config.Logging=$false
function Assert-That([bool]$Condition,[string]$Message){if(-not $Condition){throw $Message}}

# 1. Personal details are removed.
$raw="C:\Users\$env:USERNAME\AppData\Local\x.exe started by $env:USERNAME on $env:COMPUTERNAME; mail jane.doe@example.com; $env:LOCALAPPDATA\y"
$clean=Protect-YumReportText $raw
foreach($s in @($env:USERNAME,$env:COMPUTERNAME,'jane.doe@example.com',$env:LOCALAPPDATA)){ Assert-That ($clean.IndexOf($s,[StringComparison]::OrdinalIgnoreCase) -lt 0) ("Report text still contains '{0}'." -f $s) }
Assert-That ($clean -match '%USERPROFILE%' -and $clean -match '<user>' -and $clean -match '<pc>' -and $clean -match '<email>') 'Replacements are readable.'

# 2. Real details from this PC, scrubbed.
$d=Get-YumReportDetails
Assert-That ($d.Version -eq [string]$script:Yum.Config.Version) 'Version is the running version.'
Assert-That ($d.Pc -match 'Windows') 'PC details include Windows.'
Assert-That ($d.Admin -in @('Ask each time','Start without asking','Never','Not sure')) 'Admin mode matches a form option.'
Assert-That ($d.Pc.IndexOf($env:COMPUTERNAME,[StringComparison]::OrdinalIgnoreCase) -lt 0) 'No PC name in the details.'

# 3. URL: pre-filled fields, under GitHub's size limit even with a huge log, newest lines kept.
$u=Get-YumReportUrl -Details $d -What 'test'
Assert-That ($u -like 'https://github.com/*/issues/new?template=bug_report.yml&title=*') 'Opens the bug-report form.'
foreach($k in 'version','admin','pc','what'){ Assert-That ($u -match ('[?&]{0}=' -f $k)) ("URL fills in '{0}'." -f $k) }
$big=[pscustomobject]@{Version='1';Admin='Never';Pc='x';Log=((1..2000 | ForEach-Object { "line $_ " + ('x' * 80) }) -join "`n")}
$u2=Get-YumReportUrl -Details $big
Assert-That ($u2.Length -le 7500) ('URL too long: {0}' -f $u2.Length)
Assert-That ($u2 -match 'line%202000') 'Newest log line kept.'
Assert-That ((Get-YumReportUrl -Details $big -NoLog) -notmatch '[?&]log=') '-NoLog leaves the log out.'

# 4. Form fields used by the URL exist in the bug form (ids), and the forms use block YAML (no flow maps
#    with unquoted commas - that broke both forms on GitHub in 5.12.0).
$form=[IO.File]::ReadAllText((Join-Path $root '.github\ISSUE_TEMPLATE\bug_report.yml'))
foreach($k in 'version','admin','pc','what','log'){ Assert-That ($form -match ('id:\s*{0}\b' -f $k)) ("bug_report.yml has field '{0}'." -f $k) }
foreach($f in Get-ChildItem (Join-Path $root '.github\ISSUE_TEMPLATE') -Filter *.yml){ Assert-That (-not ([IO.File]::ReadAllText($f.FullName) -match 'attributes:\s*\{')) ("{0}: use block style for attributes." -f $f.Name) }

# 5. Wiring: About button, tray item, module loaded.
$about=[IO.File]::ReadAllText((Join-Path $root 'UI\Xaml\About.xaml'))
Assert-That ($about -match 'x:Name="ReportProblem"') 'About has Report a problem.'
Assert-That ([IO.File]::ReadAllText((Join-Path $root 'UI\Dialogs.ps1')) -match "FindName\('ReportProblem'\)") 'About button is wired.'
Assert-That ([IO.File]::ReadAllText((Join-Path $root 'UI\Tray.ps1')) -match 'Open-YumReportProblem') 'Tray menu has Report a problem.'
Assert-That ($null -ne (Get-Command Open-YumReportProblem -ErrorAction SilentlyContinue)) 'Report module loaded by Bootstrap.'

# 6. Uninstall safety (source): only this copy's entries, own files only, refuses a git folder.
$cs=[IO.File]::ReadAllText((Join-Path $root 'Launcher\YumramLauncher.cs'))
Assert-That ($cs -notmatch 'rmdir /s /q') 'Uninstall must never delete the whole folder recursively.'
Assert-That ($cs -match 'OwnDirs' -and $cs -match 'OwnFiles') 'Uninstall deletes only known YUMRAM files.'
Assert-That ($cs -match '"\.git"') 'Uninstall refuses a development folder.'
Assert-That ($cs -match 'InstallLocation' -and $cs -match 'PointsInto') 'Uninstall checks entries point at this copy.'

# 7. Release zip writes "/" paths.
Assert-That ([IO.File]::ReadAllText((Join-Path $root 'Tools\Build-Release.ps1')) -match "Replace\('\\','/'\)") 'Build-Release writes standard zip paths.'

Write-Host 'Release513Test passed.'
