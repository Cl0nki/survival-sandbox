# Survival Sandbox

Local playable prototype of a 3D top-down survival sandbox, plus a dedicated authoritative server. Milestone 1 is one player in one arena. Milestone 2 adds a headless server, two clients, server-side movement, and server-side hitscan. Milestone 7 saves the dedicated-server world and restores a player who reconnects with the same token.

Built for Godot **4.7.2 stable**.

**What is next:** [docs/roadmap.md](docs/roadmap.md) has the plan to the vertical slice (M10 to M14), then the full game, plus the bug and debt backlog.

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

Locomotion QA (stand BlendSpace on the Pro mannequin — rest mismatch, hip bob, unbound tracks):

```powershell
powershell -ExecutionPolicy Bypass -File "C:\Users\Admin\Documents\VSC\survival-sandbox\tools\check_loco.ps1"
powershell -ExecutionPolicy Bypass -File "C:\Users\Admin\Documents\VSC\survival-sandbox\tools\check_loco.ps1" -Rebuild
powershell -ExecutionPolicy Bypass -File "C:\Users\Admin\Documents\VSC\survival-sandbox\tools\check_loco.ps1" -Capture
```

Manual eye-check: open `scenes/debug/loco_preview.tscn` (keys `1–9` directions, `C` crouch). Capture PNGs land in `user://loco_shots/`.

Controls, the manual checklist, and the decisions for the local prototype are in [docs/milestone-1.md](docs/milestone-1.md).

## Multiplayer

Double-click `tools\launcher.vbs`. The window can pick **debug** or **survival** map, start/reset/stop the server, open client windows, and open the asset pipeline dashboard. Survival is a larger resource yard with no chests and no debug loadout (`--map survival`, save `user://world_survival.json`); debug keeps the showcase pads and free tools.

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

Line-of-sight filtering is [docs/milestone-3.md](docs/milestone-3.md). Inventories, pickups, and crates are [docs/milestone-4.md](docs/milestone-4.md). World save and reconnect are [docs/milestone-7.md](docs/milestone-7.md). Death, drops, and respawn, plus the scope freeze for the vertical slice, are [docs/milestone-8.md](docs/milestone-8.md). The first creature, the hog, and the shared creature base are [docs/milestone-9.md](docs/milestone-9.md).

Run every headless test at once with `tools\run_tests.ps1`.

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

## Sound

Footsteps (per ground type), gunshots and bullet impacts, hog calls, getting hurt, and crafting have sound slots. Placeholder files for walking, shooting and the hog are in `assets/audio/sfx/` (credits in `CREDITS.md` there). The game stays silent for a slot until it has a file. Fill them in the **Sounds** tool: open the dashboard (launcher button **Open sounds**, or `http://127.0.0.1:8765/sounds`). Upload WAV, OGG, MP3, or a pack ZIP, or scan a folder on this PC with a name filter. Each file lands in an inbox with a suggested slot. Press **Add**, or drag it onto a column. Files go to `assets/audio/sfx/<event>/` and the game reads `resources/audio/sounds.json`, so the next launch plays them. Per-event volume, pitch, cooldown, and hearing range are on each column. Details are in [tools/ai_asset_pipeline/README.md](tools/ai_asset_pipeline/README.md#sounds).

Check: `tools\run_tests.ps1 -Only sfx` prints `SFX_OK`.
