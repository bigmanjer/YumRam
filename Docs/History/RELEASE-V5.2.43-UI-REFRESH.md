# YUMRAM v5.2.43 — Intelligence UI Refresh Fix

- Added a dedicated 500 ms WPF DispatcherTimer to the Intelligence window.
- Research status, live research snapshots, persistent database changes, counters, filters, and result rows now refresh independently of the main-window timer.
- Needs Research / Review Queue / Researching views now include persisted unresolved records, not only live-scan records.
- Research snapshot merging is skipped when no active research run exists.
- Timer and search-timer cleanup is performed when the Intelligence window closes.
