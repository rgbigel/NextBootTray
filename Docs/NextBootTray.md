# NextBootTray - Design Flow & Architecture (v3.0.0)

## Overview

NextBootTray is a tray-first launcher for boot target control.

- Left-click opens a dynamic boot-action menu.
- Right-click exposes only an exit command.
- Boot entry data is read from `bcdedit` and cached in memory for repeated interactions.
- Hibernation resume entries (`winresume`) are classified as `Hibernation` and excluded from menu selection.
- A `More...` entry opens a tools placeholder page with back navigation.
- Actions are executed via helper scripts:
	- `NextBoot-SetDefault.ps1`
	- `NextBoot-BootNow.ps1`

## Runtime interaction model

1. Tray process starts, writes process-state/log snapshot, restores pending hibernation state if needed, and performs startup cleanup of older tray instances.
2. Tray icon becomes visible.
3. User left-clicks tray icon.
4. Menu is built from cached BCD/default state (cache is refreshed at startup or when explicitly forced).
5. User picks one of:
	 - `<entry>` (set as default)
	 - `Boot now: <active entry>`
	 - `More...` (tools placeholder page)

### Action behavior

- Selecting a non-active entry:
	- Runs `NextBoot-SetDefault.ps1 -Id <GUID>`
	- Updates active default selection in menu state
	- Reopens menu so `Boot now` remains immediately available
- Selecting the checked active default entry:
	- Runs `NextBoot-BootNow.ps1 -Id <GUID>`
- Selecting `Boot now: <active entry>`:
	- Runs `NextBoot-BootNow.ps1 -Id <GUID>`
- `NextBoot-BootNow.ps1` sequence:
	- Reads current hibernation state
	- Persists machine-scoped restore state file
	- Disables hibernation (`powercfg /h off`)
	- Sets one-time boot target (`bcdedit /bootsequence`)
	- Reboots with `shutdown /r /t 0 /hybrid-off`
- On next tray start:
	- `NextBootTray.ps1` restores hibernation state when a pending restore file exists for the current machine

## Flow diagram

```mermaid
flowchart TD
		A[Launch NextBootTray.ps1] --> B{Stop switch?}
		B -- Yes --> C[Stop running tray instances and exit]
		B -- No --> D[Write process snapshot and restore pending hibernate state]
		D --> E[Startup cleanup stop older tray instances]
		E --> F[Refresh initial boot cache and default info]
		F --> G[Load WinForms and create tray icon]
		G --> H[Enter message loop]

		H --> I{User click}
		I -- Right click --> J[Show exit-only menu]
		I -- Left click --> K[Build left menu from cached state]

		K --> L{Menu selection}
		L -- Select non-active entry --> M[Run NextBoot-SetDefault.ps1]
		M --> N[Update active default in memory and reopen menu]
		L -- Select checked active entry --> O[Run NextBoot-BootNow.ps1]
		L -- Boot now active --> O
		L -- More... --> P[Show tools placeholder page]
		P --> Q[Back to boot entries]

		J --> H
		N --> H
		Q --> H
		O --> R[Save hibernate state, disable hibernate, set bootsequence, reboot hybrid-off]
```

## Notes

- BCD access requires elevation.
- Normal non-interactive startup is provided via elevated scheduled task (`NextBootTray-LogonElevated`) registered by installer.
- Diagnostics can be enabled with `-D`.
- Direct script diagnostics should use `-Detach` to avoid blocking the launching shell.
- Right-click intentionally does not show boot actions.
