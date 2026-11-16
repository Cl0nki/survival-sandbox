import io
import json
import re
import shutil
import time
import uuid
from pathlib import Path

from PIL import Image

from blender.runner import process_with_blender, separate_clothing_with_blender
from core.costs import check_budget, cost_record_from_task, estimate_operation, load_pricing
from core.errors import ConfigError, PipelineError, ProviderError
from core.optimization import resolve_profile
from core.redact import redact
from core.settings import Settings
from core.store import AssetStore, _snapshot
from core.workshop import load_workshop, resolve_category
from generators.modular import PIECE_META, build_piece, kit_piece_ids
from godot.animation_library import clip_set, load_meshy_actions, shared_clip_name
from godot.publish import publish_asset
from processors.clothing import analyze_clothing_glb, clothing_export_plan, load_clothing_slots
from processors.gltf_write import write_glb
from processors.icons import procedural_icon
from processors.maps import derive_maps, procedural_maps, save_maps, seam_score, tiled_preview
from processors.skeleton_normalize import load_skeleton_profile, normalize_glb_skeleton
from processors.validate import MANUAL_RIG_STEPS, validate_mesh, validate_texture
from prompts.builder import FIREARM_TARGET_SIZE, GENERIC_PICKUP_SIZE, build_prompts, is_firearm
from providers.http_client import download
from providers.meshy import MeshyProvider, glb_url
from providers.registry import meshy_from, openai_from, threed_from
from providers.tripo import model_url, rendered_image_url

SECTION = {
    "texture": "textures",
    "prop": "props",
    "character": "characters",
    "building": "buildings",
    "deployable": "deployables",
    "resource": "resources",
    "decoration": "decorations",
    "enemy": "enemies",
}

STATIC_MESH_KINDS = {"prop", "building", "deployable", "resource", "decoration"}
CHARACTER_LIKE_KINDS = {"character", "enemy"}


_ICON_CATEGORIES = {
    "medical",
    "ammo",
    "food",
    "weapon",
    "tool",
    "harvest",
    "refined",
    "component",
    "explosive",
    "container",
    "deployable",
    "world_prop",
    "material",
}


def _icon_category(value) -> str:
    text = str(value or "").strip().lower()
    return text if text in _ICON_CATEGORIES else "misc"


def _swatch(value) -> list[float] | None:
    if not isinstance(value, (list, tuple)) or len(value) < 3:
        return None
    try:
        return [float(value[0]), float(value[1]), float(value[2])]
    except (TypeError, ValueError):
        return None


def safe_name(value: str) -> str:
    token = re.sub(r"[^a-z0-9_]+", "_", (value or "").strip().lower())
    token = re.sub(r"_+", "_", token).strip("_")
    if not token:
        raise PipelineError("Asset name is empty.")
    if token[0].isdigit():
        token = f"a_{token}"
    return token[:48]


def preset_for(settings: Settings, kind: str, category: str) -> dict:
    catalog = settings.catalog()
    section = catalog.get(SECTION.get(kind, ""), {})
    preset = section.get(category)
    if preset is None:
        known = ", ".join(sorted(section)) or "(none)"
        raise PipelineError(f"Unknown {kind} category '{category}'. Known categories: {known}")
    return preset


def normalize_request(settings: Settings, payload: dict) -> dict:
    workshop = load_workshop(settings.workshop_path)
    workshop_category = str(payload.get("workshop_category") or "").strip().lower()
    kind = str(payload.get("kind") or "").strip()
    profile = None
    if workshop_category:
        try:
            profile = resolve_category(workshop, workshop_category)
        except KeyError as exc:
            raise PipelineError(str(exc)) from None
        kind = kind or profile.get("kind", "")
    if kind not in SECTION:
        raise PipelineError(
            "Kind must be texture, prop, character, building, deployable, resource, decoration, or enemy."
        )
    category = str(payload.get("category", "")).strip()
    preset = preset_for(settings, kind, category)
    if not workshop_category:
        workshop_category = str(preset.get("workshop_category") or "").strip().lower()
        if workshop_category:
            try:
                profile = resolve_category(workshop, workshop_category)
            except KeyError:
                profile = None
    name = safe_name(str(payload.get("name", "")))
    variations = int(payload.get("variations", settings.defaults["variations"]))
    if variations < 1 or variations > int(settings.defaults["max_variations"]):
        raise PipelineError(f"Variations must be from 1 to {settings.defaults['max_variations']}.")
    resolution = int(payload.get("resolution", settings.defaults["resolution"]))
    allowed = [int(item) for item in settings.defaults["allowed_resolutions"]]
    if resolution not in allowed:
        raise PipelineError(f"Resolution must be one of {allowed}.")
    default_poly = settings.defaults["character_polycount" if kind in CHARACTER_LIKE_KINDS else "polycount"]
    polycount = int(payload.get("polycount", default_poly))
    if polycount < 100 or polycount > 250000:
        raise PipelineError("Polygon count must be between 100 and 250000.")
    seed = payload.get("seed")
    if seed is not None and seed != "":
        seed = int(seed)
    else:
        seed = None
    provider = str(payload.get("provider") or "").strip()
    mesh_provider = str(payload.get("mesh_provider") or preset.get("mesh_provider") or "").strip()
    if profile and not mesh_provider:
        mesh_provider = str(profile.get("mesh_provider") or "").strip()
    implementation = preset.get("implementation")
    humanoid = preset.get("humanoid")
    if humanoid is None and profile is not None:
        humanoid = profile.get("humanoid")
    if humanoid is None:
        humanoid = kind in {"character"} or (kind == "enemy" and preset.get("implementation") == "ai_character")
    humanoid = bool(humanoid)
    if implementation in {"procedural", "procedural_kit"}:
        provider = "procedural"
        mesh_provider = ""
    elif kind == "texture":
        provider = provider or "procedural"
        if provider not in {"procedural", "openai", "manual"}:
            raise PipelineError("Texture provider must be procedural, openai, or manual.")
        if provider == "manual" and not str(payload.get("source_file") or "").strip():
            raise PipelineError("Manual texture jobs need an uploaded source image.")

    else:
        provider = provider or "openai"
        mesh_provider = mesh_provider or "meshy"
        if mesh_provider not in {"meshy", "tripo", "meshy_text"}:
            raise PipelineError("Mesh provider must be meshy, tripo, or meshy_text.")
        if provider not in {"openai", "manual"} and mesh_provider != "meshy_text":
            raise PipelineError("Mesh jobs need an image provider, or meshy_text for Meshy text-to-3D.")
    quality = str(payload.get("quality") or settings.defaults["openai_quality"])
    firearm = is_firearm(
        name,
        str(payload.get("prompt") or ""),
        str(payload.get("subject_override") or ""),
        icon_category=str(payload.get("icon_category") or ""),
    )
    # Gun pictures stay on the high setting so a side-view firearm actually comes back.
    if firearm:
        quality = "high"
    target_size = _target_size(payload.get("target_size"))
    if firearm and kind != "texture" and _is_generic_pickup_size(target_size):
        target_size = list(FIREARM_TARGET_SIZE)
    customization = payload.get("customization") if kind in CHARACTER_LIKE_KINDS and humanoid else {}
    if customization is None:
        customization = {}
    if not isinstance(customization, dict):
        raise PipelineError("Customization must be an object of labels.")
    default_auto_rig = bool(profile.get("auto_rig")) if profile else (kind == "character" or (kind == "enemy" and humanoid))
    if "auto_rig" in preset:
        default_auto_rig = bool(preset.get("auto_rig"))
    auto_rig = bool(payload.get("auto_rig", default_auto_rig)) and humanoid
    ## Meshy walk/run clips stay opt-in. Characters use the Quaternius Shared library by default.
    default_auto_animate = bool(profile.get("auto_animate")) if profile else False
    if "auto_animate" in preset:
        default_auto_animate = bool(preset.get("auto_animate"))
    auto_animate = bool(payload.get("auto_animate", default_auto_animate)) and auto_rig
    godot_folder = preset.get("godot_folder") or (profile or {}).get("godot_folder") or "props"
    expect_collision = bool((profile or {}).get("expect_collision", kind in STATIC_MESH_KINDS))
    if kind == "building":
        expect_collision = True
    return {
        "kind": kind,
        "category": category,
        "workshop_category": workshop_category,
        "name": name,
        "prompt": str(payload.get("prompt") or "")[:2000],
        "prompt_override": " ".join(str(payload.get("prompt_override") or "").split())[:12000],
        "subject_override": " ".join(str(payload.get("subject_override") or "").split())[:2000],
        "provider": provider,
        "mesh_provider": mesh_provider,
        "resolution": resolution,
        "variations": 1 if implementation == "procedural_kit" else variations,
        "quality": quality,
        "polycount": polycount,
        "seed": seed,
        "customization": {str(key): str(value)[:80] for key, value in customization.items()},
        "auto_rig": auto_rig,
        "auto_animate": auto_animate,
        "humanoid": humanoid,
        "expect_collision": expect_collision,
        "optimization_profile": (profile or {}).get("optimization_profile") or ("character" if humanoid else "prop"),
        "source_file": _checked_source(settings, str(payload.get("source_file") or "")),
        "reference_images": _checked_references(settings, payload.get("reference_images")),
        "icon_category": _icon_category(payload.get("icon_category")),
        "swatch": _swatch(payload.get("swatch")),
        "implementation": implementation,
        "godot_folder": godot_folder,
        "procedural_piece": preset.get("procedural_piece"),
        "target_size": target_size,
        "firearm": firearm,
    }


