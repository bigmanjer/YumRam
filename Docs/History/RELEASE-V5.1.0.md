# YUMRAM V5.2.0

Hardening release.

- Safe optimization runs independently of Monitoring via a one-shot controller.
- Automatic research uses local Windows evidence first, exact WinGet `list --name --exact --details --count 1`, Authenticode, registry and optional web corroboration.
- Automatic promotion to cleanup Candidate requires stronger corroboration; weak evidence remains Review.
- Research engine/cache version is 5.2.0.
- Intelligence UI explicitly explains the research→organization workflow and manual organization.
- Graph legend remains outside the plot area in monitor order: Available RAM, Memory Used, CPU, GPU 3D.

4.9.4 remains the stable rollback baseline.
