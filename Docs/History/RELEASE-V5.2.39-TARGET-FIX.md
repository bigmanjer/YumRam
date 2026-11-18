# YUMRAM v5.2.39 Target-Reach Fix

## Fix
The target-driven cleanup planner no longer rejects the only eligible working-set candidate merely because its current working set is larger than the remaining Available-RAM gap.

A working-set trim is a reclaim request; the full working set is not guaranteed to be released. The planner therefore permits the first eligible candidate to exceed the remaining gap when it remains inside the per-pass trim budget. Additional candidates remain gap-aware to limit unnecessary overshoot.

The adaptive controller also enters the legacy fallback immediately when the adaptive planner produces no candidates, rather than spending multiple passes repeating an empty plan.
