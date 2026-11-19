# YUMRAM 4.8.0 Scanner Research Basis

## Design decisions

1. **Process inventory:** use the Windows `Win32_Process` CIM class once for parent-process relationships and process metadata, with `Get-Process` for live working-set/process objects. Microsoft documents `Win32_Process` as the process inventory class and exposes `ProcessId`, `ParentProcessId`, `WorkingSetSize`, `PrivatePageCount`, and related fields.
2. **Services:** use one bulk `Win32_Service` query and map it to running `Get-Service` objects. Service dependencies are treated as review/protection evidence; YUMRAM does not stop services in the stable build.
3. **Apps:** use `Get-AppxPackage` for installed AppX/MSIX packages when available.
4. **Memory:** report working-set memory as process-level evidence, but use system Available RAM as the actual optimizer target. Microsoft explicitly describes working set as only one part of system-wide memory effects, and RAMMap exposes additional physical-memory categories.
5. **CPU:** the new scan keeps CPU as a conservative process estimate rather than making expensive per-process counter calls. If future live CPU sampling is required, it should be done with a bounded sample window.

## References
- Microsoft Learn: Win32_Process — https://learn.microsoft.com/en-us/windows/win32/cimwin32prov/win32-process
- Microsoft Learn: Get-AppxPackage — https://learn.microsoft.com/en-us/powershell/module/appx/get-appxpackage
- Microsoft Learn: Working Set — https://learn.microsoft.com/en-us/windows/win32/memory/working-set
- Microsoft Learn: SetProcessWorkingSetSize — https://learn.microsoft.com/en-us/windows/win32/api/memoryapi/nf-memoryapi-setprocessworkingsetsize
- Microsoft Learn / Sysinternals RAMMap — https://learn.microsoft.com/en-us/sysinternals/downloads/rammap
- Microsoft Learn / Sysinternals Process Explorer — https://learn.microsoft.com/en-us/sysinternals/downloads/process-explorer
- Microsoft Learn: Stop-Service — https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.management/stop-service
