## YUMRAM 5.15.10 - starts about 2.5 s faster, uses less CPU in the background

Continuing the lag work from 5.15.9. Measured on the test PC against 5.15.9 (same machine, same data):

| | 5.15.9 | 5.15.10 |
|---|---|---|
| Loading the program (every start after the first) | 3.7-4.5 s | **1.4-2.2 s** |
| Window up and responding (busy PC) | 7.5 s | **5.2 s** |
| Overview graph, per redraw (twice a second) | 38 ms | **4 ms** |
| YUMRAM's window thread while the Overview is open | 17 % of a core | **11 %** |
| All of YUMRAM, Overview open, monitoring on | 26-34 % of a core | **21 %** (1.3 % of the whole CPU) |
| All of YUMRAM, hidden in the tray, monitoring on | 13 % of a core | **~10 %** (0.6 % of the whole CPU) |

### What changed
- **YUMRAM no longer recompiles its helpers on every start.** It contains 11 small C# helpers (memory, CPU care,
  tray, hotkey, graph...). Every start compiled all of them again - each run of the C# compiler took 220-430 ms,
  about 3 s per start. They are now compiled once into `Runtime\TypeCache` inside YUMRAM's own folder and loaded
  from there (10-20 ms each). The file name includes a fingerprint of the code, so an update that changes a helper
  compiles it once again; a missing or damaged file simply falls back to the old way. The first start after
  installing or updating is as slow as before; every start after that is faster.
- **The Overview graph** builds its lines in compiled code (it was a PowerShell object per point, 180 per redraw).
- **The rings** are only redrawn when their number or colour changes.
- **The CPU cards** are drawn at most once a second (CPU care updates once a second) and not while YUMRAM is hidden.

### Measured, not changed yet (honest list)
- For about 40 s after start, YUMRAM's background start-up work (workers, caches, preloading) uses about a third of
  one core; after that the numbers above apply.
- Opening What's running (~0.8-1.1 s) and Intelligence (~1.1-1.3 s) the first time still takes a moment.

### Tested
67 automated tests (the responsiveness test now also checks the helper cache: loading from it, a new build after a
code change, and that a damaged file never breaks YUMRAM) and the 82-step UI test.

### Install / update
- From 5.15.4 or newer: installs itself within about 15 minutes (never while you play).
- New install: `YUMRAM-Setup-5.15.10.exe` or `YUMRAM-5.15.10.zip`; `SHA256SUMS.txt` lists both checksums.