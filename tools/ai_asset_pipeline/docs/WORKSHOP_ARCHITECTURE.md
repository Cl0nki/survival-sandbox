# AI 3D Asset Workshop — architecture map

Phase 1 deliverable. Maps the blueprint onto the existing `tools/ai_asset_pipeline` package. No game scripts are rewritten.

## Existing stack (do not replace)

| Piece | Location | Role |
| --- | --- | --- |
| Godot 4.7.2 game | repo root (`project.godot`, `scripts/`, `scenes/`) | Runtime. Pipeline only publishes into `assets/` on approve. |
| Pipeline entry | [`run.py`](../run.py) | `doctor`, `serve`, `generate` CLI. |
| Settings / secrets | [`core/settings.py`](../core/settings.py), `.env` | Keys never sent to the dashboard UI. |
| Persistence | [`core/store.py`](../core/store.py) → `library/` (gitignored) | JSON jobs + asset folders (`original/`, `processed/`, `preview/`, `versions/`). |
| Job queue | [`jobqueue/worker.py`](../jobqueue/worker.py) | Background thread; UI stays responsive. |
| Orchestration | [`generators/orchestrator.py`](../generators/orchestrator.py) | Normalize request → concept → mesh → optional rig → Blender → validate. |
| Image provider | [`providers/openai_images.py`](../providers/openai_images.py) | Concept / albedo images. |
| Mesh providers | [`providers/meshy.py`](../providers/meshy.py), [`providers/tripo.py`](../providers/tripo.py) | Image/text → GLB; Meshy humanoid rig. |
| Blender | [`blender/process_mesh.py`](../blender/process_mesh.py), [`blender/runner.py`](../blender/runner.py) | Scale, normals, soft decimate, collision, LOD. |
| Validate / publish | [`processors/validate.py`](../processors/validate.py), [`godot/publish.py`](../godot/publish.py) | Review gate; copy into `assets/` + `.tres` / `.tscn`. |
| Dashboard | [`dashboard/server.py`](../dashboard/server.py), [`dashboard/static/`](../dashboard/static/) | Local HTTP UI on `127.0.0.1:8765`. |
| Catalog / style | [`presets/catalog.json`](../presets/catalog.json), [`config/style.json`](../config/style.json) | Category prompts without code changes. |

Approved metadata lives in `assets/pipeline_meta/` (`.gdignore`). Working copies stay in `library/`.

## Current kinds vs workshop categories

| Workshop category (blueprint) | Current `kind` / catalog section | Gap |
| --- | --- | --- |
| Characters (survivors, humanoid enemies) | `character` / `characters` | Skeleton normalize + Shared animation library + AnimationTree (Phases 4–5). |
| Non-humanoid enemies | `enemy` / `enemies` (Tripo default) | Tripo alt-rig adapter ready; animate_rig still optional per job. |
| Deployables | `deployable` / `deployables` → `assets/deployables/` | Done in Phase 3. |
| Resources | `resource` / `resources` → `assets/resources/` | Done in Phase 3. |
| Decorations | `decoration` / `decorations` → `assets/environment/` | Production counters in Phase 3. |
| Textures / icons | `texture` | Keep; concept source for 3D jobs. |

Production targets (10 / 30 / 90 / 50 / 100) will count **approved** assets by workshop category, not generation attempts.

## Workflow today vs target states

Existing job/asset statuses: `waiting`, `generating`, `downloading`, `processing`, `ready_for_review`, `approved`, `failed`, `rejected` (approval only).

Target workshop stages: Pending → Generating → Texturing → Rigging → Animating → Processing → Validating → Ready for Review → Approved | Rejected | Failed.

Phase 2 introduces persistent **generation tasks** per provider operation so stages can be recorded without blocking the UI. Full stage UI lands in Phase 3.

## Provider strategy

| Operation | Primary | Secondary | Notes |
| --- | --- | --- | --- |
| Image → 3D | Meshy | Tripo | Both already download GLB immediately. |
| Text → 3D | Meshy (`meshy_text`) | — | Preview + refine. |
| Texturing | Bundled in Meshy/Tripo mesh calls (`should_texture` / `texture`) | Separate Meshy remesh/texture later if needed | Phase 2 keeps bundled texturing; optional remesh API later. |
| Humanoid rig | Meshy `/openapi/v1/rigging` | Manual Blender steps | Humanoid only. |
| Non-humanoid / alt rig | Tripo `animate_rig` (+ `rig_type`) | Manual Blender | Wired in Phase 2 adapter; orchestrator use in Phase 4. |
| Animations | Meshy `/openapi/v1/animations` | Shared library retarget | Adapter in Phase 2; library workflow in Phase 5. |

Common interface: [`providers/base.py`](../providers/base.py) (`ThreeDProvider`). Adapters keep provider-specific HTTP inside Meshy/Tripo modules. Orchestrator must not branch on undocumented raw payloads.

## Files changed / planned by phase

| Phase | Focus | Touch |
| --- | --- | --- |
| **1** (this doc) | Inspect + map | `docs/WORKSHOP_ARCHITECTURE.md` |
| **2** | Provider abstraction, task/cost records, Meshy animation + Tripo rig adapters | `providers/*`, `core/store.py`, `core/costs.py`, `config/provider_pricing.json`, orchestrator hooks, tests, `.env.example` |
| **3** (done) | Workshop library UI, profiles, production counters, static E2E | `config/workshop.json`, catalog deployables/resources/decorations/enemies, dashboard Production tab, orchestrator kinds |
| **4** (done) | Character pipeline + skeleton normalize + Godot template | `processors/skeleton_normalize.py`, `godot/character_template.py`, `config/humanoid_skeleton.json` |
| **5** (done) | Animation library + AnimationTree | Quaternius UAL as Shared default (`config/shared_animation_library.json`); Meshy clips optional; AnimationTree blend space |
| **6** (done) | Modular clothing | `config/clothing_slots.json`, slot analysis, optional Blender separate + weight transfer |
| **7** (done) | Cost dashboard, budgets | Costs tab, `/api/costs/summary`, workshop `budgets` soft/hard gate |
| **8** (done) | Optimization profiles, reliability | `config/optimization_profiles.json` → Blender job fields; mesh-provider retries |

## First milestone assets (Phase 17)

Prove before mass production:

1. One human survivor (Meshy + humanoid rig).
2. One humanoid enemy (same skeleton profile).
3. One non-humanoid enemy (Tripo / alt rig).
4. One static deployable.
5. One resource node.

Done when: concept → generate → store → rig (where applicable) → basic anim preview → validate → approve → Godot export → cost recorded → restart-safe.

## Constraints carried forward

- No fake provider geometry.
- Keys only in process env; dashboard gets `configured: true/false`.
- Originals preserved; processing writes new files under `processed/` / `versions/`.
- Do not auto-publish candidates into live game folders.
- Pricing tables are config JSON, not hardcoded constants in logic.
- Pillow remains the only required third-party package unless a later phase needs more.
