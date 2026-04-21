<#
    Install-NextBootTray.ps1
    Version: 3.0.0

    PURPOSE:
      - Copy all verified NextBootTray sources from the repository
        into the runtime folder D:\OneDrive\cmd.
      - Preserve deterministic structure and ASCII encoding.
    - Never modify PATH.
      - Safe to re-run; overwrites existing files cleanly.

    REQUIREMENTS:
      - PowerShell 7+
      - Write access to D:\OneDrive\cmd
            - Run from within the NextBootTray repository
#>

param(
    [switch]$ElevatedChild
)

function Test-IsElevated {
    try {
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = [Security.Principal.WindowsPrincipal]::new($identity)
        return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    }
    catch {
        return $false
    }
}

if (-not (Test-IsElevated) -and -not $ElevatedChild) {
    $selfPath = if ($PSCommandPath) { $PSCommandPath } else { $MyInvocation.MyCommand.Path }
    $argList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $selfPath, '-ElevatedChild')

    try {
        Start-Process -FilePath 'pwsh.exe' -Verb RunAs -ArgumentList $argList -Wait
        exit 0
    }
    catch {
        Write-Warning 'Installer requires elevation to register NextBootTray-LogonElevated.'
        Write-Warning ("Elevation failed or was cancelled: {0}" -f $_.Exception.Message)
        exit 1
    }
}

$RepoRoot = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Path $MyInvocation.MyCommand.Path -Parent }
$Target   = "D:\OneDrive\cmd"
Write-Host "Installing NextBootTray v3.0.0..."
Write-Host "Source: $RepoRoot"
Write-Host "Target: $Target"

# Ensure target folder exists
if (-not (Test-Path $Target)) {
    Write-Host "Creating target folder..."
    New-Item -ItemType Directory -Force -Path $Target | Out-Null
}

# Copy main sources
$Files = @(
    "NextBootTray.cmd",
    "NextBootTray.ps1",
    "NextBoot-SetDefault.ps1",
    "NextBoot-BootNow.ps1"
)

foreach ($f in $Files) {
    $src = Join-Path $RepoRoot $f
    $dst = Join-Path $Target $f
    if (Test-Path $src) {
        Copy-Item -Force -Path $src -Destination $dst
        Write-Host "Copied: $f"
    } else {
        Write-Warning "Missing source file: $src"
    }
}

# Copy icon if present
$IconSrc = Join-Path $RepoRoot "NextBootTray.ico"
if (Test-Path $IconSrc) {
    Copy-Item -Force -Path $IconSrc -Destination (Join-Path $Target "NextBootTray.ico")
    Write-Host "Copied: NextBootTray.ico"
} else {
    Write-Warning "Icon file not found in repository."
}

# Register elevated logon startup task
try {
    $taskName = "NextBootTray-LogonElevated"
    $currentUser = "{0}\{1}" -f $env:USERDOMAIN, $env:USERNAME
    $scriptPath = Join-Path -Path $Target -ChildPath "NextBootTray.ps1"

    $action = New-ScheduledTaskAction -Execute "pwsh.exe" -Argument ("-NoProfile -STA -WindowStyle Hidden -ExecutionPolicy Bypass -File `"{0}`"" -f $scriptPath)
    $trigger = New-ScheduledTaskTrigger -AtLogOn -User $currentUser
    $principal = New-ScheduledTaskPrincipal -UserId $currentUser -LogonType Interactive -RunLevel Highest

    Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $principal -Force | Out-Null
    Write-Host "Configured logon scheduled task: $taskName"

    $runKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
    if (Test-Path -LiteralPath $runKey) {
        Remove-ItemProperty -Path $runKey -Name "NextBootTray" -ErrorAction SilentlyContinue
    }
}
catch {
    Write-Warning "Could not configure scheduled task startup."
    Write-Warning "Reason: $($_.Exception.Message)"
}

Write-Host "Installation complete."
Write-Host "NextBootTray is now ready in D:\OneDrive\cmd."
