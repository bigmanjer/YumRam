# Security policy

## Reporting a problem

Please **do not** open a public issue for a security problem. Use GitHub's private reporting instead:
**Security › Report a vulnerability** on https://github.com/bigmanjer/YumRam. Include the YUMRAM version
(About page), what you did and what happened. You will get an answer as soon as possible.

## Supported versions

Only the latest release receives fixes. YUMRAM updates itself (About › Check for updates).

## How YUMRAM protects you

- **Updates** come only from this repository's GitHub releases and are installed only if the download matches
  its published SHA-256. A previous version is kept (`YUMRAM.exe --rollback`).
- **Installer** is per-user (no administrator). Releases are not code-signed yet; Windows SmartScreen may warn.
- **Administrator rights** are optional. *Start without asking* creates a scheduled task with highest
  privileges; Settings explains the trade-off (programs running as you could change YUMRAM's files and gain
  administrator through it). Choose *Ask each time* to remove it.
- **Privacy:** no account, no telemetry. Network use: the daily update check (GitHub), optional online research
  (Bing plus up to 4 trustworthy result pages), the weekly shared game-results file (GitHub, sends nothing about
  you), and only if you opt in, your game benchmark results. Details: README › Privacy and Docs/COMMUNITY.md.
