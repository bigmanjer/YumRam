# YUMRAM 4.6.7 — Full Audit / Fix Record

## Scope

Full-program review of startup/configuration, memory target behavior, Safe/Balanced/Aggressive modes, process CPU scoring, scanning, Smart Intelligence organization/persistence, services/apps classification, UI structure, PowerShell 5.1 compatibility, and release packaging.

## Fixed in 4.6.4

1. Version consistency: VERSION, default configuration, runtime migration, dashboard footer, and release metadata use 4.6.4.
2. Canonical RAM target: `MinimumAvailableGB` is the authoritative target. `CleanupTargetAvailableGB` is maintained only as a compatibility alias.
3. Settings Reset Defaults now matches the shipped Safe/Balanced/Aggressive process-per-pass defaults: 3 / 6 / 10.
4. Manual Reclaim now runs the same repeated target-seeking cleanup loop as automatic pressure control instead of performing a single pass.
5. Cleanup reports measured Available RAM separately from working-set reduction and exposes target shortfall when the OS cannot reach the configured target with safe candidates.
6. Process CPU scoring now uses a bulk Windows formatted performance sample, normalized across processor count, with a short cache; lifetime-average CPU is only a fallback.
7. Service Intelligence records now include confidence/publisher metadata and correct service confidence values.
8. Installed AppX classification now distinguishes Games, Apps, and Protected framework packages instead of marking every package identically.
9. Smart Intelligence now displays Saved Records alongside the seven live classification categories, using a 4x2 card layout for better readability.
10. Intelligence Scan remains the single scan concept. Protected, Games, Apps, Services, Safe to Manage, Review, and Unknown are views of the same scan results and persisted local catalog.
11. Stable-build service termination remains disabled.
12. Static tests now check version consistency, canonical target synchronization, mode defaults, legacy scan-setting removal, and the service-termination gate.

## Research basis

Windows working sets are resident pageable pages and can be trimmed with documented Windows APIs, but Microsoft also notes that working-set size is not a complete measure of system-wide memory use. YUMRAM therefore uses **Available RAM** as the target-success metric and reports working-set reduction separately.

Microsoft documents that per-process `% Processor Time` is calculated from performance-counter samples and can exceed 100% on multi-core machines. YUMRAM uses bulk formatted performance data and normalizes it.

Microsoft's service documentation confirms that stopping a service can also stop dependent services, so YUMRAM checks dependents and keeps service termination disabled in this stabilization release.

Bruce Dawson's independent Random ASCII investigation demonstrated that `EmptyWorkingSet` can drastically reduce a process working set and that it can refill when the process touches its memory again. That supports treating working-set trimming as pressure relief, not a permanent or exact RAM-release guarantee.

## Release verification

Post-package static audit of the exact delivered ZIP:

- PowerShell files: 19
- XAML files: 10
- JSON configuration: valid
- PowerShell UTF-8 BOM: passed
- `ContainsKey()` compatibility check: passed
- XAML XML parsing: passed
- Canonical target synchronization: passed
- Safe/Balanced/Aggressive default consistency: passed
- Intelligence controls / Services / Saved Records: passed
- Scanner `SkipParentMap` contract: passed
- Cleanup target-seeking path: passed
- ZIP integrity: passed

## Runtime limitation

The build environment used for this audit is Linux and cannot execute Windows PowerShell 5.1/WPF. Windows preflight/launch remains the final runtime validation step.
