# Changelog

# YUMRAM 5.17.2 — YUMRAM now stands for "Yume's Ultimate Machine Rescue And Maintenance"

- **The name has a meaning** (owner's choice): **Y**ume's **U**ltimate **M**achine **R**escue **A**nd
  **M**aintenance - named for Yume. Shown on the About page (under the name, with "Named for Yume 💜") and at the
  top of the README. The program, installer, settings and updates keep the name YUMRAM, so nothing changes for
  anyone who has it installed.
- About: the keyboard shortcuts now include Disk cleanup (Ctrl+9) and Uninstall programs (Ctrl+0).

# YUMRAM 5.17.1 — Disk cleanup: progress bar, "finished", list updates by itself

- **Progress bar while cleaning** (user: "loading bar indicating when clean is finished, then update automatically").
  Disk cleanup used to show only "Cleaning 7 categories…" in the footer until it was done - with Windows' own tools
  that can be minutes with no sign of life. Now a bar in the "Safe to clean" header shows which category is being
  cleaned, how many are done, how much is freed so far and the time ("Cleaning: Browser caches… 3 of 7 • 412 MB •
  14 s"; Windows' own tools say "a few minutes"). When it ends the bar turns green - "Finished - freed X. Updating
  the list…" - the list is measured again by itself and the bar then says "List updated" with how long it took.
  "Check again" hides it. In the header line, so the list keeps all its room.
- Tests: the disk cleanup test checks the progress counts (without deleting anything); the UI test checks the bar
  mid-clean, runs the real clean flow end to end (on categories that are skipped without administrator) and checks
  that it ends "finished" with the list re-measured.
# YUMRAM 5.17.0 — Uninstall programs (with leftover clean-up)

- **New page: Uninstall programs** (sidebar, <kbd>Ctrl</kbd>+<kbd>0</kbd>; user: "having ability like IObit
  Uninstaller"). Lists every desktop program (all users and this account) and every Store app with its size and
  install date, biggest first, with search, sort (size / name / date) and plain advice: *Careful* for drivers,
  hardware tools, runtimes (.NET, Visual C++, DirectX) and codecs; *Your call* with a note for anti-cheat and
  antivirus. Windows updates, system components and child entries are hidden. Measured on the test PC: 98 desktop
  programs in about 0.15 s, 37 Store apps read in the background.
- **Uninstall** runs the program's own uninstaller (Windows Installer programs with `msiexec /x`, Store apps with
  Windows' own removal); Windows asks for administrator approval when the program needs it. YUMRAM waits until
  Windows no longer lists the program (also for uninstallers that hand off to a copy and exit) and can stop waiting.
- **Leftovers**: afterwards YUMRAM looks for what was left behind - the install folder, folders with the program's
  exact name in Program Files / ProgramData / AppData, Start menu and desktop shortcuts, and its registry settings -
  and lists them with sizes. Strict on purpose: never a folder with a merely similar name, a shared folder
  (Microsoft, Common Files...), a folder another installed program uses, or one with a program running from it.
  Settings folders in AppData are listed but not ticked (they may hold your own files). Folders and shortcuts go to
  the **Recycle Bin**; registry keys are first saved to a `.reg` file (double-click to restore, "Open backups");
  a list of what was removed is kept in `uninstall-last.txt`.
- YUMRAM cannot uninstall itself while it runs; for YUMRAM the page points to Settings > Apps.
- New test `Tests\UninstallerTest.ps1`: installs a fake program for this account only, uninstalls it with its own
  uninstaller, checks that exactly the right leftovers are found and ticked (a similar-named folder and a folder used
  by another program are not), removes them, and restores the registry backup. The UI test checks the new page.
- README: feature row and picture; competitor review and architecture updated.
# YUMRAM 5.16.4 — "What's using my disk" really works; anti-stutter while gaming; competitor review

- **What's using my disk, rebuilt** (user: "that whole section doesn't really work"). Measured: a scan of C:\ took
  85 s on the test PC (983,000 files) and showed nothing until the very end, the page never scanned by itself, and
  only about two rows fit. Now the folders appear at once and each gets its size as soon as it is measured
  (biggest first, "15 of 18 folders done"), Scan becomes **Stop** while it runs, double-click / Up start a new scan
  right away, the last result is remembered (also after a restart), the section has its own status line and more
  room, and folder rows take one line. Checked on the test PC's screen: C:\ (Program Files (x86) 129 GB, Users
  86 GB...), double-click into a folder (2 s), biggest files.
- **Anti-stutter while I play** (Settings > Gaming, **off by default**, administrator): ISLC-style - while a game runs,
  when free memory is below 1 GB and Windows' standby cache is above 1 GB, the standby cache is emptied, at most
  every 30 s. Measured: standby 5.4 GB -> 0, free 0.16 GB -> 5.5 GB; the clearing and the first opening of the
  memory counters run in the background (window thread 20-32 ms per check, every 5 s, only while a game runs).
- **Competitor review updated** (`Docs/COMPETITIVE-REVIEW.md`): pros, cons and what is still open versus Mem Reduct,
  ISLC, Process Lasso, WizTree/WinDirStat, BleachBit/CCleaner, HWiNFO, PC Manager and others.
# YUMRAM 5.16.3 — Disk cleanup "Select all" really ticks everything; startup names without account IDs

- **Fix: Disk cleanup "Select all" left some categories unticked** (user: "Select all doesn't tick everything"). It
  skipped categories with nothing to clean right now (on the test PC: Crash dumps, Graphics driver installer
  leftovers, Recycle Bin), so it looked broken. It now ticks every category that is not locked (locked = needs
  administrator), and rebuilds the list so every box shows its tick. The UI test now checks the real tick boxes on
  screen, scrolling row by row; it fails on 5.16.2's code (naming those three) and passes now.
- **Startup apps: names no longer show the Windows account's security ID** (e.g. `GHelper_S-1-5-21-...` is shown as
  `GHelper`) - unreadable and an account identifier that does not belong on screen or in screenshots. The real task
  name is still used to turn it on or off. Found in the full visual check (user: "double check everything visual and
  functions"); the startup test checks it.
- Disk cleanup: more space between "Clean selected" and "Select all". About mentions temperatures.
- README pictures re-taken (5.16.3: flat labels, temperatures, Select all, clean startup names).
# YUMRAM 5.16.2 — looks like YUMRAM, not PowerShell; temperatures; flat labels; Disk cleanup Select all

User: "make it not look like a PowerShell program - the top bar and the taskbar". YUMRAM runs inside Windows
PowerShell, so Windows showed PowerShell's blue icon in the title bar and on the taskbar, grouped YUMRAM with other
PowerShell windows, and "Pin to taskbar" pinned PowerShell. Seen on the test PC's screen, then fixed:
- **YUMRAM's icon** in the title bar and on the taskbar (every YUMRAM window, dialogs included).
- **Its own taskbar identity** (AppUserModelID `YUMRAM.App`): its own taskbar button, and pinning it pins
  `YUMRAM.exe` with YUMRAM's name and icon.
- **A dark title bar in YUMRAM's colours** (dark purple bar, light text, purple border) instead of the Windows accent
  colour (orange on the test PC). Windows 11; Windows 10 gets Windows' dark title bar.
- New `UI\WindowChrome.ps1`; the responsiveness test checks the icon, colours and identity are applied.
- **Temperatures** (user: "showing temps would be nice"), top-right on the CPU, GPU and Disk cards, green / amber /
  red: CPU area from Windows' thermal zone counter, NVIDIA graphics from the NVIDIA driver (`nvml.dll`) - read only
  while the chip is awake (busy or holding memory) so a sleeping laptop GPU is never woken (shows "asleep"), disks
  from Windows' drive health data (administrator; some drives do not report it). No extra drivers: tools that read
  CPU sensors directly install kernel drivers (e.g. WinRing0, which Windows now flags). Read in the background
  sampler every ~5 s (disks every 60 s); test PC: CPU 84-93 °C under load, GPU 73-76 °C.
- **Flat status labels** (user: "no circle/oval bubbles, looks like PowerPoint"): "On target", "Watching", "ACTIVE",
  sidebar mode and monitoring state are plain coloured text; advice tags in lists are small rectangles.
- **Disk cleanup: Select all** (ticks every category that can be cleaned; click again to untick) and **fix: a tick
  disappeared when the list was scrolled** (the list re-reads each row when it redraws; ticks were not stored on the
  row - the clean itself used the right list). The UI test checks both.

# YUMRAM 5.16.1 — Overview graph fixed; overclock/undervolt tools left alone; pages open faster; new screenshots

- **Fix: the Overview graph stayed empty in 5.16.0.** When the graph code was sped up, one line was lost; the graph
  then failed on every redraw (strict mode) and the error was caught silently. Found while re-taking the README
  pictures (user: "double check graphs working?"). The UI test now checks that the graph really draws lines.
  **Correction to the 5.16.0 notes:** its "graph 38 -> 4 ms" and "window thread 17 % -> 11 %" were measured with the
  broken graph (it failed before drawing). Measured again with the fix: graph **38 -> ~13 ms** per redraw (the live
  30-second view is now built in one compiled call per line); window thread with the Overview open about the same
  as 5.15.9. The start-up and hidden-in-tray gains of 5.16.0 do not involve the graph and stand.
- **Overclock / undervolt tools are never touched** (user: "I may have undervolted my GPU and overclocked my CPU").
  YUMRAM never changes clocks, voltages, power limits, fan curves or power plans (a test now checks there is no
  power-plan code). In addition, the tools that apply those settings - MSI Afterburner / RTSS, AMD Ryzen Master,
  Radeon Software, NVIDIA app, ThrottleStop, Intel XTU, EVGA Precision, ASUS GPU Tweak / Armoury Crate, Legion
  Toolkit, OMEN / Alienware / MSI Center, FanControl, HWiNFO and others - are now never trimmed by RAM care or Free
  RAM and never held back by CPU care, whatever the settings say.
- **Fix: Settings > CPU > "Never hold back" could show `system.collections.specialized.ordereddictionary`.** A name
  list loaded from config.json could lose its shape (PowerShell turns `[]` into nothing and a one-item list into a bare
  value), was saved as `{}`, shown as a .NET type name and saved back as an entry when Apply was pressed (found on
  the test PC's real config while taking the screenshots). Lists now keep their shape, and on start the four name
  lists drop such entries (harmless - no program has that name - but wrong).
- Live readings: CPU and disk are read before the GPU adapter list (which compiles a helper the first time), so the
  Overview shows numbers sooner on a busy PC.
- **Screenshots:** the README gallery shows 5.16.1, now with Disk cleanup. `Tools\Capture-Screenshots.ps1` takes
  them from the real app and hides the Windows user and computer name.

| Opening (test PC, real data) | 5.16.0 | 5.16.1 |
|---|---|---|
| Intelligence (first time) | 1.1-1.3 s | **0.6 s** |
| What's running | 0.8-1.1 s | **0.7 s** |
| Window up and responding after start | ~5 s | **3.3 s** |

- **Intelligence:** building the list asked "is there a manual decision for this program?" for every record (~1 ms
  each, ~600 ms for 521 records) even with no saved decisions. With none saved it is skipped; with decisions the
  same lookup runs as before (identity keys are now remembered, file path built without a slow cmdlet). Merge:
  ~740 ms -> ~170-210 ms.
- **What's running:** program details (path, description, company) are kept for the whole session and read once in
  the background after start, instead of reading ~100 program files each time the page opens.
- **Repository:** ARCHITECTURE (5.16: background readers, responsiveness rule, helper cache, live readings off the
  UI thread) and CONTRIBUTING (UI test, Actions run by hand, new rules for slow calls and C# helpers) updated;
  GitHub checked: 0 open issues/PRs, all three branches on the same commit, 12 published releases with assets.

# YUMRAM 5.16.0 — starts 2.5 s faster, uses less CPU in the background

Measured on the test PC against 5.15.9 (same machine, same data):

| | 5.15.9 | 5.16.0 |
|---|---|---|
| Loading the program (every start after the first) | 3.7-4.2 s | **1.4-1.5 s** |
| Overview graph, per redraw (twice a second) | 38 ms | **4 ms** |
| Window thread while the Overview is open | 17 % of a core | **11 %** |
| Whole YUMRAM, Overview open, monitoring on | 26-34 % of a core | **21 %** (1.3 % of the whole CPU) |
| Whole YUMRAM, hidden in the tray, monitoring on | 13 % of a core | **~10 %** (0.6 % of the whole CPU) |

- **Compiled helpers are cached.** Every start compiled the same 11 small C# helpers (each start of the C# compiler
  took 220-430 ms - ~3 s per start). They are now compiled once into `Runtime\TypeCache` inside YUMRAM's folder
  and loaded from there (~10-20 ms each). The name carries a hash of the code, so an update compiles changed helpers
  once; a missing or damaged file falls back to the old compile. Never packaged, kept across updates.
- **The Overview graph** builds its lines in compiled code from number arrays (was a PowerShell object per point).
- **Rings** are only redrawn when their value (0.1 %) or colour changes.
- **CPU cards** are drawn at most once a second (CPU care ticks once a second) and not while YUMRAM is hidden.
- Found while measuring: the first ~40 s after start YUMRAM's background start-up work (workers, caches, preload)
  uses about a third of a core; steady state is the numbers above.

# YUMRAM 5.15.9 — no more "Not responding" after start, much less lag

User report: "program lagging, at first it said not responding, then responded" - "should run with minimal lag to no
lag". Measured with a new freeze meter (a watcher asks the window for an empty job every 50 ms at input priority and
records every wait over 200 ms) on a copy of the test PC's real data, every page opened in turn:

| Moment | 5.15.8 | 5.15.9 |
|---|---|---|
| ~2 s after the window appears (the "Not responding") | 4,742 ms | **232 ms** |
| Every What's running refresh (every 2 s) | up to 716 ms | **under 200 ms** |
| Opening What's running | 1,769 ms | 805 ms |
| Opening Intelligence | 1,408 ms | 1,095 ms |
| Reclaim Center / Settings / Disk cleanup / About | up to 605 ms | under 200 ms |

- **Live readings (CPU, GPU, VRAM, disk) are taken in the background.** Windows opens these counters slowly the first
  time (GPU 1.5 s, CPU 1.1 s, disk/adapters 0.65 s) and that happened on the window thread. A background sampler now
  reads them every ~2 s while the Overview or mini bar is on screen; the window only copies the latest numbers.
- **CPU details (name, laptop/desktop) come from a one-off background query** instead of WMI on the window thread
  (~1 s, asked from two places on the Overview).
- **The Intelligence database is preloaded in the background** shortly after start (0.6-0.7 s with 521 records) and
  is no longer reloaded when Intelligence opens; a preload never replaces a database the window already has.
- **What's running:** CPU time of every process in one system call and main windows in one window walk (was one call
  per process, ~226 here) - the 2-second refresh no longer stutters.
- **Intelligence list:** the record check reuses one defaults table (2x faster, same result) and manual decisions
  are not re-checked on disk ~200 times in a row.
- New **ResponsivenessTest** keeps this work off the window thread (67 tests).

# YUMRAM 5.15.8 — more disk space found, repository brought up to date

- **Disk cleanup 15 -> 18 categories** (researched against BleachBit, CCleaner and Storage Sense; every location
  checked to be a re-creatable cache). On the test PC this finds **0.95 GB more (2.26 -> 3.21 GB)**; measuring takes
  ~0.3 s longer (background, the window does not wait).
  - **Store app temporary files** - only the `AC\Temp` and `AC\INetCache` folders of Microsoft Store apps, files
    older than 24 hours.
  - **Developer download caches** (pip, NuGet, npm, pnpm cache, Yarn, Go build cache) - *your call*: the next build
    downloads/compiles once more. Never projects, installed packages or the pnpm store projects link to.
  - **Old app updater downloads** (Edge / Chrome updaters' installer copies) - administrator, only files older than
    7 days.
  - **App caches** now also cover Steam's logs and crash reports and classic Teams.
  - Deliberately **not** cleaned (researched): `ProgramData\Package Cache` and `Windows\Installer` (needed to repair
    and uninstall programs), Maven/Gradle/Go module stores, Office's document cache (can hold unsynced files).
  - None of the new categories is part of the weekly automatic clean unless you tick them.
- **Repository:** the `YUMRAM.exe` committed in the repo (used when running from a clone or "Download ZIP") was still
  the 5.15.1 launcher without the 5.15.7 updater fix - rebuilt, and a test now fails if it falls behind again. README
  (update check every 15 minutes with automatic install, disk cleanup list) and ARCHITECTURE (GPU memory & network
  module, updater, Windows' own clean-up tools) brought up to date.

# YUMRAM 5.15.7 — automatic updates fixed (found by the first real update)

- **Fix: an automatic update could leave you with no YUMRAM.** First real-world update (5.15.5 -> 5.15.6 on the test
  PC): YUMRAM found, downloaded and verified 5.15.6 and closed its window, but its process stayed alive for over a
  minute (background helper threads). The updater gave up after 60 s with an error box, and Windows' "start without
  asking" task would not start YUMRAM again while the old process was still there - so nothing was running.
  - YUMRAM now **ends its process right after its window closes** (everything is saved by then). Measured: 13 ms.
  - The updater **ends a lingering old YUMRAM after 30 s** instead of giving up, and copes with a process it may not
    inspect (e.g. an administrator YUMRAM watched by a normal updater; that used to crash it).
  - If an update cannot be applied, the updater **starts the installed version again** and logs why - no blocking
    error box, no YUMRAM-less PC. The in-app updater simply tries again later.
- **Real end-to-end test:** a copy of YUMRAM started like a user would, found a local test release, downloaded and
  verified it, gave the 10-second heads-up, closed, was updated and started again as the new version - unattended,
  36 s. The automated update test now also covers a lingering old process, "nothing to wait for" and a broken update.
- Coming from 5.15.4-5.15.6: the new updater (inside the 5.15.7 package) handles the old version's lingering process,
  so the update goes through.

# YUMRAM 5.15.6 — updates as soon as they come out

- **Checks every 15 minutes** (was every 6 hours; GitHub allows ~60 unauthenticated checks an hour from one address,
  so 4 an hour is well inside it) and **installs right away** - only a running game (and YUMRAM's own work: Free RAM,
  an Intelligence scan, a disk clean, Measure games) makes it wait. It no longer waits for "a quiet moment" while you
  use YUMRAM; with the window open it gives a 10-second heads-up first. Settings: "Install new versions as soon as
  they come out".

# YUMRAM 5.15.5 — automatic updates, safer and honest disk cleanup, network speed

- **Real-PC disk cleanup test** (test PC, without administrator, default ticks only): temp files 759 MB, browser
  caches 663 MB, picture previews 141 MB, crash dumps 45 MB, app caches 136 MB - 17,000 files in 35 s. YUMRAM said
  1.7 GB freed, but the Windows drive gained 1.2 GB: Windows lets a program "delete" a file that another program still
  has open (Chrome's cache, Explorer's previews), and that space only returns when the program closes.
- **Fix:** a file is now deleted only when no program has it open (an exclusive open must succeed first); otherwise it
  is skipped as "in use". The reported number now matches the real gain (re-test: reported = real), and open
  programs are never disturbed. New test: a file open the way Chrome opens its cache is skipped, then cleaned once
  closed.
- The confirm box names open programs that hold caches ("Open now: Chrome, Discord, Steam - close them first for the
  biggest result").
- **Safer Temp cleaning** (user: "how do you know you're not deleting important things?"): files a person may have
  opened straight from an e-mail or a zip land in Temp, so documents, pictures, videos, music, archives and key files
  there are never touched, nor the folders Windows unpacks when you open a zip ("Temp1_..."). New test.
- **Spotify left out of app caches:** its folder can hold the songs you downloaded for offline listening.
- **Driver installer folders (C:\AMD, C:\NVIDIA) are "your call"**, not ticked by default - someone could have saved
  their own files there.
- **Look first, see after:** "Open folder - look before cleaning" opens each category's folder (or the Recycle Bin)
  in File Explorer; "See what was deleted" opens the exact list of files the last clean removed (category, file,
  size), written after every clean, automatic ones included.
- **Network speed on the mini bar** (download / upload, all adapters, like IObit's floating monitor), read in the
  background once a second only while the mini bar is shown.
- **Windows Storage Sense status** in Disk cleanup with a link to its settings: Windows' own long-term cleaner (old
  Recycle Bin items, old Downloads by your choice, OneDrive files made online-only) is shown rather than duplicated.

# YUMRAM 5.15.4 — updates install themselves (never published on its own; shipped in 5.15.5)

- **Automatic updates** (user: "whenever an update becomes available it gets updated"). YUMRAM now checks GitHub
  every 6 hours while it runs (was once a day and only at start-up, so a copy living in the tray for days never
  looked again), downloads a new version in the background (the window no longer freezes while downloading),
  checks its SHA-256, and installs it at the first quiet moment: never while a game runs, Free RAM, an Intelligence
  scan, a disk clean or Measure games is working, and not while you are clicking in YUMRAM. YUMRAM restarts the way
  it was (hidden in the tray or the mini bar if it was hidden); settings and data are kept and the previous version
  stays in `.previous` for rollback. On by default; Settings > General > "Install new versions automatically" turns
  it off (then the banner asks, as before). A download that fails is retried later (at most 3 times per session).
- Tests: the end-to-end update test now runs the automatic path (background download + verify + apply + rollback)
  and checks the 6-hour timing, the "never while gaming" rule and the Settings switch.
- Note: copies on 5.15.3 or older still show the banner once; from 5.15.4 on, updates install themselves.

# YUMRAM 5.15.3 — Disk cleanup button fix, deeper disk cleanup, graphics memory (VRAM) help

Compared with 5.15.2 (test PC: Ryzen 7 4800H, RTX 3050 Laptop + Radeon iGPU):

- **Fix: the Disk cleanup sidebar button did nothing** (it was not in the main window's control list; Ctrl+9 worked).
  New test: every sidebar button is registered; the UI probe clicks the real button.
- **Fix (Intelligence): "signer matches publisher" never counted** - the certificate subject was compared against the
  publisher the wrong way round. Now the publisher's distinctive words must be in the certificate's CN / O (generic
  words such as Inc / LLC never match alone). Exact developer-signed packages from a publisher with an installed
  program (Notepad++, WinRAR, AMD shell extensions) are identified. Fresh admin scan: 4 -> 0 Unknown.
- **Disk cleanup 9 -> 15 categories:** app caches (Discord, Spotify, Steam, Epic, Teams, VS Code), graphics driver
  installer leftovers, Windows logs older than 30 days, Windows Update clean-up via `DISM /StartComponentCleanup`
  (no /ResetBase), old driver packages and Windows.old via Windows' own Disk Cleanup handlers (`cleanmgr /sagerun`,
  flags removed afterwards; *your call*). "Restart as administrator" button when categories are locked.
- **Graphics memory (VRAM):** Windows' video memory manager owns VRAM; no program can free another's. YUMRAM now shows
  per-program VRAM and chip in What's running with where to turn hardware acceleration off, can move a background
  program to the power-saving chip on two-chip laptops (Windows' per-app setting, exact undo), warns once per game
  when the gaming chip is >= 90 % full, and lists the biggest users in the GPU tile tooltip. Read in a background
  runspace every 3 s only while needed.
- Clearer Settings labels, About lists the new features, "what is it for" explains Windows building blocks; Startup
  apps no longer shows the previous program's text after the selection is cleared.
- Tests: 66 (new VramTest); UI probe 82 steps.

# YUMRAM 5.15.2 — Intelligence fixes, Disk cleanup, floating mini bar, clearer Overview, plain words everywhere

Compared with 5.15.1 (measured on the test PC: Ryzen 7 4800H, RTX 3050 Laptop + Radeon iGPU):

- **CPU speed, CPU % and GPU now update while monitoring is off** (was "-- GHz", "--" and a frozen GPU).
  The Overview reads cheap Windows counters every 2 s while it is on screen (13-40 ms per read; nothing while
  hidden or on another page).
- **GPU card explained and VRAM added.** "GPU 3D" is now "GPU busy (3D)" with a tooltip (how hard the graphics
  chip's 3D engine works - Task Manager's "3D" graph). VRAM in use / total is shown per graphics chip, because
  laptops have two (busy % can come from the built-in chip while the gaming card idles).
- **Intelligence scan is easy to see:** big status, what is being looked at in plain words ("Now looking at:
  X - looking it up online on trusted sites"), a full-width bar with a percentage, a highlighted frame, and a
  "Scanning / Researching 12/40" bar in the sidebar on every page (click it to open Intelligence).
- **Scan finds everything, 4x faster:** every process, service and Store app (was the first 80 of each, which
  hid small programs like VoiceMeeter) plus classic installed programs (Settings > Apps; never scanned before).
  Signature checks run once per file, 6 at a time. Test PC: 240 items in 39.5 s -> 603 items in 8.9 s.
  Background services that hide their path from a non-admin app are matched to their service file and
  signature-checked: "Unknown" items 46 -> 18.
- **Known programs:** Roblox ("RobloxPlayerBeta" is the normal player), Bloxstrap, VoiceMeeter (all editions),
  VB-Cable, ASUS (Armoury Crate, Fn keys, touchpad, MyASUS parts) and HP (Support Assistant, Insights Analytics,
  HSA helpers, OMEN Gaming Hub, Wolf Security, printer apps) get a plain description and advice. A name alone
  never makes an unverified file trusted (it stays Unknown with a hint). Online research trusts asus.com,
  hp.com, vb-audio.com, roblox.com and other PC / device makers' sites.
- **Intelligence: Open file location** and **Look it up online** for the selected item.
- **One advice vocabulary everywhere:** *Keep* (pink), *Turn off is fine* (green), *Your call* (blue),
  *Careful* (red, not identified), with a legend on Startup apps and Windows bloat and an "Our advice" badge in
  Intelligence and What's running. Startup shows "Turn off (recommended)", "Keep on (required)",
  "Keep on (device)", "Your call"; Windows bloat "Remove (recommended)" / "Turn off (recommended)" / "Your call".
- **Intelligence identifies installed programs again (big fix).** Research read only 3 of the ~265 installed
  programs on the test PC: one program without a version number made a strict-mode error drop the rest of that
  registry hive. On a fresh first scan WinRAR, Git, GPU-Z, CPU-Z, Notepad++, the NVIDIA and Realtek drivers and
  ~40 more ended "Unknown". Fresh first scan on the test PC: **48 -> 21 Unknown, 0 left in Review**; the 21 left are
  hidden system processes whose file a non-admin app cannot read (run as administrator to identify them).
  Installed driver packages from hardware makers are now filed under Drivers / Hardware (advice: Keep).
- **Fix: a second copy of a program could show "Unknown".** When research reused a result found earlier in the
  same scan (a second Chrome / Discord / Steam process), the item inherited the previous item's status.
- **Research 3.75x faster:** 30 items 60 s -> 16 s; a fresh first scan's research ~10 min -> 3.5 min (312 items,
  test PC). Signatures are checked 6 at a time up front, each file is hashed once, the installed-program /
  service / Store / WinGet lists are split into words once per run instead of once per item, and the 4 MB cache
  and live checkpoint are written at most every 2 s instead of after every item.
- **Disk cleanup page (new, Ctrl+9):** like BleachBit / CCleaner, but every category shows its size and a plain
  explanation before anything is removed, and it never touches your files, cookies, saved passwords or browser
  history: temporary files (yours and Windows'), web browser caches (Chrome, Edge, Brave, Opera, Vivaldi,
  Firefox), picture previews, game shader caches (your call), crash dumps and error reports, Windows Update
  downloads older than 10 days, Delivery Optimization (Windows' own command) and the Recycle Bin (your call).
  Junctions / links are never followed, files in use and temp files newer than a day are skipped. Optional
  weekly automatic clean of the safest leftovers (off by default). Test PC: 2.4 GB found without admin
  (+2.5 GB of old Windows Update files with admin).
- **"What's using my disk"** (like WinDirStat / WizTree): biggest folders with share bars (double-click to go
  deeper, Up to go back) and the 50 biggest files, with Open location. YUMRAM never deletes your files there.
- **Fix: Settings > Apply no longer stops** when the administrator choice cannot be changed without admin (it
  used to save nothing else); the reason is shown in amber next to that choice.
- **Overview reorganised** (user: "cluttered, hard to understand"): the top row answers "what is my PC doing
  right now?" with four matching ring tiles - RAM free, CPU, Graphics (GPU) and Disk. Below: the History graph on
  the left and everything you can do on the right (Free RAM, automatic care, game, RAM freed, CPU care, goal).
- **Disk like Task Manager:** busy % (active time) ring, read / write speed, response time, SSD / NVMe / USB,
  free space on the Windows drive with a warning bar (red above 90 % full); per-disk details on hover (~24 ms
  per read).
- **The X button keeps YUMRAM running** in the notification area (or the taskbar when the tray icon is off);
  "Exit YUMRAM" in the tray menu, installing an update and Windows sign-out still quit. Opening YUMRAM again
  brings back the hidden window instead of an "already running" box. Settings: "The X button keeps YUMRAM
  running in the background".
- **Floating mini bar:** a small always-on-top bar (RAM, CPU, GPU, disk + Free RAM / Open / hide-to-tray) you
  can drag anywhere; the position is remembered. Open it from the Overview's "Mini bar" button or the tray
  menu, or make minimize / close use it (Settings). Reads only while visible.
- **"What is it for?"** for every item in Intelligence, What's running and Startup apps: the Windows service
  description or the file's own description, the product and maker, and the device or feature it serves
  ("Used for: sound: your speakers, headphones and microphone", "your touchpad", "the Fn keys", "anti-cheat for
  online games", ...). 70 % of running items on the test PC get a device / feature answer.
- **Plain words everywhere:** Intelligence columns "Our advice" (Keep / Turn off is fine / Your call / Careful)
  and "Checked?" instead of Risk / Status; tiles Identified / Never touched / Not checked yet / Not identified /
  Already known / Will retry. Reclaim Center: "Free for programs", "Taken from idle apps", "Real gain last
  time", plain reasons. Status bar "Live readings" instead of telemetry timings; CPU settings without jargon.
- CPU care while gaming steps in from 50 % whole-PC load (was 70 %): the focused re-test showed games starved
  at 50-55 % total load with nothing held back.
- Costs / trade-offs: the scan uses up to 6 threads for a few seconds; the Intelligence list is longer (all
  items, not 240). The research engine version is now 5.15.2, so items an older version left "Unknown" are
  researched once more (with the fixes above) on the next scan; saved categories update then.
- Tests: 65 (new LiveReadingsTest, IdentifyAndAdviceTest, PurposeAndMiniBarTest, DiskCleanupTest); UI probe 82
  steps (paused readings, rings, disk cleanup, mini bar, X button, advice badge, scan visibility), also run as
  administrator. GitHub Actions workflow is manual-only while the account's billing lock is on.

# YUMRAM 5.15.1 — CPU load reading fix, readable Store publishers, docs

- **Fix: CPU care thought an idle PC was ~100 % busy.** The one-call process snapshot (5.15.0) includes the System
  Idle Process, whose CPU time is idle time. It is no longer counted (found from a screenshot: the CPU care card
  said "PC at 99 %" while the CPU ring showed 11 %). New test: an idle PC must read as idle.
- Startup apps: Store apps show their real publisher (e.g. "Apple Inc." instead of a package ID).
- About page: up-to-date privacy and Startup texts. New `SECURITY.md`; `Docs/ARCHITECTURE.md` rewritten for 5.15;
  README screenshot gallery of every page. UI probe also captures the Startup page.

# YUMRAM 5.15.0 — Windows bloat, audit fixes

- **Windows bloat page** (sidebar, Ctrl+8). *Preinstalled apps*: only apps on a curated list are ever offered
  (Microsoft News, Clipchamp, Solitaire, Office hub, Tips, Feedback Hub, retired apps like Cortana and Skype,
  promoted games…), each marked **Remove** or **Your call** with a plain-word reason. Store, Edge, Terminal,
  Photos, Calculator, Notepad, Paint, Xbox Identity, App Installer, frameworks and non-removable packages are
  never offered. Removal is for your account (no administrator); as administrator also for new user accounts.
  Every removal is listed, and "Get it back" opens its Microsoft Store page. *Settings*: 12 ad / tip /
  suggestion / AI settings (Start suggestions, silent installs of promoted apps, lock-screen and Settings ads,
  Explorer promotions, advertising ID, Bing in Start search, Copilot, Recall, Widgets and minimum diagnostic
  data as whole-PC policies). The exact original value is saved before each change and Undo restores it
  (value **and** type; values that did not exist are deleted again). App scans and removals run off the UI
  thread. Research: Win11Debloat and winutil (both MIT) safety lists and undo model; no code copied.
- **Game CPU benchmark and learning** (`Tools\Bench-CpuCare.ps1`, Settings › CPU › *Measure games on this PC*).
  A test game (N job threads, every frame timed: average FPS, 1 % lows, p99 frame time) runs next to test
  background loads (half the CPU, saturating, bursty) with CPU care Off / Gentle / Balanced / Strong. Results
  are saved as `cpu-knowledge.json`; while a detected game is in front, CPU care uses the level that gave
  clearly better (≥ 10 %, medians of repeated runs) 1 % lows for that kind of game and load on **this** PC. No file = no change.
  CPU care pauses while the benchmark runs. `-Validate` replays the learned cases with adaptation on.
- **CPU care reacts in time under full load.** The benchmark showed it acting 4–14 s late: each check took
  0.6–4.3 s because it asked WMI for every busy program's parent (0.24 s idle, **1.7 s** under load) and opened
  ~250 processes one by one for CPU time (~0.4 s). Now one `NtQuerySystemInformation` call returns CPU time,
  parent, session, start time and memory of every process (**3.9 ms**), leak sampling runs after the
  decisions, and the worker warms up at start (the very first check under load took ~10 s).
- **Make room could fail with an error** in strict mode: records lacked `RoomFailed`/`RoomChecked`/`RoomTicks`/
  `FgBefore`, so the benchmark recorded zero make-room actions. Records are complete now; measured: medium
  test game vs a saturating hog, Off 3.9 FPS → Balanced 150 FPS → Strong 176 FPS (1 % low 102, as with no hog).
- **Startup apps: Store apps and sign-in tasks.** The page listed only Run keys and Startup folders. It now also
  lists Store/MSIX app startup tasks (same per-user switch as Task Manager) and third-party scheduled tasks
  that run when you sign in (turned off, never deleted). Test PC: 16 entries the page had missed, including
  vendor "sale" pop-up tasks. They load in the background so the page opens at once.
- **Review fixes:** every shared-state key a background thread writes now exists from the start (the shared
  dictionary was changing shape while other threads read it); the log rotates at 5 MB; RAM care's candidate
  scoring reuses CPU care's per-second CPU figures instead of a WMI query that took 0.46–0.78 s per call; the
  online-research privacy text now says that up to 4 trustworthy result pages are opened to check an answer
  (it said "nothing else"); uninstall says Windows-bloat settings stay off and how to undo them first.
- **Audit fixes** (see `Docs/AUDIT-AND-RESEARCH-2026-11.md`): automatic care no longer flushes the modified
  page list (file-cache assist at most every 10 min); automatic care closes listed apps only if you opt in;
  stale-PID guard before trimming; Free RAM busy-state race fixed.
- Tests: `WindowsBloatTest` (catalog safety, matching, removal with a stand-in remover, exact undo on a test
  registry key), `Release515Test`; UI probe opens the new page (60/60 steps).
# YUMRAM 5.14.0 — Beta: big programs trimmed in chunks, clearer graph, "applied" confirmations

YUMRAM is now **beta**.

- **Goal reached even when one program is huge.** Automatic care never trimmed a program bigger than its
  per-pass budget (Balanced 2 GB), so one large browser tab — measured here: a 2.7 GB Chrome renderer, the
  top-ranked candidate — was skipped forever. Small programs were trimmed, refilled within a minute, and a
  reachable 6 GB goal sat at 4.6–5.5 GB. Now such a program is trimmed **in chunks** (only what the budget
  and the gap allow, once a minute at most) with a soft working-set limit. **Measured on this PC:** the tab
  went 2,931 → 1,332 MB and Available RAM 4.9 → 5.8 GB. Free RAM now / Deep reclaim still trim in full.
- **CPU care no longer pauses or misleads RAM care.** (1) RAM care skipped every pass while total CPU was
  ≥ 90 %; a background program CPU care had already slowed down still filled idle CPU, so RAM care stopped
  for as long as it ran. CPU used by held-back programs no longer counts. (2) A program CPU care lowered to
  Below Normal / Idle got a "low priority = idle" trim bonus, although it is busy and its memory faults
  straight back — that bonus is gone for programs CPU care holds back.
- **Graph: two lanes instead of four crossing lines.** Top: Available RAM with your goal as a dashed line
  (below the line = below goal). Bottom: CPU and GPU. Available and RAM-in-use mirrored each other and
  crossed near 50 %; CPU and GPU sat on top of each other. Gaps in the history now show as gaps instead of
  long straight lines. Same in 30 s, 5 min, 1 h and 12 h.
- **"Applied" confirmations.** A short pop-up confirms the memory goal ("Memory goal set to 6 GB", with a
  warning when it is above what is reachable now), Settings › Apply and Mode changes.
- Tests: new `Release514Test` (chunked plan + a real 1.6 GB test program trimmed by ~600 MB with no hard
  limit left, CPU-care rules, graph, confirmations, beta).
# YUMRAM 5.13.0 — Report a problem, safer uninstall, working issue forms

- **Report a problem** (About page and tray menu): opens GitHub's bug form in the browser, filled in with
  the YUMRAM version, administrator mode, Windows version, CPU, RAM, laptop/desktop and the last 30 log lines.
  Your user name, PC name, user-folder paths and e-mail addresses are replaced before anything leaves YUMRAM.
  Nothing is posted until you press Create on GitHub (a GitHub account is needed). Titles start with
  `[From app]` so these reports are easy to find.
- **Issue forms fixed.** The bug-report and feature-request forms had a YAML error, so GitHub hid them and
  (with blank issues off) nobody but the owner could open an issue. Rewritten and checked.

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

