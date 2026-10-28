# Milestone 2 — dedicated server and multiplayer combat

Godot **4.7.2.stable**. One headless authoritative server and two clients share the Milestone 1 arena. The server simulates movement, raycasts shots, and owns health. Clients send input and render the result.

Milestone 1 local play is unchanged when you launch with no network flags.

## Launch

Double-click [tools/launcher.vbs](../tools/launcher.vbs). It starts, restarts, and stops the headless server, and it opens client windows on the address and port in the form. Closing the launcher leaves the server and clients running.

From the project root:

```powershell
powershell -ExecutionPolicy Bypass -File "C:\Users\Admin\Documents\VSC\survival-sandbox\tools\start_multiplayer.ps1"
```

That waits until the server writes `SERVER_READY`, then opens two client windows. Default address `127.0.0.1`, port `7777`. Override with `-Address` and `-Port`.

The script prints the exact Godot command for that run, including a unique status file under `%TEMP%`. The same flags with a stable status path are:

```powershell
& "$env:LOCALAPPDATA\Microsoft\WinGet\Packages\GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe\Godot_v4.7.2-stable_win64_console.exe" --headless --path "C:\Users\Admin\Documents\VSC\survival-sandbox" -- --server --port 7777 --status-file "$env:TEMP\survival-sandbox-server.txt"
```

```powershell
& "$env:LOCALAPPDATA\Microsoft\WinGet\Packages\GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe\Godot_v4.7.2-stable_win64.exe" --path "C:\Users\Admin\Documents\VSC\survival-sandbox" -- --client --address 127.0.0.1 --port 7777 --window-x 40 --window-y 40
```

```powershell
& "$env:LOCALAPPDATA\Microsoft\WinGet\Packages\GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe\Godot_v4.7.2-stable_win64.exe" --path "C:\Users\Admin\Documents\VSC\survival-sandbox" -- --client --address 127.0.0.1 --port 7777 --window-x 700 --window-y 40
```

Local single-player (Milestone 1) is still:

```powershell
& "$env:LOCALAPPDATA\Microsoft\WinGet\Packages\GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe\Godot_v4.7.2-stable_win64.exe" --path "C:\Users\Admin\Documents\VSC\survival-sandbox"
```

`--server` and `--client` together is an error. `--bot` is only valid with `--client`. A failed bind prints `SERVER_FAILED` and exits. A client that cannot connect prints `connection to <host>:<port> failed` on each attempt and `CLIENT_FAILED` after eight attempts.

## Checks

Authoritative simulation, in one process:

```powershell
& "$env:LOCALAPPDATA\Microsoft\WinGet\Packages\GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe\Godot_v4.7.2-stable_win64_console.exe" --headless --path "C:\Users\Admin\Documents\VSC\survival-sandbox" --script res://tests/milestone2_net.gd
```

Success prints `MILESTONE2_NET_OK`.

Two real processes (headless server, two bot clients):

```powershell
powershell -ExecutionPolicy Bypass -File "C:\Users\Admin\Documents\VSC\survival-sandbox\tools\start_multiplayer.ps1" -Automated
```

Success prints `AUTOMATED_MULTIPLAYER_OK`. Milestone 1 is still `tests/milestone1_smoke.gd` and `MILESTONE1_SMOKE_OK`.

Godot 4.7.2 does not expose `Node.set_multiplayer`, so the in-process script cannot attach a second ENet peer. It drives the server handlers directly. The process script is the connection test.

## Controls

Same as Milestone 1. Each window controls only its own character. The mouse is the aim point. Movement is camera-relative. Your character and remote characters both glide between server snapshots.

| Action | Input |
| --- | --- |
| Move | W A S D, or the arrow keys |
| Aim | Mouse |
| Shoot | Left mouse button |
| Zoom | Mouse wheel |
| Orbit | Middle mouse, or Z/Y and C |
| Lean | Q and E |
| Crouch | Hold Ctrl. Lowers the server hitbox and the muzzle. |
| Inventory | Tab opens it. Escape or Tab closes it. |

The window title shows the server-assigned peer id. Godot 4.7 gives each connection a large id, not 2 and 3. Body color is picked from a small palette using that id.

## What the server decides

- Peer id. The ENet id is the session id. Clients never send an id to claim a pawn.
- Spawn pad, chosen from separated points in the south yard.
- Movement. The client sends axes, camera yaw, aim yaw, lean, and a sequence. It does not send a position.
- Shot origin, from the pawn muzzle after the server clamps lean, crouch, and aim pitch. The client sends a direction only. Pitch can aim up or down and is clamped. Crouch shortens the capsule and lowers the muzzle.
- Cooldown (0.35 s on the pistol), fire rate, and the raycast.
- Health of players and both dummies.

A shot event is only a tracer. Health is a separate absolute value. Clients ignore a higher health value, so a stale snapshot cannot heal. Nothing in this milestone heals or respawns.

## Manual checklist

1. Run `tools\start_multiplayer.ps1`. The server console stays up. Two windows open, titled with different peer ids.
2. Both windows show two characters. WASD moves only the local one. The other window shows that movement without a hard snap every tick.
3. Walk into the north wall. The body stops. The other window agrees.
4. Orbit, zoom, and lean still work. The visor does not spin with the camera.
5. Shoot the red Open Dummy in the chest, then aim at its head and at the ground in front of it. The tracer follows the cursor up and down. A second click during the cooldown does not. Hold Ctrl and the body and muzzle drop; a shot aimed at standing head height can pass over a crouched player.
6. Shoot the orange dummy on the west side. The shot lands. Aim past the north wall and the tracer stops on that wall.
7. Shoot the other player in the open. Their HP drops in both windows. Put the north wall between you and the shot does not.
8. Close one window. That character disappears from the other window. The remaining player can still move and shoot. The server process is still running.
9. Launch a client with `--port 1` (nothing listening). The overlay and console say the connection failed.
10. Launch the game with no flags. The Milestone 1 arena, camera, and pistol still work.

## Decisions

- High-level multiplayer over ENet. The listen cap is 100. That number is not a load test.
- Snapshots are 20 Hz and stamped on the server tick. Remote bodies interpolate over the last 100 ms. The owning body interpolates over the last 80 ms, so the camera does not step once per snapshot. Gaps larger than 8 m snap once.
- The owning client does not predict. It stores the last acknowledged input sequence and server velocity so prediction can be added without changing the server command.
- Input is `unreliable_ordered`. Spawns, shots, and health are reliable. This Godot build rejects a channel number on `@rpc`, so those calls share the default channel.
- The dedicated server loads the same arena, deletes the baked player and the HUD, and strips the camera from each server pawn.
- Players do not collide with each other. Walls and dummies still stop the body. Shots hit players and dummies and stop on world geometry.
- There is no ammunition. The pistol cooldown is the fire gate, read from `HitscanWeapon` (34 damage, 40 m, 0.35 s).

## Known limitations

- Local movement lags by the round trip plus about 80 ms of interpolation. It does not predict.
- No lag compensation or rollback. Live enemy transforms are filtered by line of sight in Milestone 3.
- Session ids only. No accounts, persistence, inventory, building, or fog of war.
- A modified client can still aim perfectly. It cannot grant itself a hit, an origin, a damage value, or a faster cooldown.
- Downed players stay at 0 HP. There is no respawn.
- Two clients are the tested multiplayer case. One hundred listeners is only the ENet cap.
- `debug_place` and `debug_reset_cooldown` are in-process test hooks. They are not RPCs.
