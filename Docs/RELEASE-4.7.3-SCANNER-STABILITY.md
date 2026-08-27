# YUMRAM 4.7.3 Scanner Stability

## Baseline
The process/service/system scanner in this release is restored from the known-good 4.5.9 Scanner.ps1 supplied by the user.

## Intelligence integration
The Intelligence layer consumes a structured scan result using `Records` instead of reusing a UI-style `Items` property. The WPF list is updated through `ItemsSource`, reducing ambiguity between data records and control collections.

## Reliability changes
- Scanner implementation retained as the baseline.
- Intelligence worker supplies required runtime configuration and helper functions.
- Scan result is normalized to one structured object.
- Saved catalog remains separate from the live ListView control state.
- Settings Scanner section uses explicit rows to avoid text overlap.
- Monitoring remains manual.
- Intelligence Scan remains automatic on Intelligence launch.

## Research basis
Microsoft documents that PowerShell dot-sourcing executes a script in the current scope, and that pipeline output is produced by commands that emit objects; module-loading output therefore should not be mixed into a structured worker result. Microsoft also documents CIM/WMI as the Windows system-management interface used by the scanner.
