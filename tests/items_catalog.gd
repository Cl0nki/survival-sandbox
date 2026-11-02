extends SceneTree

## Headless check that the item catalog and test chests loaded.
## godot --headless --path <project> --script res://tests/items_catalog.gd

const REQUIRED := [
	"logs", "sticks", "plant_resin", "stone", "limestone", "clay", "sand", "gravel", "iron_ore", "copper_ore",
	"coal", "sulfur", "bauxite", "lead_ore", "quartz", "scrap_metal", "steel_scrap",
	"bucket_empty", "bucket_full", "water_bottle_empty", "water_bottle_full",
	"gas_bottle_empty", "gas_bottle_full", "oil_drum_empty", "oil_drum_full",
	"electronics", "plastic", "rubber", "glass", "mechanical_parts",
	"chemicals", "fuel", "batteries",
	"planks", "bricks", "mortar", "cut_stone", "cement", "concrete_mix",
	"iron_ingots", "steel_ingots", "copper_ingots", "lead_ingots", "aluminum_ingots", "composite_stock", "refined_plastic",
	"synthetic_rubber", "gunpowder",
	"metal_parts", "steel_plates", "metal_beams", "nails", "screws_bolts",
	"pipes", "wiring", "circuit_boards", "mechanical_components",
	"industrial_motors", "composite_panels", "reinforcement_mesh",
	"explosive_compound",
	"ammo_9mm", "ammo_45acp", "ammo_556", "ammo_762", "ammo_12gauge",
	"ammo_50bmg", "explosive_rounds", "grenades", "demolition_charges",
	"mines", "rocket_warheads",
	"chest", "workbench", "furnace_scrap", "smelter_iron", "smelter_steel", "foundry",
	"water_well", "pump_jack_gas", "pump_jack_oil",
	"door_scrap", "door_wood", "door_brick", "door_stone", "door_concrete", "door_composite",
	"window_scrap", "window_wood", "window_brick", "window_stone", "window_concrete", "window_composite",
	"hatchet_scrap", "hatchet_iron", "hatchet_steel", "hatchet_composite",
	"pickaxe_scrap", "pickaxe_iron", "pickaxe_steel", "pickaxe_composite",
	"shovel_scrap", "shovel_iron", "shovel_steel", "shovel_composite",
	"crowbar_scrap", "crowbar_iron", "crowbar_steel", "crowbar_composite",
	"cloth", "medical_supplies", "canned_food",
	"raw_meat", "cooked_meat", "raw_fish", "cooked_fish",
	"potato", "baked_potato", "mushroom", "cooked_mushroom",
	"egg", "fried_egg", "corn", "cooked_corn", "meat_stew", "fish_stew",
	"sawbench", "sawmill", "kiln", "kiln_shed",
	"workbench_iron", "workbench_steel", "workbench_composite", "machine_shop",
	"chem_bench", "refinery", "ammo_bench", "armory",
	"campfire", "fire_pit", "cooking_pot", "stove", "kitchen",
]


func _init() -> void:
	physics_frame.connect(_boot, CONNECT_ONE_SHOT)


func _boot() -> void:
	var code := _run()
	if code == 0:
		print("ITEMS_CATALOG_OK")
	quit(code)


