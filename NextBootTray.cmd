@echo off
setlocal

rem ============================================================
rem NextBootTray.cmd v3.0.0
rem Wrapper for NextBootTray.ps1
rem Version: 3.0.0
rem
rem - Normal startup uses scheduled task for non-interactive elevated launch
rem - Runs hidden by default (only tray icon visible)
rem - If -D is passed, shows a console with diagnostics
rem - If -STOP is passed, terminates running tray instances
rem - Only -D and -STOP are interpreted.
rem ============================================================

set SHOWCONSOLE=0
set STOPMODE=0

for %%A in (%*) do (
    if /I "%%A"=="-D" set SHOWCONSOLE=1
    if /I "%%A"=="-STOP" set STOPMODE=1
)

set SCRIPT=D:\OneDrive\cmd\NextBootTray.ps1

rem ------------------------------------------------------------
rem If -STOP is present: terminate running tray instances
rem ------------------------------------------------------------
if %STOPMODE%==1 (
    pwsh.exe -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%" -Stop
    exit /b
)

rem ------------------------------------------------------------
rem If -D is present: show console + elevation
rem ------------------------------------------------------------
if %SHOWCONSOLE%==1 (
    powershell.exe -NoProfile -ExecutionPolicy Bypass -Command ^
        "Start-Process pwsh.exe -Verb RunAs -ArgumentList '-NoProfile','-STA','%SCRIPT%','-D'"
    exit /b
)

rem ------------------------------------------------------------
rem No -D: run elevated scheduled task without UAC prompt
rem ------------------------------------------------------------
schtasks /Run /TN "NextBootTray-LogonElevated" >nul 2>&1
if errorlevel 1 (
    rem Fallback path if task does not exist yet.
    powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -Command ^
        "Start-Process pwsh.exe -Verb RunAs -WindowStyle Hidden -ArgumentList '-NoProfile','-STA','%SCRIPT%'"
)

exit /b
