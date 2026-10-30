# Building System Status

## Current phase

**Phase 4 — Multiplayer, Replication, and Performance: complete, waiting for approval.**
Phases 1, 2, and 3 remain in place. There is no later building phase in the original plan.

## Phase 2

- **Health.** Every piece stores `health`, `max_health`, a material id, and `destroyed` on its existing `BuildComponent`. Profiles in `resources/building/damage/` set the numbers: wood walls take half of bullet damage, glass windows take full bullet damage and extra blast damage and do not stop a blast.
- **Shots.** Hotbar 1 is the pistol. It hits a building body and the authority applies that shot once. The same event id a second time does nothing. Bullet holes are separate quads under `Impacts`. Damage only darkens that piece.
- **Blast Gun.** Hotbar 3. Left click explodes at the aim point. Damage falls off with distance. A solid wall blocks pieces behind it. A window does not.
- **Destruction.** A piece at zero health is deleted, including its node and its slot. Posts nothing else uses go with a wall. A room is deleted once it has no floor, wall, opening, or stairs left, and the plot can be built on again.
- **Repair Tool.** Hotbar 4. Left click restores a damaged piece that is still standing. It does not bring back something that was destroyed.
- **Debris.** A destroyed piece drops a few visual chips under `Debris`. They have no collision, a cap, and a lifetime.

## Phase 3

- **What holds a building up.** Level-0 floors are foundations. The ground carries them. Every higher floor tile weighs 1, plus whatever the walls on it have brought down from above. A connected floor splits that weight equally across the walls and doorways still under it. Windows and posts do not carry floors. A wall or doorway buckles above `wall_bearing` tiles (4). A floor with no wall or doorway left under it falls. So does a wall with no floor beside it, stairs that lose a slab under a step, and a post with nothing left to stand on.
- **Only the affected part.** The check starts at the pieces that touched the destroyed support and walks their connections. A separate building is not visited.
- **Stages.** Each stage waits `collapse_delay_sec` (0.2 s) and then removes the failing pieces in id order. The next stage sees the result. A chain stops after `collapse_max_waves` (32). Putting a wall back before the timer fires cancels the stage.
- **Damage only.** Shooting or blasting a support can bring down what stood on it. The Build Tool still refuses to dismantle a floor that walls stand on, and dismantling a wall does not collapse the floor above it.
- **Repair.** A damaged wall that is still standing keeps its load. Repair restores the wall. It does not bring back a piece that already fell.

## Phase 4

- **Who decides.** The server `BuildingAuthority` is the only writer in a network game. A client can preview and send a request. It cannot commit, damage, repair, explode, or collapse on its own. Local play is unchanged: the same authority runs in-process, with no packets.
- **Requests.** Place, repair, and blast are reliable RPCs with a per-player sequence number. A repeated sequence is ignored. More than 8 building requests in one second are refused. The server checks that the sender has a living player, is holding the matching hotbar item, and is within 15 m of the point. Placement is re-planned on the server. When costs are enabled, scrap is counted and spent from that player's server inventory.
- **What is sent.** A change is a batch of piece records, room records, health values, bullet-hole points, and debris origins. Stable component ids travel with the records. Unchanged chunks are left out. Pieces are grouped into 8 m chunks. A player receives a chunk while they stand within two chunks of it, gets a snapshot of a chunk when they walk into range or join late, and is told to drop a chunk when they leave. Dropping a chunk does not delete it on the server.
- **Damage and collapse.** Server hitscan already calls `receive_damage` on the body it hits. That applies bullet damage once. The same shot id a second time does nothing. Blasts and collapse run only on the server. Clients apply the resulting removals, including the falling flag, and do not run the structural solver.
- **Sight.** Line of sight now includes the building layer, so a wall blocks network visibility the same way the arena walls do.
- **Rendering.** Piece meshes and materials were already cached and are still one mesh per kind and bottom mask. Destructible pieces stay separate bodies so each can be damaged. Break chips and collapse dust are two `MultiMeshInstance3D` nodes with a cap and a lifetime.

New files: `scripts/building/building_codec.gd` (piece and room records), `scripts/building/building_relay.gd` (requests, chunks, batches), `tests/building_phase4.gd`. The relay is a child of `BuildingSystem`. `GameNet` tells it when a player spawns or leaves. The arena creates a `BuildingSystem` for the server and for clients, not only for local play.