def execute_job(settings: Settings, store: AssetStore, job: dict) -> None:
    request = normalize_request(settings, job["request"])
    job["request"] = request
    _budget_preflight(settings, store, job, request)
    try:
        if request["implementation"] == "procedural_kit":
            _run_kit(settings, store, job, request)
        elif request["implementation"] == "procedural":
            _run_procedural_mesh(settings, store, job, request)
        elif request["kind"] == "texture":
            _run_textures(settings, store, job, request)
        else:
            _run_generated_meshes(settings, store, job, request)
    except (PipelineError, ProviderError, OSError, ValueError) as exc:
        job["status"] = "failed"
        job["errors"].append(redact(str(exc)))
        job["message"] = job["errors"][-1]
        store.save_job(job)
        store.append_log(f"job {job['job_id']} failed: {job['message']}")
        return
    _finish_job(store, job)


def approve_asset(settings: Settings, store: AssetStore, asset_id: str, acknowledge: bool, force: bool, confirm_approved: bool) -> dict:
    asset = store.get_asset(asset_id)
    if asset.get("approval_status") == "approved" and not confirm_approved:
        raise PipelineError("This asset is already approved. Confirm an overwrite to publish it again.")
    published = publish_asset(
        settings.project_root,
        asset,
        store.root,
        acknowledge=acknowledge,
        force=force or confirm_approved,
        confirm_approved=confirm_approved,
    )
    asset["approval_status"] = "approved"
    asset["processing_status"] = "approved"
    asset["production_files"] = published["files"]
    asset["history"].append(_snapshot(asset, "approved"))
    store.save_asset(asset)
    _refresh_job_approval(store, asset.get("job_id", ""))
    return asset


def discard_asset(store: AssetStore, asset_id: str) -> dict:
    asset = store.get_asset(asset_id)
    if asset.get("approval_status") == "approved":
        raise PipelineError("This picture is already in the game. Remove only deletes a review copy.")
    folder = (store.assets_dir / asset_id).resolve()
    root = store.assets_dir.resolve()
    if not folder.is_dir() or root not in folder.parents:
        raise PipelineError("That review copy is not in the library.")
    shutil.rmtree(folder)
    store.append_log(f"discarded {asset_id} {asset.get('asset_name', '')}")
    return {"asset_id": asset_id, "asset_name": asset.get("asset_name", ""), "deleted": True}


def reject_asset(store: AssetStore, asset_id: str, reason: str) -> dict:
    asset = store.get_asset(asset_id)
    if asset.get("approval_status") == "approved":
        raise PipelineError("Approved assets stay in the project until you explicitly overwrite them. Rejection does not delete production files.")
    asset["approval_status"] = "rejected"
    asset["processing_status"] = "ready_for_review"
    asset.setdefault("errors", []).append(reason or "Rejected in review.")
    asset["history"].append(_snapshot(asset, "rejected"))
    store.save_asset(asset)
    return asset


def rotate_asset_images(settings: Settings, store: AssetStore, asset_id: str, degrees: int) -> dict:
    """Rotate approved images clockwise by 90/180/270 and rewrite library + game files."""
    turn = int(degrees) % 360
    if turn not in {90, 180, 270}:
        raise PipelineError("Save a 90, 180, or 270 degree rotation.")
    asset = store.get_asset(asset_id)
    if asset.get("approval_status") != "approved":
        raise PipelineError("Only approved images can be rotated. Keep the picture first.")
    folder = store.asset_dir(asset_id)
    op = {
        90: Image.Transpose.ROTATE_270,
        180: Image.Transpose.ROTATE_180,
        270: Image.Transpose.ROTATE_90,
    }[turn]
    albedo = folder / "original" / "albedo.png"
    if not albedo.is_file():
        albedo = folder / "processed" / "albedo.png"
    if albedo.is_file():
        with Image.open(albedo) as image:
            image.load()
            rotated_albedo = image.transpose(op)
        origins = asset.get("maps_origin") or {}
        derived = any(value == "derived_from_albedo" for value in origins.values())
        roughness = 0.8
        metallic = 0.0
        params = asset.get("generation_parameters") or {}
        if isinstance(params.get("roughness"), (int, float)):
            roughness = float(params["roughness"])
        if isinstance(params.get("metallic"), (int, float)):
            metallic = float(params["metallic"])
        if derived or asset.get("category") == "item_icon":
            mode = "RGBA" if asset.get("category") == "item_icon" else "RGB"
            maps = derive_maps(rotated_albedo.convert(mode), roughness, metallic)
            if asset.get("category") == "item_icon":
                maps["albedo"] = rotated_albedo.convert("RGBA")
        else:
            maps = {"albedo": rotated_albedo.convert(rotated_albedo.mode)}
            for name in ("normal", "roughness", "ao", "metallic", "height"):
                for kind in ("original", "processed"):
                    path = folder / kind / f"{name}.png"
                    if path.is_file():
                        with Image.open(path) as image:
                            image.load()
                            maps[name] = image.transpose(op)
                        break
        original_paths = save_maps(maps, folder / "original")
        processed_paths = save_maps(maps, folder / "processed")
        if asset.get("category") == "item_icon":
            preview = maps["albedo"].copy()
            preview_path = folder / "preview" / "icon.png"
        else:
            preview = tiled_preview(maps["albedo"].convert("RGB"))
            preview_path = folder / "preview" / "tiled.png"
        preview.save(preview_path, format="PNG")
        asset["original_files"] = [_relative(folder, Path(path)) for path in original_paths.values()]
        asset["processed_files"] = [_relative(folder, Path(path)) for path in processed_paths.values()]
        asset["processed_files"].append(_relative(folder, preview_path))
        asset.setdefault("generation_parameters", {})["seam_score"] = round(seam_score(maps["albedo"]), 3)
    else:
        paths = _image_files_for_asset(folder, asset)
        if not paths:
            raise PipelineError("This review has no image file to rotate.")
        for path in paths:
            _transpose_image_file(path, op)
    if asset.get("kind") == "texture":
        published = publish_asset(
            settings.project_root,
            asset,
            store.root,
            acknowledge=True,
            force=True,
            confirm_approved=True,
        )
        asset["production_files"] = published["files"]
    asset["history"].append(_snapshot(asset, f"rotated_{turn}"))
    store.save_asset(asset)
    store.append_log(f"rotated {asset_id} {turn}deg {asset.get('asset_name', '')}")
    return asset


