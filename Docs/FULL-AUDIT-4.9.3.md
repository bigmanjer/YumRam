# YUMRAM 4.9.3 — Full Expert Regression Audit

## Baseline policy
4.8.5 Scanner-Argument-FIXED was treated as the immutable stable baseline. Changes were made only in a separate working tree.

## 4.9.2 failure addressed
The previous 4.9.2 build failed Windows PowerShell preflight in `UI/MainWindow.ps1` around the Mode SelectionChanged handler. The handler was rewritten into structured multi-line PowerShell 5.1 syntax, and startup initialization was expanded into explicit blocks.

## Research / placement
Automatic research remains enabled for uncertain records. The research chain can use executable metadata, Windows uninstall registry evidence, WinGet local catalog evidence, Authenticode evidence when available, and optional online search. The result is cached and converted into Placement, Action Lane, confidence, reason, and evidence-source metadata. Placement is classification metadata only; YUMRAM does not move or delete files merely because research returns a category.

## Regression fixes
- Startup fallback rows are inserted before the UI list refresh.
- System Inventory Low Risk filtering uses the scanner's actual `Safe to Manage` / `Candidate` risk values.
- Runtime version markers are synchronized to 4.9.3.
- Launch CMD/VBS files are BOM-free for reliable Windows launch behavior.
- PowerShell sources use UTF-8 BOM to satisfy the Windows-side static-test contract.
- No undefined YUMRAM helper calls remain in the scanned PowerShell sources.

## Validation available in this environment
- JSON parse: PASS
- XAML parse: PASS
- PowerShell delimiter/quote sanity: PASS
- PowerShell source encoding contract: PASS
- Launcher encoding contract: PASS
- Undefined YUMRAM helper scan: PASS
- Runtime version consistency: PASS

## Windows validation still required
This environment cannot execute Windows PowerShell 5.1/WPF. Run `Tests\Preflight.ps1`, `Tests\StaticTest.ps1`, and then the launcher on Windows before declaring the build production-stable.
