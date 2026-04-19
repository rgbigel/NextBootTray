@echo off
setlocal

rem ============================================================
rem NextBootTray.cmd
rem Wrapper for NextBootTray.ps1
rem Version: 1.0.1
rem
rem - Forces elevation via Start-Process -Verb RunAs
rem - Runs hidden by default (only tray icon visible)
rem - If -D is passed, shows a console with diagnostics
rem - If -STOP is passed, terminates running tray instances
rem - Only -D and -STOP are interpreted.
rem ============================================================

set SHOWCONSOLE=0
set STOPMODE=0
set FORCEMODE=0

for %%A in (%*) do (
    if /I "%%A"=="-D" set SHOWCONSOLE=1
    if /I "%%A"=="-STOP" set STOPMODE=1
    if /I "%%A"=="-Force" set FORCEMODE=1
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
    if %FORCEMODE%==1 (
        powershell.exe -NoProfile -ExecutionPolicy Bypass -Command ^
            "Start-Process pwsh.exe -Verb RunAs -ArgumentList '-NoProfile','-STA','%SCRIPT%','-D','-Force'"
    ) else (
        powershell.exe -NoProfile -ExecutionPolicy Bypass -Command ^
            "Start-Process pwsh.exe -Verb RunAs -ArgumentList '-NoProfile','-STA','%SCRIPT%','-D'"
    )
    exit /b
)

rem ------------------------------------------------------------
rem No -D: hidden window + elevation
rem ------------------------------------------------------------
if %FORCEMODE%==1 (
    powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -Command ^
        "Start-Process pwsh.exe -Verb RunAs -WindowStyle Hidden -ArgumentList '-NoProfile','-STA','%SCRIPT%','-Force'"
) else (
    powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -Command ^
        "Start-Process pwsh.exe -Verb RunAs -WindowStyle Hidden -ArgumentList '-NoProfile','-STA','%SCRIPT%'"
)

exit /b
