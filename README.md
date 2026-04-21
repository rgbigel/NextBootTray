# NextBootTray Version 3.0.0

NextBootTray provides tray-based boot target control for Windows.

## Current behavior

- Left-click tray icon: show boot action menu.
- Right-click tray icon: show only `Exit NextBootTray`.
- Menu contains:
	- All detected boot entries by description (checked entry is active default)
	- A checked mark on the current active default entry
	- `Boot now: <active entry>` action
	- `More...` entry that opens a placeholder tools page (item 5 dummy)
- Clicking a non-active entry updates the default and keeps the menu open.
- Clicking the checked active default performs immediate boot/restart behavior.
- Repeated left-click interactions reuse in-memory boot cache.
- Hibernation resume entries (`winresume`) are classified as `Hibernation` and hidden from boot choices.
- Boot-now action performs cold reboot via `shutdown /r /t 0 /hybrid-off`.
- Boot-now saves current `powercfg /h` state per machine, disables hibernation for reboot, and restores state on next tray start.
- `AOMEI` and `Macrium` recovery entries are included as selectable tool entries when present.

## Run modes

- Normal launcher (runs elevated logon task): `NextBootTray.cmd`
- Diagnostics: `NextBootTray.cmd -D`
- Emergency stop: `NextBootTray.cmd -STOP`

You can also run the script directly from an elevated shell:

`pwsh -NoProfile -STA -File D:\OneDrive\cmd\NextBootTray.ps1 -D -Detach`

## Design flow

See [Docs/NextBootTray.md](Docs/NextBootTray.md) for architecture and flow diagram.
