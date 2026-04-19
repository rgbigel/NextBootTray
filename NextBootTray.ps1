<#
    NextBootTray.ps1 v2.0.0

    PURPOSE:
      - Provide a tray icon for quick boot-target actions.
            - Left-click opens a boot-action menu.
            - Right-click shows only "Exit NextBootTray".
            - Allow setting default boot target and immediate reboot actions.

    RUNTIME NOTES:
      - Use -D for diagnostics in console output.
      - Use -Stop to terminate all running NextBootTray instances
        for the current user (emergency stop path).
#>

param(
    [switch]$D,
    [switch]$Stop,
    [switch]$Detach,
    [switch]$DetachedChild
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

# Optional detached launch for direct shell testing. The parent shell exits
# immediately, and a child pwsh instance hosts the tray UI.
if ($Detach -and -not $DetachedChild) {
    $selfPath = $MyInvocation.MyCommand.Path
    $args = @('-NoProfile', '-STA', '-File', $selfPath, '-DetachedChild')
    if ($D) {
        $args += '-D'
    }

    Start-Process -FilePath 'pwsh.exe' -Verb RunAs -ArgumentList $args | Out-Null
    Write-UserMessage 'Detached NextBootTray started. This shell can be closed safely.'
    exit 0
}

# Startup self-clean: stop any existing tray runs so each launch starts from a
# single live instance without requiring manual cleanup first.
$stoppedAtStart = Stop-RunningTrayInstances -ExcludePid $PID
if ($stoppedAtStart -gt 0) {
    Write-DebugMessage "Startup cleanup: stopped $stoppedAtStart existing instance(s)."
}

# ---------------------------------------------------------------
# Resolve runtime paths
# ---------------------------------------------------------------
$ScriptPath = $MyInvocation.MyCommand.Path
$BasePath   = Split-Path -Path $ScriptPath -Parent
$IconPath   = Join-Path -Path $BasePath -ChildPath "NextBootTray.ico"

# Helper scripts are invoked directly from tray menu actions.
$SetDefaultScript = Join-Path -Path $BasePath -ChildPath "NextBoot-SetDefault.ps1"
$BootNowScript    = Join-Path -Path $BasePath -ChildPath "NextBoot-BootNow.ps1"

# ---------------------------------------------------------------
# Load dependencies (WinForms)
# ---------------------------------------------------------------
try {
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
}
catch {
    Write-UserMessage "Startup failed: required components could not be loaded."
    Write-UserMessage "Details: $($_.Exception.Message)"
    exit 1
}

# P/Invoke: required to give keyboard focus to our hidden menu owner so that
# Esc and other keyboard shortcuts work in the left-click context menu.
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class TrayFocus {
    [DllImport("user32.dll", SetLastError = true)]
    public static extern bool SetForegroundWindow(IntPtr hWnd);
}
'@

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
        Write-DebugMessage ("Rejected: no GUID in section starting with '{0}'" -f $Section[0].Substring(0, [Math]::Min(50, $Section[0].Length)))
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
    $isWinload = $text -match '(?i)\\windows\\system32\\winload\.(efi|exe)'
    # Scope exclusion check to the description only — full-text matching would catch
    # 'recoverysequence' properties present in every normal Windows boot entry.
    # 'boot\s+manager' is checked as a phrase to avoid matching "rEFInd Boot Manager".
    $isExcluded = ($description -and $description -match '(?i)\b(recovery|wiederherstellung|resume|setup)\b') -or
                  ($description -and $description -match '(?i)^windows\s+boot\s+manager$|^windows-start-manager$')
    $isUbuntu = $text -match '(?i)\bubuntu\b'
    $isRefind = $text -match '(?i)\brefind\b'
    $hasLoaderPath = $text -match '(?im)^\s*(path|pfad)\s+.+'
    $isWindowsDesc = $description -and $description -match '(?i)\bwindows\b'
    $isLinuxDesc = $description -and $description -match '(?i)\b(ubuntu|linux|debian|fedora|arch|mint)\b'
    $isTooling = $description -and $description -match '(?i)(memory|diagnostic|tools|werkzeug|test)'
    $isRecoveryTool = $description -and $description -match '(?i)\b(aomei|macrium|reflect|pe)\b'

    if (($isWinload -or $isWindowsDesc) -and -not $isExcluded) {
        if (-not $description) { $description = "Windows" }
        return [PSCustomObject]@{
            Type        = "Windows"
            Description = $description
            Identifier  = $identifier
        }
    }

    if (($isUbuntu -or $isLinuxDesc) -and -not $isExcluded) {
        if (-not $description) { $description = "Ubuntu" }
        return [PSCustomObject]@{
            Type        = "Linux"
            Description = $description
            Identifier  = $identifier
        }
    }

    if ($isRefind -and -not $isExcluded) {
        if (-not $description) { $description = "rEFInd" }
        return [PSCustomObject]@{
            Type        = "rEFInd"
            Description = $description
            Identifier  = $identifier
        }
    }

    if ($isRecoveryTool) {
        return [PSCustomObject]@{
            Type        = "Tool"
            Description = $description
            Identifier  = $identifier
        }
    }

    # Fallback: keep loader-like entries that have GUID + description + path.
    if ($hasLoaderPath -and $description -and -not $isExcluded -and -not $isTooling) {
        return [PSCustomObject]@{
            Type        = "Boot"
            Description = $description
            Identifier  = $identifier
        }
    }

    # Unclassified entry (log for diagnostics).
    Write-DebugMessage ("Unclassified entry: {0} {1}" -f $identifier, $description)
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

function Get-BcdDefaultInfo {
    # Reads the active default boot target from bootmgr and resolves aliases.
    $raw = bcdedit /enum '{bootmgr}' 2>&1
    if (-not $raw) {
        return [PSCustomObject]@{ Identifier = $null; Description = $null }
    }

    $rawText = ($raw | ForEach-Object { $_.ToString() }) -join [Environment]::NewLine
    if ($rawText -match '(?i)access is denied|zugriff verweigert') {
        return [PSCustomObject]@{ Identifier = $null; Description = $null }
    }

    $defaultToken = $null
    $tokenMatch = [regex]::Match($rawText, '(?im)^\s*(default|standard|standardeintrag)\s+(\{[^\}]+\})\s*$')
    if ($tokenMatch.Success) {
        $defaultToken = $tokenMatch.Groups[2].Value
    }

    $resolvedId = $null
    if ($defaultToken -and $defaultToken -match '^\{[0-9a-fA-F\-]+\}$') {
        $resolvedId = $defaultToken
    }
    elseif ($defaultToken) {
        # Resolve aliases like {current} to a concrete GUID when possible.
        $resolvedRaw = bcdedit /enum $defaultToken 2>&1
        $resolvedText = ($resolvedRaw | ForEach-Object { $_.ToString() }) -join [Environment]::NewLine
        $idMatch = [regex]::Match($resolvedText, '(?im)^\s*(identifier|bezeichner)\s+(\{[0-9a-fA-F\-]+\})\s*$')
        if ($idMatch.Success) {
            $resolvedId = $idMatch.Groups[2].Value
        }
    }

    $desc = $null
    $defaultIdFromDefault = $null
    $defaultRaw = bcdedit /enum '{default}' 2>&1
    $defaultText = ($defaultRaw | ForEach-Object { $_.ToString() }) -join [Environment]::NewLine
    $defaultIdMatch = [regex]::Match($defaultText, '(?im)^\s*(identifier|bezeichner)\s+(\{[0-9a-fA-F\-]+\})\s*$')
    if ($defaultIdMatch.Success) {
        $defaultIdFromDefault = $defaultIdMatch.Groups[2].Value
    }
    $descMatch = [regex]::Match($defaultText, '(?im)^\s*(description|beschreibung)\s+(.+)$')
    if ($descMatch.Success) {
        $desc = $descMatch.Groups[2].Value.Trim()
    }

    if (-not $resolvedId -and $defaultIdFromDefault) {
        $resolvedId = $defaultIdFromDefault
    }

    return [PSCustomObject]@{ Identifier = $resolvedId; Description = $desc }
}

function Invoke-ActionScript {
    param(
        [string]$ScriptPath,
        [string]$Id
    )

    if (-not (Test-Path -LiteralPath $ScriptPath)) {
        Write-UserMessage "Action skipped: helper script missing: $ScriptPath"
        return
    }

    if (-not $Id) {
        Write-UserMessage "Action skipped: missing boot identifier."
        return
    }

    Start-Process -FilePath "pwsh.exe" -WindowStyle Hidden -ArgumentList @(
        "-NoProfile",
        "-ExecutionPolicy", "Bypass",
        "-File", $ScriptPath,
        "-Id", $Id
    ) | Out-Null
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

# Right-click menu: exit only.
$rightMenu = New-Object System.Windows.Forms.ContextMenuStrip
$rightExit = New-Object System.Windows.Forms.ToolStripMenuItem("Exit NextBootTray")
$rightExit.Add_Click({ [System.Windows.Forms.Application]::Exit() })
$null = $rightMenu.Items.Add($rightExit)
$notifyIcon.ContextMenuStrip = $rightMenu

# Left-click menu: boot actions.
$leftMenu = New-Object System.Windows.Forms.ContextMenuStrip
$leftMenu.ShowCheckMargin = $true
$leftMenu.ShowImageMargin = $false
$script:CachedEntries = @()
$script:CurrentDefaultId = $null
$script:CurrentDefaultDescription = $null
$script:BootCacheReady = $false
$script:IsOpeningLeftMenu = $false

# Hidden owner form gives the menu a proper keyboard owner so Esc works.
$menuOwner = New-Object System.Windows.Forms.Form
$menuOwner.ShowInTaskbar = $false
$menuOwner.Opacity = 0
$menuOwner.FormBorderStyle = 'None'
$menuOwner.Size = New-Object System.Drawing.Size(1, 1)
$menuOwner.TopMost = $true
$leftMenu.Add_Closed({
    if ($menuOwner.Visible) { $menuOwner.Hide() }
})

function Refresh-BootCache {
    param([switch]$Force)

    if (-not $Force -and $script:BootCacheReady) {
        return
    }

    $script:CachedEntries = @(Get-BootEntries)
    $defaultInfo = Get-BcdDefaultInfo

    $script:CurrentDefaultId = $defaultInfo.Identifier
    $script:CurrentDefaultDescription = $defaultInfo.Description
    Write-DebugMessage ("Default info: Id='{0}' Desc='{1}'" -f $script:CurrentDefaultId, $script:CurrentDefaultDescription)

    # If we cannot resolve by GUID, try a description match against current entries.
    if (-not $script:CurrentDefaultId -and $script:CurrentDefaultDescription) {
        $descMatchEntry = $script:CachedEntries | Where-Object { $_.Description -eq $script:CurrentDefaultDescription } | Select-Object -First 1
        if ($descMatchEntry) {
            $script:CurrentDefaultId = $descMatchEntry.Identifier
        }
    }

    $script:BootCacheReady = $true
}

function Build-LeftMenu {
    $leftMenu.Items.Clear()
    # Refresh on open so checkmark/Boot-now always reflect latest BCD state.
    Refresh-BootCache -Force
    $entries = @($script:CachedEntries)

    # Filter entries that serve infrastructure roles and are not user boot targets.
    $skipDescriptions = @('Windows Boot Manager', 'Windows-Start-Manager')
    $entries = @($entries | Where-Object { $skipDescriptions -notcontains $_.Description })

    if ($entries.Count -eq 0) {
        $noneItem = New-Object System.Windows.Forms.ToolStripMenuItem('No supported boot entries detected')
        $noneItem.Enabled = $false
        $null = $leftMenu.Items.Add($noneItem)
        return
    }

    # Sort: DxPy entries first (numerically by disk then partition),
    # then rEFInd, then everything else alphabetically.
    $sortedEntries = $entries | Sort-Object -Property @{
        Expression = {
            if ($_.Description -match '^D(\d+)P(\d+)') {
                '0-{0:D5}-{1:D5}' -f [int]$Matches[1], [int]$Matches[2]
            } elseif ($_.Type -eq 'rEFInd') {
                '1-{0}' -f $_.Description
            } else {
                '2-{0}' -f $_.Description
            }
        }
    }

    function Get-DiskPartToken {
        param([string]$Text)
        if (-not $Text) { return $null }
        $m = [regex]::Match($Text, '(?i)\bD\s*(\d+)\s*P\s*(\d+)\b')
        if (-not $m.Success) { return $null }
        return ('D{0}P{1}' -f [int]$m.Groups[1].Value, [int]$m.Groups[2].Value)
    }

    $activeEntry = $sortedEntries | Where-Object { $_.Identifier -eq $script:CurrentDefaultId } | Select-Object -First 1
    if (-not $activeEntry -and $script:CurrentDefaultDescription) {
        $activeEntry = $sortedEntries | Where-Object { $_.Description -eq $script:CurrentDefaultDescription } | Select-Object -First 1
    }
    if (-not $activeEntry -and $script:CurrentDefaultDescription) {
        $activeEntry = $sortedEntries | Where-Object { $_.Description -like ("*{0}*" -f $script:CurrentDefaultDescription) -or $script:CurrentDefaultDescription -like ("*{0}*" -f $_.Description) } | Select-Object -First 1
    }
    if (-not $activeEntry -and $script:CurrentDefaultDescription) {
        $defaultDpToken = Get-DiskPartToken -Text $script:CurrentDefaultDescription
        if ($defaultDpToken) {
            $activeEntry = $sortedEntries | Where-Object {
                (Get-DiskPartToken -Text $_.Description) -eq $defaultDpToken
            } | Select-Object -First 1
            Write-DebugMessage ("Active fallback by normalized token '{0}': {1}" -f $defaultDpToken, $(if ($activeEntry) { 'matched' } else { 'not found' }))
        }
    }

    if ($activeEntry) {
        $script:CurrentDefaultId = $activeEntry.Identifier
        $script:CurrentDefaultDescription = $activeEntry.Description
    }
    Write-DebugMessage ("Active entry resolved: {0}" -f $(if ($activeEntry) { "$($activeEntry.Description) [$($activeEntry.Identifier)]" } else { "<none>" }))

    foreach ($entry in $sortedEntries) {
        $isActiveDefault = ($activeEntry -and $entry.Identifier -eq $activeEntry.Identifier)
        $menuItem = New-Object System.Windows.Forms.ToolStripMenuItem($entry.Description)
        $menuItem.CheckOnClick = $false
        $menuItem.CheckState = if ($isActiveDefault) { [System.Windows.Forms.CheckState]::Checked } else { [System.Windows.Forms.CheckState]::Unchecked }
        $menuItem.Checked = $isActiveDefault

        $targetId = $entry.Identifier
        if ($isActiveDefault) {
            # Clicking the active default triggers an immediate reboot.
            $bootScript = $BootNowScript
            $menuItem.Add_Click({
                Invoke-ActionScript -ScriptPath $bootScript -Id $targetId
            }.GetNewClosure())
        }
        else {
            $setScript = $SetDefaultScript
            $targetDescription = $entry.Description
            $menuItem.Add_Click({
                Invoke-ActionScript -ScriptPath $setScript -Id $targetId
                $script:CurrentDefaultId = $targetId
                $script:CurrentDefaultDescription = $targetDescription
                Build-LeftMenu
                $menuOwner.Show()
                [void][TrayFocus]::SetForegroundWindow($menuOwner.Handle)
                $leftMenu.Show($menuOwner, $menuOwner.PointToClient([System.Windows.Forms.Cursor]::Position))
            }.GetNewClosure())
        }

        $null = $leftMenu.Items.Add($menuItem)
    }

    $null = $leftMenu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))

    if ($activeEntry) {
        $bootItem = New-Object System.Windows.Forms.ToolStripMenuItem(('Boot now: {0}' -f $activeEntry.Description))
        $bootId = $activeEntry.Identifier
        $bootScript = $BootNowScript
        $bootItem.Add_Click({
            Invoke-ActionScript -ScriptPath $bootScript -Id $bootId
        }.GetNewClosure())
        $null = $leftMenu.Items.Add($bootItem)
    }
    elseif ($script:CurrentDefaultId) {
        $bootDesc = if ($script:CurrentDefaultDescription) { $script:CurrentDefaultDescription } else { $script:CurrentDefaultId }
        $bootItem = New-Object System.Windows.Forms.ToolStripMenuItem(('Boot now: {0}' -f $bootDesc))
        $bootId = $script:CurrentDefaultId
        $bootScript = $BootNowScript
        $bootItem.Add_Click({
            Invoke-ActionScript -ScriptPath $bootScript -Id $bootId
        }.GetNewClosure())
        $null = $leftMenu.Items.Add($bootItem)
    }
    else {
        $bootItem = New-Object System.Windows.Forms.ToolStripMenuItem('Boot now: (active default unavailable)')
        $bootItem.Enabled = $false
        $null = $leftMenu.Items.Add($bootItem)
    }

}

Refresh-BootCache -Force

# Left-click shortcut mirrors the menu action.
$notifyIcon.Add_MouseClick({
    param($sender, $eventArgs)
    if ($eventArgs.Button -eq [System.Windows.Forms.MouseButtons]::Left) {
        if ($script:IsOpeningLeftMenu) {
            return
        }

        $script:IsOpeningLeftMenu = $true
        try {
            Build-LeftMenu
            $menuOwner.Show()
            [void][TrayFocus]::SetForegroundWindow($menuOwner.Handle)
            $leftMenu.Show($menuOwner, $menuOwner.PointToClient([System.Windows.Forms.Cursor]::Position))
        }
        finally {
            $script:IsOpeningLeftMenu = $false
        }
    }
})

# ---------------------------------------------------------------
# Main message loop + cleanup
# ---------------------------------------------------------------

try {
    [System.Windows.Forms.Application]::Run()
}
finally {
    $notifyIcon.Visible = $false
    $notifyIcon.Dispose()
}
