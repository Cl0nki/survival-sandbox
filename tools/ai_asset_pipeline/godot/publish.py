import json
import shutil
from pathlib import Path

from core.errors import PipelineError
from core.settings import PIPELINE_ROOT
from godot.animation_library import (
    load_meshy_actions,
    resolve_shared_library,
    shared_clip_name,
    update_library_index,
    write_quaternius_library_index,
)
from godot.character_template import write_character_scene, write_shared_skeleton_note
from godot.retarget_import import write_character_glb_import, write_quaternius_animation_import, write_static_glb_import
from processors.clothing import analyze_clothing_glb, load_clothing_slots

KIND_FOLDERS = {
    "texture": "textures",
    "prop": "props",
    "character": "characters",
    "building": "buildings",
    "deployable": "deployables",
    "resource": "resources",
    "decoration": "environment",
    "enemy": "characters",
}


def res_path(project_root: Path, file_path: Path) -> str:
    relative = file_path.resolve().relative_to(project_root.resolve()).as_posix()
    return f"res://{relative}"


def write_material(path: Path, maps: dict[str, Path], project_root: Path, roughness: float, metallic: float, color: tuple[float, float, float] | None = None) -> None:
    resources = []
    ids = {}
    order = [("albedo", "albedo"), ("normal", "normal"), ("roughness", "roughness"), ("ao", "ao"), ("metallic", "metallic"), ("height", "height")]
    for key, _label in order:
        texture = maps.get(key)
        if texture and Path(texture).is_file():
            slot = f"{len(resources) + 1}_{key[:3]}"
            ids[key] = slot
            resources.append(f'[ext_resource type="Texture2D" path="{res_path(project_root, Path(texture))}" id="{slot}"]')
    lines = [f'[gd_resource type="StandardMaterial3D" load_steps={len(resources) + 1} format=3]', ""]
    lines.extend(resources)
    lines.append("")
    lines.append("[resource]")
    if color is not None and "albedo" not in ids:
        lines.append(f"albedo_color = Color({color[0]:.4f}, {color[1]:.4f}, {color[2]:.4f}, 1)")
    if "albedo" in ids:
        lines.append(f'albedo_texture = ExtResource("{ids["albedo"]}")')
    if "normal" in ids:
        lines.append("normal_enabled = true")
        lines.append(f'normal_texture = ExtResource("{ids["normal"]}")')
    if "roughness" in ids:
        lines.append(f'roughness_texture = ExtResource("{ids["roughness"]}")')
        lines.append("roughness_texture_channel = 0")
    lines.append(f"roughness = {roughness:.3f}")
    if "metallic" in ids:
        lines.append(f'metallic_texture = ExtResource("{ids["metallic"]}")')
        lines.append("metallic_texture_channel = 0")
    lines.append(f"metallic = {metallic:.3f}")
    if "ao" in ids:
        lines.append("ao_enabled = true")
        lines.append(f'ao_texture = ExtResource("{ids["ao"]}")')
        lines.append("ao_texture_channel = 0")
    if "height" in ids:
        lines.append("heightmap_enabled = true")
        lines.append(f'heightmap_texture = ExtResource("{ids["height"]}")')
        lines.append("heightmap_scale = 0.04")
    lines.append("texture_filter = 5")
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def write_scene(path: Path, node_name: str, glb_path: Path, project_root: Path) -> None:
    scene = "\n".join(
        [
            "[gd_scene load_steps=2 format=3]",
            "",
            f'[ext_resource type="PackedScene" path="{res_path(project_root, glb_path)}" id="1_model"]',
            "",
            f'[node name="{node_name}" type="Node3D"]',
            "",
            '[node name="Model" parent="." instance=ExtResource("1_model")]',
            "",
        ]
    )
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(scene, encoding="utf-8")


def _refuse_existing(path: Path, meta_path: Path, force: bool, confirm_approved: bool) -> None:
    if not path.exists():
        return
    approved = False
    if meta_path.is_file():
        try:
            approved = json.loads(meta_path.read_text(encoding="utf-8")).get("approval_status") == "approved"
        except json.JSONDecodeError:
            approved = False
    if approved and not confirm_approved:
        raise PipelineError(
            f"{path.name} is already approved. Pass confirm_overwrite_approved to replace it."
        )
    if not force and not confirm_approved:
        raise PipelineError(f"{path} already exists. Pass force to replace a file that is not approved.")


