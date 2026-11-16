"""Write Codex edits back into the game files.

Tier moves change one recipe integer. New items are .tres files, plus an
optional recipe line. gen_items.py is not run; its table is not the catalog.
"""

from __future__ import annotations

import re
from pathlib import Path

from core.errors import PipelineError
from godot.codex_index import FAMILY_LABELS, _parse_stations, _station_for, build_codex
from godot.item_index import safe_item_id

_ITEM_SCRIPT = "res://scripts/items/item_definition.gd"
_FOLDERS = {"", "harvestable", "salvage", "food", "refined", "components", "military", "tools", "deployables"}
_CATEGORIES = {
    "harvest", "container", "food", "refined", "component", "ammo", "explosive",
    "tool", "deployable", "material", "medical", "weapon", "debug", "misc",
}
_DESCRIPTION_LIMIT = 400
_NAME_LIMIT = 64


def _safe(value: object) -> str:
    try:
        return safe_item_id(str(value or ""))
    except ValueError as exc:
        raise PipelineError(str(exc)) from exc


def _craft_path(project_root: Path) -> Path:
    return project_root / "scripts" / "deployables" / "craft_rules.gd"


def _smelt_path(project_root: Path) -> Path:
    return project_root / "scripts" / "deployables" / "smelt_rules.gd"


def _number(value: float) -> str:
    text = f"{float(value):.4f}".rstrip("0").rstrip(".")
    return text or "0"


def _gd_string(value: str) -> str:
    return '"' + value.replace("\\", "\\\\").replace('"', '\\"') + '"'


def _clean_text(value: object, limit: int, label: str) -> str:
    text = " ".join(str(value or "").split())
    if len(text) > limit:
        raise PipelineError(f"{label} is limited to {limit} characters.")
    return text


def _family_max(project_root: Path, family: str) -> int:
    stations = [station for station in _parse_stations(project_root) if station["family"] == family]
    if not stations:
        raise PipelineError(f"No station uses the {family} family.")
    return max(station["tier"] for station in stations)


def _require_tier(project_root: Path, family: str, tier: object) -> int:
    try:
        parsed = int(tier)
    except (TypeError, ValueError) as exc:
        raise PipelineError("Tier must be a number.") from exc
    highest = _family_max(project_root, family)
    if parsed < 1 or parsed > highest:
        label = FAMILY_LABELS.get(family, family)
        raise PipelineError(f"{label} only has tiers 1–{highest}.")
    return parsed


def _item_file(project_root: Path, item_id: str) -> Path | None:
    root = project_root / "resources" / "items"
    if not root.is_dir():
        return None
    needle = f'id = "{item_id}"'
    for path in root.rglob("*.tres"):
        if needle in path.read_text(encoding="utf-8"):
            return path
    return None


def _known_ids(project_root: Path) -> set[str]:
    return {item["id"] for item in build_codex(project_root)["items"]}


def station_note(project_root: Path, family: str, tier: int) -> str:
    station = _station_for(_parse_stations(project_root), family, tier)
    name = station["name"] if station else FAMILY_LABELS.get(family, family)
    return f"{name} and above"


def set_recipe_tier(project_root: Path, family: str, input_id: str, extra: str, output: str, tier: object) -> str:
    """Rewrite one recipe tier. Identity is family + input + extra + output."""
    project_root = Path(project_root)
    family = str(family or "").strip()
    input_id = _safe(input_id)
    extra_id = _safe(extra) if str(extra or "").strip() else ""
    output_id = _safe(output)
    if family == "smelt" and extra_id:
        raise PipelineError("A smelt recipe has no second ingredient.")
    parsed = _require_tier(project_root, family, tier)
    if family == "smelt":
        path = _smelt_path(project_root)
        pattern = re.compile(
            r'(\{\s*"input"\s*:\s*"' + re.escape(input_id) + r'"\s*,\s*"output"\s*:\s*"'
            + re.escape(output_id) + r'"\s*,\s*"tier"\s*:\s*)\d+'
        )
    else:
        path = _craft_path(project_root)
        pattern = re.compile(
            r'(_out\(\s*"' + re.escape(family) + r'"\s*,\s*)\d+(\s*,\s*"' + re.escape(input_id)
            + r'"\s*,\s*"' + re.escape(extra_id) + r'"\s*,\s*"' + re.escape(output_id) + r'"\s*,)'
        )
    if not path.is_file():
        raise PipelineError(f"Missing {path.name}.")
    text = path.read_text(encoding="utf-8")
    found = list(pattern.finditer(text))
    if len(found) != 1:
        raise PipelineError(f"Expected one {output_id} recipe from {input_id}, found {len(found)}.")

    def replacer(match: re.Match) -> str:
        if family == "smelt":
            return f"{match.group(1)}{parsed}"
        return f"{match.group(1)}{parsed}{match.group(2)}"

    path.write_text(pattern.sub(replacer, text, count=1), encoding="utf-8")
    return station_note(project_root, family, parsed)


