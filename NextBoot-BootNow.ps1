# =================================================================================================
#  Module:      NextBoot-BootNow.ps1
#  Path:        .
#  Author:      Rolf Bercht
#  Version:     3.0.0
#  Changelog:
#      3.0.0  - Added hibernation-state save/disable pipeline and cold reboot via /hybrid-off.
#      2.0.0  - One-shot boot sequence action.
# =================================================================================================

param(
    [string]$Id,
    [string]$Uri
)

$script:LogFile = Join-Path -Path $PSScriptRoot -ChildPath 'NextBootTray-Action.log'
$script:HibernateStatePath = Join-Path -Path $PSScriptRoot -ChildPath 'NextBootTray-HibernateState.json'

function Write-LogEntry {
    param(
        [ValidateSet('INFO', 'WARN', 'ERROR')]
        [string]$Level,
        [string]$Message
    )

    $timestamp = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss.fff')
    $entry = "[{0}] [BootNow] [{1}] {2}" -f $timestamp, $Level, $Message
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

function Get-HibernateEnabledState {
    try {
        $key = Get-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Power' -Name HibernateEnabled -ErrorAction Stop
        return ([int]$key.HibernateEnabled -ne 0)
    }
    catch {
        Write-LogEntry -Level ERROR -Message ("Could not read HibernateEnabled from registry: {0}" -f $_.Exception.Message)
        return $false
    }
}

function Save-HibernateStateForRestore {
    param([bool]$WasEnabled)

    $state = [ordered]@{
        ComputerName       = $env:COMPUTERNAME
        HibernateWasEnabled = $WasEnabled
        PendingRestore     = $true
        SavedAtUtc         = [DateTime]::UtcNow.ToString('o')
    }

    try {
        $json = $state | ConvertTo-Json -Depth 3
        Set-Content -Path $script:HibernateStatePath -Value $json -Encoding ascii -ErrorAction Stop
        Write-LogEntry -Level INFO -Message ("Saved hibernation state to {0}" -f $script:HibernateStatePath)
    }
    catch {
        Write-LogEntry -Level ERROR -Message ("Could not save hibernation state: {0}" -f $_.Exception.Message)
    }
}

$ResolvedId = Resolve-Guid -RawId $Id -RawUri $Uri -ExpectedScheme "bootnow"
if (-not $ResolvedId) {
    Write-LogEntry -Level WARN -Message 'No valid boot identifier was provided; action skipped.'
    exit 0
}

$hibernateWasEnabled = Get-HibernateEnabledState
Save-HibernateStateForRestore -WasEnabled:$hibernateWasEnabled

if ($hibernateWasEnabled) {
    try {
        powercfg /h off | Out-Null
        Write-LogEntry -Level INFO -Message 'Disabled hibernation before reboot.'
    }
    catch {
        Write-LogEntry -Level ERROR -Message ("powercfg /h off failed: {0}" -f $_.Exception.Message)
    }
}

bcdedit /bootsequence $ResolvedId | Out-Null
if ($LASTEXITCODE -ne 0) {
    Write-LogEntry -Level ERROR -Message ("bcdedit /bootsequence failed for {0} with exit code {1}" -f $ResolvedId, $LASTEXITCODE)
    exit 1
}

Write-LogEntry -Level INFO -Message ("Applied one-time bootsequence target: {0}" -f $ResolvedId)
shutdown /r /t 0 /hybrid-off