def publish_asset(project_root: Path, asset: dict, library_root: Path, acknowledge: bool = False, force: bool = False, confirm_approved: bool = False) -> dict:
    validation = asset.get("validation") or {}
    if validation and not validation.get("ok", False):
        if not acknowledge:
            problems = "; ".join(validation.get("errors") or ["validation failed"])
            raise PipelineError(f"Asset failed validation and was not copied into the project. {problems}")
    asset_dir = library_root / "assets" / asset["asset_id"]
    folder_name = (asset.get("generation_parameters") or {}).get("godot_folder") or KIND_FOLDERS.get(asset["kind"], "props")
    name = asset["asset_name"]
    destination_dir = project_root / "assets" / folder_name
    meta_dir = project_root / "assets" / "pipeline_meta"
    meta_dir.mkdir(parents=True, exist_ok=True)
    (meta_dir / ".gdignore").write_text("", encoding="utf-8")
    meta_path = meta_dir / f"{name}.json"
    produced = []

    if asset["kind"] == "texture":
        source = asset_dir / "processed"
        maps = {}
        for map_name in ("albedo", "normal", "roughness", "ao", "metallic", "height"):
            candidate = source / f"{map_name}.png"
            if candidate.is_file():
                maps[map_name] = candidate
        if "albedo" not in maps:
            raise PipelineError("Texture asset has no processed albedo.")
        target_dir = destination_dir / name
        _refuse_existing(target_dir / "albedo.png", meta_path, force, confirm_approved)
        target_dir.mkdir(parents=True, exist_ok=True)
        copied = {}
        for map_name, source_path in maps.items():
            target = target_dir / f"{map_name}.png"
            shutil.copy2(source_path, target)
            copied[map_name] = target
            produced.append(str(target.relative_to(project_root)).replace("\\", "/"))
        preview = asset_dir / "preview" / "tiled.png"
        if preview.is_file():
            shutil.copy2(preview, target_dir / "preview_tiled.png")
            produced.append(str((target_dir / "preview_tiled.png").relative_to(project_root)).replace("\\", "/"))
        material_path = project_root / "assets" / "materials" / f"{name}.tres"
        _refuse_existing(material_path, meta_path, force, confirm_approved)
        params = asset.get("generation_parameters") or {}
        write_material(
            material_path,
            copied,
            project_root,
            float(params.get("roughness", 0.8)),
            float(params.get("metallic", 0.0)),
        )
        produced.append(str(material_path.relative_to(project_root)).replace("\\", "/"))
        if asset.get("category") == "item_icon":
            icon_path = project_root / "assets" / "icons" / f"{name}.png"
            _refuse_existing(icon_path, meta_path, force, confirm_approved)
            icon_path.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(copied["albedo"], icon_path)
            produced.append(str(icon_path.relative_to(project_root)).replace("\\", "/"))
    else:
        glb_source = _first_existing(asset_dir, asset.get("processed_files") or [], ".glb")
        if glb_source is None:
            raise PipelineError("Mesh asset has no processed GLB.")
        target_glb = destination_dir / f"{name}.glb"
        target_scene = destination_dir / f"{name}.tscn"
        _refuse_existing(target_glb, meta_path, force, confirm_approved)
        _refuse_existing(target_scene, meta_path, force, confirm_approved)
        destination_dir.mkdir(parents=True, exist_ok=True)
        shutil.copy2(glb_source, target_glb)
        humanoid = bool((asset.get("generation_parameters") or {}).get("humanoid", asset["kind"] == "character"))
        if humanoid and asset["kind"] in {"character", "enemy"}:
            profile_path = PIPELINE_ROOT / "config" / "humanoid_skeleton.json"
            profile = json.loads(profile_path.read_text(encoding="utf-8")) if profile_path.is_file() else {}
            actions_path = PIPELINE_ROOT / "config" / "meshy_actions.json"
            actions = load_meshy_actions(actions_path) if actions_path.is_file() else {}
            clothing_path = PIPELINE_ROOT / "config" / "clothing_slots.json"
            equipment_slots = {}
            if clothing_path.is_file():
                clothing = analyze_clothing_glb(glb_source, load_clothing_slots(clothing_path))
                equipment_slots = clothing.get("equipment_slots") or {}
            shared_dir = project_root / "assets" / "characters" / "Shared"
            write_shared_skeleton_note(shared_dir / "skeleton_profile.json", profile)
            produced.append(str((shared_dir / "skeleton_profile.json").relative_to(project_root)).replace("\\", "/"))
            shared = resolve_shared_library(project_root)
            anim_dir = shared_dir / "Animations"
            anim_dir.mkdir(parents=True, exist_ok=True)
            # Meshy clips stay as optional provenance under Animations/; Quaternius is the default Shared library.
            clip_map = _publish_shared_animations(
                asset_dir,
                asset,
                anim_dir,
                actions,
                project_root,
                produced,
            )
            if shared:
                for logical, anim_name in (shared.get("clips") or {}).items():
                    clip_map[logical] = {
                        "path": shared["relative"],
                        "animation": anim_name,
                        "source": "quaternius",
                        "provider": "quaternius",
                    }
                bone_map = project_root / (shared.get("bone_map") or "assets/characters/Shared/Quaternius/QuaterniusBoneMap.tres")
                source_glb = project_root / (
                    (shared.get("config") or {}).get("source_glb")
                    or "assets/characters/Shared/Quaternius/AnimationLibrary_Godot_Standard.glb"
                )
                if source_glb.is_file():
                    write_quaternius_animation_import(source_glb, bone_map, project_root)
                write_quaternius_library_index(project_root, shared)
            else:
                update_library_index(
                    shared_dir / "library_index.json",
                    clip_map,
                    skeleton_profile=profile.get("profile", "godot_humanoid"),
                )
            write_character_scene(
                target_scene,
                name,
                target_glb,
                project_root,
                profile,
                actions=actions,
                clip_names=list(clip_map.keys()) or list((shared or {}).get("logical_names") or []),
                equipment_slots=equipment_slots,
                shared_library=shared,
            )
            char_bone = project_root / (
                (shared or {}).get("character_bone_map") or "assets/characters/Shared/GodotHumanoidBoneMap.tres"
            )
            write_character_glb_import(
                target_glb,
                char_bone,
                fix_silhouette=bool((shared or {}).get("fix_silhouette", True)),
                project_root=project_root,
            )
            produced.append(str((shared_dir / "library_index.json").relative_to(project_root)).replace("\\", "/"))
        else:
            write_scene(target_scene, name, target_glb, project_root)
            write_static_glb_import(target_glb, project_root)
        produced.append(str(target_glb.relative_to(project_root)).replace("\\", "/"))
        produced.append(str(target_scene.relative_to(project_root)).replace("\\", "/"))
        for extra_name in ("lod1.glb", "lod2.glb"):
            extra = glb_source.parent / extra_name
            if extra.is_file():
                extra_target = destination_dir / f"{name}_{extra_name}"
                shutil.copy2(extra, extra_target)
                write_static_glb_import(extra_target, project_root)
                produced.append(str(extra_target.relative_to(project_root)).replace("\\", "/"))

    record = dict(asset)
    record["approval_status"] = "approved"
    record["production_files"] = produced
    meta_path.write_text(json.dumps(record, indent=2), encoding="utf-8")
    produced.append(str(meta_path.relative_to(project_root)).replace("\\", "/"))
    return {"files": produced, "metadata": str(meta_path)}