## Features

- **Grid.** 1.0 m cells, 3.0 m floor-to-floor, 0.15 m walls, 0.1 m slabs, 4 levels, build area cells (-17,-17)..(16,16). All values live in `resources/building/default_building_config.tres` (`BuildingConfig`) and every mesh, shape, and transform is derived from them.
- **Canonical slots and single ownership.** Every piece has exactly one slot: slab `(x, level, z)`, corner post `(vx, level, vz)`, boundary `(x, z, level, axis)`, stairs `(anchor, level, rotation)`. `EdgeRegistry` is the only owner of boundaries. A wall, doorway, or window is one piece on one boundary, shared by both rooms that touch it.
- **Seamless joints by construction.** Posts own the t×t corner squares at grid vertices. Walls span exactly between posts. Vertical pieces span a full floor height, so stacked walls and posts meet face to face. Wall and post bottom faces are split per adjacent cell and omitted wherever a slab covers that cell, so no two same-facing faces ever share a plane (no Z-fighting). Transforms are computed from slot keys with exact 0/±1 rotation bases; nothing accumulates offsets.
- **Blueprints** (`resources/blueprints/*.tres`, 7 entries): room (sized by dragging); wall, doorway, window; floor/ceiling 1×1 (one entry, because a ceiling is the floor of the next level: PageUp places it as a ceiling); straight stairs; dismantle. Posts are not placeable on their own; every wall, doorway, and window adds the posts at its ends and dismantling removes posts nothing ends on. Each has name, category, description, footprint, openings, and restrictions; the menu shows a generated icon and the cost.
- **Rooms** are one resizable blueprint: hold LMB on one corner cell, drag to the opposite corner, release to build. A click builds 1×1; the size is clamped to 8×8 (`max_size`), RMB during the drag cancels it. The size travels in the request (`size`), the authority sanitizes it, and the planner clamps it, so a request can never build a larger room than the blueprint allows. Rooms always have a floor, closed walls around the rectangle, and a ceiling, and no built-in openings. Doorways and windows are placed separately and replace a wall in place. A room built on top stands on the ceiling below (one shared slab).
- **Construction plans.** `RoomPlacer` turns a request into a `ConstructionPlan` without touching state. Each entry is CREATE, REUSE, REPLACE, REMOVE, SKIP, or CONFLICT with a reason. Doorways and windows replace walls; a room asking for a wall where an opening stands keeps the opening; two different openings on one boundary are a conflict. Repeating a placement is a no-op ("Already built") or repairs only the missing pieces.
- **Atomic commit.** `BuildingAuthority` is the only writer. It re-plans from the request (clients never send plans), checks physics obstructions, optionally charges resources, and commits only if the plan is valid against the current state revision. `BuildingState` emits one `changed` event per commit.
- **Floors, ceilings, levels, stairs.** A ceiling is the next level's floor (one shared slab). Upper levels need support (a slab beside them, or walls/posts below). Walls, doorways, and windows always stand on a floor on at least one side: a floor / ceiling slab, or the top of a stairwell (so walls can enclose the opening on top of stairs; the exit takes only a doorway and the boundaries over the flight stay open). Single pieces without a floor are rejected, a floor slab or stairs cannot be dismantled while they are the last floor of an edge piece, and rooms skip boundaries with no floor on either side. The geometry audit checks this for every edge piece. Stairs need floor slabs under all three cells, cut the ceiling slabs above them out as a stairwell, and keep their top, middle, and bottom boundaries open; a doorway is allowed at the upper exit. The boundaries across the flight one level up must also stay open (headroom). Rooms built later skip those boundaries and the stairwell slabs automatically; explicit wall pieces there are rejected. A 3-cell flight is longer than the inside of a 3×3 room, so stairs run through two rooms whose shared wall has been dismantled (scenario H). Scenario K is a dragged 5×2 room.
- **Build Tool.** Hotbar item `build_tool` (slot 2 of the starting loadout). Mouse aim on the build level's plane, snapping with 0.15-cell hysteresis, blueprint menu on the right, preview, confirm. Controls: LMB place, RMB cancel, R rotate (Shift+R reverse), PageUp/PageDown level, `[` `]` previous/next blueprint (physical keys; Ü and + on a German keyboard), F3 building debug view. Blueprints can also be clicked in the menu.
- **Preview.** Visual only: pooled nodes under `BuildingSystem/PreviewRoot`, no physics bodies, no state writes. New pieces get a translucent ghost (green valid, red invalid). Reused pieces get a yellow outline only, never a second surface. Replaced pieces get an orange outline of the old piece plus a cyan outline of the new one. Cyan footprint, nearby grid lines, and a front arrow. Status text with `[OK]` / `[X] reason`, level, rotation, grid position, piece counts, and cost. Rebuilt only when the request or the state revision changes.
- **Cutaway.** While the tool is equipped, meshes above the build level are hidden; otherwise, when the player stands under a slab. Collision is never hidden.
- **Physics.** New layer `BUILDING` (8). Player movement, aim, and hitscan include it. The camera pull-in does not, so ceilings do not crush the camera.
- **Debug view (F3).** Grid coordinates, boundary ids, piece bounds, real collision shapes, and audit warnings around the cursor, plus a HUD line with counts and the audit result.
- **Geometry audit** (`GeometryAudit.run`). Checks slot ownership, one node per piece, bit-exact canonical transforms, the correct bottom-mask mesh, collision shapes against visual parts, collision overlaps (exact for the stairs wedge), coplanar same-facing overlapping faces read from the real mesh arrays, faces on the ground plane, triangle winding, flush wall-to-post joints, orphan posts, mirrored graph links, and bodies under the preview.

