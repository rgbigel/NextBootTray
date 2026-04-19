<#
    NextBootTray.ps1 v1.0.1
    Initializes tray icon, parses BCD, shows BurntToast buttons per GUID.
    No reboot until user clicks "Boot now".
#>
param([switch]$D)
function DBG { param([string]$M) if ($D) { $t=(Get-Date).ToString("HH:mm:ss.fff"); Write-Host "[DBG $t] $M" } }
Import-Module BurntToast -ErrorAction Stop
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
# (Full implementation omitted for brevity ? use your verified version)