def _image_files_for_asset(folder: Path, asset: dict) -> list[Path]:
    names = list(asset.get("original_files") or []) + list(asset.get("processed_files") or [])
    paths = []
    seen = set()
    for relative in names:
        if not isinstance(relative, str):
            continue
        if not relative.lower().endswith((".png", ".jpg", ".jpeg", ".webp")):
            continue
        path = (folder / relative).resolve()
        root = folder.resolve()
        if root not in path.parents and path != root:
            continue
        if not path.is_file() or path in seen:
            continue
        seen.add(path)
        paths.append(path)
    for kind in ("original", "preview"):
        directory = folder / kind
        if not directory.is_dir():
            continue
        for path in sorted(directory.iterdir()):
            if path.suffix.lower() in {".png", ".jpg", ".jpeg", ".webp"} and path.is_file() and path not in seen:
                seen.add(path)
                paths.append(path)
    return paths


def _transpose_image_file(path: Path, op) -> None:
    with Image.open(path) as image:
        image.load()
        converted = image.transpose(op)
        suffix = path.suffix.lower()
        temporary = path.with_suffix(path.suffix + ".tmp")
        if suffix in {".jpg", ".jpeg"}:
            converted.convert("RGB").save(temporary, format="JPEG", quality=95)
        elif suffix == ".webp":
            converted.save(temporary, format="WEBP", quality=95)
        else:
            converted.save(temporary, format="PNG")
    temporary.replace(path)


def reprocess_mesh(settings: Settings, store: AssetStore, asset_id: str, source: Path) -> dict:
    asset = store.get_asset(asset_id)
    if asset.get("approval_status") == "approved":
        raise PipelineError("This asset is approved. Reprocess is blocked until you confirm a new version from an unapproved copy.")
    if asset["kind"] == "texture":
        raise PipelineError("Reprocess a mesh asset, or generate a new texture.")
    data = Path(source).read_bytes()
    if not data.startswith(b"glTF"):
        raise PipelineError("Reprocess expects a GLB file.")
    folder = store.asset_dir(asset_id)
    version = int(asset.get("version", 1)) + 1
    archive = folder / "versions" / f"v{asset.get('version', 1)}"
    archive.mkdir(parents=True, exist_ok=True)
    for relative in asset.get("processed_files") or []:
        current = folder / relative
        if current.is_file():
            shutil.copy2(current, archive / current.name)
    target = folder / "processed" / f"{asset['asset_name']}.glb"
    target.write_bytes(data)
    asset["version"] = version
    asset["processed_files"] = [_relative(folder, target)]
    asset["history"].append(_snapshot(asset, "reprocess"))
    expect = bool((asset.get("generation_parameters") or {}).get("expect_collision", asset["kind"] in STATIC_MESH_KINDS or asset["kind"] == "building"))
    humanoid = bool((asset.get("generation_parameters") or {}).get("humanoid", asset["kind"] == "character"))
    _validate_and_ready(store, asset, target, expect_collision=expect, humanoid=humanoid)
    store.save_asset(asset)
    return asset


def _run_kit(settings, store, job, request) -> None:
    job["status"] = "processing"
    job["message"] = "Building the modular kit from the project grid."
    store.save_job(job)
    for index, piece_id in enumerate(kit_piece_ids(), start=1):
        name = safe_name(f"{request['name']}_{piece_id}")
        try:
            _write_procedural_piece(settings, store, job, request, piece_id, name, index)
        except (PipelineError, ProviderError, OSError, ValueError) as exc:
            job["errors"].append(f"{name}: {redact(str(exc))}")
            store.save_job(job)


def _run_procedural_mesh(settings, store, job, request) -> None:
    piece_id = request.get("procedural_piece")
    if not piece_id:
        raise PipelineError(f"{request['category']} has no procedural piece.")
    count = request["variations"]
    for index in range(1, count + 1):
        name = request["name"] if count == 1 else f"{request['name']}_{index:02d}"
        _write_procedural_piece(settings, store, job, request, piece_id, name, index)


def _write_procedural_piece(settings, store, job, request, piece_id, name, index) -> None:
    prompts = _prompts(settings, request)
    asset = store.create_asset(
        {
            "asset_name": name,
            "category": piece_id if request["implementation"] == "procedural_kit" else request["category"],
            "kind": "prop" if piece_id == "crate" else "building",
            "provider": "procedural",
            "model": "building_grid",
            "prompt": prompts["prompt"],
            "negative_prompt": prompts["negative_prompt"],
            "seed": request["seed"],
            "seed_supported": True,
            "generation_parameters": {
                "sent_prompt": prompts["provider_prompt"],
                "godot_folder": "props" if piece_id == "crate" else "buildings",
                "piece": piece_id,
                "grid": settings.grid(),
                "variation": index,
            },
            "job_id": job["job_id"],
            "modular": PIECE_META.get(piece_id, {}),
            "processing_status": "processing",
        }
    )
    job["asset_ids"].append(asset["asset_id"])
    store.save_job(job)
    folder = store.asset_dir(asset["asset_id"])
    meshes, materials = build_piece(piece_id, settings.grid())
    original = folder / "original" / f"{name}.glb"
    processed = folder / "processed" / f"{name}.glb"
    write_glb(original, meshes, materials)
    shutil.copy2(original, processed)
    asset["original_files"] = [_relative(folder, original)]
    asset["processed_files"] = [_relative(folder, processed)]
    asset["provider"] = "procedural"
    asset["maps_origin"] = {"mesh": "procedural_grid"}
    note = process_with_blender(
        settings,
        original,
        processed,
        request["polycount"],
        [],
        lambda message: store.asset_log(asset["asset_id"], message),
    )
    if note.get("skipped"):
        asset.setdefault("warnings", []).append(note["message"])
    elif not note.get("ok", False):
        shutil.copy2(original, processed)
        asset.setdefault("warnings", []).append("Blender processing failed. The original procedural mesh was kept. " + note.get("error", ""))
    else:
        asset["processed_files"] = [_relative(folder, processed)]
        for lod in note.get("lod_files") or []:
            asset["processed_files"].append(_relative(folder, Path(lod)))
    _validate_and_ready(store, asset, processed, expect_collision=True)


def _require_icon_alpha(image: Image.Image) -> None:
    if "A" not in image.getbands():
        raise PipelineError("The icon PNG has no alpha channel. Item icons must be transparent outside the object.")
    low, _high = image.getchannel("A").getextrema()
    if low == 255:
        raise PipelineError(
            "The icon PNG has no transparent pixels. The image provider painted a background instead of returning alpha."
        )


def _run_textures(settings, store, job, request) -> None:
    for index in range(1, request["variations"] + 1):
        name = request["name"] if request["variations"] == 1 else f"{request['name']}_{index:02d}"
        try:
            _one_texture(settings, store, job, request, name, index)
        except (PipelineError, ProviderError, OSError, ValueError) as exc:
            _mark_latest_failed(store, job, redact(str(exc)))


