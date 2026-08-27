# YUMRAM v5.2.69 — Research PS 5.1 Safe Collection Fix

## Regression correction
V5.2.68 changed Research evidence inventory iteration to direct `.ToArray()` calls. That is unsafe when a runtime inventory is a normal PowerShell array. V5.2.69 restores collection-agnostic `foreach` enumeration: it works with arrays, generic lists, and other enumerable collections without using the PS5.1 `@($genericList)` conversion that caused `Argument types do not match`.

## Preservation boundary
The scanner implementation is unchanged from V5.2.66. The repair is limited to Research collection enumeration, Research schema/provider hardening already introduced in V5.2.67, and version/test metadata.
