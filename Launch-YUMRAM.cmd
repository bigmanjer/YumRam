@echo off
setlocal EnableExtensions DisableDelayedExpansion
title YUMRAM v5.2.74

set "ROOT=%~dp0"
set "ROOT=%ROOT:~0,-1%"
set "PS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
set "APP=%ROOT%\App\YUMRAM.ps1"
set "LOG=%ROOT%\YUMRAM.log"
set "STARTLOG=%TEMP%\YUMRAM-startup.log"

>"%STARTLOG%" echo ================================================================
>>"%STARTLOG%" echo YUMRAM v5.2.74 STARTUP
>>"%STARTLOG%" echo Time: %DATE% %TIME%
>>"%STARTLOG%" echo Root: %ROOT%
>>"%STARTLOG%" echo Launcher: %~f0
>>"%STARTLOG%" echo ================================================================

echo.
echo YUMRAM v5.2.74
echo Startup log: %STARTLOG%
echo.

if not exist "%PS%" goto :powershell_missing
if not exist "%APP%" goto :app_missing

>>"%STARTLOG%" echo PowerShell: %PS%
>>"%STARTLOG%" echo App: %APP%
>>"%STARTLOG%" echo Preflight intentionally skipped for release startup.
>>"%STARTLOG%" echo Launching application...
echo Launching YUMRAM...

"%PS%" -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%APP%" >>"%STARTLOG%" 2>&1
set "RC=%ERRORLEVEL%"

>>"%STARTLOG%" echo Application exit code: %RC%
copy /y "%STARTLOG%" "%LOG%" >nul 2>&1

if "%RC%"=="0" goto :success
echo.
echo ================================================================
echo YUMRAM FAILED TO START
echo ================================================================
echo Exit code: %RC%
echo Log: %LOG%
echo.
type "%STARTLOG%"
echo.
echo Press any key to close...
pause >nul
exit /b %RC%

:powershell_missing
>>"%STARTLOG%" echo ERROR: Windows PowerShell 5.1 not found: %PS%
echo ERROR: Windows PowerShell 5.1 not found.
echo Log: %STARTLOG%
pause
exit /b 1

:app_missing
>>"%STARTLOG%" echo ERROR: Application missing: %APP%
echo ERROR: App\YUMRAM.ps1 was not found.
echo Expected: %APP%
echo Log: %STARTLOG%
pause
exit /b 2

:success
endlocal
exit /b 0
