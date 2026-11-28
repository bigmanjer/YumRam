## YUMRAM 5.17.1 - Disk cleanup progress bar

### Disk cleanup: you can see it working, and when it is done
- A **progress bar** in the "Safe to clean" header shows which category is being cleaned, how many are done, how
  much has been freed so far and how long it has been running. Windows' own tools (which can take a few minutes) say
  so.
- When the clean ends the bar turns **green: "Finished - freed X"**. The list is then **measured again by itself**
  and the bar says "List updated" with how long the clean took. "Check again" hides it.

Also in 5.17.0: **Uninstall programs** (sidebar, Ctrl+0) - every program and Store app with size, date and plain
advice; runs the program's own uninstaller and then cleans up what it left behind (Recycle Bin, registry backed up).

### How to check the download
Compare the SHA-256 of `YUMRAM-Setup-5.17.1.exe` with `SHA256SUMS.txt`. The installer is not code-signed yet, so
SmartScreen may say "Windows protected your PC" - choose More info > Run anyway.