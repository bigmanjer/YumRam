# YUMRAM V5.2.70 — Research Live GUI Refresh Fix

## Scope
Research/UI synchronization only.

## Root cause
The Research worker already emitted immutable `research-live-results-<run>-<completed>.json` checkpoints, but the Intelligence UI intentionally ignored those checkpoints and waited for `EndInvoke()` before replacing the displayed records. Research was therefore running successfully while the GUI remained visually stale.

## Fix
- Re-enabled safe consumption of immutable live Research snapshots from the Intelligence UI poller.
- Progressively merges completed Research records into the existing UI data set.
- Persists each checkpoint to the Intelligence database.
- Forces the Intelligence ListView/counts/status to refresh after each completed item.
- Preserves the final worker result path as the authoritative completion boundary.
- No scanner code changes.
