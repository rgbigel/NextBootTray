<#
    Install-NextBootTray.ps1
    Version: 1.0.1

    PURPOSE:
      - Copy all verified NextBootTray sources from the repository
        into the runtime folder D:\OneDrive\cmd.
      - Preserve deterministic structure and ASCII encoding.
      - Never modify PATH or registry beyond protocol handlers.
      - Safe to re-run; overwrites existing files cleanly.

    REQUIREMENTS:
      - PowerShell 7+
      - Write access to D:\OneDrive\cmd
      - Repository located at D:\OneDrive\Git_Repositories\PS\NextBoot
#>

$RepoRoot = "D:\OneDrive\Git_Repositories\PS\NextBoot"
$Target   = "D:\OneDrive\cmd"
Write-Host "Installing NextBootTray v1.0.1..."
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

Write-Host "Installation complete."
Write-Host "NextBootTray is now ready in D:\OneDrive\cmd."
