# YUMRAM 4.9.4 — Expert Research Architecture

4.8.5 remains the read-only stable baseline. 4.9.4 is a separate development build.

## Engineering changes
- Local evidence classification now runs for every uncertain record; the old scan cap no longer prevents later records from receiving a placement decision.
- `ResearchMaxOnlineItemsPerScan` limits online lookups; local identity/classification runs for every uncertain record. The older `ResearchMaxItemsPerScan` key remains supported as a compatibility fallback.
- Registry matching uses literal token overlap instead of PowerShell wildcard matching.
- Research confidence is evidence-derived rather than fixed per category.
- Authenticode validity and signer/publisher corroboration contribute weighted evidence.
- WinGet matches contribute only when the returned text materially matches the scanned identity.
- Online research scores the returned RSS title/description for name/publisher corroboration.
- Research results persist the evidence scores and whether online research actually occurred.
- Unknown/weakly supported items remain in the non-destructive review/quarantine lane.
- Version markers are normalized to 4.9.4.

## Safety
Placement remains metadata/classification only. YUMRAM does not move or delete files based solely on research results.
