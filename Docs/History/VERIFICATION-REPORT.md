# YUMRAM 4.5.9 Verification Report

## Scope

This release is based on the previously working YUMRAM 4.3.1 GUI/runtime and merges the requested monitoring, scanner, cleanup, UI, and safety improvements without replacing the specialized dashboard.

## Static checks performed in the build environment

- 35 files packaged.
- All PowerShell modules saved as UTF-8 with BOM for Windows PowerShell 5.1 compatibility.
- All WPF XAML files parsed as XML successfully.
- `default-config.json` parsed successfully.
- MainWindow control references checked, including telemetry status and PC Scan.
- Required-file manifest checked.
- Here-string delimiter counts checked across PowerShell modules.
- Core modules scanned for automatic `Stop-Process`, `taskkill`, `TerminateProcess`, `.Kill()`, `Remove-Service`, and `Set-Service` signatures. Manual End Task is intentionally isolated to `UI/Dialogs.ps1`.
- ZIP integrity checked with `unzip -t`.

## Architecture changes

Telemetry sampling and the background cleanup controller now use separate timers. This prevents a long cleanup pass from blocking the next telemetry sample. The UI reads published snapshots and maintains graph history on the UI thread.

## Scanner

The scanner inventories running processes, running services, and AppX packages. It gathers evidence such as memory, CPU, foreground/game state, publisher/signature information, service start mode, `CanStop`, and running dependents. Unknown software is review-only and is never automatically classified as disposable.

## Manual End Task

Top Memory Processes offers an explicit user-confirmed End Task action. It attempts graceful window close first and only offers a force-end after the process refuses to close. YUMRAM safety protections still veto protected targets.

## Known limitation

The build environment used for packaging is not Windows, so live Windows PowerShell 5.1/WPF execution and native Windows API behavior were not run here. The included `Tests/StaticTest.ps1` is intended for the final Windows-side parser/runtime verification.
