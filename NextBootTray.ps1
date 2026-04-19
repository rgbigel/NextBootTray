<#
    NextBootTray.ps1 v1.0.1
    Initializes tray icon, parses BCD, shows BurntToast buttons per GUID.
    No reboot until user clicks "Boot now".

    Purpose:
    - Create a Windows tray icon for quick boot-target inspection and control.
    - Read BCD via "bcdedit /enum all" and classify:
        * Windows boot loaders (winload.efi, non-Recovery, non-WinPE)
        * Ubuntu entries
        * rEFInd entries
    - On tray left-click, show a BurntToast notification with:
        * List of detected entries
        * Buttons that:
            - Set default boot entry
            - Boot a specific entry once and reboot immediately

    Design goals:
    - Deterministic, ASCII-only, no hidden Unicode.
    - Explicit diagnostics controlled by -D switch.
    - No silent failures: every early exit is explained in diagnostics.
    - No global PATH pollution; script is self-contained.
#>

param(
    [switch]$D
)

# ---------------------------------------------------------------
# Diagnostic helper
# ---------------------------------------------------------------
function Write-DebugMessage {
    param(
        [string]$Message
    )

    if ($D) {
        $timestamp = (Get-Date).ToString("HH:mm:ss.fff")
        Write-Host "[DBG $timestamp] $Message"
    }
}

Write-DebugMessage "=== NextBootTray.ps1 v1.0.1 starting ==="
Write-DebugMessage "PSVersion: $($PSVersionTable.PSVersion.ToString())"

# ---------------------------------------------------------------
# Resolve paths
# ---------------------------------------------------------------
$ScriptPath = $MyInvocation.MyCommand.Path
$BasePath   = Split-Path -Path $ScriptPath -Parent
$IconPath   = Join-Path -Path $BasePath -ChildPath "NextBootTray.ico"

$SetDefaultScript = Join-Path -Path $BasePath -ChildPath "NextBoot-SetDefault.ps1"
$BootNowScript    = Join-Path -Path $BasePath -ChildPath "NextBoot-BootNow.ps1"

Write-DebugMessage "Script path: $ScriptPath"
Write-DebugMessage "Base path:   $BasePath"
Write-DebugMessage "Icon path:   $IconPath"
Write-DebugMessage "SetDefault script: $SetDefaultScript"
Write-DebugMessage "BootNow script:    $BootNowScript"

# ---------------------------------------------------------------
# Ensure base directory exists
# ---------------------------------------------------------------
if (-not (Test-Path -LiteralPath $BasePath)) {
    Write-DebugMessage "Base path does not exist, creating: $BasePath"
    New-Item -ItemType Directory -Path $BasePath -Force | Out-Null
}
else {
    Write-DebugMessage "Base path exists."
}

# ---------------------------------------------------------------
# Import BurntToast
# ---------------------------------------------------------------
try {
    Write-DebugMessage "Importing BurntToast..."
    Import-Module BurntToast -ErrorAction Stop
    Write-DebugMessage "BurntToast imported."
}
catch {
    Write-DebugMessage "Failed to import BurntToast: $($_.Exception.Message)"
    throw
}

# ---------------------------------------------------------------
# Load WinForms and Drawing
# ---------------------------------------------------------------
try {
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    Write-DebugMessage "WinForms and Drawing loaded."
}
catch {
    Write-DebugMessage "Failed to load WinForms/Drawing: $($_.Exception.Message)"
    throw
}

# ---------------------------------------------------------------
# Build helper scripts
# ---------------------------------------------------------------
function Write-HelperScripts {
    <#
        Writes two helper scripts:

        NextBoot-SetDefault.ps1
        - Sets the default boot entry to the given identifier.
        - Does NOT reboot by itself; reboot is handled by BootNow
          or by the user.

        NextBoot-BootNow.ps1
        - Sets a one-time boot sequence to the given identifier.
        - Immediately triggers a reboot.

        Both scripts are designed to be called via custom URL
        protocols: setdefault: and bootnow:
    #>

    Write-DebugMessage "Building helper scripts..."

    $setDefaultContent = @'
param(
    [Parameter(Mandatory = $true)]
    [string]$Id
)

# NextBoot-SetDefault.ps1
# Sets the default boot entry to the given identifier.

Write-Host "NextBoot-SetDefault.ps1: setting default to $Id"
bcdedit /default $Id
'@

    $bootNowContent = @'
param(
    [Parameter(Mandatory = $true)]
    [string]$Id
)

# NextBoot-BootNow.ps1
# Sets a one-time boot sequence and reboots immediately.

Write-Host "NextBoot-BootNow.ps1: booting once to $Id"
bcdedit /bootsequence $Id
shutdown /r /t 0
'@

    Set-Content -LiteralPath $SetDefaultScript -Value $setDefaultContent -Encoding ASCII
    Set-Content -LiteralPath $BootNowScript    -Value $bootNowContent    -Encoding ASCII

    Write-DebugMessage "Helper scripts written."
}

