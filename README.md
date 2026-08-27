# YUMRAM

**Yumes Ultimate Memory Reclaim & Monitor**

YUMRAM is a Windows desktop utility for monitoring system memory/CPU/GPU activity and reclaiming RAM toward a configurable available-memory target. It combines live telemetry, protected-process rules, game detection, system inventory, local intelligence, and optional multi-source research to make cleanup decisions more deliberately than a simple "kill the biggest process" tool.

> **Status:** V5.2.74  
> **Platform:** Windows  
> **Runtime:** Windows PowerShell 5.1 + WPF  
> **License:** Not specified in this package

## What YUMRAM does

YUMRAM is built around a target-driven approach to memory management:

- Monitor **available RAM, memory usage, CPU, GPU 3D usage, and active game state**.
- Work toward a configurable **Available RAM target** instead of always trying to maximize free RAM.
- Use **Safe, Balanced, or Aggressive** cleanup modes.
- Preview planned cleanup actions before applying them.
- Protect the **foreground application**, detected games, configured protected processes, and YUMRAM itself.
- Detect known games automatically and optionally avoid cleaning the active game.
- Scan processes, services, installed applications/packages, startup items, and related system inventory.
- Classify items with a persistent **Intelligence** database.
- Research unresolved identities using local evidence and optional online corroboration.
- Keep unknown items in **Review/Quarantine** rather than automatically managing them.
- Optionally manage approved background applications and selected Windows services.
- Keep diagnostic logs and research/cache state locally.

## Main features

### Live monitoring

The dashboard displays:

- Available RAM
- RAM usage
- CPU usage
- GPU 3D usage
- Detected game
- Target status
- Telemetry freshness

Monitoring can be enabled from the main window. It is separate from one-time cleanup, so you can also choose **Reach Target Now** without leaving continuous monitoring enabled.

### Target-driven cleanup

The cleanup controller evaluates memory pressure and selects eligible candidates according to the configured mode.

The default configuration uses:

- **Safe:** minimal intervention
- **Balanced:** recommended
- **Aggressive:** maximum reclaim

Cleanup can also use follow-up passes when the target has not been reached and safe reclaimable candidates remain.

YUMRAM uses working-set trimming rather than intentionally terminating arbitrary processes. Optional applications/services are separately controlled and filtered.

### Safety and protection

YUMRAM contains explicit protection logic for important processes and situations. The default configuration protects items such as:

- Windows core processes
- Security components
- Explorer and shell components
- PowerShell/YUMRAM
- The foreground process
- The detected active game

Service cleanup is also guarded by conditions such as service start mode, dependency checks, and a list of core/security/vendor services that should not be touched.

> **Important:** No cleanup utility can guarantee that every Windows configuration is safe. Review your settings and understand what an optional cleanup action does before enabling it.

### Intelligence and Research

The Intelligence Center separates discovery from decision-making.

**RUN SCAN** builds a current inventory.  
**RUN RESEARCH** investigates unresolved records.

The research pipeline can combine evidence from sources such as:

- Windows Registry
- Authenticode/signature information
- File version metadata
- WinGet local catalog data
- Windows service metadata
- AppX package identity
- Verified web sources
- GitHub repository corroboration
- Reddit community context

The project is designed so that **unknown items are not automatically managed**. Manual classifications are persisted and reused on later scans.

Research state is also persisted so completed identities do not need to be rediscovered every time.

## Getting started

### Requirements

YUMRAM is packaged for:

- Windows 10/11 systems capable of running **Windows PowerShell 5.1**
- A desktop session with WPF available
- Administrator privileges may be required for some system-level operations

The included launcher explicitly looks for:

```text
%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe
```

### Run from the extracted folder

1. Download or clone the repository.
2. Extract the project so the folder structure remains intact.
3. Run:

```text
Launch-YUMRAM.cmd
```

For a windowed launcher, you can also use:

```text
Launch-YUMRAM.vbs
```

The launcher writes startup/application output to:

```text
YUMRAM.log
```

A temporary startup log is also created under the Windows `%TEMP%` directory while launching.

### Run the PowerShell entry point directly

The main application entry point is:

```text
App\YUMRAM.ps1
```

The project bootstrap loads the core and UI modules from the repository.

For normal use, the provided launcher is recommended because it checks for the expected PowerShell runtime and records startup failures.

## First-use workflow

A sensible first run is:

1. Open YUMRAM with the launcher.
2. Leave **Balanced** mode selected.
3. Review the **Memory Goal** and set an Available RAM target appropriate for your machine.
4. Start with **Preview What Will Be Cleaned**.
5. Run **Scan** from the Intelligence Center to build the live inventory.
6. Review unresolved items before using **RUN RESEARCH**.
7. Enable automatic monitoring only after you are comfortable with the cleanup policy.
8. Keep game protection enabled if you use YUMRAM while gaming.

## Configuration

Default settings live in:

```text
Config\default-config.json
```

The configuration includes controls for:

- Memory targets and pressure thresholds
- Cleanup pass limits
- Candidate cooldowns
- Foreground/game protection
- Game detection
- Optional background cleanup
- Optional service cleanup
- Telemetry intervals
- Scanner limits
- Research limits, timeouts, cache age, and sources
- Intelligence database/cache behavior
- Target maintenance and fallback cleanup

