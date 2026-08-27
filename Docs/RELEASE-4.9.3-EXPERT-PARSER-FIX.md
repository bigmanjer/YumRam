# YUMRAM 4.9.3 — Expert Parser, Startup & Research Fix

YUMRAM 4.8.5 remains the read-only stable baseline; this release is a separate development build based on 4.9.2 and regression-checked against 4.8.5.

## Fixes
- Replaced the parser-fragile one-line Mode selection handler with structured Windows PowerShell 5.1 syntax.
- Expanded startup initialization to explicit blocks for safer error localization.
- Ensured Startup fallback data is inserted before UI list refresh.
- Added Authenticode evidence to automatic research when an executable path is available.
- Normalized runtime/version markers to 4.9.3.

## Automatic classification
Research remains automatic for uncertain scan records. Placement is classification metadata only: YUMRAM does not move or delete files based solely on online research.
