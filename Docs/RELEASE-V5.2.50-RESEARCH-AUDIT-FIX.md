# YUMRAM v5.2.50 — Research Audit Fix

## Expert audit findings
- Run Research could queue Candidate/Unknown records but the worker only forced research for Review-like records. This made the button appear to run while silently skipping eligible records.
- Online research for Review items bypassed the configured per-run web research cap.
- Research engine version metadata was still 5.2.49 in the v5.2.50 package, causing unnecessary cache invalidation.
- Intelligence UI contained stale automatic-research wording.

## Fixes
- Every non-manual unresolved record without a valid terminal cache now enters the research pipeline.
- Web research respects ResearchMaxOnlineItemsPerScan for all items.
- Engine/version metadata is aligned to 5.2.50.
- UI wording is manual-first and consistent.
- Stable launchers remain unchanged.
