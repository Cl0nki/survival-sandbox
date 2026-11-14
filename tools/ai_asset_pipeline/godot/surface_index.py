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
_PIECE_LABEL = {"wall": "Wall", "floor": "Floor"}

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
    ## Walls and floors only. Posts and stairs reuse the wall/floor look in-game.
    script = project_root / "scripts" / "building" / "building_tier.gd"
    colors = _colors(script.read_text(encoding="utf-8"))
    stored = (copy or {}).get("surfaces", {})
    surfaces = []
    for piece in ("wall", "floor"):
        for tier, (slug, label) in _TIERS.items():
            swatch = colors.get((piece, tier))
            if swatch is None:
                continue
            roughness = _ROUGHNESS[tier]
            metallic = 0.45 if tier == 6 and piece != "floor" else 0.0
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
                    "asset_kind": "texture",
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
    for surface_id, name, category, swatch, roughness, description, material in _GROUNDS:
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
                "material": material,
                "category": "forest" if category.startswith("forest_") else "ground",
                "swatch": swatch,

                "roughness": roughness,
                "metallic": 0.0,
                "pipeline_category": category,
                "asset_kind": "texture",
                "has_art": albedo.is_file(),
                "art_file": "albedo.png" if albedo.is_file() else "",
                "needs_art": not albedo.is_file(),
            }
        )
    return grounds



def load_vegetation(project_root: Path, copy: dict | None = None) -> list[dict]:
    """Harvest trees, stones, and ground-scatter plants. Finished meshes are assets/environment/<id>.glb."""
    stored = (copy or {}).get("surfaces", {})
    plants = []
    for plant_id, name, category, swatch, polycount, description in _VEGETATION:
        glb = project_root / "assets" / "environment" / f"{plant_id}.glb"
        saved = stored.get(plant_id) if isinstance(stored, dict) else None
        saved = saved if isinstance(saved, dict) else {}
        ingame = " ".join(str(saved.get("ingame") or "").split())
        image = " ".join(str(saved.get("image") or "").split())
        plants.append(
            {
                "id": plant_id,
                "display_name": name,
                "description": ingame or description,
                "image_description": image,
                "material": "Vegetation",
                "category": "vegetation",
                "swatch": swatch,
                "roughness": 0.9,
                "metallic": 0.0,
                "pipeline_category": category,
                "asset_kind": "prop",
                "polycount": polycount,
                "has_art": glb.is_file(),
                "art_file": f"{plant_id}.glb" if glb.is_file() else "",
                "needs_art": not glb.is_file(),
            }
        )
    return plants


## (id, display name, pipeline_category, swatch, roughness, description, material group)
_GROUNDS = (
    ("ground_forest_oak", "Oak Forest Floor", "forest_oak", [0.42, 0.34, 0.18, 1.0], 0.92, "Warm oak forest floor with leaf litter.", "Forest"),
    ("ground_forest_birch", "Birch Forest Floor", "forest_birch", [0.55, 0.58, 0.40, 1.0], 0.88, "Pale birch forest floor with light litter.", "Forest"),
    ("ground_forest_spruce", "Spruce Forest Floor", "forest_spruce", [0.18, 0.26, 0.16, 1.0], 0.94, "Dark spruce needle carpet.", "Forest"),
    ("ground_grass", "Grass", "grass", [0.26, 0.34, 0.20, 1.0], 0.90, "Short grass on open ground.", "Grass"),
    ("ground_meadow", "Meadow", "meadow", [0.30, 0.42, 0.22, 1.0], 0.86, "Lush meadow ground with soft mixed grass.", "Meadow"),
    ("ground_dirt", "Dirt", "dirt", [0.42, 0.36, 0.24, 1.0], 0.95, "Packed dirt under the ground deposits.", "Dirt"),
    ("ground_rock", "Rock", "rock", [0.48, 0.46, 0.44, 1.0], 0.92, "Rocky stone ground for hard terrain.", "Rock"),
    ("ground_asphalt", "Asphalt", "asphalt", [0.28, 0.28, 0.30, 1.0], 0.92, "Worn asphalt for the scrap / scavenge yard.", "Asphalt"),
    ("ground_sand", "Sand", "sand", [0.85, 0.76, 0.54, 1.0], 0.93, "Sand patch. A shovel gathers it.", "Soil"),
    ("ground_clay", "Clay", "clay", [0.62, 0.36, 0.24, 1.0], 0.90, "Clay patch. A shovel gathers it.", "Soil"),
    ("ground_gravel", "Gravel", "gravel", [0.52, 0.52, 0.52, 1.0], 0.94, "Gravel patch. A shovel gathers it.", "Soil"),
    ("ground_water", "Ground Water", "water", [0.22, 0.49, 0.66, 1.0], 0.22, "Shallow water. A well draws from it.", "Fluid"),
    ("ground_gas", "Natural Gas", "gas", [0.65, 0.65, 0.29, 1.0], 0.84, "Gas seep. A gas pump draws from it.", "Fluid"),
    ("ground_oil", "Crude Oil", "oil", [0.22, 0.19, 0.18, 1.0], 0.45, "Oil seep. An oil pump draws from it.", "Fluid"),
)



## Harvest trees, stone props, and scatter plants for meadow / woods pads.
_VEGETATION = (
    (
        "tree_oak",
        "Oak Tree",
        "tree",
        [0.42, 0.28, 0.16, 1.0],
        8000,
        "Broad oak harvest tree with a thick trunk and a round leafy crown.",
    ),
    (
        "tree_birch",
        "Birch Tree",
        "tree",
        [0.82, 0.80, 0.74, 1.0],
        6500,
        "Tall birch harvest tree with pale bark and a light open crown.",
    ),
    (
        "tree_spruce",
        "Spruce Tree",
        "tree",
        [0.36, 0.24, 0.16, 1.0],
        7000,
        "Conical spruce harvest tree with layered evergreen needles.",
    ),
    (
        "stone_boulder",
        "Stone Boulder",
        "boulder",
        [0.52, 0.52, 0.50, 1.0],
        3500,
        "Readable stone boulder for the rock / mine field.",
    ),
    (
        "grass_tuft",
        "Grass Tuft",
        "grass_tuft",
        [0.34, 0.46, 0.22, 1.0],
        900,
        "Small low-poly grass clump for meadow and woods scatter.",
    ),
    (
        "fern",
        "Fern",
        "fern",
        [0.28, 0.48, 0.24, 1.0],
        1200,
        "Small stylized fern frond clump for meadow and woods scatter.",
    ),
)
