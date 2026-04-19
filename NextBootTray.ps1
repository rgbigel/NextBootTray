<#
    NextBootTray.ps1 v1.0.1

    PURPOSE:
      - Provide a tray icon for quick boot-target actions.
      - Show BurntToast notifications with buttons for:
          * Set default boot target
          * Boot once and reboot immediately
      - Keep protocol actions inactive until explicit user click.

    RUNTIME NOTES:
      - Use -D for diagnostics in console output.
      - Use -Stop to terminate all running NextBootTray instances
        for the current user (emergency stop path).
#>

param(
    [switch]$D,
    [switch]$Stop,
    [switch]$Force
)

# ---------------------------------------------------------------
# Logging helpers
# ---------------------------------------------------------------
function Write-DebugMessage {
    # Diagnostic output is opt-in to keep normal startup silent.
    param([string]$Message)
    if ($D) {
        $timestamp = (Get-Date).ToString("HH:mm:ss.fff")
        $entry = "[DBG $timestamp] $Message"
        Write-Host $entry
        
        # Also log to file for capturing diagnostics when GUI loop is active.
        $logFile = "$PSScriptRoot\NextBootTray-Debug.log"
        Add-Content -Path $logFile -Value $entry -ErrorAction SilentlyContinue
    }
}

function Write-UserMessage {
    # User-facing messages are concise and prefixed for clarity.
    param([string]$Message)
    Write-Host "[NextBootTray] $Message"
}

# ---------------------------------------------------------------
# Process discovery and emergency stop helpers
# ---------------------------------------------------------------
function Get-RunningTrayProcesses {
    <#
        Detects running PowerShell processes that include this script
        in their command line so we can reliably stop orphaned runs.
    #>
    param([int]$ExcludePid = -1)

    $escaped = [regex]::Escape("NextBootTray.ps1")
    $processes = Get-CimInstance Win32_Process -Filter "Name='pwsh.exe' OR Name='powershell.exe'"
    $matches = $processes | Where-Object {
        $_.CommandLine -and $_.CommandLine -match $escaped -and $_.ProcessId -ne $ExcludePid
    }

    return @($matches)
}

function Stop-RunningTrayInstances {
    # Returns number of instances successfully terminated.
    param([int]$ExcludePid = -1)

    $targets = Get-RunningTrayProcesses -ExcludePid $ExcludePid
    $stopped = 0

    foreach ($p in $targets) {
        try {
            Stop-Process -Id $p.ProcessId -Force -ErrorAction Stop
            $stopped++
        }
        catch {
            Write-DebugMessage "Failed to stop PID $($p.ProcessId): $($_.Exception.Message)"
        }
    }

    return $stopped
}

Write-DebugMessage "=== NextBootTray.ps1 starting ==="

# Clear old debug log at startup when -D is specified
if ($D) {
    $logFile = "$PSScriptRoot\NextBootTray-Debug.log"
    if (Test-Path $logFile) {
        Clear-Content -Path $logFile -ErrorAction SilentlyContinue
    }
}

# Emergency control path used by launcher -STOP switch.
if ($Stop) {
    $count = Stop-RunningTrayInstances -ExcludePid $PID
    if ($count -gt 0) {
        Write-UserMessage "Stopped $count running NextBootTray instance(s)."
    }
    else {
        Write-UserMessage "No running NextBootTray instance found."
    }
    exit 0
}

# ---------------------------------------------------------------
# Resolve runtime paths
# ---------------------------------------------------------------
$ScriptPath = $MyInvocation.MyCommand.Path
$BasePath   = Split-Path -Path $ScriptPath -Parent
$IconPath   = Join-Path -Path $BasePath -ChildPath "NextBootTray.ico"

# Helper scripts are invoked indirectly via protocol URL handlers.
$SetDefaultScript = Join-Path -Path $BasePath -ChildPath "NextBoot-SetDefault.ps1"
$BootNowScript    = Join-Path -Path $BasePath -ChildPath "NextBoot-BootNow.ps1"

# Single-instance lock to avoid duplicate tray icons and ghost behavior.
# When -Force is used, use a session-specific mutex name to bypass stuck global locks.
if ($Force) {
    $mutexName = "Global\NextBootTray.Force.$PID"
    Write-DebugMessage "Using session-specific mutex: $mutexName"
}
else {
    $mutexName = "Global\NextBootTray.SingleInstance"
}

$createdNew = $false
$singleInstanceMutex = New-Object System.Threading.Mutex($true, $mutexName, [ref]$createdNew)

if (-not $createdNew -and -not $Force) {
    Write-UserMessage "NextBootTray is already running. Use NextBootTray.cmd -STOP to force shutdown."
    exit 0
}

# ---------------------------------------------------------------
# Load dependencies (BurntToast + WinForms)
# ---------------------------------------------------------------
try {
    Import-Module BurntToast -ErrorAction Stop
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
}
catch {
    Write-UserMessage "Startup failed: required components could not be loaded."
    Write-UserMessage "Details: $($_.Exception.Message)"
    if ($singleInstanceMutex) {
        $singleInstanceMutex.ReleaseMutex() | Out-Null
        $singleInstanceMutex.Dispose()
    }
    exit 1
}