def _one_texture(settings, store, job, request, name, index) -> None:
    preset = preset_for(settings, "texture", request["category"])
    prompts = _prompts(settings, request)
    seed = None if request["seed"] is None else int(request["seed"]) + index - 1
    asset = store.create_asset(
        {
            "asset_name": name,
            "category": request["category"],
            "kind": "texture",
            "provider": request["provider"],
            "model": "",
            "prompt": prompts["prompt"],
            "negative_prompt": prompts["negative_prompt"],
            "seed": seed,
            "seed_supported": request["provider"] == "procedural",
            "generation_parameters": {
                "sent_prompt": prompts["provider_prompt"],
                "godot_folder": preset.get("godot_folder", "textures"),
                "roughness": preset.get("roughness", 0.8),
                "metallic": preset.get("metallic", 0.0),
                "variation": index,
                "quality": request["quality"],
            },
            "texture_resolution": request["resolution"],
            "job_id": job["job_id"],
            "processing_status": "generating",
        }
    )
    job["asset_ids"].append(asset["asset_id"])
    job["status"] = "generating"
    job["message"] = f"Generating {name}."
    store.save_job(job)
    folder = store.asset_dir(asset["asset_id"])
    colors = _palette_colors(settings.style(), preset.get("palette") or [])
    if request["provider"] == "procedural" and request["category"] == "item_icon":
        albedo = procedural_icon(request["resolution"], request["icon_category"], request.get("swatch"), seed or 1)
        maps = derive_maps(albedo, float(preset.get("roughness", 0.8)), float(preset.get("metallic", 0.0)))
        maps["albedo"] = albedo
        asset["model"] = "procedural-item-icon"
        asset["maps_origin"] = {"albedo": "procedural", **{key: "derived_from_albedo" for key in maps if key != "albedo"}}
        asset["seed_supported"] = True
        asset.setdefault("warnings", []).append(
            "This icon is painted locally from the item category and swatch. It is not an image-model picture."
        )
    elif request["provider"] == "procedural":
        maps = procedural_maps(request["resolution"], colors, seed or 1, float(preset.get("roughness", 0.8)), float(preset.get("metallic", 0.0)))
        asset["model"] = "procedural-tile-noise"
        asset["maps_origin"] = {map_name: "procedural" for map_name in maps}
        asset["seed_supported"] = True
    elif request["provider"] == "manual":
        source = Path(request["source_file"])
        if not source.is_file():
            raise PipelineError("Manual texture jobs need a source PNG uploaded with the job.")
        albedo = Image.open(source).convert("RGBA" if request["category"] == "item_icon" else "RGB")
        if albedo.size != (request["resolution"], request["resolution"]):
            albedo = albedo.resize((request["resolution"], request["resolution"]), Image.Resampling.LANCZOS)
            asset["generation_parameters"]["resized_to"] = request["resolution"]
        maps = derive_maps(albedo, float(preset.get("roughness", 0.8)), float(preset.get("metallic", 0.0)))
        if request["category"] == "item_icon":
            maps["albedo"] = albedo
        asset["model"] = "manual-image"
        asset["maps_origin"] = {"albedo": "manual_image", **{key: "derived_from_albedo" for key in maps if key != "albedo"}}
    else:
        provider = openai_from(settings)
        provider.require_key()
        asset["processing_status"] = "generating"
        store.save_asset(asset)
        original_albedo = folder / "original" / "albedo.png"
        references = _reference_pngs(request.get("reference_images") or [])
        if references:
            info = provider.edit_png(
                prompts["provider_prompt"],
                references,
                original_albedo,
                request["resolution"],
                request["quality"],
                transparent=request["category"] == "item_icon",
            )
        else:
            info = provider.generate_png(
                prompts["provider_prompt"],
                original_albedo,
                request["resolution"],
                request["quality"],
                transparent=request["category"] == "item_icon",
            )
        asset["model"] = info["model"]
        asset["seed_supported"] = False
        asset["generation_parameters"]["provider_parameters"] = info["parameters"]
        asset["generation_parameters"]["provider_resolution"] = info["provider_resolution"]
        if info.get("upscaled_from"):
            asset["generation_parameters"]["upscaled_from"] = info["upscaled_from"]
        albedo = Image.open(original_albedo).convert("RGBA" if request["category"] == "item_icon" else "RGB")
        if albedo.size != (request["resolution"], request["resolution"]):
            albedo = albedo.resize((request["resolution"], request["resolution"]), Image.Resampling.LANCZOS)
        maps = derive_maps(albedo, float(preset.get("roughness", 0.8)), float(preset.get("metallic", 0.0)))
        if request["category"] == "item_icon":
            maps["albedo"] = albedo
        asset["maps_origin"] = {"albedo": "openai", **{key: "derived_from_albedo" for key in maps if key != "albedo"}}
        asset["processing_status"] = "processing"
        store.save_asset(asset)
    if request["category"] == "item_icon":
        _require_icon_alpha(maps["albedo"])
    original_paths = save_maps(maps, folder / "original")
    processed_paths = save_maps(maps, folder / "processed")
    if request["category"] == "item_icon":
        preview = maps["albedo"].copy()
        preview_path = folder / "preview" / "icon.png"
    else:
        preview = tiled_preview(maps["albedo"])
        preview_path = folder / "preview" / "tiled.png"
    preview.save(preview_path, format="PNG")
    asset["original_files"] = [_relative(folder, Path(path)) for path in original_paths.values()]
    asset["processed_files"] = [_relative(folder, Path(path)) for path in processed_paths.values()]
    asset["processed_files"].append(_relative(folder, preview_path))
    asset["generation_parameters"]["seam_score"] = round(seam_score(maps["albedo"]), 3)
    if asset["generation_parameters"]["seam_score"] > 30 and request["provider"] != "procedural":
        asset.setdefault("warnings", []).append(
            "The albedo still has a visible edge jump. Review the tiled preview before approving it."
        )
    validation = validate_texture({key: folder / "processed" / f"{key}.png" for key in maps}, request["resolution"])
    validation["warnings"] = list(asset.get("warnings", [])) + validation["warnings"]
    asset["validation"] = validation
    asset["warnings"] = validation["warnings"]
    asset["errors"] = validation["errors"]
    asset["processing_status"] = "ready_for_review" if validation["ok"] else "failed"
    if not validation["ok"]:
        job["errors"].append(f"{name}: " + "; ".join(validation["errors"]))
    asset["history"].append(_snapshot(asset, "processed"))
    store.save_asset(asset)


def _run_generated_meshes(settings, store, job, request) -> None:
    for index in range(1, request["variations"] + 1):
        name = request["name"] if request["variations"] == 1 else f"{request['name']}_{index:02d}"
        try:
            _one_mesh(settings, store, job, request, name, index)
        except (PipelineError, ProviderError, OSError, ValueError) as exc:
            _mark_latest_failed(store, job, redact(str(exc)))


