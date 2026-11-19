# YUMRAM 4.9.0 — Full Audit & Research Build Review

## Baseline protection
`YUMRAM 4.8.5 — Scanner-Argument-FIXED` was used as the read-only baseline. The 4.8.5 project archive in the ChatGPT Library was copied into a separate working tree before changes.

## Important limitation
This environment cannot launch Windows PowerShell 5.1/WPF, so the desktop application was not executed here. The review therefore combines source inspection, dependency checks, XAML/XML validation, JSON validation, structural PowerShell checks, and release-package inspection. The existing Windows `Preflight.ps1` and `StaticTest.ps1` remain in the package for final on-Windows runtime/parser verification.

## Defects found in the 4.8.5 baseline
1. **System Inventory Low Risk filter mismatch** — the UI searched for `Risk = Low`, while the scanner actually emitted `Safe to Manage`, `Candidate`, `Review`, `Protected`, and `Unknown`.
2. **Startup inventory data mismatch** — the System Inventory UI expected `User`/`Location`, but the startup records did not provide those properties; the result could display blank columns.
3. **Intelligence live state could be blank** — live scanner records lacked a guaranteed `StateText` value, despite the XAML exposing a State column.
4. **Intelligence database schema drift risk** — old saved records do not necessarily contain newly introduced research fields; strict-mode property access could fail during database merge.
5. **Cleanup preview fallback risk mismatch** — a fallback path looked for the obsolete `Low` risk value, so it could produce no candidates even when `Safe to Manage`/`Candidate` processes existed.
6. **Missing helper implementations** — the code referenced `Get-YumExecutableIdentity` and `Get-YumProcessCpuMap` without definitions in the shipped modules. Those paths could fail at runtime when reached.
7. **Process snapshot switch propagation bug** — `Get-YumProcessSnapshotRows` accepted `SkipParentMap` but did not pass it into the scanner call.
8. **Stale UI version string** — the main window still displayed `YUMRAM 4.8.4`.

## 4.9.0 fixes / improvements
- Added `Core\Research.ps1`.
- Added automatic identity research from Windows uninstall registry data.
- Added optional WinGet local-catalog research when `winget.exe` is available.
- Added optional online research through Bing Search RSS. Only item identity fields such as name/publisher/product are submitted; local filesystem paths are not sent.
- Added a local research cache with expiration.
- Added automatic startup inventory from Run/RunOnce registry locations and Startup folders.
- Added automatic placement lanes such as `Protected`, `Security`, `Drivers / Hardware`, `Games / Gaming`, `User Background Apps`, `Identified Applications`, `Startup Inventory`, `Review Queue`, and `Unknown / Quarantine for Review`.
- Added `ActionLane`, `Placement`, `ResearchReason`, `ResearchConfidence`, and evidence-source metadata.
- Added live/saved state handling.
- Added safe compatibility handling for old intelligence database records.
- Added missing executable identity/signature and process CPU-map helpers.
- Fixed `SkipParentMap` propagation.
- Fixed the System Inventory Low Risk filter.
- Fixed Startup UI bindings.
- Added Placement and Research columns to the Intelligence UI.
- Updated versioning to 4.9.0.

## Safety model
Research does not authorize destructive actions. Protected and Unknown items remain outside automatic management. The automatic placement feature is an inventory/classification decision; it does **not** automatically move files, uninstall software, or delete items.

## Validation performed
- XAML/XML parse validation: passed.
- JSON validation: passed.
- YUMRAM function-reference scan: no undefined `*-Yum*` helper calls remain.
- PowerShell structural brace checks on non-test source: passed.
- UTF-8 BOM check: passed for PowerShell files.
- ZIP creation and required-file presence: passed.
- Windows PowerShell 5.1 parser/runtime execution: not available in this Linux environment; run the included `Launch-YUMRAM.cmd`, `Tests\Preflight.ps1`, and `Tests\StaticTest.ps1` on Windows before treating 4.9.0 as production-stable.
