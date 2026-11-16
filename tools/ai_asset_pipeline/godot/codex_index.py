"""Join item files with gather, craft, smelt, and fill sources.

The game files stay authoritative. This module only reads them and builds the
document the Codex page and resources/wiki/catalog.json share.
"""

from __future__ import annotations

import json
import re
from pathlib import Path

from godot.item_index import art_path

_ASSIGN = re.compile(r"^([A-Za-z0-9_]+)\s*=\s*(.+)$")
_COLOR = re.compile(r"Color\(\s*([0-9.]+)\s*,\s*([0-9.]+)\s*,\s*([0-9.]+)\s*,\s*([0-9.]+)\s*\)")
_OUT = re.compile(
    r'_out\(\s*"([a-z_]+)"\s*,\s*(\d+)\s*,\s*"([a-z0-9_]*)"\s*,\s*"([a-z0-9_]*)"\s*,\s*"([a-z0-9_]+)"\s*,\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*\)'
)
_SMELT = re.compile(
    r'\{\s*"input"\s*:\s*"([a-z0-9_]+)"\s*,\s*"output"\s*:\s*"([a-z0-9_]+)"\s*,\s*"tier"\s*:\s*(\d+)\s*,\s*"alloy"\s*:\s*(true|false)\s*\}'
)
_STATION = re.compile(
    r'_station\(\s*"([^"]+)"\s*,\s*"([^"]+)"\s*,\s*"([^"]+)"\s*,\s*(\d+)\s*,\s*(\d+)\s*,'
    r'\s*[0-9.]+\s*,\s*\d+\s*,\s*\d+\s*,\s*[A-Za-z_]+\s*,\s*\d+\s*,\s*[0-9.]+\s*,\s*"([^"]+)"'
)
_SMELT_STATION = re.compile(
    r'_put\(\s*"([^"]+)"\s*,\s*(\d+)\s*,\s*(\d+)\s*,\s*[0-9.]+\s*,\s*\d+\s*,\s*\d+\s*,\s*\d+\s*,\s*\d+\s*,'
    r'\s*(?:true|false)\s*,\s*\d+\s*,\s*"([^"]+)"'
)
_FILL = re.compile(r'_put\(\s*"([^"]+)"\s*,\s*"([^"]+)"\s*,.*?\{([^}]*)\}', re.S)
_PAIR = re.compile(r'\[\s*"([a-z0-9_]+)"\s*,\s*(\d+)\s*\]')
_QUOTED = re.compile(r'"([^"]+)"')
_PICKUP = re.compile(r'_pickup\(\s*[^,]+,\s*"([^"]+)"\s*,\s*"([a-z0-9_]+)"\s*,\s*(\d+)')
_ID_FIELD = re.compile(r'\{"id":\s*"?([A-Za-z0-9_]+)"?')

FAMILY_LABELS = {
    "saw": "Saw",
    "kiln": "Kiln",
    "bench": "Workbench",
    "chem": "Chem",
    "armory": "Armory",
    "cook": "Cooking",
    "smelt": "Smelting",
}
RECIPE_KINDS = {"craft", "cook", "smelt"}
DEBUG_IDS = {"build_tool", "repair_tool", "upgrade_tool", "debug_weapon", "debugweapon", "blast_gun"}
WIKI_PATH = Path("resources") / "wiki" / "catalog.json"


def _unquote(value: str) -> str:
    text = value.strip().rstrip(",")
    if len(text) >= 2 and text[0] == '"' and text[-1] == '"':
        return text[1:-1].replace('\\"', '"')
    return text


def _read(path: Path) -> str:
    if not path.is_file():
        return ""
    return path.read_text(encoding="utf-8")


def _func_body(text: str, name: str) -> str:
    match = re.search(rf"func {re.escape(name)}\(", text)
    if not match:
        return ""
    nxt = re.search(r"\nstatic func ", text[match.end():])
    end = match.end() + nxt.start() if nxt else len(text)
    return text[match.start():end]


def _split_args(body: str) -> list[str]:
    args: list[str] = []
    buf: list[str] = []
    depth = 0
    quote = False
    index = 0
    while index < len(body):
        char = body[index]
        if quote:
            buf.append(char)
            if char == "\\":
                if index + 1 < len(body):
                    buf.append(body[index + 1])
                    index += 2
                    continue
            elif char == '"':
                quote = False
            index += 1
            continue
        if char == '"':
            quote = True
            buf.append(char)
        elif char == "," and depth == 0:
            args.append("".join(buf).strip())
            buf = []
        else:
            buf.append(char)
            if char in "([{":
                depth += 1
            elif char in ")]}":
                depth -= 1
        index += 1
    tail = "".join(buf).strip()
    if tail:
        args.append(tail)
    return args


