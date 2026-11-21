# YUMRAM architecture (5.15)

YUMRAM is a Windows PowerShell 5.1 + WPF desktop app with a small C# launcher and installer. It runs as one
process with one UI thread and four background runspaces that share one state object.

## Processes and threads

```text
YUMRAM.exe (C# launcher)  ->  powershell.exe -STA App\YUMRAM.ps1  (hidden console; or via the "YUMRAM" scheduled
                               task when "Start without asking" is chosen)

shared state: $script:Yum (ordered dictionary; every key a worker writes exists from start - Core\Config.ps1)

 UI thread (WPF)                 Telemetry Core runspace        Controller runspace         CPU care runspace
 DispatcherTimer 0.25 s:         memory + CPU every 0.5 s       wakes <= 1 s or on request   wakes 1 s or on app switch
 reads snapshots, draws pages;   Telemetry Aux runspace:        - Free RAM / Deep requests   (SetWinEventHook foreground)
 pages hosted in one window      GPU (only while Overview is    - automatic RAM care         - CPU care (priority, make
 (UI\Shell.ps1)                  visible), game, foreground     - reachable-RAM estimate       room, EcoQoS, learned level)
                                                                                             - leak watch (1/min)
 short-lived runspaces: update check, community download, Windows bloat scan/removal, Startup extras
```

Only the UI thread touches WPF objects; workers publish data into `$script:Yum` and the UI timer renders it.

## Modules (`App\Bootstrap.ps1` load order)

| Area | Files | Notes |
|---|---|---|
| Base | `Core\Logging.ps1`, `Core\Config.ps1`, `Core\Native.ps1` | log with 5 MB rotation; defaults merged with the user's `config.json` (old defaults migrated, user choices kept); Win32 interop (working sets, memory lists, memory combining, priority/EcoQoS) |
| RAM | `Core\Telemetry*.ps1`, `Core\Controller.ps1`, `Core\Cleanup.ps1`, `Core\MemoryReclaim.ps1`, `Core\Safety.ps1`, `Core\Games.ps1` | goal maintenance with hysteresis/back-off; candidates = identified, non-protected programs, re-checked by start time before acting; smallest-first plan, big programs trimmed in chunks (`SetProcessWorkingSetSizeEx`, soft limits); Free/Deep reclaim verified after 5/15/30 s; learned retention ratio |
| CPU | `Core\CpuBalance.ps1`, `Core\LeakWatch.ps1` | one `NtQuerySystemInformation` snapshot per second; Gentle / Balanced (make room) / Strong (Efficiency mode); self-check undo; learned level while gaming from `cpu-knowledge.json`; crash-safe restore file |
| Knowledge | `Core\Intelligence.ps1`, `Core\Research.ps1`, `Core\Scanner.ps1`, `Core\ProcessGuide.ps1` | identity (path, signer, hash), risk lanes, manual organisation, user-triggered scan (every process/service/app + installed programs, signatures checked once per file in parallel, known-apps catalog, one advice vocabulary) and optional online research |
| Windows | `Core\Startup.ps1`, `Core\WindowsBloat.ps1`, `Core\Bloatware.ps1`, `Core\Elevation.ps1` | startup items (Run keys, Startup folders, Store startup tasks, sign-in scheduled tasks); Windows bloat apps/settings with exact undo; opt-in closing of listed background apps; admin modes |
| Distribution | `Core\Updates.ps1`, `Core\Report.ps1`, `Core\Community.ps1` | GitHub release check + SHA-256 verified install; "Report a problem" pre-filled issue; opt-in game-result sharing and weekly shared file |
| Live readings | `Core\LiveReadings.ps1` | Overview CPU % / speed / GPU busy / VRAM per chip (counters + DXGI) and disk busy / speed / free space (PhysicalDisk counters), UI thread, every 2 s only while the Overview or mini bar is visible; works with monitoring off |
| What is it for | `Core\Purpose.ps1` | Plain "what is it / used for which device" text from the catalog, service descriptions and file version info; cached; used by Intelligence, What's running and Startup apps |
| Mini bar | `UI\MiniBar.ps1` | Small always-on-top floating bar (RAM / CPU / GPU / disk, Free RAM, Open, hide to tray); position saved as MiniBarLeft / MiniBarTop |
| UI | `UI\Shell.ps1`, `UI\MainWindow.ps1`, `UI\Dialogs.ps1`, `UI\*Page.ps1`, `UI\Tray.ps1`, `UI\Xaml\*` | one window with a sidebar (Ctrl+1..8), tray, global hotkey, toasts |

## Data files (next to YUMRAM; never in the release package)

`config.json`, `stats.json`, `history.json`, `state.json`, `cpu-balance.json` (crash-safe CPU care restore),
`reclaim-learning.json`, `intelligence-db.json`, `research-*.json`, `manual-organizations.json`,
`cpu-knowledge.json` (this PC's game benchmark), `cpu-community.json` (shared results),
`windows-bloat-undo.json`, `windows-bloat-history.json`, `cpu-bench\`, `YUMRAM.log` (+ `YUMRAM.old.log`).
The installer keeps them on reinstall/update; `YUMRAM.exe --uninstall` removes exactly these and YUMRAM's
program folders, and the folder itself only if it is then empty.

## Launcher, installer, updates

- `Launcher\YumramLauncher.cs` -> `YUMRAM.exe`: start, `--apply-update` (backup to `.previous`, copy, restart),
  `--rollback`, `--uninstall` (only this copy's entries).
- `Launcher\YumramSetup.cs` -> `YUMRAM-Setup-<v>.exe`: per-user install to `%LOCALAPPDATA%\Programs\YUMRAM`.
- `Tools\Build-Release.ps1`: zip (forward-slash paths) + setup + `SHA256SUMS.txt` in `dist\`.

## Measurement tools

- `Tools\Bench-CpuCare.ps1` - test game vs test loads x CPU care levels, repeated runs, medians.
- `Tools\Compare-Versions.ps1` - the same benchmark on the previous release and the new code (gains and losses).
- `Tools\Build-CommunityKnowledge.ps1` - builds `Community\cpu-community.json` from shared results.

## Tests

`Tests\Run-AllTests.ps1` runs every test in its own process; `Tests\UI\FullUiProbe.ps1` drives the real app
(every page, setting and button that does not open external windows) and saves screenshots.