def _recipe_pattern(family: str, input_id: str, extra_id: str, output_id: str) -> re.Pattern:
    if family == "smelt":
        return re.compile(
            r'\{\s*"input"\s*:\s*"' + re.escape(input_id) + r'"\s*,\s*"output"\s*:\s*"'
            + re.escape(output_id) + r'"\s*,\s*"tier"\s*:\s*\d+'
        )
    return re.compile(
        r'_out\(\s*"' + re.escape(family) + r'"\s*,\s*\d+\s*,\s*"' + re.escape(input_id)
        + r'"\s*,\s*"' + re.escape(extra_id) + r'"\s*,\s*"' + re.escape(output_id) + r'"\s*,'
    )


def apply_tier_moves(project_root: Path, moves: list[dict]) -> list[str]:
    """Apply every tier move, or leave the files untouched when one is illegal."""
    if not moves:
        raise PipelineError("Nothing to move.")
    project_root = Path(project_root)
    pending = []
    for move in moves:
        if not isinstance(move, dict):
            raise PipelineError("Each move needs a recipe identity.")
        family = str(move.get("family") or "").strip()
        input_id = _safe(move.get("input"))
        extra_id = _safe(move.get("extra")) if str(move.get("extra") or "").strip() else ""
        output_id = _safe(move.get("output"))
        parsed = _require_tier(project_root, family, move.get("tier"))
        path = _smelt_path(project_root) if family == "smelt" else _craft_path(project_root)
        if not path.is_file():
            raise PipelineError(f"Missing {path.name}.")
        found = _recipe_pattern(family, input_id, extra_id, output_id).findall(path.read_text(encoding="utf-8"))
        if len(found) != 1:
            raise PipelineError(f"Expected one {output_id} recipe from {input_id}, found {len(found)}.")
        pending.append((family, input_id, extra_id, output_id, parsed))
    notes = []
    for family, input_id, extra_id, output_id, parsed in pending:
        notes.append(set_recipe_tier(project_root, family, input_id, extra_id, output_id, parsed))
    return notes


def _swatch(value: object) -> list[float]:
    if not isinstance(value, (list, tuple)) or len(value) < 3:
        raise PipelineError("Swatch needs red, green, and blue values.")
    channels = []
    for channel in list(value)[:4]:
        try:
            number = float(channel)
        except (TypeError, ValueError) as exc:
            raise PipelineError("Swatch values must be numbers from 0 to 1.") from exc
        if number > 1:
            number = number / 255.0
        if number < 0 or number > 1:
            raise PipelineError("Swatch values must be numbers from 0 to 1.")
        channels.append(number)
    if len(channels) == 3:
        channels.append(1.0)
    return channels


def _write_tres(path: Path, item: dict) -> None:
    red, green, blue, alpha = item["swatch"]
    harvest = ""
    if item.get("harvest_kind"):
        harvest = (
            f'\nharvest_kind = {_gd_string(item["harvest_kind"])}\n'
            f'harvest_tier = {int(item["harvest_tier"])}\n'
            f'harvest_power = {int(item["harvest_power"])}\n'
        )
    text = (
        '[gd_resource type="Resource" script_class="ItemDefinition" load_steps=2 format=3]\n\n'
        f'[ext_resource type="Script" path="{_ITEM_SCRIPT}" id="1_item"]\n\n'
        "[resource]\n"
        'script = ExtResource("1_item")\n'
        f'id = {_gd_string(item["id"])}\n'
        f'display_name = {_gd_string(item["display_name"])}\n'
        f'description = {_gd_string(item["description"])}\n'
        f'max_stack = {int(item["max_stack"])}\n'
        f'weight = {_number(item["weight"])}\n'
        f'category = {_gd_string(item["category"])}\n'
        "can_pickup = true\n"
        "can_store = true\n"
        f"swatch = Color({_number(red)}, {_number(green)}, {_number(blue)}, {_number(alpha)})\n"
        f"{harvest}"
    )
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")


