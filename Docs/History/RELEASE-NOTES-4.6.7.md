# YUMRAM 4.6.7 — Stable Intelligence Scan Baseline

## Scanner
- Rebased the Intelligence Scan on the user-validated scanner implementation.
- Intelligence consumes `Get-YumSystemScan` results instead of maintaining a parallel process scanner.
- Process, service, and AppX inventory are organized by one scan into Protected, Games, Apps, Services, Safe to Manage, Review, and Unknown.
- `SkipParentMap` remains optional for performance-sensitive Intelligence refreshes.

## Persistence
- Existing Intelligence records are loaded, updated, and preserved between scans.
- Saved records remain visible when an item is not currently running or installed.

## Safety
- Unknown items are never automatically managed.
- Service termination remains disabled in the stable build.
- Active games, foreground processes, Windows/security components, and drivers remain protected.

## Memory target
- `MinimumAvailableGB` is the authoritative Available-RAM target; the legacy cleanup-target alias remains synchronized for compatibility.
- Reclaim reports actual Available-RAM attainment separately from working-set reduction.

## Validation
- Static post-package audit passed: XAML, JSON, PowerShell BOM, control references, `$PID` assignment collision checks, and ZIP integrity.
- Windows PowerShell 5.1 + WPF runtime execution still requires validation on a Windows machine.
