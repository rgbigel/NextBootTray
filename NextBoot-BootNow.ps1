param(
    [string]$Id,
    [string]$Uri
)

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

$ResolvedId = Resolve-Guid -RawId $Id -RawUri $Uri -ExpectedScheme "bootnow"
if (-not $ResolvedId) {
    exit 0
}

bcdedit /bootsequence $ResolvedId
shutdown /r /t 0
