# YUMRAM V5.2.0 Regression Ledger

## Controls

- **4.9.4** — last proven stable rollback baseline.
- **5.0.0** — previous V5 candidate.
- **5.2.0** — current candidate.

## 5.0.0 issues addressed

1. Safe optimization depended on Monitoring/controller activity.
2. Research layer used evidence heuristics without a strong promotion gate.
3. Weak evidence could promote records too aggressively.
4. Research sources were not surfaced clearly in the UI.
5. Clearing a manual override did not immediately re-research in Intelligence.
6. WinGet lookup relied on broad table parsing.

## V5.2.0 changes

- Safe optimization requests start a one-shot controller when Monitoring is not running and stop that temporary controller after the request is serviced.
- WinGet installed-app research uses exact name filtering with detailed output and a bounded count when available.
- Research confidence now distinguishes strong proof/corroboration from weak heuristics; automatic promotion to cleanup Candidate requires stronger evidence.
- Research links from online corroboration are retained in the research record and displayed in Intelligence details.
- Clearing a manual Intelligence organization queues immediate fresh research for the selected record.
- Monitor legend remains outside the graph canvas and follows monitor order: Available RAM, Memory Used, CPU, GPU 3D.
- Research cache engine version is advanced to 5.2.0.

## Regression results

- V5.0.0 → V5.2.0 changed 13 files.
- PowerShell files retain the required UTF-8 BOM.
- XAML and JSON parse successfully in the Linux-side structural checks.
- 156 local YUMRAM functions were defined; no undefined YUMRAM helper calls were detected by the source sweep.
- 4.9.4 is unchanged and remains the rollback baseline.

## Windows-only validation still required

Run `Tests\\Preflight.ps1` and `Tests\\StaticTest.ps1` on Windows PowerShell 5.1, then exercise the UI and live telemetry. This environment cannot execute WPF/Windows PowerShell 5.1.
