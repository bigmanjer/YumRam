## YUMRAM 5.15.3 — Disk cleanup button fix, deeper disk cleanup, graphics memory (VRAM) help

Everything that changed since **5.15.2**. Measurements are from the test PC (Ryzen 7 4800H laptop, RTX 3050 + Radeon
graphics, 16 GB RAM, Windows 11).

### Fixes
- **The Disk cleanup button in the sidebar did nothing** (Ctrl+9 worked). It was never connected. Fixed, and a new
  test now checks that every sidebar button is connected; the full UI test clicks the real button.
- **Intelligence: "signer matches publisher" never counted.** The check compared the long certificate text with the
  short publisher name the wrong way round, so a valid signature from the program's own maker was never used as
  proof. Now the publisher's own words must appear in the certificate's company name (generic words like "Inc" or
  "LLC" are ignored, so they can never match by themselves).
- **Shell-extension packages** of installed programs (Notepad++, WinRAR, AMD) are identified instead of "Unknown".
  Fresh scan as administrator on the test PC: **4 → 0 Unknown** (48 before 5.15.2).
- Startup apps: no leftover explanation of the previous program after the selection is cleared.

### Disk cleanup: 9 → 15 categories
- **App caches** — Discord, Spotify, Steam, Epic Games, Teams and VS Code (caches only — never messages, logins,
  playlists, games or settings).
- **Graphics driver installer leftovers** — the unpacked NVIDIA / AMD installers (`C:\NVIDIA`, `C:\AMD`) and old
  NVIDIA driver downloads. The installed driver is not touched.
- **Old Windows log files** (older than 30 days; administrator).
- **Windows Update clean-up** — Microsoft's own component store cleanup (`DISM /StartComponentCleanup`, *without*
  `/ResetBase`, so installed updates can still be uninstalled). Administrator; takes a few minutes.
- **Old driver packages** and **the previous Windows installation (Windows.old)** — *your call*; done by Windows' own
  Disk Cleanup (the documented `cleanmgr /sagerun` automation; YUMRAM removes its settings again afterwards).
- **Restart as administrator** button when some categories are locked (uses your "start without asking" setup if you
  have it).
- Same safety rules as before: sizes and plain explanations first, nothing personal, links never followed, files in
  use skipped — checked by tests.

### Graphics memory (VRAM)
Research result: Windows' own video memory manager controls all graphics memory, and no program can free another
program's VRAM. So YUMRAM does what really helps:
- **What's running shows how much VRAM each program holds and on which graphics chip**, and says exactly where to turn
  off that program's hardware acceleration (Chrome/Edge/Brave/Opera/Firefox, Discord, Steam, Spotify, Teams, VS Code,
  Wallpaper Engine).
- **Laptops with two graphics chips:** one click moves a background program to the power-saving chip using Windows'
  own per-app graphics setting, so its VRAM stays off your gaming chip. Undo puts the previous value back exactly.
- **While you play:** if the gaming chip's VRAM is 90 % full or more, one notice names the background programs holding
  it and what to do.
- The Overview's GPU tile tooltip lists the biggest users of graphics memory.
- Read in the background every 3 s, only while someone is looking (or a game runs).

### Clearer words
- Settings: "Extra margin above the goal", "Rest time for each program", "Starts at % RAM used / Programs per round",
  a plain Intelligence scanner option; the read-only cleanup target box is gone. The administrator hint now says
  what it is needed for (Deep reclaim, Windows files in Disk cleanup, hidden system programs).
- About lists Disk cleanup, live readings, the mini bar and "what is it for".
- "What is it for?" explains Windows building blocks (UI.Xaml, .NET, VC++ runtimes): other apps need them.

### Tested
- 66 automated tests (new: VRAM) and the 82-step full UI test, which now clicks the sidebar buttons.

### Install / update
- In YUMRAM: the update banner offers *Install and restart* (verified with SHA-256). Settings are kept.
- New install: `YUMRAM-Setup-5.15.3.exe` (per-user, no administrator needed) or `YUMRAM-5.15.3.zip`.
  `SHA256SUMS.txt` lists both checksums.
