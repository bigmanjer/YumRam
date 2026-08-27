# YUMRAM 4.9.0 — Intelligence Research Build

## Baseline protection
YUMRAM 4.8.5 Scanner-Argument-FIXED remains the stable baseline and is not modified. This build is a separate copy.

## Major changes
- Automatic research/enrichment for uncertain scanner records.
- Stronger identity evidence from Windows uninstall registry, file/publisher metadata, optional WinGet local catalog, and optional Bing Search RSS.
- Automatic placement into inventory lanes such as Protected, Security, Drivers / Hardware, Games / Gaming, User Background Apps, Identified Applications, Startup Inventory, Review Queue, or Unknown / Quarantine for Review.
- Explicit ActionLane and research-confidence metadata are stored with records.
- Startup inventory is included in the scanner.
- Fixed the System Inventory Low Risk filter mismatch (it previously looked for a Risk value never produced by the scanner).
- Fixed Intelligence live State values being blank.
- Research data is cached locally; network research only sends item identity fields, not local filesystem paths.
- Research never grants destructive authority: Protected and Unknown records remain non-automatic.
- Cleanup candidate fallback now recognizes the scanner's actual Safe to Manage/Candidate risk values.
- Main-window version text advanced to 4.9.0.

## Research behavior
Research is automatic after scanning, capped by `ResearchMaxItemsPerScan`, and cached for `ResearchCacheMaxAgeDays`. Online research can be disabled without disabling local identity enrichment.
