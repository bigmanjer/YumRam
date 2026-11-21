# YUMRAM audit, competitor and open-source research — November 2026

Audited version: **5.14.0 beta**, `main` = `78585fb` (fresh clone from GitHub, branch `audit-5.15`).
Status words used below: **Verified** (read in code and/or measured on the test PC), **Documented** (from a
vendor's or Microsoft's own page), **Proposed** (not built), **Untested** (not run anywhere yet).

Test PC for every measurement here: Ryzen 7 4800H laptop, 8 cores / 16 threads, 2 L3 groups, 15.4 GB RAM,
Windows 11 Home build 26200.

---

## 1. Architecture (Verified, read from source)

| Layer | Files | What it does |
|---|---|---|
| Start | `Launcher/YumramLauncher.cs` → `YUMRAM.exe`; `App/YUMRAM.ps1`, `App/Bootstrap.ps1` | exe finds `App\YUMRAM.ps1`, starts Windows PowerShell 5.1 (STA, hidden), or runs `--apply-update`, `--rollback`, `--uninstall`. Bootstrap dot-sources 25 modules in a fixed order. |
| Install | `Launcher/YumramSetup.cs` → `YUMRAM-Setup-<v>.exe` | per-user install to `%LOCALAPPDATA%\Programs\YUMRAM`, zip embedded, keeps root `*.json/*.log`, Start menu + Apps entry. |
| Updates | `Core/Updates.ps1` + launcher `--apply-update` | daily GitHub `releases/latest` check, SHA-256 from GitHub's asset digest or `SHA256SUMS.txt`, staging, `.previous` backup, rollback. **Automatic updates stay as they are** (your requirement). |
| Shared state | `Core/Config.ps1` (`$script:Yum`, synchronized hashtables) | one dictionary shared by the UI thread and 4 runspaces; config = defaults merged with the user's `config.json` (missing keys added, user values kept). |
| Telemetry | `Core/Telemetry.ps1`, `Core/TelemetryWorker.ps1` | 2 runspaces: memory + CPU every 0.5 s; GPU (only while the Overview is visible), game and foreground every 1.2–5 s. |
| RAM engine | `Core/Controller.ps1`, `Core/Cleanup.ps1`, `Core/MemoryReclaim.ps1`, `Core/Safety.ps1`, `Core/Native.ps1` | controller runspace wakes ≤1 s; target maintenance with hysteresis, back-off and fallback; candidate scoring (`Get-YumCandidateProcesses`), trim plan (smallest-first + partial trim of big programs, 5.14), memory-area assist; Free/Deep reclaim with 5/15/30 s verification and a learned retention ratio. |
| CPU engine | `Core/CpuBalance.ps1` | own runspace, `SetWinEventHook(EVENT_SYSTEM_FOREGROUND)`; Gentle (Below Normal), Balanced (+ "make room" via **affinity**, self-check undo), Strong (Idle + EcoQoS + memory priority 2); battery → Strong; crash-safe restore file `cpu-balance.json`. |
| Leak watch | `Core/LeakWatch.ps1` | private bytes sampled each 60 s on the CPU worker, 30 min window, heuristic flag, one notice per program. |
| Intelligence | `Core/Intelligence.ps1`, `Core/Research.ps1` (118 k chars), `Core/Scanner.ps1`, `Core/ProcessGuide.ps1` | identity (path, signer, hash), classification with risk lanes (Protected / Safe to Manage / Candidate / Review / Unknown), manual organisation, user-triggered scan and research (only `https://www.bing.com` is contacted). |
| Optional cleanup | `Core/Bloatware.ps1` | **not Windows bloat**: closes listed background programs (Widgets, GameBarFTServer, SteamWebHelper, EpicWebHelper) and can stop manual-start services (off by default). |
| Startup | `Core/Startup.ps1`, `UI/StartupPage.ps1` | Run keys + Startup folders, on/off through Task Manager's `StartupApproved` flags. |
| Elevation | `Core/Elevation.ps1` | Ask / NoPrompt (scheduled task, highest privileges) / Never. |
| UI | `UI/Shell.ps1`, `UI/MainWindow.ps1`, `UI/Dialogs.ps1` (188 k chars), `UI/Tray.ps1`, `UI/Xaml/*` | one window, sidebar pages, only the UI thread touches WPF; tray; global hotkey. |
| Tests | `Tests/*Test.ps1` (54 + `Release514Test`) + `Tests/UI/FullUiProbe.ps1` (55 steps) | each test in its own process. |

