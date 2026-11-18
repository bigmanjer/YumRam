# YUMRAM V5.2.36 — Research PowerShell 5.1 Scalar Hardening

This candidate is based directly on V5.2.35. No scanner, UI, cleanup-policy, or research decision logic was intentionally redesigned.

## Fixes

- Preserves the V5.2.35 fixes for `RegistryEvidence`, `identitySignals`, and online-search `terms` scalar collapse.
- Hardens the cleanup caller by forcing `Get-YumTrimPlan` output into array context before `.Count` is evaluated. A single selected process can no longer cause a PowerShell 5.1 `PropertyNotFoundException`.
- Refreshes active package metadata and smoke-test labels to V5.2.36. Historical release documents remain historical.

## Regression intent

The candidate must remain safe for 0, 1, and multiple results wherever `.Count` is used on pipeline/function output, while preserving V5.2.4 as the rollback/control baseline.
