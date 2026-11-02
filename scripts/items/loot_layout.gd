extends RefCounted
class_name LootLayout

## Deterministic test loot. The same nodes are created in local play and on
## every peer. Container contents are authoritative only on the server.

const WOODS := [
	["log", 20],
	["stick", 20],
	["plant_resin", 12],
]

const MINE := [
	["stone", 20],
	["iron_ore", 20],
	["copper_ore", 20],
	["coal", 20],
	["limestone", 20],
	["sulfur", 20],
	["bauxite", 20],
	["lead_ore", 20],
	["quartz", 20],
]

const GROUND := [
	["sand", 20],
	["clay", 20],
	["gravel", 20],
	["bucket_empty", 4],
	["water_bottle_empty", 4],
	["gas_bottle_empty", 4],
	["oil_drum_empty", 4],
]

const SCAVENGE := [
	["scrap_metal", 20],
	["steel_scrap", 20],
	["rubber", 20],
	["mechanical_part", 10],
	["glass", 20],
	["plastic", 20],
	["stone", 20],
	["limestone", 20],
]

## Materials only. Doors and window bars live in the doors chest.
const TIER_SCRAP := [
	["scrap_metal", 40],
	["steel_scrap", 20],
]
const TIER_WOOD := [
	["plank", 40],
	["nail", 40],
]
const TIER_BRICK := [
	["brick", 40],
	["mortar", 20],
]
const TIER_STONE := [
	["cut_stone", 40],
]
const TIER_CONCRETE := [
	["concrete_mix", 30],
	["cement", 20],
	["reinforcement_mesh", 10],
]
const TIER_COMPOSITE := [
	["composite_panel", 20],
]

const MILL_STOCK := [
	["log", 20],
	["clay", 20],
	["stone", 20],
	["limestone", 20],
	["sand", 20],
	["coal", 20],
	["cement", 20],
]

const BENCH_STOCK := [
	["scrap_metal", 20],
	["steel_scrap", 20],
	["stick", 20],
	["iron_ingot", 20],
	["copper_ingot", 20],
	["steel_ingot", 20],
	["coal", 20],
	["electronics", 10],
	["mechanical_part", 10],
	["refined_plastic", 20],
]

const CHEM_STOCK := [
	["plastic", 20],
	["rubber", 20],
	["chemicals", 10],
	["sulfur", 20],
	["oil_drum_full", 1],
	["gunpowder", 20],
	["lead_ingot", 20],
	["aluminum_ingot", 20],
	["explosive_compound", 8],
	["steel_plate", 10],
	["coal", 20],
	["iron_ingot", 20],
	["copper_ingot", 20],
	["steel_ingot", 20],
	["steel_scrap", 20],
]

const SMELT_STOCK := [
	["iron_ore", 20],
	["copper_ore", 20],
	["lead_ore", 20],
	["bauxite", 20],
	["quartz", 20],
	["sand", 20],
	["coal", 20],
	["fuel", 10],
	["iron_ingot", 20],
]

const COOK_STOCK := [
	["raw_meat", 20],
	["raw_fish", 20],
	["potato", 20],
	["mushroom", 20],
	["egg", 20],
	["corn", 20],
	["stick", 20],
	["log", 20],
	["coal", 20],
]

const COLLECTABLES := [
	["electronics", 10],
	["chemicals", 10],
	["fuel", 10],
	["battery", 8],
	["raw_meat", 8],
	["raw_fish", 8],
	["potato", 8],
	["mushroom", 8],
	["egg", 8],
	["corn", 8],
]

const REFINED := [
	["plank", 20],
	["brick", 20],
	["mortar", 20],
	["cut_stone", 20],
	["cement", 20],
	["concrete_mix", 20],
	["glass", 20],
	["iron_ingot", 20],
	["steel_ingot", 20],
	["copper_ingot", 20],
	["refined_plastic", 20],
	["synthetic_rubber", 20],
	["gunpowder", 20],
]

const COMPONENTS := [
	["metal_part", 15],
	["steel_plate", 15],
	["metal_beam", 8],
	["nail", 50],
	["screw_bolt", 50],
	["pipe", 15],
	["wiring", 20],
	["circuit_board", 8],
	["mechanical_component", 8],
	["industrial_motor", 4],
	["battery", 8],
	["composite_panel", 10],
	["reinforcement_mesh", 10],
	["explosive_compound", 8],
]

