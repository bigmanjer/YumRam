# Contributing to YUMRAM

Thanks for helping. YUMRAM runs on **Windows PowerShell 5.1** (not PowerShell 7) with WPF, so
please test changes there.

## Before you open a pull request

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File Tests\Run-AllTests.ps1
```

All tests must pass. GitHub Actions runs the same command on `windows-latest`.

For anything that changes memory behaviour, also run the app and report numbers: Available RAM
before/after (after the 1.5 s settle), YUMRAM CPU while monitoring, and anything you saw in
`YUMRAM.log`.

## Rules that prevent real bugs

`Tests\PowerShell51PitfallScanTest.ps1` enforces these; each one broke YUMRAM before:

- Wrap statements used as values in `$( )`: `-TopN $(if($x){16}else{10})`, never `(if ...)`.
- Use double quotes for `` `n ``/`` `t `` escapes; single quotes print them literally.
- Give `-f` as many arguments as placeholders, and parenthesize arithmetic in argument lists:
  `-f $a,($b/1MB)`.
- `Sort-Object` has no `-Ascending`; use `@{Expression='X';Descending=$true}` for mixed order.
- No `System.Timers.Timer` scriptblock handlers. Use the controller worker or a `DispatcherTimer`.
- Helpers that tolerate missing data take `[AllowNull()]` parameters, not `Mandatory`.
- Never wrap a `List[object]` in `@()`; call `.ToArray()`.
- Parameters that receive the config must be `[System.Collections.IDictionary]`, not
  `[hashtable]` (a `[hashtable]` parameter silently copies an ordered dictionary).

## Style

- Source files are UTF-8 **with BOM** and CRLF (`.gitattributes` enforces CRLF; the BOM is checked
  by `Tests\StaticTest.ps1`). YUMRAM is started by `YUMRAM.exe` (built from `Launcher\YumramLauncher.cs` by `Tools\Build-Launcher.ps1`).
- Do not touch WPF objects from a worker runspace; publish data and let the UI timer render it.
- Bump `VERSION` for releases; `Config/default-config.json` `Version` and `ResearchEngineVersion`
  must match it.
- Never commit `config.json`, logs or the learned `*.json` data files (they describe the
  contributor's PC).
