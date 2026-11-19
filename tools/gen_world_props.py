"""Write resources/world_props/<id>.tres for every non-placeable world object.

Usage: python tools/gen_world_props.py

The table below is the authoring source. The game reads the .tres files
(scripts/world/world_prop_catalog.gd) and the art pipeline reads the same files
for icons and Meshy target sizes. Health, tool and yield are NOT here: harvest
nodes take them from scripts/items/resource_catalog.gd through deposit_id.

Prop ids must not collide with an item id or a deployable id. The harvest rocks
get a _node suffix for that reason (the item "stone" is not the boulder).
"""

from __future__ import annotations

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "resources" / "world_props"

ROCK = (0.95, 0.85, 0.95)

# id, display name, kind, deposit id, body size (w, h, d), swatch, description
PROPS = [
    ("stone_node", "Stone Boulder", "resource", "stone", ROCK, (0.52, 0.52, 0.50), "A grey boulder. Chip it with a pickaxe."),
    ("iron_ore_node", "Iron Ore Boulder", "resource", "iron_ore", ROCK, (0.48, 0.28, 0.22), "A rust-red rock with iron veins."),
    ("copper_ore_node", "Copper Ore Boulder", "resource", "copper_ore", ROCK, (0.72, 0.42, 0.22), "A rock streaked with orange copper."),
    ("coal_node", "Coal Seam", "resource", "coal", ROCK, (0.18, 0.18, 0.20), "A black lump of coal."),
    ("limestone_node", "Limestone Boulder", "resource", "limestone", ROCK, (0.78, 0.74, 0.64), "A pale, layered limestone block."),
    ("sulfur_node", "Sulfur Deposit", "resource", "sulfur", ROCK, (0.86, 0.78, 0.22), "A yellow crust of sulfur crystals."),
    ("bauxite_node", "Bauxite Boulder", "resource", "bauxite", ROCK, (0.72, 0.38, 0.22), "A clay-red aluminium ore rock."),
    ("lead_ore_node", "Lead Ore Boulder", "resource", "lead_ore", ROCK, (0.36, 0.38, 0.42), "A dull blue-grey ore rock."),
    ("quartz_node", "Quartz Outcrop", "resource", "quartz", ROCK, (0.86, 0.84, 0.78), "A cluster of milky quartz."),
    ("tree_oak", "Oak Tree", "resource", "oak", (2.99, 5.14, 2.99), (0.42, 0.28, 0.16), "A broad oak with a round crown."),
    ("tree_birch", "Birch Tree", "resource", "birch", (2.47, 4.62, 2.47), (0.82, 0.80, 0.74), "A slim white birch."),
    ("tree_spruce", "Spruce Tree", "resource", "spruce", (2.47, 4.88, 2.47), (0.32, 0.24, 0.18), "A tall conical spruce."),
    ("cactus", "Cactus", "resource", "cactus", (0.9, 1.55, 0.5), (0.28, 0.48, 0.30), "A desert cactus with one arm."),
    ("dead_bush", "Dead Bush", "resource", "dead_bush", (0.85, 1.0, 0.85), (0.42, 0.30, 0.18), "A dry, leafless shrub."),
    ("broken_car", "Broken Down Car", "resource", "broken_car", (2.2, 1.3, 1.1), (0.45, 0.22, 0.16), "A stripped rusty car."),
    ("scrap_pile", "Scrap Pile", "resource", "scrap_pile", (1.6, 0.9, 1.4), (0.48, 0.50, 0.52), "A heap of scrap metal."),
    ("rubble_pile", "Rubble Pile", "resource", "rubble_pile", (1.5, 1.0, 1.3), (0.55, 0.50, 0.44), "Concrete chunks and bricks."),
    ("tire_pile", "Tire Pile", "resource", "tire_pile", (1.9, 0.85, 1.6), (0.12, 0.12, 0.13), "A heap of worn tires."),
    ("drum_stack", "Drum Stack", "resource", "drum_stack", (1.1, 1.5, 1.0), (0.55, 0.30, 0.18), "Rusty metal drums."),
    ("appliance_pile", "Dead Appliances", "resource", "appliance_pile", (1.5, 1.55, 1.0), (0.78, 0.78, 0.76), "A fridge, a washer and a microwave."),
    ("loot_crate", "Loot Crate", "crate", "", (1.15, 0.72, 0.8), (0.42, 0.30, 0.18), "A wooden storage crate with a lid."),
    # NEXUS storage. Contents come from the NEXUS_* tables in scripts/items/loot_layout.gd.
    # Swatches are placeholders until the NEXUS palette is decided.
    ("nexus_shipping_container", "NEXUS Shipping Container", "crate", "", (6.06, 2.6, 2.44), (0.36, 0.40, 0.44), "A 20-foot NEXUS LOGISTICS cargo container, still sealed and waiting for a MULE that never came. Packed with freight."),
    ("nexus_supply_chest", "NEXUS Supply Chest", "crate", "", (1.2, 0.7, 0.8), (0.40, 0.44, 0.46), "A stackable NEXUS LOGISTICS transit case. Holds batteries, electronics, and general stock."),
    ("nexus_parts_chest", "NEXUS Parts Chest", "crate", "", (0.9, 1.0, 0.6), (0.46, 0.44, 0.38), "A NEXUS CONSTRUCTION maintenance chest. Spare mechanical parts and fasteners for field repairs."),
    ("nexus_security_lockbox", "NEXUS Security Lockbox", "crate", "", (0.8, 0.6, 0.6), (0.30, 0.34, 0.30), "An armored NEXUS SECURITY lockbox. Access-controlled, though nobody is left to check credentials."),
]


def _num(value: float) -> str:
    return f"{value:g}"


def _color(rgb: tuple[float, float, float]) -> str:
    return "Color(%s, %s, %s, 1)" % tuple(_num(channel) for channel in rgb)


def _kept_description(path: Path, fallback: str) -> str:
    """The dashboard edits the description inside the file, so a rerun keeps it."""
    if not path.is_file():
        return fallback
    match = re.search(r'^description = "(.*)"$', path.read_text(encoding="utf-8"), re.M)
    return match.group(1) if match else fallback


def _tres(entry: tuple, description: str) -> str:
    prop_id, name, kind, deposit_id, size, swatch, _default = entry
    lines = [
        '[gd_resource type="Resource" script_class="WorldPropDefinition" load_steps=2 format=3]',
        "",
        '[ext_resource type="Script" path="res://scripts/world/world_prop_definition.gd" id="1_def"]',
        "",
        "[resource]",
        'script = ExtResource("1_def")',
        f'id = "{prop_id}"',
        f'display_name = "{name}"',
        f'description = "{description}"',
        'category = "world_prop"',
        f'kind = "{kind}"',
        f'deposit_id = "{deposit_id}"',
        "body_size = Vector3(%s, %s, %s)" % tuple(_num(axis) for axis in size),
        f"swatch = {_color(swatch)}",
        "",
    ]
    return "\n".join(lines)


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    wanted = set()
    for entry in PROPS:
        path = OUT / f"{entry[0]}.tres"
        description = _kept_description(path, entry[6])
        path.write_text(_tres(entry, description), encoding="utf-8", newline="\n")
        wanted.add(path.name)
    for stale in OUT.glob("*.tres"):
        if stale.name not in wanted:
            stale.unlink()
    print(f"wrote {len(PROPS)} world props to {OUT}")


if __name__ == "__main__":
    main()