def _iter_calls(text: str, names: set[str]):
    pattern = re.compile(r"\b(" + "|".join(sorted(names, key=len, reverse=True)) + r")\(")
    for match in pattern.finditer(text):
        start = match.end() - 1
        depth = 0
        quote = False
        index = start
        while index < len(text):
            char = text[index]
            if quote:
                if char == "\\":
                    index += 2
                    continue
                if char == '"':
                    quote = False
            elif char == '"':
                quote = True
            elif char == "(":
                depth += 1
            elif char == ")":
                depth -= 1
                if depth == 0:
                    yield match.group(1), _split_args(text[start + 1:index])
                    break
            index += 1


def _string_arg(value: str) -> str:
    match = re.search(r'"([^"]*)"', value)
    return match.group(1) if match else ""


def _pairs(text: str) -> list[tuple[str, int]]:
    return [(match.group(1), int(match.group(2))) for match in _PAIR.finditer(text)]


def _recipe_kind(family: str) -> str:
    if family == "cook":
        return "cook"
    if family == "smelt":
        return "smelt"
    return "craft"


def _station_for(stations: list[dict], family: str, tier: int) -> dict | None:
    eligible = [station for station in stations if station["family"] == family and station["tier"] >= tier]
    eligible.sort(key=lambda station: (station["tier"], station["batch"], station["name"]))
    return eligible[0] if eligible else None


def _parse_items(project_root: Path) -> list[dict]:
    root = project_root / "resources" / "items"
    items = []
    if not root.is_dir():
        return items
    for path in sorted(root.rglob("*.tres")):
        fields: dict[str, str] = {}
        for line in path.read_text(encoding="utf-8").splitlines():
            match = _ASSIGN.match(line.strip())
            if match:
                fields[match.group(1)] = match.group(2).strip()
        item_id = _unquote(fields.get("id", ""))
        if not item_id:
            continue
        color = _COLOR.search(fields.get("swatch", ""))
        swatch = [float(color.group(index)) for index in range(1, 5)] if color else [0.7, 0.7, 0.7, 1.0]
        relative = path.relative_to(root)
        folder = "" if len(relative.parts) == 1 else relative.parts[0]
        picture = art_path(project_root, item_id)
        try:
            weight = float(fields.get("weight", "0") or 0)
        except ValueError:
            weight = 0.0
        try:
            stack = int(float(fields.get("max_stack", "1") or 1))
        except ValueError:
            stack = 1
        items.append({
            "id": item_id,
            "display_name": _unquote(fields.get("display_name", item_id)),
            "description": _unquote(fields.get("description", "")),
            "category": _unquote(fields.get("category", "misc")),
            "folder": folder,
            "max_stack": stack,
            "weight": weight,
            "swatch": swatch,
            "harvest_kind": _unquote(fields.get("harvest_kind", "")),
            "harvest_tier": int(float(fields.get("harvest_tier", "0") or 0)),
            "harvest_power": int(float(fields.get("harvest_power", "0") or 0)),
            "has_art": picture is not None,
            "icon": f"assets/icons/{picture.name}" if picture else "",
            "debug": _unquote(fields.get("category", "")) == "debug" or item_id in DEBUG_IDS,
        })
    return items


def _parse_stations(project_root: Path) -> list[dict]:
    stations = []
    craft = _read(project_root / "scripts" / "deployables" / "craft_rules.gd")
    for kind, _group, family, tier, batch, name in _STATION.findall(craft):
        stations.append({
            "kind": kind,
            "family": family,
            "tier": int(tier),
            "batch": int(batch),
            "name": name,
        })
    smelt = _read(project_root / "scripts" / "deployables" / "smelt_rules.gd")
    for kind, tier, batch, name in _SMELT_STATION.findall(smelt):
        stations.append({
            "kind": kind,
            "family": "smelt",
            "tier": int(tier),
            "batch": int(batch),
            "name": name,
        })
    return stations


