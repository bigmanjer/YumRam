# YUMRAM 4.6.9 Intelligence Scan Fix

Fixed a strict-mode PowerShell 5.1 runtime failure in Core/Intelligence.ps1 where the loader accessed `.Items` directly on an arbitrary ConvertFrom-Json result. Older, empty, or legacy intelligence-db.json files can now load as an empty catalog or supported array form without aborting the Intelligence scan.

Behavior preserved: Intelligence remains the single organizer for Protected, Games, Apps, Services, Safe to Manage, Review, and Unknown.
