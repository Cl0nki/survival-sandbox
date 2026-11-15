# AI asset pipeline

Local tool for generating, reviewing, processing, and importing assets into this Godot 4.7.2 Forward+ project. The game keeps its own scripts. Approved files are copied into `assets/` only when you approve them.

## What already exists in the game

The project is Godot 4.7.2, renderer Forward+. Characters, weapons, deployables, and the world are primitive meshes with flat `StandardMaterial3D` colors. Buildings are generated in `scripts/building/building_geometry.gd` from `BuildingConfig`: 1 m cells, 3 m floors, 0.15 m walls, 2.2 m doors. North is -Z. The pipeline reads those numbers from `config/building_grid.json` and does not change the solver.

There is no style reference image yet. Put it at `assets/style_reference/style_reference.png`. Until then, every prompt still uses `config/style.json`.

## Run

```powershell
python tools\ai_asset_pipeline\run.py doctor
python tools\ai_asset_pipeline\run.py serve
python -m unittest discover -s tools\ai_asset_pipeline\tests -v
```

The dashboard binds to `127.0.0.1:8765`. Generation runs on a background thread, so the page stays usable. The Items tab lists every catalog item with the placeholder icon the game draws today. A finished picture belongs at `assets/icons/<id>.png`.

The game launcher (`tools\launcher.vbs`) has **Open dashboard** and **Stop dashboard**. Open starts this server when it is not already running, then opens the page in the browser. Closing the launcher leaves the dashboard running.

A foreground job, with no network, builds a grid wall:

```powershell
python tools\ai_asset_pipeline\run.py generate --kind building --category concrete_wall --name yard_wall
```

Pillow is the only third-party package (`requirements.txt`). HTTP calls use the Python standard library.

## Configure keys

Copy [`tools/ai_asset_pipeline/.env.example`](.env.example) to `tools/ai_asset_pipeline/.env`. The file is gitignored. The dashboard receives only `configured: true/false`. Keys are sent to the matching host and stripped from logs.

| Variable | Used for |
| --- | --- |
| `OPENAI_API_KEY` | Concept images and texture albedo via `POST https://api.openai.com/v1/images/generations` |
| `OPENAI_IMAGE_MODEL` | Default `gpt-image-2.5-flare` |
| `MESHY_API_KEY` | Image-to-3D `POST /openapi/v1/image-to-3d`, text-to-3D `POST /openapi/v2/text-to-3d`, rigging `POST /openapi/v1/rigging` on `https://api.meshy.ai` |
| `TRIPO_API_KEY` | Image-to-3D `POST https://api.tripo3d.ai/v2/openapi/task` with `type: image_to_model` |
| `BLENDER_BIN` | Background processing. Optional. |
| `GODOT_BIN` | Detected from the WinGet Godot 4.7 install when present. The pipeline does not need it to write `.tscn` files. |

Docs used for the adapters:

