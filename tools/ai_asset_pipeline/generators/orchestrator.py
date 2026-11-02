import io
import re
import shutil
from pathlib import Path

from PIL import Image

from blender.runner import process_with_blender
from core.errors import ConfigError, PipelineError, ProviderError
from core.redact import redact
from core.settings import Settings
from core.store import AssetStore, _snapshot
from generators.modular import PIECE_META, build_piece, kit_piece_ids
from godot.publish import publish_asset
from processors.gltf_write import write_glb
from processors.icons import procedural_icon
from processors.maps import derive_maps, procedural_maps, save_maps, seam_score, tiled_preview
from processors.validate import MANUAL_RIG_STEPS, validate_mesh, validate_texture
from prompts.builder import build_prompts
from providers.http_client import download
from providers.meshy import MeshyProvider, glb_url
from providers.registry import meshy_from, openai_from, tripo_from
from providers.tripo import model_url, rendered_image_url

SECTION = {
    "texture": "textures",
    "prop": "props",
    "character": "characters",
    "building": "buildings",
}


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
    kind = payload.get("kind", "")
    if kind not in SECTION:
        raise PipelineError("Kind must be texture, prop, character, or building.")
    category = str(payload.get("category", "")).strip()
    preset = preset_for(settings, kind, category)
    name = safe_name(str(payload.get("name", "")))
    variations = int(payload.get("variations", settings.defaults["variations"]))
    if variations < 1 or variations > int(settings.defaults["max_variations"]):
        raise PipelineError(f"Variations must be from 1 to {settings.defaults['max_variations']}.")
    resolution = int(payload.get("resolution", settings.defaults["resolution"]))
    allowed = [int(item) for item in settings.defaults["allowed_resolutions"]]
    if resolution not in allowed:
        raise PipelineError(f"Resolution must be one of {allowed}.")
    polycount = int(payload.get("polycount", settings.defaults["character_polycount" if kind == "character" else "polycount"]))
    if polycount < 100 or polycount > 250000:
        raise PipelineError("Polygon count must be between 100 and 250000.")
    seed = payload.get("seed")
    if seed is not None and seed != "":
        seed = int(seed)
    else:
        seed = None
    provider = str(payload.get("provider") or "").strip()
    mesh_provider = str(payload.get("mesh_provider") or "").strip()
    implementation = preset.get("implementation")
    if implementation in {"procedural", "procedural_kit"}:
        provider = "procedural"
        mesh_provider = ""
    elif kind == "texture":
        provider = provider or "procedural"
        if provider not in {"procedural", "openai", "manual"}:
            raise PipelineError("Texture provider must be procedural, openai, or manual.")
    else:
        provider = provider or "openai"
        mesh_provider = mesh_provider or "meshy"
        if mesh_provider not in {"meshy", "tripo", "meshy_text"}:
            raise PipelineError("Mesh provider must be meshy, tripo, or meshy_text.")
        if provider not in {"openai", "manual"} and mesh_provider != "meshy_text":
            raise PipelineError("Prop and character jobs need an image provider, or meshy_text for Meshy text-to-3D.")
    quality = str(payload.get("quality") or settings.defaults["openai_quality"])
    customization = payload.get("customization") if kind == "character" else {}
    if customization is None:
        customization = {}
    if not isinstance(customization, dict):
        raise PipelineError("Customization must be an object of labels.")
    return {
        "kind": kind,
        "category": category,
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
        "auto_rig": bool(payload.get("auto_rig", kind == "character")),
        "source_file": _checked_source(settings, str(payload.get("source_file") or "")),
        "reference_images": _checked_references(settings, payload.get("reference_images")),
        "icon_category": _icon_category(payload.get("icon_category")),
        "swatch": _swatch(payload.get("swatch")),
        "implementation": implementation,
        "godot_folder": preset.get("godot_folder", "props"),
        "procedural_piece": preset.get("procedural_piece"),
    }


