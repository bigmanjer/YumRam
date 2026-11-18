# YUMRAM V5.2.12 — Research Empty-Queue Fix

## Problem
V5.2.11 could launch the asynchronous research worker with a null-only serialized record array. Windows PowerShell 5.1 then rejected the mandatory `Records` binding with an empty-array error.

## Fix
- Research queues now accept empty input as a safe no-op.
- Research launch filters null records before worker creation.
- Worker filters null records before invoking the research engine.
- Scan result records are filtered for null entries before starting automatic research.
- Static regression tests cover all three queue boundaries.

## Compatibility
Windows PowerShell 5.1 / WPF.
