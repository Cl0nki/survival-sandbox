# Roadmap — vertical slice, then the full game

Written 2026-11-16 against commit `db5b47e`. Baseline: `tools\run_tests.ps1` runs 25 tests and all 25 pass.

This file is the plan. `docs/milestone-N.md` files stay as the record of what each milestone built. When a milestone ships, add its doc, tick it here, and move any leftovers into the backlog at the bottom.

## Where we are

| # | Milestone | State | Doc |
| --- | --- | --- | --- |
| 1 | Local playable prototype | done | [milestone-1](milestone-1.md) |
| 2 | Dedicated server, authoritative movement and shooting | done | [milestone-2](milestone-2.md) |
| 3 | Line-of-sight filtering | done | [milestone-3](milestone-3.md) |
| 4 | Inventories, pickups, crates | done | [milestone-4](milestone-4.md) |
| 5–6 | Crafting, deployables, tech tree, smelting, biomes, survival map, building system, asset and sound pipeline | **done, but never written up.** The building system is documented and **approved** (2026-11-17). | only [BUILDING_SYSTEM_STATUS](../BUILDING_SYSTEM_STATUS.md) |
| 7 | World save and reconnect | done | [milestone-7](milestone-7.md) |
| 8 | Death loop | done | [milestone-8](milestone-8.md) |
| 9 | Hog (enemy v1, part a) | done | [milestone-9](milestone-9.md) |

What a player can do today on the survival map: join a server, gather from nodes and wrecks, craft through about 160 items and several tech tiers, smelt, cook, build multi-storey rooms that collapse when their supports die, shoot a pistol that uses ammo, get gored by a hog, die, drop everything, respawn, and return with the same token to a saved world.

What is missing is the part that makes it a game: **nothing keeps you alive and nothing makes you want to**. Food cannot be eaten, medicine cannot be used, nothing heals, there is one enemy type, and nothing asks you to plan.

## Principles

