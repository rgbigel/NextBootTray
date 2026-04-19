@echo off
setlocal
$11.0.1
set SHOWCONSOLE=0
for %%A in (%*) do ( if /I "%%A"=="-D" set SHOWCONSOLE=1 )
set SCRIPT=D:\OneDrive\cmd\NextBootTray.ps1
if %SHOWCONSOLE%==1 (
    powershell.exe -NoProfile -ExecutionPolicy Bypass -Command ^
        "Start-Process pwsh.exe -Verb RunAs -ArgumentList '-NoProfile','-STA','%SCRIPT%','-D'"
    exit /b
)
powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -Command ^
    "Start-Process pwsh.exe -Verb RunAs -WindowStyle Hidden -ArgumentList '-NoProfile','-STA','%SCRIPT%'"
exit /b
