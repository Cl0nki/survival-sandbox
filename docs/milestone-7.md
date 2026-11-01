# Milestone 7 — persistent world and reconnect

The dedicated server writes one JSON file for the arena. A client that comes back with the same token gets its inventory, health, and last position. There are still no accounts.

Local play and the automated two-process check do not write a file. Tests leave `world_path` empty unless they set it.

## Launch

Double-click `tools\launcher.vbs`, or:

```powershell
powershell -ExecutionPolicy Bypass -File "C:\Users\Admin\Documents\VSC\survival-sandbox\tools\start_multiplayer.ps1"
```

Both pass `--world-file user://world.json` to the server. On Windows that file is under `%APPDATA%\Godot\app_userdata\Survival Sandbox\world.json`. Restart the server, then a client, and the yard is the one you left.

A client keeps `user://player.id` and sends it with `client_ready`. Override it with `--player-token TOKEN` when you want two windows to be different people on one machine.

```powershell
& "$env:LOCALAPPDATA\Microsoft\WinGet\Packages\GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe\Godot_v4.7.2-stable_win64.exe" --path "C:\Users\Admin\Documents\VSC\survival-sandbox" -- --client --address 127.0.0.1 --port 7777 --player-token aliceslot
```

Headless check:

```powershell
& "$env:LOCALAPPDATA\Microsoft\WinGet\Packages\GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe\Godot_v4.7.2-stable_win64_console.exe" --headless --path "C:\Users\Admin\Documents\VSC\survival-sandbox" --script res://tests/milestone7_persist.gd
```

Success prints `MILESTONE7_PERSIST_OK`.

## What is saved

- Building pieces, rooms, health, and the next ids, using the same records a late joiner already applies
- World pickups, including drops, and crate slots
- Dummy health
- One profile per valid token: slots, position, yaw, health

The file is replaced atomically (`path.tmp`, then rename). The server also writes on disconnect, every 30 seconds, and when the process exits. A missing or corrupt file leaves the live arena as it is.

## Reconnect

The token is 8–64 letters, digits, `-`, or `_`. It is a cookie. A second live peer with the same token is refused. An empty or invalid token still plays, but that pawn is not stored. A bot makes a fresh token each run and does not write `player.id`.

The owning client never sends inventory contents or a claimed position. The server restores those from the file.

## Manual check

1. Start the server from the launcher, then one client.
2. Pick up the south-east scrap pile and build a 2×2 room near the origin.
3. Close the client. Restart the server and the client.
4. The scrap pile is gone, the room is still there, and the hotbar still has that scrap.
5. Open a second client with a different `--player-token`. It starts with the usual loadout and no scrap.

## Limits

There is no login, password, or database. Anyone who can send a token can claim that profile. Local F5 play does not save. The automated `start_multiplayer.ps1 -Automated` run does not pass `--world-file`, so it cannot leave a dirty yard for the next check. Crafting, respawn, and hunger are still absent.
