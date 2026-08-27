# YUMRAM 4.6.7

## Stability / Intelligence
- Intelligence window startup now uses WPF ContentRendered and Window.Tag state handoff instead of a PowerShell local-variable dispatcher closure.
- Protected, Games, Apps, and Services all route to the single Intelligence view/filter system.
- Saved Intelligence classifications remain visible when an item is not present in the current live scan.

## Memory / target
- Available RAM is the authoritative target metric.
- Working-set reduction is reported separately from Available-RAM improvement.
- Reclaim target-seeking follow-up passes bypass the per-process cooldown inside the same target-seeking operation so the optimizer can make additional attempts when memory pressure persists.
- Smart Intelligence optimization uses the normal target-seeking path rather than a force bypass.

## Safety
- Automatic service termination remains disabled.
- Unknown and protected items remain excluded from automatic management.
