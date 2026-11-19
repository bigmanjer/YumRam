# YUMRAM 5.3.0 — Expert Review, Fixes, and Road to Beta

Reviewed: 5.2.90 (folder + `YUMRAM-5.2.90-Startup-Fixed.zip`, identical) and 5.2.74
(`YUMRAM-V5.2.74-GUI-REFINED-CLASSIFICATION-FIX.rar`). Environment: Windows 11, Windows
PowerShell 5.1.26100.

## 1. Consolidation

| Version | Status | Decision |
|---|---|---|
| 5.2.90 | Newest code. Folder is named 5.2.89 but `VERSION` says 5.2.90. | Base for 5.3.0 |
| 5.2.74 | Older. Only unique feature: Cleanup Preview window. | Not restored: replaced by RAM Reclaim Center in 5.2.80, and removed deliberately because the preview scan made the window lag |

Everything else in 5.2.74 exists in 5.2.90 in a newer form. Historical audit documents from both
versions remain in `Docs/` and `Docs/History/`.

## 2. Critical defects found and fixed

Each one was verified by reproducing it, and each is now covered by a test.

| # | Defect | Effect in 5.2.90 | Test |
|---|---|---|---|
| 1 | `System.Timers.Timer` + scriptblock handler (controller, reclaim verifier) | Handler never executes on PS 5.1: **automatic maintenance, queued optimizations, and verification never ran** | ControllerWorkerRegressionTest |
| 2 | `Update-YumGameState` never called | Auto-clean on game start and game priority boost did nothing | (worker calls it each tick) |
| 3 | `-TopN (if(...){16}else{10})` | **Every Free RAM / Deep Reclaim threw** | ReclaimEngineBehaviorTest |
| 4 | `@($List[object])` in reclaim and trim plan | "Argument types do not match" | ReclaimEngineBehaviorTest, CleanupCoreBehaviorTest |
| 5 | `(Measure-Object ...).Sum` on empty input under StrictMode | Reclaim threw when nothing was trimmable | ReclaimEngineBehaviorTest |
| 6 | `Sort-Object WorkingSetMB,Priority -Ascending` | **Every adaptive trim plan threw** | ResearchStateRegressionTest, CleanupCoreBehaviorTest |
| 7 | First trim candidate capped at gap+128 MB | One large idle process never selectable near target | CleanupCoreBehaviorTest |
| 8 | `-f $name,$id,$r.Before/1MB,...` (comma binds tighter than `/`) | Log line threw after every successful trim, **aborting the pass** | CleanupCoreBehaviorTest |
| 9 | Reflection `GetProperty()` on a PSCustomObject | Reclaim Center verification always "Pending" | ReclaimEngineBehaviorTest |
| 10 | `'Research {0}/{1} • {2}' -f $index,$stage` | FormatException; progress text never updated | StaticTest |
| 11 | `Test-Path` on a full command line | Services/startup items with quoted args lost identity | ResearchPathNormalizationRegressionTest |
| 12 | `` `n `` inside single quotes (10 places) | Literal "`n" shown in dialogs | (AST scan) |
| 13 | `[uint32]` cast of a negative NTSTATUS | Real error code replaced by a cast exception | ReclaimEngineBehaviorTest |
| 14 | `Update-YumSnapshotMemory` wrote the wrong store | Cleanup loop read stale memory values | ControllerWorkerRegressionTest |

Root causes in common: PowerShell 5.1 pitfalls (statement-as-argument, `@()` on generic lists,
operator precedence, single-quote escapes, timer threading) and a test suite that grepped source
text instead of executing code, so none of these were caught.

## 3. Test suite

- Before: 12 of 37 passing. Most failures were bugs in the tests themselves (double-quoted regexes
  expanding `$vars`, an escaped `` `$PSScriptRoot ``, backslashes turned into newlines, a mid-file
  `exit` that skipped half a test). Several also asserted mutually contradictory designs.
- After: 40 of 40 passing via `Tests\Run-AllTests.ps1`. Contradictory assertions were aligned to
  the current design (automatic research during scan, live result merging).

## 4. Verified at runtime

- Main window loads in ~2.5 s (bootstrap 0.75 s). The 8.4 s gap in the old log was the time
  before monitoring was clicked; monitoring does not start automatically.
- Monitoring starts telemetry and the controller worker; on close, everything stops cleanly with
  no errors logged.
- Not verified: an elevated session with real standby-list purges. Run FREE RAM NOW and DEEP
  RAM RECLAIM once as administrator and check `YUMRAM.log`.

## 5. Known issues (remaining for beta)

1. ~~Reclaim runs on the UI thread.~~ **Fixed in 5.3.1**: it runs on the controller worker.
2. ~~Online research has no off switch.~~ **Decided in 5.3.3**: stays on by default (owner's choice),
   documented in the README, with a Settings → Privacy switch.
3. **Shared state is an OrderedDictionary used from 4 threads** (UI, two telemetry workers,
   controller). Value writes are low-risk, but a `Hashtable.Synchronized` runtime or a clear
   per-field ownership rule would remove the residual race risk.
4. **Most tests are still source-text contracts.** They protect against known regressions but
   cannot catch new logic bugs. Convert the Research and Intelligence ones to behavioral tests
   like the three added in 5.3.0.
5. **`UI\Dialogs.ps1` is ~2,000 dense lines.** Split it per window (Intelligence, Reclaim Center,
   Settings, Scan) before adding features.
6. **Interrupted-session service restore** restarts any service YUMRAM recorded as stopped, even
   if you stopped it yourself later. Record and compare the service's start time.
7. **Packaging:** ~~`config.json` shipped with personal settings~~ (fixed in 5.3.3: created on first
   run, git-ignored). Still open: scripts are unsigned and the launcher uses
   `-ExecutionPolicy Bypass` for its own process.
8. **No license chosen yet** (owner's decision); the README states all rights are reserved.

## 6. Road to beta

1. ~~Move manual reclaim off the UI thread~~ (done, 5.3.1).
2. ~~Decide the online research default~~ (done, 5.3.3).
3. Run an elevated soak test: monitoring on for a full gaming session with `YUMRAM.log` reviewed.
4. Convert the Research contract tests to behavioral tests (issue 4).
5. Split `Dialogs.ps1` (issue 5).
6. Choose a license before inviting outside contributions.
