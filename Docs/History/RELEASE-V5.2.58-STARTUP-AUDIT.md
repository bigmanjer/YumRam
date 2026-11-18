# YUMRAM v5.2.58 — Startup Audit / Diagnostic Hardening

## Findings from v5.2.57

1. The release launcher copied `%TEMP%\\YUMRAM-startup.log` over the application's `YUMRAM.log` after PowerShell exited. This could erase the real application/Bootstrap exception and made startup failures impossible to diagnose from the displayed log.
2. Bootstrap loaded a long module chain without logging the individual module being sourced, making a module-level parse/runtime failure hard to isolate.
3. The configuration migration defaulted `AutoResearchAfterScan` to `true`, contradicting the manual-first Intelligence contract.
4. The confirmed working launcher contract must not be changed during feature work.

## v5.2.58 changes

- Preserves the application-owned `YUMRAM.log`.
- Writes launcher diagnostics to `YUMRAM-launcher.log` and `%TEMP%\\YUMRAM-startup.log`.
- Writes earliest application entry to `%TEMP%\\YUMRAM-app-startup.log`.
- Logs each Bootstrap module before loading it.
- Sets `AutoResearchAfterScan=false` in defaults and migration.
- No changes to cleanup logic, research worker logic, service stopping, or UI behavior in this build.

This build is an instrumentation/contract-hardening release. It does not claim Windows runtime certification in a non-Windows environment.
