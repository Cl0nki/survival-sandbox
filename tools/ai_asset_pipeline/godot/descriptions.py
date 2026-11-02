"""In-game copy and the separate text sent to the image model.

Item in-game text stays on the item resource. Image text, and both texts for
building surfaces, stay in config/descriptions.json.
"""

import json
import re
from pathlib import Path

from core.errors import PipelineError
from core.settings import Settings
from godot.item_index import _parse_tres, load_items
from godot.surface_index import load_grounds, load_surfaces

_ITEM_ID = re.compile(r"[a-z0-9_]+")
_SURFACE_ID = re.compile(
    r"^(?:(?:wall|floor|post|stairs)_(?:scrap|wood|brick|stone|concrete|composite)"
    r"|ground_(?:grass|dirt|rock|meadow|sand|clay|gravel|water|gas|oil))$"
)
_DESCRIPTION_LIMIT = 400
_IMAGE_LIMIT = 1500


def load_descriptions(settings: Settings) -> dict:
    path = settings.descriptions_path
    if not path.is_file():
        return {"items": {}, "surfaces": {}}
    data = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(data, dict):
        return {"items": {}, "surfaces": {}}
    items = data.get("items")
    surfaces = data.get("surfaces")
    return {
        "items": items if isinstance(items, dict) else {},
        "surfaces": surfaces if isinstance(surfaces, dict) else {},
    }


def save_item_copy(settings: Settings, item_id: str, description: str, image_description: str) -> dict:
    path = _item_file(settings.project_root, item_id)
    ingame = _clean(description, _DESCRIPTION_LIMIT, "In-game description")
    image = _clean(image_description, _IMAGE_LIMIT, "Image description")
    _write_item_description(path, ingame)
    stored = load_descriptions(settings)
    items = dict(stored["items"])
    if image:
        items[item_id] = {"image": image}
    else:
        items.pop(item_id, None)
    _write(settings, {"items": items, "surfaces": stored["surfaces"]})
    found = next(item for item in load_items(settings.project_root, {"items": items}) if item["id"] == item_id)
    return found


def save_surface_copy(settings: Settings, surface_id: str, description: str, image_description: str) -> dict:
    if not _SURFACE_ID.fullmatch(surface_id):
        raise PipelineError("Unknown surface.")
    known = {item["id"] for item in load_surfaces(settings.project_root)}
    known.update(item["id"] for item in load_grounds(settings.project_root))
    if surface_id not in known:
        raise PipelineError("Unknown surface.")
    ingame = _clean(description, _DESCRIPTION_LIMIT, "In-game description")
    image = _clean(image_description, _IMAGE_LIMIT, "Image description")
    stored = load_descriptions(settings)
    surfaces = dict(stored["surfaces"])
    entry = {}
    if ingame:
        entry["ingame"] = ingame
    if image:
        entry["image"] = image
    if entry:
        surfaces[surface_id] = entry
    else:
        surfaces.pop(surface_id, None)
    copy = {"items": stored["items"], "surfaces": surfaces}
    _write(settings, copy)
    found = _find_surface(settings.project_root, copy, surface_id)
    return found


def _find_surface(project_root: Path, copy: dict, surface_id: str) -> dict:
    for item in load_surfaces(project_root, copy) + load_grounds(project_root, copy):
        if item["id"] == surface_id:
            return item
    raise PipelineError("Unknown surface.")


def _item_file(project_root: Path, item_id: str) -> Path:
    if not _ITEM_ID.fullmatch(item_id):
        raise PipelineError("Unknown item.")
    root = project_root / "resources" / "items"
    if not root.is_dir():
        raise PipelineError("Unknown item.")
    matches = []
    for path in root.rglob("*.tres"):
        parsed = _parse_tres(path)
        if parsed and parsed["id"] == item_id:
            matches.append(path)
    if len(matches) != 1:
        raise PipelineError("Unknown item.")
    return matches[0]


def _write_item_description(path: Path, description: str) -> None:
    raw = path.read_text(encoding="utf-8")
    if not re.search(r"^description = .*$", raw, re.M):
        raise PipelineError("That item file has no description line.")
    line = f"description = {_godot_string(description)}"
    updated = re.sub(r"^description = .*$", line, raw, count=1, flags=re.M)
    path.write_text(updated, encoding="utf-8")


def _godot_string(text: str) -> str:
    escaped = text.replace("\\", "\\\\").replace('"', '\\"')
    return f'"{escaped}"'


def _clean(text: str, limit: int, label: str) -> str:
    if not isinstance(text, str):
        raise PipelineError(f"{label} must be text.")
    collapsed = " ".join(text.split())
    if len(collapsed) > limit:
        raise PipelineError(f"{label} must be {limit} characters or fewer.")
    return collapsed


def _write(settings: Settings, payload: dict) -> None:
    path = settings.descriptions_path
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(".tmp.json")
    temporary.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
    temporary.replace(path)
