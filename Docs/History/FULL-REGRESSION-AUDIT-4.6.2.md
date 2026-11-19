# YUMRAM 4.6.7 — Full Regression Audit

## Scope

This audit covers the 4.6.2 Smart Intelligence / automatic-organization candidate after the scan and UI fixes.

## Functional changes verified by static inspection

- Smart Intelligence is the only system-wide scan entry point in the main UI.
- The obsolete MainWindow Scan control/wiring is removed.
- Protected, Games, Apps, and Services side-menu entries route into the same Intelligence view with category filters.
- Intelligence Scan uses the existing process scanner with an explicit `SkipParentMap` switch rather than maintaining a second scanner implementation.
- Intelligence uses cached executable identity lookups during repeated scans.
- Intelligence loads the existing local `intelligence-db.json` and merges new/updated classifications into it instead of replacing the database on every scan.
- Service discovery uses one bulk `Win32_Service` query per Intelligence scan rather than one CIM query per service.
- Unknown, protected, active-game, security, and driver/hardware items remain excluded from automatic cleanup.
- RAM target remains user-configurable and cleanup reports whether the configured target was reached.
- Safe/Balanced/Aggressive follow-up passes are 6/12/20 respectively, with conservative candidate rules preserved.
- Cleanup target-seeking tolerates two consecutive no-gain passes before declaring that safe candidates are exhausted.

## Visual regression checks

- Smart Intelligence page uses a single focused layout with high-contrast panels.
- Scan button, filter, search, table headers, selected rows, counts, and status panels use explicit dark/purple styling.
- ComboBox dropdown is explicitly themed to avoid the previous white/default WPF appearance.
- Summary cards use distinct high-contrast backgrounds and borders.
- Main dashboard graph and target controls are preserved.
- Side menu remains organized under Smart Intelligence with Settings/About retained at the bottom.

## Static validation

- 19 PowerShell files inspected.
- 10 XAML files parsed with XML parser.
- JSON parsed successfully.
- PowerShell source BOM requirement checked for all `.ps1` files.
- No `.ContainsKey()` usage remains.
- No obsolete MainWindow `Scan` control reference remains.
- No obsolete `Smart Scan` user-facing label remains in the Intelligence page.
- Required MainWindow controls are present.
- ZIP integrity checked after packaging.

## Runtime limitation

This build was statically audited in a non-Windows environment. Windows PowerShell 5.1/WPF could not be launched here, so the user's Windows preflight/startup run remains the authoritative runtime test.

## Stability boundary

Automatic process termination is intentionally NOT enabled in this build. The intelligence database and category organization should become the stable source of truth first. Termination can be introduced as a later, separately audited capability once the scan/organization system is proven stable.