def _one_mesh(settings, store, job, request, name, index) -> None:
    preset = preset_for(settings, request["kind"], request["category"])
    prompts = _prompts(settings, request)
    asset = store.create_asset(
        {
            "asset_name": name,
            "category": request["category"],
            "kind": request["kind"],
            "workshop_category": request.get("workshop_category") or preset.get("workshop_category") or "",
            "provider": request["mesh_provider"],
            "model": "",
            "prompt": prompts["prompt"],
            "negative_prompt": prompts["negative_prompt"],
            "seed": request["seed"],
            "seed_supported": request["mesh_provider"] == "tripo" and request["seed"] is not None,
            "generation_parameters": {
                "sent_prompt": prompts["compact_prompt"] if request["mesh_provider"] == "meshy_text" else prompts["provider_prompt"],
                "prompt_truncated": prompts["prompt_truncated"],
                "godot_folder": request.get("godot_folder") or preset.get("godot_folder", "props"),
                "polycount": request["polycount"],
                "customization": request["customization"],
                "variation": index,
                "image_provider": request["provider"],
                "workshop_category": request.get("workshop_category") or "",
                "humanoid": bool(request.get("humanoid")),
                "auto_rig": bool(request.get("auto_rig")),
                "auto_animate": bool(request.get("auto_animate")),
                "optimization_profile": request.get("optimization_profile") or "prop",
                "expect_collision": bool(request.get("expect_collision")),
            },
            "job_id": job["job_id"],
            "processing_status": "generating",
        }
    )
    job["asset_ids"].append(asset["asset_id"])
    job["status"] = "generating"
    job["message"] = f"Generating {name}."
    store.save_job(job)
    folder = store.asset_dir(asset["asset_id"])
    concept = _concept_image(settings, store, job, asset, request, prompts, folder)
    job["status"] = "generating"
    job["message"] = f"Generating the mesh for {name}."
    asset["processing_status"] = "generating"
    store.save_job(job)
    store.save_asset(asset)
    mesh_op = _run_mesh_provider(settings, store, job, asset, request, prompts, concept, folder)
    original = folder / "original" / "model.glb"
    if not original.is_file():
        raise ProviderError("The mesh provider finished without a local GLB.")
    processed = folder / "processed" / f"{name}.glb"
    asset["processing_status"] = "texturing" if mesh_op.get("textured") else "processing"
    store.save_asset(asset)
    job["status"] = "processing"
    job["message"] = f"Processing {name}."
    store.save_job(job)
    if request.get("humanoid") and request["auto_rig"] and settings.meshy_key:
        job["status"] = "rigging"
        job["message"] = f"Rigging {name}."
        asset["processing_status"] = "rigging"
        store.save_job(job)
        store.save_asset(asset)
        _try_rig(settings, store, job, asset, folder, original, processed)
        if (
            request.get("auto_animate")
            and (asset.get("generation_parameters") or {}).get("rigging", {}).get("provider_task_id")
        ):
            job["status"] = "animating"
            job["message"] = f"Animating {name}."
            asset["processing_status"] = "animating"
            store.save_job(job)
            store.save_asset(asset)
            _try_animate(settings, store, job, asset, folder)
    else:
        if request.get("humanoid"):
            asset["manual_steps"] = list(MANUAL_RIG_STEPS)
            asset.setdefault("warnings", []).append(
                "Automatic rigging did not run. Meshy humanoid rigging requires MESHY_API_KEY. "
                "Non-humanoid enemies should use Tripo animate_rig in a later step, or the Blender fallback."
            )
        shutil.copy2(original, processed)
    job["status"] = "processing"
    asset["processing_status"] = "processing"
    store.save_job(job)
    store.save_asset(asset)
    if request.get("humanoid") and processed.is_file():
        _normalize_character_skeleton(settings, store, asset, folder, processed)
        _maybe_separate_clothing(settings, store, asset, folder, processed)
    profile = resolve_profile(
        request.get("optimization_profile") or "prop",
        defaults=settings.defaults,
        polycount_override=request["polycount"],
    )
    note = process_with_blender(
        settings,
        processed if processed.is_file() else original,
        processed,
        profile["target_polycount"],
        list(profile["lod_ratios"]) if settings.blender_bin else [],
        lambda message: store.asset_log(asset["asset_id"], message),
        profile_name=profile["name"],
        add_collision=bool(request.get("expect_collision", profile["add_collision"])),
        recalc_normals=profile["recalc_normals"],
        preserve_skin=profile["preserve_skin"],
        skip_lod_if_skinned=profile["skip_lod_if_skinned"],
        target_size=request.get("target_size") or None,
    )
    if note.get("skipped"):
        if not processed.is_file():
            shutil.copy2(original, processed)
        asset.setdefault("warnings", []).append(note["message"])
    elif not note.get("ok", False):
        if not processed.is_file():
            shutil.copy2(original, processed)
        asset.setdefault("warnings", []).append("Blender processing failed. The downloaded model was kept. " + note.get("error", ""))
    asset["generation_parameters"]["optimization"] = {
        "profile": profile["name"],
        "target_polycount": profile["target_polycount"],
        "lod_ratios": profile["lod_ratios"],
        "add_collision": bool(request.get("expect_collision", profile["add_collision"])),
        "target_size": request.get("target_size") or None,
    }
    animation_files = list((asset.get("generation_parameters") or {}).get("animations") or [])
    asset["processed_files"] = list(
        dict.fromkeys([_relative(folder, processed)] + animation_files + [_relative(folder, Path(lod)) for lod in (note.get("lod_files") or [])])
    )
    job["status"] = "validating"
    asset["processing_status"] = "validating"
    store.save_job(job)
    store.save_asset(asset)
    _validate_and_ready(
        store,
        asset,
        processed,
        expect_collision=bool(request.get("expect_collision")),
        humanoid=bool(request.get("humanoid")),
    )


def _concept_image(settings, store, job, asset, request, prompts, folder: Path) -> Path:
    destination = folder / "original" / "concept.png"
    if request["mesh_provider"] == "meshy_text":
        return destination
    if request["provider"] == "manual":
        source = Path(request["source_file"])
        if not source.is_file():
            raise PipelineError("Upload a concept image or choose Meshy text-to-3D.")
        shutil.copy2(source, destination)
        asset["original_files"] = [_relative(folder, destination)]
        asset["generation_parameters"]["image_provider"] = "manual"
        store.save_asset(asset)
        return destination
    if request["provider"] != "openai":
        raise ConfigError("Set an image provider. OpenAI is the implemented concept-image adapter.")
    info = openai_from(settings).generate_png(prompts["provider_prompt"], destination, 1024, request["quality"])
    asset["generation_parameters"]["image_model"] = info["model"]
    asset["generation_parameters"]["image_parameters"] = info["parameters"]
    asset["original_files"] = [_relative(folder, destination)]
    store.save_asset(asset)
    return destination


def _run_mesh_provider(settings, store, job, asset, request, prompts, concept: Path, folder: Path) -> dict:
    mesh_provider = request["mesh_provider"]
    adapter = threed_from(settings, mesh_provider)
    gen_task = store.create_generation_task(
        {
            "job_id": job["job_id"],
            "asset_id": asset["asset_id"],
            "provider": adapter.name,
            "operation": "text_to_3d" if mesh_provider == "meshy_text" else ("image_to_model" if adapter.name == "tripo" else "image_to_3d"),
            "status": "generating",
            "input": {
                "mesh_provider": mesh_provider,
                "polycount": request["polycount"],
                "character": bool(request.get("humanoid")),
                "seed": request.get("seed"),
                "workshop_category": request.get("workshop_category") or "",
            },
        }
    )
    attempts = 3
    last_error = None
    for attempt in range(1, attempts + 1):
        try:
            if mesh_provider == "meshy":
                result = adapter.image_to_3d(
                    concept,
                    request["polycount"],
                    settings.defaults["meshy_texture_resolution"],
                    bool(request.get("humanoid")),
                    lambda message: store.asset_log(asset["asset_id"], message),
                    auto_size=_meshy_auto_size(request),
                )
                _store_meshy_download(store, job, asset, folder, result, gen_task["task_id"], "image_to_3d")
                return {"textured": True, "provider": "meshy", "generation_task_id": gen_task["task_id"]}
            if mesh_provider == "meshy_text":
                result = adapter.text_to_3d(
                    prompts["compact_prompt"],
                    request["polycount"],
                    bool(request.get("humanoid")),
                    lambda message: store.asset_log(asset["asset_id"], message),
                )
                asset["provider"] = "meshy"
                _store_meshy_download(store, job, asset, folder, result, gen_task["task_id"], "text_to_3d")
                return {"textured": True, "provider": "meshy", "generation_task_id": gen_task["task_id"]}
            if mesh_provider == "tripo":
                result = adapter.image_to_3d(
                    concept,
                    request["polycount"],
                    request["seed"],
                    lambda message: store.asset_log(asset["asset_id"], message),
                )
                _store_tripo_download(store, job, asset, folder, result, gen_task["task_id"])
                return {"textured": True, "provider": "tripo", "generation_task_id": gen_task["task_id"]}
            raise PipelineError(f"Unsupported mesh provider {mesh_provider}.")
        except (ProviderError, OSError) as exc:
            last_error = exc
            message = redact(str(exc))
            if not _retryable_provider_error(message) or attempt >= attempts:
                store.update_generation_task(gen_task["task_id"], status="failed", error=message)
                raise
            store.asset_log(asset["asset_id"], f"Transient mesh error (attempt {attempt}/{attempts}): {message}")
            time.sleep(min(8, 2 * attempt))
        except (ConfigError, ValueError) as exc:
            message = redact(str(exc))
            store.update_generation_task(gen_task["task_id"], status="failed", error=message)
            raise
    if last_error:
        raise last_error
    raise PipelineError(f"Unsupported mesh provider {mesh_provider}.")


def _retryable_provider_error(message: str) -> bool:
    lowered = (message or "").lower()
    tokens = ("timeout", "timed out", "429", "rate limit", "503", "502", "504", "temporar", "connection reset", "connection aborted")
    return any(token in lowered for token in tokens)


