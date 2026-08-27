# YUMRAM v5.2.42 — Intelligence Research Hardening

- Scan remains manual.
- Unresolved live records automatically queue research after a successful scan when `AutoResearchAfterScan` is enabled.
- Run Research is usable for saved unresolved records as well as current live records.
- Clicking Run Research during an active run queues a fresh manual retry instead of launching a concurrent worker.
- Research progress is marshalled through the WPF Dispatcher and persisted incrementally.
- Research results are saved to the Intelligence database and research cache for reuse across launches.
- Online corroboration now applies source-quality weighting and verifies result pages before treating them as corroboration.
