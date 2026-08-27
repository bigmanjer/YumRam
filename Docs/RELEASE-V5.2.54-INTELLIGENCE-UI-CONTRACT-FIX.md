# YUMRAM v5.2.54 — Intelligence UI Contract Fix

Fixes the intelligence-selection UI contract so records without a Signature property cannot crash the WPF dispatcher update path.

Research worker and launcher behavior are unchanged from v5.2.53. The UI now receives a stable Signature display field and defensively handles legacy records.
