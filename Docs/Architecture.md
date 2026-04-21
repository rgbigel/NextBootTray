# NextBootTray Architecture

Version: 3.0.0
Profile: default
Author: Rolf Bercht

## 1. Solution Structure

### 1.1 Runtime Entry and Wrappers
- NextBootTray.cmd: launcher wrapper for argument parsing, elevation, hidden/diagnostic mode, stop mode.
- NextBootTray.ps1: primary tray process and UI event loop.

### 1.2 Action Modules
- NextBoot-SetDefault.ps1: sets persistent BCD default target.
- NextBoot-BootNow.ps1: sets one-time boot sequence and initiates reboot.

### 1.3 Deployment and Maintenance Modules
- Install-NextBootTray.ps1: installs runtime files to D:\OneDrive\cmd and registers elevated logon scheduled task NextBootTray-LogonElevated.
- Set-NextBootVersion.ps1: updates version string across repository-controlled files.
- VERSION.txt: repository version source.

### 1.4 Documentation and Assets
- README.md: user-level behavior and run mode summary.
- Docs/NextBootTray.md: design flow and mermaid diagram.
- NextBootTray.ico: optional tray icon asset.

## 2. Component Responsibilities

### 2.1 NextBootTray.cmd
- Parses only -D and -STOP.
- Normal startup runs scheduled task NextBootTray-LogonElevated (non-interactive elevation).
- Uses Start-Process with -Verb RunAs as fallback when scheduled task startup is unavailable.
- Uses hidden window for normal mode and visible console for diagnostics mode.

### 2.2 NextBootTray.ps1
- Loads WinForms and Drawing assemblies.
- Creates NotifyIcon, right-click menu, left-click menu, and hidden owner form.
- Handles click events and rebuilds left menu dynamically.
- Provides a second menu page placeholder reachable via More... with back navigation.
- Reads and parses BCD data through helper functions.
- Reuses in-memory boot cache during repeated interactions.
- Resolves active default target and maps it to classified entries.
- Restores pending hibernation state at startup when machine-scoped restore metadata exists.
- Writes structured log file entries and process snapshot metadata.
- Executes action scripts through Start-Process pwsh child invocation.
- Hosts the message loop using Application.Run and disposes icon on exit.

### 2.3 BCD Parsing Subsystem (inside NextBootTray.ps1)
- Get-BcdSections:
  - Calls bcdedit /enum all.
  - Splits output into sections by blank lines.
  - Handles localized access-denied detection.
- Classify-BcdSection:
  - Extracts GUID and description.
  - Applies pattern-based classification into Windows, Linux, rEFInd, Tool, Hibernation, Boot.
  - Excludes selected non-user targets by description.
- Get-BootEntries:
  - Iterates sections, classifies entries, logs diagnostics, deduplicates by identifier.
- Get-BcdDefaultInfo:
  - Reads boot manager default token and resolves concrete GUID where possible.
  - Reads description from {default} entry.

### 2.4 Action Scripts
- Shared technique:
  - Resolve-Guid accepts direct GUID or URI-form token with expected scheme.
  - If resolution fails, script exits with no side effect.
- NextBoot-SetDefault.ps1:
  - Executes bcdedit /default <GUID>.
  - Logs action outcome and validates command exit code.
- NextBoot-BootNow.ps1:
  - Saves current machine hibernation state metadata.
  - Disables hibernation before reboot (powercfg /h off).
  - Executes bcdedit /bootsequence <GUID>.
  - Reboots via shutdown /r /t 0 /hybrid-off.
  - Logs action outcome and validates command exit code.

### 2.5 Installation and Startup Registration
- Install-NextBootTray.ps1 copies executable scripts and icon to D:\OneDrive\cmd.
- Installer registers per-user elevated scheduled task NextBootTray-LogonElevated.
- Installer removes legacy HKCU Run startup value NextBootTray when present.

## 3. Runtime Control Flow
1. Launcher starts elevated tray process.
2. Tray script optionally stops running instances when -Stop is passed.
3. On normal startup, tray script writes process snapshot, restores pending hibernation state if needed, and performs self-clean of older tray instances.
4. Tray icon is shown and right-click exit menu is attached.
5. Left-click triggers Build-LeftMenu from cached BCD-derived state.
6. User selection triggers set-default action, boot-now action, or More... tools placeholder page.
7. Boot-now action stores hibernation state, disables hibernation, applies bootsequence, and performs hybrid-off reboot.
8. Message loop runs until exit; resources are disposed in finally block.

## 4. State Model
- In-memory script scope state:
  - CachedEntries
  - CurrentDefaultId
  - CurrentDefaultDescription
  - BootCacheReady
  - IsOpeningLeftMenu
  - CurrentMenuPage
- Persistent runtime state:
  - NextBootTray_<timestamp>.log (structured tray log)
  - NextBootTray-Action.log (helper action script log)
  - NextBootTray-ProcessState.json (process snapshot)
  - NextBootTray-HibernateState.json (pending restore metadata)

## 5. Techniques Used
1. Event-driven desktop UI using System.Windows.Forms NotifyIcon and ContextMenuStrip.
2. External command integration via bcdedit, shutdown, and pwsh child process execution.
3. Text parsing and regex-based classification over localized command output.
4. Defensive execution with early returns when dependencies, identifiers, or permissions are missing.
5. Process hygiene using Win32 process query and forced stop for single-instance startup behavior.

## 6. Trust Boundaries and Assumptions Implemented
1. BCD command output is treated as authoritative source for boot entry discovery.
2. Classification is heuristic and depends on output text patterns.
3. Elevated execution is assumed available for full feature operation.
