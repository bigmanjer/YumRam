# Competitive review (November 2026)

How established Windows memory/optimizer tools work, and what YUMRAM should take from them.
Researched for the 5.4.0 visual overhaul. Sources are listed at the end.

## Design: what professional tools look like

| Pattern | Seen in | YUMRAM 5.4 |
|---|---|---|
| One large primary action ("Boost", "Optimize") above a memory summary | Microsoft PC Manager, Wise Memory Optimizer | Done: "Free RAM now" is the only primary button in the top row |
| Memory gauge (pie/ring) for used vs available | Wise Memory Optimizer, IObit dashboards | Done: RAM-in-use ring beside Available RAM |
| Live real-time graph | Wise Memory Optimizer | Done: themed, labelled, legend outside the plot |
| Settings that are easy to find (a common IObit criticism) | IObit reviews | Done: Settings split into tabs |
| Avoid fixed-height windows that force scrolling (PC Manager criticism) | PC Manager reviews | Done: all windows resizable; only side panels scroll |
| Windows 11 type and spacing: Segoe UI, 14 px body / 12 px caption, 4 px grid, AA contrast | Microsoft design guidance | Done: `UI/Xaml/Theme.xaml` |
| Honest results: reviewers note boost gains are temporary | PC Manager reviews | Already unique to YUMRAM: 5/15/30 s retained-gain verification |

## Features worth adopting (roadmap)

1. **Tray icon with live RAM %** and quick actions (Open, Free RAM now, Start/Stop monitoring, Exit);
   minimize to tray. Standard in Mem Reduct-class tools.
2. **Standby-list guard (ISLC-style)** for gaming: purge the standby list only when *free* memory is
   below X MB **and** the standby list is above Y MB, while monitoring and elevated. Smarter than an
   unconditional Deep purge.
3. **Choose reclaim areas in Settings** (working sets, system working set, standby, low-priority
   standby, modified list). The config keys already exist (`Reclaim*`); only the UI is missing.
4. **Command-line switches** (`/FreeRam`, `/Deep`, `/Minimized`) for shortcuts and scheduled tasks,
   as WinMemoryCleaner does.
5. **ProBalance-style CPU restraint**: temporarily lower the priority of background CPU hogs (never
   the foreground app or the game) and show them as "Restrained". Addresses lag RAM trimming cannot.
6. **Distribution**: code-signed scripts and a WinGet/Scoop manifest (WinMemoryCleaner ships both).

## Where YUMRAM is already ahead

- Target-based automatic care with a no-progress back-off, instead of a fixed "% used" trigger.
- Measures the real Available-RAM gain after Windows settles, and learns each PC's retention.
- Shows what is realistically reachable next to the goal.
- Identifies every program (signatures, installed software, services, Store packages, WinGet,
  verified web sources) and never trims protected, security, driver, game or unknown programs.

## Sources

- IObit Advanced SystemCare: https://www.tech-critter.com/a-beginners-guide-to-enhancing-pc-performance-with-advanced-systemcare-18-free/ ,
  https://www.techradar.com/sg/reviews/iobit-advanced-systemcare-free , https://mspoweruser.com/ccleaner-vs-iobit-advanced-system-care
- Wise Memory Optimizer: https://www.wisecleaner.com/wise-memory-optimizer.html , https://www.filehorse.com/download-wise-memory-optimizer
- Microsoft PC Manager: https://windowsreport.com/microsoft-pc-manager-review/ , https://pureinfotech.com/reduce-ram-usage-windows-11-pc-manager/ ,
  https://www.windowscentral.com/software-apps/windows-11/what-is-pc-manager-and-how-to-get-started-using-it-on-windows-11
- Windows design guidance: https://learn.microsoft.com/en-us/windows/apps/design/widgets/widgets-design-fundamentals
- Mem Reduct: https://github.com/henrypp/memreduct , https://betanews.com/2015/04/22/mem-reduct-a-memory-cleaner-which-isnt-rubbish
- ISLC: https://www.wagnardsoft.com/forums/viewtopic.php?p=11392 , https://tier1settings.com/intelligent-standby-list-cleaner-islc-guide/
- WinMemoryCleaner: https://github.com/IgorMundstein/WinMemoryCleaner
- Process Lasso ProBalance: https://bitsum.com/apps/process-lasso/docs/algorithms/probalance/
