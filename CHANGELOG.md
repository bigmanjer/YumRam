# Changelog

# YUMRAM 5.6.0 — One window, global shortcut, freed-RAM counter (branch `visual-overhaul`)

Compared against IObit Advanced SystemCare / Smart RAM, Wise Memory Optimizer, Mem Reduct, Process
Lasso and Razer Cortex; this release closes the gaps that mattered for everyday use.

- **One window with a sidebar.** Overview, What's using RAM, Reclaim Center, Intelligence, Settings
  and About are pages in the main window instead of separate pop-ups (the Windows 11 Task Manager /
  Fluent NavigationView pattern: left pane for 5–10 equal sections, Settings at the bottom). The
  sidebar always shows mode, monitoring state and RAM in use, shrinks to icons below 1240 px (or with
  the ☰ button), and `Ctrl+1`…`Ctrl+6` switch pages. Done/Close on a page returns to Overview.
  Intelligence stays alive in the background, so scans and research keep running while you look at
  other pages and it reopens instantly.
- **Global shortcut for Free RAM now** (Mem Reduct has one): `Ctrl+Alt+R` by default, works while
  YUMRAM is minimised to the tray or a game is in front; a tray notice reports the result. Change or
  turn it off in Settings › General. If another program already owns the shortcut, Settings says so.
- **RAM freed by YUMRAM** card (IObit / Wise show this): today and all-time totals, counted from the
  measured Available RAM gain after Windows settles — not trimmed working set, which overstates it.
  Saved in `stats.json`.
- Already on par: free-when-below-threshold (memory goal), skip-when-CPU-busy (`MaxCPUPercent`),
  memory-area choice and game-aware protection.
- Tests: new `Release56ShellTest`; 47/47 pass.

# YUMRAM 5.5.0 — Stays at target, no more Unknowns, plain-language process view (branch `visual-overhaul`)

Memory (from the 5.4 field test: Deep gained +1.2 to +3.5 GB, Free RAM Now +0.3 GB, and automatic
care logged "Target not reachable" every 30-120 s just under a 9 GB goal):
- **Free RAM Now is much closer to Deep.** It now also trims the system file cache (pages move to
  standby, so files stay cached) and flushes the modified list, and considers 24 processes / 12 trims
  (was 16 / 8). Deep alone still purges standby and empties every working set at once.
- **Automatic care keeps up.** When trimming alone falls short, it runs the same file-cache +
  modified-list step (administrator only, never during a game, at most every 45 s). The "reachable"
  estimate includes it.
- **Per-pass limits were silently capped** at 4 / 6 / 10 (Safe / Balanced / Aggressive), so higher
  values in Settings did nothing. Caps are now 10 / 16 / 24; defaults raised to 6 / 10 / 16, clean
  interval 30 → 15 s (old defaults migrate; your own values are kept).

Intelligence:
- **Unknowns resolved on this PC: 0 left (was 2-8).** Protected processes (audiodg, sppsvc,
  SearchProtocolHost, NVIDIA containers, Gaming Services) hide their path from non-admin programs;
  YUMRAM now finds the binary through its Windows service or System32 and lets Windows verify the
  signature. Microsoft's own Store package IDs resolve as Windows components.
- **Research could stop working for good**: a status file left by a closed or crashed run made every
  later Run Scan think research was still running. Status files now carry the process id, and per-item
  results no longer end the run early.
- **Manual decisions now work visibly**: choosing a category resolves the item (risk + status) instead
  of leaving it "Unknown"; "Review Queue" now means reset (it used to pin items as Unknown forever).
- Clicking a summary card switches the Show view and outlines the card; the selected item gets a
  header, the decision panel starts from the item's current category, the search box has a hint, and
  there is a result count. Status appears once (activity strip) instead of four times.
- Saved records that are still Unknown are re-checked on Run Scan, not only running programs.

