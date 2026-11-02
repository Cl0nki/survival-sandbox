import json
import shutil
from pathlib import Path

from core.errors import PipelineError

KIND_FOLDERS = {
    "texture": "textures",
    "prop": "props",
    "character": "characters",
    "building": "buildings",
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
        write_scene(target_scene, name, target_glb, project_root)
        produced.append(str(target_glb.relative_to(project_root)).replace("\\", "/"))
        produced.append(str(target_scene.relative_to(project_root)).replace("\\", "/"))
        for extra_name in ("lod1.glb", "lod2.glb"):
            extra = glb_source.parent / extra_name
            if extra.is_file():
                extra_target = destination_dir / f"{name}_{extra_name}"
                shutil.copy2(extra, extra_target)
                produced.append(str(extra_target.relative_to(project_root)).replace("\\", "/"))

    record = dict(asset)
    record["approval_status"] = "approved"
    record["production_files"] = produced
    meta_path.write_text(json.dumps(record, indent=2), encoding="utf-8")
    produced.append(str(meta_path.relative_to(project_root)).replace("\\", "/"))
    return {"files": produced, "metadata": str(meta_path)}


def _first_existing(asset_dir: Path, relative_files: list[str], suffix: str) -> Path | None:
    for relative in relative_files:
        candidate = asset_dir / relative
        if candidate.is_file() and candidate.suffix.lower() == suffix:
            return candidate
    matches = sorted((asset_dir / "processed").glob(f"*{suffix}"))
    return matches[0] if matches else None
