# YUMRAM v5.2.67 — Research PowerShell 5.1 Qualification Fix

## Expert audit findings
- Research progress snapshots accessed optional `ResearchRunDisposition`, `ResearchRunResolved`, and `ResearchRunOnline` properties directly under `Set-StrictMode`, so a record could fail before its final schema fields were attached.
- The Research worker had no canonical `Config.OnlineResearchProvider` injection seam, preventing deterministic online-stage qualification without replacing the web transport.
- `Get-YumResearchFileEvidence` was defined twice; the duplicate did not change the final function body but was removed to keep one authoritative Research implementation.
- Several regression tests still asserted 5.2.62 after the package had already advanced to 5.2.66.

## Fixes
- Added `Ensure-YumResearchRecordSchema` and normalize every queued record before Research status/progress access.
- Made live research progress counters property-safe for legacy/minimal records.
- Added canonical `Config.OnlineResearchProvider` support with the previous top-level provider as a compatibility fallback.
- Preserved the existing real web adapter when no provider is injected.
- Removed the duplicate file-evidence function.
- Synchronized release metadata/tests to 5.2.67.

## No-regression boundary
Scanner, cleanup, launchers, telemetry, and unrelated UI behavior were not redesigned. Changes are limited to Research execution/schema robustness and Research regression contracts.