# ---------------------------------------------------------------
# Register custom protocol handlers used by BurntToast buttons
# ---------------------------------------------------------------
function Register-Protocol {
    param(
        [string]$Name,
        [string]$TargetScript
    )

    # Never register a broken protocol target.
    if (-not (Test-Path -LiteralPath $TargetScript)) {
        Write-UserMessage "Protocol setup skipped: missing helper script $TargetScript"
        return
    }

    $keyPath = "HKCU:\Software\Classes\$Name"
    $commandKey = Join-Path $keyPath "shell\open\command"

    if (-not (Test-Path -LiteralPath $keyPath)) {
        New-Item -Path $keyPath -Force | Out-Null
    }

    New-ItemProperty -Path $keyPath -Name "URL Protocol" -Value "" -PropertyType String -Force | Out-Null

    if (-not (Test-Path -LiteralPath $commandKey)) {
        New-Item -Path $commandKey -Force | Out-Null
    }

    # %1 is the full protocol URI from toast button click.
    $cmd = "pwsh.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$TargetScript`" -Uri `"%1`""
    Set-ItemProperty -Path $commandKey -Name "(default)" -Value $cmd -Force

    Write-DebugMessage "Protocol registered: $Name"
}

Register-Protocol -Name "setdefault" -TargetScript $SetDefaultScript
Register-Protocol -Name "bootnow" -TargetScript $BootNowScript

# ---------------------------------------------------------------
# BCD read and parsing helpers
# ---------------------------------------------------------------
function Get-BcdSections {
    <#
        Retrieves full BCD dump and splits it into logical sections.
        Returns empty set for non-admin / inaccessible environments.
    #>
    # Keep stderr in-band so localized errors can be detected.
    $raw = bcdedit /enum all 2>&1
    if (-not $raw) {
        Write-DebugMessage "Get-BcdSections: bcdedit returned empty"
        return @()
    }

    $rawText = ($raw | ForEach-Object { $_.ToString() }) -join [Environment]::NewLine
    if ($rawText -match '(?i)access is denied|zugriff verweigert') {
        Write-UserMessage "BCD could not be read. Start tray as Administrator."
        Write-DebugMessage "Get-BcdSections: access denied from bcdedit"
        return @()
    }

    Write-DebugMessage ("Get-BcdSections: bcdedit returned {0} lines" -f $raw.Count)

    $sections = @()
    $current  = @()

    foreach ($line in $raw) {
        $lineText = $line.ToString()
        if ([string]::IsNullOrWhiteSpace($lineText)) {
            if ($current.Count -gt 0) {
                $sections += ,@($current)
                $current = @()
            }
            continue
        }
        $current += $lineText
    }

    if ($current.Count -gt 0) {
        $sections += ,@($current)
    }

    Write-DebugMessage ("Get-BcdSections: parsed into {0} sections" -f $sections.Count)
    return $sections
}

