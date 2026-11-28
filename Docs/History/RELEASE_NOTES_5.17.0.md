## YUMRAM 5.17.0 - Uninstall programs

### New: Uninstall programs (sidebar, Ctrl+0)
Like IObit Uninstaller or Revo, inside YUMRAM:
- Every program and Store app on the PC with its **size** and **install date**, biggest first. Search by name or
  publisher, sort by size, name or date.
- Plain advice per program: **Careful** for drivers, hardware tools, runtimes and codecs that other programs need;
  **Your call** for everything else (with a note for anti-cheat and antivirus).
- **Uninstall** runs the program's own uninstaller. Windows asks for approval when the program needs administrator
  rights.
- **Leftovers**: afterwards YUMRAM finds what the uninstaller left behind - folders, shortcuts and registry settings
  with the program's exact name - and shows their size. You choose what goes:
  - folders and shortcuts go to the **Recycle Bin** (you can get them back);
  - registry settings are saved to a `.reg` backup first (double-click it to put them back);
  - folders that may hold your own files (AppData settings) are not ticked;
  - shared folders, folders other programs use and folders with a program running in them are never offered.

### How to check the download
Compare the SHA-256 of `YUMRAM-Setup-5.17.0.exe` with `SHA256SUMS.txt`. The installer is not code-signed yet, so
SmartScreen may say "Windows protected your PC" - choose More info > Run anyway.