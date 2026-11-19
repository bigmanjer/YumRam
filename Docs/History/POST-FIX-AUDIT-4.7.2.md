# YUMRAM 4.7.2 Post-Fix Audit

## Fix
The Intelligence worker had a pipeline-output hazard when dot-sourcing supporting modules in a separate PowerShell runspace. Module-load output could contaminate EndInvoke(), causing the UI to receive an array instead of the scan-result object and fail on `.Items`.

The worker now suppresses dot-source output and validates/selects the final scan-result object before applying UI results.

## Additional release fixes
- Internal package folder/version synchronized to 4.7.2.
- VERSION and default config synchronized to 4.7.2.
- Main UI/Smoke test version references updated.
- Known-good 4.5.9 scanner implementation remains the scan baseline.
- No `$pid =` assignments detected.
- No Intelligence dispatcher local-variable closure pattern detected.

## Validation
- 19 PowerShell files
- 10 XAML files
- PowerShell BOM check: PASS
- XAML parse: PASS
- JSON parse: PASS
- ZIP integrity: PASS
- Intelligence worker final-result selection: PASS
- Supporting module dot-source output suppression: PASS
