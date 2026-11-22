## YUMRAM 5.15.9 - no more "Not responding" after start, much less lag

You said YUMRAM lagged and showed "Not responding" right after it started, and that it should run with little to no
lag. I measured it with a freeze meter (a watcher asks YUMRAM's window for an empty job every 50 ms, at the same
priority as mouse and keyboard, and records every wait over 200 ms) on a copy of the test PC's real data, opening
every page in turn. Same meter, same data, before and after:

| Moment | 5.15.8 | 5.15.9 |
|---|---|---|
| About 2 s after the window appears (the "Not responding") | 4,742 ms | **232 ms** |
| Every What's running refresh (every 2 s) | up to 716 ms | **under 200 ms** |
| Opening What's running | 1,769 ms | 805 ms |
| Opening Intelligence | 1,408 ms | 1,095 ms |
| Reclaim Center, Settings, Disk cleanup, About | up to 605 ms | under 200 ms |

### What was slow and what changed
- **Live readings (CPU, GPU, VRAM, disk) now come from the background.** Windows opens these counters slowly the
  first time (GPU 1.5 s, CPU 1.1 s, disk 0.65 s) and YUMRAM did that on its window thread - that was the freeze after
  start. A background reader now takes them every ~2 s while the Overview or mini bar is on screen; the window just
  shows the latest numbers. Nothing is read while YUMRAM is hidden.
- **CPU details** (name, laptop or desktop) come from a one-off background query instead of making the window wait.
- **The Intelligence database is loaded in the background** shortly after start, so What's running and Intelligence
  open without loading it (0.6-0.7 s on the test PC). It is no longer reloaded each time Intelligence first opens.
- **What's running** reads the CPU time of every program in one system call and finds program windows in one pass
  (it used to ask Windows once per process - about 226 times every 2 seconds).
- **Intelligence list** checks are about twice as fast, with exactly the same results.

### Still to improve (honest list)
- The window takes ~2 s to appear at start (building it, before it is shown - not a freeze of a visible window).
- Opening What's running and Intelligence still takes 0.8-1.1 s the first time (reading program details).

### Tested
67 automated tests - including a new **ResponsivenessTest** that keeps this work off the window thread - and the
82-step UI test.

### Install / update
- From 5.15.4 or newer: installs itself within about 15 minutes (never while you play).
- New install: `YUMRAM-Setup-5.15.9.exe` or `YUMRAM-5.15.9.zip`; `SHA256SUMS.txt` lists both checksums.