def _parse_recipes(project_root: Path, stations: list[dict]) -> list[dict]:
    recipes = []
    craft = _read(project_root / "scripts" / "deployables" / "craft_rules.gd")
    for family, tier, input_id, extra, output, in_n, extra_n, out_n in _OUT.findall(craft):
        recipes.append(_recipe(family, int(tier), input_id, extra, output, int(in_n), int(extra_n), int(out_n), False, stations))
    smelt = _read(project_root / "scripts" / "deployables" / "smelt_rules.gd")
    for input_id, output, tier, alloy in _SMELT.findall(smelt):
        recipes.append(_recipe("smelt", int(tier), input_id, "", output, 1, 0, 1, alloy == "true", stations))
    return recipes


def _recipe(family: str, tier: int, input_id: str, extra: str, output: str, in_n: int, extra_n: int, out_n: int, alloy: bool, stations: list[dict]) -> dict:
    station = _station_for(stations, family, tier)
    name = station["name"] if station else FAMILY_LABELS.get(family, family)
    return {
        "kind": _recipe_kind(family),
        "family": family,
        "tier": tier,
        "input": input_id,
        "extra": extra,
        "output": output,
        "in_n": in_n,
        "extra_n": extra_n,
        "out_n": out_n,
        "alloy": alloy,
        "station": name,
        "station_kind": station["kind"] if station else "",
        "station_note": f"{name} and above",
    }


def _parse_deposits(project_root: Path) -> list[dict]:
    text = _read(project_root / "scripts" / "items" / "resource_catalog.gd")
    body = _func_body(text, "_ensure")
    deposits = []
    for name, args in _iter_calls(body, {"_add", "_add_tree", "_add_flora", "_add_scavenge"}):
        if len(args) < 2:
            continue
        deposit_id = _string_arg(args[0])
        display_name = _string_arg(args[1])
        if name == "_add" and len(args) >= 6:
            deposits.append({
                "id": deposit_id,
                "name": display_name,
                "tool": _string_arg(args[5]),
                "yields": [(_string_arg(args[2]), int(float(args[4])))],
            })
            continue
        yields_arg = next((arg for arg in args if arg.lstrip().startswith("[")), "")
        tool = "crowbar" if name == "_add_scavenge" else "hatchet"
        deposits.append({
            "id": deposit_id,
            "name": display_name,
            "tool": tool,
            "yields": _pairs(yields_arg),
        })
    return deposits


def _node_ids(body: str) -> list[str]:
    return [match.group(1) for match in _ID_FIELD.finditer(body)]


def _parse_biomes(project_root: Path) -> tuple[dict[str, list[dict]], dict[str, list[dict]]]:
    text = _read(project_root / "scripts" / "world" / "biome_catalog.gd")
    ore_match = re.search(r"ORE_IDS.*?\[(.*?)\]", text, re.S)
    ores = _QUOTED.findall(ore_match.group(1)) if ore_match else []
    nodes: dict[str, list[dict]] = {}
    patches: dict[str, list[dict]] = {}

    def add(table: dict[str, list[dict]], node_id: str, biome: dict) -> None:
        if node_id in {"tree_id", "ore_id"} or not node_id:
            return
        table.setdefault(node_id, [])
        if biome not in table[node_id]:
            table[node_id].append(biome)

    forest_body = _func_body(text, "_forest")
    forest_nodes = [node for node in _node_ids(forest_body) if node != "tree_id"]
    for biome_id, display_name, tree_id in re.findall(r'_forest\(\s*"([^"]+)"\s*,\s*"([^"]+)"\s*,\s*"([^"]+)"\s*\)', text):
        biome = {"id": biome_id, "name": display_name}
        add(nodes, tree_id, biome)
        for node_id in forest_nodes:
            add(nodes, node_id, biome)

    for func_name in ("_meadow", "_wasteland", "_hills", "_city"):
        body = _func_body(text, func_name)
        biome_id = re.search(r'biome\.id = "([^"]+)"', body)
        biome_name = re.search(r'biome\.display_name = "([^"]+)"', body)
        if not biome_id or not biome_name:
            continue
        biome = {"id": biome_id.group(1), "name": biome_name.group(1)}
        harvest_block = body.split("biome.deposits", 1)[0]
        for node_id in _node_ids(harvest_block):
            add(nodes, node_id, biome)
        if "ORE_IDS" in body:
            for ore_id in ores:
                add(nodes, ore_id, biome)
        deposit_block = body.split("biome.deposits", 1)[1] if "biome.deposits" in body else ""
        for patch_id in _node_ids(deposit_block):
            add(patches, patch_id, biome)
    return nodes, patches


