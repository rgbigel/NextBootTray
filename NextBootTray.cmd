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
rem - Only the -D flag is interpreted; other args are ignored
rem   for determinism.
rem ============================================================

set SHOWCONSOLE=0

for %%A in (%*) do (
    if /I "%%A"=="-D" set SHOWCONSOLE=1
)

set SCRIPT=D:\OneDrive\cmd\NextBootTray.ps1

rem ------------------------------------------------------------
rem If -D is present: show console + elevation
rem ------------------------------------------------------------
if %SHOWCONSOLE%==1 (
    powershell.exe -NoProfile -ExecutionPolicy Bypass -Command ^
        "Start-Process pwsh.exe -Verb RunAs -ArgumentList '-NoProfile','-STA','%SCRIPT%','-D'"
    exit /b
)

rem ------------------------------------------------------------
rem No -D: hidden window + elevation
rem ------------------------------------------------------------
powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -Command ^
    "Start-Process pwsh.exe -Verb RunAs -WindowStyle Hidden -ArgumentList '-NoProfile','-STA','%SCRIPT%'"

exit /b
