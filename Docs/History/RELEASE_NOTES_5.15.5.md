## YUMRAM 5.15.5 — updates install themselves, safer and honest Disk cleanup

Everything since **5.15.3** (5.15.4 was never published on its own; it is included here). Measurements are from the
test PC (Ryzen 7 4800H laptop, RTX 3050 + Radeon graphics, 16 GB RAM, Windows 11).

### Updates install themselves
- **Checks every 6 hours** while YUMRAM runs (before: only at start-up, at most once a day — a copy living in the tray
  for days never looked again).
- **Downloads in the background** (no frozen window) and checks the SHA-256 against the published one.
- **Installs at a quiet moment:** never while a game runs, while Free RAM, an Intelligence scan, a disk clean or
  *Measure games* is working, or while you are clicking around in YUMRAM. The banner says what it is waiting for.
- **Comes back the way it was** (hidden in the tray or the mini bar if it was hidden). Settings and data are kept; the
  previous version stays in `.previous` for rollback.
- **On by default** — Settings › General › *Install new versions automatically* turns it off.

### Disk cleanup: honest numbers
- A real test on the test PC freed 17,000 files (temp files 759 MB, browser caches 663 MB, picture previews 141 MB,
  crash dumps 45 MB, app caches 136 MB). YUMRAM said 1.7 GB, but the drive gained 1.2 GB: Windows lets a program
  "delete" a file that another program (Chrome, Explorer) still has open, and that space only returns when that
  program closes.
- **Fixed:** a file is now deleted only if no program has it open; otherwise it is skipped as "in use". Re-test:
  reported = real gain. Open programs are never disturbed.
- The confirm box names open programs holding caches ("Open now: Chrome, Discord, Steam — close them first for the
  biggest result").

### Disk cleanup: never your things
- **Temp folder:** documents, PDFs, pictures, videos, music, archives and key files are never touched there (you may
  have opened them straight from an e-mail), nor the folders Windows creates when you open a zip ("Temp1_…").
- **Spotify left out:** its folder can hold the songs you downloaded for offline listening.
- **Driver installer folders (C:\AMD, C:\NVIDIA)** are *your call*, not ticked by default.
- **Open folder — look before cleaning** opens a category's folder (or the Recycle Bin) in File Explorer.
- **See what was deleted** opens the exact list of files the last clean removed (category, file, size).
- **Windows Storage Sense** status and a link to its settings — Windows' own long-term cleaner (old Recycle Bin items,
  old Downloads by your choice, OneDrive files made online-only) is shown rather than duplicated.

### Mini bar
- **Network speed** (download / upload, all adapters) next to RAM, CPU, GPU and disk — read in the background only
  while the mini bar is shown.

### Tested
- 66 automated tests (new cases: files open by another program are skipped; documents in Temp survive; the
  deleted-files list is written; network speed is read in the background) and the 82-step UI test. The end-to-end
  update test runs the automatic path (background download, verify, apply, rollback).

### Install / update
- **From 5.15.3 or older:** the update banner appears one last time — press *Install and restart*. After that,
  updates install themselves.
- New install: `YUMRAM-Setup-5.15.5.exe` (per-user, no administrator needed) or `YUMRAM-5.15.5.zip`.
  `SHA256SUMS.txt` lists both checksums.
