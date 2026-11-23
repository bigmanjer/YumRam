## YUMRAM 5.16.4 - "What's using my disk" really works, anti-stutter while gaming

### What's using my disk (Disk cleanup page)
It used to show nothing at all while it measured - a whole drive took over a minute - and only about two rows fit.
Now:
- The folders appear right away and each one gets its size as soon as it is measured, biggest first, with progress
  ("15 of 18 folders done").
- **Scan** becomes **Stop** while it runs; double-click a folder or press Up to look elsewhere at any time.
- The last result is remembered, so the next time you open the page it is already there.
- More room and one line per folder, so you see more at once. "Biggest files" lists the 50 largest files below it.

### Anti-stutter while I play (new, off by default)
Settings > Gaming > "Anti-stutter while I play". Like ISLC: while a game runs, when free memory is below 1 GB and
Windows' standby cache is above 1 GB, YUMRAM empties the standby cache (at most every 30 seconds). Some games
stutter when Windows is slow to hand out memory; this helps those. Needs YUMRAM to run as administrator. The work
happens in the background - YUMRAM itself never pauses.

### Compared with other tools
`Docs/COMPETITIVE-REVIEW.md` lists where YUMRAM is ahead (one tool for RAM, CPU, startup, bloat, disk and readings;
honest re-measured results; never touches protected programs, games or tuning tools; no drivers) and what is still
open (signed program / WinGet, command-line actions, uninstalling programs).

### Tested
67 automated tests and the UI test, plus checks on the test PC's screen and an administrator test of anti-stutter.

### Install / update
- From 5.15.4 or newer: installs itself within about 15 minutes (never while you play).
- New install: `YUMRAM-Setup-5.16.4.exe` or `YUMRAM-5.16.4.zip`; `SHA256SUMS.txt` lists both checksums.