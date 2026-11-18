# YUMRAM 4.6.7 Research / Audit Basis

This pass used multiple independent sources to validate memory reclamation, CPU measurement, service handling, and Windows app inventory behavior.

## Memory / target semantics

- Microsoft documents that a process working set is only the pageable pages resident in physical memory; it is not the complete picture of system-wide physical memory.
- Microsoft Sysinternals RAMMap separates process working sets from standby lists, file cache, kernel/device-driver memory, and other physical-memory categories.
- Microsoft documents that EmptyWorkingSet removes as many pages as possible from a process working set, but that operation is not a promise of an equivalent increase in system Available RAM.

Implication for YUMRAM: Available RAM is the success metric for the user's target. Working-set reduction is reported separately. The optimizer keeps seeking the target while safe candidates remain, but it must report a shortfall when Windows memory state prevents the target from being reached.

## CPU measurement

- Microsoft documents that per-process `% Processor Time` is derived from performance-counter samples and can exceed 100% on multi-processor systems before normalization.
- Independent PowerShell examples likewise recommend sampling process performance counters rather than treating TotalProcessorTime as instantaneous CPU usage.

Implication for YUMRAM: bulk per-process CPU samples are used for scoring; lifetime CPU time is only a fallback.

## Services

- Microsoft documents that services have dependency relationships and that stopping a service can fail when dependent services are running.
- Microsoft PowerShell documentation recommends inspecting dependent services before stopping a service.

Implication for YUMRAM: services remain classification/review items in the stable build; automatic service termination stays disabled.

## App inventory

- Microsoft documents that Get-AppxPackage enumerates installed app packages and exposes framework packages separately.

Implication for YUMRAM: AppX framework packages are protected; game/application indicators are classified separately from generic installed apps.