def _parse_ground(project_root: Path, patch_biomes: dict[str, list[dict]]) -> tuple[list[dict], dict[str, list[dict]]]:
    root = project_root / "resources" / "ground_deposits"
    digs = []
    extractors: dict[str, list[dict]] = {}
    if not root.is_dir():
        return digs, extractors
    for path in sorted(root.glob("*.tres")):
        fields: dict[str, str] = {}
        for line in path.read_text(encoding="utf-8").splitlines():
            match = _ASSIGN.match(line.strip())
            if match:
                fields[match.group(1)] = match.group(2).strip()
        deposit_id = _unquote(fields.get("id", ""))
        item_id = _unquote(fields.get("item_id", ""))
        kinds = _QUOTED.findall(fields.get("extractor_kinds", ""))
        biomes = patch_biomes.get(deposit_id, [])
        if item_id:
            try:
                qty = int(float(fields.get("yield_amount", "0") or 0))
            except ValueError:
                qty = 0
            digs.append({
                "item_id": item_id,
                "node": deposit_id,
                "node_name": _unquote(fields.get("display_name", deposit_id)),
                "tool": _unquote(fields.get("harvest_kind", "")) or (kinds[0] if kinds else ""),
                "qty": qty,
                "biomes": biomes,
            })
        for kind in kinds:
            extractors.setdefault(kind, [])
            for biome in biomes:
                if biome not in extractors[kind]:
                    extractors[kind].append(biome)
    return digs, extractors


def _parse_fills(project_root: Path, extractors: dict[str, list[dict]]) -> list[dict]:
    text = _read(project_root / "scripts" / "deployables" / "fill_rules.gd")
    fills = []
    for kind, name, body in _FILL.findall(text):
        for empty_id, full_id in re.findall(r'"([a-z0-9_]+)"\s*:\s*"([a-z0-9_]+)"', body):
            fills.append({
                "kind": "fill",
                "output": full_id,
                "input": empty_id,
                "station": name,
                "station_kind": kind,
                "biomes": extractors.get(kind, []),
            })
    return fills


def _parse_loot(project_root: Path) -> list[dict]:
    text = _read(project_root / "scripts" / "items" / "loot_layout.gd")
    found = []
    for name, body in re.findall(r"const ([A-Z0-9_]+) := \[(.*?)\]", text, re.S):
        pairs = _pairs(body)
        if not pairs:
            continue
        label = name.replace("_", " ").title() + " crate"
        for item_id, qty in pairs:
            found.append({"item_id": item_id, "label": label, "qty": qty, "node": name.lower()})
    for node, item_id, qty in _PICKUP.findall(text):
        found.append({
            "item_id": item_id,
            "label": node.replace("_", " ").title(),
            "qty": int(qty),
            "node": node,
        })
    return found


def _chip(source: dict, names: dict[str, str]) -> str:
    kind = source["kind"]
    if kind in RECIPE_KINDS:
        left = f"{source['in_n']} {names.get(source['input'], source['input'])}"
        if source.get("extra"):
            left += f" + {source['extra_n']} {names.get(source['extra'], source['extra'])}"
        return f"{left} → {source['station']}"
    if kind == "gather":
        biomes = source.get("biomes") or []
        if len(biomes) == 1:
            return f"{source['node_name']} · {biomes[0]['name']}"
        if biomes:
            return f"{source['node_name']} · {len(biomes)} biomes"
        return f"{source['node_name']} · {source.get('tool') or 'gather'}"
    if kind == "dig":
        biomes = source.get("biomes") or []
        if len(biomes) == 1:
            return f"{source['node_name']} · {biomes[0]['name']}"
        if biomes:
            return f"{source['node_name']} · {len(biomes)} biomes"
        return f"{source['node_name']} · {source.get('tool') or 'shovel'}"
    if kind == "fill":
        return f"{names.get(source['input'], source['input'])} → {source['station']}"
    return source.get("label") or kind


