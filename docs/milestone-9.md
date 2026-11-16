# Milestone 9 — enemy v1, part a: the hog (vertical slice, phase 2a)

The first creature. It shares a base class with everything that comes later (swarmers, brutes), so this milestone is mostly the foundation: server-side simulation, replication to clients, loot, and a test that drives the creature by hand.

## What the hog does

A wild hog grazes near its home and ignores you until you shoot it or walk up to it.

| State | What happens | Counter-play |
| --- | --- | --- |
| Idle / Walk | Wanders within 6 m of home. Notices a standing player at 3.5 m, a crouching one at 2 m. | Crouch past it. |
| Windup (0.9 s) | Stops, faces you, then locks its direction for the last 0.35 s. Tints red and digs with its front legs. | The lock is visible; leave the line. |
| Charge | Runs 5 m/s in the locked direction for up to 8 m. Gores (25 damage) the first player it touches once per charge. | Sidestep. You cannot outrun it (sprint is 3 m/s). |
| Recover | 1.0 s after a gore, 1.4 s after running out of range. | Free shots. |
| Stunned | 2.5 s after hitting a wall or any solid. Yellow tint, stands still. | The reward for baiting it into a wall. |
| Dead | Drops 2–3 `raw_meat` around it, corpse stays 12 s. | |

It stays angry for 10 s after the last provocation, then goes back to grazing. A target that goes down or runs 18 m away ends the chase. 80 HP, so three pistol hits and a bit (34 each).

## How it is built

- `scripts/enemies/creature.gd` — `Creature`, the server-side base: health, `receive_damage` (the same duck-typed entry point the hitscan already calls), loot, a state number that gets replicated. It never simulates itself; `EnemySystem` calls `advance(delta)`.
- `scripts/enemies/hog.gd` — `Hog`, the state machine above. Kinds add states from `S_KIND_BASE` (10) up.
- `scripts/enemies/enemy_system.gd` — `EnemySystem`, owned by `GameNet` on both sides. Server: spawns, advances, drops loot, queues respawns, and publishes. Client: builds and updates puppets.
- `scripts/enemies/creature_view.gd` — `CreatureView`, the client puppet. It interpolates poses (`MotionBuffer`, same delay as player puppets) and plays a state-matched animation. The art is boxes; replace `_build_hog()` with a model later.
- `GameNet` gained four RPCs (`creature_spawn`, `creature_despawn`, `creature_health`, `creature_snapshot`) that only forward to `EnemySystem`, plus small public accessors (`server_tick`, `map_id`, `view_distance`, `spawn_loot`, `replicate_health`). `_handle_fire` tells a creature who shot it (`note_attacker`) before applying damage.

### Replication

A player is sent only the creatures it can see: inside the view distance (42 m) and with a clear line of sight from its eyes, the same rule as other players. Entering view sends a reliable spawn, leaving sends a despawn, and visible creatures ride a 20 Hz unreliable snapshot (x, y, z, yaw, state). Health changes go out reliably to the players who currently see the creature. Hogs are not saved in the world file; the server restocks them on boot.

### Spawning

Only the dedicated server (`--server`) stocks the world: 2 hogs on the debug map, 3 on survival, one placed per second until full. Spots are picked at random, must have open ground and room for the body, and must be at least 14 m from any player, 12 m from the spawn pads, and 6 m from another creature. A dead hog respawns 60 s later. Tests and local play do not auto-spawn.

## Run the checks

```powershell
powershell -ExecutionPolicy Bypass -File "C:\Users\Admin\Documents\VSC\survival-sandbox\tools\run_tests.ps1" -Refresh -Only milestone9
```

Prints `MILESTONE9_HOG_OK`. The test steps hogs by hand (60 Hz) and covers grazing, the crouch trigger, windup then charge order, gore damage and once-per-charge, a shot provoking it, a dodged charge, wall stun, death loot and corpse, a downed target ending the chase, the replication payload and puppet smoothing, and the server's spawner and respawn.

The placeholder art can be rendered with `tests/creature_capture.gd` (needs a window, not `--headless`); the shot lands in `user://creature_shots/`.

## Manual check

1. Start a server (`tools\start_multiplayer.ps1`) and join. Within a few seconds two hogs appear in the arena.
2. Walk toward one. It should stand still until about 3.5 m, then paw the ground, turn red, and charge. Sidestep late.
3. Shoot one from range: it charges you. Three-plus hits kill it and it drops raw meat. Pick the meat up.
4. Lure one so a wall is behind you, dodge, and watch it stun against the wall.
5. Two players: both see the same hog charge, and a hog behind a wall is not drawn.

## Limits

- No knockback on the player yet; a gore only deals damage.
- Hogs are not hurt by other hogs, do not path around obstacles (they walk straight, and give up a stuck wander goal), and do not attack buildings.
- Local (offline) play has no `GameNet`, so no hogs there.
- Melee harvest tools do not hit creatures; only the pistol does.
- Next: swarmers and the nest (2b), now M10 in [roadmap.md](roadmap.md). The base class, replication, and spawner are meant to be reused as they are.