Write-HelperScripts

# ---------------------------------------------------------------
# Register custom URL protocols
# ---------------------------------------------------------------
function Register-Protocol {
    param(
        [string]$Name,
        [string]$ScriptPath
    )

    <#
        Registers a custom URL protocol under HKCU\Software\Classes:

        Name: setdefault or bootnow

        Example:
        setdefault:{GUID}
        bootnow:{GUID}

        The command will call pwsh.exe with the helper script and
        pass the full URL as %1, which the script interprets as Id.
    #>

    $keyPath = "HKCU:\Software\Classes\$Name"
    $commandKey = Join-Path $keyPath "shell\open\command"

    Write-DebugMessage "Registering protocol: $Name"

    if (-not (Test-Path -LiteralPath $keyPath)) {
        New-Item -Path $keyPath -Force | Out-Null
    }

    New-ItemProperty -Path $keyPath -Name "URL Protocol" -Value "" -PropertyType String -Force | Out-Null

    if (-not (Test-Path -LiteralPath $commandKey)) {
        New-Item -Path $commandKey -Force | Out-Null
    }

    # Command line: pwsh.exe -NoProfile -WindowStyle Hidden -File "ScriptPath" "%1"
    $cmd = "pwsh.exe -NoProfile -WindowStyle Hidden -File `"$ScriptPath`" `"%1`""

    New-ItemProperty -Path $commandKey -Name "(default)" -Value $cmd -PropertyType String -Force | Out-Null

    Write-DebugMessage "Protocol $Name registered."
}

Register-Protocol -Name "setdefault" -ScriptPath $SetDefaultScript
Register-Protocol -Name "bootnow"    -ScriptPath $BootNowScript

# ---------------------------------------------------------------
# Create tray icon
# ---------------------------------------------------------------
$notifyIcon = New-Object System.Windows.Forms.NotifyIcon

try {
    if (Test-Path -LiteralPath $IconPath) {
        $iconObject = New-Object System.Drawing.Icon($IconPath)
        $notifyIcon.Icon = $iconObject
        Write-DebugMessage "Custom icon loaded from $IconPath."
    }
    else {
        Write-DebugMessage "Icon file not found at $IconPath. Using default icon."
    }
}
catch {
    Write-DebugMessage "Failed to load icon: $($_.Exception.Message)"
}

$notifyIcon.Visible = $true
$notifyIcon.Text    = "NextBootTray"

# ---------------------------------------------------------------
# BCD parsing
# ---------------------------------------------------------------
function Get-BcdSections {
    <#
        Runs "bcdedit /enum all" and splits the output into sections
        separated by blank lines. Each section is an array of lines.
    #>

    Write-DebugMessage "Calling bcdedit /enum all..."
    $raw = bcdedit /enum all 2>&1
    if (-not $raw) {
        Write-DebugMessage "bcdedit returned no output."
        return @()
    }

    Write-DebugMessage ("bcdedit returned {0} lines." -f $raw.Count)

    $sections = @()
    $current  = @()

    foreach ($line in $raw) {
        if ([string]::IsNullOrWhiteSpace($line)) {
            if ($current.Count -gt 0) {
                $sections += ,@($current)
                $current = @()
            }
        }
        else {
            $current += $line
        }
    }

    if ($current.Count -gt 0) {
        $sections += ,@($current)
    }

    Write-DebugMessage ("Parsed {0} sections from BCD output." -f $sections.Count)
    return $sections
}

