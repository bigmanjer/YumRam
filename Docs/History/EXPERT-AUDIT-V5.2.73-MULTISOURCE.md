# YUMRAM V5.2.74 — Expert Multi-Source Program Audit

## Controls
- Stable control: V5.2.72
- Proven rollback/control: V4.9.4
- Candidate: V5.2.74

## External research basis
1. Microsoft PowerShell 5.1 scope documentation confirms event/script blocks execute in child scopes and variable visibility must be handled deliberately. This directly supports the prior `$State` context-menu failure analysis.
2. PowerShell GitHub issue #27558 documents `@($list)` throwing `Argument types do not match` with `System.Collections.Generic.List[object]` in Windows PowerShell 5.1. The candidate therefore avoids unsafe generic-list array-subexpression patterns.
3. PowerShell GitHub issue #4257 documents long-standing collection/array-subexpression quirks around `New-Object` collections. Collection-agnostic enumeration remains the preferred production pattern.
4. Microsoft WinGet documentation confirms `winget list --name ... --exact` is an installed-application lookup and that exact matching can be used for identity corroboration.
5. Microsoft Authenticode documentation confirms `Get-AuthenticodeSignature` provides signature status and signer information for Windows files. Valid signatures are therefore treated as one identity signal, not as sole proof.
6. Microsoft FileShare documentation confirms `ReadWrite` and `Delete` sharing are required when one process reads a file while another may replace/delete it. This supports the shared live-checkpoint file contract.

## Defects found and fixed
- Online research no-match was conflated with operational online failure. Fixed by distinguishing an empty/no-match result from a returned exception/error.
- Strong local application identity could still be quarantined because the pre-research Review flag and confidence gate outweighed multiple independent identity signals. Added a two-anchor promotion rule using independent signature/publisher, WinGet, registry, AppX, and file metadata evidence.
- Research history could record the same terminal Unknown outcome twice for one processing pass. Removed the duplicate intermediate terminal history write; the final-state block is authoritative.
- UI status polling could overwrite a terminal result with transient `Researching`. Added a terminal-state regression guard.
- Live checkpoint merge could replace an already-terminal record with an incomplete/transient update. Added an existing-terminal versus updated-transient guard.
- Worker-wide failure previously returned incomplete records. Worker failure now terminally quarantines every affected record as `Research Error` with `ResearchComplete=true`.
- Active release test/version metadata was stale in the candidate source tree. Synchronized to 5.2.74.
- Config and Cleanup contained collection conversions matching the PowerShell 5.1 failure class. Replaced `@($list)` / `@($selected)` with explicit `.ToArray()` on the known ArrayList/generic-list values.

## No-regression boundary
The candidate intentionally does not modify the functional implementation of:
- Core/Scanner.ps1
- Core/Cleanup.ps1
- Core/Native.ps1
- Core/Games.ps1
- Core/Safety.ps1
- Core/Telemetry.ps1
- Core/TelemetryWorker.ps1
- App/YUMRAM.ps1
- App/Bootstrap.ps1
- UI/MainWindow.ps1

Functional changes are limited to Core/Research.ps1 and the Research live-state behavior in UI/Dialogs.ps1, plus tests/documentation/version metadata.

## Static qualification
- PowerShell delimiter balance: required and checked in package audit.
- XAML XML parsing: required and checked in package audit.
- JSON parsing: required and checked in package audit.
- Active current-version references: required and checked in package audit.
- Manifest SHA-256 self-consistency: required and checked in package audit.
- Windows PowerShell 5.1 runtime qualification: still required on the target machine.

## Expected Research contract
Every automatic record must end in exactly one terminal outcome:
- Organized
- Unknown / Quarantine for Review
- Research Error (diagnostic) with terminal quarantine

A completed automatic record must never regress to Researching or remain in Review Queue.
