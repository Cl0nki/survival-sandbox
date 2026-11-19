"""Write the weapon item .tres files. Run from repo root: python tools/gen_weapons.py

The pistol and the debug weapon are hand-written in resources/items. Everything
else that shoots or swings is a row here, so a new gun is one line plus a recipe
in scripts/deployables/craft_rules.gd.

Names are invented on purpose. They echo the real guns they stand in for
(compact bullpup PDW, 1911-style heavy pistol, AR-style rifle, M2-style heavy
machine gun, anti-materiel rifle) without using a maker's name or model.
"""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1] / "resources" / "items" / "weapons"
SCRIPT = "res://scripts/items/item_definition.gd"

TPL = """[gd_resource type="Resource" script_class="ItemDefinition" load_steps=2 format=3]

[ext_resource type="Script" path="{script}" id="1_item"]

[resource]
script = ExtResource("1_item")
id = "{id}"
display_name = "{name}"
description = "{desc}"
max_stack = 1
weight = {weight}
category = "weapon"
can_pickup = true
can_store = true
swatch = Color({r}, {g}, {b}, 1)
weapon_kind = "{kind}"
ammo_id = "{ammo}"
weapon_damage = {damage}
weapon_range = {range}
weapon_cooldown = {cooldown}
weapon_pellets = {pellets}
weapon_spread_deg = {spread}
weapon_automatic = {auto}
weapon_length = {length}
"""

AMMO_9 = "ammo_9mm"
AMMO_45 = "ammo_45acp"
AMMO_556 = "ammo_556"
AMMO_762 = "ammo_762"
AMMO_12 = "ammo_12gauge"
AMMO_50 = "ammo_50bmg"


def gun(item_id, name, desc, weight, rgb, ammo, damage, reach, cooldown, spread, length,
        auto=False, pellets=1):
    return {
        "id": item_id, "name": name, "desc": desc, "weight": weight, "rgb": rgb,
        "kind": "firearm", "ammo": ammo, "damage": damage, "range": reach,
        "cooldown": cooldown, "pellets": pellets, "spread": spread,
        "auto": auto, "length": length,
    }


WEAPONS = [
    # 9mm. The scrap Pistol is the entry gun.
    gun("courier_pistol", "Courier Pistol",
        "Machined service pistol. Accurate and quick to follow up. Fires 9mm.",
        1.0, (0.46, 0.48, 0.52), AMMO_9, 38, 45.0, 0.28, 0.5, 0.28),
    gun("hornet_pdw", "Hornet PDW",
        "Compact bullpup personal defense weapon. Light and fast, loose at range. Hold to fire. 9mm.",
        2.4, (0.40, 0.44, 0.40), AMMO_9, 15, 35.0, 0.10, 2.5, 0.36, auto=True),
    # .45 ACP
    gun("marshal_pistol", "Marshal Heavy Pistol",
        "Slow, heavy-hitting sidearm. Fires .45 ACP.",
        1.4, (0.50, 0.46, 0.38), AMMO_45, 52, 42.0, 0.55, 0.5, 0.30),
    gun("rattler_smg", "Rattler SMG",
        "Open-bolt submachine gun with a wide spray. Hold to fire. .45 ACP.",
        3.0, (0.46, 0.40, 0.32), AMMO_45, 24, 32.0, 0.12, 3.2, 0.40, auto=True),
    # 5.56mm
    gun("ridgeback_rifle", "Ridgeback Rifle",
        "Light, accurate assault rifle. The all-rounder. Hold to fire. 5.56mm.",
        3.6, (0.36, 0.42, 0.34), AMMO_556, 26, 70.0, 0.12, 1.2, 0.62, auto=True),
    gun("hailstorm_lmg", "Hailstorm LMG",
        "Belt-fed light machine gun. Heavy, and it drifts when it runs hot. Hold to fire. 5.56mm.",
        7.5, (0.30, 0.34, 0.30), AMMO_556, 21, 65.0, 0.10, 2.6, 0.78, auto=True),
    # 7.62mm
    gun("kodiak_rifle", "Kodiak Battle Rifle",
        "Semi-automatic battle rifle. Every round counts. 7.62mm.",
        4.2, (0.44, 0.34, 0.24), AMMO_762, 56, 80.0, 0.32, 0.6, 0.68),
    gun("falconer_rifle", "Falconer Marksman Rifle",
        "Long, steady rifle for single placed shots. 7.62mm.",
        5.0, (0.34, 0.38, 0.30), AMMO_762, 78, 100.0, 0.70, 0.0, 0.86),
    # 12 gauge. Pellets: damage is per pellet, one shell per pull.
    gun("breacher_shotgun", "Breacher Pump Shotgun",
        "Pump-action shotgun. Brutal up close, useless past a short run. 12 gauge.",
        3.8, (0.40, 0.30, 0.22), AMMO_12, 14, 24.0, 0.85, 4.5, 0.78, pellets=8),
    gun("mule_shotgun", "Mule Sawn-Off Shotgun",
        "Cut-down shotgun. Huge spread, one shell, almost no range. 12 gauge.",
        2.8, (0.46, 0.34, 0.24), AMMO_12, 11, 16.0, 1.0, 8.0, 0.52, pellets=10),
    # .50 BMG
    gun("goliath_amr", "Goliath Anti-Materiel Rifle",
        "Huge rifle that punches through anything it hits once. Slow to cycle. .50 BMG.",
        11.0, (0.26, 0.28, 0.26), AMMO_50, 160, 120.0, 1.25, 0.0, 1.05),
    gun("titan_hmg", "Titan Heavy Machine Gun",
        "Man-portable heavy machine gun. Enormous weight, enormous noise. Hold to fire. .50 BMG.",
        15.0, (0.22, 0.24, 0.22), AMMO_50, 48, 90.0, 0.14, 2.8, 1.0, auto=True),
    {
        "id": "sword", "name": "Steel Sword",
        "desc": "Forged blade. Needs no ammunition. Cuts anything within arm's reach.",
        "weight": 1.6, "rgb": (0.72, 0.74, 0.78),
        "kind": "melee", "ammo": "", "damage": 48, "range": 1.9,
        "cooldown": 0.55, "pellets": 1, "spread": 0.0, "auto": False, "length": 0.9,
    },
]


def write_one(entry):
    ROOT.mkdir(parents=True, exist_ok=True)
    r, g, b = entry["rgb"]
    text = TPL.format(
        script=SCRIPT,
        id=entry["id"],
        name=entry["name"],
        desc=entry["desc"].replace('"', '\\"'),
        weight=entry["weight"],
        r=r, g=g, b=b,
        kind=entry["kind"],
        ammo=entry["ammo"],
        damage=entry["damage"],
        range=entry["range"],
        cooldown=entry["cooldown"],
        pellets=entry["pellets"],
        spread=entry["spread"],
        auto="true" if entry["auto"] else "false",
        length=entry["length"],
    )
    path = ROOT / f"{entry['id']}.tres"
    path.write_text(text, encoding="utf-8", newline="\n")
    return path


def main():
    written = [write_one(entry) for entry in WEAPONS]
    print(f"wrote {len(written)} weapons")


if __name__ == "__main__":
    main()
