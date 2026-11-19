YUMRAM 4.8.4 FULL RELEASE AUDIT

Status: PASS (static/package audit)

Fixes applied:
- scanner stage error propagation via ErrorSink
- SkipParentMap now actually skips parent CIM enumeration
- sampled CPU map used when available, lifetime CPU only as fallback
- scanner status distinguishes CompletedWithWarnings from Completed
- live vs saved Intelligence records labeled with StateText and shown in UI
- Settings Reset defaults synchronized with shipped defaults
- runtime/version metadata synchronized to 4.8.4
- stable service termination gate retained

Research basis:
- Microsoft working-set documentation: working set is only resident pageable process memory; it is not a complete system memory accounting.
- Microsoft RAMMap documentation: system physical memory includes processes, file cache, standby lists, kernel and driver memory.
- Microsoft service stop documentation: dependent services can prevent or complicate stopping a service.
- Microsoft AppX documentation: Get-AppxPackage is the supported cmdlet for installed app packages.

Static checks:
- 19 PowerShell files
- 10 XAML files
- BOM encoding verified
- XAML/JSON parsing verified
- no $PID assignment collisions
- scanner contract verified
- Intelligence state contract verified
- Settings Scanner layout verified
- safety gate verified
