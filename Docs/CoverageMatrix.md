# NextBootTray Coverage Matrix

Version: 3.0.0
Profile: default
Author: Rolf Bercht

## Flow Step IDs
- S1: Runtime interaction model step 1 (startup snapshot, restore pending hibernation state, startup cleanup).
- S2: Runtime interaction model step 2 (tray icon visible).
- S3: Runtime interaction model step 3 (left-click).
- S4: Runtime interaction model step 4 (build menu from cached state).
- S5: Runtime interaction model step 5 (entry selection including More...).
- A1: Action behavior: non-active entry -> NextBoot-SetDefault -> reopen menu.
- A2: Action behavior: checked active entry -> NextBoot-BootNow.
- A3: Action behavior: Boot now menu item -> NextBoot-BootNow.
- A4: Action behavior: BootNow sequence (state save, powercfg off, bootsequence, hybrid-off reboot).
- A5: Action behavior: next startup restore path.
- D1: Flow diagram right-click path (Show exit-only menu).

## Coverage Legend
- `Full`: Requirement is fully represented in flow or documented non-flow contract.
- `Partial`: Requirement has only high-level flow representation; details are in Requirements/Architecture.

## Non-Flow Contract Codes
- O1: Runtime mode contract (Notes section).
- O2: Launcher argument contract.
- O3: Launcher startup contract (scheduled task model).
- O4: Launcher fallback contract.
- O5: Installer contract.
- O6: Maintenance/versioning script contract.

## Functional Requirements -> Flow Coverage
| Req | Step(s) | Status | Note |
|:---:|:--------|:------:|:-----|
| F1 | S2 | Full | |
| F2 | S3 | Full | |
| F3 | D1 | Full | |
| F4 | S4 | Full | |
| F5 | S4 | Full | |
| F6 | S4 | Full | |
| F7 | S4 | Full | |
| F8 | S4 | Full | |
| F9 | S4 | Full | |
| F10 | S5 | Full | |
| F11 | S5 | Full | |
| F12 | S4 | Full | |
| F13 | S4 | Full | |
| F14 | A1 | Full | |
| F15 | A1 | Full | |
| F16 | A2 | Full | |
| F17 | A3 | Full | |
| F18 | S4 | Full | |
| F19 | O1 | Full | Non-flow runtime mode |
| F20 | S1 | Full | Stop-switch branch |
| F21 | S1 | Full | |
| F22 | O1 | Full | Non-flow runtime mode |
| F23 | A1, A2, A3 | Full | |
| F24 | A4 | Full | |
| F25 | A4 | Full | |
| F26 | A4 | Full | |
| F27 | A5 | Full | |
| F28 | A1 | Full | |
| F29 | O2 | Full | Non-flow launcher args |
| F30 | O3 | Full | Non-flow launcher startup |
| F31 | O4 | Full | Non-flow launcher fallback |
| F32 | O5 | Full | Non-flow installer |
| F33 | O5 | Full | Non-flow installer |
| F34 | O5 | Full | Non-flow installer |
| F35 | O5 | Full | Non-flow installer |
| F36 | O6 | Full | Non-flow maintenance |

## Interface, Operational, Data, and Safety Requirements
These requirements are implementation constraints and runtime qualities. They are not always represented as explicit menu-flow steps.

| Group | Flow Coverage | Notes |
|:------|:--------------|:------|
| Interface 1-3 | Partial | Platform and STA details are architectural constraints, not user-flow steps. |
| Operational 1-6 | Partial | Flow covers key runtime branches; detailed error/log handling is specified in Requirements/Architecture. |
| Data and State 1-5 | Partial | Flow covers cache/restore sequence; file schemas and state fields are architectural details. |
| Security and Safety 1-3 | Partial | Flow covers safe branches; validation and exit-code rules live in action-module behavior specs. |
