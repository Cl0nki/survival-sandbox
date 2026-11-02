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

Copy `tools/ai_asset_pipeline/.env.example` to `tools/ai_asset_pipeline/.env`. The file is gitignored. The dashboard receives only `configured: true/false`. Keys are sent to the matching host and stripped from logs.

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

Tripo's separate rigging API is not called. Character jobs use Meshy rigging when `MESHY_API_KEY` is set. Otherwise the asset stays unrigged and the metadata lists the Blender steps. Image-to-3D is not treated as an animation-ready character.

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
  config/        style, defaults, building grid
  presets/       category prompts
  prompts/       prompt assembly
  core/          settings, metadata store, redaction
  providers/     OpenAI, Meshy, Tripo
  generators/    textures, modular kit, job orchestration
  processors/    glTF writer, PBR maps, validation
  blender/       background processing
  godot/         tres and tscn publishing
  jobqueue/      background worker
  dashboard/     local review UI
  tests/
```

New image or mesh services should follow the provider modules: build a documented request, poll the documented task endpoint, and return files plus parameters. Do not add a provider that returns stand-in geometry.