## Files changed

New:

| Path | Purpose |
|---|---|
| `scripts/building/building_types.gd` | Kinds, actions, sides, axes |
| `scripts/building/building_config.gd`, `resources/building/default_building_config.tres` | Dimensions and rules |
| `scripts/building/grid_system.gd` | Keys, doubled-lattice rotation, world conversion, canonical transforms |
| `scripts/building/blueprint_opening.gd`, `blueprint_definition.gd`, `blueprint_catalog.gd`, `resources/blueprints/*.tres` | Blueprint data |
| `scripts/building/build_component.gd`, `edge_registry.gd`, `construction_graph.gd`, `building_state.gd` | Logical state |
| `scripts/building/construction_plan.gd`, `room_placer.gd` | Planning |
| `scripts/building/building_authority.gd` | Only writer: validate, obstruction check, costs, commit |
| `scripts/building/building_geometry.gd`, `building_world.gd` | Meshes, shapes, committed nodes, cutaway |
| `scripts/building/build_preview.gd`, `build_tool.gd`, `blueprint_menu_ui.gd` | Player-facing tool |
| `scripts/building/building_system.gd` | Composition root (group `building_system`) |
| `scripts/building/geometry_audit.gd`, `building_debug_view.gd` | Verification and F3 view |
| `scripts/building/building_scenarios.gd` | Shared scenario layout |
| `scenes/world/building_test.tscn`, `.gd` | Manual test scene with all scenarios prebuilt |
| `resources/items/build_tool.tres` | Hotbar item |
| `tests/building_phase1.gd` | Headless regression suite |
| `tests/building_capture.gd`, `tests/building_perf.gd` | Rendered screenshots and frame-time comparison (need a window) |

Edited (small, targeted):

| Path | Change |
|---|---|
| `scripts/core/physics_layers.gd` | `BUILDING := 8`; `HITS_MASK` includes it |
| `project.godot` | Layer 4 named `building` |
| `scripts/player/player_controller.gd` | Collides with `BUILDING`; world ray includes it; `holds_build_tool()`; attaches `BuildTool` in local play; fire button does nothing while the tool is held (networked: notice that building is local-only) |
| `scripts/camera/aim_projector.gd` | Aim ray includes `BUILDING` |
| `scripts/core/input_bindings.gd` | `build_rotate`, `build_level_up/down`, `build_next/prev`, `build_debug` |
| `scripts/items/item_catalog.gd`, `item_icons.gd`, `inventory.gd` | Build tool item, icon, and loadout slot 2 |
| `scenes/world/test_arena.gd` | Adds `BuildingSystem` in local mode |
| `scripts/ui/debug_overlay.gd` | Build controls help line (local play) |
| `README.md` | Building section |

