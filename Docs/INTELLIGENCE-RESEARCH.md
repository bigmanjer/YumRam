# YUMRAM 4.6 Smart Intelligence Research Basis

YUMRAM 4.6 consolidates manual process/service/game lists into a conservative classification layer.

Design principles were checked against multiple independent sources:

- Microsoft Learn / Sysinternals Process Explorer: process identity, handles, loaded DLLs and process relationships are useful evidence when understanding what a process is doing.
- Microsoft Learn / RAMMap: working sets and standby/available memory are different concepts; RAM pressure should not be treated as a simple process-killing contest.
- Microsoft Learn / Windows driver security: process termination requires extreme caution and protected/PPL security processes must not be terminated.
- Microsoft Learn / anti-malware protected services: Windows has explicit protected-process infrastructure for security components.
- Valve Steamworks documentation: game installs/launchers and process paths can provide useful game-related context, but game detection should remain heuristic rather than assume every executable is safe to stop.
- NVIDIA documentation: graphics drivers and management services are hardware infrastructure and should be treated as protected rather than generic background processes.
- OWASP Developer Guide / Secure Product Design: secure-by-default, fail-safe, least privilege, defense in depth, and keeping complexity manageable are appropriate principles for an optimizer that can affect running processes.

YUMRAM therefore uses the following safety hierarchy:

1. Security, Windows core, drivers/hardware, active game, and YUMRAM itself: Protected.
2. Known optional background applications with strong identity evidence: Safe-to-Manage candidates.
3. Ordinary user applications and services: Review / explicit approval.
4. Unknown identity: Unknown / no automatic action.

The classifier is intentionally not a malware detector. It uses local evidence such as process name, executable path, publisher metadata, Authenticode status, Windows location, game-related paths, configured protected names, and current foreground/game state. Low-confidence classifications are never used as an automatic kill/disable decision.
