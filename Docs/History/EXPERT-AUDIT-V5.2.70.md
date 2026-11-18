# YUMRAM V5.2.70 Expert Audit — GUI Research Live Refresh

## Result
PASS — targeted Research-to-GUI synchronization repair.

## Root cause
`Merge-YumLiveResearchResults` in V5.2.69 was a deliberate no-op. The Research worker wrote immutable `research-live-results-<RunId>-<Completed>.json` checkpoints, but the Intelligence UI ignored them until worker completion. This made the Research backend progress while the GUI remained visually stale.

## Repair
- Restored safe incremental consumption of immutable Research snapshots.
- Merges updated records into the existing Intelligence UI data set while Research is running.
- Saves each checkpoint to the Intelligence database.
- Forces ListView, counters, and Research progress to refresh after each checkpoint.
- Leaves final `EndInvoke()` result application as the authoritative completion boundary.

## Regression boundary
Scanner was not edited. MainWindow was not edited. Research.ps1 was not edited by this release.

Core/Scanner.ps1 SHA-256: `fc7d8486cd446ed8d4b3fbef4e9279947331b93eda456cfd7ea5573633b1ae30`
Core/Research.ps1 SHA-256: `812d4e90e8a9c11517a4453dbabda166e41913b2c38899c49086ca4f3b0bd70a`
UI/MainWindow.ps1 SHA-256: `01f33f5533aa50d194df03ede58ff03007db61275f23d961d431792837530725`

## Qualification
- Static structural checks: PASS
- GUI snapshot contract test added: `Tests/ResearchGuiLiveRefreshRegressionTest.ps1`
- Windows PowerShell 5.1 execution remains required on the target machine.
