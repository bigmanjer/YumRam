# YUMRAM V5.2.72 — Regression Audit Hardened

V5.2.72 preserves the V5.2.71 live Research monitor while hardening two no-regression boundaries: PS 5.1 collection enumeration and run-owned shared checkpoint cleanup. Scanner code is unchanged.


## Release-integrity repair

Post-audit release metadata was synchronized to V5.2.72 across VERSION, Config/default-config.json, and current-release regression contracts. Docs/MANIFEST.txt was regenerated from the repaired package contents so all recorded SHA-256 values correspond to the shipped files. No functional production source outside the pre-existing V5.2.72 changes was modified.

## Final Research classification hardening

V5.2.72 also hardens post-research promotion: a scanner-provided initial `Risk=Review` value no longer blocks a trusted application/background classification when Research has multiple independent identity signals and confidence >=85. This prevents signed/catalogued applications such as Discord/Chrome from being unnecessarily quarantined solely because they entered Research from the scanner in Review.
