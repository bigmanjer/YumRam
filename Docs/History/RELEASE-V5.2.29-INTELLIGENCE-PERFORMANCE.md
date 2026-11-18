# YUMRAM V5.2.31 — Intelligence UI Performance & Clarity

- Explicit dark ComboBox item template and virtualization/recycling.
- Debounced Intelligence search (250 ms).
- Research UI polling reduced from 120 ms to 400 ms.
- Intelligence auto-refresh default increased from 20s to 60s; only the historical default is migrated.
- ListView refresh avoids unnecessary ItemsSource replacement and preserves selected row.
- Main Intelligence table reduced to Item, Category, RAM, Risk, Research, Placement, Confidence.
- Overview title text remains static; research progress belongs in the status/progress area.
- Selected-item panel remains responsible for detailed Action/Recommendation.