1. **The slice is one loop, not a feature list.** Gather, craft, eat, build, fight, die, recover. Every slice milestone must make that loop more playable or be cut.
2. **Scope freeze stays.** No new items, recipes, tech tiers, or deployables until the slice gate passes (see [milestone-8](milestone-8.md#scope-freeze)). About 160 items already exist. The loop around them is what is missing. Items that a milestone needs to function (a bandage, a water bottle effect) are allowed only if they reuse an existing item id.
3. **Server decides, client shows.** Every new system follows the `VitalsSystem` and `EnemySystem` pattern: a child of `GameNet`, `GameNet` keeps the RPC surface and forwards. There is no offline mode: single-player is an in-process server (M10, step 0), so a system written once works in both.
4. **Every milestone ships with a headless test and a doc**, the way M8 and M9 did.
5. **Stop growing `game_net.gd` (2,594 lines) and `player_controller.gd` (1,889 lines).** New code goes in new files. Splitting them is its own task (M14).

---

# Part 1 — Vertical slice

## Slice definition

> Two players join the survival map. They gather, craft a weapon, cook food, build a shelter, and survive roaming enemies for about 20 minutes. One dies, and the other recovers the loot. Both reconnect and find their state intact.

The first sentence of that goal was written in M8. This version adds numbers so "done" is checkable.

### Slice gate (exit criteria)

All of these must hold on a build exported from this repo, not only in the editor.

| # | Criterion | How it is checked |
| --- | --- | --- |
| G1 | A new player with no help reaches a cooked meal, a weapon, and a roof within 20 minutes. | Two fresh playtesters, screen recorded, nobody coaches them. |
| G2 | Hunger and thirst create pressure but never kill a player who is trying. | Idle test: a player who only eats when warned survives 60 minutes. |
| G3 | Every enemy type has a counter that a first-time player finds in under 3 encounters. | Playtest notes, one line per enemy. |
| G4 | A two-player, 20-minute server session has zero script errors in the server log and no desync report. | `start_multiplayer.ps1 -Automated` extended to a soak mode, then a real session. |
| G5 | Death, recovery, and reconnect work in a real two-process run, not only the in-process test. | Soak mode includes a scripted death and a client restart. |
| G6 | Server holds 60 ticks/s with 4 clients and 10 creatures. | Frame-time log from the soak run. |
| G7 | All tests in `run_tests.ps1` pass, including the new ones. | CI of one: the script. |
| G8 | The game has sound for walking, shooting, getting hurt, eating, and crafting, and no placeholder box is a creature. | Eyes and ears. |

## M9 — Hog (done)

Server-side creature base, replication, hog state machine, loot, spawner.

## M10 — NEXUS HOUND SECURITY (enemy v1, part b)

The first threat that comes to you. It is the first NEXUS robot in the game (see [nexus-industries.md](nexus-industries.md)). The base class, replication, and spawner from M9 are reused unchanged. If they cannot be, that is the bug to fix first.

### Step 0 — Single-player is an in-process server

**Decided.** There is no separate offline mode. Pressing Play starts a server inside the game process and connects the player to it, so single-player and multiplayer run the same code. This closes B-10. Do it first, before any new system, so M10 to M14 are written once.

- **What goes.** `NetConfig.MODE_LOCAL` and every branch that checks it: `GameNet` (7 references), `NetSession` (7), `NetConfig` (7), `test_arena.gd` (3), `debug_overlay.gd`, and `building_test.gd`. The local-only code paths the [milestone-1](milestone-1.md#local-only-code) doc lists (`player_controller.gd` movement and fire, `hitscan_weapon.gd`) stop being a second implementation and become the client side only.
- **What replaces it.** A "Play" entry that starts the server and client in one process. Whether the link is a loopback ENet peer on a random local port, or Godot's `OfflineMultiplayerPeer` (no socket, same RPC surface), is decided in this step. Try `OfflineMultiplayerPeer` first, since it avoids a port and a firewall prompt. Fall back to loopback ENet if RPCs or authority behave differently.
- **Hosting for friends is the same code.** "Host" is "Play" with the port open. This gives listen-server co-op for free, ahead of the dedicated-server work.
- **Latency.** The in-process link has no round trip, so the 80 ms interpolation delay is the only lag a solo player feels (B-24). It can be shortened for the loopback case.
- **Saving.** Single-player gets its own world file (`user://world_solo.json`) and the same token and profile path as a server. This replaces "Local F5 play does not save" from [milestone-7](milestone-7.md#limits).
- **Tests.** About a dozen files reference the mode (`milestone2_net`, `milestone3_visibility`, `milestone4_inventory`, `milestone7_persist`, `milestone8_death`, `milestone9_hog`, `building_phase1`, `building_phase4`, `survival_map_smoke`, `building_perf`, and two more). Some use local mode as a quick harness with no socket. They move to the in-process server, and the headless run must stay about as fast as today (all 25 passed in about 140 s). If a test needs an arena with no network at all, give it an explicit test harness, not a game mode.
- **Exit.** Pressing F5 gives hogs, death, respawn, saving, and (after M11) hunger, with no extra flags. `MODE_LOCAL` no longer appears in the repo. All 25 tests still pass.

### Rest of M10

- **NEXUS HOUND SECURITY.** The armed variant of the HOUND quadruped (NEXUS SECURITY, tier 3). Fast and lightly armoured, in patrol groups of 3 to 6. This is the pressure creature the hog is not.
  - **Job.** It patrols a route and investigates noise, as the doc requires of every robot. It does not stand and wait. An intruder is anyone who interferes with NEXUS property or production, so the player is a target, not prey.
  - **Behaviour.** Hunts by sight, then by last-known position. Breaks off and returns to its patrol route when hurt badly. Groups share what they see.
  - **No spawner.** Patrol groups are placed once when the server boots, on authored routes. There is no nest, no wave, and no respawn timer. A destroyed unit stays destroyed until the next server reset, so killing a patrol is a real decision. (The hog is different: it still respawns after 60 s.)
  - **Threat level.** Medium. Dangerous in a group, weak alone.
  - **Loot.** Drops follow its construction: existing `circuit_board`, `industrial_motor`, and `mechanical_component`. No new items (scope freeze).
  - **Data, not code.** It is a `Creature` kind configured by a resource, so HOUND (unarmed, investigates only) and WASP can be added later as data without new AI code.
  - **Look.** Quadruped silhouette, angular panels, visible joints, small NEXUS marking. It reads from the isometric camera and cannot be mistaken for the hog.
- **Pathing.** Hogs walk straight and give up on obstacles. NEXUS robots cannot. Add a navigation mesh bake for the static map and use `NavigationAgent3D` from `Creature`, with a straight-line fallback near the player. Buildings are dynamic, so this is the hard part. Decision needed: rebake chunks on building change, or let creatures treat player buildings as breakable walls (see M13).
- **Noise.** Sound is client-side playback only (`SfxManager.play_at`), so the server has no noise events yet. Add a small server call, `EnemySystem.make_noise(position, radius)`, and call it from shots, crafting, and building. A shot then wakes creatures within a radius. This is the first real reason to choose the quiet option.
- **Tests.** `milestone10_nexus`: patrol group placement (and no respawn), route following, noise investigation, chase, lose-target, return to route, replication, and a 6-creature tick budget.

Exit: two players can sneak past a patrol or draw it with noise, be chased by it, and fight it from a doorway.

## M11 — Eat, drink, heal

The first thing that makes existing items matter. Nothing here adds items.

- **`use_item`.** One request RPC: `use_item(slot)`. The server checks the player is alive and holds the item, applies the effect, consumes one, and replies. A use takes time (0.5 to 3 s) and is cancelled by moving, being hit, or switching slot. Use `ItemDefinition.use_*` fields, not a code table, so effects are data.
- **Hunger and thirst** in `VitalsSystem`. Slow drain (a full bar lasts 25 to 30 minutes of play). At zero, health drains slowly, never faster than a cooked meal can recover. A warning at 25%.
- **Food values.** Raw food is poor and risky (small chance of a short sickness). Cooked food is good. `meat_stew` is the best. This finally gives the campfire and the hog's raw meat a purpose.
- **Healing.** Medical supplies heal over time. A bandage-like use stops bleeding (see M12). Passive regeneration only when fed and not recently hurt.
- **HUD.** Health, hunger, and thirst bars in `VitalsHud` (the file already says later vitals get their bars there). Save hunger and thirst in the player profile.
- **Water.** Water bottles and the well already exist (`fill_rules`). Drinking from a filled bottle is the only new action. No purification system yet.
- **Tests.** `milestone11_vitals`: use and cancel, double-use race, hunger drain and starvation damage, healing, saving and loading the new values, death by starvation going through the same `VitalsSystem` path as a shot.

Exit: a player can be in trouble, fix it with something they made, and know why they were in trouble.

## M12 — Stamina and combat feel

Combat is a pistol and a hog today. Make it feel like a fight.

- **Stamina.** Sprinting, melee swings, and harvesting drain it. Server-owned, replicated with the player snapshot so the HUD is accurate. This is what makes "you cannot outrun it (sprint is 3 m/s)" a decision.
- **Melee.** Harvest tools do not hit creatures today. Let axes, pickaxes, and the crowbar damage creatures through the same `receive_damage` entry, with a reach and a swing time. Gives a no-ammo answer to NEXUS HOUND SECURITY.
- **Knockback and hit reaction.** The player gets shoved by a gore. Creatures flinch. The server applies it, the client presents it.
- **Ammo as a decision.** `ammo_9mm` is already spent per shot. Add a magazine and a reload time so firing is a rhythm. Decide in this milestone whether ammo is craftable early (the ammo bench exists) or loot-only.
- **Bleeding.** Some creature hits cause a bleed that stops with the M11 bandage use. Cheap, readable, creates a reason to carry medical supplies.
- **Weapon variety: done, tune it.** Twelve more guns (two or more per ammunition type, including shotguns) and a sword are in. Stats live in each item's `weapon_*` fields, read through `WeaponSpec`, and `tools/gen_weapons.py` writes them. What is left here is balance, a magazine and reload, and a per-gun shot sound.
- **Hit feedback.** Damage numbers are off. Use a short hit marker, a creature flash, and sound.
- **Tests.** `milestone12_combat`: stamina drain and recovery, melee on creature, knockback respects walls, reload, bleed and its cure.

## M13 — Shelter matters

A base is only a decision if something threatens it.

- **Creatures vs buildings.** NEXUS HOUND SECURITY units breach the weakest reachable piece to get at an intruder. Damage goes through the existing `damage_catalog` so wood, brick, and concrete mean something. The structural solver already collapses the rest, so a pack that breaks one load-bearing wall can bring a roof down. Test that this reads as fair, not random.
- **Night.** A day and night cycle (server clock, replicated as one number). Patrols do not multiply at night; darkness changes what players and robots can see. Visibility and the cutaway shader dim. This one clock is also what weather and temperature later hang on.
- **Safe-ish zones.** A lit, enclosed room (walls, a door, a fire) counts as shelter: creatures lose interest after a while. Define "enclosed" with the building graph, which already knows rooms and openings.
- **Costs.** Building cost is charged when the held item is `building_plan`, and `require_resources` is off by default in the config ([BUILDING_SYSTEM_STATUS](../BUILDING_SYSTEM_STATUS.md) says the wallet is not connected, which is out of date). Decide the survival map's rule and set it. A shelter that costs nothing is not a decision.
- **Dismantle and collapse.** Dismantling a wall does not collapse the floor above. Decide: keep it (a player-safe tool), or make dismantle go through the same path as damage.
- **Tests.** `milestone13_siege`: a creature damages a wall, a support breaks, the structure collapses, shelter rule, night visibility.

## M14 — Slice polish and the gate

No new mechanics.

- **Onboarding.** A short, skippable objective line at the top of the HUD: gather wood, craft a hatchet, cook, build a room. Reads game state, so it never lies. This is what G1 measures.
- **Art pass on what the player stares at.** Hog, NEXUS HOUND SECURITY, player, pistol, and 10 most-used items through `tools/ai_asset_pipeline`. The hog is boxes today.
- **Sound.** Footsteps (per ground type), shots, bullet impacts and hog calls have placeholder files. Still empty: hurt, craft_start, craft_done. Not yet slots: eat, footsteps on building floors, ambient wind. Ranges are already per-slot.
- **Pickup cleanup.** Dropped items never despawn. Add a timer for ground drops (not for placed containers) so a long server does not fill up.
- **Refactor.** Move player movement, interaction, and weapon handling out of `player_controller.gd`. Move death, respawn, and profile code out of `game_net.gd`. Behaviour must not change; the 25 tests are the guard.
- **Soak and export.** A scripted 20-minute run with 2 clients, one death, one reconnect. A Windows export of server and client from `export_presets.cfg`.
- **Tuning.** Spawn counts, hunger rates, damage, and respawn delay are constants today. Put them in one `resources/tuning.tres` so playtest changes do not touch code.
- **Gate review.** Walk G1 to G8. Anything that fails goes back into M10 to M13 as a fix, not into a new milestone.

---

# Part 2 — Full game

Versions are by player-facing capability, not dates. Each version is a release you could hand to a friend.

## v0.2 Alpha — a world with a rhythm

The slice is a sandbox yard. Alpha makes it a place with time, weather, and a reason to move.

### A1. World clock, weather, temperature, clothing
- Day and night, then rain and cold on top of the M13 clock.
- **Clothing**, cut from the slice and moved here. It needs temperature to mean anything. Cloth, rubber, and armor from the existing catalog feed it.
- Body temperature and wetness. A campfire, a lit room, and a jacket are three answers to one problem.

### A2. Bigger map and streaming
- The survival map is 80 by 80 m. Alpha needs about 400 by 400 m. That needs streaming of resource nodes, creatures, and buildings in chunks, and interest management for replication.
- Points of interest with authored layouts: a gas station, a bunker, a radio tower, a farm, a rail yard.
- Loot tables per point of interest instead of the fixed layout in `loot_layout.gd` (which a modified client can read today).

### A3. Threat ladder
The enemies are NEXUS robots, taken from the doc's roster (see [nexus-industries.md](nexus-industries.md)), not invented monsters. Each keeps its job and loot from the doc.
- **EXCAVATOR** (tier 5, mining prototype). Slow, huge, destroys obstacles and structures as part of its work. Counter: kite, stagger with a blast, or use height.
- **SENTINEL** (tier 3). Patrols restricted areas, warns, then shoots. Ranged, hits through windows. This is the use of glass windows taking full bullet damage.
- **WASP** (tier 2). Small inspection drone. It detects movement and marks lone players for nearby security units. Low durability. Makes the shelter rule real, because a lit, enclosed room hides you from it.
- **OVERSEER** (tier 5). Coordinates nearby units at a point of interest and guards a keycard or a blueprint. The doc says it is not a conventional boss, so it is a hard target that makes the others smarter, not a health bar.
- **Facility security state.** Each NEXUS point of interest tracks its own state, 0 (normal) to 4 (lockdown), as the doc defines. Escalation makes existing robots react (HOUND investigates, SENTINEL warns, doors close) and a facility can calm down again.
- Pathing upgrades: group tactics, flanking, doors.

### A4. Progression
- The tech tree exists. Tie it to discovery: some tiers need a blueprint found in a point of interest, not only materials.
- **Skills** that grow by doing (harvesting, cooking, building, shooting), kept small. Each skill gets 3 to 5 perks, not 50.
- **Durability and repair** for tools and weapons. The repair tool exists for buildings.
- A simple **journal**: the 160-item wiki in `resources/wiki/catalog.json` shown in game, with recipes as you discover them.

### A5. Systems hardening
- **Client prediction** for movement. Today the local player lags by the round trip plus about 80 ms ([milestone-2](milestone-2.md#known-limitations)).
- Replace the full-circle line-of-sight check, which is O(n²) per physics frame, with a spatial grid.
- Real accounts or at least signed tokens. Today the token is a cookie and anyone who sends it owns that profile.

## v0.3 Beta — things to do and people to do them with

Creative features, chosen to reuse what the game already has.

| Idea | Why it fits |
| --- | --- |
| **Siege night.** Every fifth night a large wave heads for the player base and goes for the weakest load-bearing wall. | The structural solver, damage profiles, and blast gun already exist. This makes building a real discipline and gives the solver a purpose. |
| **Repairable car.** The map has broken cars and salvage parts (engine block, radiator, headlight, tires). Gather them, build a working car. | Salvage items exist, the pad and wreck art exist. Gives the scavenging a visible payoff and the map a travel speed. |
| **Power.** Copper, wiring, batteries, and electronics exist. Add generators, lights, and wire. Lights make safe-ish zones stronger and nights bearable. | Items already in the catalog; only the system is missing. |
| **Farming and husbandry.** Corn, potato, and mushroom exist. Plant them. Tame or pen hogs for meat and leather. | The hog is already a server creature with a state machine. A tame state is one more state. |
| **Traps.** Spike, noise-maker, and blast traps. Hogs walk straight and NEXUS patrols follow routes and last-known positions, so both are predictable, so traps pay off. | Uses `receive_damage`, noise events, and the blast system. |
| **Turrets.** A pistol on a deployable that takes ammo from a nearby crate. | Deployable system, crate system, and `HitscanWeapon` exist. |
| **Noise and smell.** Cooking and shooting attract creatures. A lit window shows from outside. | The noise call comes from M10. LoS already knows what can see what. |
| **Corpse run.** A death leaves a marker on the map and a tombstone bag instead of a scatter of drops. Items you recover appear in your journal. | Replaces the scattered drops decided in M8. A tidy bag is already listed there as a later step. |
| **Radio events.** Timed airdrops and distress calls that pull players into the same danger zone. | Events are timers plus spawns; the server tick already has both. |
| **Trader.** A fixed NPC that swaps surplus for things not found on the map. | Gives junk items a use and soaks excess scrap. |
| **Bunker with keycard.** A locked point of interest with the best loot, opened by a card guarded by the OVERSEER. | The door system already opens and closes; add a key check. |
| **Fishing.** Raw fish and cooked fish are already in the cooking rules. | Item pair exists. |
| **Lock and codes** for doors, with a claim flag on a base. | Needed before raiding means anything. |

Social, in the same version:
- **Teams and claims.** A flag deployable that sets who may build, open, and loot inside a radius.
- **Raid rules.** Server option: always, nights only, or off.
- **Player count up to 16.** Only after A5 prediction and the spatial LoS replacement.
- **Chat and pings.**
- **Admin tools:** kick, ban, give, teleport, wipe, and a status page.

## v1.0 — ship

- **Art and animation.** Replace remaining box art, player locomotion polish, held items. The asset pipeline already runs from the launcher.
- **Audio.** Music, ambience, mixing, and a pass on every sound slot.
- **UI.** Main menu (Play, Host, Join), server browser or direct connect, settings, rebindable keys (QWERTZ and QWERTY both work today because bindings use physical keys; keep that), accessibility options, localisation hooks (UI text is hard-coded in the scripts today).
- **Performance.** Profile on a low-end GPU. Pooling for creatures, debris, and shots. A frame-time budget per system in the soak test.
- **Packaging.** One-click dedicated server build, a client build, an update path, and a world-wipe tool.
- **Safety.** Rate limits on every RPC (building already has them), logging of rejected requests, a basic cheat report.
- **Docs.** A player guide, a server-owner guide, and a modding note for item and recipe data.
- **Release checklist.** All tests pass, soak passes, fresh-install playthrough passes.

---

# Backlog — bugs, debt, and doc drift

Severity: **H** blocks the slice, **M** should be fixed before 1.0, **L** can wait. Source is where I found it: *code* means I looked at the file, *doc* means a milestone doc says so and I did not re-check it.

## Blocks the slice

| ID | Problem | Source | Milestone |
| --- | --- | --- | --- |
| B-01 | Food and medical items cannot be used. There is no `use_item`. Cooked food is worthless. | code | M11 |
| B-02 | Nothing heals. Health only goes down except at respawn. | doc ([M8](milestone-8.md#decisions)) | M11 |
| B-03 | No hunger, thirst, or stamina. `vitals_system.gd` and `vitals_hud.gd` both reserve space and say "later". | code | M11, M12 |
| B-04 | Only one creature, and it ignores obstacles and cannot be pathed around. | doc ([M9](milestone-9.md#limits)) | M10 |
| B-05 | Harvest and melee tools do not hit creatures. | doc ([M9](milestone-9.md#limits)) | M12 |
| B-06 | A gore only damages the player. No knockback. | doc ([M9](milestone-9.md#limits)) | M12 |
| B-07 | Dropped items never despawn. A long server fills up. | code (no despawn path found in `scripts/items`) | M14 |
| B-08 | Footstep sound slot has no files. The game is silent for it. | code | M14 |
| B-09 | Hog art is boxes. | doc ([M9](milestone-9.md#how-it-is-built)) | M14 |
| B-10 | Local (offline) play has no `GameNet`, so no creatures, no death loop, no hunger. Two code paths drift apart. **Decided:** remove offline mode; single-player is an in-process server. | doc ([M9](milestone-9.md#limits)) | M10, step 0 |
| B-11 | The death loop is not covered by an automated two-process test. | doc ([M8](milestone-8.md#limits)) | M14 (soak) |

## Gameplay and balance

| ID | Problem | Source |
| --- | --- | --- |
| B-12 | Hogs are not hurt by other hogs and do not attack buildings. | doc |
| B-13 | A downed body keeps its collider, so shots that hit it stop there. | doc |
| B-14 | Death delay, drop ring, and flash strengths are constants, not tuned. | doc |
| B-15 | A stuck hog gives up its wander goal. Should path or be reseated. | doc |
| B-16 | Item weight is stored and shown but does not limit carrying. Decide whether it should. | doc ([M4](milestone-4.md#items)) |
| B-17 | Leaving while dead and coming back is a fresh spawn with a new loadout. This can be abused for a free loadout on the debug map; survival loadout is empty so it only matters there. | doc |
| B-18 | Dismantling a wall does not collapse the floor above. Decide, then document. | doc |

## Building

| ID | Problem | Source |
| --- | --- | --- |
| B-19 | Posts show as darker strips every metre along walls. Intentional; a continuous wall look needs the same material for post and wall. | doc |
| B-20 | Diagonal boundaries are reserved in the key format but not implemented. | doc |
| B-21 | Stairs are 45° and the player's `floor_max_angle` is 50°. Verified with a capsule, not the real player. | doc |
| B-22 | A chunk the player has not received has no collision on that client, so it cannot block line of sight until it arrives. | doc |
| B-23 | F3 building debug view costs a few milliseconds when on. | doc |

## Networking and security

| ID | Problem | Source |
| --- | --- | --- |
| B-24 | No client prediction. Local movement lags by the round trip plus about 80 ms. | doc |
| B-25 | Line of sight is a full circle, checked every physics frame for each pair. Fine for 4 players, wrong for 100. | doc |
| B-26 | The token is a cookie. Anyone who sends it owns that profile. | doc |
| B-27 | World pickup positions go to every client, and fixed test loot is readable in `loot_layout.gd`. | doc |
| B-28 | No lag compensation for shots. | doc |
| B-29 | 100 players is the ENet cap, not a measured number. | doc |

## Code health

| ID | Problem | Source |
| --- | --- | --- |
| B-30 | `game_net.gd` is 2,594 lines and `player_controller.gd` is 1,889. | code |
| B-31 | Constants for spawns, rates, and damage are spread across files. One tuning resource should hold them. | code |
| B-32 | `.godot` class cache needs `-Refresh` after adding a `class_name`. Easy to forget. | doc |
| B-33 | Test runner has no CI. It is a script you run by hand. | code |

## Doc drift (fix with the next docs pass)

| ID | Problem |
| --- | --- |
| D-01 | Milestones 5 and 6 have no docs. Crafting, deployables, tech tree, smelting, fill stations, biomes, harvest, the survival map, the asset pipeline, and the sound system were built without them. Write one retroactive page, or merge them into a "systems overview". |
| D-02 | [milestone-4](milestone-4.md) says "ammunition is not consumed", "there is no crafting", and lists six items. The code spends `ammo_9mm`, crafting exists, and the catalog has about 160 items. Add a status note at the top. |
| D-03 | [BUILDING_SYSTEM_STATUS](../BUILDING_SYSTEM_STATUS.md): the approval line is fixed (approved 2026-11-17). Still out of date: it says costs are not charged and the wallet is not connected, that `milestone4_inventory.gd` does not parse, and that `building_phase1` has one failure. |
| D-04 | ~~The README opening describes Milestones 1, 2, and 7 only.~~ Done: it now links to this roadmap. The rest of the README intro is still short. |
| D-05 | ~~[milestone-8](milestone-8.md) lists "clothing" in the slice order.~~ Done: a note there points to this roadmap. |
| D-06 | `milestone-1.md` describes a hand-placed showcase arena. The survival map is the main game now. Add a pointer. |

---

## How to use this file

- Pick the next milestone, write its `docs/milestone-N.md` first (scope, checks, limits), then the test, then the code.
- A bug found while working goes in the backlog with an ID, not into the current milestone.
- When a gate criterion fails, fix it in the milestone that owns the cause.
- Revisit Part 2 after the gate. Do not build any of it before then; the point of the freeze is to finish the loop first.
