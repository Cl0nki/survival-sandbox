# Survival Sandbox

Local playable prototype of a 3D top-down survival sandbox, plus a dedicated authoritative server. Milestone 1 is one player in one arena. Milestone 2 adds a headless server, two clients, server-side movement, and server-side hitscan. Milestone 7 saves the dedicated-server world and restores a player who reconnects with the same token.

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

Double-click `tools\launcher.vbs`. The window can start, reset, and stop the server, open client windows, and open the asset pipeline dashboard.

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

Line-of-sight filtering is [docs/milestone-3.md](docs/milestone-3.md). Inventories, pickups, and crates are [docs/milestone-4.md](docs/milestone-4.md). World save and reconnect are [docs/milestone-7.md](docs/milestone-7.md).

## Building

Press F5, or start a server and a client from `tools\launcher.vbs`. Select hotbar slot 2 (Build Tool), pick a blueprint from the right-hand menu, left-click to place. In a server game the same tool sends a request; the server places, damages, and collapses, and clients receive the result. **Reset server** wipes `user://world.json` and starts an empty yard. `scenes/world/building_test.tscn` is the arena with every Phase 1 scenario prebuilt. Building regression suite:

```powershell
& "$env:LOCALAPPDATA\Microsoft\WinGet\Packages\GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe\Godot_v4.7.2-stable_win64_console.exe" --headless --path "C:\Users\Admin\Documents\VSC\survival-sandbox" --script res://tests/building_phase1.gd
```

A passing run prints `BUILDING_PHASE1_OK`. Status, architecture, controls, and known issues are in [BUILDING_SYSTEM_STATUS.md](BUILDING_SYSTEM_STATUS.md).

## Asset pipeline

Generated textures, props, characters, and modular building pieces are produced by `tools/ai_asset_pipeline`. It does not replace the live building solver or the primitive player mesh. Setup, provider keys, and the dashboard are documented in [tools/ai_asset_pipeline/README.md](tools/ai_asset_pipeline/README.md).

```powershell
python tools\ai_asset_pipeline\run.py serve
```
