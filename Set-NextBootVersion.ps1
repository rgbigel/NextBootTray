<#
    Set-NextBootVersion.ps1
    Synchronizes NextBoot version references across the repository.

    Usage:
      pwsh -File .\Set-NextBootVersion.ps1 -Version 1.0.2
      pwsh -File .\Set-NextBootVersion.ps1           # uses VERSION.txt
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [ValidatePattern('^\d+\.\d+\.\d+$')]
    [string]$Version
)

$RepoRoot = Split-Path -Parent $PSCommandPath
$VersionFile = Join-Path $RepoRoot 'VERSION.txt'

if (-not (Test-Path $VersionFile)) {
    throw "Missing VERSION.txt at: $VersionFile"
}

if ([string]::IsNullOrWhiteSpace($Version)) {
    $Version = (Get-Content -Path $VersionFile -TotalCount 1).Trim()
}

if ($Version -notmatch '^\d+\.\d+\.\d+$') {
    throw "Invalid version '$Version'. Expected semantic version format: X.Y.Z"
}

Set-Content -Path $VersionFile -Value $Version -NoNewline -Encoding ascii

function Set-VersionInFile {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Pattern,
        [Parameter(Mandatory = $true)][string]$Replacement
    )

    if (-not (Test-Path $Path)) {
        Write-Warning "Skipping missing file: $Path"
        return
    }

    $raw = Get-Content -Path $Path -Raw
    $updated = [regex]::Replace($raw, $Pattern, $Replacement)

    if ($updated -ne $raw) {
        Set-Content -Path $Path -Value $updated -NoNewline -Encoding ascii
        Write-Host "Updated: $Path"
    } else {
        Write-Host "No change: $Path"
    }
}

$files = @(
    @{
        Path        = (Join-Path $RepoRoot 'README.md')
        Pattern     = '(?m)^(#\s+NextBootTray\s+v)\d+\.\d+\.\d+(\s*)$'
        Replacement = ('$1' + $Version + '$2')
    },
    @{
        Path        = (Join-Path $RepoRoot 'NextBootTray.ps1')
        Pattern     = '(?m)^(\s*NextBootTray\.ps1\s+v)\d+\.\d+\.\d+(\s*)$'
        Replacement = ('$1' + $Version + '$2')
    },
    @{
        Path        = (Join-Path $RepoRoot 'NextBootTray.cmd')
        Pattern     = '(?m)^(rem\s+NextBootTray\.cmd\s+v)\d+\.\d+\.\d+(\s*)$'
        Replacement = ('$1' + $Version + '$2')
    },
    @{
        Path        = (Join-Path $RepoRoot 'Install-NextBootTray.ps1')
        Pattern     = '(?m)^(\s*Version:\s+)\d+\.\d+\.\d+(\s*)$'
        Replacement = ('$1' + $Version + '$2')
    },
    @{
        Path        = (Join-Path $RepoRoot 'Install-NextBootTray.ps1')
        Pattern     = '(?m)^(\s*Write-Host\s+"Installing\s+NextBootTray\s+v)\d+\.\d+\.\d+(\.\.\.")\s*$'
        Replacement = ('$1' + $Version + '$2')
    }
)

foreach ($item in $files) {
    Set-VersionInFile -Path $item.Path -Pattern $item.Pattern -Replacement $item.Replacement
}

Write-Host "Synchronized repository version to $Version"