The shipped configuration is conservative in several important areas. For example, optional service cleanup is disabled by default and automatic unknown-item management is disabled.

## Project structure

```text
YUMRAM-V5.2.74/
├── App/
│   ├── Bootstrap.ps1
│   └── YUMRAM.ps1
├── Config/
│   └── default-config.json
├── Core/
│   ├── Bloatware.ps1
│   ├── Cleanup.ps1
│   ├── Config.ps1
│   ├── Games.ps1
│   ├── Intelligence.ps1
│   ├── Logging.ps1
│   ├── Native.ps1
│   ├── Research.ps1
│   ├── Safety.ps1
│   ├── Scanner.ps1
│   ├── Telemetry.ps1
│   └── TelemetryWorker.ps1
├── Docs/
│   ├── ARCHITECTURE.md
│   └── release and audit documentation
├── Tests/
│   ├── Preflight.ps1
│   ├── SmokeTest.ps1
│   ├── StaticTest.ps1
│   └── regression/audit tests...
├── UI/
│   ├── Dialogs.ps1
│   ├── MainWindow.ps1
│   └── Xaml/
├── Launch-YUMRAM.cmd
├── Launch-YUMRAM.vbs
├── VERSION
└── README.md
```

## Testing

The repository includes several validation and regression scripts.

### Preflight validation

```powershell
.\Tests\Preflight.ps1 -Root (Split-Path -Parent $PWD)
```

The preflight checks PowerShell parsing plus XAML and JSON validity.

### Smoke test

```powershell
.\Tests\SmokeTest.ps1
```

The smoke test verifies the expected project files and parses key XAML/JSON files.

### Static audit

```powershell
.\Tests\StaticTest.ps1
```

The static audit performs broader PowerShell 5.1 parser checks, file/version consistency checks, XAML/JSON validation, and project-specific architecture safeguards.

> Runtime qualification on the target Windows machine is still important. Passing static checks does not prove that every Windows version, driver, service, game, or third-party application behaves identically.

## Research and online access

YUMRAM's research subsystem can use optional online corroboration in addition to local Windows evidence.

The shipped configuration enables online research:

```json
"EnableOnlineResearch": true
```

Research uses configured providers and stores research/cache state locally. If you are packaging YUMRAM for other users, explain your own privacy expectations and consider whether online research should be disabled by default for your distribution.

## Logs and local state

You may see local runtime files such as:

```text
YUMRAM.log
intelligence-db.json
research-cache.json
research-history.json
research-status.json
research-live.json
```

Not every file is present before the corresponding feature is used.

For a public GitHub repository, consider adding runtime/generated files to `.gitignore` rather than committing personal machine state.

## GitHub-friendly `.gitignore`

A basic starting point:

```gitignore
# Runtime logs
YUMRAM.log
*.log

# Local intelligence / research state
intelligence-db.json
research-cache.json
research-history.json
research-status.json
research-live.json

# Temporary files
*.tmp
*.bak

# PowerShell/editor noise
.vscode/
.idea/
```

Adjust this list if any of those files are intentionally part of your release.

## Architecture

At a high level, the application is split into:

```text
Windows APIs / system counters
            |
            v
       Telemetry layer
            |
            v
      System snapshot
        /         \
       /           \
      v             v
     WPF UI     Background controller
                    |
                    +--> pressure decision
                    +--> candidate filtering
                    +--> safety checks
                    +--> cleanup / trimming
                    +--> before/after measurement

System Scan
    |
    v
Intelligence database
    |
    v
Review / Research
    |
    +--> Organized
    +--> Unknown / Quarantine
    +--> Research Error
```

The project documentation in `Docs/` contains additional release audits, regression notes, and research-engineering details.

## Current release

### V5.2.74

This release focuses on Research/Intelligence hardening, including:

- Safer collection handling for Windows PowerShell 5.1
- Better separation of online "no match" results from operational online errors
- Stronger multi-source identity promotion
- Protection against stale research UI/checkpoint updates overwriting terminal states
- Terminal quarantine when the research worker fails
- De-duplicated research history terminal events
- Synchronized version/test metadata

The package notes explicitly call out that **Windows PowerShell 5.1 runtime qualification is still required on the target machine**.

## Known limitations

- YUMRAM is **Windows-only**.
- The application depends on **Windows PowerShell 5.1** rather than PowerShell 7 as its primary runtime.
- Available RAM reported by Windows does not translate directly into guaranteed reclaimed RAM.
- Working-set trimming is a request to Windows, not a promise to reclaim a specific number of megabytes.
- Online research depends on network access and external source availability.
- Hardware, drivers, security software, games, and third-party applications can behave differently across systems.
- The project's static/regression tests cannot replace testing on real target machines.

## Contributing

Before opening a pull request:

1. Keep PowerShell 5.1 compatibility in mind.
2. Preserve the protected-process and safety rules.
3. Add or update regression coverage for behavior changes.
4. Run the provided preflight, smoke, and static checks.
5. Update `VERSION` and related release metadata when appropriate.
6. Avoid committing local runtime state, logs, or machine-specific intelligence/research data.

## Disclaimer

YUMRAM is a system-management utility that can affect process working sets and, when explicitly configured, optional background applications/services.

Use it at your own discretion. Review cleanup previews, protection settings, and optional cleanup configuration before enabling automatic behavior. The project does not guarantee improved performance on every system.
