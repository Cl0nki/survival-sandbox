# Milestone 1 — playable 3D prototype

Godot **4.7.2.stable**. One local player in a primitive arena. Inventory, crafting, building, fog of war, cutaway, and persistence are intentionally absent. Multiplayer is Milestone 2.

The automated check `tests/milestone1_smoke.gd` passed on this machine against the installed engine: floor contact, camera-relative movement math, screen-center aim on the floor plane, outer-wall collision, wall occlusion, lean clamping, camera pull-in, hitscan damage, and the fire cooldown.

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
| Aim | Move the mouse. The shot goes from the muzzle toward the 3D point under the cursor, so it can aim up or down. |
| Shoot | Left mouse button. One shot per click. |
| Deploy | Select a deployable on the hotbar. A blueprint shows the footprint (2x1 for a chest). Left click places it within 5 m. R rotates it. |
| Zoom | Mouse wheel. |
| Orbit the camera | Hold the middle mouse button and drag, or hold C. Orbit the other way with Z, or with Y so the key labeled Z works on a German QWERTZ keyboard. |
| Lean | Q left, E right. |
| Crouch | Hold Ctrl. The capsule and the muzzle drop. Crouch movement is slower. |
| Inventory | Tab opens it. Escape or Tab closes it. |

WASD, Q, and E are the same physical keys on US QWERTY and German QWERTZ. Bindings use physical key positions.

At startup the camera sits south of the character and looks toward the north wall. W walks toward that wall.

## What you should see

- A 3 by 3 grid of **10x10** tiles. A blue capsule with a dark visor and a gun stands on **DEPLOYABLES**.
- **WOODS** north-west: Oak, Birch, and Spruce, tall enough to walk under the canopy. A pickup of each yield sits beside the trunk. Hatchets on the south edge, and a **Woods** chest in the south-east corner.
- **SCAVENGE** north: Broken Down Car, Scrap Pile, Rubble Pile, and Tire Pile, still cubes, each with its yield pickups beside it. Crowbars on the south edge. A **Scavenge** chest on the east side.
- **GROUND** north-east: Sand, Clay, Gravel, Ground Water, Natural Gas, and Crude Oil, each with a pickup. Sand, clay, and gravel take a shovel. The fluids wait for a well or pump. A **Ground** chest on the east side.
- **MINE** west: nine ore nodes, each with a pickup. Pickaxes on the south edge. A **Mine** chest on the north edge.
- **BUILDING** in the middle: one chest per tier (Scrap, Wood, Brick, Stone, Concrete, Composite), stocked with that tier's materials. A gap down the middle stays open to walk through.
- **RANGE** east: red **Open Dummy**, orange **Covered Dummy**, and the **Military** chest on the south-west corner.
- **CRAFTING** south-west: Refining and Parts chests.
- **DEPLOYABLES** south: spawn pads, a **Deployables** chest (Chest and Workbench at 100 HP, plus the Scrap Furnace, Iron Smelter, Steel Smelter, and Foundry), and a **Doors and Windows** chest with one door and one set of window bars for every building tier, at half that tier's health. Put one on the hotbar and a blueprint shows where it will sit. Left click places it within 5 m. R rotates a footprint. Doors and window bars fit the matching opening. **F** opens and closes a door, and opens a furnace. A furnace runs one batch at a time: load input and coal (the Foundry also takes fuel) and the ingots land in the output slot. A shot that spends the last HP destroys the piece. A deployable on an upper floor is also destroyed when that floor falls.
- **SUPPLIES** south-east: the Collectables chest, plus cloth, food, scrap, and medical pickups.
- Resource and ground labels stay hidden until **F1**. Chests are solid. A standing shot still passes over a chest.

Three hits destroy a dummy (100 HP, 34 damage). It turns dark, the label says `DESTROYED`, and the body still blocks movement and shots.

## Manual checklist

1. The game window opens on the arena. The character stands near `(0, 0, 8)`, looking north. No debug panel is on screen.
2. W A S D move the character. The outer walls and both dummies stop the body.
3. Walk into the north wall. The character stops on the near side. The wall has no NORTH label.
4. Scroll the wheel. The view moves closer and farther while staying above the character. The closest and farthest distances stop changing at the limits.
5. Orbit with the middle mouse button, then with Z/Y and C. The character's visor does not spin with the camera.
6. After a large orbit, W still moves toward the top of the screen (camera-forward), not toward the old north.
7. Put the cursor over a floor spot, a wall, or a dummy and orbit with Z/Y or C while holding the mouse still. The green marker stays on that surface under the cursor.
8. Left-click the red dummy. A short tracer appears, its label loses 34 HP, and the body flashes. The fourth click during the cooldown does not add a second hit. Three clicks destroy it.
9. From the spawn, aim at the north wall and shoot. The tracer stops on the wall.
10. Walk to the east **RANGE**. Shoot the red open dummy from its FIRE pad. Its HP drops.
11. From the covered FIRE pad the orange dummy is behind COVER. Step beside the lane and shoot it. Its HP drops.
12. Stand in the open and hold Q or E. The tracer leaves the gun from the leaned position, shifted sideways from a shot fired while standing straight. Stand beside the west wall and lean into it. The mesh and the muzzle stop on the near side of the wall. The camera shifts sideways with that same lean.
13. Walk up to a wall with the camera zoomed out. The camera pulls in to the near side of that wall.
14. Press **F1**. White health and yield labels appear on the resource nodes and ground patches. Press **F1** again and they hide.
15. Escape closes the inventory. It does not quit.

## Decisions

- The cursor ray hits the arena, so the weapon aims up and down. Pitch is clamped to about 62 degrees. A straight-up or straight-down direction is rejected.
- The camera pitch is fixed at −52°. Distance changes with the wheel. Orbit input is middle-mouse drag plus Z/Y and C, because Q and E are lean.
- Hitscan starts at the weapon muzzle and follows that 3D direction. The muzzle is on the lean pivot, so Q and E move it sideways and Ctrl lowers it with the crouch capsule (1.8 m standing, 1.05 m crouched). Two sideways raycasts keep the body on the near side of cover. If the barrel would start inside a wall, the origin is pulled back to that wall's near face. Standing up is blocked when the standing capsule would intersect the world.
- Dummies use the world layer and the damageable layer, so they stop movement and can be hit. A destroyed dummy keeps its collision.
- Camera collision is one ray from the chest to the desired camera position. SpringArm3D is available in 4.7.2 and was left unused so the pull-in stays obvious.
- On this engine build, `CapsuleShape3D.height` and `CapsuleMesh.height` are the full height. The body is 1.8 m tall with a 0.35 m radius.
- 3D physics uses the engine default (`physics/3d/physics_engine = DEFAULT`). No extra physics plugin is installed.

## Local-only code

With no `--server` or `--client` flag, these files still decide gameplay on the local machine. Milestone 2 runs the same movement and hitscan on the dedicated server when those flags are set:

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
- The camera sits high enough to see across the open yard. Shots stop on the outer walls. Hiding what the camera can see is Milestone 3 and Milestone 6.
- Structural collapse and dynamic cutaway are not implemented.
- The scene is a handful of boxes and a capsule, built to read cover, not to look finished.
- Player count and server tick cost are not measured. Nothing here is evidence for 100 concurrent players.

## Next milestone

Milestone 2, a dedicated server with authoritative movement and combat, is documented in [milestone-2.md](milestone-2.md). This file stays the record of the local prototype.
