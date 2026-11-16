# Milestone 8 — death loop (vertical slice, phases 0 and 1)

A pawn that reaches zero health drops everything it carries where it fell, waits five seconds, and comes back at a spawn pad. This is the first step toward a playable multiplayer slice: enemies (phase 2) need a consequence to mean anything.

## Scope freeze

Until the slice plays end to end, add no new items, recipes, tech tiers, or deployables. The catalog already holds about 200 items; the loop around them is what is missing. The slice is: two players join the survival map, gather, craft a weapon, cook food, build a shelter, survive roaming enemies for about 20 minutes, die and recover their loot, and keep their state across a reconnect.

Order of work: death loop (this milestone), enemy v1, `use_item` and stamina, hunger, clothing, polish.

> Superseded by [roadmap.md](roadmap.md). The order is now: M9 hog, M10 swarmers and nest, M11 eat/drink/heal, M12 stamina and combat, M13 shelter, M14 polish and gate. Clothing moved to Alpha, because it needs temperature to matter. The freeze itself still holds.

## Run the checks

```powershell
powershell -ExecutionPolicy Bypass -File "C:\Users\Admin\Documents\VSC\survival-sandbox\tools\run_tests.ps1"
```

Runs every headless test and prints one line each. Add `-Refresh` after adding a `class_name` script, `-Only milestone8` for one test, `-Slow` to add the building stress test. A test that is accepted as failing for now goes in the `$Known` table in the script (it prints `KNOWN` and is not counted; `-Strict` counts it). The table is empty. The new test alone prints `MILESTONE8_DEATH_OK`. The HUD can be rendered to PNGs (needs a window, not `--headless`) with `tests/vitals_capture.gd`; shots land in `user://vitals_shots/`.

### Tests repaired

Five tests failed before the death-loop work started. None was a game bug. Each test assumed something the game had since changed on purpose, and two of them stopped early, so most of their checks had not run for a while.

| Test | What had changed | Fix |
| --- | --- | --- |
| `milestone2_net` | Walking is slower (1.25 × 1.3 m/s), so 45 ticks no longer reached the wall. | Walk until blocked, with a time limit. It then also hit an impossible expectation (a dummy at 32 HP "dropping to -2"; health clamps at 0), now corrected. |
| `milestone4_inventory` | Same pace change; 8 ticks no longer cover 0.2 m after closing a crate. | Allow up to 30 ticks. |
| `building_phase1` | Doorways are draggable runs now (`doorway.tres`, "Wände ziehbar"). | The check "a doorway cannot drag" became checks that it drags along its edge, stays straight, and cancels cleanly. |
| `building_phase2` | Tiers have texture art, and a textured material keeps a white `albedo_color`. | One helper compares the texture (or the colour when a tier has no art), and now also asserts composite differs from scrap. |
| `building_phase4` | Players spawn in the south-west yard, past the 15 m build reach of the origin. | Stand both players beside the build site. |

Repairing `milestone2_net` and `building_phase4` also means their shot, crouch, disconnect, damage, repair, blast and collapse checks now run against the death-loop code (that was 17 of 90 checks before for phase 4).

`scripts/core/debug_flags.gd` replaces four direct `InputBindings.debug_enabled` reads. An autoload name does not compile under `godot --script`, so every test that loaded the player scene failed. `DebugFlags.enabled()` looks the autoload up at call time and behaves the same in the game.

## What happens when someone dies

1. `VitalsSystem` (server only) sees health at zero. It polls, so a death from any source (a shot now; enemies, hunger, cold later) takes the same path.
2. `GameNet.server_handle_death` closes any open crate, empties the bag and the cursor, and drops each stack on a widening ring around the body. A wall between the body and a spot pulls that drop back in front of the wall. The owner gets `death_notice` and sees YOU DIED with a countdown.
3. After `VitalsSystem.RESPAWN_DELAY_SEC` (5 s) `server_respawn` picks the spawn pad farthest from every other living player, calls `PlayerController.revive`, and grants the loadout (empty on the survival map). Observers who can see the pawn get `player_respawned`.
4. Anyone can loot the drops. They are ordinary `drop_N` pickups, so they save and load with the world.

Not dropped: items the respawn loadout hands back (the debug map's free tools, so each death does not mint a spare), and items nobody can pick up.

## Decisions

- Health still only goes down. `apply_authoritative_health` and `Damageable` ignore a higher value, so a stale snapshot cannot heal. `revive()` is the only way up, and the server tells clients with a reliable RPC.
- Drops are scattered pickups, not a single bag container. Containers are baked into the scene and indexed at boot, so a dynamic bag would need its own spawn, sync, and save path. Scattered drops reuse code that is already tested. A tidy bag can replace them later.
- A downed body lies on its back. The character model comes from a glTF and ignores the capsule material, so tinting alone looked alive.
- A dead player cannot pick up, craft, move items, open crates, toggle doors, shoot, build, repair, upgrade, blast, or deploy. Item actions fail in `_begin_item`; building actions in the relay `_gate`; `hotbar_item` returns nothing.
- Leaving while dead and coming back is a fresh spawn with a fresh loadout, not a corpse. The bag was already dropped when they died.
- `VitalsSystem` and `EnemySystem` are children of `GameNet` on the server. `GameNet` keeps the RPC surface and routes to them, so the new systems do not grow `game_net.gd`. `EnemySystem` is an empty skeleton until phase 2.

## Manual check

1. Start the server from the launcher, then two clients.
2. Shoot the other player three times. Their health bar empties, the screen flashes red, and the body lies down.
3. They see YOU DIED and a countdown. Their things are on the ground around the body, and you can pick them up.
4. After five seconds they stand up at a spawn pad away from you, with an empty hotbar on the survival map.
5. Close and reopen the client while dead. It comes back alive.

## Limits

- Nothing heals yet. There is no `use_item`, so food and medical supplies still cannot be used.
- A downed body keeps its collider, so shots that hit it stop there.
- The delay, the drop ring, and the flash strengths are constants, not tuned.
- Dropped items are never removed. Despawn timers come with the other pickup limits.
- Death over a real connection is covered by the HUD render and the two-process bot run, not by an automated two-process death test.
