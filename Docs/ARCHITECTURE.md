# YUMRAM architecture (5.3.x)

## Threads

```text
                 shared state: $script:Yum (ordered dictionary, guarded by Monitor locks)
                                       |
 +------------------+   +--------------+--------------+   +----------------------------+
 | UI thread (WPF)  |   | Telemetry Core runspace     |   | Controller worker runspace |
 | DispatcherTimer  |   | memory + CPU every 0.5 s    |   | wakes every 1 s or on      |
 | 0.25 s: read     |<--| Telemetry Aux runspace      |   | request (AutoResetEvent):  |
 | snapshot, draw   |   | GPU (5 s), game/foreground  |   | - manual reclaim requests  |
 | graph, show      |   | (2 s); publishes only on    |   | - queued cleanup requests  |
 | results          |   | change                      |   | - automatic maintenance    |
 +------------------+   +-----------------------------+   | - game state, estimates    |
        |  button clicks only queue work                  +----------------------------+
        +------------------------------------------------>  (Request-YumMemoryReclaim,
                                                              Request-YumCleanup)
 Research worker runspace (Intelligence): researches unresolved items, writes a live checkpoint.
```

Rules:

- Only the UI thread touches WPF objects. Workers publish results (`CleanupResult`, `LastReclaim`,
  `ReachableEstimate`) and bump a version counter; the UI timer renders when a version changes.
- Never use `System.Timers.Timer` with a scriptblock handler: on Windows PowerShell 5.1 it fires
  on a thread with no runspace and never runs. Use a runspace worker or a `DispatcherTimer`.
- Anything that can take more than ~50 ms (process enumeration, signature checks, trims, settle
  delays) runs on a worker, never on the UI thread.

## Memory engine

| Piece | File | Purpose |
|---|---|---|
| Native calls | `Core/Native.ps1` | `K32EmptyWorkingSet`, `GlobalMemoryStatusEx`, `GetPerformanceInfo`, `NtSetSystemInformation` memory lists, privilege adjust |
| Safety policy | `Core/Safety.ps1` | Protected-process test and per-mode candidate filter/scoring |
| Automatic cleanup | `Core/Cleanup.ps1` | Pressure decision, trim plan, adaptive passes, fallback, back-off |
| Manual reclaim | `Core/MemoryReclaim.ps1` | Free RAM / Deep reclaim, settle + verification, learning |
| Controller | `Core/Controller.ps1` | Background worker loop and request queue |

### Measurement model

Trimming moves pages out of a working set. Clean/shared pages become Standby (counted as Available)
immediately; private pages are compressed or written out, so only part of a trim becomes Available,
and only after ~1-2 s. Therefore:

1. Every pass waits `CleanupSettleMilliseconds` / `ReclaimSettleMilliseconds` (1.5 s) before measuring.
2. `Update-YumGlobalRetention` keeps an EWMA of (Available gain / working set trimmed) for passes of
   at least 200 MB, persisted in `reclaim-learning.json` (bounded 15-90%, default 40%).
3. `Get-YumTrimPlan` divides the Available gap by that retention to size a pass.
4. `Get-YumReachableEstimate` = Available + (eligible working sets x retention) drives the
   `reachable ≈ X GB` display and the **[OUT OF REACH]** state.
5. Per-process learning records how much of each trim stayed trimmed after settling, so processes
   that page straight back in are deprioritized; each PID has a 60 s cooldown.

## Intelligence and research

`Core/Intelligence.ps1` builds an identity for each executable (version info + Authenticode,
cached per path) and classifies it (Protected / Safe to Manage / Candidate / Review / Unknown).
`Core/Research.ps1` resolves Review/Unknown items from local evidence (installed software, services,
Store packages, parent folder) and, if enabled, online search. Results persist in
`intelligence-db.json` and `research-*.json`.

## Configuration

`Config/default-config.json` holds shipped defaults. On launch, `Initialize-YumConfig` merges the
user's `config.json` over it (`Merge-YumHashtable`, which takes `IDictionary` so the ordered config is
modified in place), migrates values still at old defaults, and saves. `VERSION` is the single
source of the release number.