function Classify-BcdSection {
    <#
        Identifies target boot entries from a BCD section with locale-
        tolerant matching (English/German labels where practical).
    #>
    param([string[]]$Section)

    if (-not $Section -or $Section.Count -eq 0) {
        return $null
    }

    $text = [string]::Join([Environment]::NewLine, $Section)
    
    # Simple GUID extraction (not bound to "identifier" label).
    $guidMatch = [regex]::Match($text, '\{[0-9a-fA-F\-]{36}\}')
    if (-not $guidMatch.Success) {
        Write-DebugMessage (\"Rejected: no GUID in section starting with '{0}'\" -f $Section[0].Substring(0, [Math]::Min(50, $Section[0].Length)))
        return $null
    }

    $identifier = $guidMatch.Value
    $description = $null
    
    # Extract description line more flexibly.
    $descLine = $Section | Where-Object { $_ -match '(?i)^\s*(description|beschreibung)\s+' }
    if ($descLine) {
        $description = ($descLine -replace '(?i)^\s*(description|beschreibung)\s+', '').Trim()
    }

    # Detection rules intentionally broad to survive localization.
    $isWinload = $text -match '(?i)\\windows\\system32\\winload\.efi'
    $isRecovery = $text -match '(?i)(recovery|wiederherstellung)'
    $isUbuntu = $text -match '(?i)\bubuntu\b'
    $isRefind = $text -match '(?i)\brefind\b'

    if ($isWinload -and -not $isRecovery) {
        if (-not $description) { $description = "Windows" }
        return [PSCustomObject]@{
            Type        = "Windows"
            Description = $description
            Identifier  = $identifier
        }
    }

    if ($isUbuntu) {
        if (-not $description) { $description = "Ubuntu" }
        return [PSCustomObject]@{
            Type        = "Linux"
            Description = $description
            Identifier  = $identifier
        }
    }

    if ($isRefind) {
        if (-not $description) { $description = "rEFInd" }
        return [PSCustomObject]@{
            Type        = "rEFInd"
            Description = $description
            Identifier  = $identifier
        }
    }

    # Unclassified entry (log for diagnostics).
    Write-DebugMessage (\"Unclassified entry: {0} {1}\" -f $identifier, $description)
    return $null
}

function Get-BootEntries {
    # Parse and classify BCD sections at click time so data is fresh.
    Write-DebugMessage "Get-BootEntries: starting BCD collection"
    
    $sections = Get-BcdSections
    Write-DebugMessage ("Get-BootEntries: got {0} BCD sections" -f $sections.Count)
    
    $entries = @()
    foreach ($section in $sections) {
        $entry = Classify-BcdSection -Section $section
        if ($entry) {
            $entries += $entry
            Write-DebugMessage ("Classified entry: {0} ({1})" -f $entry.Description, $entry.Type)
        }
    }

    $entries = $entries | Group-Object Identifier | ForEach-Object { $_.Group[0] }
    Write-DebugMessage ("Boot entries found: {0}" -f $entries.Count)
    return @($entries)
}

# ---------------------------------------------------------------
# Toast rendering
# ---------------------------------------------------------------
function Show-BootToast {
    <#
        Renders compact toast text and up to five action buttons.
        Keeping button count small improves compatibility and avoids
        silent action suppression on some Windows configurations.
    #>
    Write-DebugMessage "Show-BootToast: starting"
    
    $entries = Get-BootEntries
    Write-DebugMessage ("Show-BootToast: got {0} entries" -f $entries.Count)
    
    if ($entries.Count -eq 0) {
        Write-DebugMessage "Show-BootToast: no entries, showing error message"
        New-BurntToastNotification -Text "NextBootTray", "No supported boot entries detected."
        return
    }

    # Preview text is capped to keep toast compact.
    $preview = @()
    foreach ($entry in ($entries | Select-Object -First 3)) {
        $preview += ("{0}: {1}" -f $entry.Type, $entry.Description)
    }

    if ($entries.Count -gt 3) {
        $preview += ("+{0} more entries" -f ($entries.Count - 3))
    }

    # BurntToast supports up to five buttons.
    $buttons = @()
    foreach ($entry in $entries) {
        if ($buttons.Count -ge 5) {
            break
        }

        $shortName = $entry.Description
        if ($shortName.Length -gt 24) {
            $shortName = $shortName.Substring(0, 24)
        }

        # Keep arguments protocol-based so action only runs on click.
        $buttons += New-BTButton -Content ("Set: {0}" -f $shortName) -Arguments ("setdefault:{0}" -f $entry.Identifier)

        if ($buttons.Count -ge 5) {
            break
        }

        $buttons += New-BTButton -Content ("Boot: {0}" -f $shortName) -Arguments ("bootnow:{0}" -f $entry.Identifier)
    }

    if ($buttons.Count -eq 0) {
        New-BurntToastNotification -Text "NextBootTray", "Entries found but no actionable GUIDs parsed."
        return
    }

    try {
        New-BurntToastNotification -Text "NextBootTray", ([string]::Join([Environment]::NewLine, $preview)) -Button $buttons
    }
    catch {
        Write-UserMessage "Failed to render action toast."
        Write-UserMessage "Details: $($_.Exception.Message)"
    }
}

# ---------------------------------------------------------------
# Tray icon and context menu wiring
# ---------------------------------------------------------------
$notifyIcon = New-Object System.Windows.Forms.NotifyIcon
try {
    # Missing icon is non-fatal; tray still works with default icon.
    if (Test-Path -LiteralPath $IconPath) {
        $notifyIcon.Icon = New-Object System.Drawing.Icon($IconPath)
    }
}
catch {
    Write-DebugMessage "Icon load failed: $($_.Exception.Message)"
}

$notifyIcon.Visible = $true
$notifyIcon.Text = "NextBootTray"

# Simple context menu for exit only (left-click is the primary action).
$menu = New-Object System.Windows.Forms.ContextMenuStrip
$itemExit = New-Object System.Windows.Forms.ToolStripMenuItem("Exit NextBootTray")
$null = $menu.Items.Add($itemExit)
$notifyIcon.ContextMenuStrip = $menu

$itemExit.Add_Click({ [System.Windows.Forms.Application]::Exit() })

# Left-click shortcut mirrors the menu action.
$notifyIcon.Add_MouseClick({
    param($sender, $eventArgs)
    if ($eventArgs.Button -eq [System.Windows.Forms.MouseButtons]::Left) {
        Show-BootToast
    }
})

# ---------------------------------------------------------------
# Main message loop + cleanup
# ---------------------------------------------------------------

# Diagnostic test mode: show boot toast immediately for testing BCD parsing
if ($D) {
    Write-DebugMessage "Debug mode: triggering Show-BootToast immediately for diagnostics"
    Show-BootToast
    Start-Sleep -Milliseconds 500
}

try {
    [System.Windows.Forms.Application]::Run()
}
finally {
    $notifyIcon.Visible = $false
    $notifyIcon.Dispose()

    if ($singleInstanceMutex) {
        try { $singleInstanceMutex.ReleaseMutex() | Out-Null } catch {}
        $singleInstanceMutex.Dispose()
    }
}
