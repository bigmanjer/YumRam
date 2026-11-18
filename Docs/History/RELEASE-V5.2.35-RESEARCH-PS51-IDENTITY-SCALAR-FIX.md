# YUMRAM V5.2.36 — Research PowerShell 5.1 Identity-Signal Scalar Fix

## Scope

This candidate is based directly on V5.2.34 and changes only the proven Research runtime defect. V5.2.4 remains the stable rollback/control baseline.

## Root cause

PowerShell 5.1 can collapse a single `Where-Object` result to a scalar. V5.2.34 correctly array-materialized `RegistryEvidence`, but `identitySignals` remained scalar-sensitive and was followed by `.Count`.

## Fix

`identitySignals` and the online-search `$terms` collection are now explicitly array-materialized before their `.Count` checks.

## Regression coverage

The ResearchScalarCount regression now validates 0, 1, and multiple identity-signal matches and asserts that the unsafe production pattern cannot return.