def _is_animation_glb(name: str) -> bool:
    lowered = name.lower()
    return any(token in lowered for token in ("walking", "running", "idle", "walk.glb", "run.glb", "animation", "lod"))


def _first_existing(asset_dir: Path, relative_files: list[str], suffix: str) -> Path | None:
    for relative in relative_files:
        candidate = asset_dir / relative
        if candidate.is_file() and candidate.suffix.lower() == suffix and not _is_animation_glb(Path(relative).name):
            return candidate
    for relative in relative_files:
        candidate = asset_dir / relative
        if candidate.is_file() and candidate.suffix.lower() == suffix:
            return candidate
    matches = sorted((asset_dir / "processed").glob(f"*{suffix}"))
    preferred = [path for path in matches if not _is_animation_glb(path.name)]
    if preferred:
        # Prefer normalized/rigged/named mesh over random extras.
        for hint in ("normalized.glb", "rigged.glb", "model.glb"):
            for path in preferred:
                if path.name.lower() == hint:
                    return path
        return preferred[0]
    return matches[0] if matches else None


def _clip_key_from_filename(filename: str, actions: dict) -> str | None:
    lowered = filename.lower()
    clips = ((actions.get("sets") or {}).get(actions.get("default_set") or "") or {}).get("clips") or {}
    for key, meta in clips.items():
        shared = shared_clip_name(key, meta).lower()
        basic = str(meta.get("from_rig_basic") or "").lower()
        if shared and shared in lowered:
            return key
        if basic and basic.replace("_glb", "") in lowered:
            return key
        if key in lowered:
            return key
    for token, key in (("walking", "walk"), ("running", "run"), ("idle", "idle"), ("walk", "walk"), ("run", "run")):
        if token in lowered:
            return key
    return None


def _publish_shared_animations(
    asset_dir: Path,
    asset: dict,
    anim_dir: Path,
    actions: dict,
    project_root: Path,
    produced: list[str],
) -> dict:
    clip_map: dict[str, dict] = {}
    params = asset.get("generation_parameters") or {}
    relatives = list(asset.get("processed_files") or [])
    for relative in list(params.get("animations") or []):
        if relative not in relatives:
            relatives.append(relative)
    for relative in relatives:
        if not str(relative).endswith(".glb"):
            continue
        source = asset_dir / relative
        if not source.is_file():
            continue
        key = _clip_key_from_filename(Path(relative).name, actions)
        if not key:
            continue
        clips = ((actions.get("sets") or {}).get(actions.get("default_set") or "") or {}).get("clips") or {}
        shared = shared_clip_name(key, clips.get(key) or {})
        target = anim_dir / f"{shared}.glb"
        shutil.copy2(source, target)
        # Also keep a per-asset copy for debugging provenance.
        provenance = anim_dir / f"{asset['asset_name']}_{Path(relative).name}"
        shutil.copy2(source, provenance)
        rel_target = str(target.relative_to(project_root)).replace("\\", "/")
        rel_prov = str(provenance.relative_to(project_root)).replace("\\", "/")
        produced.extend([rel_target, rel_prov])
        clip_map[shared] = {
            "path": rel_target,
            "source": "meshy",
            "asset_id": asset.get("asset_id", ""),
            "asset_name": asset.get("asset_name", ""),
            "provenance": rel_prov,
        }
    return clip_map