Windows:
- **What's using my RAM** (was Top memory processes): one row per program (Chrome's 17 processes = 1
  row), memory bars, plain type labels, updates itself every 2 s without losing your selection
  (Pause available), and a "What is this?" panel in everyday words: what it is, how much RAM, can I
  close it, what YUMRAM does with it, where it is, and **Show in File Explorer**.
- **RAM Reclaim Center**: the two options side by side with exactly what each does, an administrator
  badge, coloured results, clearer empty state.
- **Main window**: all tools in the header (the Tools card was below the fold).
- **About**: feature tiles and quick links (YUMRAM folder, log, project page).

Tests: 46/46 (new Release55BehaviorTest; two text-contract tests updated for the new code).

# YUMRAM 5.4.0 — Visual overhaul and faster, more complete research (branch `visual-overhaul`)

Design (researched against Microsoft PC Manager, Wise Memory Optimizer, IObit and Windows 11
guidance; see `Docs/COMPETITIVE-REVIEW.md`, screenshots in `Docs/Screenshots/before|after`):
- One shared theme (`UI/Xaml/Theme.xaml`) for every window: Windows 11 type scale, 4 px grid,
  AA contrast; tables, scrollbars, tabs, group boxes and buttons no longer fall back to white/grey
  Windows defaults.
- Main window reorganized: Available RAM with a RAM-in-use ring, automatic care, and one primary
  "Free RAM now" at the top; graph plus side panel below; no overlapping labels.
- Reclaim Center, Settings (now in tabs), Top Processes, About and Intelligence reorganized.

Tray icon (new, `UI/Tray.ps1`):
- The notification-area icon shows live RAM in use as a number, coloured like the main ring
  (purple, amber from 70 %, red from 85 %); tooltip shows % used and GB free.
- Right-click: Open YUMRAM, Free RAM now (result shown as a notification), Start/Stop monitoring,
  Exit. Left-click opens the window.
- Minimizing hides YUMRAM to the tray (Settings → General: "Show RAM % in the notification area",
  "Minimize to the notification area"; both on by default). The main window now runs its own
  message loop instead of `ShowDialog()`, which would have exited YUMRAM when hidden.
- Icon redraws only when the rounded % changes; tested for GDI/USER handle leaks.

Research:
- All 6 previous Unknowns on the test PC resolve: Store/System packages now use Windows' own
  publisher and signature data (the scanner stored the publisher ID hash before).
- Online verification works for the first time: the trust check assigned to the read-only `$host`
  variable and scored every site 0. The publisher's own domain now counts as authoritative.
- About 3x faster on real items: one `winget list` per run instead of one winget.exe per item
  (whose exact-match flag never worked), cached executable paths, parallel web requests, and
  linear-time text matching (one vendor page took 85 s, now ~1 s).
- Unknown results are re-checked once when the research engine improves.
- Game detection no longer matches "EA" inside words like "Search".

Tests: 45/45 (new ResearchSpeedAndIdentityTest, TrayIconTest; pitfall scan flags assignments to automatic variables).

# YUMRAM 5.3.3 — Alpha: GitHub-ready

- **Settings → Privacy** switch for online research (on by default; it sends unidentified
  programs' names to Bing). Previously there was no way to turn it off in the app.
- **"Start monitoring automatically" now works.** 5.2.x forced it off at every launch.
- `config.json`, logs and learned data are no longer shipped; the first launch creates
  `config.json` from defaults (tested).
- New `Tests\PowerShell51PitfallScanTest.ps1`: an AST scan for the seven PS 5.1 bug patterns
  found in this release cycle (it flags 19 issues in the original 5.2.90 code, 0 now).
- GitHub Actions workflow (`windows-latest`, Windows PowerShell 5.1), `.gitattributes` for CRLF,
  `CONTRIBUTING.md`, current `Docs/ARCHITECTURE.md`; 96 historical audit files moved to
  `Docs/History`. Release notes are now this `CHANGELOG.md`.

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

