# YUMRAM 5.2.82 — Expert Engineering Audit

## Scope

Audited and modified from YUMRAM 5.2.80 ReclaimRestored / AutoResearch baseline. Focus areas: reclaim effectiveness, research-state architecture, UI responsiveness, Windows PowerShell 5.1 compatibility, release consistency, and regression protection.

## Engineering changes

- Removed the expensive RAM reclaim preview scan from the Reclaim Center. Opening the Center no longer enumerates processes solely to predict cleanup.
- Kept the three requested user actions: **💜 FREE RAM NOW**, **💜 DEEP RAM RECLAIM**, and **🧠 RAM RECLAIM CENTER**.
- Made research an internal analysis phase rather than a competing primary UI mode; the existing research status pipeline remains available for live progress.
- Added an internal `ResearchState` runtime object and synchronized it from the research status writer.
- Added per-process reclaim learning with persisted EWMA effectiveness. Candidate scoring can now reward historically useful reclaim targets and deprioritize targets whose trims repeatedly return little/no useful available RAM.
- Added per-process system Available-RAM measurement around each successful trim.
- Corrected Deep Reclaim so the system/user working-set pass is governed by `ReclaimSystemWorkingSet`, not `ReclaimModifiedPageList`.
- Corrected process-action accounting so failed trim attempts do not consume the successful-action quota.
- Added version-aligned regression coverage and a dedicated reclaim expert audit test.
- Removed `.bak` files from the release package.
- Updated the release/configuration version to 5.2.82 and enabled automatic research defaults explicitly.

## Why the verification model is correct

Windows defines a process working set as pages resident in physical memory at a point in time; pages can be removed from a working set by `EmptyWorkingSet`, but that does not mean the same number of bytes becomes immediately reusable system RAM. Microsoft identifies `ullAvailPhys` as physical memory that can be immediately reused without first writing it to disk. Therefore YUMRAM treats Working-Set reduction as a secondary measurement and system Available RAM gain as the primary useful-reclaim signal.

## Final audit checks

- ZIP integrity: PASS
- Required product files: PASS
- Canonical VERSION/config consistency: PASS
- Requested reclaim UI controls: PASS
- Preview scan dependency removed: PASS
- Reclaim learning code present and wired: PASS
- Per-action Available-RAM verification: PASS
- Deep system-working-set flag corrected: PASS
- Failed-action quota bug corrected: PASS
- Historical backup files removed: PASS
- Windows PowerShell 5.1 parser/runtime execution: NOT RUN in this Linux environment
- WPF runtime execution: NOT RUN in this Linux environment

## Final validation

**26/26 source/package audit checks passed.**

The final audit rechecked version consistency, preview removal, requested UI controls, reclaim learning, per-action verification, Deep Reclaim routing, failed-action accounting, ResearchState, backup-file removal, JSON/XAML parsing, and ZIP integrity.

## Release decision

**CONDITIONALLY READY FOR WINDOWS RUNTIME TESTING.**

The source-level audit is satisfied. The remaining qualification is platform execution on Windows PowerShell 5.1/WPF. No claim is made that the application has been fully runtime-tested here.