def _store_meshy_download(store, job, asset, folder, result, generation_task_id: str, operation: str) -> None:
    task = result["task"]
    provider_task_id = str(task.get("id", ""))
    asset["model"] = result["model"]
    asset["generation_parameters"]["provider_parameters"] = result["parameters"]
    asset["generation_parameters"]["provider_task_id"] = provider_task_id
    asset["generation_parameters"]["generation_task_id"] = generation_task_id
    url = glb_url(task)
    original = folder / "original" / "model.glb"
    original.write_bytes(download(url))
    files = [_relative(folder, original)]
    urls = task.get("model_urls") or {}
    if urls.get("pre_remeshed_glb"):
        pre = folder / "original" / "pre_remeshed.glb"
        pre.write_bytes(download(urls["pre_remeshed_glb"]))
        files.append(_relative(folder, pre))
    thumb = task.get("thumbnail_url")
    if thumb:
        preview = folder / "preview" / "thumbnail.png"
        preview.write_bytes(download(thumb))
        files.append(_relative(folder, preview))
    asset["original_files"] = list(dict.fromkeys(list(asset.get("original_files", [])) + files))
    store.save_asset(asset)
    credits = task.get("consumed_credits")
    store.update_generation_task(
        generation_task_id,
        status="succeeded",
        provider_task_id=provider_task_id,
        output={"files": files, "provider_task_id": provider_task_id},
        consumed_credits=credits,
    )
    store.create_cost_record(
        cost_record_from_task(
            provider="meshy",
            operation=operation,
            asset_id=asset["asset_id"],
            job_id=job.get("job_id", ""),
            generation_task_id=generation_task_id,
            provider_task_id=provider_task_id,
            consumed_credits=credits,
            category=asset.get("category", ""),
        )
    )


def _store_tripo_download(store, job, asset, folder, result, generation_task_id: str) -> None:
    task = result["task"]
    provider_task_id = str(task.get("task_id", ""))
    asset["model"] = result["model"]
    asset["generation_parameters"]["provider_parameters"] = result["parameters"]
    asset["generation_parameters"]["provider_task_id"] = provider_task_id
    asset["generation_parameters"]["generation_task_id"] = generation_task_id
    if result["parameters"].get("model_seed") is not None:
        asset["seed"] = result["parameters"]["model_seed"]
        asset["seed_supported"] = True
    original = folder / "original" / "model.glb"
    original.write_bytes(download(model_url(task)))
    files = [_relative(folder, original)]
    preview_url = rendered_image_url(task)
    if preview_url:
        preview = folder / "preview" / "thumbnail.png"
        preview.write_bytes(download(preview_url))
        files.append(_relative(folder, preview))
    asset["original_files"] = list(dict.fromkeys(list(asset.get("original_files", [])) + files))
    store.save_asset(asset)
    credits = task.get("consumed_credits")
    store.update_generation_task(
        generation_task_id,
        status="succeeded",
        provider_task_id=provider_task_id,
        output={"files": files, "provider_task_id": provider_task_id},
        consumed_credits=credits,
    )
    store.create_cost_record(
        cost_record_from_task(
            provider="tripo",
            operation="image_to_model",
            asset_id=asset["asset_id"],
            job_id=job.get("job_id", ""),
            generation_task_id=generation_task_id,
            provider_task_id=provider_task_id,
            consumed_credits=credits,
            category=asset.get("category", ""),
        )
    )


def _try_rig(settings, store, job, asset, folder, original: Path, processed: Path) -> None:
    provider: MeshyProvider = meshy_from(settings)
    gen_task = store.create_generation_task(
        {
            "job_id": job.get("job_id", ""),
            "asset_id": asset["asset_id"],
            "provider": "meshy",
            "operation": "rigging",
            "status": "rigging",
            "input": {"glb": "original/model.glb", "height_meters": settings.defaults["character_height_m"]},
        }
    )
    try:
        result = provider.rig(
            original,
            float(settings.style().get("character_height_m", settings.defaults["character_height_m"])),
            lambda message: store.asset_log(asset["asset_id"], message),
        )
    except (ProviderError, ConfigError, OSError) as exc:
        message = redact(str(exc))
        shutil.copy2(original, processed)
        asset["manual_steps"] = list(MANUAL_RIG_STEPS)
        asset.setdefault("warnings", []).append("Meshy rigging failed. The unrigged model was kept. " + message)
        store.update_generation_task(gen_task["task_id"], status="failed", error=message)
        return
    task = result["task"]
    provider_task_id = str(task.get("id", ""))
    rigged = (task.get("result") or {}).get("rigged_character_glb_url")
    if not rigged:
        shutil.copy2(original, processed)
        asset["manual_steps"] = list(MANUAL_RIG_STEPS)
        asset.setdefault("warnings", []).append("Meshy rigging finished without a rigged GLB URL.")
        store.update_generation_task(gen_task["task_id"], status="failed", error="No rigged_character_glb_url", provider_task_id=provider_task_id)
        return
    rigged_path = folder / "processed" / "rigged.glb"
    rigged_path.write_bytes(download(rigged))
    shutil.copy2(rigged_path, processed)
    saved = []
    ## Walk/run from Meshy rigging are opt-in via auto_animate; Quaternius is the default Shared library.
    if bool((asset.get("generation_parameters") or {}).get("auto_animate")):
        animations = (task.get("result") or {}).get("basic_animations") or {}
        for key in ("walking_glb_url", "running_glb_url"):
            if animations.get(key):
                target = folder / "processed" / f"{key.replace('_url', '')}.glb"
                target.write_bytes(download(animations[key]))
                saved.append(_relative(folder, target))
    credits = task.get("consumed_credits")
    asset["generation_parameters"]["rigging"] = {
        "provider": "meshy",
        "provider_task_id": provider_task_id,
        "generation_task_id": gen_task["task_id"],
        "animations": saved,
    }
    asset["generation_parameters"]["animations"] = list(
        dict.fromkeys(list(asset["generation_parameters"].get("animations") or []) + saved)
    )
    asset["processed_files"] = list(
        dict.fromkeys([_relative(folder, processed)] + list(asset["generation_parameters"]["animations"]))
    )
    store.save_asset(asset)
    store.update_generation_task(
        gen_task["task_id"],
        status="succeeded",
        provider_task_id=provider_task_id,
        output={"files": [_relative(folder, processed)] + saved},
        consumed_credits=credits,
    )
    store.create_cost_record(
        cost_record_from_task(
            provider="meshy",
            operation="rigging",
            asset_id=asset["asset_id"],
            job_id=job.get("job_id", ""),
            generation_task_id=gen_task["task_id"],
            provider_task_id=provider_task_id,
            consumed_credits=credits,
            category=asset.get("category", ""),
        )
    )


