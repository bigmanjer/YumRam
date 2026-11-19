# YUMRAM V5.2.11 — Record Schema Boundary Fix

## Fix
All Intelligence records are normalized through `Ensure-YumIntelligenceRecordSchema` before UI filtering, persistence, manual-organization application, or research-result rendering.

## Regression protection
Saved records and fresh scan results now share the same canonical schema boundary, preventing strict-mode missing-property failures such as `ResearchStatus` and `ManualOverride`.
