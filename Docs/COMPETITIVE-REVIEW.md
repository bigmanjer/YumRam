# Competitive review (YUMRAM 5.17.0, November 2026)

How YUMRAM compares with the tools people use for the same jobs, what it does better, what it still lacks, and what
was fixed because of this review. Earlier version of this review: 5.4 (its roadmap items are marked below).

## The tools

| Job | Tools people use |
|---|---|
| Free / manage RAM | Mem Reduct, Wise Memory Optimizer, WinMemoryCleaner, Microsoft PC Manager, Razer Cortex |
| Gaming stutter (standby list) | ISLC (Intelligent Standby List Cleaner) |
| CPU priority / background hogs | Process Lasso (ProBalance) |
| Startup programs | Task Manager, Autoruns, CCleaner |
| Disk cleanup | Windows Disk Cleanup / Storage Sense, BleachBit, CCleaner |
| What's using my disk | WinDirStat, WizTree, TreeSize |
| Live readings and temperatures | Task Manager, HWiNFO, MSI Afterburner, Core Temp |
| Windows bloat | WinUtil, O&O ShutUp10++ |
| Uninstall programs + leftovers | IObit Uninstaller, Revo Uninstaller, Geek Uninstaller, Windows Settings > Apps |

## Pros - where YUMRAM is better

- **One tool instead of six:** RAM care, CPU care, startup apps, Windows bloat, disk cleanup, disk usage and live
  readings with temperatures, explained in plain words.
- **Honest numbers:** every reclaim is re-measured after Windows settles (5 / 15 / 30 s) and only real gains count;
  Mem Reduct-style tools show what was trimmed, not what was kept.
- **Goal-based, careful automation:** keeps RAM above *your* goal and backs off when it cannot help; protected,
  security, driver, game, unknown and (since 5.16.1) overclock/undervolt tools are never touched.
- **Knows every program** (signatures, installed software, Store packages, optional web research) and says what it
  is for - none of the RAM tools do this.
- **Safe disk cleanup:** sizes and explanations first, "open folder" to look, a list of every deleted file, Windows'
  own tools for system areas; never personal files, cookies or passwords (BleachBit/CCleaner can).
- **Everything can be undone** (Windows bloat, startup items, GPU preferences, CPU care).
- **No drivers, no account, no telemetry, free.**

## Cons - where competitors are still ahead

| Gap | Who does it | Status |
|---|---|---|
| Anti-stutter standby-list cleaning while gaming | ISLC | **Added in 5.16.4** (opt-in, administrator) |
| Fast whole-drive "what's using my disk" | WizTree (reads the NTFS file table, seconds) | 5.16.4: results appear live while scanning; a full NTFS reader is not planned (needs raw disk access) |
| Exact CPU core temperatures | HWiNFO, Core Temp (kernel drivers) | By design: Windows' thermal zone only - no kernel drivers (WinRing0 is flagged by Windows) |
| Signed program, WinGet / Scoop listing | WinMemoryCleaner, Process Lasso | Open (needs a code-signing certificate - an owner decision) |
| Command-line actions (e.g. a "Free RAM" shortcut) | WinMemoryCleaner, Mem Reduct | Open - next candidate |
| Uninstall programs from the same window, with leftover clean-up | IObit Uninstaller, Revo, CCleaner, PC Manager | **Added in 5.17.0** (own uninstaller, then leftovers to the Recycle Bin, registry backed up first). Not planned: install monitoring / snapshots (Revo Pro) and forced removal of broken programs without an uninstaller |
| Real-time per-app rules (CPU affinity, priority classes) | Process Lasso | Partly: "never trim" / "never hold back" rules; full rules not planned |
| Native look and start-up time | All compiled tools start in < 1 s | Improved (5.16.0 helper cache, 5.16.2 own icon and title bar); PowerShell + WPF still needs ~3 s |

## 5.4 roadmap - where it stands

1. Tray icon with live RAM % - **done**.
2. Standby-list guard for gaming (ISLC-style) - **done in 5.16.4**.
3. Choose reclaim areas in Settings - **done**.
4. Command-line switches - open.
5. ProBalance-style CPU care - **done** (CPU care, with self-check and undo).
6. Code signing / WinGet - open (owner decision).

## Added in 5.17.0

- **Uninstall programs** (user: "having ability like IObit Uninstaller"): every desktop program and Store app with
  size, install date and plain advice, biggest first, searchable. Runs the program's own uninstaller and then finds
  what it left behind. Safer than IObit / Revo's defaults: only exact-name matches, never a folder used by another
  program or with a program running in it, settings folders unticked, folders to the Recycle Bin and registry keys
  backed up to a `.reg` file you can double-click to restore. Also bundles no extra software and shows no ads (IObit
  Uninstaller's free version does both).

## Fixed because of this review (5.16.4)

- **Anti-stutter while I play** (Settings > Gaming, off by default): while a game runs and YUMRAM is administrator,
  when free memory is below 1 GB and Windows' standby cache is above 1 GB, the standby cache is emptied (at most
  every 30 s) - ISLC's default rule. Measured on the test PC: standby 5.4 GB -> 0, free 0.16 GB -> 5.5 GB; the work
  runs in the background (window thread 20-32 ms per check, every 5 s, only while a game runs).
- **What's using my disk** works like a disk analyzer should: folders appear at once, sizes fill in biggest-first
  while it scans (a full C:\ took 85 s and showed nothing until the end), Stop, the last result is remembered, and
  rows are compact.
