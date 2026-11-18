# YUMRAM V5.2.71 — Intelligence Live Research Monitor

## Scope
Research/UI synchronization only. Scanner, Cleanup, MainWindow shell, and Research evidence logic remain unchanged from V5.2.70 unless explicitly noted below.

## Fixes
- Intelligence now attaches to an already-running Research pass when the window is opened.
- The Intelligence list marks the currently researched record as `Researching` while the worker is active, so the user can see exactly which item is being researched.
- Live Research checkpoints use one atomic file: `research-live-results.json`, instead of creating one immutable JSON file per completed item.
- The live merge remains incremental and preserves the final worker result as authoritative.
- Existing queue/config transport files remain temporary and are removed when the Research run ends or times out.

## Safety
No scanner code was changed by this release. No Research evidence provider or placement algorithm was redesigned.
