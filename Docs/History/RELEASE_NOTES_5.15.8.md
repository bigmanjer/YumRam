## YUMRAM 5.15.8 - more disk space found, repository brought up to date

### Disk cleanup: 15 -> 18 categories
Researched against BleachBit, CCleaner and Windows Storage Sense; every new location was checked to be a cache that
rebuilds itself. On the test PC Disk cleanup now finds **0.95 GB more (2.26 GB -> 3.21 GB)**. Measuring takes about
0.3 s longer; it runs in the background, so the window never waits.

- **Store app temporary files** - only the `Temp` and web-cache folders of Microsoft Store apps (Photos, Widgets,
  Xbox...), files older than 24 hours. Never the apps' data or settings.
- **Developer download caches** (pip, NuGet, npm, pnpm cache, Yarn, Go build cache) - *your call*: the next build
  downloads or compiles those packages once more. Never your projects, installed packages or the pnpm store your
  projects link to. Only shown if you have these tools.
- **Old app updater downloads** (Microsoft Edge / Google Chrome updaters' installer copies) - administrator, only
  files older than 7 days, the browsers themselves are not touched.
- **App caches** now also cover Steam's log files and crash reports, and classic Microsoft Teams.

Deliberately **not** cleaned (researched): `ProgramData\Package Cache` and `Windows\Installer` - Windows needs them to
repair and uninstall programs - and Maven / Gradle / Go module stores. As before: sizes and a plain explanation
first, *Open folder* to look, a list of every deleted file afterwards, files in use and recent files skipped.
**None of the new categories joins the weekly automatic clean** unless you tick it.

### Repository
- The `YUMRAM.exe` committed in the repository (used when you run YUMRAM from a clone or GitHub's "Download ZIP")
  was still the 5.15.1 launcher, without the 5.15.7 updater fix. Rebuilt; a test now fails if it falls behind again.
  (The installer and zip packages always build a fresh one, so release users were not affected.)
- README (update check every 15 minutes with automatic install; disk cleanup list) and ARCHITECTURE (GPU memory &
  network module, updater, Windows' own clean-up tools) brought up to date.

### Tested
66 automated tests (with new safety checks: no installer caches, no package stores, Store apps limited to their
Temp/web-cache folders, new categories not in the automatic clean) and the 82-step UI test.

### Install / update
- From 5.15.4 or newer: installs itself within about 15 minutes (never while you play).
- New install: `YUMRAM-Setup-5.15.8.exe` or `YUMRAM-5.15.8.zip`; `SHA256SUMS.txt` lists both checksums.
