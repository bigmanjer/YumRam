# Changelog

# YUMRAM 5.12.1 — Safer uninstall, standard zip

- **Uninstall removes only YUMRAM.** Before, `YUMRAM.exe --uninstall` deleted the whole folder YUMRAM was
  in — if the portable zip had been extracted straight into Downloads or the Desktop, that folder went with
  it. It also removed *every* YUMRAM shortcut, sign-in entry, no-prompt task and Settings › Apps entry, even
  ones belonging to another copy. Now it deletes only YUMRAM's own files and folders, removes the folder only
  if it is then empty, removes only shortcuts/entries/task that point at this copy, and refuses to run in a
  development (git) folder. **Tested:** a fake Downloads folder kept the user's own files and folders; a second
  install kept its sign-in and Apps entries; a normal install was fully removed.
- **Release zip uses `/` in paths** (the ZIP standard). Windows PowerShell wrote `App\YUMRAM.ps1`, which
  7-Zip warns about and macOS/Linux extract as flat file names. The installer and in-app updater read both.
- **Checked against the live 5.12.0 release:** a 5.11 copy finds 5.12.0, downloads it, verifies the SHA-256
  and stages it.

# YUMRAM 5.12.0 — Leak alerts, memory combining, 12 h history, no UAC prompt (branch `visual-overhaul`)

- **No administrator prompt every time** (Settings › General › Administrator rights):
  *Ask each time* (default) · *Start without asking* — one-time setup creates a scheduled task that runs
  YUMRAM with highest privileges, and YUMRAM starts through it. **Verified here:** started from a
  non-administrator shell, the task ran as administrator with no prompt · *Never* — run without the
  admin-only steps. *Start YUMRAM when I sign in* uses the task (no prompt) or the normal Run entry.
  YUMRAM.exe no longer forces UAC itself. Trade-off stated in Settings: with *Start without asking*, any
  program running as you could change YUMRAM's files and get administrator through the task.
- **Memory-leak alerts.** Microsoft's guidance: a leak shows as private memory rising steadily, not as
  a big number. YUMRAM samples every program's private memory once a minute (30 min kept, on the CPU care
  worker's existing process list) and flags a program that grew ≥ 400 MB and ≥ 40 %, mostly upward, and
  is still at its peak. One tray notice per program; *What's running* shows "Growing +X GB" and explains
  that closing and reopening it gives the memory back. Nothing is closed automatically.
- **Memory combining** (Windows 10/11; Mem Reduct's "combine memory lists"): identical memory pages are
  kept once. **Measured here:** first run combined 261 MB, Available +0.26 GB in 3.5 s; repeats within
  minutes found only 10–16 MB. So Deep always combines, Free RAM now every 15 min, automatic care every
  30 min. Administrator only.
- **History graph:** 30 s / 5 min / 1 h / **12 h** buttons. A point every 5 s (also while hidden in the
  tray); 12 h kept and saved as 1-minute averages when YUMRAM closes, so a restart keeps it.
- **Low-RAM warning:** a tray notice (at most hourly) when Available stays 1 GB+ under the goal for 2
  minutes and automatic care is off or cannot fix it.
- **Your rules per program** in *What's running*: "Never trim this program" and "Never hold back its CPU".
- Tests: new `Release512Test` (leak heuristic + a real leaking test program flagged, combining wiring,
  12 h history save/load, elevation choices, rules).
- **A real program:** `YUMRAM-Setup-<version>.exe` (≈300 KB, built by `Tools\Build-Release.ps1`).
  Installs for the current user to `%LOCALAPPDATA%\Programs\YUMRAM` (no administrator), adds Start menu
  (+ optional desktop) shortcuts and an entry in **Settings › Apps** with version, publisher, icon and
  Uninstall; reinstalling keeps settings and statistics; in-app updates keep the Apps version current.
  `YUMRAM.exe --uninstall` closes YUMRAM and removes shortcuts, the sign-in entry, the no-prompt task,
  the Apps entry and the folder. Tested: install → reinstall (settings kept) → uninstall (all removed).
- **Smaller download:** the release package holds only YUMRAM.exe, App, Core, UI, Config, VERSION and
  two docs (46 files); build scripts, launcher sources, tests and old .cmd/.vbs launchers stay in the
  repository.
- **GitHub page:** README rewritten (screenshots, features, install, how it works with measured numbers,
  privacy, FAQ, development); bug-report and feature-request forms.

# YUMRAM 5.11.0 — CPU care: automatic help for the CPU, like the RAM goal (branch `visual-overhaul`)

**Research** (primary sources): Task Manager's Efficiency mode = Idle priority + EcoQoS; Microsoft
measured 14–76 % better responsiveness against a background CPU hog. EcoQoS was tuned first for Intel
10th/11th-gen mobile, Ryzen 5000 mobile and Qualcomm. ProBalance (Process Lasso) = Below Normal; its
"Efficiency mode while restrained" is off by default. Process Lasso's CPU Limiter constrains affinity;
anti-cheat blocks opening game processes. Dual-cache-group / X3D users report moving background work off
the game's cores keeps 1 % lows higher. Open source: EnergyStar (EcoQoS for background apps, reacts to
the foreground event), Seanox Process Balancer. Laptop vs desktop matters (shared power/heat budget).

