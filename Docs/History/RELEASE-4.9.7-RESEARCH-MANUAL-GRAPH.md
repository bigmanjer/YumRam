# YUMRAM 4.9.7 — Research, Manual Organization & Memory Graph

Baseline control: 4.9.4. Previous candidate: 4.9.7.

## Fixes
- Pass YUMRAM runtime/config into scan workers so automatic research can execute.
- Attach manual organization context menu to Smart Intelligence.
- Reapply persistent manual organization after live research/scan results.
- Preserve research and manual fields for saved/offline records.
- Require research cache EngineVersion match.
- Accurate ResearchPerformed/ResearchCount reporting.
- RAM Used + RAM Available share one auto-scaled graph range.
- Clear 4.9.7 research engine identity in config/cache writes.

## Safety
Manual organization changes classification/action-lane metadata only; it does not move or delete files. Unknown/protected items remain non-automatic-management lanes.
