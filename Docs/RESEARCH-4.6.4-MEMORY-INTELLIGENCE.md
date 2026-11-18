# YUMRAM 4.6.7 Research Basis

YUMRAM 4.6.7 changes were based on current Windows documentation plus independent Windows performance research.

## Memory / target behavior

- Windows defines a process working set as resident pageable pages. Windows can trim working sets, and the documented APIs can explicitly empty a process working set. YUMRAM therefore reports **working-set reduction separately** from **measured Available RAM improvement**.
- Microsoft also documents that working-set size is not a complete measure of system-wide memory use; Windows may have file cache, kernel/driver memory, standby lists, and other memory activity outside the targeted process. Therefore YUMRAM's success criterion is the system's **Available RAM**, not the sum of process working-set reductions.
- Sysinternals RAMMap is used as a conceptual cross-check for this distinction: it exposes process working sets alongside physical-memory/page-list accounting.
- Bruce Dawson's independent Random ASCII testing demonstrates that EmptyWorkingSet can dramatically reduce a process working set and that the working set can later refill when the memory is touched again. This supports YUMRAM treating trimming as a best-effort pressure-relief action rather than a guaranteed permanent release.

## CPU measurement

- Microsoft documents that per-process `% Processor Time` is calculated from performance-counter samples and that process values can exceed 100% on multi-core systems.
- YUMRAM now obtains a bulk `Win32_PerfFormattedData_PerfProc_Process` sample and normalizes it to a 0-100 process percentage. A short-lived fallback remains for processes without a current formatted sample.
- The previous lifetime-average calculation was removed from the primary scoring path because it could label a currently-idle process as active based on CPU time accumulated much earlier.

## Services

- Windows/.NET documentation confirms that stopping a service can affect dependent services. YUMRAM therefore checks `CanStop`, running dependents, startup mode, and protected-service rules before an optional service can ever become eligible.
- Service termination remains disabled in the stable intelligence build.

## Intelligence organization

The scan is the source of truth. It records and persists classifications for:

- Protected
- Games
- Apps
- Services
- Safe to Manage
- Review
- Unknown

Unknown items are left alone automatically.

## Sources

Microsoft Learn — Working Set:
https://learn.microsoft.com/en-us/windows/win32/memory/working-set

Microsoft Learn — SetProcessWorkingSetSize:
https://learn.microsoft.com/en-us/windows/win32/api/memoryapi/nf-memoryapi-setprocessworkingsetsize

Microsoft Learn — Reference sets and system-wide memory effects:
https://learn.microsoft.com/en-us/windows-hardware/test/wpt/wpa-reference-set

Microsoft Sysinternals — RAMMap:
https://learn.microsoft.com/en-us/sysinternals/downloads/rammap

Microsoft Learn — Collecting performance data:
https://learn.microsoft.com/en-us/windows/win32/perfctrs/collecting-performance-data

Microsoft Learn — Accessing WMI preinstalled performance classes:
https://learn.microsoft.com/en-us/windows/win32/wmisdk/accessing-wmi-preinstalled-performance-classes

Microsoft Learn — ServiceController.Stop / dependent services:
https://learn.microsoft.com/en-us/dotnet/api/system.serviceprocess.servicecontroller.stop

Bruce Dawson / Random ASCII — 32 MiB Working Sets on a 64 GiB machine:
https://randomascii.wordpress.com/2023/10/01/32-mib-working-sets-on-a-64-gib-machine/
