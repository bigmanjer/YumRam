# YUMRAM 4.6.7

## Smart Intelligence
- Consolidated Scan, Protected, Services, Background Apps, Top Processes, and manual game-management entry points into a single Smart Intelligence experience.
- Added automatic classification for Windows/system, security, driver/hardware, active game, game launcher/game-related, background app, service, user application, review, and unknown items.
- Added confidence and recommendation fields to explain classifications.
- Unknown items default to no automatic action.
- Smart Intelligence refreshes automatically while open.
- Added one-click safe optimization that uses the existing YUMRAM cleanup controller rather than inventing a second cleanup engine.

## Safety
- Protected classification is conservative and includes security components, drivers/hardware, Windows components, the foreground process, active game, and YUMRAM.
- Services are review-first unless explicitly approved.
- Classification is advisory and does not claim to detect malware.

## UX
- Main Control Center now presents Smart Intelligence instead of multiple technical management buttons.
- Existing advanced settings and legacy dialog code remain in the project for compatibility; the normal user flow no longer requires them.


4.6.1 additions: persistent intelligence database, scan dependency decoupling, identity caching, bulk service classification, stronger target-driven cleanup passes, and nested Smart Intelligence navigation.
