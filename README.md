# Survival Sandbox

Local playable prototype of a 3D top-down survival sandbox, plus a dedicated authoritative server. Milestone 1 is one player in one arena. Milestone 2 adds a headless server, two clients, server-side movement, and server-side hitscan. There is still no persistence.

Built for Godot **4.7.2 stable**.

## Play

Import `project.godot` in the Godot 4.7 project manager and press F5, or run:

```powershell
& "$env:LOCALAPPDATA\Microsoft\WinGet\Packages\GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe\Godot_v4.7.2-stable_win64.exe" --path "C:\Users\Admin\Documents\VSC\survival-sandbox"
```

Open the editor with the same command plus `--editor`.

## Check

```powershell
& "$env:LOCALAPPDATA\Microsoft\WinGet\Packages\GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe\Godot_v4.7.2-stable_win64_console.exe" --headless --path "C:\Users\Admin\Documents\VSC\survival-sandbox" --script res://tests/milestone1_smoke.gd
```

A passing run prints `MILESTONE1_SMOKE_OK` and exits 0.

Controls, the manual checklist, and the decisions for the local prototype are in [docs/milestone-1.md](docs/milestone-1.md).

## Multiplayer

Double-click `tools\launcher.vbs`. The window can start, restart, and stop the server, and it can open client windows.

```powershell
powershell -ExecutionPolicy Bypass -File "C:\Users\Admin\Documents\VSC\survival-sandbox\tools\start_multiplayer.ps1"
```

Headless server plus two bot clients:

```powershell
powershell -ExecutionPolicy Bypass -File "C:\Users\Admin\Documents\VSC\survival-sandbox\tools\start_multiplayer.ps1" -Automated
```

Authoritative simulation check:

```powershell
& "$env:LOCALAPPDATA\Microsoft\WinGet\Packages\GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe\Godot_v4.7.2-stable_win64_console.exe" --headless --path "C:\Users\Admin\Documents\VSC\survival-sandbox" --script res://tests/milestone2_net.gd
```

A passing run prints `MILESTONE2_NET_OK`. The launch flags, manual checklist, and limitations are in [docs/milestone-2.md](docs/milestone-2.md).

Line-of-sight filtering is [docs/milestone-3.md](docs/milestone-3.md). Inventories, pickups, and crates are [docs/milestone-4.md](docs/milestone-4.md).

## Building

Press F5, or use **Play local (building)** in `tools\launcher.vbs`. Select hotbar slot 2 (Build Tool), pick a blueprint from the right-hand menu, left-click to place. In a server game the same tool sends a request; the server places, damages, and collapses, and clients receive the result. `scenes/world/building_test.tscn` is the arena with every Phase 1 scenario prebuilt. Building regression suite:

```powershell
& "$env:LOCALAPPDATA\Microsoft\WinGet\Packages\GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe\Godot_v4.7.2-stable_win64_console.exe" --headless --path "C:\Users\Admin\Documents\VSC\survival-sandbox" --script res://tests/building_phase1.gd
```

A passing run prints `BUILDING_PHASE1_OK`. Status, architecture, controls, and known issues are in [BUILDING_SYSTEM_STATUS.md](BUILDING_SYSTEM_STATUS.md).
