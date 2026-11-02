"""Building surfaces that still use a flat color.

Colors come from scripts/building/building_tier.gd. A finished albedo belongs
at assets/textures/<id>/albedo.png.
"""

import re
from pathlib import Path

_COLOR = re.compile(r"Color\(\s*([0-9.]+)\s*,\s*([0-9.]+)\s*,\s*([0-9.]+)")
_KIND = {
    "POST": "post",
    "SLAB": "floor",
    "STAIRS": "stairs",
}
_TIERS = {
    1: ("scrap", "Scrap"),
    2: ("wood", "Wood"),
    3: ("brick", "Brick"),
    4: ("stone", "Stone"),
    5: ("concrete", "Concrete"),
    6: ("composite", "Composite"),
}
_PIECE_LABEL = {"wall": "Wall", "floor": "Floor", "post": "Post", "stairs": "Stairs"}
_ROUGHNESS = {1: 0.97, 2: 0.92, 3: 0.88, 4: 0.78, 5: 0.88, 6: 0.28}
_PIPELINE = {
    ("concrete", "floor"): "concrete_floor",
    ("concrete", "wall"): "concrete_wall",
    ("concrete", "post"): "concrete_wall",
    ("concrete", "stairs"): "concrete_wall",
    ("wood", "wall"): "wood",
    ("wood", "floor"): "wood",
    ("wood", "post"): "wood",
    ("wood", "stairs"): "wood",
    ("brick", "wall"): "brick",
    ("brick", "floor"): "brick",
    ("brick", "post"): "brick",
    ("brick", "stairs"): "brick",
    ("stone", "wall"): "stone",
    ("stone", "floor"): "stone",
    ("stone", "post"): "stone",
    ("stone", "stairs"): "stone",
    ("composite", "wall"): "painted_metal",
    ("composite", "post"): "painted_metal",
    ("composite", "floor"): "painted_metal",
    ("scrap", "floor"): "dirt",
}


def _colors(script: str) -> dict[tuple[str, int], list[float]]:
    start = script.index("func color_for")
    end = script.index("static func roughness_of")
    piece = ""
    tier = 0
    found: dict[tuple[str, int], list[float]] = {}
    for line in script[start:end].splitlines():
        kind = re.search(r"Kind\.([A-Z]+)", line)
        if kind:
            piece = _KIND[kind.group(1)]
            continue
        stripped = line.strip()
        if stripped == "_:":
            indent = len(line) - len(line.lstrip("\t"))
            if indent <= 2:
                piece = "wall"
            else:
                tier = 1
            continue
        number = re.fullmatch(r"(\d+):", stripped)
        if number:
            tier = int(number.group(1))
            continue
        color = _COLOR.search(stripped)
        if color and piece and tier:
            found[(piece, tier)] = [float(color.group(index)) for index in range(1, 4)] + [1.0]
            tier = 0
    return found


def _pipeline_category(slug: str, piece: str) -> str:
    return _PIPELINE.get((slug, piece), "painted_metal" if slug == "composite" else "rusted_metal")


def load_surfaces(project_root: Path, copy: dict | None = None) -> list[dict]:
    script = project_root / "scripts" / "building" / "building_tier.gd"
    colors = _colors(script.read_text(encoding="utf-8"))
    stored = (copy or {}).get("surfaces", {})
    surfaces = []
    for piece in ("wall", "floor", "post", "stairs"):
        for tier, (slug, label) in _TIERS.items():
            swatch = colors.get((piece, tier))
            if swatch is None:
                continue
            roughness = _ROUGHNESS[tier]
            metallic = 0.0
            if tier == 6 and piece != "floor":
                metallic = 0.28 if piece == "post" else 0.45
            if piece == "post":
                roughness = min(1.0, roughness + 0.06)
            surface_id = f"{piece}_{slug}"
            albedo = project_root / "assets" / "textures" / surface_id / "albedo.png"
            saved = stored.get(surface_id) if isinstance(stored, dict) else None
            saved = saved if isinstance(saved, dict) else {}
            ingame = " ".join(str(saved.get("ingame") or "").split())
            image = " ".join(str(saved.get("image") or "").split())
            surfaces.append(
                {
                    "id": surface_id,
                    "display_name": f"{label} {_PIECE_LABEL[piece]}",
                    "description": ingame or f"{label} {piece} surface.",
                    "image_description": image,
                    "material": label,
                    "category": piece,
                    "swatch": swatch,
                    "roughness": round(roughness, 2),
                    "metallic": metallic,
                    "pipeline_category": _pipeline_category(slug, piece),
                    "has_art": albedo.is_file(),
                    "art_file": "albedo.png" if albedo.is_file() else "",
                    "needs_art": not albedo.is_file(),
                }
            )
    return surfaces


def load_grounds(project_root: Path, copy: dict | None = None) -> list[dict]:
    """World pads and deposit patches. A finished albedo is assets/textures/<id>/albedo.png."""
    stored = (copy or {}).get("surfaces", {})
    grounds = []
    for surface_id, name, category, swatch, roughness, description in _GROUNDS:
        albedo = project_root / "assets" / "textures" / surface_id / "albedo.png"
        saved = stored.get(surface_id) if isinstance(stored, dict) else None
        saved = saved if isinstance(saved, dict) else {}
        ingame = " ".join(str(saved.get("ingame") or "").split())
        image = " ".join(str(saved.get("image") or "").split())
        grounds.append(
            {
                "id": surface_id,
                "display_name": name,
                "description": ingame or description,
                "image_description": image,
                "material": name,
                "category": "ground",
                "swatch": swatch,
                "roughness": roughness,
                "metallic": 0.0,
                "pipeline_category": category,
                "has_art": albedo.is_file(),
                "art_file": "albedo.png" if albedo.is_file() else "",
                "needs_art": not albedo.is_file(),
            }
        )
    return grounds


_GROUNDS = (
    ("ground_grass", "Grass", "grass", [0.26, 0.34, 0.20, 1.0], 0.90, "Short grass on the woods pad."),
    ("ground_dirt", "Dirt", "dirt", [0.42, 0.36, 0.24, 1.0], 0.95, "Packed dirt under the ground deposits."),
    ("ground_sand", "Sand", "sand", [0.85, 0.76, 0.54, 1.0], 0.93, "Sand patch. A shovel gathers it."),
    ("ground_clay", "Clay", "clay", [0.62, 0.36, 0.24, 1.0], 0.90, "Clay patch. A shovel gathers it."),
    ("ground_gravel", "Gravel", "gravel", [0.52, 0.52, 0.52, 1.0], 0.94, "Gravel patch. A shovel gathers it."),
    ("ground_water", "Ground Water", "water", [0.22, 0.49, 0.66, 1.0], 0.22, "Shallow water. A well draws from it."),
    ("ground_gas", "Natural Gas", "gas", [0.65, 0.65, 0.29, 1.0], 0.84, "Gas seep. A gas pump draws from it."),
    ("ground_oil", "Crude Oil", "oil", [0.22, 0.19, 0.18, 1.0], 0.45, "Oil seep. An oil pump draws from it."),
)
