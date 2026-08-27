# YUMRAM V5.2.69 Expert Audit

## Incident
V5.2.68 was reported to make scanning unusable. Static comparison showed `Core/Scanner.ps1` and `Core/Intelligence.ps1` were unchanged from V5.2.66, so the regression boundary was traced into the Research collection handling invoked around scanned records.

## Root cause
V5.2.68 converted three Research evidence inventories from PowerShell array-subexpression enumeration to direct `.ToArray()` calls. That is not collection-agnostic: normal PowerShell arrays do not expose the same `ToArray()` method contract as `System.Collections.Generic.List[T]`.

The earlier PS5.1 fix also had to avoid `@($genericList)`, because Windows PowerShell 5.1 can throw `Argument types do not match` for that conversion pattern.

## V5.2.69 correction
Research evidence inventories now use direct `foreach` enumeration. This works for normal arrays and generic lists without invoking either unsafe conversion pattern.

The existing Research schema hardening and canonical `Config.OnlineResearchProvider` injection from V5.2.67 remain intact.

## No-regression boundary
- `Core/Scanner.ps1`: unchanged from V5.2.66.
- `Core/Intelligence.ps1`: unchanged from V5.2.66.
- Launcher/UI/cleanup/telemetry files: unchanged from V5.2.68.
- Changes are limited to Research enumeration, Research metadata/tests, and release documentation.

## Static checks
- Research brace/parenthesis balance: PASS.
- Scanner brace/parenthesis balance: PASS.
- No remaining `@($script.YumResearch*...)` generic-inventory patterns: PASS.
- No direct `.ToArray()` calls remain on the three problematic Research inventories: PASS.
- Version metadata synchronized to 5.2.69: PASS.

## Runtime limitation
Windows PowerShell 5.1 is not installed in the build environment, so Windows runtime qualification must still be executed on the target machine.