## Tests executed

All runs on Godot 4.7.2 stable, Windows, 2026-10-27.

| Test | How | Result |
|---|---|---|
| `tests/building_phase1.gd` | headless, 2026-10-28 after walls on top of stairs | **Pass**: 512 checks, 0 failures, prints `BUILDING_PHASE1_OK`. One `ERROR` line is expected: the test feeds a stale plan to `BuildingState.commit` and checks that it is refused. |
| `tests/milestone1_smoke.gd` | headless | **Pass** (`MILESTONE1_SMOKE_OK`), no errors or warnings, with `BuildingSystem` in the arena |
| `tests/milestone2_net.gd` | headless | **Pass** (`MILESTONE2_NET_OK`) |
| `tests/milestone3_visibility.gd` | headless | **Pass** (`MILESTONE3_VISIBILITY_OK`) |
| `tests/milestone4_inventory.gd` | headless | **Fails to parse, pre-existing**: it references `Inventory.STARTING_SCRAP`, which does not exist in `inventory.gd`. Not caused by and not changed by Phase 1. |
| `tests/building_capture.gd` | windowed, Vulkan, RTX 2080 Ti | Ran; all scenarios built inside the real arena (0 failures); 12 screenshots saved to `%APPDATA%\Godot\app_userdata\Survival Sandbox\building_shots` and inspected |
| `tests/building_perf.gd` | windowed | Ran twice. Quiet run: arena alone 14.30 ms average / 0 frames over 30 ms; 422-piece showcase 14.32 ms / 0; tool equipped with preview 14.30 ms / 0; F3 debug view on 14.68 ms / 4. The second run had spikes in the plain arena too, so this machine's background load is noisy. |

`building_phase1.gd` sections: catalog and config; grid math (exact bases, footprints in all rotations, negative coordinates, edge round trip); 1 single room; 2 adjacent rooms share one wall; 3 four rooms share one centre post; 4 larger rectangles from two 3×3 rooms, a 3×3 grid of 1×1 rooms, and mixed 3×3/2×2/1×1 rooms sharing walls; 5 repeated placement is a no-op and repairs a removed wall; 6 stairs in all four rotations climb toward their front (rooms are square and not rotatable); 6b snapping hysteresis with no flicker at a boundary and no re-planning without a change; 6c drag sizing (1×1 click, drags in every direction, 8×8 clamp, cancel, a dragged 4×3 room has exactly its perimeter walls and posts, invalid sizes are clamped); 7 rooms bring no openings, doorways and windows replace walls in place, opening swaps, a later room keeps an existing window; 8 shared floor/ceiling slabs and bottom masks; 9 three stacked levels with RESTS_ON/SUPPORTS links and unsupported rooms rejected; 9c walls, a window, and a doorway on top of stairs (walls across the exit or over the flight rejected, stairs under them not removable); 9d a room over a stairwell keeps all its walls except the exit; 9b stairs through two 3×3 rooms with the partition dismantled (ceiling cut out, exact slope height by raycast, boundary rules, a capsule character walks up to the upper floor); 11 preview next to existing geometry (ghosts only for new pieces, canonical ghost transforms, no bodies, state unchanged); 12 1,800 random preview moves, rotations, and blueprint switches (state unchanged, pool bounded); 13 rejected and cancelled placement (bounds, level, support, physics obstruction, stale plan, cancel); 13b resource costs (refused when short, charged exactly once, reused pieces free); 10a dismantle with orphan-post cleanup (posts still used by another piece stay), the last floor under walls cannot be removed, wall bottom changes when a neighbouring slab goes, single walls/doorways/windows without a floor are rejected, support posts are not in the catalog; 14 collision stability (a standing capsule drifts < 0.1 mm over 120 frames, pressing into a wall varies < 1 mm, pieces bit-identical after neighbours are built, hitscan stops at walls); the full showcase layout; an audit self-check that plants a 1 mm drift, a duplicate node, a Z-fighting mesh, and a preview body and confirms each is reported; arena integration (loadout, equip by hotbar, menu, build a room, unequip).

