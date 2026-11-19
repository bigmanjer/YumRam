# YUMRAM

**Yumes Ultimate Memory Reclaim & Monitor**

Version: 5.10.0
Stage: alpha

**YUMRAM keeps Windows responsive by keeping Available RAM above a target you choose.** It trims the
memory of idle, identified background programs, never closes anything on its own, and stays out of
the way of games and whatever you are using.

It is a single-folder Windows PowerShell 5.1 + WPF app: no installer, no runtime to download.

![tests](https://img.shields.io/badge/tests-Windows%20PowerShell%205.1-7c3aed)

## Features

- **One window**: a sidebar (like Windows 11 Task Manager) opens Overview, What's using RAM, Reclaim
  Center, Startup apps, Intelligence, Settings and About (What's running shows live RAM and CPU per program) as pages in the same window. `Ctrl+1`…`Ctrl+7`
  jump between them, and the sidebar shrinks to icons when the window is narrow.
- **CPU balance** (like Process Lasso's ProBalance): when the PC is busy and a background program hogs
  the CPU, YUMRAM temporarily lowers it to Below Normal priority so the app you are using stays smooth,
  and puts it back as soon as it calms down. The foreground app, games, Windows core processes,
  services and programs with their own priority are never touched. Measured here with an all-core CPU
  hog: a normal program's wake-up delay went from 33.8 ms (no CPU balance) to 2.0 ms (1.8 ms idle).
- **Startup apps**: every program that starts when you sign in, how much RAM it uses right now, and
  plain-language advice (Turn off / Your call / Careful / Keep). Turning one off uses the same switch
  as Task Manager, so nothing is deleted and it can be turned back on in either place. Security and
  anti-cheat software cannot be turned off from YUMRAM.
- **Live dashboard**: Available RAM, memory use, CPU, GPU 3D and a 60-sample history graph, plus how
  much RAM YUMRAM has freed today and in total (measured Available gain, not trimmed memory).
- **Global shortcut**: `Ctrl+Alt+R` runs Free RAM now from anywhere, even when YUMRAM is in the tray
  (change or turn it off in Settings).
- **Automatic target maintenance**: while monitoring is on, YUMRAM trims eligible idle processes
  in small paced passes until Available RAM is back above your target.
- **Knows what is reachable**: it learns, on your PC, how much trimmed memory Windows actually turns
  into Available RAM, and shows `reachable ≈ X GB` next to your target. Targets above that are
  marked **[OUT OF REACH]** and retried with a back-off instead of hammering the system.
- **FREE RAM NOW / DEEP RAM RECLAIM**: one-click reclaim with measured before/after results and
  5 s / 15 s / 30 s verification of how much of the gain was retained.
- **Smart Intelligence**: identifies every process, service, Store app and startup item (signatures,
  installed-software records, services) and sorts them into Protected, Candidate, Review and Unknown.
  Only identified, non-protected programs are ever trimmed.
- **Game aware**: detects known games, protects the game and the foreground window, and can raise
  game priority or clean up when a game starts.

## Requirements

- Windows 10 or 11 (64-bit)
- Windows PowerShell 5.1 and .NET Framework 4.x (both built into Windows)
- Administrator rights for the full feature set (YUMRAM asks on launch). Without them it still
  trims your own programs, but cannot purge the standby/modified memory lists.

## Getting started

1. Download the latest release zip from GitHub (or clone this repository) into any folder.
2. Double-click **`YUMRAM.exe`**. It is a small launcher (source in `Launcher\`, built by
   `Tools\Build-Launcher.ps1` with the C# compiler that ships with Windows) that starts the readable
   scripts next to it with no console window. `Launch-YUMRAM.cmd` still works too.
3. Accept the administrator prompt (it says "YUMRAM").

**Updates:** YUMRAM checks GitHub Releases once a day (Settings › General to turn it off; nothing about
you or your PC is sent). When a new version is out, the Overview shows *Install and restart*. The
download is verified against its published SHA-256 before anything is installed, your settings and
statistics are kept, and the previous version is kept in `.previous` (`YUMRAM.exe --rollback` to go
back). Maintainers: `Tools\Build-Release.ps1` builds `dist\YUMRAM-<version>.zip` and `SHA256SUMS.txt`
to attach to a GitHub Release tagged `v<version>`.

The exe is not code-signed yet, so Windows SmartScreen may say "Windows protected your PC" the first
time (More info › Run anyway).
4. Set your **Available RAM target** and press **Start Monitoring**.

Your settings are saved in `config.json` next to the program (created on first launch).

## Modes

| Mode | What it may trim | Per pass |
|---|---|---|
| **Safe** | Identified, low-risk idle programs only | up to 3 processes / 512 MB |
| **Balanced** (default) | Safe + programs with a valid publisher signature | up to 5 processes / 1 GB |
| **Aggressive** | Balanced + other identified programs pending review | up to 8 processes / 2 GB |

Protected items (Windows core, security software, drivers, games, launchers/overlays), the
foreground window, the active game and anything unidentified are never trimmed in any mode.

### Why "trim" and not "free"

Trimming asks Windows to move a program's idle pages out of RAM. Nothing is closed and no data is
lost: if the program needs a page again, Windows brings it back. Only part of a trimmed working set
becomes Available RAM (about 40% on a typical PC, because of memory compression), and only after
1-2 seconds. YUMRAM measures this on your machine and plans with your real number.

## Privacy

- **Online research is on by default.** When Intelligence cannot identify a program locally, it
  searches Bing for the program's name, publisher and product name. No other data is sent.
  Turn it off in **Settings → Privacy**; local identification keeps working.
- Nothing else leaves your PC. There is no telemetry, account or update check.
- Everything YUMRAM learns (`intelligence-db.json`, `research-*.json`, `reclaim-learning.json`,
  `YUMRAM.log`) stays in the program folder and is excluded from git by `.gitignore`.

## Safety

- YUMRAM never terminates processes automatically. "End task" in Top Processes always asks twice.
- Optional services are stopped only if you allow it in Settings, never Automatic/boot services or
  services with running dependents, and they are restarted when YUMRAM exits (or on the next launch
  after a crash).
- The launcher starts PowerShell with `-ExecutionPolicy Bypass` for this process only; it does not
  change your system execution policy.

## Troubleshooting

| Symptom | What to check |
|---|---|
| Target shows **[OUT OF REACH]** | Your target is higher than this PC can free right now. Lower it, close apps, or use Aggressive. |
| Deep reclaim rows say *Required privilege was not enabled* | Run as administrator. |
| Nothing happens automatically | Monitoring must be on (green **ACTIVE**). |
| Something failed | See `YUMRAM.log` in the program folder and `%TEMP%\YUMRAM-startup.log`. |

## Development

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File Tests\Run-AllTests.ps1
```

Every test runs in its own Windows PowerShell 5.1 process. Behavioural tests fake the native memory
calls, so running them never changes anything on your machine. GitHub Actions runs the same suite on
every push. See [CONTRIBUTING.md](CONTRIBUTING.md) and [Docs/ARCHITECTURE.md](Docs/ARCHITECTURE.md).

```text
App/        launcher entry point and module bootstrap
Core/       memory engine, safety policy, intelligence, research, telemetry, controller worker
UI/         WPF windows (XAML) and their PowerShell code
Config/     default-config.json (shipped defaults)
Tests/      test suite and Run-AllTests.ps1
Docs/       architecture, review, and History/ (audit trail of earlier versions)
```

## Status and license

YUMRAM is **alpha** software: the memory engine, automatic maintenance and UI are tested on real
hardware, but expect rough edges. See [CHANGELOG.md](CHANGELOG.md).

No license has been chosen yet, so all rights are reserved by the YUMRAM contributors. You may
read the code, but please ask before reusing or redistributing it.
