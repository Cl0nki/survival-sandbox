"""Write item .tres files from the catalog table. Run from repo root."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1] / "resources" / "items"
SCRIPT = "res://scripts/items/item_definition.gd"

TPL = """[gd_resource type="Resource" script_class="ItemDefinition" load_steps=2 format=3]

[ext_resource type="Script" path="{script}" id="1_item"]

[resource]
script = ExtResource("1_item")
id = "{id}"
display_name = "{name}"
description = "{desc}"
max_stack = {stack}
weight = {weight}
category = "{cat}"
can_pickup = true
can_store = true
swatch = Color({r}, {g}, {b}, 1)
{harvest}"""


def item(folder, item_id, name, desc, stack, weight, cat, rgb, harvest=None):
    return {
        "folder": folder,
        "id": item_id,
        "name": name,
        "desc": desc.replace('"', '\\"'),
        "stack": stack,
        "weight": weight,
        "cat": cat,
        "rgb": rgb,
        "harvest": harvest,
    }


ITEMS = [
    # Harvestable
    item("harvestable", "log", "Log", "Rough timber from felled trees. Saw into plank.", 50, 0.45, "harvest", (0.55, 0.38, 0.22)),
    item("harvestable", "stick", "Stick", "Broken branches. Kindling and light framing.", 50, 0.08, "harvest", (0.62, 0.46, 0.28)),
    item("harvestable", "plant_resin", "Plant Resin", "Sticky sap from felled trees.", 50, 0.12, "harvest", (0.72, 0.52, 0.18)),
    item("harvestable", "stone", "Stone", "Rough rock. Break it from boulders.", 50, 0.55, "harvest", (0.52, 0.52, 0.50)),
    item("harvestable", "limestone", "Limestone", "Soft pale stone used for mortar and cement.", 50, 0.50, "harvest", (0.78, 0.74, 0.64)),
    item("harvestable", "clay", "Clay", "Wet earth. Dig it from riverbanks.", 50, 0.40, "harvest", (0.62, 0.36, 0.24)),
    item("harvestable", "sand", "Sand", "Loose grit. Shovel it from dunes and pits.", 50, 0.40, "harvest", (0.84, 0.74, 0.48)),
    item("harvestable", "gravel", "Gravel", "Loose stone. Shovel it from ground deposits.", 50, 0.50, "harvest", (0.52, 0.52, 0.52)),
    item("harvestable", "iron_ore", "Iron Ore", "Red-brown ore. Needs a furnace.", 50, 0.70, "harvest", (0.48, 0.28, 0.22)),
    item("harvestable", "copper_ore", "Copper Ore", "Green-stained ore for wiring and ingots.", 50, 0.65, "harvest", (0.72, 0.42, 0.22)),
    item("harvestable", "coal", "Coal", "Black fuel for furnaces and forges.", 50, 0.35, "harvest", (0.18, 0.18, 0.20)),
    item("harvestable", "sulfur", "Sulfur", "Yellow mineral. Feedstock for gunpowder and chemicals.", 50, 0.30, "harvest", (0.86, 0.78, 0.22)),
    item("harvestable", "bauxite", "Bauxite", "Red aluminum ore. Needs a furnace.", 50, 0.60, "harvest", (0.72, 0.38, 0.22)),
    item("harvestable", "lead_ore", "Lead Ore", "Heavy dull ore for ballast and shot.", 50, 0.80, "harvest", (0.36, 0.38, 0.42)),
    item("harvestable", "quartz", "Quartz", "Hard crystal. Cuts slowly even with a good pick.", 50, 0.45, "harvest", (0.86, 0.84, 0.78)),
    item("harvestable", "steel_scrap", "Steel Scrap", "Heavier salvage than rusted scrap metal.", 50, 0.50, "harvest", (0.42, 0.46, 0.50)),
    item("harvestable", "electronics", "Electronics", "Pulled boards and chips from wrecks.", 30, 0.20, "harvest", (0.22, 0.48, 0.32)),
    item("harvestable", "plastic", "Plastic", "Broken housings and bottles.", 50, 0.15, "harvest", (0.35, 0.58, 0.72)),
    item("harvestable", "rubber", "Rubber", "Tires, seals, and hoses.", 50, 0.25, "harvest", (0.22, 0.22, 0.24)),
    item("harvestable", "glass", "Glass", "Broken panes and bottles. Recast or reuse.", 50, 0.25, "harvest", (0.62, 0.78, 0.82)),
    item("harvestable", "mechanical_part", "Mechanical Part", "Gears, housings, and seized assemblies.", 30, 0.45, "harvest", (0.46, 0.44, 0.40)),
    item("harvestable", "chemicals", "Chemicals", "Unlabeled drums and lab leftovers.", 20, 0.50, "harvest", (0.42, 0.72, 0.38)),
    item("harvestable", "fuel", "Fuel", "Refined or siphoned liquid fuel.", 20, 0.70, "harvest", (0.72, 0.55, 0.16)),
    item("harvestable", "bucket_empty", "Empty Bucket", "Place in a well. Comes out full of water.", 1, 1.2, "container", (0.55, 0.58, 0.62)),
    item("harvestable", "bucket_full", "Full Bucket", "A bucket of water from a well.", 1, 4.0, "container", (0.28, 0.48, 0.66)),
    item("harvestable", "water_bottle_empty", "Empty Water Bottle", "Place in a well. Comes out full.", 1, 0.2, "container", (0.62, 0.72, 0.78)),
    item("harvestable", "water_bottle_full", "Full Water Bottle", "A bottle of water from a well.", 1, 0.8, "container", (0.32, 0.55, 0.72)),
    item("harvestable", "gas_bottle_empty", "Empty Gas Bottle", "Place in a gas pump jack. Comes out full.", 1, 0.4, "container", (0.7, 0.72, 0.4)),
    item("harvestable", "gas_bottle_full", "Full Gas Bottle", "A bottle of natural gas.", 1, 0.6, "container", (0.78, 0.74, 0.22)),
    item("harvestable", "oil_drum_empty", "Empty Oil Drum", "Place in a crude pump jack. Comes out full.", 1, 8.0, "container", (0.42, 0.36, 0.28)),
    item("harvestable", "oil_drum_full", "Full Oil Drum", "A drum of crude oil.", 1, 20.0, "container", (0.16, 0.12, 0.1)),
    item("harvestable", "battery", "Battery", "Salvaged cells. Still hold a charge.", 20, 0.40, "harvest", (0.28, 0.62, 0.36)),
    item("food", "raw_meat", "Raw Meat", "Uncooked meat. Cook it on a fire.", 20, 0.40, "food", (0.62, 0.22, 0.20)),
    item("food", "cooked_meat", "Cooked Meat", "Meat cooked over a fire.", 20, 0.35, "food", (0.48, 0.28, 0.16)),
    item("food", "raw_fish", "Raw Fish", "Uncooked fish. Cook it on a fire.", 20, 0.30, "food", (0.72, 0.74, 0.70)),
    item("food", "cooked_fish", "Cooked Fish", "Fish cooked over a fire.", 20, 0.28, "food", (0.78, 0.58, 0.32)),
    item("food", "potato", "Potato", "A raw potato. Bake it on a fire, or stew it in a pot.", 20, 0.25, "food", (0.76, 0.64, 0.36)),
    item("food", "baked_potato", "Baked Potato", "A potato baked over a fire.", 20, 0.22, "food", (0.62, 0.44, 0.22)),
    item("food", "mushroom", "Mushroom", "A raw mushroom. Cook it on a fire.", 20, 0.08, "food", (0.72, 0.62, 0.52)),
    item("food", "cooked_mushroom", "Cooked Mushroom", "A mushroom cooked over a fire.", 20, 0.08, "food", (0.48, 0.36, 0.28)),
    item("food", "egg", "Egg", "A raw egg. Fry it on a fire.", 20, 0.06, "food", (0.92, 0.88, 0.72)),
    item("food", "fried_egg", "Fried Egg", "An egg fried over a fire.", 20, 0.06, "food", (0.95, 0.82, 0.28)),
    item("food", "corn", "Corn", "A raw ear of corn. Cook it on a fire.", 20, 0.20, "food", (0.92, 0.78, 0.22)),
    item("food", "cooked_corn", "Cooked Corn", "Corn cooked over a fire.", 20, 0.18, "food", (0.82, 0.62, 0.18)),
    item("food", "meat_stew", "Meat Stew", "Meat and potato cooked in a pot.", 10, 0.55, "food", (0.46, 0.28, 0.16)),
    item("food", "fish_stew", "Fish Stew", "Fish and potato cooked in a pot.", 10, 0.50, "food", (0.58, 0.48, 0.28)),
    # Refined
    item("refined", "plank", "Plank", "Sawn from log. Ready to build with.", 50, 0.30, "refined", (0.70, 0.52, 0.30)),
    item("refined", "brick", "Brick", "Fired clay brick.", 50, 0.45, "refined", (0.62, 0.28, 0.22)),
    item("refined", "mortar", "Mortar", "Lime mix for binding brick and stone.", 50, 0.35, "refined", (0.72, 0.70, 0.64)),
    item("refined", "cut_stone", "Cut Stone", "Dressed blocks for walls and foundations.", 50, 0.70, "refined", (0.58, 0.58, 0.56)),
    item("refined", "cement", "Cement", "Binder for concrete.", 50, 0.40, "refined", (0.68, 0.68, 0.66)),
    item("refined", "concrete_mix", "Concrete Mix", "Cement, sand, and aggregate ready to pour.", 50, 0.80, "refined", (0.56, 0.54, 0.50)),
    item("refined", "iron_ingot", "Iron Ingot", "Smelted iron bars.", 50, 0.80, "refined", (0.58, 0.58, 0.62)),
    item("refined", "steel_ingot", "Steel Ingot", "Hardened iron with carbon.", 50, 0.85, "refined", (0.40, 0.44, 0.50)),
    item("refined", "copper_ingot", "Copper Ingot", "Smelted copper bars.", 50, 0.75, "refined", (0.80, 0.48, 0.24)),
    item("refined", "lead_ingot", "Lead Ingot", "Smelted lead bars.", 50, 0.90, "refined", (0.45, 0.46, 0.50)),
    item("refined", "aluminum_ingot", "Aluminum Ingot", "Smelted aluminum from bauxite.", 50, 0.40, "refined", (0.78, 0.80, 0.82)),
    item("refined", "composite_stock", "Composite Stock", "Smelted quartz. Stock for composite tools.", 50, 0.35, "refined", (0.70, 0.68, 0.78)),
    item("refined", "refined_plastic", "Refined Plastic", "Clean polymer stock.", 50, 0.18, "refined", (0.55, 0.78, 0.88)),
    item("refined", "synthetic_rubber", "Synthetic Rubber", "Processed rubber sheet.", 50, 0.28, "refined", (0.30, 0.30, 0.32)),
    item("refined", "gunpowder", "Gunpowder", "Milled sulfur and charcoal.", 50, 0.12, "explosive", (0.28, 0.26, 0.22)),
    # Crafted components
    item("components", "metal_part", "Metal Part", "Cut and stamped iron fittings.", 30, 0.35, "component", (0.62, 0.64, 0.68)),
    item("components", "steel_plate", "Steel Plate", "Flat steel stock.", 30, 0.70, "component", (0.38, 0.42, 0.48)),
    item("components", "metal_beam", "Metal Beam", "Structural lengths for frames.", 20, 1.20, "component", (0.44, 0.46, 0.50)),
    item("components", "nail", "Nail", "Iron nail for timber work.", 100, 0.02, "component", (0.55, 0.55, 0.52)),
    item("components", "screw_bolt", "Screw & Bolt", "Threaded fasteners.", 100, 0.02, "component", (0.50, 0.52, 0.55)),
    item("components", "pipe", "Pipe", "Metal pipe lengths.", 30, 0.50, "component", (0.48, 0.50, 0.42)),
    item("components", "wiring", "Wiring", "Insulated copper runs.", 50, 0.08, "component", (0.78, 0.58, 0.22)),
    item("components", "circuit_board", "Circuit Board", "Assembled boards from refined electronics.", 20, 0.15, "component", (0.18, 0.42, 0.28)),
    item("components", "mechanical_component", "Mechanical Component", "Rebuilt assemblies from salvage.", 20, 0.40, "component", (0.50, 0.48, 0.40)),
    item("components", "industrial_motor", "Industrial Motor", "Heavy electric motors.", 10, 2.00, "component", (0.32, 0.34, 0.38)),
    item("components", "composite_panel", "Composite Panel", "Layered structural sheets.", 20, 0.45, "component", (0.42, 0.40, 0.48)),
    item("components", "reinforcement_mesh", "Reinforcement Mesh", "Wire grid for concrete and composites.", 20, 0.55, "component", (0.60, 0.60, 0.58)),
    item("components", "explosive_compound", "Explosive Compound", "Stable mixed charge for demolitions.", 20, 0.25, "explosive", (0.72, 0.28, 0.18)),
    # Military
    item("military", "ammo_9mm", "9mm Ammunition", "Pistol and SMG cartridges.", 60, 0.02, "ammo", (0.78, 0.70, 0.28)),
    item("military", "ammo_45acp", ".45 ACP Ammunition", "Heavy pistol cartridges.", 60, 0.025, "ammo", (0.72, 0.62, 0.28)),
    item("military", "ammo_556", "5.56mm Ammunition", "Rifle cartridges.", 60, 0.02, "ammo", (0.58, 0.68, 0.32)),
    item("military", "ammo_762", "7.62mm Ammunition", "Full-power rifle cartridges.", 60, 0.03, "ammo", (0.48, 0.58, 0.30)),
    item("military", "ammo_12gauge", "12 Gauge Ammunition", "Shotgun shells.", 40, 0.04, "ammo", (0.72, 0.32, 0.22)),
    item("military", "ammo_50bmg", ".50 BMG Ammunition", "Heavy anti-materiel rounds.", 20, 0.12, "ammo", (0.36, 0.36, 0.32)),
    item("military", "explosive_round", "Explosive Round", "Tipped cartridges that burst on impact.", 20, 0.06, "explosive", (0.80, 0.42, 0.16)),
    item("military", "grenade", "Grenade", "Hand-thrown fragmentation.", 10, 0.40, "explosive", (0.32, 0.40, 0.24)),
    item("military", "demolition_charge", "Demolition Charge", "Placed breaching charges.", 10, 1.20, "explosive", (0.55, 0.22, 0.16)),
    item("military", "mine", "Mine", "Pressure-triggered charges.", 10, 1.00, "explosive", (0.28, 0.30, 0.22)),
    item("military", "rocket_warhead", "Rocket Warhead", "Payloads for a launcher.", 5, 2.50, "explosive", (0.42, 0.28, 0.18)),
    # Harvest tools, four tiers
    item("tools", "hatchet_scrap", "Scrap Hatchet", "Tier I. Chops wood. Soft and short-lived.", 1, 1.4, "tool", (0.62, 0.64, 0.68), ("hatchet", 1, 8)),
    item("tools", "hatchet_iron", "Iron Hatchet", "Tier II. Chops wood faster than scrap.", 1, 1.6, "tool", (0.58, 0.58, 0.62), ("hatchet", 2, 14)),
    item("tools", "hatchet_steel", "Steel Hatchet", "Tier III. Reliable woodcutting.", 1, 1.7, "tool", (0.40, 0.44, 0.50), ("hatchet", 3, 22)),
    item("tools", "hatchet_composite", "Composite Hatchet", "Tier IV. Light and hard on timber.", 1, 1.3, "tool", (0.42, 0.40, 0.48), ("hatchet", 4, 36)),
    item("tools", "pickaxe_scrap", "Scrap Pickaxe", "Tier I. Breaks stone and ore slowly.", 1, 2.0, "tool", (0.62, 0.64, 0.68), ("pickaxe", 1, 8)),
    item("tools", "pickaxe_iron", "Iron Pickaxe", "Tier II. Breaks stone and ore.", 1, 2.2, "tool", (0.58, 0.58, 0.62), ("pickaxe", 2, 14)),
    item("tools", "pickaxe_steel", "Steel Pickaxe", "Tier III. Cuts hard rock cleanly.", 1, 2.4, "tool", (0.40, 0.44, 0.50), ("pickaxe", 3, 22)),
    item("tools", "pickaxe_composite", "Composite Pickaxe", "Tier IV. Fastest stone and ore tool.", 1, 1.8, "tool", (0.42, 0.40, 0.48), ("pickaxe", 4, 36)),
    item("tools", "shovel_scrap", "Scrap Shovel", "Tier I. Digs sand and clay slowly.", 1, 1.5, "tool", (0.62, 0.64, 0.68), ("shovel", 1, 8)),
    item("tools", "shovel_iron", "Iron Shovel", "Tier II. Digs sand and clay.", 1, 1.7, "tool", (0.58, 0.58, 0.62), ("shovel", 2, 14)),
    item("tools", "shovel_steel", "Steel Shovel", "Tier III. Moves earth quickly.", 1, 1.8, "tool", (0.40, 0.44, 0.50), ("shovel", 3, 22)),
    item("tools", "shovel_composite", "Composite Shovel", "Tier IV. Lightest digging tool.", 1, 1.2, "tool", (0.42, 0.40, 0.48), ("shovel", 4, 36)),
    item("tools", "crowbar_scrap", "Scrap Crowbar", "Tier I. Pries scrap from wrecks slowly.", 1, 1.6, "tool", (0.62, 0.64, 0.68), ("crowbar", 1, 8)),
    item("tools", "crowbar_iron", "Iron Crowbar", "Tier II. Strips wrecks faster than scrap.", 1, 1.8, "tool", (0.58, 0.58, 0.62), ("crowbar", 2, 14)),
    item("tools", "crowbar_steel", "Steel Crowbar", "Tier III. Reliable salvage tool.", 1, 1.9, "tool", (0.40, 0.44, 0.50), ("crowbar", 3, 22)),
    item("tools", "crowbar_composite", "Composite Crowbar", "Tier IV. Light and hard on wrecks.", 1, 1.4, "tool", (0.42, 0.40, 0.48), ("crowbar", 4, 36)),
    # Placeable deployables. The workbench has no station use yet.
    item("deployables", "chest", "Chest", "A placeable crate. Takes a 2x1 on the building grid. 100 HP.", 1, 8.0, "deployable", (0.42, 0.28, 0.16)),
    item("deployables", "workbench", "Workbench", "1x1 bench. Nail, scrap tools, and metal part. One coal. 100 HP.", 1, 12.0, "deployable", (0.52, 0.36, 0.20)),
    item("deployables", "workbench_iron", "Iron Workbench", "1x1 bench. Iron tools, wiring, and metal beam. 200 HP.", 1, 16.0, "deployable", (0.58, 0.58, 0.62)),
    item("deployables", "workbench_steel", "Steel Workbench", "1x1 bench. Steel tools, steel plate, pipe, and screw bolt. Half the coal. 400 HP.", 1, 18.0, "deployable", (0.40, 0.44, 0.50)),
    item("deployables", "workbench_composite", "Composite Workbench", "1x1 bench. Composite tools, industrial motor, and composite panel. 800 HP.", 1, 16.0, "deployable", (0.42, 0.40, 0.48)),
    item("deployables", "sawbench", "Sawbench", "1x1 saw. One log and one coal become four plank. 150 HP.", 1, 10.0, "deployable", (0.62, 0.44, 0.24)),
    item("deployables", "sawmill", "Sawmill", "2x2 mill. Eight log at a time, on half the coal. 400 HP.", 1, 28.0, "deployable", (0.50, 0.34, 0.18)),
    item("deployables", "kiln", "Kiln", "1x1 kiln. Clay, stone, or limestone, with one coal. 200 HP.", 1, 14.0, "deployable", (0.64, 0.32, 0.24)),
    item("deployables", "kiln_shed", "Kiln Shed", "2x2 kiln. Also cement and concrete, eight at a time. 500 HP.", 1, 30.0, "deployable", (0.52, 0.28, 0.22)),
    item("deployables", "chem_bench", "Chem Bench", "1x1 bench. Gunpowder, plastic, rubber, and fuel. 200 HP.", 1, 14.0, "deployable", (0.42, 0.62, 0.36)),
    item("deployables", "refinery", "Refinery", "3x2 refinery. Chem jobs, plus a full oil drum into fuel. 800 HP.", 1, 48.0, "deployable", (0.32, 0.36, 0.34)),
    item("deployables", "machine_shop", "Machine Shop", "3x3 shop. The same bench jobs, twelve at a time. 1200 HP.", 1, 55.0, "deployable", (0.36, 0.38, 0.42)),
    item("deployables", "ammo_bench", "Ammo Bench", "1x1 bench. Gunpowder and metal into rounds. 250 HP.", 1, 16.0, "deployable", (0.48, 0.42, 0.28)),
    item("deployables", "armory", "Armory", "2x2 armory. Round, grenade, mine, and demolition charge. 600 HP.", 1, 32.0, "deployable", (0.32, 0.36, 0.26)),
    item("deployables", "campfire", "Campfire", "1x1 fire. Cooks one meat or fish on stick, log, or coal. 80 HP.", 1, 4.0, "deployable", (0.72, 0.36, 0.16)),
    item("deployables", "fire_pit", "Fire Pit", "2x1 fire. Cooks four at a time. 120 HP.", 1, 8.0, "deployable", (0.46, 0.28, 0.16)),
    item("deployables", "cooking_pot", "Cooking Pot", "1x1 pot. Cooks two at a time. 100 HP.", 1, 6.0, "deployable", (0.40, 0.42, 0.44)),
    item("deployables", "stove", "Stove", "2x1 stove. Cooks four, on half the fuel. 250 HP.", 1, 18.0, "deployable", (0.55, 0.50, 0.46)),
    item("deployables", "kitchen", "Kitchen", "2x2 kitchen. Cooks eight at a time. 400 HP.", 1, 24.0, "deployable", (0.62, 0.58, 0.50)),
    item("deployables", "furnace_scrap", "Scrap Furnace", "1x1 furnace. Smelts one iron or copper ore with 2 coal. 200 HP.", 1, 14.0, "deployable", (0.55, 0.32, 0.22)),
    item("deployables", "smelter_iron", "Iron Smelter", "2x2 smelter. Iron, copper, and lead, five at a time, one coal each. 400 HP.", 1, 28.0, "deployable", (0.42, 0.42, 0.46)),
    item("deployables", "smelter_steel", "Steel Smelter", "2x3 smelter. Ore, steel, and glass, ten at a time, on half the coal. 800 HP.", 1, 40.0, "deployable", (0.34, 0.40, 0.48)),
    item("deployables", "foundry", "Foundry", "3x3 foundry. Every melt, plus aluminum and composite stock, twenty at a time. Burns coal or fuel. 1600 HP.", 1, 60.0, "deployable", (0.28, 0.22, 0.20)),
    item("deployables", "water_well", "Water Well", "1x1 well. One slot. An empty bucket or water bottle comes out full. 200 HP.", 1, 18.0, "deployable", (0.45, 0.52, 0.56)),
    item("deployables", "pump_jack_gas", "Gas Pump Jack", "3x3 pump jack. Only on a natural gas patch. An empty gas bottle comes out full. 300 HP.", 1, 36.0, "deployable", (0.62, 0.64, 0.32)),
    item("deployables", "pump_jack_oil", "Crude Pump Jack", "2x2 pump jack. One slot. An empty oil drum comes out full. 400 HP.", 1, 36.0, "deployable", (0.24, 0.18, 0.14)),
]


def write_one(entry):
    folder = ROOT / entry["folder"]
    folder.mkdir(parents=True, exist_ok=True)
    r, g, b = entry["rgb"]
    harvest = ""
    extra = entry.get("harvest")
    if extra:
        kind, tier, power = extra
        harvest = (
            f'harvest_kind = "{kind}"\n'
            f"harvest_tier = {tier}\n"
            f"harvest_power = {power}\n"
        )
    text = TPL.format(
        script=SCRIPT,
        id=entry["id"],
        name=entry["name"],
        desc=entry["desc"],
        stack=entry["stack"],
        weight=entry["weight"],
        cat=entry["cat"],
        r=r,
        g=g,
        b=b,
        harvest=harvest,
    )
    path = folder / f"{entry['id']}.tres"
    path.write_text(text, encoding="utf-8")
    return path


def main():
    entries = list(ITEMS)
    # Half of BuildingTier.HEALTH, in the same tier order.
    tiers = [
        ("scrap", "Scrap", (0.72, 0.58, 0.44), 100),
        ("wood", "Wood", (0.78, 0.60, 0.38), 200),
        ("brick", "Brick", (0.74, 0.42, 0.32), 400),
        ("stone", "Stone", (0.76, 0.74, 0.68), 800),
        ("concrete", "Concrete", (0.84, 0.80, 0.74), 1800),
        ("composite", "Composite", (0.46, 0.64, 0.68), 4000),
    ]
    for slug, name, rgb, hp in tiers:
        entries.append(item(
            "deployables", f"door_{slug}", f"{name} Door",
            f"Fits a doorway. Opens and closes with F. {hp} HP.",
            1, 6.0, "deployable", rgb,
        ))
        bars = tuple(round(channel * 0.62, 3) for channel in rgb)
        entries.append(item(
            "deployables", f"window_{slug}", f"{name} Window Bars",
            f"Fits a window opening. {hp} HP.",
            1, 3.0, "deployable", bars,
        ))
    written = [write_one(entry) for entry in entries]
    print(f"wrote {len(written)} items")


if __name__ == "__main__":
    main()
