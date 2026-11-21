## YUMRAM 5.15.6 — updates as soon as they come out

### Updates
- **Checks for a new version every 15 minutes** while YUMRAM runs (was every 6 hours). GitHub allows about 60 checks an
  hour from one PC without signing in, so 4 an hour is well inside that.
- **Installs right away.** It no longer waits for "a quiet moment". Only these make it wait:
  - **a game is running** - it installs after you stop playing;
  - YUMRAM itself is in the middle of a job (Free RAM, an Intelligence scan, a disk clean, *Measure games*) - a few
    seconds, so nothing is left half-done.
- **Heads-up:** if the YUMRAM window is open you see "Updating YUMRAM to … in a few seconds" for 10 seconds first. If it
  is hidden in the tray, it updates quietly and comes back hidden.
- As before: the download is checked with SHA-256, your settings and data are kept, and the previous version stays in
  `.previous` for rollback. Settings › General › *Install new versions as soon as they come out* turns it off.

### Tested
- The end-to-end update test checks the 15-minute timing, that a running game blocks installing, the background
  download and verification, applying and rolling back. 66 automated tests and the 82-step UI test pass.

### Install / update
- **From 5.15.4 or 5.15.5:** nothing to do - it installs itself.
- **From 5.15.3 or older:** press *Install and restart* on the update banner once.
- New install: `YUMRAM-Setup-5.15.6.exe` (per-user, no administrator needed) or `YUMRAM-5.15.6.zip`.
  `SHA256SUMS.txt` lists both checksums.
