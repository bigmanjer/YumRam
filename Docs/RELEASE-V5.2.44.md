# YUMRAM V5.2.44

## Expert Audit Fixes

- Automatic monitoring now treats any below-target Available RAM as a cleanup condition; hysteresis no longer suppresses cleanup while the target is unmet.
- Cleanup Preview now exposes action type, time, planned/actual state, and before/after/reduced memory fields.
- Actual cleanup results use the same action record schema as preview, making the UI activity model consistent.
- Intelligence documentation now matches the scan -> automatic research -> persistent knowledge flow.
- Research engine version is bound to the canonical VERSION.
- Online research source trust now recognizes authoritative government, education, major vendor, Microsoft, GitHub, and established software-publisher domains without treating every generic .com as equally trustworthy.
- Release metadata and smoke-test version strings are synchronized.
