## YUMRAM 5.15.2 — easier to understand, smarter Intelligence, new Disk cleanup

Everything that changed since **5.15.1**, in plain words. Measurements are from the test PC (Ryzen 7 4800H laptop,
RTX 3050 + Radeon graphics, 16 GB RAM, Windows 11).

### Highlights
- **New Disk cleanup page** — frees space from caches and leftovers that rebuild themselves, shows the size of
  everything *before* anything is removed, and never touches your files, cookies, saved passwords or history.
- **"What's using my disk"** — biggest folders and files, like WinDirStat.
- **Intelligence identifies far more** — a bug hid almost every installed program from research; fixed.
  Fresh first scan: **48 → 21 "Unknown", nothing left "under review"**, and research is **3.75× faster**.
- **"What is it for?"** — every program, service and startup item now says which device or feature it is for.
- **Clearer Overview** — four matching rings at the top: RAM, CPU, Graphics (GPU) and Disk.
- **Floating mini bar** and **the X button keeps YUMRAM running** in the background.
- **Plain words everywhere** and one advice vocabulary on every page: *Keep*, *Turn off is fine*, *Your call*,
  *Careful*.

### Intelligence (what is everything on my PC?)
- **Big fix: installed programs are identified again.** Research could read only 3 of the ~265 installed
  programs (one program without a version number made an error drop the rest of the list). WinRAR, Git, GPU-Z,
  CPU-Z, Notepad++, the NVIDIA and Realtek drivers and ~40 more ended "Unknown". Fixed, with a regression test.
- **Fix:** a second copy of a program (another Chrome / Discord / Steam process) could show "Unknown" because it
  inherited the previous item's result.
- **Research 3.75× faster:** a first scan's research went from about 10 minutes to 3.5 (312 items). Signatures
  are checked 6 at a time, each file is hashed once, and the 4 MB cache is no longer rewritten after every item.
- **The scan sees everything:** every process, service and Store app (was only the first 80 of each) plus
  classic installed programs. 240 items in 39.5 s → 603 items in 8.9 s.
- **What is it for?** The details panel explains the device or feature: "Used for: your touchpad",
  "the Fn keys", "sound: your speakers, headphones and microphone", "anti-cheat for online games", ...
- **Known programs:** Roblox (RobloxPlayerBeta is the normal player), Bloxstrap, VoiceMeeter, VB-Cable, ASUS
  (Armoury Crate, Fn keys, touchpad, MyASUS) and HP (Support Assistant, Insights Analytics, OMEN Gaming Hub, Wolf
  Security, printer apps). A matching name alone never makes an unverified file trusted.
- Driver packages from hardware makers are filed under **Drivers / Hardware** (advice: Keep).
- **Open file location** and **Look it up online** buttons; a big, clear progress strip while scanning, also in
  the sidebar on every page.
- Plain columns and tiles: *Our advice*, *Checked?*, *Identified*, *Never touched*, *Not checked yet*,
  *Not identified*, *Already known*, *Will retry*.
- Existing installs: items an older version left "Unknown" are researched once more on the next scan.

### Overview
- Top row: **four ring tiles** — RAM free, CPU (speed + busy), Graphics (busy + VRAM per graphics chip; laptops
  have two) and Disk (busy, read/write, free space). They update every 2 s **even when monitoring is off**
  (CPU speed used to show "-- GHz").
- Below: the **History** graph on the left and everything you can **do** on the right.
- **Disk tile like Task Manager:** active time, read/write speed, response time, SSD / NVMe / USB, and a warning
  when the Windows drive is over 90 % full.

### Disk cleanup (new page, Ctrl+9)
- Categories: temporary files (yours and Windows'), web browser caches (Chrome, Edge, Brave, Opera, Vivaldi,
  Firefox — cache only), picture previews, game shader caches (*your call*), crash dumps and error reports,
  Windows Update downloads older than 10 days, Delivery Optimization and the Recycle Bin (*your call*).
- Each shows its size, what it is, what cleaning changes and whether it can be undone. You confirm the total.
- Safety: never follows folder links/junctions, skips files in use and temp files newer than a day, and never
  includes Documents, Downloads, Desktop, Pictures, cookies, passwords or history (checked by a test).
- **Optional weekly automatic clean** of only the safest leftovers (old temp files, crash reports, old Windows
  Update files). **Off by default.**
- **What's using my disk:** biggest folders with share bars (double-click to go deeper) and the 50 biggest files,
  with Open location. YUMRAM never deletes your own files.
- Test PC: 2.4 GB found without administrator, 6.3 GB with administrator.

### Closing, tray and the mini bar
- **The X button keeps YUMRAM running** in the notification area (taskbar if the tray icon is off). Quit with
  *Exit YUMRAM* in the tray menu; updates and Windows sign-out still close it properly. Setting in Settings.
- Opening YUMRAM again brings back the hidden window instead of an "already running" box.
- **Floating mini bar:** small always-on-top bar with RAM, CPU, GPU and disk, Free RAM, Open, and hide to the
  tray icon (it may be under the ^ arrow). Drag it anywhere; the position is remembered. From the Overview's
  *Mini bar* button, the tray menu, or make minimize/close use it (Settings).

### Plain words and advice
- One vocabulary and colour on every page: **Keep** (pink), **Turn off is fine** (green), **Your call** (blue),
  **Careful** (red, not identified). Legends on Startup apps, Windows bloat and Disk cleanup.
- Reclaim Center: *Free for programs*, *Taken from idle apps*, *Real gain last time*, plain reasons.
- Status bar says *Live readings* instead of telemetry timings; CPU settings explained without jargon.

### Other fixes and changes
- **Settings › Apply no longer stops** when the administrator choice needs admin rights (it used to save nothing
  else); the reason is shown next to that choice.
- CPU care while gaming steps in from 50 % whole-PC load (was 70 %), after a test showed games starving at 50–55 %.

### Costs / trade-offs
- A scan uses up to 6 threads for a few seconds; the Intelligence list is longer because it now includes
  everything. Live readings cost 15–40 ms every 2 s, only while the Overview or the mini bar is visible.

### Tested
- 65 automated tests and an 82-step full UI test (every page, button, setting and the tray), run normally **and
  as administrator**. Fresh-install research measured on a clean profile.

### Install / update
- In YUMRAM: the update banner offers *Install and restart* (the download is verified with SHA-256).
- New install: run `YUMRAM-Setup-5.15.2.exe` (per-user, no administrator needed), or download
  `YUMRAM-5.15.2.zip`, unzip and run `YUMRAM.exe`. `SHA256SUMS.txt` lists both checksums.
- Your settings, history and learned data are kept when updating.
