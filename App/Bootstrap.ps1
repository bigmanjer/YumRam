#requires -Version 5.1
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$script:Root=Split-Path -Parent $PSScriptRoot
$modules=@('Core\Logging.ps1','Core\Config.ps1','Core\Intelligence.ps1','Core\Native.ps1','Core\Games.ps1','Core\Safety.ps1','Core\Bloatware.ps1','Core\Scanner.ps1','Core\Telemetry.ps1','Core\Cleanup.ps1','UI\Dialogs.ps1','UI\MainWindow.ps1')
foreach($relative in $modules){$path=Join-Path $script:Root $relative; try { Add-Content -LiteralPath (Join-Path $script:Root 'YUMRAM.log') -Value ('[{0}] Bootstrap module: {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'),$relative) -Encoding UTF8 } catch {}; if(-not(Test-Path -LiteralPath $path)){throw "Missing module: $path"}; . $path}

