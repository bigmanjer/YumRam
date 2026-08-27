# YUMRAM V5.2.5 — Research Cache Fix

## Purpose
Prevent completed research from restarting on every scan.

## Behavior
- A valid, current cached result hydrates the newly scanned record before the research decision is made.
- Scanner defaults such as Risk=Review no longer force re-research when a valid completed cache entry exists.
- Startup/other conservative Action Lanes do not invalidate a completed research result.
- Research Error, expired cache, changed research engine version, or changed identity/hash/signature can trigger a new research pass.
- Cached items are shown as `Cached` in research status and are not counted as newly researched.
- ResearchComplete is derived from the current valid cache state rather than the scanner's pre-cache state.