const MILITARY := [
	["ammo_9mm", 30],
	["ammo_45acp", 30],
	["ammo_556", 30],
	["ammo_762", 30],
	["ammo_12gauge", 20],
	["ammo_50bmg", 10],
	["grenade", 4],
	["smoke_grenade", 4],
	["flash_grenade", 4],
	["demolition_charge", 4],
	["mine", 4],
	["rocket_warhead", 2],
]

static func build(arena: Node3D) -> void:
	if arena.get_node_or_null("Loot") != null:
		return
	var folder := Node3D.new()
	folder.name = "Loot"
	arena.add_child(folder)
	ShowcasePad.add(folder, ShowcasePad.SUPPLIES, Color(0.42, 0.36, 0.24), "ground_dirt")
	ShowcasePad.label(folder, "SUPPLIES", ShowcasePad.SUPPLIES + Vector3(0.0, 2.6, -3.6), 52, Color(0.88, 0.82, 0.55))
	_pickup(folder, "scrap_pile", "scrap_metal", 8, Vector3(-6.0, 0.15, 16.0))
	_pickup(folder, "cloth_pile", "cloth", 6, Vector3(-7.2, 0.15, 16.0))
	_pickup(folder, "food_pile", "canned_food", 3, Vector3(-6.0, 0.15, 14.8))
	_pickup(folder, "scrap_north", "scrap_metal", 12, Vector3(-7.2, 0.15, 14.8))
	_pickup(folder, "scrap_east", "scrap_metal", 12, Vector3(-4.8, 0.15, 14.8))
	_pickup(folder, "medical_pile", "medical_supplies", 2, Vector3(-3.4, 0.15, 16.0))
	_crate(folder, "woods_crate", "Woods", Color(0.30, 0.42, 0.22), ShowcasePad.WOODS_CRATE, WOODS)
	_crate(folder, "mine_crate", "Mine", Color(0.42, 0.36, 0.28), ShowcasePad.MINE + Vector3(0.0, 0.15, -4.2), MINE)
	_crate(folder, "ground_crate", "Ground", Color(0.55, 0.46, 0.28), ShowcasePad.GROUND + Vector3(3.6, 0.15, 2.8), GROUND)
	_crate(folder, "scavenge_crate", "Scavenge", Color(0.40, 0.32, 0.24), ShowcasePad.SCAVENGE + Vector3(3.6, 0.15, 1.4), SCAVENGE)
	_crate(folder, "refined_crate", "Refined", Color(0.48, 0.48, 0.50), ShowcasePad.CRAFTING + Vector3(2.8, 0.15, 4.5), REFINED)
	_crate(folder, "mill_stock_crate", "Mill Stock", Color(0.46, 0.34, 0.22), ShowcasePad.CRAFTING + Vector3(-1.2, 0.15, 4.5), MILL_STOCK)
	_crate(folder, "bench_stock_crate", "Bench Stock", Color(0.42, 0.44, 0.48), ShowcasePad.BENCHES + Vector3(-1.5, 0.15, 4.2), BENCH_STOCK)
	_crate(folder, "chem_stock_crate", "Chem Stock", Color(0.36, 0.46, 0.34), ShowcasePad.CHEM + Vector3(0.0, 0.15, 4.2), CHEM_STOCK)
	_crate(folder, "smelt_stock_crate", "Smelt Stock", Color(0.42, 0.30, 0.24), ShowcasePad.SMELTING + Vector3(0.0, 0.15, 4.5), SMELT_STOCK)
	_crate(folder, "cook_stock_crate", "Cook Stock", Color(0.58, 0.36, 0.22), ShowcasePad.FOOD + Vector3(0.0, 0.15, 4.5), COOK_STOCK)
	_crate(folder, "component_crate", "Parts", Color(0.32, 0.40, 0.48), ShowcasePad.BENCHES + Vector3(1.5, 0.15, 4.2), COMPONENTS)
	_crate(folder, "collectable_crate", "Collectables", Color(0.28, 0.40, 0.36), ShowcasePad.SUPPLIES + Vector3(0.0, 0.15, 2.8), COLLECTABLES)
	_crate(folder, "military_crate", "Military", Color(0.28, 0.32, 0.20), ShowcasePad.RANGE + Vector3(-3.7, 0.15, 3.9), MILITARY)
	_crate(folder, "smelters_crate", "Smelters", Color(0.48, 0.32, 0.24), ShowcasePad.DEPLOYABLES + Vector3(-4.2, 0.15, 1.5), smelter_contents())
	_crate(folder, "crafting_crate", "Crafting", Color(0.52, 0.36, 0.20), ShowcasePad.DEPLOYABLES + Vector3(-1.4, 0.15, 1.5), crafting_contents())
	_crate(folder, "cooking_crate", "Cooking", Color(0.62, 0.34, 0.18), ShowcasePad.DEPLOYABLES + Vector3(-4.2, 0.15, -4.5), cooking_contents())
	_crate(folder, "pumps_crate", "Pumps", Color(0.32, 0.38, 0.36), ShowcasePad.DEPLOYABLES + Vector3(1.4, 0.15, 1.5), pump_contents())
	_crate(folder, "doors_crate", "Doors and Windows", Color(0.50, 0.40, 0.30), ShowcasePad.DEPLOYABLES + Vector3(4.2, 0.15, 1.5), opening_contents())
	_building_chests(folder)