function Classify-BcdSection {
    <#
        Classifies a single BCD section into:
        - Windows  : real Windows boot loader (winload.efi, not Recovery/WinPE)
        - Linux    : Ubuntu
        - rEFInd   : rEFInd Boot Manager
        - $null    : not relevant for tray display
    #>

    param(
        [string[]]$Section
    )

    if (-not $Section -or $Section.Count -eq 0) {
        return $null
    }

    $newline = [Environment]::NewLine
    $text    = [string]::Join($newline, $Section)

    # Extract description
    $description = $null
    $descLine = $Section | Where-Object { $_ -match '^\s*description\s+' }
    if ($descLine) {
        $description = ($descLine -replace '^\s*description\s+', '').Trim()
    }

    # Extract identifier
    $identifier = $null
    $idLine = $Section | Where-Object { $_ -match '^\s*identifier\s+' }
    if ($idLine) {
        $identifier = ($idLine -replace '^\s*identifier\s+', '').Trim()
    }

    # Case-insensitive detection of winload.efi
    $isWinload = $text -match '(?im)^\s*path\s+\\windows\\system32\\winload\.efi\s*$'

    # Exclude WinRE / WinPE
    $isRecovery = $false
    $isWinPE    = $false

    if ($description -and ($description -match '(?i)recovery')) {
        $isRecovery = $true
    }

    if ($text -match '(?im)^\s*winpe\s+Yes\s*$') {
        $isWinPE = $true
    }

    if ($isWinload -and -not $isRecovery -and -not $isWinPE) {
        return [PSCustomObject]@{
            Type        = "Windows"
            Description = $description
            Identifier  = $identifier
            Raw         = $Section
        }
    }

    # Ubuntu
    if ($description -and ($description -match '(?i)ubuntu')) {
        return [PSCustomObject]@{
            Type        = "Linux"
            Description = $description
            Identifier  = $identifier
            Raw         = $Section
        }
    }

    # rEFInd
    if ($description -and ($description -match '(?i)refind')) {
        return [PSCustomObject]@{
            Type        = "rEFInd"
            Description = $description
            Identifier  = $identifier
            Raw         = $Section
        }
    }

    return $null
}

Write-DebugMessage "Reading and classifying BCD entries..."
$sections  = Get-BcdSections
$osEntries = @()

foreach ($section in $sections) {
    $classified = Classify-BcdSection -Section $section
    if ($classified) {
        Write-DebugMessage ("Detected OS entry: [{0}] {1}" -f $classified.Type, $classified.Description)
        $osEntries += $classified
    }
}

Write-DebugMessage ("Final OS entry count: {0}" -f $osEntries.Count)

# ---------------------------------------------------------------
# Toast builder
# ---------------------------------------------------------------
function Show-BootToast {
    <#
        Builds and shows a BurntToast notification listing all
        detected OS entries and providing buttons for:
        - Set default (setdefault:{Id})
        - Boot now (bootnow:{Id})
    #>

    if ($osEntries.Count -eq 0) {
        Write-DebugMessage "Show-BootToast: no OS entries, showing simple toast."
        New-BurntToastNotification -Text "NextBootTray", "No boot entries detected."
        return
    }

    $lines = @()
    foreach ($entry in $osEntries) {
        $lines += ("{0}: {1}" -f $entry.Type, $entry.Description)
    }

    $bodyText = [string]::Join([Environment]::NewLine, $lines)

    $buttons = @()

    foreach ($entry in $osEntries) {
        if (-not $entry.Identifier) {
            continue
        }

        $id   = $entry.Identifier
        $desc = $entry.Description

        # Set default button
        $btnSet = New-BTButton -Content ("Set default: {0}" -f $desc) -Arguments ("setdefault:{0}" -f $id)
        $buttons += $btnSet

        # Boot now button
        $btnBoot = New-BTButton -Content ("Boot now: {0}" -f $desc) -Arguments ("bootnow:{0}" -f $id)
        $buttons += $btnBoot
    }

    Write-DebugMessage "Show-BootToast: showing toast with buttons."
    New-BurntToastNotification -Text "NextBootTray", $bodyText -Button $buttons
}

# ---------------------------------------------------------------
# Tray click handler
# ---------------------------------------------------------------
$notifyIcon.Add_Click({
    param($sender, $eventArgs)

    if ($eventArgs.Button -eq [System.Windows.Forms.MouseButtons]::Left) {
        Write-DebugMessage "Tray left-click detected."
        Show-BootToast
    }
})

Write-DebugMessage "Entering WinForms message loop..."
[System.Windows.Forms.Application]::Run()

Write-DebugMessage "Message loop exited. Cleaning up tray icon."
$notifyIcon.Visible = $false
$notifyIcon.Dispose()
