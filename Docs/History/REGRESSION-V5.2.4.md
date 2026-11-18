# YUMRAM V5.2.4 Regression / Hardening

Controls: 4.9.4 stable rollback, V5.1.1 prior V5 control, V5.2.3 immediate candidate.

## Fixes
- Review is a true research state machine.
- Research errors are distinct from research-exhausted Unknown results.
- Online research verifies top result pages instead of trusting RSS metadata alone.
- Research cache keys include executable hash and signer thumbprint.
- Research history is persisted per item.
- Candidate promotion requires multi-source identity evidence.
- Online research remains asynchronous and bounded by the single worker + per-request timeout.
- Research completion no longer claims errors are exhausted.
