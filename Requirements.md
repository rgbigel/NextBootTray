# NextBootTray Requirements

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
8. The left menu shall show exactly one active default entry as checked when resolvable.
9. Selecting a non-active entry shall invoke NextBoot-SetDefault.ps1 with that entry identifier.
10. After selecting a non-active entry, the left menu shall rebuild and reopen at cursor position.
11. Selecting the checked active entry shall invoke NextBoot-BootNow.ps1 with that entry identifier.
12. The menu shall provide a Boot now action for the active target when available.
13. The tray process shall resolve current default info from bcdedit /enum {bootmgr} and bcdedit /enum {default}.
14. The tray process shall support diagnostics mode via switch -D.
15. In diagnostics mode, debug lines shall be written to console and NextBootTray-Debug.log in script root.
16. The tray process shall support emergency stop mode via switch -Stop, terminating other running NextBootTray PowerShell instances.
17. Normal startup shall perform self-cleanup by terminating older tray instances.
18. The script shall support detached diagnostic launch via -Detach and -DetachedChild.
19. Helper scripts shall validate identifier input format before executing BCD actions.
20. NextBoot-BootNow.ps1 shall set one-time boot sequence using bcdedit /bootsequence <GUID> and then call shutdown /r /t 0.
21. NextBoot-SetDefault.ps1 shall set persistent default using bcdedit /default <GUID>.
22. NextBootTray.cmd shall support -D and -STOP switches only.
23. NextBootTray.cmd shall launch the tray elevated using Start-Process -Verb RunAs.
24. Install-NextBootTray.ps1 shall copy runtime files from repository to D:\OneDrive\cmd.
25. Install-NextBootTray.ps1 shall register HKCU Run startup entry named NextBootTray pointing to D:\OneDrive\cmd\NextBootTray.cmd.
26. Set-NextBootVersion.ps1 shall synchronize version references across VERSION.txt and selected repository files.

## Interface Requirements
1. Runtime platform shall be Windows.
2. The GUI mechanism shall be System.Windows.Forms NotifyIcon and ContextMenuStrip.
3. The process shall run PowerShell in STA mode for tray UI operation.

## Operational Requirements
1. Administrative rights shall be required for reliable BCD read/write operations.
2. If BCD read returns access denied text (English or German), tray logic shall return no entries and emit user/debug messages.
3. Missing icon file shall not prevent tray startup.
4. Missing helper script on action invocation shall not terminate tray process.

## Data and State Requirements
1. Boot entries shall be represented as objects containing Type, Description, Identifier.
2. Duplicate entries by Identifier shall be deduplicated before menu build.
3. The tray process shall maintain in-memory state for cached entries and resolved active default metadata.

## Security and Safety Requirements
1. Action scripts shall ignore invalid or absent GUID input and exit without applying BCD changes.
2. Emergency stop behavior shall target only PowerShell processes whose command line includes NextBootTray.ps1.
