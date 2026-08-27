# YUMRAM V5.2.27 — Gradual Gaming-Safe Cleanup

- Cleanup selects the smallest eligible working sets first.
- Each mode controls pass size, pacing, reclaim budget, and maximum pass time.
- Cleanup will not intentionally select a working set larger than the remaining target gap.
- Active gaming applies a safer mode-specific profile: Safe=1 small trim / 400ms, Balanced=2 / 300ms, Aggressive=3 / 225ms; optional background/service cleanup is disabled during gaming.
- Optional background processes are only considered when their estimated working set fits within the remaining target gap.
- Optional services are excluded from target reclaim because their memory release cannot be reliably estimated.
- Regression tests cover small-first ordering, pass limits, target-overshoot prevention, mode pacing, and gaming caps.