def _replace_line(text: str, key: str, literal: str) -> str:
    pattern = re.compile(rf"^{re.escape(key)} = .*$", re.M)
    if not pattern.search(text):
        raise PipelineError(f"The item file has no {key} line.")
    return pattern.sub(f"{key} = {literal}", text, count=1)


def update_item(project_root: Path, payload: dict) -> str:
    """Rewrite the display fields of an existing item. Folder and id stay put."""
    project_root = Path(project_root)
    item_id = _safe(payload.get("id"))
    path = _item_file(project_root, item_id)
    if path is None:
        raise PipelineError(f"No item named {item_id}.")
    name = _clean_text(payload.get("display_name"), _NAME_LIMIT, "Name")
    if not name:
        raise PipelineError("Name is required.")
    description = _clean_text(payload.get("description"), _DESCRIPTION_LIMIT, "Description")
    try:
        stack = int(payload.get("max_stack"))
        weight = float(payload.get("weight"))
    except (TypeError, ValueError) as exc:
        raise PipelineError("Stack and weight must be numbers.") from exc
    if stack < 1 or stack > 999:
        raise PipelineError("Stack must be from 1 to 999.")
    if weight < 0 or weight > 999:
        raise PipelineError("Weight must be from 0 to 999.")
    swatch = _swatch(payload.get("swatch"))
    text = path.read_text(encoding="utf-8")
    text = _replace_line(text, "display_name", _gd_string(name))
    text = _replace_line(text, "description", _gd_string(description))
    text = _replace_line(text, "max_stack", str(stack))
    text = _replace_line(text, "weight", _number(weight))
    red, green, blue, alpha = swatch
    text = _replace_line(text, "swatch", f"Color({_number(red)}, {_number(green)}, {_number(blue)}, {_number(alpha)})")
    path.write_text(text, encoding="utf-8")
    return item_id


def _recipe_payload(project_root: Path, output: str, recipe: dict, known: set[str]) -> dict:
    if not isinstance(recipe, dict):
        raise PipelineError("Recipe details are missing.")
    kind = str(recipe.get("kind") or "craft").strip()
    family = "smelt" if kind == "smelt" else str(recipe.get("family") or "").strip()
    if kind == "smelt":
        family = "smelt"
    tier = _require_tier(project_root, family, recipe.get("tier"))
    input_id = _safe(recipe.get("input"))
    extra_id = _safe(recipe.get("extra")) if str(recipe.get("extra") or "").strip() else ""
    if input_id not in known:
        raise PipelineError(f"Input {input_id} is not an item yet.")
    if extra_id and extra_id not in known:
        raise PipelineError(f"Extra ingredient {extra_id} is not an item yet.")
    if family == "smelt" and extra_id:
        raise PipelineError("A smelt recipe has no second ingredient.")
    if family != "smelt":
        try:
            in_n = int(recipe.get("in_n"))
            extra_n = int(recipe.get("extra_n") or 0)
            out_n = int(recipe.get("out_n"))
        except (TypeError, ValueError) as exc:
            raise PipelineError("Recipe counts must be numbers.") from exc
    else:
        in_n, extra_n, out_n = 1, 0, 1
    if in_n < 1 or out_n < 1 or extra_n < 0 or in_n > 99 or extra_n > 99 or out_n > 99:
        raise PipelineError("Recipe counts must be from 1 to 99.")
    if extra_id and extra_n < 1:
        raise PipelineError("The second ingredient needs a count.")
    if not extra_id:
        extra_n = 0
    return {
        "kind": kind,
        "family": family,
        "tier": tier,
        "input": input_id,
        "extra": extra_id,
        "output": output,
        "in_n": in_n,
        "extra_n": extra_n,
        "out_n": out_n,
        "alloy": bool(recipe.get("alloy")),
    }


