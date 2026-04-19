param([string]$Id)
if (-not $Id -or $Id -notmatch "^\{[0-9a-fA-F\-]+\}$") { exit 0 }
bcdedit /default $Id
