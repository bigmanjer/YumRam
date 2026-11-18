# YUMRAM V5.2.72 Expert Regression Audit

## Scope
V5.2.71 Intelligence live Research monitor, compared against V5.2.69. Stable boundary remains V5.2.4.

## Findings
- Scanner.ps1 is unchanged from V5.2.69.
- MainWindow.ps1, Intelligence.ps1, App/YUMRAM.ps1 and Bootstrap.ps1 are unchanged from V5.2.69.
- Research.ps1 changes only the live checkpoint transport from per-item files to one atomic `research-live-results.json`.
- Dialogs.ps1 implements live Research attachment/polling and current-item visibility.
- The live checkpoint cleanup was hardened to delete only a checkpoint whose embedded RunId matches the owner being cleaned up.
- The newly added status enumeration avoids wrapping a potentially generic PS5.1 List[T] in `@(...)`.
- The existing GUI regression test was updated so it validates the shared checkpoint contract instead of the retired per-item filename contract.

## Static checks
- Brace balance: Core/Research.ps1 743/743; UI/Dialogs.ps1 1383/1383.
- No legacy per-item live-checkpoint pattern remains in executable product code.
- No changes detected in Scanner.ps1 or UI/MainWindow.ps1 relative to V5.2.69.

## Runtime limitation
Windows PowerShell 5.1 is not installed in this Linux analysis environment, so actual WPF/runtime qualification must still be run on Windows.
