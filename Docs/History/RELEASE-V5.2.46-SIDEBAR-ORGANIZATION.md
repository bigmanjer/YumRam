# YUMRAM V5.2.46

## Sidebar organization

- Reorganized the main RAM Cleaner sidebar around the user workflow.
- Separated Monitor, Target/Mode, Cleanup Actions, Intelligence, Protection/Gaming, System/Diagnostics, and Application settings.
- Clarified that Monitoring performs automatic target maintenance while Clean Now performs a one-shot cleanup without enabling monitoring.
- Renamed the Preview action visually to `Preview Cleanup Plan` without changing the underlying control name/wiring.
- Restored the Gaming/Protection controls to a visible, organized section while preserving their existing bindings.
- Improved descriptive text so the purpose of each section is clear without implying that Preview or Clean Now starts monitoring.

## No-regression principle

Existing control names and event wiring were preserved. This release is a layout/UX organization change, not a replacement of the cleanup engine.
