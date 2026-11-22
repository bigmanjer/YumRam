## YUMRAM 5.16.2 - looks like YUMRAM, temperatures, cleaner labels, Disk cleanup "Select all"

### Looks like YUMRAM, not PowerShell
YUMRAM runs inside Windows PowerShell, so Windows showed PowerShell's blue icon in the title bar and on the taskbar,
grouped YUMRAM with PowerShell windows, and "Pin to taskbar" pinned PowerShell. Now:
- YUMRAM's own icon in the title bar and on the taskbar.
- Its own taskbar button; pinning it pins YUMRAM.
- A dark title bar in YUMRAM's colours instead of the Windows accent colour (Windows 11; Windows 10 gets a dark title bar).

### Temperatures
Shown top-right on the CPU, Graphics and Disk cards, in green / amber / red:
- **CPU area** - from Windows' own thermal sensor reading.
- **NVIDIA graphics** - from the NVIDIA driver, only while the chip is awake. A resting laptop GPU shows "asleep":
  YUMRAM never wakes it just to read a temperature (that would cost battery).
- **Disks** - from Windows' drive health data, when YUMRAM runs as administrator (some drives do not report it).

No extra drivers are installed for this. Tools that read CPU sensors directly install kernel drivers, and the most
common one (WinRing0) is now flagged by Windows as vulnerable.

### Cleaner look
The rounded "bubble" labels (On target, Watching, Active, Balanced, Paused...) are now plain coloured text, and the
advice tags in lists are small rectangles.

### Disk cleanup
- **Select all**: ticks every category that can be cleaned (click again to untick all). You still see and confirm
  the total before anything is removed.
- **Fixed:** a tick could disappear from the screen when you scrolled the list.

### Tested
67 automated tests and the UI test (new: Select all and ticks that survive scrolling), plus a look at the real
window on the test PC: title bar, taskbar button, temperatures, labels, Select all and scrolling.

### Install / update
- From 5.15.4 or newer: installs itself within about 15 minutes (never while you play).
- New install: `YUMRAM-Setup-5.16.2.exe` or `YUMRAM-5.16.2.zip`; `SHA256SUMS.txt` lists both checksums.