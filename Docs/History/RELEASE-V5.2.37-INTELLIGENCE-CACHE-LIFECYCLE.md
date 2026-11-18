# YUMRAM V5.2.37 — Intelligence Scan / Cache Lifecycle

This build adds controlled Intelligence lifecycle operations without touching monitoring, cleanup, gaming, telemetry, scanner, or protection policy behavior.

- Normal Scan reuses valid identity knowledge and valid research cache.
- Fresh Scan keeps saved knowledge but forces fresh research for the current research pass.
- Clear Research Cache deletes only research-cache.json.
- Clear Knowledge deletes only intelligence-db.json.
- Clear & Rescan clears both stores and launches a fresh scan.
- PowerShell 5.1 scalar-count hardening remains intact from V5.2.36.