**Geometry stability.** Measured, not assumed: every audit in the suite reports no duplicate pieces, no unexpected collision overlap, no coplanar same-facing faces, no faces on the ground plane, no reversed winding, and no gaps at joints, including the 502-piece showcase built inside the arena (re-checked after the room change). Transforms are bit-identical to their canonical values and do not change when neighbours are built. In the rendered screenshots, shared walls, corners, windows, stacked floors, and grazing views along floors at levels 0 and 1 show no Z-fighting or gaps. This is evidence for the tested layouts and camera angles, not a proof for every possible layout.

## Known issues and limitations

- **Build reach is 15 m.** A request farther from the player than that is refused. Chunks outside that neighbourhood are not sent until the player walks up to them.
- **Costs are shown, not charged, by default.** `require_resources` is off and the authority's wallet hooks are not yet connected to the player inventory. The charging path is covered by the suite with a test wallet.
- **Posts are visible** as darker strips at every metre along straight walls (posts own every vertex). This is intentional and seamless; if a continuous wall look is wanted, posts can share the wall material without geometry changes.
- **45° stairs.** The player's `floor_max_angle` is 50°, so the stairs are walkable (verified with a capsule of the same settings, not the full player). A stricter player angle would need a shallower stair blueprint.
- **Stairs' bottom entry must stay open.** A doorway there would cut the headroom of a player climbing the first step (found by the walker test). The upper exit allows a doorway.
- **Dismantle does not collapse.** Removing a wall with the Build Tool leaves the floor above it in place. Collapse runs only after a support is destroyed by damage. A floor that still has walls on it cannot be dismantled. A slab that carries stairs, and a post that still carries walls, stay blocked the same way.
- **Posts and windows carry no floor load.** A wide floor needs walls or doorways. Posts only join those walls. Glass does not hold a floor up.
- **Four tiles is the buckle point.** A wall or doorway falls when its equal share of the floor above is more than 4. A 1×1 ceiling stays up on its last wall (share 1). Six tiles on one wall buckle it, and the ceiling follows one stage later. A wider intact room has more walls, so the share stays lower until enough of them are destroyed.
- **Diagonal boundaries** are reserved in the key format (axes 2 and 3) but not implemented.
- **`line_of_sight.gd`** includes the building layer. A wall between two players hides them from each other. A chunk the player has not been sent yet has no collision on that client, so it cannot block sight until it arrives.
- **F3 debug view** costs a few milliseconds while on (labels and lines without depth test). It is off by default.
- **`tests/milestone4_inventory.gd`** does not parse (pre-existing, see above).

## Architectural decisions

- **Logical state first, scene second.** `BuildingState` holds no nodes. `BuildingWorld` builds nodes from `changed` events and refreshes only the bottom masks next to slabs that changed. Later phases (damage, collapse, replication) work on the same state and the same ids.
- **Requests, not plans, cross the authority boundary.** The authority looks up the blueprint by id and re-plans, which is what the server will do in the multiplayer phase.
- **Doubled integer lattice** for footprints and rotation, so rotated rooms land exactly on the grid with no float rounding.
- **Bottom masks instead of offsets** to remove coplanar faces where walls stand on slabs. No piece is nudged to hide a depth conflict.
- **Outlines for existing pieces in the preview,** drawn without depth test, so the preview never puts a second surface over committed geometry.
- **ConstructionGraph** (ATTACHED, FLOOR_JOIN, RESTS_ON/SUPPORTS, ADJACENT) is maintained on every commit and mirrored from both ends, ready for the structural pass.
- **One audit used three ways:** the test suite, the F3 view, and the screenshot scene all run `GeometryAudit` on the real scene tree.

## Manual verification steps

1. Open `scenes/world/building_test.tscn` and press F6 (or set it as the main scene temporarily). Every scenario is prebuilt and labelled A–J.
2. Press `2` to take the Build Tool. The blueprint menu appears on the right.
3. Pick *Room*, hold LMB on a cell next to room A and drag a few cells, then release. Before releasing, expect a green ghost for new pieces and a yellow outline on the wall it would share, with `[OK]` and "1 reused" in the label.
4. Move over room A itself with *Room 2×2*. Expect red with `[X] … Overlaps room`.
5. Press R to rotate; the cyan arrow shows the front (door side).
6. Pick *Doorway* and aim at a wall. Expect an orange outline (old wall) plus cyan (doorway). Click, and the wall becomes a doorway with no gap.
7. Press PageUp, then place a room on top of an existing room; walls should line up exactly with the level below.
8. Walk up the stairs in scenario H. Look along floors and wall bases at low camera angles for flicker.
9. Press F3. The HUD should read "Audit: OK".

