# NextBootTray Requirements

Version: 3.0.0
Profile: default
Author: Rolf Bercht

## Scope
This document captures requirements inferred from the current implementation.

## Functional Requirements
1. The solution shall provide a Windows tray icon process for boot target actions.
2. Left-click on the tray icon shall open a boot action menu.
3. Right-click on the tray icon shall show an exit-only menu item: Exit NextBootTray.
4. The tray process shall read BCD entries using bcdedit /enum all.
5. The tray process shall classify boot entries into selectable items using section parsing and description/path matching.
6. The tray process shall include Linux, Windows, rEFInd, and selected tool entries when classification rules match.
7. The tray process shall exclude infrastructure-only descriptions Windows Boot Manager and Windows-Start-Manager from the displayed left menu.
8. The tray process shall classify winresume loader entries as type Hibernation.
9. The left menu shall exclude entries of type Hibernation.
10. The left menu shall provide a More... entry that switches to a tools placeholder page.
11. The tools placeholder page shall provide a Back to boot entries action.
12. The tray process shall reuse in-memory boot cache for repeated left-click interactions without forced BCD re-parse.
13. The left menu shall show exactly one active default entry as checked when resolvable.
14. Selecting a non-active entry shall invoke NextBoot-SetDefault.ps1 with that entry identifier.
15. After selecting a non-active entry, the left menu shall rebuild and reopen at cursor position.
16. Selecting the checked active entry shall invoke NextBoot-BootNow.ps1 with that entry identifier.
17. The menu shall provide a Boot now action for the active target when available.
18. The tray process shall resolve current default info from bcdedit /enum {bootmgr} and bcdedit /enum {default}.
19. The tray process shall support diagnostics mode via switch -D.
20. The tray process shall support emergency stop mode via switch -Stop, terminating other running NextBootTray PowerShell instances.
21. Normal startup shall perform self-cleanup by terminating older tray instances.
22. The script shall support detached diagnostic launch via -Detach and -DetachedChild.
23. Helper scripts shall validate identifier input format before executing BCD actions.
24. NextBoot-BootNow.ps1 shall set one-time boot sequence using bcdedit /bootsequence <GUID>.
25. NextBoot-BootNow.ps1 shall perform reboot using shutdown /r /t 0 /hybrid-off.
26. NextBoot-BootNow.ps1 shall read current hibernation enabled state, persist machine-scoped restore metadata, and disable hibernation before reboot.
27. NextBootTray.ps1 shall restore hibernation state on next startup when pending restore metadata exists for the current machine.
28. NextBoot-SetDefault.ps1 shall set persistent default using bcdedit /default <GUID>.
29. NextBootTray.cmd shall support -D and -STOP switches only.
30. Normal NextBootTray.cmd startup shall run scheduled task NextBootTray-LogonElevated for non-interactive elevated launch.
31. NextBootTray.cmd shall keep an elevation fallback path when the scheduled task is unavailable.
32. Install-NextBootTray.ps1 shall copy runtime executable files from repository to D:\OneDrive\cmd.
33. Install-NextBootTray.ps1 shall not copy documentation as an install action.
34. Install-NextBootTray.ps1 shall register elevated logon scheduled task NextBootTray-LogonElevated.
35. Install-NextBootTray.ps1 shall remove legacy HKCU Run startup value NextBootTray when present.
36. Set-NextBootVersion.ps1 shall synchronize version references across VERSION.txt and selected repository files.

## Interface Requirements
1. Runtime platform shall be Windows.
2. The GUI mechanism shall be System.Windows.Forms NotifyIcon and ContextMenuStrip.
3. The process shall run PowerShell in STA mode for tray UI operation.

## Operational Requirements
1. Administrative rights shall be required for reliable BCD read/write operations.
2. If BCD read returns access denied text (English or German), tray logic shall return no entries and emit user/debug messages.
3. Missing icon file shall not prevent tray startup.
4. Missing helper script on action invocation shall not terminate tray process.
5. Runtime shall write structured log entries for tray and action scripts.
6. Runtime shall defensively catch and log startup, BCD read, and child-process invocation failures.

## Data and State Requirements
1. Boot entries shall be represented as objects containing Type, Description, Identifier.
2. Duplicate entries by Identifier shall be deduplicated before menu build.
3. The tray process shall maintain in-memory state for cached entries and resolved active default metadata.
4. The tray process shall persist process snapshot metadata in NextBootTray-ProcessState.json.
5. Boot-now action shall persist pending hibernation restore metadata in NextBootTray-HibernateState.json.

## Security and Safety Requirements
1. Action scripts shall ignore invalid or absent GUID input and exit without applying BCD changes.
2. Emergency stop behavior shall target only PowerShell processes whose command line includes NextBootTray.ps1.
3. Action scripts shall validate bcdedit exit codes and return non-zero on command failure.
