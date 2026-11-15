"""Read the Godot item catalog for the art gallery.

Icons in the game are drawn by scripts/items/item_icons.gd from each item's
swatch. A finished picture belongs at assets/icons/<id>.png.

World meshes for the Ingame tab land at assets/deployables/<id>.glb (placed
stations), assets/props/<id>.glb (ground pickups) or assets/resources/<id>.glb
(world props from resources/world_props: trees, boulders, wrecks, crates).
World props are rows in the same gallery with category "world_prop". Their
target_size is the body_size in the definition file.
"""

from __future__ import annotations

import re
from pathlib import Path

from godot.deployable_dimensions import dimensions_for, load_dimensions, target_size_for_item

_ASSIGN = re.compile(r"^([A-Za-z0-9_]+)\s*=\s*(.+)$")
_COLOR = re.compile(r"Color\(\s*([0-9.]+)\s*,\s*([0-9.]+)\s*,\s*([0-9.]+)\s*,\s*([0-9.]+)\s*\)")
_VECTOR3 = re.compile(r"Vector3\(\s*([0-9.]+)\s*,\s*([0-9.]+)\s*,\s*([0-9.]+)\s*\)")
_ART_SUFFIXES = (".png", ".webp", ".jpg", ".jpeg")
_MESH_FOLDERS = {
    "deployable": ("deployables",),
    "world_prop": ("resources", "environment"),
    "default": ("props", "resources", "equipment", "weapons"),
}
WORLD_PROP_CATEGORY = "world_prop"
# Folders under resources/ that hold gallery rows. Items first, then world props.
_ROW_FOLDERS = ("items", "world_props")


def _unquote(value: str) -> str:
    text = value.strip()
    if len(text) >= 2 and text[0] == '"' and text[-1] == '"':
        return text[1:-1].replace('\\"', '"')
    return text


def _parse_tres(path: Path) -> dict | None:
    fields: dict[str, str] = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        match = _ASSIGN.match(line.strip())
        if match:
            fields[match.group(1)] = match.group(2).strip()
    item_id = _unquote(fields.get("id", ""))
    if not item_id:
        return None
    color = _COLOR.search(fields.get("swatch", ""))
    swatch = [float(color.group(index)) for index in range(1, 5)] if color else [0.7, 0.7, 0.7, 1.0]
    parsed = {
        "id": item_id,
        "display_name": _unquote(fields.get("display_name", item_id)),
        "description": _unquote(fields.get("description", "")),
        "category": _unquote(fields.get("category", "misc")),
        "swatch": swatch,
        "source": path.as_posix(),
    }
    box = _VECTOR3.search(fields.get("body_size", ""))
    if box:
        parsed["body_size"] = [float(box.group(index)) for index in range(1, 4)]
        parsed["prop_kind"] = _unquote(fields.get("kind", "resource"))
        parsed["deposit_id"] = _unquote(fields.get("deposit_id", ""))
    return parsed


def safe_item_id(value: str) -> str:
    token = re.sub(r"[^a-z0-9_]+", "_", (value or "").strip().lower())
    token = re.sub(r"_+", "_", token).strip("_")
    if not token:
        raise ValueError("Item id is empty.")
    return token[:64]


def art_path(project_root: Path, item_id: str) -> Path | None:
    folder = project_root / "assets" / "icons"
    for suffix in _ART_SUFFIXES:
        candidate = folder / f"{item_id}{suffix}"
        if candidate.is_file():
            return candidate
    return None


def world_mesh_path(project_root: Path, item_id: str, category: str) -> Path | None:
    folders = _MESH_FOLDERS.get(category, _MESH_FOLDERS["default"])
    for folder_name in folders:
        candidate = project_root / "assets" / folder_name / f"{item_id}.glb"
        if candidate.is_file():
            return candidate
    return None


def row_paths(project_root: Path) -> list[Path]:
    """Every .tres that becomes a gallery row: items, then world props."""
    paths: list[Path] = []
    for folder in _ROW_FOLDERS:
        root = project_root / "resources" / folder
        if root.is_dir():
            paths.extend(sorted(root.rglob("*.tres")))
    return paths


def load_items(project_root: Path, copy: dict | None = None) -> list[dict]:
    images = (copy or {}).get("items", {})
    dims = load_dimensions()
    items = []
    for path in row_paths(project_root):
        parsed = _parse_tres(path)
        if parsed is None:
            continue
        saved = images.get(parsed["id"]) if isinstance(images, dict) else None
        parsed["image_description"] = " ".join(str((saved or {}).get("image") or "").split()) if isinstance(saved, dict) else ""
        picture = art_path(project_root, parsed["id"])
        parsed["has_art"] = picture is not None
        parsed["art_file"] = picture.name if picture else ""
        parsed["needs_art"] = picture is None
        mesh = world_mesh_path(project_root, parsed["id"], parsed["category"])
        parsed["has_world_art"] = mesh is not None
        parsed["world_art_file"] = f"{mesh.parent.name}/{mesh.name}" if mesh else ""
        parsed["needs_world_art"] = mesh is None
        if parsed["category"] == WORLD_PROP_CATEGORY and "body_size" in parsed:
            size = [round(axis, 4) for axis in parsed["body_size"]]
            parsed["target_size"] = size
            parsed["footprint"] = None
            parsed["height"] = size[1]
            parsed["mount"] = "world"
            items.append(parsed)
            continue
        size = target_size_for_item(parsed["id"], parsed["category"], dims)
        parsed["target_size"] = size
        if parsed["category"] == "deployable":
            info = dimensions_for(parsed["id"], dims)
            parsed["footprint"] = info["footprint"] if info else None
            parsed["height"] = info["height"] if info else None
            parsed["mount"] = info["mount"] if info else None
        else:
            parsed["footprint"] = None
            parsed["height"] = None
            parsed["mount"] = "pickup"
        items.append(parsed)
    items.sort(key=lambda item: (item["category"], item["display_name"].lower(), item["id"]))
    return items