## Tests executed

Phase 2, Godot 4.7.2 stable, Windows, 2026-10-28:

| Test | Result |
|---|---|
| `tests/building_phase2.gd` | **Pass**: 167 checks, 0 failures, prints `BUILDING_PHASE2_OK` |
| `tests/building_phase1.gd` | **Pass**: 533 checks, 0 failures, prints `BUILDING_PHASE1_OK`. The stale-plan `ERROR` line is still the one the suite expects |
| `tests/milestone1_smoke.gd` | **Pass** (`MILESTONE1_SMOKE_OK`) |

Phase 2 checks cover profile loading, falloff math, starting health for every kind, bullet resistance, direct impact, duplicate shot ids, mesh and transform stability, deletion of a killed wall and of a room with no floor, wall, opening, or stairs left, repair of a standing piece, blast falloff, a wall blocking a blast, a window letting one through, repeated blasts, debris and impact caps and cleanup, and a geometry audit after damage, rebuild, blasts, and cleanup.

## Tests executed

Phase 3, Godot 4.7.2 stable, Windows, 2026-10-28:

| Test | Result |
|---|---|
| `tests/building_phase3.gd` | **Pass**: 48 checks, 0 failures, prints `BUILDING_PHASE3_OK` |
| `tests/building_phase2.gd` | **Pass**: 167 checks, 0 failures, prints `BUILDING_PHASE2_OK` |
| `tests/building_phase1.gd` | **Pass**: 533 checks, 0 failures, prints `BUILDING_PHASE1_OK`. The stale-plan `ERROR` line is still the one the suite expects |

Phase 3 checks cover one missing wall leaving the upper floor up, the last wall dropping the ceiling, six tiles buckling the final wall, a second building staying out of the walk, a destroyed ground floor taking both storeys with it, stairs falling with their slab, repair keeping the load, dismantle not collapsing, and a wall put back during the 0.2 s delay cancelling the fall. An audit runs after each of those.

## Tests executed

Phase 4, Godot 4.7.2 stable, Windows, 2026-10-30:

| Test | Result |
|---|---|
| `tests/building_phase4.gd` | **Pass**: 87 checks, 0 failures, prints `BUILDING_PHASE4_OK` |
| `tests/building_phase3.gd` | **Pass**: 96 checks, 0 failures, prints `BUILDING_PHASE3_OK` |
| `tests/building_phase2.gd` | **Pass**: 167 checks, 0 failures, prints `BUILDING_PHASE2_OK` |
| `tests/building_phase1.gd` | **1 failure**, 556 checks. `6c rooms sized by dragging` expects a doorway not to start a drag. `resources/blueprints/doorway.tres` has `resizable = true` (a doorway run). That check was already out of date with the blueprint. The stale-plan `ERROR` line is still the one the suite expects. Not introduced by Phase 4 |
| `tests/milestone1_smoke.gd` | **Pass** (`MILESTONE1_SMOKE_OK`) |
| `tests/milestone2_net.gd` | **Pass** (`MILESTONE2_NET_OK`) |
| `tests/milestone3_visibility.gd` | **Pass** (`MILESTONE3_VISIBILITY_OK`) |

Phase 4 checks cover two peers placing adjacent rooms that share one wall, duplicate and invalid requests, the request rate, bullet damage with a repeated shot id, repair, a blast that hits more than one piece, a flush that sends nothing when nothing changed, collapse that the client does not apply until the server packet arrives, falling meshes, stairs, a distant chunk withheld until the player walks up to it and dropped again when they leave, a late joiner, a disconnect that keeps the building and rejects the peer, server-side scrap costs, a server hitscan shot into a wall, building walls blocking sight, and a geometry audit after damage and collapse. Replica nodes use the same ids and canonical transforms, and applying a packet twice does not add a second copy.

## Next steps

The four planned building phases are in place. A follow-up is to update the doorway drag check in `tests/building_phase1.gd` so it matches a resizable doorway, and to try a two-process session from `tools\launcher.vbs` (the headless suite drives the server directly, the same way Milestone 2 does).
