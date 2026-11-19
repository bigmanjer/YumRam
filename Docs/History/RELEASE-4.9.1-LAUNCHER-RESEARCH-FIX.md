# YUMRAM 4.9.1 — Launcher & Research Fix

## Fixes
- Removed the UTF-8 BOM from `Launch-YUMRAM.cmd`; Windows CMD now starts cleanly.
- Corrected the malformed PowerShell research function parameter declaration that caused Windows PowerShell 5.1 preflight failure.
- Preflight now prints the exact validation errors to the console instead of only returning code 2.
- Added Placement and Research columns to the System Inventory process/startup views.
- Updated version metadata to 4.9.1.

## Research behavior
Research remains automatic after scan collection. It uses local evidence (registry/WinGet) and optional online research, then assigns a non-destructive placement/action lane. It does not move or delete files automatically.
