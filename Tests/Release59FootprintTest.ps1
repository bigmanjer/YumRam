#requires -Version 5.1
# 5.9: YUMRAM's own footprint stays low, and CPU is visible per program.
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
function Assert-That([bool]$Condition,[string]$Message){if(-not $Condition){throw $Message}}
$tw=Get-Content -Raw (Join-Path $root 'Core\TelemetryWorker.ps1')
Assert-That ($tw -match "UiWantsGpu" -and $tw -match '\$uiWantsGpu -and') 'GPU sampling must be skipped while the Overview is not on screen.'
$mw=Get-Content -Raw (Join-Path $root 'UI\MainWindow.ps1')
Assert-That ($mw -match "TelemetryCache\['UiWantsGpu'\]=\`$overviewShown") 'The UI must tell telemetry whether the Overview is on screen.'
Assert-That ($mw -match 'if\(\$newSnapshot -and -not \$overviewShown\)') 'Nothing may be redrawn while hidden / on another page.'
Assert-That ($mw -notmatch 'Measure-Object -Minimum') 'The graph must not use pipelines every refresh.'
Assert-That ($mw -match 'FromSeconds\(1\)') 'The screen timer must slow down while hidden.'
$tray=Get-Content -Raw (Join-Path $root 'UI\Tray.ps1')
Assert-That ($tray -match 'function Invoke-YumSelfTrim' -and $tray -match 'Invoke-YumSelfTrim\}') 'YUMRAM must release its own idle memory when hidden in the tray.'
$ct=Get-Content -Raw (Join-Path $root 'Core\Controller.ps1')
Assert-That ($ct -match '\$estimateEvery=120') 'The reachable estimate must refresh less often while nobody sees it.'
[xml]$x=Get-Content -Raw (Join-Path $root 'UI\Xaml\TopProcesses.xaml')
$names=@($x.SelectNodes('//*[@*[local-name()="Name"]]') | ForEach-Object { $_.GetAttribute('Name','http://schemas.microsoft.com/winfx/2006/xaml') })
foreach($n in 'SumCpu','SumCpuTop','SumCpuBar','SortRam','SortCpu','ExplainCpu','SumBiggest'){Assert-That ($names -contains $n) "What's running is missing $n"}
$dl=Get-Content -Raw (Join-Path $root 'UI\Dialogs.ps1')
Assert-That ($dl -match 'CpuPercent' -and $dl -match "SortBy" -and $dl -match "CPU held back") 'Per-program CPU, sorting and the CPU balance marker must be wired.'
Write-Host 'Release 5.9 footprint test passed.'
