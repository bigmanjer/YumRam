# YUMRAM 4.8.0 - New Scanner Architecture

## Purpose
YUMRAM 4.8.0 replaces the previously fragile scanner integration with a self-contained scanner engine.

## Scanner design
- Process inventory uses one bulk `Win32_Process` query for parent relationships and `Get-Process` for live memory/process metadata.
- Service inventory uses one bulk `Win32_Service` query and maps running `Get-Service` objects to that metadata.
- App inventory uses `Get-AppxPackage` when available.
- Executable identity uses `FileVersionInfo` and does not require Authenticode verification during the normal scan path.
- The scanner does not depend on Games.ps1, Safety.ps1, Bloatware.ps1, or Intelligence.ps1 to produce its result.
- The scanner returns a single structured result with Processes, Services, Apps, Records, Errors, and explicit Status.

## Safety
The scanner is observational. It does not terminate processes or stop services. Unknown items are classified as Unknown and are not automatic cleanup candidates.

## Intelligence integration
The Intelligence window consumes the scanner result, merges the live classifications into the persistent local catalog, preserves saved classifications for items not currently running, and binds the UI through `ItemsSource`.

## UI
The Settings footer now uses a dedicated validation row so status text cannot overlap Reset/Apply/Close.
