# YUMRAM 4.6.7

## Full audit fixes

- Canonical RAM target: `MinimumAvailableGB` is the single source of truth; `CleanupTargetAvailableGB` is maintained only as a compatibility alias.
- Manual Reclaim now uses the same repeated target-seeking cleanup loop as automatic pressure control.
- Safe/Balanced/Aggressive defaults are synchronized across config and Settings Reset Defaults.
- Process CPU scoring now uses a bulk Windows formatted performance sample, with normalized multi-core values and a short-lived cache.
- Service intelligence includes confidence and publisher metadata, and service organization is persisted through the Intelligence database.
- Installed AppX packages are classified more meaningfully into Apps, Games, or Protected framework packages.
- Smart Intelligence summary now includes Saved Records and uses a more readable 4x2 card layout.
- Version metadata/footer is synchronized to 4.6.5.
- Stable build keeps automatic service termination disabled.
