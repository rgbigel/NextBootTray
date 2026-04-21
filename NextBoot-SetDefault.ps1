# =================================================================================================
#  Module:      NextBoot-SetDefault.ps1
#  Path:        .
#  Author:      Rolf Bercht
#  Version:     3.0.0
#  Changelog:
#      3.0.0  - Added structured action logging and exit-code validation.
#      2.0.0  - Default-target action baseline.
# =================================================================================================

param(
    [string]$Id,
    [string]$Uri
)

$script:LogFile = Join-Path -Path $PSScriptRoot -ChildPath 'NextBootTray-Action.log'

function Write-LogEntry {
    param(
        [ValidateSet('INFO', 'WARN', 'ERROR')]
        [string]$Level,
        [string]$Message
    )

    $timestamp = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss.fff')
    $entry = "[{0}] [SetDefault] [{1}] {2}" -f $timestamp, $Level, $Message
    try {
        Add-Content -Path $script:LogFile -Value $entry -ErrorAction Stop
    }
    catch {
        # Non-fatal logging failure.
    }
}

function Resolve-Guid {
    param(
        [string]$RawId,
        [string]$RawUri,
        [string]$ExpectedScheme
    )

    if ($RawId -and $RawId -match '^\{[0-9a-fA-F\-]+\}$') {
        return $RawId
    }

    if (-not $RawUri) {
        return $null
    }

    $pattern = "^(?i)${ExpectedScheme}:(\{[0-9a-fA-F\-]+\})$"
    if ($RawUri -match $pattern) {
        return $Matches[1]
    }

    return $null
}

$ResolvedId = Resolve-Guid -RawId $Id -RawUri $Uri -ExpectedScheme "setdefault"
if (-not $ResolvedId) {
    Write-LogEntry -Level WARN -Message 'No valid boot identifier was provided; action skipped.'
    exit 0
}

bcdedit /default $ResolvedId | Out-Null
if ($LASTEXITCODE -ne 0) {
    Write-LogEntry -Level ERROR -Message ("bcdedit /default failed for {0} with exit code {1}" -f $ResolvedId, $LASTEXITCODE)
    exit 1
}

Write-LogEntry -Level INFO -Message ("Applied default boot target: {0}" -f $ResolvedId)
