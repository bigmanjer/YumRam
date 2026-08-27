# YUMRAM V5.0.0 — Intelligence, Organization, Optimization, and Telemetry

## Stable control
YUMRAM 4.9.4 is retained as the proven rollback baseline. It is not modified by this release.

## V5 workflow
1. Scan the system without blocking on research.
2. Automatically research Review/Unknown/Candidate records.
3. Automatically classify and organize supported records.
4. Leave only genuinely unresolved records in Review/Unknown.
5. Allow persistent manual organization from Intelligence and major inventory lists.

## Manual organization
Right-click rows or use Organize Selected. Manual choices are persisted and take precedence over automatic classification until cleared. Manual Security, Drivers, Games, Unknown, and Review selections are reflected in cleanup safety state.

## Safe optimization
OPTIMIZE SAFE NOW bypasses normal pressure/cooldown gating but remains Safe-only. It can trim only low-risk working sets; protected, unknown, review, foreground, active-game, and manually protected items remain excluded.

## Memory graph
The graph uses four live series in monitor order: Available RAM, Memory Used, CPU, GPU 3D. The legend is outside the graph canvas so it cannot cover the plotted lines.