def _append_recipe(project_root: Path, recipe: dict) -> None:
    if recipe["family"] == "smelt":
        path = _smelt_path(project_root)
        sample = re.search(r"\n([ \t]+)\{\s*\"input\"", _read(path))
        indent = sample.group(1) if sample else "\t\t"
        alloy = "true" if recipe["alloy"] else "false"
        line = (
            f'{indent}{{"input": "{recipe["input"]}", "output": "{recipe["output"]}", '
            f'"tier": {recipe["tier"]}, "alloy": {alloy}}},\n'
        )
        marker = '{"input":'
    else:
        path = _craft_path(project_root)
        sample = re.search(r"\n([ \t]+)_out\(", _read(path))
        indent = sample.group(1) if sample else "\t\t"
        line = (
            f'{indent}_out("{recipe["family"]}", {recipe["tier"]}, "{recipe["input"]}", '
            f'"{recipe["extra"]}", "{recipe["output"]}", {recipe["in_n"]}, {recipe["extra_n"]}, {recipe["out_n"]}),\n'
        )
        marker = "_out("
    if not path.is_file():
        raise PipelineError(f"Missing {path.name}.")
    text = path.read_text(encoding="utf-8")
    if recipe["family"] == "smelt":
        identity = f'"input": "{recipe["input"]}", "output": "{recipe["output"]}"'
        if identity in text:
            raise PipelineError("That smelt recipe already exists.")
    else:
        duplicate = re.compile(
            r'_out\(\s*"' + re.escape(recipe["family"]) + r'"\s*,\s*\d+\s*,\s*"' + re.escape(recipe["input"])
            + r'"\s*,\s*"' + re.escape(recipe["extra"]) + r'"\s*,\s*"' + re.escape(recipe["output"]) + r'"'
        )
        if duplicate.search(text):
            raise PipelineError("That recipe already exists.")
    start = text.find("\t_recipes = [")
    if start < 0:
        start = text.find("_recipes = [")
    if start < 0:
        raise PipelineError(f"{path.name} has no recipe list.")
    close = re.search(r"\n[ \t]*\]", text[start:])
    if close is None or marker not in text[start:start + close.start()]:
        raise PipelineError(f"{path.name} has no recipe list to extend.")
    at = start + close.start() + 1
    path.write_text(text[:at] + line + text[at:], encoding="utf-8")


def _read(path: Path) -> str:
    return path.read_text(encoding="utf-8") if path.is_file() else ""


def create_item(project_root: Path, payload: dict) -> dict:
    """Write a new item file and, when asked, one recipe that outputs it."""
    project_root = Path(project_root)
    if not isinstance(payload, dict):
        raise PipelineError("Item details are missing.")
    item_id = _safe(payload.get("id"))
    if _item_file(project_root, item_id) is not None:
        raise PipelineError(f"{item_id} already exists.")
    name = _clean_text(payload.get("display_name"), _NAME_LIMIT, "Name")
    if not name:
        raise PipelineError("Name is required.")
    description = _clean_text(payload.get("description"), _DESCRIPTION_LIMIT, "Description")
    category = str(payload.get("category") or "misc").strip()
    folder = str(payload.get("folder") or "").strip()
    if category not in _CATEGORIES:
        raise PipelineError("Pick a category the game already uses.")
    if folder not in _FOLDERS:
        raise PipelineError("Pick an item folder.")
    try:
        stack = int(payload.get("max_stack"))
        weight = float(payload.get("weight"))
    except (TypeError, ValueError) as exc:
        raise PipelineError("Stack and weight must be numbers.") from exc
    if stack < 1 or stack > 999:
        raise PipelineError("Stack must be from 1 to 999.")
    if weight < 0 or weight > 999:
        raise PipelineError("Weight must be from 0 to 999.")
    item = {
        "id": item_id,
        "display_name": name,
        "description": description,
        "category": category,
        "folder": folder,
        "max_stack": stack,
        "weight": weight,
        "swatch": _swatch(payload.get("swatch")),
    }
    recipe = payload.get("recipe")
    prepared = None
    if recipe:
        prepared = _recipe_payload(project_root, item_id, recipe, _known_ids(project_root))
    destination = project_root / "resources" / "items"
    if folder:
        destination = destination / folder
    destination = destination / f"{item_id}.tres"
    _write_tres(destination, item)
    if prepared:
        try:
            _append_recipe(project_root, prepared)
        except Exception:
            destination.unlink(missing_ok=True)
            raise
    item["tier_note"] = station_note(project_root, prepared["family"], prepared["tier"]) if prepared else ""
    return item
