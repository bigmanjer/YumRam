YUMRAM 4.6.9 — stability, scan reliability, and Intelligence consolidation release.

YUMRAM 4.6.9

Task Manager-style system inventory expansion and selection-race repair.

- Processes: PID, RAM, CPU, parent PID, session, publisher, risk and score.
- Services: start mode, CanStop, dependents and risk.
- Apps: installed AppX package inventory.
- Startup: Win32_StartupCommand inventory.
- Filter selection is safe before inventory completion.
- Selected-row text is explicitly readable in the purple theme.

## 4.5.9
- Fixed Windows PowerShell 5.1 XAML decoding by reading all UI XAML explicitly as UTF-8.
- Added a regression check preventing bare Get-Content XAML reads in UI modules.
- Preserved UTF-8 BOM for PowerShell source and ASCII/no-BOM launchers.

# YUMRAM 4.6.9 Release Notes

This is a stability-first improvement over 4.3.0. The specialized purple GUI remains intact.

Key fixes: graph series, target updates, cleanup preview, richer information dialogs, scrollbar polish, and safer game-priority handling.

Game priority changes CPU scheduling preference only. Microsoft documents Above Normal as above Normal but below High, and warns that High priority can let a CPU-bound process consume nearly all available CPU cycles; YUMRAM therefore defaults to KeepExisting and confirms High before enabling it.

Optional background cleanup remains user-configurable. The recommended catalog includes common optional desktop helpers and explicitly describes possible side effects. Services remain explicit, dependency-checked, and startup-type-neutral.

### 4.5.9
The 4.5.9 repair build addresses the frozen dashboard/graph problem caused by a missing worker-to-UI snapshot-version handoff. It also moves system/background scans off the UI thread and upgrades Settings from a report window to an editable configuration panel.
