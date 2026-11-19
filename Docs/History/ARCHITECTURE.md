# YUMRAM 4.5.9 Architecture

```text
Windows APIs / Counters
        |
        v
Telemetry timer (background data collection)
        |
        v
Immutable-style system snapshot
        |
   +----+---------+
   |              |
   v              v
WPF Dispatcher   Background controller
   |              |
   |              +--> pressure decision
   |              +--> candidate scoring
   |              +--> trim / optional cleanup
   |              +--> before/after measurement
   v
Specialized purple dashboard
```

### UI rules

- The UI thread owns graph history and WPF controls.
- Background telemetry never mutates WPF objects.
- Cleanup requests are queued so button clicks do not perform the full cleanup synchronously.
- Graph polylines are reusable objects.

### Cleanup rules

- Never intentionally terminate a process.
- Foreground process, active game, RealTime process, configured protected process, and YUMRAM itself are excluded.
- `K32EmptyWorkingSet` is used for working-set trimming.
- Optional background applications are cooperative only.
- Optional services require explicit configuration and must pass dependency/start-mode/core-service checks.

## 4.5.9 UI/Controller improvements
The UI now maintains independent RAM, CPU, and GPU 3D graph series. Target rendering is independent of snapshot-version changes. Preview cleanup bypasses the request queue and calls the non-mutating core directly. Settings/About/Top Processes use dedicated WPF dialogs.


## 4.5.9 regression-control architecture

Telemetry is isolated from cleanup controller work. The telemetry timer samples memory/CPU and schedules slower GPU/game samples. The controller timer evaluates pressure and requests cleanup separately. The WPF UI consumes immutable-ish snapshot replacements and owns graph point history/rendering.

The scanner is on-demand so a full process/service/package inventory cannot stall live dashboard telemetry.


## 4.6.1 Intelligence / Target Architecture

The system scan is the source of truth for automatic organization. Scanned items are classified into protected, active game/game launcher, background app, service, safe candidate, review, or unknown categories. A local intelligence database (`intelligence-db.json`) persists classification evidence so repeated scans can reuse known identities and only rediscover changed or new items. Unknown items are never managed automatically.

Safe, Balanced, and Aggressive are target-driven memory modes. Each mode changes candidate breadth and the number of safe follow-up passes, while the configured Available RAM Target is the hard stopping goal. The controller continues until the target is reached or safe reclaimable candidates no longer produce measurable available-memory gain.
