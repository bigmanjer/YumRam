## YUMRAM 5.16.1 - Overview graph fixed, overclock/undervolt tools left alone, pages open faster

### Fixed: the Overview graph was empty in 5.16.0
When I sped up the graph in 5.16.0, one line of code was lost. The graph then failed on every redraw and the error
was caught silently, so the History graph stayed empty. Found while re-taking the README pictures. The automated UI
test now checks that the graph really draws its lines, so this cannot slip through again.

**Correction to the 5.16.0 notes:** "graph 38 -> 4 ms" and "window thread 17 % -> 11 %" were measured while the graph
was failing. Measured again with the fix: the graph takes **~13 ms** per redraw (5.15.9: 38 ms); YUMRAM's window
thread with the Overview open is about the same as in 5.15.9. The faster start and lower CPU while hidden in the
tray (5.16.0) do not involve the graph and are unchanged.

### Your overclock and undervolt stay yours
YUMRAM never changes clock speeds, voltages, power limits, fan curves or power plans - it only reads the CPU speed to
show it. New in 5.16.1: the tools that apply those settings are never trimmed (automatic RAM care, Free RAM) and never
held back (CPU care), whatever the settings say: MSI Afterburner and RTSS, AMD Ryzen Master, AMD Radeon Software,
NVIDIA app, ThrottleStop, Intel XTU, EVGA Precision, ASUS GPU Tweak and Armoury Crate, Lenovo Legion Toolkit, OMEN,
Alienware and MSI Center, FanControl, HWiNFO and others.

### Fixed: a strange entry in Settings > CPU > "Never hold back"
On some PCs this box showed `system.collections.specialized.ordereddictionary`. A list in YUMRAM's settings file
could lose its shape when loaded and then showed up as that text (and pressing Apply saved it as an entry). It was
harmless - no program has that name - but wrong. Lists now keep their shape, and YUMRAM removes such entries by itself.

### Faster pages
| Opening (test PC, real data) | 5.16.0 | 5.16.1 |
|---|---|---|
| Intelligence (first time) | 1.1-1.3 s | **0.6 s** |
| What's running | 0.8-1.1 s | **0.7 s** |
| Window up and responding after start | ~5 s | **3.3 s** |

- Intelligence no longer looks up "your manual decision" for each of its ~500 programs when you have none saved.
- What's running reads each program's details once per session, in the background after start.

### Repository
- New README pictures of 5.16.1 (now with Disk cleanup), taken from the real app by `Tools\Capture-Screenshots.ps1`,
  which hides the Windows user and computer name.
- ARCHITECTURE and CONTRIBUTING describe 5.16; checked on GitHub: no open issues or pull requests, all branches on
  the same commit, every release has its files.

### Tested
67 automated tests and the 84-step UI test (new: the graph draws; tuning tools are never held back; saved manual
decisions are still found; the program-details cache).

### Install / update
- From 5.15.4 or newer: installs itself within about 15 minutes (never while you play).
- New install: `YUMRAM-Setup-5.16.1.exe` or `YUMRAM-5.16.1.zip`; `SHA256SUMS.txt` lists both checksums.