# 5.2.39 target-driven cleanup refinement
- Adaptive selection is smallest-working-set-first, with safety and CPU idleness as tie-breakers.
- Added target-locked cleanup escalation: when adaptive cleanup stalls below the target, the cleaner automatically falls back to the earlier broader ranking strategy.
- Fallback remains protected-process aware and uses working-set trimming only; no process termination is introduced.
- Added configurable fallback stall threshold, passes, process count, trim budget, and score floor.

# V5.2.28 — Intelligence Overhaul

- Reworked Intelligence UI and research controls.
- Removed redundant Optimize control from Intelligence.
- Added explicit research views and actions.

## 4.5.9

- Fixed System Inventory filter/search binding and selection contrast.
- Inventory scan now reports per-category errors instead of failing the whole result.
- Added live text search across processes, services, apps, and startup entries.
- Widened/refined scan controls.

﻿## 4.5.9
- Fixed About/Info dialog failure caused by undefined DoneTop reference under StrictMode.
- Re-audited dialog event wiring and version metadata.

# YUMRAM 4.5.9

- Live Available-RAM telemetry keeps raw byte precision and exposes clearer target diagnostics.
- System Inventory is refreshed automatically while open (configurable interval) across processes, services, AppX apps, and startup entries.
- Optional Services manager now shows current reviewable/stoppable services and lets users explicitly approve selections.
- Game priority labels are clearer: Keep Existing, Normal (Default), Above Normal (Game Preference), High (Advanced).
- Settings/About metadata and visual spacing refreshed without replacing the specialized GUI.
- Preserved native WPF scrolling and UTF-8 XAML loading.

## 4.5.9 — Task Manager-style system inventory and UI selection repair
- Expanded system scan into Processes, Services, Apps, and Startup inventory views.
- Added parent PID and session information to process scan rows.
- Fixed scanner filtering before the background scan completed.
- Hardened selection handling and readable selected-row styling.
- Preserved native WPF scrolling.

## 4.5.9 — Launcher/Preflight hardening

- Removed UTF-8 BOM from CMD/VBS launchers so `cmd.exe` and Windows Script Host do not interpret BOM bytes as source text.
- Added Windows PowerShell preflight parsing of all PowerShell modules plus XAML/JSON validation before application startup.
- Startup failures now print the collected startup details to the console and persist them to the root `YUMRAM.log`.

## 4.5.9 — Telemetry & Background Manager Stability

- Split core, GPU, and game telemetry into independent non-overlapping timers so slow GPU/game enumeration cannot hold up RAM/CPU telemetry.
- Reduced UI work when no new snapshot is available, improving scrolling responsiveness.
- Reworked Optional Background Cleanup manager with live-PC discovery, publisher/risk display, multi-select add/remove, and broader opt-in catalog.
- Preserved cooperative-only optional app shutdown; no forced kill is used by the automatic bloatware layer.
- Refined custom scrollbar template and reduced repeat-button event frequency.
- GPU dashboard/graph color changed to pastel light blue (`#B7E3FF`).

# Changelog

## 4.4.1 — Scanner / Telemetry / UX hardening

- Added evidence-based PC background activity scanner.
- Added process/service risk classification and scan dialog.
- Added manual End Task to Top Memory Processes with confirmation and hard protection rules.
- Separated telemetry sampling from cleanup controller to reduce delayed telemetry.
- Added telemetry freshness indicator.
- Reworked scrollbar styling to keep native ScrollViewer behavior for better responsiveness.
- Expanded optional background software recommendations across Microsoft and third-party vendors.
- Preserved existing YUMRAM purple dashboard and graph colors.

# Changelog

## 4.4.1
- Restored three persistent graph series: RAM, CPU, GPU 3D.
- Target UI now refreshes independently of telemetry snapshot version, so changing the target is immediately reflected.
- Preview Cleanup now calls the non-mutating cleanup core directly, avoiding queue/switch argument ambiguity.
- Added dedicated WPF Settings/About and Top Memory Processes dialogs.
- Improved scrollbar styling with hover/drag states and wider thumb.
- Added a curated recommended optional-background catalog with risk notes; recommendations are user-approved additions rather than hidden automatic actions.
- Added explicit game-priority explanation and confirmation before High priority.
- Preserved KeepExisting as the default game-priority behavior.

## 4.3.0
- Prodigy merge baseline.

## 4.5.9 — Telemetry/UI integration repair
- Fixed frozen dashboard and missing graph lines by wiring worker SnapshotVersion into the UI refresh contract.
- Added editable WPF Settings dialog with monitoring, cleanup, game, optional-background, and scanner controls.
- Moved system/background scans off the UI thread using background runspaces plus UI polling.
- Improved cleanup preview with Refresh and explicit non-mutating plan display.
- Preserved the simple native WPF ScrollViewer baseline.

## 4.5.9 — Dashboard and configuration repair
- Fixed telemetry snapshot version propagation so live dashboard cards and RAM/CPU/GPU graph series redraw from worker-published snapshots.
- Core telemetry cadence is configurable and defaults to 0.5 seconds; CPU remains sampled on the recommended one-second performance-counter cadence.
- System scan and optional-background scan are now background-runspace operations so the WPF UI remains responsive.
- Optional background manager now reports scan progress/results and exposes reason text.
- Cleanup Preview is refreshable and explicitly read-only.
- Settings is now a full editable WPF dialog covering memory targets, telemetry intervals, pressure thresholds, cleanup pass limits, game behavior, optional cleanup, and scanner controls.
- Retained the simple native WPF ScrollViewer baseline for reliability.


## 4.5.9

UX and scanner reliability pass: fixed optional-app scan result visibility, widened scan controls, improved game-priority labels, and improved settings/dialog spacing.

## 5.2.23
- Hardened Review research queue predicate so protected/terminal items are not unnecessarily researched.
- Optional online corroboration failures no longer invalidate an otherwise terminal local classification.
- Empty research queues are true no-ops and no longer replace the active Intelligence collection.


## 5.2.24
- Clears stale protected-item Research Error states during Intelligence hydration.
- Prevents Protected records from re-entering the research queue solely because of legacy Research Error state.


## 5.2.25
- Fixed concurrent process identity collisions: live process records now use unique instance keys while retaining a stable executable identity for research and persistence.
- Intelligence database storage now keys executable profiles by stable identity rather than live PID-instance keys.
- Live/saved Intelligence merging now matches records by StableIdentityKey, preventing concurrent Chrome/Discord/etc. instances from collapsing into one saved record.
- Added StableIdentityKey to the canonical Intelligence record schema and regression checks for unique live instance identity.
- Updated release metadata to 5.2.25.
