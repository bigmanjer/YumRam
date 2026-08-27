# YUMRAM 4.6.7 — Full Audit / Fix Record

## Primary fixes

- Fixed PowerShell `$PID` variable collisions in foreground-process detection, process CPU-map collection, and Intelligence process classification. PowerShell variable names are case-insensitive, so `$pid` aliases the automatic `$PID` variable and can break execution.
- Intelligence Scan now has a resilient process-scan fallback when the formatted performance/process snapshot is unavailable.
- The main System Inventory Scan also has a resilient process fallback.
- Intelligence is a singleton window: Protected, Games, Apps, and Services reuse the same Intelligence catalog and switch its filter/title instead of opening duplicate windows.
- Saved Intelligence classifications are shown immediately while the current scan runs.
- RAM target remains a single user-controlled `MinimumAvailableGB` value; the compatibility alias is synchronized.
- Safe/Balanced/Aggressive are differentiated by candidate thresholds, candidate counts, optional app scope, and follow-up target-seeking passes.
- Manual/automatic cleanup continues to use Available RAM as the success metric and reports working-set reduction separately.
- Automatic service cleanup remains disabled until the later termination phase.
- Release metadata is synchronized to 4.6.7.

## Research basis

Microsoft documents that a process working set is only the currently resident pageable pages of that process and is not equivalent to total system memory availability. Microsoft also documents `EmptyWorkingSet` as removing pages from a process working set, not as a guarantee of an equivalent system-wide Available-RAM increase.

Microsoft's performance-counter guidance states that process CPU percentage counters are rate measurements requiring two samples and that per-process values can exceed 100% on multi-processor systems. YUMRAM therefore uses sampled process CPU data when available and treats fallback CPU as unknown/neutral rather than inventing precision.

Microsoft documents that Windows services have dependencies and that stopping a service can affect dependent services. YUMRAM therefore keeps service termination disabled in the stable build and classifies services conservatively.

Microsoft's AppX documentation distinguishes framework packages and installed application packages. YUMRAM uses that metadata to separate protected framework packages from ordinary apps and gaming indicators.

Independent performance research by Bruce Dawson also demonstrates that EmptyWorkingSet can cause a working set to refill when pages are touched again, and that aggressive working-set manipulation can have significant performance costs. YUMRAM therefore treats working-set reduction as an observed effect, not a guaranteed amount of Available RAM reclaimed.

## Validation performed

- ZIP extracted after packaging.
- 19 PowerShell files inspected.
- All PowerShell files retain UTF-8 BOM encoding required by the project.
- 10 XAML files parse as XML.
- Config JSON parses.
- No `$pid =` assignments remain in project scripts.
- No `ContainsKey()` calls remain.
- Intelligence singleton launch state is present.
- Protected/Games/Apps/Services routes are present.
- Saved Intelligence catalog preload is present.
- Scan fallback is present.
- `SkipParentMap` scanner contract is present.
- Service termination is gated and disabled by default.
- Package integrity verified after final ZIP creation.

## Runtime limitation

The build environment used for this audit does not provide Windows PowerShell 5.1/WPF execution, so the final runtime authority remains the Windows preflight and application log on the target machine.
