# Milestone 3 — server-side line of sight

The dedicated server decides who can see whom. A client receives another player's live transform only while that player is inside 42 m, 5% past the 40 m pistol, and a world ray from the observer can touch the target. The rays start at the leaned eye and at the muzzle. They aim at the head, chest, hips, and a ring 0.3 m outside the capsule, including the side facing the observer. A corner still gets the extra 5% margin. Someone is shown slightly before a bullet can touch them. Someone standing fully behind an outer wall does not.

There is no fog mesh. A hidden remote pawn is removed. Your own character is always replicated to you.

## Launch

Double-click `tools\launcher.vbs`, or:

```powershell
powershell -ExecutionPolicy Bypass -File "C:\Users\Admin\Documents\VSC\survival-sandbox\tools\start_multiplayer.ps1"
```

Headless check:

```powershell
& "$env:LOCALAPPDATA\Microsoft\WinGet\Packages\GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe\Godot_v4.7.2-stable_win64_console.exe" --headless --path "C:\Users\Admin\Documents\VSC\survival-sandbox" --script res://tests/milestone3_visibility.gd
```

Success prints `MILESTONE3_VISIBILITY_OK`.

## What is filtered

Snapshots are sent with `rpc_id` to each observer. The payload is built by `_snapshot_for`. It includes that observer and every peer `_is_visible` currently allows. A hidden peer's id and coordinates are left out of the array.

Becoming visible sends `spawn_player` and health to that one client. Becoming hidden sends `hide_player` with only the peer id. Join sync uses the same rule. Player health and shot tracers follow it: a third client does not receive a hidden shooter's muzzle or a hidden victim's impact point. The shooter still receives their own shot result. Dummy health is unchanged, because dummies are fixed arena props.

Sight is recomputed every physics frame, and again just before a shot. `NetConfig.VISIBILITY_DISTANCE` is 42 m. `NetConfig.VISIBILITY_EDGE_MARGIN` is 0.05. `NetConfig.VISIBILITY_LEAD` is 0.3 m.

## Manual check

1. Open the launcher and start the server, then two clients.
2. Stand in the south yard. Both windows show both characters.
3. Put the north wall between them, with one player outside it. The other character disappears from each window.
4. Walk back inside the yard. The character comes back at the real position, not the old one.
5. Walk until you are far apart. Beyond about 42 m the other character disappears even with a clear line.

## Limits

Sight is a full circle, not a facing cone. There is no light, sound, or stealth. The check runs every physics frame for each pair, which is enough for this arena and too naive for 100 players. The lead looks a short step around an edge. It does not see through a wall. A modified client can remember a position it was allowed to see earlier. It does not receive that player's later coordinates until the server can see them again.
