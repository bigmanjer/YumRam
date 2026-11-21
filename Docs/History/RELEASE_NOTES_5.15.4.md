## YUMRAM 5.15.4 — updates install themselves

From this version on, you never have to install a YUMRAM update by hand again.

### Automatic updates
- **Checks every 6 hours** while YUMRAM runs. Before, it only checked when it started (at most once a day), so a copy
  running in the tray for days never looked again.
- **Downloads in the background** — the window no longer freezes while downloading — and checks the download's
  SHA-256 against the published one before anything is used.
- **Installs at a quiet moment:** never while a game runs, while Free RAM, an Intelligence scan, a disk clean or
  *Measure games* is working, or while you are clicking around in YUMRAM. The banner says what it is waiting for.
- **Comes back the way it was:** if YUMRAM was hidden in the tray (or the mini bar) it restarts hidden. A tray note
  says it is updating.
- **Nothing is lost:** settings, statistics and learned data are kept, and the previous version stays in `.previous`
  so it can be rolled back.
- **On by default.** Settings › General › *Install new versions automatically* turns it off — then the banner asks
  you, as before. A download that fails is retried later.

### Tested
- The end-to-end update test runs the automatic path for real: it builds a release package, downloads and verifies
  it in the background, applies it to a test copy, rolls back, and checks that user data is untouched, that a
  running game blocks installing, the 6-hour timing and the Settings switch. 66 automated tests and the 82-step UI
  test pass.

### Install / update
- **Coming from 5.15.3 or older:** the update banner appears one last time — press *Install and restart*. After
  that, updates install themselves.
- New install: `YUMRAM-Setup-5.15.4.exe` (per-user, no administrator needed) or `YUMRAM-5.15.4.zip`.
  `SHA256SUMS.txt` lists both checksums.
- Also in 5.15.3 (released just before): Disk cleanup button fix, 15 disk cleanup categories, graphics memory (VRAM)
  help, and better program identification — see the 5.15.3 release.
