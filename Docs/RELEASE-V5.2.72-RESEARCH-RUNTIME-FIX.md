# YUMRAM V5.2.72 — Research Runtime Fix

## Incident

Windows PowerShell 5.1 runtime testing showed Research creating transport/checkpoint files while the Intelligence UI reported that live checkpoint merging failed with `Access is denied`. This made the Research worker appear stalled even though the queue transport was active.

## Root cause

The Research worker wrote a single shared `research-live-results.json` by first creating a temporary file and then replacing the destination. The Intelligence UI could hold or open the destination while the worker attempted replacement. Windows then rejected the replacement, and the previous implementation generated a unique temporary file for each failed checkpoint.

## Repair

- Added a named cross-runspace mutex `Global\YUMRAM-ResearchLiveCheckpoint` shared by the Research writer and Intelligence reader.
- The worker now uses one deterministic temporary checkpoint file and deletes it in `finally`, preventing orphaned `.tmp` files.
- The UI acquires the same mutex while reading the completed checkpoint.
- Added startup cleanup of orphaned `research-queue-*.json`, `research-config-*.json`, and `research-live-results*.tmp` transport/checkpoint files from interrupted runs.
- Moved Research-worker startup logging until after the logging module is loaded and the transported record collection has been materialized.
- Added `Tests/ResearchLiveCheckpointConcurrencyRegressionTest.ps1`.

## Regression boundary

Functional changes are limited to the Research live-checkpoint transport and Intelligence Research worker orchestration. Scanner, Cleanup, MainWindow, Bootstrap, and the memory-management engine were not modified.

## Release integrity

Active version is `5.2.72` across VERSION and configuration. MANIFEST.txt is regenerated after the runtime fix.

## Runtime qualification

Windows PowerShell 5.1 execution remains required on the target machine. The critical acceptance test is a real manual Research run in which live progress advances beyond `0/N`, no `Access is denied` checkpoint error appears, no orphaned `research-live-results*.tmp` files accumulate, and records reach terminal Research states.
