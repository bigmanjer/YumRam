## YUMRAM 5.15.7 — automatic updates fixed (found by the first real update)

### What went wrong in the first real update
On the test PC, 5.15.5 found 5.15.6 by itself, downloaded and verified it and closed its window to install it — but
its process stayed alive (for 30+ minutes, it turned out), the updater gave up after 60 seconds with an error box,
and Windows' "start YUMRAM without asking" task refused to start YUMRAM again while the old process existed.
Result: no YUMRAM running.

### Fixed
- **YUMRAM ends its process right after its window closes** (everything is saved by then). Measured: 13 ms after
  the window closed (before: still alive after 30+ minutes).
- **The updater ends a stuck old YUMRAM after 30 seconds** instead of giving up, and no longer crashes when it may not
  inspect the old process (e.g. an administrator YUMRAM watched by a normal updater).
- **An update that cannot be applied never leaves you without YUMRAM:** the updater starts the installed version
  again and logs why — no blocking error box. YUMRAM tries the update again later.
- **Coming from 5.15.4 – 5.15.6:** the new updater inside this package handles the old version's stuck process, so
  this update goes through.

### Tested for real
- A copy of YUMRAM, started like a user starts it, found a local test release, downloaded and verified it, showed the
  10-second heads-up, closed (process gone in 13 ms), was updated and started again as the new version —
  unattended, in 36 seconds.
- The installer was run over the test PC's real install (5.15.5 → 5.15.7): settings kept, YUMRAM started again as
  administrator through the "start without asking" task.
- The automated update test now also covers: a stuck old process (ended after the wait, update applied in under
  30 s), "nothing to wait for", and a broken update (installed version untouched, logged). 66 automated tests and
  the 82-step UI test pass.

### Install / update
- From 5.15.4 or newer: installs itself (within about 15 minutes; never while you play).
- From 5.15.3 or older: press *Install and restart* on the update banner once.
- New install: `YUMRAM-Setup-5.15.7.exe` or `YUMRAM-5.15.7.zip`; `SHA256SUMS.txt` lists both checksums.