func _run() -> int:
	var missing: PackedStringArray = []
	for item_id in REQUIRED:
		if not ItemCatalog.known(item_id):
			missing.append(item_id)
	if not missing.is_empty():
		print("FAIL catalog missing: %s" % ", ".join(missing))
		return 1
	if ItemCatalog.known("wood"):
		print("FAIL wood should be replaced by logs")
		return 1
	if ItemCatalog.known("roubles"):
		print("FAIL roubles should be gone")
		return 1
	if ItemCatalog.known("nitrates"):
		print("FAIL nitrates should be gone")
		return 1
	if ItemCatalog.known("ammunition"):
		print("FAIL generic ammunition should be gone")
		return 1
	if ItemCatalog.known("ground_water") or ItemCatalog.known("natural_gas") or ItemCatalog.known("oil"):
		print("FAIL ground water, natural gas, and crude oil should not be items")
		return 1
	if ItemCatalog.known("door") or ItemCatalog.known("window_bars"):
		print("FAIL generic door and window bars should be split by building tier")
		return 1
	var arena := Node3D.new()
	arena.name = "Arena"
	root.add_child(arena)
	LootLayout.build(arena)
	if arena.get_node_or_null("Loot/supply_crate") != null:
		print("FAIL supply crate should be gone")
		return 1
	if arena.get_node_or_null("Loot/harvest_crate") != null:
		print("FAIL harvest crate should be gone")
		return 1
	if arena.get_node_or_null("Loot/tool_crate") != null:
		print("FAIL tool crate should be gone")
		return 1
	if not _crate_filled(arena, "woods_crate", LootLayout.WOODS):
		return 1
	if not _crate_filled(arena, "mine_crate", LootLayout.MINE):
		return 1
	if not _crate_filled(arena, "ground_crate", LootLayout.GROUND):
		return 1
	if not _crate_filled(arena, "scavenge_crate", LootLayout.SCAVENGE):
		return 1
	if not _crate_filled(arena, "collectable_crate", LootLayout.COLLECTABLES):
		return 1
	if not _crate_filled(arena, "refined_crate", LootLayout.REFINED):
		return 1
	if not _crate_filled(arena, "mill_stock_crate", LootLayout.MILL_STOCK):
		return 1
	if not _crate_filled(arena, "bench_stock_crate", LootLayout.BENCH_STOCK):
		return 1
	if not _crate_filled(arena, "chem_stock_crate", LootLayout.CHEM_STOCK):
		return 1
	if not _crate_filled(arena, "smelt_stock_crate", LootLayout.SMELT_STOCK):
		return 1
	if not _crate_filled(arena, "cook_stock_crate", LootLayout.COOK_STOCK):
		return 1
	if not _crate_filled(arena, "component_crate", LootLayout.COMPONENTS):
		return 1
	if not _crate_filled(arena, "military_crate", LootLayout.MILITARY):
		return 1
	if not _crate_filled(arena, "tier_scrap_crate", LootLayout.TIER_SCRAP):
		return 1
	if not _crate_filled(arena, "tier_wood_crate", LootLayout.TIER_WOOD):
		return 1
	if not _crate_filled(arena, "tier_brick_crate", LootLayout.TIER_BRICK):
		return 1
	if not _crate_filled(arena, "tier_stone_crate", LootLayout.TIER_STONE):
		return 1
	if not _crate_filled(arena, "tier_concrete_crate", LootLayout.TIER_CONCRETE):
		return 1
	if arena.get_node_or_null("Loot/deployables_crate") != null:
		print("FAIL deployables crate should be split")
		return 1
	if not _crate_filled(arena, "smelters_crate", LootLayout.smelter_contents()):
		return 1
	if not _crate_filled(arena, "crafting_crate", LootLayout.crafting_contents()):
		return 1
	if not _crate_filled(arena, "cooking_crate", LootLayout.cooking_contents()):
		return 1
	if not _crate_filled(arena, "pumps_crate", LootLayout.pump_contents()):
		return 1
	if not _crate_filled(arena, "doors_crate", LootLayout.opening_contents()):
		return 1
	if not _crate_filled(arena, "tier_composite_crate", LootLayout.TIER_COMPOSITE):
		return 1
	print("catalog %d items" % ItemCatalog.all_ids().size())
	return 0


func _crate_filled(arena: Node3D, container_id: String, contents: Array) -> bool:
	for entry in contents:
		if not _crate_has(arena, container_id, str(entry[0]), int(entry[1])):
			return false
	return true


func _crate_has(arena: Node3D, container_id: String, item_id: String, qty: int) -> bool:
	var crate := arena.get_node_or_null("Loot/%s" % container_id) as LootContainer
	if crate == null or crate.inventory == null:
		print("FAIL missing crate %s" % container_id)
		return false
	var have := crate.inventory.count_item(item_id)
	if have != qty:
		print("FAIL %s %s was %d, expected %d" % [container_id, item_id, have, qty])
		return false
	return true
