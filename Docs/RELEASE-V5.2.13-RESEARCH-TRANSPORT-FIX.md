# YUMRAM V5.2.13 — Research Transport Fix

## Purpose
Fix the V5.2.12 failure where the UI prepared a non-empty research queue but the secondary PowerShell runspace received an empty/invalid `Records` parameter.

## Engineering changes
- Research queues cross the runspace boundary as JSON instead of a live `object[]` argument.
- Worker config also crosses as JSON for deterministic deserialization.
- Worker logs the received record count and run ID.
- Worker returns one JSON result document; the UI deserializes it once.
- Empty queues remain a valid no-op.
- Existing canonical Intelligence Record Schema normalization remains mandatory before UI updates/persistence.
- Added static regression checks for JSON transport and worker diagnostics.

## Regression controls
- Current stable baseline: V5.2.4
- Immediate failed candidate: V5.2.12
- New candidate: V5.2.13