def _try_animate(settings, store, job, asset, folder: Path) -> None:
    actions_path = settings.pipeline_root / "config" / "meshy_actions.json"
    if not actions_path.is_file():
        return
    actions = load_meshy_actions(actions_path)
    clips = clip_set(actions)
    rig_task_id = str(((asset.get("generation_parameters") or {}).get("rigging") or {}).get("provider_task_id") or "")
    if not rig_task_id:
        return
    provider: MeshyProvider = meshy_from(settings)
    saved = list((asset.get("generation_parameters") or {}).get("animations") or [])
    # Rename / copy rig basic clips to stable shared names under processed/.
    for clip_key, meta in clips.items():
        basic = str(meta.get("from_rig_basic") or "")
        if not basic:
            continue
        source = folder / "processed" / f"{basic}.glb"
        if not source.is_file():
            # Older downloads used walking_glb.glb naming from URL key.
            alt = folder / "processed" / f"{basic}_url.glb"
            source = alt if alt.is_file() else source
        if not source.is_file():
            # walking_glb from walking_glb_url → walking_glb.glb
            candidates = list((folder / "processed").glob(f"*{basic.replace('_glb', '')}*.glb"))
            source = candidates[0] if candidates else source
        if source.is_file():
            shared = shared_clip_name(clip_key, meta)
            target = folder / "processed" / f"{shared}.glb"
            if source.resolve() != target.resolve():
                shutil.copy2(source, target)
            rel = _relative(folder, target)
            if rel not in saved:
                saved.append(rel)
    # Fetch optional Meshy action clips (e.g. idle).
    for clip_key, meta in clips.items():
        action_ids = meta.get("action_ids")
        if not action_ids:
            continue
        shared = shared_clip_name(clip_key, meta)
        target = folder / "processed" / f"{shared}.glb"
        if target.is_file():
            rel = _relative(folder, target)
            if rel not in saved:
                saved.append(rel)
            continue
        gen_task = store.create_generation_task(
            {
                "job_id": job.get("job_id", ""),
                "asset_id": asset["asset_id"],
                "provider": "meshy",
                "operation": "animation",
                "status": "animating",
                "input": {"rig_task_id": rig_task_id, "action_ids": action_ids, "clip": shared},
            }
        )
        try:
            result = provider.animate_model(
                {"rig_task_id": rig_task_id, "action_ids": action_ids},
                lambda message: store.asset_log(asset["asset_id"], message),
            )
            downloaded = provider.download_result("animation", result["provider_task_id"], folder / "processed" / f"anim_{shared}")
            files = downloaded.get("files") or []
            glb = next((Path(item) for item in files if str(item).lower().endswith(".glb")), None)
            if glb and Path(glb).is_file():
                shutil.copy2(glb, target)
                saved.append(_relative(folder, target))
            store.update_generation_task(
                gen_task["task_id"],
                status="succeeded",
                provider_task_id=result.get("provider_task_id", ""),
                output={"files": [_relative(folder, target)] if target.is_file() else []},
                consumed_credits=result.get("consumed_credits"),
            )
            store.create_cost_record(
                cost_record_from_task(
                    provider="meshy",
                    operation="animation",
                    asset_id=asset["asset_id"],
                    job_id=job.get("job_id", ""),
                    generation_task_id=gen_task["task_id"],
                    provider_task_id=result.get("provider_task_id", ""),
                    consumed_credits=result.get("consumed_credits"),
                    category=asset.get("category", ""),
                )
            )
        except (ProviderError, ConfigError, OSError, ValueError) as exc:
            message = redact(str(exc))
            store.update_generation_task(gen_task["task_id"], status="failed", error=message)
            if meta.get("optional", True):
                asset.setdefault("warnings", []).append(f"Optional animation '{shared}' skipped. {message}")
            else:
                asset.setdefault("warnings", []).append(f"Animation '{shared}' failed. {message}")
    # Normalize animation clip skeletons when possible.
    profile_path = settings.pipeline_root / "config" / "humanoid_skeleton.json"
    if profile_path.is_file():
        profile = load_skeleton_profile(profile_path)
        for rel in list(saved):
            path = folder / rel
            if not path.is_file():
                continue
            try:
                normalize_glb_skeleton(path, path, profile)
            except (OSError, ValueError, KeyError, json.JSONDecodeError):
                continue
    asset["generation_parameters"]["animations"] = list(dict.fromkeys(saved))
    asset["processed_files"] = list(
        dict.fromkeys(list(asset.get("processed_files") or []) + asset["generation_parameters"]["animations"])
    )
    store.save_asset(asset)


def _maybe_separate_clothing(settings, store, asset, folder: Path, processed: Path) -> None:
    slots_path = settings.pipeline_root / "config" / "clothing_slots.json"
    if not slots_path.is_file() or not processed.is_file():
        return
    slots = load_clothing_slots(slots_path)
    analysis = analyze_clothing_glb(processed, slots)
    asset["generation_parameters"]["clothing"] = {
        "slots": analysis.get("slots") or {},
        "equipment_slots": analysis.get("equipment_slots") or {},
        "unmatched_meshes": analysis.get("unmatched_meshes") or [],
        "missing_required": analysis.get("missing_required") or [],
    }
    equipment = analysis.get("equipment_slots") or {}
    if not equipment:
        store.save_asset(asset)
        return
    out_dir = folder / "processed" / "clothing"
    plan = clothing_export_plan(analysis, out_dir)
    body = ((analysis.get("slots") or {}).get("body") or {}).get("mesh_name") or "Body"
    note = separate_clothing_with_blender(
        settings,
        processed,
        plan,
        body,
        lambda message: store.asset_log(asset["asset_id"], message),
    )
    if note.get("skipped"):
        asset.setdefault("warnings", []).append(note.get("message") or "Clothing separation skipped.")
    elif not note.get("ok", False):
        asset.setdefault("warnings", []).append("Clothing separation failed. " + str(note.get("error") or ""))
    else:
        exported = []
        for item in note.get("exported") or []:
            path = Path(item.get("output") or "")
            if path.is_file():
                exported.append(_relative(folder, path))
        asset["generation_parameters"]["clothing"]["exported"] = exported
        asset["processed_files"] = list(dict.fromkeys(list(asset.get("processed_files") or []) + exported))
    store.save_asset(asset)


def _budget_preflight(settings, store, job, request) -> None:
    workshop = settings.workshop()
    budgets = workshop.get("budgets") or {}
    if not budgets:
        return
    pricing = load_pricing()
    estimate = 0.0
    ops = []
    if request.get("provider") == "openai":
        ops.append(("openai", "image_generation"))
    mesh = request.get("mesh_provider") or ""
    if mesh == "meshy":
        ops.append(("meshy", "image_to_3d"))
    elif mesh == "meshy_text":
        ops.append(("meshy", "text_to_3d_preview"))
    elif mesh == "tripo":
        ops.append(("tripo", "image_to_model"))
    if request.get("auto_rig") and request.get("humanoid"):
        ops.append(("meshy", "rigging"))
        if request.get("auto_animate"):
            ops.append(("meshy", "animation"))
    for provider, operation in ops:
        info = estimate_operation(pricing, provider, operation)
        if info.get("estimated_usd") is not None:
            estimate += float(info["estimated_usd"])
    gate = check_budget(
        budgets,
        records=store.list_cost_records(),
        estimated_usd=estimate,
        category=request.get("category") or "",
        workshop_category=request.get("workshop_category") or "",
    )
    job.setdefault("budget", gate)
    if gate.get("warnings"):
        job.setdefault("warnings", [])
        job["warnings"].extend(gate["warnings"])
    store.save_job(job)
    if gate.get("blocked"):
        raise PipelineError("; ".join(gate["warnings"]) or "Budget hard limit blocked this job.")


def _normalize_character_skeleton(settings, store, asset, folder: Path, processed: Path) -> None:
    profile_path = settings.pipeline_root / "config" / "humanoid_skeleton.json"
    if not profile_path.is_file():
        asset.setdefault("warnings", []).append("humanoid_skeleton.json is missing; skeleton normalize was skipped.")
        return
    profile = load_skeleton_profile(profile_path)
    normalized = folder / "processed" / "normalized.glb"
    try:
        result = normalize_glb_skeleton(processed, normalized, profile)
    except (OSError, ValueError, KeyError, json.JSONDecodeError) as exc:
        asset.setdefault("warnings", []).append("Skeleton normalize failed. Keeping the rigged GLB. " + redact(str(exc)))
        return
    if normalized.is_file():
        shutil.copy2(normalized, processed)
        asset["generation_parameters"]["skeleton"] = {
            "profile": profile.get("profile", "godot_humanoid"),
            "renamed_bones": result.get("renamed_bones", 0),
            "renames": result.get("renames", {}),
            "missing_required": result.get("missing_required", []),
            "clip_renames": result.get("clip_renames", {}),
        }
        if result.get("missing_required"):
            asset.setdefault("warnings", []).append(
                "Skeleton normalize still missing required bones: " + ", ".join(result["missing_required"])
            )
        else:
            # Drop the older Godot-name warning if bones now match.
            asset["warnings"] = [
                warning
                for warning in asset.get("warnings", [])
                if "Godot humanoid bone names" not in warning
            ]
        asset["processed_files"] = list(dict.fromkeys(list(asset.get("processed_files") or []) + [_relative(folder, normalized), _relative(folder, processed)]))
        store.save_asset(asset)
        store.asset_log(asset["asset_id"], f"Skeleton normalize renamed {result.get('renamed_bones', 0)} bones.")


def _validate_and_ready(store, asset, glb_path: Path, expect_collision: bool, humanoid: bool | None = None) -> None:
    params = asset.get("generation_parameters") or {}
    if humanoid is None:
        humanoid = bool(params.get("humanoid", asset.get("kind") == "character"))
    validate_kind = "character" if humanoid else "prop"
    validation = validate_mesh(glb_path, validate_kind, expect_collision)
    report = validation.get("report") or {}
    asset["polygon_count"] = report.get("triangles")
    if report.get("bounds"):
        asset["dimensions"] = {
            "min": report["bounds"][0],
            "max": report["bounds"][1],
            "size": [report["bounds"][1][i] - report["bounds"][0][i] for i in range(3)],
        }
    warnings = list(asset.get("warnings", [])) + list(validation.get("warnings") or [])
    validation["warnings"] = warnings
    asset["validation"] = {"ok": validation["ok"], "errors": validation["errors"], "warnings": warnings}
    asset["warnings"] = warnings
    asset["errors"] = validation["errors"]
    if humanoid and not validation["ok"]:
        asset["manual_steps"] = list(dict.fromkeys(list(asset.get("manual_steps", [])) + MANUAL_RIG_STEPS))
    asset["processing_status"] = "ready_for_review"
    asset["history"].append(_snapshot(asset, "processed"))
    store.save_asset(asset)


