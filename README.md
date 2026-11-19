# YUMRAM 5.3.0 — Alpha

Version: 5.3.0 (alpha)
Previous release: 5.2.90 ("Startup Fixed" / "UI-Telemetry-Verified")
Earlier build reviewed: 5.2.74 ("GUI Refined Classification Fix")

YUMRAM is a Windows PowerShell 5.1 + WPF memory manager. It keeps Available RAM above a target
by trimming the working sets of idle, identified processes, purges the standby lists on request,
and classifies everything running on the machine (Intelligence + Research) so it never touches
protected, security, driver, game, or unknown processes.

## Running it

Double-click `Launch-YUMRAM.cmd` (or `Launch-YUMRAM.vbs` for no console window).
YUMRAM asks for administrator rights: the standby-list and system working-set commands need
`SeProfileSingleProcessPrivilege`, and trimming other users' processes needs elevation.

- **FREE RAM NOW** – purges the low-priority standby list, then trims up to N idle processes.
- **DEEP RAM RECLAIM** – also purges the full standby list (and, if enabled in Settings, the
  modified-page list and system working sets). Not run while a game is detected.
- **Start Monitoring** – turns on automatic target maintenance: whenever Available RAM drops
  below your target, YUMRAM trims eligible idle processes in small, paced passes.
- **RAM Reclaim Center** – shows the last reclaim and its 5s/15s/30s retained-gain verification.
- **Smart Intelligence** – scans processes, services, apps, and startup items and researches
  anything unresolved.

## Running the tests

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File Tests\Run-AllTests.ps1
```

All 40 tests pass on Windows PowerShell 5.1. The behavioral tests (`ControllerWorker`,
`ReclaimEngineBehavior`, `CleanupCoreBehavior`) fake the native memory calls and process trims,
so running them never changes anything on the machine.

## What "alpha" means here

The memory engine, automatic maintenance, and UI were verified working end to end on Windows 11
with PowerShell 5.1.26100. See `RELEASE-NOTES.md` for what changed and `Docs/REVIEW-5.3.0.md`
for the full review, the remaining known issues, and the recommended road to beta.
