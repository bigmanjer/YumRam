# v5.2.62 — Intelligence + Memory Cleanup Stabilization

Bug-fix and performance stabilization release. No new feature expansion.

- Canonical release metadata synchronized to 5.2.62.
- Manual organization JSON loading corrected and cached.
- Intelligence view refresh now skips unchanged data using a revision counter.
- Manual organization saves and resets now expose persistence failures and roll back database changes when needed.
- Cleanup manual identity now includes file hash and signer thumbprint.
- Research reset clears stale research metadata.
- Adaptive cleanup constrains trim overshoot near the target.
- Legacy fallback has a session-wide working-set reduction cap.
- Existing game/foreground protection and smallest-first cleanup strategy preserved.
- Regression tests and PowerShell BOM requirements synchronized.

Runtime hotfixes discovered from Windows 11 v5.2.61 startup testing:

- Removed the PowerShell generic-List `@($sources)` coercion that caused repeated `Argument types do not match` failures in the Intelligence refresh loop.
- Made the research result `Errors` envelope optional/property-safe so successful worker results without an Errors property cannot fail UI application.
- Added regression guards for both PowerShell runtime hazards.
