# YUMRAM V5.2.15

Research transport hardened.

- Replaced cross-runspace JSON argument transport with atomic queue/config files.
- Uses explicit ConvertTo-Json -InputObject for deterministic collection serialization.
- Worker logs received record count before invoking research.
- Queue/config transport files are cleaned up on completion and timeout.
- Version/config/research engine aligned to 5.2.15.
