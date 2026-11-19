# YUMRAM 5.3.2 — Alpha: learns each PC, shows what is reachable

- **Per-PC learned retention.** Only part of a trimmed working set becomes Available RAM, and the
  share differs per machine. Every settled reclaim/cleanup pass that trims >= 200 MB updates a
  running average saved in `reclaim-learning.json` (bounded 15-90%; default 40% until 2 samples).
  First real run here: samples 45/42/28/38/35% -> 38%, matching the hand measurement (38-40%).
- **Trim planner uses the learned ratio** instead of a fixed 40%.
- **"Reachable ≈ X GB"** on the target line: current Available + (memory the current mode may trim
  x learned retention). The status shows **[OUT OF REACH]** when the target is above it, and the
  tooltip explains the numbers. Setting a target above it shows a note and resets the back-off.
- Tests: 42/42 (new RetentionLearningTest).

# YUMRAM 5.3.1 — Alpha: lag, settings, and reclaim strength

Measured on the developer's 16 GB Windows 11 PC with the real program running.

## Lag
| While monitoring | 5.3.0 | 5.3.1 |
|---|---|---|
| YUMRAM CPU (idle) | 77% of a core | 14% of a core |
| UI work per refresh | 25 ms avg, 298 ms worst | 4.6 ms avg, 24 ms worst |
| Free RAM / Deep Reclaim | froze the window | runs on the background worker |

- GPU usage was read with `Get-Counter`, costing ~1.4 s of CPU every 3 s. Now read directly
  (~0.27 s) and at most every 5 s.
- The telemetry aux loop republished a snapshot every 200 ms, so the UI redrew the graph ~4x/s and
  the graph only held ~15 s of history. It now publishes only when GPU/game data changes.
- Game detection uses a hash-set lookup (~6x less CPU).
- Automatic maintenance backs off (30 s, doubling to 2 min) when the target cannot be reached,
  instead of re-scanning every 1-4 s forever.
- Per-process cooldown actually works now (it was checked but never recorded), so a busy app is
  no longer trimmed on every pass and immediately paged back in.

## Settings
- **Saved settings were ignored at every launch** (present since 5.2.x): the config merge bound an
  ordered dictionary to a `[hashtable]` parameter, which made a copy, so the app always started on
  defaults (e.g. a 10 GB target came back as 4 GB). Fixed, with a regression test.
- Modes retuned. Safe mode could never trim anything (score floor 65 was unreachable); Balanced
  skipped most mid-size apps. New floors: Safe 34, Balanced 24, Aggressive 12; larger per-pass
  budgets. Balanced now also trims "Review" processes with a valid publisher signature.
- Old default values are migrated (2/3/5 processes per pass -> 3/5/8, Free RAM actions 3 -> 8,
  GPU interval 3 s -> 5 s); values you changed yourself are kept.

## Reclaim strength
- **Free RAM Now / Deep Reclaim never trimmed a process** in 5.3.0: a helper rejected `$null`
  (no reclaim history yet), so every candidate was skipped. Now: +0.45 to +0.90 GB per click here.
- Trimmed memory reaches "Available" 1-2 s later and only ~40% of it (measured). Cleanup now
  plans with that ratio and waits 1.5 s before judging a pass, instead of seeing ~0 gain and
  escalating into fallback churn.
- Learning now records how much of each trim stayed trimmed, deprioritizing apps that page
  straight back in (it previously penalized every process after two samples).
- Deep reclaim flushes the modified list *after* trimming (5.3.0 flushed first, too early).
- Free RAM Now uses the Intelligence classifier, so it no longer trims protected items such as
  Steam's web helper (game overlay).

Result with Balanced + 10 GB target: automatic maintenance gained +0.74 GB (was +0.07 GB).
Tests: 41/41 (new: ConfigPersistenceTest; reclaim test now checks real candidates).

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

