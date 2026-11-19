# YUMRAM 4.6.9 Fixes

- Monitoring is user-started; automatic monitoring is disabled by default and forced off at release migration.
- Intelligence automatically begins its scan when opened.
- Intelligence filter ComboBox has an explicit dark closed-state template so the selected value remains readable.
- Intelligence and System Inventory scans have a 90-second timeout and explicit success/failure state.
- Service metadata is collected in one bulk Win32_Service query to reduce WMI/CIM latency.
- Main RAM usage value has explicit spacing from the "RAM Usage" label.
- No process/service termination is enabled by this release.