**Measured on this PC** (Ryzen 7 4800H laptop: 8 cores / 16 threads, 2 cache groups of 4 cores, AC):
- Priority alone fixes stutter (wake 5.1 → 2.0 ms) but not speed: SMT siblings are still shared.
- **EcoQoS: no measurable effect on this Zen 2 chip** (same clocks, same work) — as expected from
  Microsoft's tuning list.
- Keeping a hog off one whole cache group made a 4-thread job 35 % faster than priority alone.
- **Simulated 8-thread game** with a 32-thread hog — no hog 153 FPS (1 % low 131); CPU care off 11 FPS;
  Gentle (priority only) 131–135 FPS / 1 % low 75; **Balanced 147–152 FPS / 1 % low 97–123**.

**What it does** (Settings › CPU; Overview card "CPU care"):
- **Gentle** = Below Normal (CPU balance, 5.8). **Balanced** (default) = + *make room*: a hog that keeps
  going while you actively use an app (8 s; a game: 1 s) is kept off whole cores so your app gets full
  cores — then YUMRAM **checks your app really got more CPU and undoes it if not**. **Strong** = Efficiency
  mode for hogs (Idle priority + EcoQoS + low memory priority so Windows drops their cached pages first),
  room after 3 s. A laptop **on battery uses Strong** automatically (can be turned off).
- **No CPU database:** Windows reports the exact layout at runtime — cores, SMT siblings, efficiency
  cores, cache groups. Hybrid Intel: hogs go to the efficiency cores. Several cache groups (AMD CCX/CCD,
  X3D): your app keeps the largest-cache group. Otherwise half the cores. Never splits a core.
- **App switches are instant:** a Windows foreground hook (idea from EnergyStar) wakes CPU care, so a
  program you click on gets its priority back within milliseconds.
- Everything is undone when the program calms down, when you switch to it, when CPU care is turned off,
  when YUMRAM closes, and after a crash (saved state) — only on the same process and only where nobody
  else changed it since.
- **Found while measuring and fixed:** a flip-flop where making room lowered PC load, which looked
  "calm", restored the hog, which took everything again.
