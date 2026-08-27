YUMRAM V5.2.2 — Review Queue Research Fix

Fixes the V5.2.0 Review queue behavior where cached Review classifications could be treated as fresh and therefore skipped on subsequent research passes.

Behavior:
- Any non-manual item whose current Risk is Review is always eligible for a new research pass.
- Any cached result whose Placement is Review Queue is always eligible for a new research pass.
- Normal cache freshness remains enabled for completed non-review classifications.
- Review research writes an explicit log entry when it starts.
- Scan flow remains unchanged.
- Manual organization remains authoritative and is never overwritten by automatic research.
