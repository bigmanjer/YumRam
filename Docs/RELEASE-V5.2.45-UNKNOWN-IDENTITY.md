# YUMRAM V5.2.45

## Unknown Identity Safety + Persistent Research

- Unknown processes are treated as unknown-to-YUMRAM, not automatically suspicious.
- Missing executable identity, unsigned/untrusted executables without a verified publisher, and unavailable paths remain outside automatic cleanup.
- Unknown items are eligible for automatic research after a scan when `UnknownAutoResearchEnabled` is enabled.
- Research persists identity evidence and can reuse SHA-256/path/publisher/signer information on future scans.
- Intelligence details now show identity state, confidence, signature, SHA-256, and the reason an item remains Unknown.
- `UnknownAutoManage` defaults to false; a future explicit classification is required before an Unknown item becomes cleanup-eligible.

## Safety rule

An item classified as Unknown is never admitted to the cleanup candidate list by default. Research may later move it to an explicit safe/candidate classification; until then it remains review-only.
