# Milestone 1 — playable 3D prototype

Godot **4.7.2.stable**. One local player in a primitive arena. Multiplayer, inventory, crafting, building, fog of war, cutaway, and persistence are intentionally absent.

The automated check `tests/milestone1_smoke.gd` passed on this machine against the installed engine: floor contact, camera-relative movement math, screen-center aim on the floor plane, divider collision, tall-cover occlusion, short-cover clearance, lean clamping, camera pull-in, hitscan damage, and the fire cooldown.

## Launch

Game:

```powershell
& "$env:LOCALAPPDATA\Microsoft\WinGet\Packages\GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe\Godot_v4.7.2-stable_win64.exe" --path "C:\Users\Admin\Documents\VSC\survival-sandbox"
```

Editor: add `--editor` to that command, or import `project.godot` from the Godot project manager and press F5.

Headless check (console build, so script errors stay visible):

```powershell
& "$env:LOCALAPPDATA\Microsoft\WinGet\Packages\GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe\Godot_v4.7.2-stable_win64_console.exe" --headless --path "C:\Users\Admin\Documents\VSC\survival-sandbox" --script res://tests/milestone1_smoke.gd
```

Success prints `MILESTONE1_SMOKE_OK`.

## Controls

The mouse is never captured. The OS cursor is the aim point.

| Action | Input |
| --- | --- |
| Move | W A S D, or the arrow keys. Direction is the camera's horizontal forward and right. |
| Aim | Move the mouse. A green marker sits on the floor under the cursor. |
| Shoot | Left mouse button. One shot per click. |
| Zoom | Mouse wheel. |
| Orbit the camera | Hold the middle mouse button and drag, or hold C. Orbit the other way with Z, or with Y so the key labeled Z works on a German QWERTZ keyboard. |
| Lean | Q left, E right. |
| Quit | Escape. |

WASD, Q, and E are the same physical keys on US QWERTY and German QWERTZ. Bindings use physical key positions.

At startup the camera sits south of the character and looks toward the `NORTH` label. W walks toward that label.

## What you should see

- A walled yard, a tan center wall, a short crate on the east side, and a tall crate on the west side.
- A blue capsule with a dark visor and a gun. The visor shows facing. Facing follows the mouse, not the camera.
- A red **Open Dummy** northeast of the spawn, visible immediately.
- An orange **Covered Dummy** due north, behind the tan wall.
- A dark overlay with FPS, position, aim, lean, weapon state, and both health values.

Three hits destroy a dummy (100 HP, 34 damage). It turns dark, the label says `DESTROYED`, and the body still blocks movement and shots.

## Manual checklist

1. The game window opens on the arena. The overlay shows a changing FPS and a position near `(0, 0, 8)`.
2. W A S D move the character. The outer walls, the tan wall, both crates, and both dummies stop the body.
3. Walk into the tan wall from the south. The character stops on the near side.
4. Scroll the wheel. The view moves closer and farther while staying above the character. The closest and farthest distances stop changing at the limits.
5. Orbit with the middle mouse button, then with Z/Y and C. The character's visor does not spin with the camera.
6. After a large orbit, W still moves toward the top of the screen (camera-forward), not toward the old north.
7. Put the cursor over a floor spot and orbit with Z/Y or C while holding the mouse still. The green marker stays under the cursor.
8. Left-click the red dummy. A short tracer appears, its label and the overlay lose 34 HP, and the body flashes. The fourth click during the cooldown does not add a second hit. Three clicks destroy it.
9. From the spawn, aim at the orange dummy and shoot. The tracer stops on the tan wall. The overlay says `blocked by Divider`. Orange HP stays at 100.
10. Walk around either end of the tan wall and shoot the orange dummy. Its HP drops.
11. Shoot the tall west crate at chest height. The shot stops on it. Shoot over the short east crate at a target beyond it. The tracer clears the crate.
12. Stand in the open and hold Q or E. The tracer leaves the gun from the leaned position, shifted sideways from a shot fired while standing straight. Stand beside the tall crate and lean into it. The mesh and the muzzle stop on the near side of the crate. The camera stays on the collision body.
13. Walk up to a wall with the camera zoomed out. The camera pulls in to the near side of that wall.
14. Escape closes the game.

## Decisions

- The aim surface is the flat plane `y = 0` (the arena floor). A physics ray onto arbitrary geometry waits until floors exist at more than one height.
- The camera pitch is fixed at −52°. Distance changes with the wheel. Orbit input is middle-mouse drag plus Z/Y and C, because Q and E are lean.
- Hitscan is horizontal from the weapon muzzle toward the aim point. The muzzle is on the lean pivot, so Q and E move the point the shot comes from. Two sideways raycasts keep the body on the near side of cover. If the barrel would start inside a wall, the origin is pulled back to that wall's near face.
- Dummies use the world layer and the damageable layer, so they stop movement and can be hit. A destroyed dummy keeps its collision.
- Camera collision is one ray from the chest to the desired camera position. SpringArm3D is available in 4.7.2 and was left unused so the pull-in stays obvious.
- On this engine build, `CapsuleShape3D.height` and `CapsuleMesh.height` are the full height. The body is 1.8 m tall with a 0.35 m radius.
- 3D physics uses the engine default (`physics/3d/physics_engine = DEFAULT`). No extra physics plugin is installed.

## Local-only code

These files decide gameplay on the local machine. Milestone 2 has to replace that authority with the dedicated server:

- `scripts/player/player_controller.gd` — movement, facing, lean clamp, fire trigger
- `scripts/combat/hitscan_weapon.gd` — ray query and damage application (`resolve_shot` is the piece to move)
- `scripts/combat/damageable.gd` — health
- `scripts/combat/shot_visual.gd` — tracer only; keep it as a response to a confirmed hit

The camera and aim projector stay client presentation. The server must not trust the projected aim point.

## Current scope

- One process plays and simulates the arena. There is no dedicated server, replication, or fog of war.
- Nothing is saved. Disconnect and restart are not meaningful yet.
- There is no inventory, loot, crafting, or grid building.
- There is no ammo, reload, recoil, or character animation. Leaning offsets the body and moves the muzzle the shots come from.
- Aiming ignores slopes and other floors. The test arena is flat.
- The camera sits high enough that zooming out can show the yard behind the tan wall. Shots stay at chest height, so that wall still stops them. Hiding what the camera can see is Milestone 3 and Milestone 6.
- Structural collapse and dynamic cutaway are not implemented.
- The scene is a handful of boxes and a capsule, built to read cover, not to look finished.
- Player count and server tick cost are not measured. Nothing here is evidence for 100 concurrent players.

## Next milestone

Milestone 2 is a dedicated server with authoritative movement and combat. Do not start it until this prototype has been played and the milestone is explicitly approved.
