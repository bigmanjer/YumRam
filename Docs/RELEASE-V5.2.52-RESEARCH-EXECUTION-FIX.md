# YUMRAM v5.2.52 — Research Execution Fix

## Problem
The Research UI could show activity without giving reliable proof that the worker was executing or that the UI was reading the worker's status file.

## Fix
- Shared research-status path is now rooted at the application root for both UI and worker.
- Manual research explicitly logs acceptance.
- Worker explicitly logs startup, per-item execution, online execution, completion, and PowerShell error stream output.
- Worker timeout is configurable and defaults to 30 minutes for large sequential queues.
- Online research is bounded but explicitly attempted while slots remain, rather than being hidden behind a UI-only review classification.
- Release/config/research engine version is synchronized to 5.2.52.

## Contract
RUN RESEARCH -> local evidence -> bounded online corroboration -> classification -> organization -> persistence -> removal from active research queue.