def _finish_job(store, job) -> None:
    assets = []
    for asset_id in job.get("asset_ids", []):
        try:
            assets.append(store.get_asset(asset_id))
        except KeyError:
            continue
    ready = [asset for asset in assets if asset.get("processing_status") in {"ready_for_review", "approved"}]
    if ready:
        job["status"] = "ready_for_review"
        job["message"] = f"{len(ready)} asset(s) ready for review."
    else:
        job["status"] = "failed"
        job["message"] = job["errors"][-1] if job.get("errors") else "Generation failed."
    store.save_job(job)


def _refresh_job_approval(store, job_id: str) -> None:
    if not job_id:
        return
    try:
        job = store.get_job(job_id)
    except KeyError:
        return
    assets = []
    for asset_id in job.get("asset_ids", []):
        try:
            assets.append(store.get_asset(asset_id))
        except KeyError:
            return
    if assets and all(asset.get("approval_status") == "approved" for asset in assets):
        job["status"] = "approved"
        job["message"] = "Every asset in this job is approved."
        store.save_job(job)


def preview_prompt(settings: Settings, payload: dict) -> dict:
    request = normalize_request(settings, payload)
    return {"prompt": _prompts(settings, request)["provider_prompt"]}


def _prompts(settings: Settings, request: dict) -> dict:
    override = request.get("prompt_override") or ""
    if override:
        return {
            "prompt": override,
            "negative_prompt": "",
            "provider_prompt": override,
            "compact_prompt": override[:800],
            "prompt_truncated": len(override) > 800,
        }
    preset = preset_for(settings, request["kind"] if request["implementation"] != "procedural_kit" else "building", request["category"])
    subject = request.get("subject_override") or ""
    if subject:
        preset = dict(preset)
        preset["prompt"] = subject
    prompt_kind = request["kind"]
    if prompt_kind in {"deployable", "resource", "decoration"}:
        prompt_kind = "prop"
    elif prompt_kind == "enemy":
        prompt_kind = "character" if request.get("humanoid") else "prop"
    prompts = build_prompts(
        settings.style(),
        preset,
        request["prompt"],
        prompt_kind,
        request.get("customization"),
        settings.style_reference().is_file(),
        firearm=bool(request.get("firearm")) or is_firearm(
            request.get("name", ""),
            request.get("prompt", ""),
            request.get("subject_override", ""),
            icon_category=request.get("icon_category", ""),
        ),
    )
    return _with_real_size(prompts, request)


def _meshy_auto_size(request: dict) -> bool:
    """Deployables ask Meshy to scale the mesh to a real-world height."""
    return request.get("kind") == "deployable" and not bool(request.get("humanoid"))


def _size_clause(size) -> str:
    if not size or len(size) != 3:
        return ""
    return (
        f"Real size {float(size[0]):.2f} m wide, {float(size[1]):.2f} m tall, "
        f"{float(size[2]):.2f} m deep. Keep those proportions."
    )


def _with_real_size(prompts: dict, request: dict) -> dict:
    clause = "" if request.get("humanoid") else _size_clause(request.get("target_size"))
    if not clause:
        return prompts
    updated = dict(prompts)
    updated["prompt"] = f"{clause} {prompts['prompt']}"
    updated["provider_prompt"] = f"{clause} {prompts['provider_prompt']}"
    compact = f"{clause} {prompts['compact_prompt']}"
    sent = compact if len(compact) <= 800 else compact[:797].rsplit(" ", 1)[0]
    updated["compact_prompt"] = sent
    updated["prompt_truncated"] = sent != compact
    return updated


def _palette_colors(style: dict, names: list[str]) -> list[str]:
    palette = style.get("palette", {})
    colors = [palette[name] for name in names if name in palette]
    return colors or list(palette.values())


def _checked_references(settings: Settings, raw) -> list[str]:
    if not raw:
        return []
    if not isinstance(raw, list):
        raise PipelineError("Reference images must be a list.")
    if len(raw) > 16:
        raise PipelineError("A prompt can include at most 16 reference images.")
    paths = []
    for item in raw:
        path = _checked_source(settings, str(item or ""))
        if not path:
            continue
        if Path(path).suffix.lower() not in {".png", ".jpg", ".jpeg", ".webp"}:
            raise PipelineError("Reference images must be PNG, JPEG, or WEBP.")
        paths.append(path)
    return paths


def _reference_pngs(paths: list[str]) -> list[tuple[str, bytes]]:
    images = []
    for path in paths:
        source = Path(path)
        try:
            with Image.open(source) as image:
                image.load()
                converted = image.convert("RGBA")
                if max(converted.size) > 2048:
                    converted.thumbnail((2048, 2048), Image.Resampling.LANCZOS)
                buffer = io.BytesIO()
                converted.save(buffer, format="PNG")
        except OSError as exc:
            raise PipelineError(f"{source.name} is not a readable image.") from exc
        images.append((f"{source.stem}.png", buffer.getvalue()))
    return images


def _is_generic_pickup_size(size: list[float] | None) -> bool:
    if not size:
        return True
    return all(abs(float(size[index]) - GENERIC_PICKUP_SIZE[index]) < 0.001 for index in range(3))


def _target_size(value) -> list[float] | None:
    if value is None or value == "":
        return None
    if not isinstance(value, (list, tuple)) or len(value) != 3:
        raise PipelineError("target_size must be [width, height, depth] in meters.")
    try:
        size = [float(value[0]), float(value[1]), float(value[2])]
    except (TypeError, ValueError) as exc:
        raise PipelineError("target_size values must be numbers.") from exc
    if any(axis <= 0.01 or axis > 50.0 for axis in size):
        raise PipelineError("Each target_size axis must be between 0.01 m and 50 m.")
    return [round(axis, 4) for axis in size]


def stage_item_icon(settings: Settings, item_id: str) -> dict:
    """Copy assets/icons/<id>.* into library/uploads so Meshy can use it as concept."""
    from godot.item_index import art_path, safe_item_id

    try:
        token = safe_item_id(item_id)
    except ValueError as exc:
        raise PipelineError(str(exc)) from None
    source = art_path(settings.project_root, token)
    if source is None:
        raise PipelineError(f"No inventory icon at assets/icons/{token}.png. Make the icon first.")
    uploads = settings.library_dir / "uploads"
    uploads.mkdir(parents=True, exist_ok=True)
    destination = uploads / f"{uuid.uuid4().hex}{source.suffix.lower()}"
    shutil.copy2(source, destination)
    return {"path": str(destination.resolve()), "item_id": token, "source": source.name}


def _checked_source(settings: Settings, text: str) -> str:
    if not text:
        return ""
    path = Path(text).resolve()
    root = (settings.library_dir / "uploads").resolve()
    root.mkdir(parents=True, exist_ok=True)
    if path != root and root not in path.parents:
        raise PipelineError("Source files must be uploaded through the dashboard.")
    if not path.is_file():
        raise PipelineError("The uploaded source file is missing.")
    return str(path)


def _mark_latest_failed(store: AssetStore, job: dict, message: str) -> None:
    job.setdefault("errors", []).append(message)
    if job.get("asset_ids"):
        try:
            asset = store.get_asset(job["asset_ids"][-1])
        except KeyError:
            asset = None
        if asset and asset.get("processing_status") not in {"ready_for_review", "approved"}:
            asset["processing_status"] = "failed"
            asset.setdefault("errors", []).append(message)
            store.save_asset(asset)
    store.save_job(job)


def _relative(folder: Path, path: Path) -> str:
    return path.resolve().relative_to(folder.resolve()).as_posix()