## Furnaces and the foundry.
static func smelter_contents() -> Array:
	return _kind_rows(SmeltRules.ids())


## The placeable chest and every crafting station.
static func crafting_contents() -> Array:
	var rows: Array = [["chest", 1]]
	rows.append_array(_group_rows("craft"))
	return rows


## Campfires and cooking stations.
static func cooking_contents() -> Array:
	return _group_rows("cook")


## The water well and both pump jacks.
static func pump_contents() -> Array:
	return _kind_rows(FillRules.ids())


## One door and one set of window bars for every building tier.
static func opening_contents() -> Array:
	return _kinds_where(false)


static func _kinds_where(on_cells: bool) -> Array:
	var rows: Array = []
	for kind in DeployableCatalog.all_ids():
		if DeployableCatalog.on_cells(str(kind)) != on_cells:
			continue
		rows.append([str(kind), 1])
	return rows


static func _group_rows(group: String) -> Array:
	var rows: Array = []
	for kind in CraftRules.ids():
		if CraftRules.group_of(kind) != group:
			continue
		rows.append([str(kind), 1])
	return rows


static func _kind_rows(ids: PackedStringArray) -> Array:
	var rows: Array = []
	for kind in ids:
		rows.append([str(kind), 1])
	return rows


static func _building_chests(folder: Node3D) -> void:
	var tiers := [
		["tier_scrap_crate", "Scrap", 1, TIER_SCRAP],
		["tier_wood_crate", "Wood", 2, TIER_WOOD],
		["tier_brick_crate", "Brick", 3, TIER_BRICK],
		["tier_stone_crate", "Stone", 4, TIER_STONE],
		["tier_concrete_crate", "Concrete", 5, TIER_CONCRETE],
		["tier_composite_crate", "Composite", 6, TIER_COMPOSITE],
	]
	## Packed into two rows of three with a 1.6 m aisle on x = 0, so a body
	## can walk north through the building tile once the chests are solid.
	var tier_x: PackedFloat32Array = [-4.075, -2.725, -1.375, 1.375, 2.725, 4.075]
	for index in tiers.size():
		var entry: Array = tiers[index]
		var x := tier_x[index]
		_crate(
			folder,
			str(entry[0]),
			str(entry[1]),
			BuildingTier.color_of(int(entry[2])),
			ShowcasePad.BUILDING + Vector3(x, 0.15, -3.6),
			entry[3]
		)


static func _crate(
	folder: Node3D,
	container_id: String,
	prompt: String,
	color: Color,
	pos: Vector3,
	contents: Array
) -> void:
	var crate := LootContainer.new()
	crate.name = container_id
	crate.container_id = container_id
	crate.prompt = prompt
	crate.box_color = color
	crate.slot_count = NetConfig.CONTAINER_SLOTS
	crate.position = pos
	folder.add_child(crate)
	for entry in contents:
		var item_id := str(entry[0])
		var qty := int(entry[1])
		if not crate.inventory.add_exact(item_id, qty):
			push_error("loot crate %s could not add %s x%d" % [container_id, item_id, qty])


static func _label(folder: Node3D, text: String, at: Vector3, color: Color) -> void:
	var label := Label3D.new()
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.position = at
	label.pixel_size = 0.012
	label.font_size = 48
	label.outline_size = 8
	label.text = text
	label.modulate = color
	folder.add_child(label)


static func _pickup(folder: Node3D, pickup_id: String, item_id: String, quantity: int, pos: Vector3) -> void:
	var pickup := WorldPickup.new()
	pickup.name = pickup_id
	pickup.pickup_id = pickup_id
	pickup.item_id = item_id
	pickup.quantity = quantity
	pickup.position = pos
	folder.add_child(pickup)