- Tests: new `Release511CpuCareTest` (profile, never splits a core, full undo incl. crash recovery,
  leaves others' changes alone).

**CPU shown like RAM, and a visual pass** (dataviz rules: one axis per chart, meters carry severity with
a same-colour track, state written as a word, text in text colour):
- **Overview:** RAM and CPU cards side by side with the same layout — a ring (meter) each, then the
  headline: Available RAM / goal on one side, **CPU speed (GHz), processes, threads, cores, busiest
  programs and what CPU care is doing** on the other (Windows' own counters, the ones Task Manager uses).
  Actions (Free RAM now, Deep reclaim, Automatic care) share one card.
- **Live graph fixed:** RAM was auto-zoomed while CPU/GPU were 0–100 % on the same chart (two scales;
  58 % RAM was drawn near the top). Every line is now on one true 0–100 % scale with 0/50/100 % labels;
  new data enters from the right; title "Live usage". Legend and stat values in text colour (the dot
  carries the series colour). The quick-stats card no longer repeats what the rings show.
- Status pills say "On target / Below goal / Out of reach" instead of "[OK] / [LOW] / [OUT OF REACH]".

**Deep reclaim numbers** (user report: "said 2.90 GB but free RAM jumped a lot more"): Windows has two
"free" numbers. Deep empties the standby cache, so **Free** (Resource Monitor) jumps by GBs, but that
cache already counted as **Available**. The result now says so with both numbers, and if Available keeps
rising after the result (Windows finishing), it reports the highest gain ("kept rising to +X GB after
N s") and counts it in RAM freed. The Reclaim Center's broken "System cache: N/A" / "Commit: N/A"
cards are now **Standby cache** and **Free (unused)** — Available = Free + Standby at a glance. Steps that
need administrator show "Skipped" instead of a red "Failed"; buttons in sentence case.

# YUMRAM 5.10.0 — YUMRAM.exe and updates from GitHub (branch `visual-overhaul`)

Research: PS2EXE builds (script wrapped in its own PowerShell host) are repeatedly flagged by antivirus
ML engines, per file hash, so every release again; established updaters check GitHub Releases, verify
a SHA-256 before replacing anything, use a separate updater process, and keep the old version.

- **YUMRAM.exe** (25 KB, `Launcher\YumramLauncher.cs`, built by `Tools\Build-Launcher.ps1` with the
  .NET Framework C# compiler — no SDK). Starts the readable scripts with no console window, asks for
  administrator itself (the UAC prompt says "YUMRAM"), has the YUMRAM icon. Not code-signed yet.
- **Updates:** once a day in the background (Settings › General, on by default, can be turned off)
  YUMRAM asks `api.github.com/repos/bigmanjer/YumRam/releases/latest` (generic User-Agent, nothing about
  you). An *Update available* banner on the Overview and a *Check for updates* button in About.
  *Install and restart*: download → **SHA-256 must match** (GitHub's asset digest or `SHA256SUMS.txt`;
  no hash = no install) → package VERSION must match the tag → the new YUMRAM.exe waits for YUMRAM to
  close, backs up program files to `.previous`, copies the update in (config, statistics, learned data
  and logs are never touched; a failed copy restores the old files) and starts YUMRAM again.
  `YUMRAM.exe --rollback` goes back.
- **Releases:** `Tools\Build-Release.ps1` → `dist\YUMRAM-<version>.zip` (program files + exe, never user
  data) + `SHA256SUMS.txt`. Today the repo has no release, so the check says so.
- **Fixed:** starting with monitoring paused left the Overview at "--" (target, stats, graph) — the first
  snapshot never bumped the version counter. Runtime files `stats.json` / `cpu-balance.json` were
  accidentally committed in 5.8/5.9; now untracked and ignored.
- Tests: new `Release510UpdateTest` builds a real 9.9.9 package and installs it over a temporary copy
  through the real checker, verifier and exe: 5.10.0 → 9.9.9 → rollback → 5.10.0, tampered download
  refused, user data unchanged. 52/52 pass; full UI probe 53 steps, 0 failures.

# YUMRAM 5.9.0 — Lighter YUMRAM, CPU you can see (branch `visual-overhaul`)

A RAM tool should not be heavy itself. Measured YUMRAM's own cost at idle (goal met, monitoring on,
CPU balance on), then fixed what the measurements pointed at:

| YUMRAM itself, idle | before | after |
|---|---|---|
| Overview on screen | ~24 % of one core | ~14 % |
| Hidden in the tray | ~9 % of one core | ~8 % |
| Own memory when hidden in the tray | ~270 MB | ~120 MB |

- GPU % (display-only, the costliest sample at ~0.25 s CPU each) is sampled only while the Overview is
  on screen. The "reachable RAM" estimate refreshes every 2 min instead of 30 s while nobody sees it.
- Nothing is redrawn while hidden or on another page (history keeps recording, so the graph is whole
  when you come back); the screen timer slows to 1 s while hidden; the graph uses plain loops instead
  of pipelines.
- Hidden in the tray for 10 s, YUMRAM releases its own idle memory (GC + trim of its own working set).

CPU visuals (there was little more than one % number):
- **What's running** (was "What's using RAM"): live CPU column with bars per program (all its
  processes together, same delta method as Task Manager), **Sort by RAM / CPU**, a **CPU now** card with
  a load bar and the busiest program, a **How busy is it?** answer in plain words, and programs CPU
  balance is holding back are marked in amber ("CPU held back"). Small programs that are busy on the
  CPU now appear even under 15 MB.
- Overview's CPU balance card shows the busiest programs right now.
- Full UI probe: 53 steps (adds CPU card, How busy, sort by CPU). A hotkey already owned by another
  running YUMRAM is reported, not treated as an error.

# YUMRAM 5.8.0 — CPU balance (ProBalance-style) (branch `visual-overhaul`)

Last big competitor gap: Process Lasso's ProBalance. Researched from Bitsum's own documentation: it
temporarily lowers a background CPU hog's priority class to Below Normal, restores it when the
condition passes, ignores the foreground app and processes with a non-Normal priority, and works by
lowering offenders rather than boosting the foreground ("far safer").

- **CPU balance** (Overview card, Settings › CPU; on by default). Its own worker checks once a second
  (~25–40 ms of work). When total CPU ≥ 70 % and a background program uses ≥ 10 % of all cores for 2 s,
  it is lowered to Below Normal; it is restored after 3 s under 4 % or when the PC drops below 50 %,
  the moment you switch to it, when CPU balance is turned off, and when YUMRAM closes. Never touched:
  the foreground app and other processes of the same app or its children, the detected game, YUMRAM,
  Windows core processes, services, protected/excluded programs, programs with their own priority.
  Only undoes its own change (same process instance, still Below Normal); a crash leaves a small file
  so the next start puts anything left behind back to Normal.
- **Measured on this PC** (16 threads, CPU hog with 32 busy threads at Normal priority, PC at 97 %),
  wake-up delay of a normal program: idle 1.8 ms avg / 4.7 ms max; hog without CPU balance 33.8 ms /
  82.9 ms; hog with CPU balance 2.0 ms / 2.7 ms. Held back 4.6 s after the hog started, restored ~4 s
  after it went quiet.
- Found while measuring and fixed before release: a blanket "skip anything in C:\Windows" rule and the
  trim list's `powershell` entry made real hogs (scripts) ineligible; the worker's own check took
  366 ms under full load until its thread was raised one notch; crash recovery missed entries because
  of the PowerShell 5.1 `ConvertFrom-Json` array quirk.
- Right after Start Monitoring the status said "Paused" (and after a pause, "Telemetry delayed")
  until the first sample arrived; it now says "Starting…".
- About lists CPU balance and privacy. Tests: new `Release58CpuBalanceTest`; 50/50 pass. Full UI probe
  (51 steps, covers the card, toggle and Settings › CPU): 0 failures.

# YUMRAM 5.7.1 — Full bug test of every view and setting (branch `visual-overhaul`)

A new UI test (`Tests\UI\FullUiProbe.ps1`) drives the real app through every page, setting, button and
tray item (49 steps, temporary config). What it and a settings audit found, all fixed:

- **Free RAM now waited behind automatic care.** With a goal out of reach, a Free RAM / Deep / hotkey
  request could wait minutes for the remaining automatic passes. Automatic care now stops at once to
  let it run.
- **"0 actions completed" with no explanation** when automatic care had already trimmed everything; the
  result now says nothing was left to trim and why.
- **Settings that did nothing:** *Target hysteresis* was saved but never used — automatic care now aims
  that far above the goal (0–2 GB) so creeping memory does not re-trigger it seconds later. The
  *optional services* switch only shows when you have approved services, and the unused *system
  inventory scanner* options are hidden.
- **GPU interval** Reset gave 3 s and accepted 0.5 s, but YUMRAM never samples faster than 5 s; the
  range is now 5–60 s with default 5.
- **Applies immediately:** tray icon on/off (was "next time YUMRAM opens") and sampling intervals
  (monitoring restarts itself; used to say "restart monitoring").
- **Sidebar mode badge** did not follow a mode change made in Settings.
- **About** now lists Startup apps, the one-window layout, the keyboard shortcuts (with your actual
  hotkey), and the privacy line matches what research really sends (name, publisher, product to Bing).
- Tests: new `Release57FixesTest`; 49/49 pass. UI probe: 49/49 steps, no errors in the log.

# YUMRAM 5.7.0 — Startup apps, honest Deep reclaim numbers (branch `visual-overhaul`)

Next competitor gap: IObit's Startup Optimizer and Windows Task Manager's "Startup apps".

- **Startup apps page** (sidebar, `Ctrl+4`). Lists what Task Manager lists (Run keys incl. 32-bit,
  Startup folders) with what each one uses in RAM right now, its publisher, and plain-language advice:
  *Turn off* (launchers, chat, updaters, browsers' background start), *Your call* (sync, backup, VPN),
  *Careful* (hardware helpers for audio, mouse, lighting), *Keep* (security and anti-cheat, locked).
  Turning one off writes the same `StartupApproved` flag as Task Manager (`03` + time; on = `02`), so
  nothing is deleted, the date shows as "off since", and Task Manager / Settings › Apps › Startup agree.
  "All users" entries need administrator; the page says so instead of failing.
- **Deep reclaim reports its real gain.** Measured as administrator: emptying every working set leaves
  GBs on the modified list that Windows writes out 3–5 s later, so Deep showed +1.38 GB while the real
  gain was +3.46 GB. Deep now waits (max 6 s, typically ~2.5 s) for that before measuring: shown
  +2.33 GB vs measured +2.30 GB. Measured Free RAM now as administrator: +1.64 GB, +1.26 GB kept at 30 s.
- **Paused is not an error.** With monitoring off, the status said "Telemetry delayed" and the sidebar
  and tray froze at "--%". It now says Paused and keeps RAM readings live with one cheap read every 2 s.
- Shortcuts are now `Ctrl+1`…`Ctrl+7` (Startup apps is 4, Intelligence 5, Settings 6, About 7).
- Tests: new `Release57StartupTest` (uses a throw-away registry value, cleaned up); all pass.

# YUMRAM 5.6.0 — One window, global shortcut, freed-RAM counter (branch `visual-overhaul`)

Compared against IObit Advanced SystemCare / Smart RAM, Wise Memory Optimizer, Mem Reduct, Process
Lasso and Razer Cortex; this release closes the gaps that mattered for everyday use.

- **One window with a sidebar.** Overview, What's using RAM, Reclaim Center, Intelligence, Settings
  and About are pages in the main window instead of separate pop-ups (the Windows 11 Task Manager /
  Fluent NavigationView pattern: left pane for 5–10 equal sections, Settings at the bottom). The
  sidebar always shows mode, monitoring state and RAM in use, shrinks to icons below 1240 px (or with
  the ☰ button), and `Ctrl+1`…`Ctrl+6` switch pages. Done/Close on a page returns to Overview.
  Intelligence stays alive in the background, so scans and research keep running while you look at
  other pages and it reopens instantly.
- **Global shortcut for Free RAM now** (Mem Reduct has one): `Ctrl+Alt+R` by default, works while
  YUMRAM is minimised to the tray or a game is in front; a tray notice reports the result. Change or
  turn it off in Settings › General. If another program already owns the shortcut, Settings says so.
- **RAM freed by YUMRAM** card (IObit / Wise show this): today and all-time totals, counted from the
  measured Available RAM gain after Windows settles — not trimmed working set, which overstates it.
  Saved in `stats.json`.
- Already on par: free-when-below-threshold (memory goal), skip-when-CPU-busy (`MaxCPUPercent`),
  memory-area choice and game-aware protection.
- Tests: new `Release56ShellTest`; 47/47 pass.

# YUMRAM 5.5.0 — Stays at target, no more Unknowns, plain-language process view (branch `visual-overhaul`)

Memory (from the 5.4 field test: Deep gained +1.2 to +3.5 GB, Free RAM Now +0.3 GB, and automatic
care logged "Target not reachable" every 30-120 s just under a 9 GB goal):
- **Free RAM Now is much closer to Deep.** It now also trims the system file cache (pages move to
  standby, so files stay cached) and flushes the modified list, and considers 24 processes / 12 trims
  (was 16 / 8). Deep alone still purges standby and empties every working set at once.
- **Automatic care keeps up.** When trimming alone falls short, it runs the same file-cache +
  modified-list step (administrator only, never during a game, at most every 45 s). The "reachable"
  estimate includes it.
- **Per-pass limits were silently capped** at 4 / 6 / 10 (Safe / Balanced / Aggressive), so higher
  values in Settings did nothing. Caps are now 10 / 16 / 24; defaults raised to 6 / 10 / 16, clean
  interval 30 → 15 s (old defaults migrate; your own values are kept).

Intelligence:
- **Unknowns resolved on this PC: 0 left (was 2-8).** Protected processes (audiodg, sppsvc,
  SearchProtocolHost, NVIDIA containers, Gaming Services) hide their path from non-admin programs;
  YUMRAM now finds the binary through its Windows service or System32 and lets Windows verify the
  signature. Microsoft's own Store package IDs resolve as Windows components.
- **Research could stop working for good**: a status file left by a closed or crashed run made every
  later Run Scan think research was still running. Status files now carry the process id, and per-item
  results no longer end the run early.
- **Manual decisions now work visibly**: choosing a category resolves the item (risk + status) instead
  of leaving it "Unknown"; "Review Queue" now means reset (it used to pin items as Unknown forever).
- Clicking a summary card switches the Show view and outlines the card; the selected item gets a
  header, the decision panel starts from the item's current category, the search box has a hint, and
  there is a result count. Status appears once (activity strip) instead of four times.
- Saved records that are still Unknown are re-checked on Run Scan, not only running programs.

Windows:
- **What's using my RAM** (was Top memory processes): one row per program (Chrome's 17 processes = 1
  row), memory bars, plain type labels, updates itself every 2 s without losing your selection
  (Pause available), and a "What is this?" panel in everyday words: what it is, how much RAM, can I
  close it, what YUMRAM does with it, where it is, and **Show in File Explorer**.
- **RAM Reclaim Center**: the two options side by side with exactly what each does, an administrator
  badge, coloured results, clearer empty state.
- **Main window**: all tools in the header (the Tools card was below the fold).
- **About**: feature tiles and quick links (YUMRAM folder, log, project page).

Tests: 46/46 (new Release55BehaviorTest; two text-contract tests updated for the new code).

# YUMRAM 5.4.0 — Visual overhaul and faster, more complete research (branch `visual-overhaul`)

Design (researched against Microsoft PC Manager, Wise Memory Optimizer, IObit and Windows 11
guidance; see `Docs/COMPETITIVE-REVIEW.md`, screenshots in `Docs/Screenshots/before|after`):
- One shared theme (`UI/Xaml/Theme.xaml`) for every window: Windows 11 type scale, 4 px grid,
  AA contrast; tables, scrollbars, tabs, group boxes and buttons no longer fall back to white/grey
  Windows defaults.
- Main window reorganized: Available RAM with a RAM-in-use ring, automatic care, and one primary
  "Free RAM now" at the top; graph plus side panel below; no overlapping labels.
- Reclaim Center, Settings (now in tabs), Top Processes, About and Intelligence reorganized.

Tray icon (new, `UI/Tray.ps1`):
- The notification-area icon shows live RAM in use as a number, coloured like the main ring
  (purple, amber from 70 %, red from 85 %); tooltip shows % used and GB free.
- Right-click: Open YUMRAM, Free RAM now (result shown as a notification), Start/Stop monitoring,
  Exit. Left-click opens the window.
- Minimizing hides YUMRAM to the tray (Settings → General: "Show RAM % in the notification area",
  "Minimize to the notification area"; both on by default). The main window now runs its own
  message loop instead of `ShowDialog()`, which would have exited YUMRAM when hidden.
- Icon redraws only when the rounded % changes; tested for GDI/USER handle leaks.

Research:
- All 6 previous Unknowns on the test PC resolve: Store/System packages now use Windows' own
  publisher and signature data (the scanner stored the publisher ID hash before).
- Online verification works for the first time: the trust check assigned to the read-only `$host`
  variable and scored every site 0. The publisher's own domain now counts as authoritative.
- About 3x faster on real items: one `winget list` per run instead of one winget.exe per item
  (whose exact-match flag never worked), cached executable paths, parallel web requests, and
  linear-time text matching (one vendor page took 85 s, now ~1 s).
- Unknown results are re-checked once when the research engine improves.
- Game detection no longer matches "EA" inside words like "Search".

Tests: 45/45 (new ResearchSpeedAndIdentityTest, TrayIconTest; pitfall scan flags assignments to automatic variables).

# YUMRAM 5.3.3 — Alpha: GitHub-ready

- **Settings → Privacy** switch for online research (on by default; it sends unidentified
  programs' names to Bing). Previously there was no way to turn it off in the app.
- **"Start monitoring automatically" now works.** 5.2.x forced it off at every launch.
- `config.json`, logs and learned data are no longer shipped; the first launch creates
  `config.json` from defaults (tested).
- New `Tests\PowerShell51PitfallScanTest.ps1`: an AST scan for the seven PS 5.1 bug patterns
  found in this release cycle (it flags 19 issues in the original 5.2.90 code, 0 now).
- GitHub Actions workflow (`windows-latest`, Windows PowerShell 5.1), `.gitattributes` for CRLF,
  `CONTRIBUTING.md`, current `Docs/ARCHITECTURE.md`; 96 historical audit files moved to
  `Docs/History`. Release notes are now this `CHANGELOG.md`.

# YUMRAM 5.3.2 — Alpha: learns each PC, shows what is reachable

- **Per-PC learned retention.** Only part of a trimmed working set becomes Available RAM, and the
  share differs per machine. Every settled reclaim/cleanup pass that trims >= 200 MB updates a
  running average saved in `reclaim-learning.json` (bounded 15-90%; default 40% until 2 samples).
  First real run here: samples 45/42/28/38/35% -> 38%, matching the hand measurement (38-40%).
- **Trim planner uses the learned ratio** instead of a fixed 40%.
- **"Reachable ≈ X GB"** on the target line: current Available + (memory the current mode may trim
  x learned retention). The status shows **[OUT OF REACH]** when the target is above it, and the
  tooltip explains the numbers. Setting a target above it shows a note and resets the back-off.
- Tests: 42/42 (new RetentionLearningTest).

# YUMRAM 5.3.1 — Alpha: lag, settings, and reclaim strength

Measured on the developer's 16 GB Windows 11 PC with the real program running.

## Lag
| While monitoring | 5.3.0 | 5.3.1 |
|---|---|---|
| YUMRAM CPU (idle) | 77% of a core | 14% of a core |
| UI work per refresh | 25 ms avg, 298 ms worst | 4.6 ms avg, 24 ms worst |
| Free RAM / Deep Reclaim | froze the window | runs on the background worker |

- GPU usage was read with `Get-Counter`, costing ~1.4 s of CPU every 3 s. Now read directly
  (~0.27 s) and at most every 5 s.
- The telemetry aux loop republished a snapshot every 200 ms, so the UI redrew the graph ~4x/s and
  the graph only held ~15 s of history. It now publishes only when GPU/game data changes.
- Game detection uses a hash-set lookup (~6x less CPU).
- Automatic maintenance backs off (30 s, doubling to 2 min) when the target cannot be reached,
  instead of re-scanning every 1-4 s forever.
- Per-process cooldown actually works now (it was checked but never recorded), so a busy app is
  no longer trimmed on every pass and immediately paged back in.

## Settings
- **Saved settings were ignored at every launch** (present since 5.2.x): the config merge bound an
  ordered dictionary to a `[hashtable]` parameter, which made a copy, so the app always started on
  defaults (e.g. a 10 GB target came back as 4 GB). Fixed, with a regression test.
- Modes retuned. Safe mode could never trim anything (score floor 65 was unreachable); Balanced
  skipped most mid-size apps. New floors: Safe 34, Balanced 24, Aggressive 12; larger per-pass
  budgets. Balanced now also trims "Review" processes with a valid publisher signature.
- Old default values are migrated (2/3/5 processes per pass -> 3/5/8, Free RAM actions 3 -> 8,
  GPU interval 3 s -> 5 s); values you changed yourself are kept.

## Reclaim strength
- **Free RAM Now / Deep Reclaim never trimmed a process** in 5.3.0: a helper rejected `$null`
  (no reclaim history yet), so every candidate was skipped. Now: +0.45 to +0.90 GB per click here.
- Trimmed memory reaches "Available" 1-2 s later and only ~40% of it (measured). Cleanup now
  plans with that ratio and waits 1.5 s before judging a pass, instead of seeing ~0 gain and
  escalating into fallback churn.
- Learning now records how much of each trim stayed trimmed, deprioritizing apps that page
  straight back in (it previously penalized every process after two samples).
- Deep reclaim flushes the modified list *after* trimming (5.3.0 flushed first, too early).
- Free RAM Now uses the Intelligence classifier, so it no longer trims protected items such as
  Steam's web helper (game overlay).

Result with Balanced + 10 GB target: automatic maintenance gained +0.74 GB (was +0.07 GB).
Tests: 41/41 (new: ConfigPersistenceTest; reclaim test now checks real candidates).

# YUMRAM 5.3.0 — Alpha (consolidated from 5.2.74 and 5.2.90)

5.2.90 is the base. 5.2.74's only unique feature (the Cleanup Preview window) was intentionally
replaced by the RAM Reclaim Center in 5.2.80 and is not restored. This release makes the core
features actually run; several were silently dead in 5.2.90. Full analysis: `Docs/REVIEW-5.3.0.md`.

## Fixed: features that never worked
- **Automatic target maintenance never ran.** The controller used `System.Timers.Timer` with a
  PowerShell scriptblock; on Windows PowerShell 5.1 those handlers fire on threads with no
  runspace and never execute. It now runs in a runspace worker (`Core\Controller.ps1`), which also
  revives queued Safe Optimization requests.
- **Auto-clean on game start and the game priority boost never ran.** Nothing called
  `Update-YumGameState`; the controller worker now calls it every second while monitoring.
- **FREE RAM NOW / DEEP RAM RECLAIM always failed.** `-TopN (if(...){16}else{10})` ran a command
  named `if`. Behind that: `@($genericList)` "Argument types do not match" and `Measure-Object .Sum`
  on empty input under StrictMode.
- **Automatic cleanup could not select or trim processes.** `Sort-Object -Ascending` (no such
  parameter) threw in every trim plan; the trim log line divided an array (comma binds tighter
  than `/`) and aborted the pass after the first trim; one large idle process could never be
  chosen when RAM was only slightly below target.
- **Reclaim verification (5s/15s/30s) never ran and always showed "Pending".**

## Fixed: other bugs
- Ten messages showed a literal `` `n `` instead of a line break.
- Research progress text threw a FormatException (3 placeholders, 2 arguments).
- Research lost the executable identity of services/startup items with quoted arguments.
- Negative NTSTATUS codes threw when formatted, hiding the real error.
- `Update-YumSnapshotMemory` wrote a snapshot that readers immediately overwrote.
- Stopping monitoring now also stops automatic maintenance; on exit the controller stops before
  optional services are restored.

## Improved
- Reclaim Center no longer rebuilds its table every second or runs WMI on the UI thread.
- Per-step reclaim measurements use the fast native snapshot (no WMI per trimmed process).
- Tests: 40/40 passing (was 12/37). New `Tests\Run-AllTests.ps1` and three behavioral tests.
- All sources normalized to UTF-8 BOM + CRLF.

## Upgrade note
`ResearchEngineVersion` changed, so the first Intelligence scan re-researches cached items.

# YUMRAM 5.2.90 — UI, Telemetry and Reclaim Verification

- Telemetry metrics now distinguish unavailable from zero.
- Reclaim results include non-blocking retained-effect verification at 5s, 15s, and 30s.

## Fixed
- Responsive RAM Reclaim Center sizing and narrower table layout.
- Corrected Cache and Commit telemetry to use Windows `GetPerformanceInfo`; unavailable metrics display `N/A` instead of false zeroes.
- Added non-blocking 5s/15s/30s reclaim-effectiveness verification and retained-gain reporting.
- Added native memory-list API bindings and privilege handling required by Deep Reclaim.
- Improved main-dashboard wording so below-target memory is not automatically described as emergency pressure.
- Kept the preview scan removed from RAM Reclaim Center startup.

# YUMRAM 5.2.87 — Stability Contract Cleanup

## Fixed
- Synchronized `VERSION`, default configuration `Version`, and `ResearchEngineVersion`.
- Removed duplicate UI helper implementations from `UI/Dialogs.ps1`; canonical core implementations are now authoritative.
- Converted release-version regression assertions to derive the expected version from the canonical `VERSION` file.
- Moved historical release/audit documents into `Docs/History` where applicable.
- Preserved the RAM Reclaim Center runtime fixes and Research State UI removal.

## Release policy
`VERSION` is the source of truth for the active YUMRAM release. Tests and runtime configuration must consume it rather than hard-code historical versions.

# YUMRAM 5.2.86 — RAM Reclaim Center Runtime Fix

## Fixed
- Corrected RAM Reclaim Center button handlers.
- The action handlers now receive the shared reclaim state instead of reading a nonexistent `Button.Tag`.
- Corrected Close handler to close the owning window.
- Added a regression test for the state-binding bug that caused `Progress` and `FreeRam` property errors.

## Runtime diagnosis
This fixes the 5.2.85 error:
`The property 'Progress' cannot be found on this object.`
and the follow-on:
`The property 'FreeRam' cannot be found on this object.`

# YUMRAM 5.2.86 — Windows PowerShell Encoding Fix

## Fixed
- Converted all PowerShell source (`.ps1`, `.psm1`) to UTF-8 with BOM for Windows PowerShell 5.1.
- Preserved emoji and non-ASCII UI/log text without parser corruption.
- Converted WPF XAML files to UTF-8 with BOM for consistent parsing.
- This specifically fixes `UI\MainWindow.ps1` failures where `💜` was decoded as mojibake (`ðŸ’œ`) and caused a PowerShell ParseException.

## Validation
- No PowerShell source file is emitted as UTF-8 without BOM.
- Launcher remains ANSI/no BOM.

# YUMRAM 5.2.83 — Launcher Reliability Fix

## Fixed
- Removed the UTF-8 BOM from `Launch-YUMRAM.cmd`; the Windows CMD interpreter now sees `@echo off` correctly.
- Launcher no longer overwrites `YUMRAM.log` after an application failure.
- Launcher/startup diagnostics remain in `%TEMP%\YUMRAM-startup.log`.
- The application owns `YUMRAM.log`, preserving the real PowerShell exception and application diagnostics.

## Validation
- CMD file: no UTF-8 BOM.
- Destructive startup-log-to-application-log copy: absent.

