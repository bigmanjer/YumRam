# YUMRAM V5.2.28 — Intelligence Overhaul

This release reorganizes the Intelligence experience around the actual workflow:

Scan → Research → Organize → Remember.

## UI changes
- Removed the redundant Safe Optimization button from Intelligence.
- Added explicit Research Selected and Retry Review actions.
- Replaced mixed category/status counters with research-focused KPIs.
- Added Needs Research, Researching, Organized, Unknown, Protected, Games, Apps, Services, and Overview views.
- Promoted ResearchStatus to the main results table.
- Added a dedicated selected-item Research State panel.
- Added visible live research progress.
- Kept right-click manual organization as the primary contextual workflow.

## Regression coverage
Tests cover Intelligence control wiring, research-view filters, authoritative research predicates, and removal of the obsolete Optimize control.
