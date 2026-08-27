# YUMRAM V5.2.4 Regression Ledger

## Controls
- 4.9.4: stable rollback/control.
- V5.1.1: prior V5 control.
- V5.2.2: immediate failed candidate with process-scanner `$PID` regression and Review-resolution state gaps.

## Fixed
- Renamed `Test-YumScannerProtectedProcess` parameter `$Pid` to `$ProcessId` to avoid PowerShell automatic `$PID` collision.
- Canonical runtime version now comes from `VERSION`; config/research engine/tests validate against it.
- Static/smoke tests updated to V5.2.4 and no longer hard-code older release versions.
- Review state is triggered by Risk, Action Lane, unresolved Placement, or incomplete research—not only `Review Queue` Placement.
- Cached Review/Unknown results are never considered fresh/resolved cache hits.
- Every unresolved Review item receives online corroboration when enabled, independent of the ordinary online cap.
- A completed research pass only produces `Unknown` when the final Placement remains unresolved; legitimate conservative categories such as Startup Inventory remain intact.
- Intelligence UI polls `research-status.json` and displays live `Queued / Researching Local / Researching Online / Organized / Unknown / Error` status.
- Safe optimization remains independent of Monitoring through the one-shot controller path inherited from the hardened V5 branch.

## Safety
Manual organization remains authoritative. Automatic research cannot overwrite a manual override. Research confidence gates Candidate promotion.
