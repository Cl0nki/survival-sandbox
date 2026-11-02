"""Read the Godot item catalog for the art gallery.

Icons in the game are drawn by scripts/items/item_icons.gd from each item's
swatch. A finished picture belongs at assets/icons/<id>.png.
"""

import re
from pathlib import Path

_ASSIGN = re.compile(r"^([A-Za-z0-9_]+)\s*=\s*(.+)$")
_COLOR = re.compile(r"Color\(\s*([0-9.]+)\s*,\s*([0-9.]+)\s*,\s*([0-9.]+)\s*,\s*([0-9.]+)\s*\)")
_ART_SUFFIXES = (".png", ".webp", ".jpg", ".jpeg")


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
    return {
        "id": item_id,
        "display_name": _unquote(fields.get("display_name", item_id)),
        "description": _unquote(fields.get("description", "")),
        "category": _unquote(fields.get("category", "misc")),
        "swatch": swatch,
        "source": path.as_posix(),
    }


def art_path(project_root: Path, item_id: str) -> Path | None:
    folder = project_root / "assets" / "icons"
    for suffix in _ART_SUFFIXES:
        candidate = folder / f"{item_id}{suffix}"
        if candidate.is_file():
            return candidate
    return None


def load_items(project_root: Path, copy: dict | None = None) -> list[dict]:
    root = project_root / "resources" / "items"
    images = (copy or {}).get("items", {})
    items = []
    if not root.is_dir():
        return items
    for path in sorted(root.rglob("*.tres")):
        parsed = _parse_tres(path)
        if parsed is None:
            continue
        saved = images.get(parsed["id"]) if isinstance(images, dict) else None
        parsed["image_description"] = " ".join(str((saved or {}).get("image") or "").split()) if isinstance(saved, dict) else ""
        picture = art_path(project_root, parsed["id"])
        parsed["has_art"] = picture is not None
        parsed["art_file"] = picture.name if picture else ""
        parsed["needs_art"] = picture is None
        items.append(parsed)
    items.sort(key=lambda item: (item["category"], item["display_name"].lower(), item["id"]))
    return items