- [OpenAI image generation](https://developers.openai.com/api/docs/guides/image-generation)
- [Meshy image to 3D](https://docs.meshy.ai/api/image-to-3d)
- [Meshy text to 3D](https://docs.meshy.ai/api/text-to-3d)
- [Meshy rigging](https://docs.meshy.ai/api/rigging)
- [Tripo generation](https://platform.tripo3d.ai/docs/generation)
- [Tripo upload](https://platform.tripo3d.ai/docs/upload)

Character jobs use Meshy humanoid rigging when `MESHY_API_KEY` is set. Otherwise the asset stays unrigged and the metadata lists the Blender steps. Image-to-3D is not treated as an animation-ready character. Meshy walk/run clips and `/openapi/v1/animations` are **opt-in** (`auto_animate`, default off); locomotion uses the Quaternius Shared library. Tripo `animate_rig` remains available on the provider adapter for non-humanoid enemies.

Missing keys fail the job. The pipeline does not invent files and label them as provider output.

## What runs without a key

- Procedural tileable PBR textures (albedo, normal, roughness, AO, metallic, height). These are wrapped noise in the style palette, labeled `procedural` in metadata.
- Modular building meshes from the live grid: walls, floors, posts, door headers, door leaves, windows, stairs, fences, gates, roofs, barricades, containers, a watchtower, and simple shells.
- Review, validation, Godot `.tres` / `.tscn` publishing, and the queue.

OpenAI albedo maps get derived normal, roughness, AO, metallic, and height images. Metadata marks those `derived_from_albedo`. They are not a second image model. A 4096 request is generated at 2048 and resized, and that fact is stored.

## Modular placement

Pieces use the same local frames as `BuildingGeometry`.

- Wall, doorway, and window: edge midpoint, local +X along the wall, thickness on Z, bottom at y = 0. Wall length is `cell_size - wall_thickness` (0.85 m).
- Floor: cell center, thickness 0.1 m.
- Door leaf: hinge at the left edge, bottom on the ground.
- Fence and gate: 1 m module, pivot at the left side.
- Stairs: footprint center, climbing toward local -Z, 1 x 3 cells, same wedge as the game.

They are reusable scenes. They are not plugged into `BuildingSystem`, so placing them does not change structural checks.

Collision nodes are named with Godot's `-colonly` suffix. On import, Godot turns those into collision and keeps the other meshes visible.

## Blender

Install Blender, then set `BLENDER_BIN` to `blender.exe`. When it is set, mesh jobs run:

```text
blender --background --python tools/ai_asset_pipeline/blender/process_mesh.py -- job.json
```

That script applies rotation and scale, recalculates normals, decimates toward the polygon budget, adds a `-colonly` box if the file has no collision node, writes LOD files, and exports GLB. The original file stays in the asset's `original/` folder. If Blender is missing or the script fails, the downloaded or procedural mesh is kept and the warning is stored on the asset.

Manual character rig, when auto-rig is unavailable:

1. Import the original GLB.
2. Add an armature using Godot humanoid names: Hips, Spine, Chest, Neck, Head, LeftUpperArm, LeftLowerArm, LeftHand, RightUpperArm, RightLowerArm, RightHand, LeftUpperLeg, LeftLowerLeg, LeftFoot, RightUpperLeg, RightLowerLeg, RightFoot.
3. Parent the body with automatic weights. Keep helmets, vests, gloves, boots, and backpacks as separate meshes on that armature if they should swap.
4. Export GLB, Y-up.
5. Use Reprocess in the dashboard. Approval stays blocked while validation reports no skin, unless you explicitly acknowledge the limitation.

## Godot output

### Upload a texture to replace graphics

On **Surfaces** or **Icons**, use **Upload** / **Upload replace**, or open the item in Preview and pick a file under Extra → **Upload albedo to replace**. The dashboard stages the file, runs a `provider: "manual"` job (albedo kept, other maps derived), and opens the review. Press **Keep**; if game art already exists, leave **Replace an approved file** checked.

Approval copies files into the project and refuses to replace an approved file unless the request sets `confirm_overwrite_approved`.


| Kind | Destination |
| --- | --- |
| Textures | `assets/textures/<name>/` and `assets/materials/<name>.tres` |
| Weapons | `assets/weapons/` |
| Equipment | `assets/equipment/` |
| Props | `assets/props/` |
| Buildings | `assets/buildings/<name>.glb` and `<name>.tscn` |
| Characters | `assets/characters/` |
| Vehicles | `assets/vehicles/` |
| Environment | `assets/environment/` |
| World props (resource kind) | `assets/resources/<id>.glb` |
| Deployables | `assets/deployables/<id>.glb` |

### World props

Trees, boulders, salvage wrecks and loot crates are not placeable, but they are defined like deployables: one id for the definition, the gameplay box, the mesh and the Meshy job.

- `resources/world_props/<id>.tres` holds name, description, kind, `deposit_id` and `body_size` (meters, the Meshy `target_size`). Add or change a prop in the table in `tools/gen_world_props.py`, run it, and add the id to `ORDER` in `scripts/world/world_prop_catalog.gd`. Health, tool and yield stay in `scripts/items/resource_catalog.gd`.
- The Icons tab lists them with category `world_prop`. Make the icon first, then **Make model** on the Ingame tab. The job runs as workshop category `resources`, preset `from_icon`.
- Approving the model writes `assets/resources/<id>.glb`. `ResourceNode` and `LootContainer` pick it up through `WorldPropArt` and fit it to `body_size`. Without a file they keep their primitive meshes. A model from the Surfaces tab at `assets/environment/<id>.glb` (for example `tree_oak`) works too.
- `tests/world_props.gd` and the world prop tests in `tests/test_pipeline.py` check the files, ids, sizes and the link to the deposits.

Metadata for approved assets is `assets/pipeline_meta/<name>.json`. That folder contains `.gdignore`, so Godot does not import the JSON. Working copies, prompts, seeds, and version history stay in `tools/ai_asset_pipeline/library/`, which is gitignored.

Materials are `StandardMaterial3D` resources. Roughness, metallic, and AO are read from the red channel. Texture filter is linear with mipmaps. UVs on procedural meshes are in meters so texel density stays consistent when a 1 m tile is applied.

Open the project in the Godot editor once after approval so it imports the new GLB and PNG files. Nothing in the current gameplay scenes references those paths, so the prototype keeps using its primitive meshes.

## Style and prompts

Edit `config/style.json` and `presets/catalog.json`. The next job reads them. No code change is required for palette, avoid-list, or category prompts.

Each asset stores the full prompt, the negative prompt, the provider, the model, the seed when the provider supports one, and the parameters that were sent. OpenAI's image API does not return a seed, so those assets record `seed_supported: false`. Tripo receives `model_seed` and `texture_seed` when you enter a seed. Meshy text prompts are capped at 800 characters because that is the documented limit. The uncut prompt is still saved.

## Validation

A failed check does not copy the asset into `assets/`. The review library still shows it. Errors cover an unreadable GLB, a missing mesh, material, or UV set, a polygon count above 250000, a bad node scale, and missing collision on props and buildings. Characters without a skin fail until you acknowledge that limit or supply a rigged GLB.

## Layout

```text
tools/ai_asset_pipeline/
  config/        style, defaults, building grid, provider_pricing
  presets/       category prompts
  prompts/       prompt assembly
  core/          settings, metadata store, costs, redaction
  providers/     OpenAI, Meshy, Tripo (+ base ThreeDProvider)
  generators/    textures, modular kit, job orchestration
  processors/    glTF writer, PBR maps, validation
  blender/       background processing
  godot/         tres and tscn publishing
  jobqueue/      background worker
  dashboard/     local review UI
  docs/          workshop architecture map
  tests/
```

New image or mesh services should follow the provider modules: build a documented request, poll the documented task endpoint, and return files plus parameters. Do not add a provider that returns stand-in geometry.

## Workshop phases

See [docs/WORKSHOP_ARCHITECTURE.md](docs/WORKSHOP_ARCHITECTURE.md) for the full map from the AI 3D Asset Workshop blueprint onto this package.

**Phase 1–8 (done in package):** Architecture map; providers/tasks/costs; Production UI; static categories; humanoid skeleton normalize + character template; **animation library + AnimationTree** ([`config/meshy_actions.json`](config/meshy_actions.json), [`godot/animation_library.py`](godot/animation_library.py)); **modular clothing slots** ([`config/clothing_slots.json`](config/clothing_slots.json), [`blender/separate_clothing.py`](blender/separate_clothing.py)); **Costs tab + budgets** ([`core/costs.py`](core/costs.py) summary/gate); **optimization profiles** ([`config/optimization_profiles.json`](config/optimization_profiles.json)) with Blender collision/LOD/skin policy and mesh-provider retries.

### First Meshy character

`workshop_survivor_01` was generated with Meshy (image-to-3D + rig), skeleton-normalized to Godot humanoid bones, and approved to:

- `assets/characters/workshop_survivor_01.glb`
- `assets/characters/workshop_survivor_01.tscn`
- `assets/characters/Shared/Animations/` (walk / run)
- `assets/characters/Shared/skeleton_profile.json`

Meshy `texture_resolution` must be `2k` / `4k` / `8k` (defaults to `2k`).

### Shared locomotion (Quaternius)

Default basic animations come from [Quaternius Universal Animation Library](https://store.godotengine.org/asset/quaternius/universal-animation-library/) (CC0) at `assets/characters/Shared/Quaternius/`.

- Config: [`config/shared_animation_library.json`](config/shared_animation_library.json) (`idle→Idle`, `walk→Walk`; walk-only, no jog)
- Runtime library: `assets/characters/Shared/Quaternius/ual_locomotion.res` (extracted after BoneMap retarget)
- Bone maps: `QuaterniusBoneMap.tres` + `GodotHumanoidBoneMap.tres` (applied by `addons/pipeline_retarget`)
- Character scenes load `ual_locomotion.res` into AnimationPlayer + idle/walk/run AnimationTree
