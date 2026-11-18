# v5.2.60 — Smart Intelligence Page Overhaul

## Goals
- Keep saved Intelligence visible even when no fresh scan is running.
- Add explicit manual organization with immediate persistence.
- Allow per-item research without requiring a full queue.
- Add a non-scanning VIEW refresh that reloads the Intelligence database.
- Preserve the stable launcher and startup path.

## Research flow
RUN SCAN builds the live inventory. RUN RESEARCH processes unresolved records. RESEARCH SELECTED performs an explicit one-item research run.

## Manual organization
A user can assign a record to a supported category and click APPLY & SAVE. The override is persisted in the manual organization store and the Intelligence database and is reapplied on later scans. RESET removes the override and returns the item to Review Queue.

## View persistence
The Intelligence page merges the current live scan with saved Intelligence records. A corrupt legacy record is skipped instead of blanking the entire page. VIEW reloads the saved database without starting a scan.