def execute_job(settings: Settings, store: AssetStore, job: dict) -> None:
    request = normalize_request(settings, job["request"])
    job["request"] = request
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
    _validate_and_ready(store, asset, target, expect_collision=asset["kind"] == "building")
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
            "provider": request["mesh_provider"],
            "model": "",
            "prompt": prompts["prompt"],
            "negative_prompt": prompts["negative_prompt"],
            "seed": request["seed"],
            "seed_supported": request["mesh_provider"] == "tripo" and request["seed"] is not None,
            "generation_parameters": {
                "sent_prompt": prompts["compact_prompt"] if request["mesh_provider"] == "meshy_text" else prompts["provider_prompt"],
                "prompt_truncated": prompts["prompt_truncated"],
                "godot_folder": preset.get("godot_folder", "props"),
                "polycount": request["polycount"],
                "customization": request["customization"],
                "variation": index,
                "image_provider": request["provider"],
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
    job["status"] = "downloading"
    job["message"] = f"Generating the mesh for {name}."
    store.save_job(job)
    if request["mesh_provider"] == "meshy":
        provider = meshy_from(settings)
        result = provider.image_to_3d(
            concept,
            request["polycount"],
            settings.defaults["meshy_texture_resolution"],
            request["kind"] == "character",
            lambda message: store.asset_log(asset["asset_id"], message),
        )
        _store_meshy_download(store, asset, folder, result)
    elif request["mesh_provider"] == "meshy_text":
        provider = meshy_from(settings)
        result = provider.text_to_3d(
            prompts["compact_prompt"],
            request["polycount"],
            request["kind"] == "character",
            lambda message: store.asset_log(asset["asset_id"], message),
        )
        asset["provider"] = "meshy"
        _store_meshy_download(store, asset, folder, result)
    elif request["mesh_provider"] == "tripo":
        provider = tripo_from(settings)
        result = provider.image_to_3d(
            concept,
            request["polycount"],
            request["seed"],
            lambda message: store.asset_log(asset["asset_id"], message),
        )
        _store_tripo_download(store, asset, folder, result)
    else:
        raise PipelineError(f"Unsupported mesh provider {request['mesh_provider']}.")
    original = folder / "original" / "model.glb"
    if not original.is_file():
        raise ProviderError("The mesh provider finished without a local GLB.")
    processed = folder / "processed" / f"{name}.glb"
    asset["processing_status"] = "processing"
    store.save_asset(asset)
    job["status"] = "processing"
    job["message"] = f"Processing {name}."
    store.save_job(job)
    if request["kind"] == "character" and request["auto_rig"] and settings.meshy_key:
        _try_rig(settings, store, asset, folder, original, processed)
    else:
        if request["kind"] == "character":
            asset["manual_steps"] = list(MANUAL_RIG_STEPS)
            asset.setdefault("warnings", []).append(
                "Automatic rigging did not run. Meshy rigging requires MESHY_API_KEY. Use the manual Blender steps on this asset."
            )
        shutil.copy2(original, processed)
    note = process_with_blender(
        settings,
        processed if processed.is_file() else original,
        processed,
        request["polycount"],
        list(settings.defaults["lod_ratios"]) if settings.blender_bin else [],
        lambda message: store.asset_log(asset["asset_id"], message),
    )
    if note.get("skipped"):
        if not processed.is_file():
            shutil.copy2(original, processed)
        asset.setdefault("warnings", []).append(note["message"])
    elif not note.get("ok", False):
        if not processed.is_file():
            shutil.copy2(original, processed)
        asset.setdefault("warnings", []).append("Blender processing failed. The downloaded model was kept. " + note.get("error", ""))
    asset["processed_files"] = [_relative(folder, processed)]
    for lod in note.get("lod_files") or []:
        asset["processed_files"].append(_relative(folder, Path(lod)))
    _validate_and_ready(store, asset, processed, expect_collision=request["kind"] != "character")


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


def _store_meshy_download(store, asset, folder, result) -> None:
    task = result["task"]
    asset["model"] = result["model"]
    asset["generation_parameters"]["provider_parameters"] = result["parameters"]
    asset["generation_parameters"]["provider_task_id"] = task.get("id", "")
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


def _store_tripo_download(store, asset, folder, result) -> None:
    task = result["task"]
    asset["model"] = result["model"]
    asset["generation_parameters"]["provider_parameters"] = result["parameters"]
    asset["generation_parameters"]["provider_task_id"] = task.get("task_id", "")
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


def _try_rig(settings, store, asset, folder, original: Path, processed: Path) -> None:
    provider: MeshyProvider = meshy_from(settings)
    try:
        result = provider.rig(
            original,
            float(settings.style().get("character_height_m", settings.defaults["character_height_m"])),
            lambda message: store.asset_log(asset["asset_id"], message),
        )
    except (ProviderError, ConfigError, OSError) as exc:
        shutil.copy2(original, processed)
        asset["manual_steps"] = list(MANUAL_RIG_STEPS)
        asset.setdefault("warnings", []).append("Meshy rigging failed. The unrigged model was kept. " + redact(str(exc)))
        return
    task = result["task"]
    rigged = (task.get("result") or {}).get("rigged_character_glb_url")
    if not rigged:
        shutil.copy2(original, processed)
        asset["manual_steps"] = list(MANUAL_RIG_STEPS)
        asset.setdefault("warnings", []).append("Meshy rigging finished without a rigged GLB URL.")
        return
    rigged_path = folder / "processed" / "rigged.glb"
    rigged_path.write_bytes(download(rigged))
    shutil.copy2(rigged_path, processed)
    animations = (task.get("result") or {}).get("basic_animations") or {}
    saved = []
    for key in ("walking_glb_url", "running_glb_url"):
        if animations.get(key):
            target = folder / "processed" / f"{key.replace('_url', '')}.glb"
            target.write_bytes(download(animations[key]))
            saved.append(_relative(folder, target))
    asset["generation_parameters"]["rigging"] = {"provider": "meshy", "animations": saved}
    asset["processed_files"] = [_relative(folder, processed)] + saved
    store.save_asset(asset)


def _validate_and_ready(store, asset, glb_path: Path, expect_collision: bool) -> None:
    validation = validate_mesh(glb_path, asset["kind"], expect_collision)
    report = validation.get("report") or {}
    asset["polygon_count"] = report.get("triangles")
    warnings = list(asset.get("warnings", [])) + list(validation.get("warnings") or [])
    validation["warnings"] = warnings
    asset["validation"] = {"ok": validation["ok"], "errors": validation["errors"], "warnings": warnings}
    asset["warnings"] = warnings
    asset["errors"] = validation["errors"]
    if asset["kind"] == "character" and not validation["ok"]:
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
    return build_prompts(
        settings.style(),
        preset,
        request["prompt"],
        request["kind"],
        request.get("customization"),
        settings.style_reference().is_file(),
    )


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
