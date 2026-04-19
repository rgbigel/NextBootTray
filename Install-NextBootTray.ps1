<#
    Install-NextBootTray.ps1
    Version: 2.0.0

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

$RepoRoot = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Path $MyInvocation.MyCommand.Path -Parent }
$Target   = "D:\OneDrive\cmd"
Write-Host "Installing NextBootTray v2.0.0..."
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

# Copy documentation
$DocsSrc = Join-Path $RepoRoot "Docs"
if (Test-Path $DocsSrc) {
    Copy-Item -Force -Recurse -Path $DocsSrc -Destination (Join-Path $Target "Docs")
    Write-Host "Copied documentation."
}

# Register user logon startup entry
try {
    $runKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
    $runName = "NextBootTray"
    $runValue = '"D:\OneDrive\cmd\NextBootTray.cmd"'

    if (-not (Test-Path -LiteralPath $runKey)) {
        New-Item -Path $runKey -Force | Out-Null
    }

    New-ItemProperty -Path $runKey -Name $runName -Value $runValue -PropertyType String -Force | Out-Null
    Write-Host "Configured logon startup entry: HKCU Run -> NextBootTray"
}
catch {
    Write-Warning "Could not configure logon startup entry."
    Write-Warning "Reason: $($_.Exception.Message)"
}

Write-Host "Installation complete."
Write-Host "NextBootTray is now ready in D:\OneDrive\cmd."
