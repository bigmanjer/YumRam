YUMRAM 4.6.7 — FULL REGRESSION AUDIT

Baseline: YUMRAM 4.5.9-final-improved
Scope: dashboard geometry, side navigation, Smart Intelligence, Scan, Quick Control, target control, cleanup/preview, XAML/JSON/static PowerShell checks.

FIXED
- Restored the 4.5.9 dashboard geometry so Available/Memory/CPU/GPU/Game cards and the Graph canvas remain present.
- Restored the right-hand Quick Controls column and added the organized Smart Intelligence/System/Gaming expanders there.
- Preserved Safe/Balanced/Aggressive mode controls.
- Preserved visible Available RAM Target + Apply control.
- Preserved Scan -> Show-YumSystemScan event path.
- Preserved Smart Intelligence -> Show-YumIntelligence event path.
- Preserved Protected/Games/Background Apps/Services/System handlers.
- Added Quick Monitor status/telemetry fields without changing the monitoring engine.
- Cleanup target logic uses MinimumAvailableGB consistently as the actual stop target.
- Smart Intelligence scan uses the established process scanner path and skips the expensive parent-process map for the live intelligence refresh.
- Default optional service cleanup remains disabled.

STATIC VALIDATION
- All XAML documents parse successfully.
- MainWindow required x:Name references: 0 missing.
- Main dashboard contains Graph and TargetBar controls.
- Config/default-config.json parses successfully.
- Custom function-reference scan found no unresolved Yum*/Show-Yum* references.
- PowerShell structural balance check found no unbalanced braces/brackets/parentheses in the 19 PowerShell files.
- ZIP/package file structure is intact.

KNOWN LIMITATION
- Windows PowerShell 5.1/WPF cannot be executed in this Linux build environment, so Windows runtime/preflight remains the authoritative final launch test.
- Authenticode verification should remain limited to deliberate scan/preview operations rather than the continuous telemetry loop.

REGRESSION POLICY
The Smart Intelligence logic is additive to the established scanner. The original dashboard and Scan command path are treated as protected regression surfaces for future changes.
