#requires -Version 5.1
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$log=Join-Path $root 'YUMRAM.log'

try {
Add-Type -MemberDefinition @'
[DllImport("kernel32.dll")]
public static extern IntPtr GetConsoleWindow();
[DllImport("user32.dll")]
public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
'@ -Name ConsoleWin -Namespace YumRamConsole -ErrorAction Stop
$h=[YumRamConsole.ConsoleWin]::GetConsoleWindow()
if($h -ne [IntPtr]::Zero){[void][YumRamConsole.ConsoleWin]::ShowWindow($h,0)}
} catch {}
try { $entry=('[{0}] YUMRAM launcher process started.' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff')); if(-not(Test-Path -LiteralPath $log)){New-Item -ItemType File -Path $log -Force|Out-Null}; Add-Content -LiteralPath $log -Value $entry -Encoding UTF8; Add-Content -LiteralPath (Join-Path $env:TEMP 'YUMRAM-app-startup.log') -Value $entry -Encoding UTF8 } catch {}
try {
    Add-Content -LiteralPath $log -Value ('[{0}] Bootstrap loading.' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff')) -Encoding UTF8
    . (Join-Path $root 'App\Bootstrap.ps1')
    Add-Content -LiteralPath $log -Value ('[{0}] Bootstrap loaded.' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff')) -Encoding UTF8
} catch {
    try { Add-Content -LiteralPath $log -Value ((Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff') + ' BOOTSTRAP ERROR: ' + $_.Exception.ToString()) -Encoding UTF8 } catch {}
    exit 1
}
try { Start-YumRamApplication } catch { try { $line=("[{0}] STARTUP ERROR: {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'),$_.Exception.ToString()); Add-Content -LiteralPath $log -Value $line -Encoding UTF8; $tempCopy=Join-Path $env:TEMP 'YUMRAM-app-startup-error.log'; Copy-Item -LiteralPath $log -Destination $tempCopy -Force -ErrorAction SilentlyContinue; Add-Content -LiteralPath (Join-Path $env:TEMP 'YUMRAM-startup.log') -Value $line -Encoding UTF8 } catch {}; exit 1 }