def _families(stations: list[dict]) -> dict:
    grouped: dict[str, dict] = {}
    for station in stations:
        family = grouped.setdefault(station["family"], {
            "id": station["family"],
            "label": FAMILY_LABELS.get(station["family"], station["family"].capitalize()),
            "max_tier": 0,
            "stations": [],
        })
        family["max_tier"] = max(family["max_tier"], station["tier"])
        family["stations"].append(station)
    for family in grouped.values():
        family["stations"].sort(key=lambda station: (station["tier"], station["batch"], station["name"]))
    return grouped


def build_codex(project_root: Path) -> dict:
    """Read the game files and return the Codex document. Does not write."""
    project_root = Path(project_root)
    items = _parse_items(project_root)
    names = {item["id"]: item["display_name"] for item in items}
    stations = _parse_stations(project_root)
    recipes = _parse_recipes(project_root, stations)
    deposits = _parse_deposits(project_root)
    node_biomes, patch_biomes = _parse_biomes(project_root)
    digs, extractors = _parse_ground(project_root, patch_biomes)
    fills = _parse_fills(project_root, extractors)
    loot = _parse_loot(project_root)

    by_output: dict[str, list[dict]] = {}
    used_by: dict[str, list[dict]] = {}
    for recipe in recipes:
        by_output.setdefault(recipe["output"], []).append(recipe)
        for role, item_id, qty in (("input", recipe["input"], recipe["in_n"]), ("extra", recipe["extra"], recipe["extra_n"])):
            if not item_id:
                continue
            used_by.setdefault(item_id, []).append({
                "output": recipe["output"],
                "output_name": names.get(recipe["output"], recipe["output"]),
                "family": recipe["family"],
                "tier": recipe["tier"],
                "role": role,
                "qty": qty,
                "station": recipe["station"],
            })

    gather_by_item: dict[str, list[dict]] = {}
    for deposit in deposits:
        biomes = node_biomes.get(deposit["id"], [])
        for item_id, qty in deposit["yields"]:
            gather_by_item.setdefault(item_id, []).append({
                "kind": "gather",
                "node": deposit["id"],
                "node_name": deposit["name"],
                "tool": deposit["tool"],
                "qty": qty,
                "biomes": biomes,
            })

    dig_by_item: dict[str, list[dict]] = {}
    for dig in digs:
        dig_by_item.setdefault(dig["item_id"], []).append({
            "kind": "dig",
            "node": dig["node"],
            "node_name": dig["node_name"],
            "tool": dig["tool"],
            "qty": dig["qty"],
            "biomes": dig["biomes"],
        })

    fill_by_item: dict[str, list[dict]] = {}
    for fill in fills:
        fill_by_item.setdefault(fill["output"], []).append(fill)

    loot_by_item: dict[str, list[dict]] = {}
    for entry in loot:
        loot_by_item.setdefault(entry["item_id"], []).append({
            "kind": "loot",
            "node": entry["node"],
            "node_name": entry["label"],
            "qty": entry["qty"],
            "label": entry["label"],
        })

    for item in items:
        sources = []
        sources.extend(gather_by_item.get(item["id"], []))
        sources.extend(dig_by_item.get(item["id"], []))
        sources.extend(fill_by_item.get(item["id"], []))
        sources.extend(by_output.get(item["id"], []))
        sources.extend(loot_by_item.get(item["id"], []))
        for source in sources:
            source["chip"] = _chip(source, names)
        item["sources"] = sources
        item["used_by"] = used_by.get(item["id"], [])
        recipes = [source for source in sources if source["kind"] in RECIPE_KINDS]
        world = [source for source in sources if source["kind"] in {"gather", "dig", "fill"}]
        if recipes:
            recipes.sort(key=lambda source: (source["tier"], source.get("station_kind", "")))
            item["column"] = recipes[0].get("station_kind") or "none"
        elif world:
            item["column"] = "gather"
        else:
            item["column"] = "none"

    items.sort(key=lambda item: (item["display_name"].lower(), item["id"]))
    folders = sorted({item["folder"] for item in items if item["folder"]})
    categories = sorted({item["category"] for item in items if item["category"]})
    return {
        "items": items,
        "families": _families(stations),
        "folders": folders,
        "categories": categories,
    }


def publish_codex(project_root: Path) -> dict:
    """Rebuild the Codex document and write resources/wiki/catalog.json."""
    project_root = Path(project_root)
    document = build_codex(project_root)
    destination = project_root / WIKI_PATH
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_text(json.dumps(document, indent=2) + "\n", encoding="utf-8")
    return document