**Documentation drift (Verified):** `Docs/ARCHITECTURE.md` still says "5.3.x" and does not mention CPU care,
leak watch, elevation modes, updates, installer or report-a-problem.

---

## 2. Source-code findings

| # | Severity | Where | Finding | Fix |
|---|---|---|---|---|
| F1 | **High** | `Core/Cleanup.ps1` memory-area assist (`AutoMemoryAreaAssist`, every **45 s**) | Automatic care flushes the **modified page list** and trims the system file cache every 45 s whenever Available is under the goal and YUMRAM is admin. Mem Reduct removes these "freeze" operations from automatic cleaning unless the user allows them (`REDUCT_MASK_FREEZES`, [main.c](https://raw.githubusercontent.com/henrypp/memreduct/master/src/main.c)); WinMemClean's `/Auto` excludes the "freeze-prone" standby/modified lists. Flushing the modified list forces page-file writes, then those pages fault back from disk. | Automatic path: never flush the modified list; trim the file cache at most every 10 min and only when the cache is large; keep both in Deep reclaim (user-pressed). |
| F2 | **High** | `Core/Bloatware.ps1` + `Cleanup.ps1` optional apps; `EnableOptionalBackgroundCleanup: true` | Automatic care may **close** a listed program (`CloseMainWindow`) in Safe/Balanced/Aggressive (`OptionalApps` 0/1/2). README says "Trim, don't kill — nothing is closed". Users never opted in. | Automatic care never closes programs unless the user turns on "Close listed background apps"; default off for new and existing users who never changed the list. |
| F3 | Medium | `Core/Safety.ps1` cached candidate path; `Cleanup.ps1` trim loop | Candidates are re-opened **by PID only**. If a process exits and Windows reuses the PID within the 1.5 s cache window, the trim hits a different process — possibly one that would be protected. Trimming is not destructive, but stale data must not authorise anything. | Keep each candidate's `StartTime`; before trimming, re-read it and skip on mismatch. |
| F4 | Medium | `Core/CpuBalance.ps1` make-room (`ProcessorAffinity`) | Hard affinity. Microsoft: affinity "is respected above any conflicting CPU Set"; CPU Sets are the soft, power-management-compatible way ([CPU Sets](https://learn.microsoft.com/en-us/windows/win32/procthread/cpu-sets)). Process Lasso uses CPU Sets for P/E-core and X3D CCD choices. The self-check (5.11) limits harm. | Use `SetProcessDefaultCpuSets` (Win10+), fall back to affinity only on failure. |
| F5 | Medium | `Core/Updates.ps1` | SHA-256 comes from the same GitHub release as the zip: protects against corruption, not against a compromised account/release. | Sign releases (SignPath once licence + CI exist) or ship an embedded public key and a signed manifest. |
| F6 | Medium | `Core/Elevation.ps1` NoPrompt | Highest-privilege task runs scripts from a user-writable folder (disclosed trade-off). | Keep opt-in; future: verify script hashes from the launcher before starting the task. |
| F10 | Medium | `Core/Controller.ps1` worker loop | **Found by the UI probe during this audit (Verified):** the worker clears `ReclaimRequest` and only later sets `ReclaimRunning` (inside `Invoke-YumMemoryReclaim`). In between, `Test-YumReclaimBusy` is false: the Free RAM / Deep buttons re-enable and a second click queues a second reclaim. Diagnostic run: request returned `True`, then immediately `running=False request=<empty>`. | `ReclaimTaken` flag set in the same lock that takes the request, cleared in `finally`; counted as busy. Probe step passes again (2 runs). |
| F7 | Low | `Core/Cleanup.ps1` `Get-YumIntelligentServiceCandidates` | Publisher filter regex contains `EA`, which matches any company with "ea" (e.g. Realtek, Creative). Errs on the safe side (skips more), but is sloppy. Feature is off by default. | Anchor publisher names. |
| F8 | Low | `Docs/ARCHITECTURE.md` | Drift (see §1). | Rewrite for 5.14/5.15. |
| F9 | Low | `UI/Dialogs.ps1` 188 k chars, `Core/Research.ps1` 118 k chars | Very large single files make regressions harder to spot. | Split by page only when a page is next changed (no sweeping refactor). |

Already fixed in 5.12–5.14 (Verified with tests): uninstall deleting the parent folder; broken issue forms;
backslash zip paths; programs over the per-pass budget never trimmed; CPU-care CPU pausing RAM care.

---

## 3. Competitor comparison

| Product | Better than YUMRAM | YUMRAM already better | Worth adopting |
|---|---|---|---|
| **Mem Reduct** (GPL-3.0, C) | registry-cache flush; volume write-cache flush; mature tray UX | goal-based targeting, per-program identity/safety, learning, CPU care, leak alerts | "freeze-prone" ops excluded from auto (F1); percent/interval triggers with cooldown |
| **WinMemoryCleaner** (GPL-3.0, C#) | process exclusion list; command-line switches; Windows-service mode; registry cache | same as above | CLI switches for scripting (e.g. `YUMRAM.exe --reclaim deep`) |
| **Process Lasso** (commercial) | persistent per-program rules (priority, I/O and memory priority, CPU Sets) enforced via IFEO; CPU Sets; IdleSaver/Performance Mode power plans; Instance Balancer; responsiveness graph | RAM goal + verified reclaim, plain-word explanations, built-in leak alerts, measured make-room self-check | CPU Sets (F4); per-program memory priority rules; power-plan switching while a game runs; "restraint history" |
| **ISLC** (freeware) | dual condition standby purge (standby ≥ X **and** free < Y); timer resolution | everything else | dual-condition rule for standby purge in Deep/automatic |
| **RAMMap** (Sysinternals) | page-level truth (lists, priorities, file pages) | automation | use `NtQuerySystemInformation(SystemMemoryListInformation)` to show standby by priority 0–7, like System Informer |
| **Win11Debloat / winutil** (MIT) | Windows app/feature debloat with undo | RAM/CPU care | Windows bloat page (see §6) |
| **WinMemClean** (Rust, MIT/Apache) | service with 15 min / 80 % / low-priority-standby-256 MB triggers | everything | "low-priority standby above N MB" trigger |
| **memclean** (Rust, MIT) | fullscreen-window game guard; SSD/HDD detection | identity, learning | skip memory-list ops on HDD systems; fullscreen check as extra game signal |

---

## 4. Open-source code worth learning from (read in source)

- **System Informer** (MIT) — [`SystemInformer/memlists.c`](https://raw.githubusercontent.com/winsiderss/systeminformer/master/SystemInformer/memlists.c): reads `SYSTEM_MEMORY_LIST_INFORMATION` (`PageCountByPriority[8]`, `RepurposedPagesByPriority[8]`, modified/free/zero counts). This is the data YUMRAM needs to decide *whether* a list operation is worth it (e.g. repurposing of priority-5 standby pages = real pressure).
- **EnergyStar** (MIT) — [`EnergyManager.cs`](https://raw.githubusercontent.com/imbushuo/EnergyStar/master/EnergyStar/EnergyManager.cs): EcoQoS on (`ControlMask=StateMask=EXECUTION_SPEED`) + Idle priority for background, off + Normal for foreground, `ApplicationFrameHost` child-window walk to find the real UWP app. YUMRAM should copy the **UWP child-window walk** idea (its foreground PID is wrong for UWP apps today — Proposed/Untested).
- **Mem Reduct** (GPL-3.0 — learn only, do not copy code into an all-rights-reserved project) — auto-clean cooldown and freeze-op mask.
- **WinMemoryCleaner** (GPL-3.0 — learn only) — per-process exclusion path and privilege set (`SeProfileSingleProcess`, `SeIncreaseQuota`, `SeDebug`).
- **Win11Debloat** (MIT) — `Config/Apps.json` (per-app `SelectedByDefault`, `Recommendation`), `Remove-SelectedApps.ps1` (`Remove-AppxPackage -AllUsers` + `Remove-AppxProvisionedPackage`), `Regfiles/` + `Regfiles/Undo`.
- **winutil** (MIT) — `config/tweaks.json`: every tweak stores `OriginalValue` / `OriginalType` / `UndoScript`. This is the right model for reversible Windows changes.

Licence note: YUMRAM has no licence (all rights reserved). Ideas and algorithms can be learned from any of
these; **code** from GPL projects must not be copied in. MIT code may be reused with its notice kept.

---

## 5. Windows APIs (Documented, Microsoft Learn)

| API | Min OS | Access | Use in YUMRAM | Verdict |
|---|---|---|---|---|
| `SetProcessInformation(ProcessMemoryPriority)` | Win8 | `PROCESS_SET_INFORMATION` | **soft trim**: set idle background programs to memory priority 2–4 so Windows trims/repurposes their pages first, with no trim cost | **Adopt** (Proposed) — measurable, reversible, documented |
| `SetProcessInformation(ProcessPowerThrottling, IGNORE_TIMER_RESOLUTION)` | Win10 2004+ (flag) | same | stop background programs holding 1 ms timers (battery, CPU wake-ups) | Adopt for CPU care Strong/battery |
| `SetThreadInformation(ThreadPowerThrottling / ThreadMemoryPriority)` | Win8 | `THREAD_SET_INFORMATION` | per-thread EcoQoS | Not worth it: needs thread handles in other processes, many threads, little gain over process-level |
| `SetProcessDefaultCpuSets` / `GetSystemCpuSetInformation` | Win10 | `PROCESS_SET_LIMITED_INFORMATION` | soft make-room; `EfficiencyClass`, `LastLevelCacheIndex` give P/E and CCD | **Adopt** (F4) |
| `CreateMemoryResourceNotification(Low)` | XP | none | Windows' own "low memory" signal for predictive care | Adopt as one input (thresholds undocumented) |
| `QueryWorkingSetEx` | Vista | `PROCESS_QUERY_INFORMATION` | sample pages to see how much of a working set is **shared** or already low priority — trimming shared pages frees nothing | Adopt in a C# helper (sampling only) |
| `SetProcessWorkingSetSizeEx` | Vista | `PROCESS_SET_QUOTA` | partial trim (5.14). **Verified here:** soft limits (`0xA`) trim to exactly the new maximum; restoring the default maximum (~1.4 MB) empties the whole set — never do that | in use |
| `NtSetSystemInformation(SystemMemoryListInformation / Combine / FileCache)` | undocumented | `SeProfileSingleProcess` / `SeIncreaseQuota` | Deep reclaim | keep, user-pressed; restrict in automatic (F1) |
| Job objects CPU rate (`JOBOBJECT_CPU_RATE_CONTROL_INFORMATION`) | Win8 | job rights | hard CPU caps | **Avoid** for other apps: hard caps stall threads; weight-based only for YUMRAM's own workers |
| PDH counters `Memory\Pages Input/sec`, `Page Reads/sec`, `Memory\Modified Page List Bytes`, `Process\Page Faults/sec` | all | none | detect paging and whether a trim caused disk reads | Adopt (cheap, already using PDH) |
| ETW (kernel memory/page-fault providers) | all | admin | deep diagnostics | Later, optional diagnostic mode only (cost) |

---

## 6. New features (genuinely new to YUMRAM), prioritised

1. **High — Windows bloat (your request).** A "Windows bloat" page, modelled on winutil's undo model and Win11Debloat's safety lists:
   - *Apps*: list installed and **provisioned** Appx packages that match a curated list (Bing News/Weather/Sports, Clipchamp, Solitaire, Teams (personal), Xbox app, Feedback Hub, Maps, Office Hub, OEM promos); never offer Store, Edge, Terminal, Photos, Calculator, Notepad, Xbox Identity Provider. Remove per user and optionally de-provision (so new users don't get it). Reinstall path: Microsoft Store.
   - *Settings*: tips/suggestions/ads in Start, lock screen, Settings and Explorer; Bing web results in Start search; Copilot; Recall; Widgets; consumer features — each a documented registry policy with the **original value saved** and a one-click undo.
   - *Never*: services disabled wholesale, Edge removal, Windows Update changes, Defender changes.
2. **High — Soft trim with memory priority** (`ProcessMemoryPriority`): before trimming an idle background program, lower its memory priority; Windows then repurposes its pages first, only when needed. Learn per program which works better (trim vs soft trim).
3. **High — Pressure-aware engine:** use hard faults (`Pages Input/sec`), standby repurposing by priority, commit vs limit, and the Windows low-memory notification, not only "Available GB under goal". Act earlier on a falling trend, and stop trimming a program whose pages come straight back (per-program effectiveness score, already partly learned globally).
4. **Medium — CPU Sets** instead of affinity (F4); P/E-core and CCD aware.
5. **Medium — Per-program rules** (memory priority, CPU priority, never trim / never hold back — partly there) persisted and visible in one place.
6. **Medium — Power plan while gaming** (Process Lasso Performance Mode equivalent), restored on exit.
7. **Medium — CLI** (`YUMRAM.exe --reclaim quick|deep`, `--status json`) for scripts and Task Scheduler.
8. **Low — Opt-in usage data** (your later item): off by default, shows exactly what is sent, aggregate numbers only (retention ratios, CPU model, which settings are used), no program names.

## 7. Performance plan for YUMRAM itself

Measured earlier on this PC (5.9): Overview visible ≈ 14 % of one core, hidden in tray ≈ tray-only, memory ≈ 120 MB after self-trim. Next: (a) CPU worker enumerates all processes every 1 s — share one enumeration between CPU care, leak watch and candidate scoring; (b) cache `Get-YumCachedExecutableIdentity` by path+size+mtime (signature checks are the most expensive call); (c) log rotation at 5 MB (Proposed; `YUMRAM.log` grows unbounded today — Untested claim, verify size limits).

## 8. Security & reliability

F3, F5, F6 above. Plus: keep online research opt-out and disclosed (only Bing, only name/publisher/product — Verified by code: only `https://www.bing.com` is contacted); report-a-problem scrubs user/PC names (5.13, tested); installer per-user, no admin (Verified). Code signing: SignPath Foundation is free but requires an OSI licence and CI builds; Azure Artifact Signing is paid and individual-eligibility is limited.

## 9. Roadmap (regression-safe order)

| Phase | Content | Why this order |
|---|---|---|
| 1 (now) | F1, F2, F3 + tests; ARCHITECTURE.md rewrite | safety and honesty before features |
| 2 | Windows bloat page (apps + settings with undo) | your explicit request; isolated module, no effect on RAM/CPU engines |
| 3 | Memory Engine 2.0: pressure signals (PDH + low-memory notification + list priorities), soft trim, per-program effectiveness | needs Phase 1 safety; measurable with existing retention learning |
| 4 | CPU Engine 2.0: CPU Sets, IGNORE_TIMER_RESOLUTION, UWP foreground fix, power plan while gaming; game benchmark harness (your TODO) | builds on 5.11 harness |
| 5 | Diagnostics: paging/disk, kernel pool, health report | needs Phase 3 signals |
| 6 | Product: CLI, rules page, signed releases, opt-in usage data | needs licence/CI decisions |

Every phase: baseline tests → narrow change → new test → full suite + UI probe → measured result on a test process (never experimental cleanup against your real programs).

## 10. First changes (this branch, `audit-5.15`)

1. **F1** `Core/Cleanup.ps1`: automatic memory-area assist no longer flushes the modified list; file-cache trim at most every 10 min (`AutoMemoryAreaAssistSeconds` default 600; existing users' 45 s value is migrated because nobody chose it — it was never in the UI).
2. **F2** `Core/Cleanup.ps1`, `Config`: new `AutoCloseOptionalApps` (default **false**); automatic care closes listed programs only when it is true. The list and manual tools stay.
3. **F3** `Core/Safety.ps1`, `Core/Cleanup.ps1`: candidates carry `StartTime`; trim skips a process whose start time no longer matches.
4. **F10** `Core/Controller.ps1`, `Core/Config.ps1`: `ReclaimTaken` closes the busy-state gap.
5. Tests: `Tests/Release515Test.ps1` covers all four (config migration with a real 5.14 config, a real
   child process for the PID check, the busy flag).

**Results on this branch (Verified, run on the test PC):** baseline before changes 56/56 tests; after
changes **57/57 tests** and the full UI probe **55/55 steps, 0 failures** (with an Intelligence database
present — a fresh clone without one fails the two Intelligence-selection steps on both the old and the new
code, which is a probe set-up limit, not an app defect).
