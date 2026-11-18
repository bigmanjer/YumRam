# YUMRAM 5.2.49 — Research Engine Overhaul

## Goal

Research is now a durable identity-resolution workflow: collect local evidence first, corroborate with trusted web sources only when required, make one authoritative classification decision, persist the evidence fingerprint, and remove the item from the research/review queue when the decision reaches a terminal state.

## Evidence model

The engine prioritizes file version metadata, Authenticode status/signer, installed-software registry evidence, WinGet local catalog data, Windows service metadata, and verified web-source corroboration. NIST's SWID guidance supports using structured software identity metadata such as product, version, publisher, and artifacts for software identification. Microsoft documents digital signatures and publisher/product/version attributes as useful application identity signals, and recommends publisher identity as more update-resilient than raw path matching in application-control policy.

## Windows PowerShell 5.1 hardening

Web verification uses `Invoke-WebRequest -UseBasicParsing`; it does not depend on the legacy `ParsedHtml` object model. Microsoft documents `-UseBasicParsing` as the safe path for PowerShell 5.1 web requests and notes recent security changes around web-content parsing.

## Terminal states

`Organized` means the item has enough independent evidence to place it into a concrete category. `Unknown` means research completed but identity remained insufficiently corroborated. `Research Error` is non-terminal and remains retryable. A valid cache entry suppresses repeat research until its identity key or research-engine revision changes or it expires.

## UI model

The live research snapshot merger has been retired. It created a second mutable data path while the worker was still writing and was the source of repeated `Data`, `Signature`, and `Summary` property failures. Progress is now durable-status driven; the final worker output is the only source used to mutate the authoritative Intelligence database/UI records.
