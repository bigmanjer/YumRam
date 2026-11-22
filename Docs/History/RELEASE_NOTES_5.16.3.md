## YUMRAM 5.16.3 - "Select all" really ticks everything

### Fixed
- **Disk cleanup "Select all"** now ticks every category. In 5.16.2 it skipped categories that had nothing to clean
  at that moment (for example Crash dumps, Graphics driver installer leftovers or the Recycle Bin), so it looked like
  it did not work. Only categories that need administrator stay unticked while YUMRAM is not running as administrator.
  You still see and confirm the total before anything is removed.
- **Startup apps** no longer show your Windows account's security ID in some names (`GHelper_S-1-5-21-...` is now
  just `GHelper`). Turning the item on or off still works exactly as before.
- A little more space between "Clean selected" and "Select all"; the About page mentions temperatures.

### Checked
Every page was rendered and looked at, and the automated UI test now checks the real tick boxes on screen while
scrolling through the Disk cleanup list (it fails on 5.16.2 and passes on 5.16.3). 67 automated tests pass.
README pictures show 5.16.3.

### Install / update
- From 5.15.4 or newer: installs itself within about 15 minutes (never while you play).
- New install: `YUMRAM-Setup-5.16.3.exe` or `YUMRAM-5.16.3.zip`; `SHA256SUMS.txt` lists both checksums.