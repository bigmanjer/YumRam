# YUMRAM 5.3.0 — Alpha (consolidated from 5.2.74 and 5.2.90)

5.2.90 is the base. 5.2.74's only unique feature (the Cleanup Preview window) was intentionally
replaced by the RAM Reclaim Center in 5.2.80 and is not restored. This release makes the core
features actually run; several were silently dead in 5.2.90. Full analysis: `Docs/REVIEW-5.3.0.md`.

## Fixed: features that never worked
- **Automatic target maintenance never ran.** The controller used `System.Timers.Timer` with a
  PowerShell scriptblock; on Windows PowerShell 5.1 those handlers fire on threads with no
  runspace and never execute. It now runs in a runspace worker (`Core\Controller.ps1`), which also
  revives queued Safe Optimization requests.
- **Auto-clean on game start and the game priority boost never ran.** Nothing called
  `Update-YumGameState`; the controller worker now calls it every second while monitoring.
- **FREE RAM NOW / DEEP RAM RECLAIM always failed.** `-TopN (if(...){16}else{10})` ran a command
  named `if`. Behind that: `@($genericList)` "Argument types do not match" and `Measure-Object .Sum`
  on empty input under StrictMode.
- **Automatic cleanup could not select or trim processes.** `Sort-Object -Ascending` (no such
  parameter) threw in every trim plan; the trim log line divided an array (comma binds tighter
  than `/`) and aborted the pass after the first trim; one large idle process could never be
  chosen when RAM was only slightly below target.
- **Reclaim verification (5s/15s/30s) never ran and always showed "Pending".**

## Fixed: other bugs
- Ten messages showed a literal `` `n `` instead of a line break.
- Research progress text threw a FormatException (3 placeholders, 2 arguments).
- Research lost the executable identity of services/startup items with quoted arguments.
- Negative NTSTATUS codes threw when formatted, hiding the real error.
- `Update-YumSnapshotMemory` wrote a snapshot that readers immediately overwrote.
- Stopping monitoring now also stops automatic maintenance; on exit the controller stops before
  optional services are restored.

## Improved
- Reclaim Center no longer rebuilds its table every second or runs WMI on the UI thread.
- Per-step reclaim measurements use the fast native snapshot (no WMI per trimmed process).
- Tests: 40/40 passing (was 12/37). New `Tests\Run-AllTests.ps1` and three behavioral tests.
- All sources normalized to UTF-8 BOM + CRLF.

## Upgrade note
`ResearchEngineVersion` changed, so the first Intelligence scan re-researches cached items.

# YUMRAM 5.2.90 — UI, Telemetry and Reclaim Verification

- Telemetry metrics now distinguish unavailable from zero.
- Reclaim results include non-blocking retained-effect verification at 5s, 15s, and 30s.

## Fixed
- Responsive RAM Reclaim Center sizing and narrower table layout.
- Corrected Cache and Commit telemetry to use Windows `GetPerformanceInfo`; unavailable metrics display `N/A` instead of false zeroes.
- Added non-blocking 5s/15s/30s reclaim-effectiveness verification and retained-gain reporting.
- Added native memory-list API bindings and privilege handling required by Deep Reclaim.
- Improved main-dashboard wording so below-target memory is not automatically described as emergency pressure.
- Kept the preview scan removed from RAM Reclaim Center startup.

# YUMRAM 5.2.87 — Stability Contract Cleanup

## Fixed
- Synchronized `VERSION`, default configuration `Version`, and `ResearchEngineVersion`.
- Removed duplicate UI helper implementations from `UI/Dialogs.ps1`; canonical core implementations are now authoritative.
- Converted release-version regression assertions to derive the expected version from the canonical `VERSION` file.
- Moved historical release/audit documents into `Docs/History` where applicable.
- Preserved the RAM Reclaim Center runtime fixes and Research State UI removal.

## Release policy
`VERSION` is the source of truth for the active YUMRAM release. Tests and runtime configuration must consume it rather than hard-code historical versions.

# YUMRAM 5.2.86 — RAM Reclaim Center Runtime Fix

## Fixed
- Corrected RAM Reclaim Center button handlers.
- The action handlers now receive the shared reclaim state instead of reading a nonexistent `Button.Tag`.
- Corrected Close handler to close the owning window.
- Added a regression test for the state-binding bug that caused `Progress` and `FreeRam` property errors.

## Runtime diagnosis
This fixes the 5.2.85 error:
`The property 'Progress' cannot be found on this object.`
and the follow-on:
`The property 'FreeRam' cannot be found on this object.`

# YUMRAM 5.2.86 — Windows PowerShell Encoding Fix

## Fixed
- Converted all PowerShell source (`.ps1`, `.psm1`) to UTF-8 with BOM for Windows PowerShell 5.1.
- Preserved emoji and non-ASCII UI/log text without parser corruption.
- Converted WPF XAML files to UTF-8 with BOM for consistent parsing.
- This specifically fixes `UI\MainWindow.ps1` failures where `💜` was decoded as mojibake (`ðŸ’œ`) and caused a PowerShell ParseException.

## Validation
- No PowerShell source file is emitted as UTF-8 without BOM.
- Launcher remains ANSI/no BOM.

# YUMRAM 5.2.83 — Launcher Reliability Fix

## Fixed
- Removed the UTF-8 BOM from `Launch-YUMRAM.cmd`; the Windows CMD interpreter now sees `@echo off` correctly.
- Launcher no longer overwrites `YUMRAM.log` after an application failure.
- Launcher/startup diagnostics remain in `%TEMP%\YUMRAM-startup.log`.
- The application owns `YUMRAM.log`, preserving the real PowerShell exception and application diagnostics.

## Validation
- CMD file: no UTF-8 BOM.
- Destructive startup-log-to-application-log copy: absent.

