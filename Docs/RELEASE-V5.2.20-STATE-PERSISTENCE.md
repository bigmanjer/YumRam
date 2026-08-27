# YUMRAM V5.2.21 — Intelligence State & Persistence Hardened

This release hardens the Review → Research → Organize pipeline.

- Fresh research results always take precedence over stale cache state.
- Research/Cached/Resolved/Error counters are separated.
- Only current live records that actually require research enter the worker queue.
- Persisted research state is restored onto matching live records before queue selection.
- Live research snapshots carry incremental counters so the Intelligence header can update during research.
- Research engine version derives from canonical VERSION/configuration rather than a hard-coded release literal.
- Empty-array research APIs remain safe under Windows PowerShell 5.1.
