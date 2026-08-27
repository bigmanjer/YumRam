# YUMRAM V5.2.2 — Review Queue Resolution

## Core behavior

Review is now a temporary research state, not a terminal category.

1. Scan the system.
2. Apply local evidence: executable metadata, Authenticode, registry, WinGet and startup/process context.
3. Any non-manual record that still resolves to Review is sent through online research.
4. The evidence is evaluated again.
5. If a supported category is established, the item is automatically organized.
6. If all available research is exhausted without sufficient identity evidence, the item is moved to Unknown / Quarantine for Review.

Manual organization always overrides automatic research.

## Safety

Unknown items remain non-manageable. Security and driver classifications remain protected.

## UI

Intelligence now reports researched count, Review items resolved into categories, and unresolved items moved to Unknown.
