# YUMRAM v5.2.41 — Expert Audit Fixes

## Release focus
This maintenance build converts the v5.2.39 audit findings into enforceable release hygiene and removes stale/manual-mode contradictions.

## Fixed
- Fixed duplicate-comma syntax defects in Intelligence regression tests.
- Renamed the Intelligence research action from `ResearchSelected` to `RunResearch`; it researches the current unresolved live queue rather than a selected row.
- Removed the scanner's implicit research execution path. System scans are inventory-only; manual research owns the research API.
- Reconciled Intelligence documentation with manual-only behavior.
- Updated the package manifest and smoke-test version to 5.2.41.
- Replaced the stale hard-coded main-window V5.1.0 footer with a runtime-bound VERSION display.
- Improved footer/telemetry contrast.
- Added explicit target stop-reason telemetry and surface it in the main footer when a cleanup completes below target.
- Used the configured no-gain controller backoff rather than a hard-coded adaptive sleep.

## Preserved
- Adaptive smallest-first cleanup.
- Target-driven legacy fallback.
- Process/game/protection safeguards.
- Manual-only Intelligence Scan + Run Research.
- Sequential research execution.

## Validation boundary
The source package was statically validated for UTF-8 BOM encoding, JSON/XAML parsing, balanced delimiters, UI/control-reference consistency, and stale-version cleanup. Windows PowerShell 5.1 runtime parsing/execution still requires validation on a Windows host.
