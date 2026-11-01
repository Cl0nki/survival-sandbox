extends RefCounted
class_name ResourceCatalog

## Static table of harvestable deposits. Clients never accept a deposit from the net.

const MINERAL_ORDER: PackedStringArray = [
	"stone",
	"iron_ore",
	"copper_ore",
	"coal",
	"limestone",
	"sulfur",
	"bauxite",
	"lead_ore",
	"quartz",
]

const TREE_ORDER: PackedStringArray = [
	"oak",
	"birch",
	"spruce",
]

const SCAVENGE_ORDER: PackedStringArray = [
	"broken_car",
	"scrap_pile",
	"rubble_pile",
	"tire_pile",
]

static var _by_id: Dictionary = {}
static var _ready := false


static func get_deposit(deposit_id: String) -> ResourceDeposit:
	_ensure()
	return _by_id.get(deposit_id) as ResourceDeposit


static func known(deposit_id: String) -> bool:
	return get_deposit(deposit_id) != null


static func mineral_ids() -> PackedStringArray:
	_ensure()
	return MINERAL_ORDER.duplicate()


static func tree_ids() -> PackedStringArray:
	_ensure()
	return TREE_ORDER.duplicate()


static func scavenge_ids() -> PackedStringArray:
	_ensure()
	return SCAVENGE_ORDER.duplicate()


static func all_ids() -> PackedStringArray:
	_ensure()
	var ids := MINERAL_ORDER.duplicate()
	ids.append_array(TREE_ORDER)
	ids.append_array(SCAVENGE_ORDER)
	return ids


static func _ensure() -> void:
	if _ready:
		return
	_ready = true
	_add("stone", "Stone", "stone", 40, 8, "pickaxe", 1.0, 1.0, Color(0.52, 0.52, 0.50))
	_add("iron_ore", "Iron Ore", "iron_ore", 70, 5, "pickaxe", 1.6, 1.0, Color(0.48, 0.28, 0.22))
	_add("copper_ore", "Copper Ore", "copper_ore", 55, 6, "pickaxe", 1.3, 1.0, Color(0.72, 0.42, 0.22))
	_add("coal", "Coal", "coal", 45, 8, "pickaxe", 1.1, 1.0, Color(0.18, 0.18, 0.20))
	_add("limestone", "Limestone", "limestone", 35, 8, "pickaxe", 0.9, 1.0, Color(0.78, 0.74, 0.64))
	_add("sulfur", "Sulfur", "sulfur", 50, 5, "pickaxe", 1.2, 1.0, Color(0.86, 0.78, 0.22))
	_add("bauxite", "Bauxite", "bauxite", 65, 5, "pickaxe", 1.5, 1.0, Color(0.72, 0.38, 0.22))
	_add("lead_ore", "Lead Ore", "lead_ore", 60, 5, "pickaxe", 1.4, 1.0, Color(0.36, 0.38, 0.42))
	_add("quartz", "Quartz", "quartz", 80, 4, "pickaxe", 1.8, 1.0, Color(0.86, 0.84, 0.78))
	_add_tree(
		"oak",
		"Oak",
		55,
		1.2,
		Color(0.42, 0.28, 0.16),
		Color(0.22, 0.42, 0.18),
		[["logs", 6], ["sticks", 4], ["plant_resin", 1]]
	)
	_add_tree(
		"birch",
		"Birch",
		32,
		0.8,
		Color(0.82, 0.80, 0.74),
		Color(0.48, 0.62, 0.28),
		[["logs", 3], ["sticks", 8], ["plant_resin", 2]]
	)
	_add_tree(
		"spruce",
		"Spruce",
		48,
		1.0,
		Color(0.32, 0.24, 0.18),
		Color(0.16, 0.36, 0.24),
		[["logs", 5], ["sticks", 6], ["plant_resin", 3]]
	)
	_add_scavenge(
		"broken_car",
		"Broken Down Car",
		56,
		1.4,
		Color(0.45, 0.22, 0.16),
		[["scrap_metal", 6], ["steel_scrap", 3], ["rubber", 2], ["mechanical_parts", 1], ["glass", 2], ["plastic", 2]]
	)
	_add_scavenge(
		"scrap_pile",
		"Scrap Pile",
		32,
		0.8,
		Color(0.48, 0.50, 0.52),
		[["scrap_metal", 10], ["steel_scrap", 2], ["plastic", 4]]
	)
	_add_scavenge(
		"rubble_pile",
		"Rubble Pile",
		40,
		1.1,
		Color(0.55, 0.50, 0.44),
		[["stone", 6], ["limestone", 4], ["scrap_metal", 2]]
	)
	_add_scavenge(
		"tire_pile",
		"Tire Pile",
		24,
		0.7,
		Color(0.12, 0.12, 0.13),
		[["rubber", 8]]
	)


static func _add(
	deposit_id: String,
	display_name: String,
	item_id: String,
	health: int,
	yield_amount: int,
	tool_kind: String,
	resistance: float,
	tool_multiplier: float,
	color: Color
) -> void:
	var deposit := ResourceDeposit.new()
	deposit.id = deposit_id
	deposit.display_name = display_name
	deposit.item_id = item_id
	deposit.health = health
	deposit.yield_amount = yield_amount
	deposit.tool_kind = tool_kind
	deposit.resistance = resistance
	deposit.tool_multiplier = tool_multiplier
	deposit.color = color
	deposit.visual = "rock"
	_by_id[deposit_id] = deposit


static func _add_tree(
	deposit_id: String,
	display_name: String,
	health: int,
	resistance: float,
	trunk: Color,
	foliage: Color,
	yields: Array
) -> void:
	var deposit := ResourceDeposit.new()
	deposit.id = deposit_id
	deposit.display_name = display_name
	deposit.item_id = "logs"
	deposit.health = health
	deposit.yield_amount = 0
	deposit.tool_kind = "hatchet"
	deposit.resistance = resistance
	deposit.tool_multiplier = 1.0
	deposit.color = trunk
	deposit.foliage_color = foliage
	deposit.visual = "tree"
	deposit.yields = yields
	for entry in yields:
		if str(entry[0]) == "logs":
			deposit.yield_amount = int(entry[1])
			break
	_by_id[deposit_id] = deposit


static func _add_scavenge(
	deposit_id: String,
	display_name: String,
	health: int,
	resistance: float,
	color: Color,
	yields: Array
) -> void:
	var deposit := ResourceDeposit.new()
	deposit.id = deposit_id
	deposit.display_name = display_name
	deposit.item_id = str(yields[0][0]) if not yields.is_empty() else ""
	deposit.health = health
	deposit.yield_amount = int(yields[0][1]) if not yields.is_empty() else 0
	deposit.tool_kind = "crowbar"
	deposit.resistance = resistance
	deposit.tool_multiplier = 1.0
	deposit.color = color
	deposit.visual = "rock"
	deposit.yields = yields
	_by_id[deposit_id] = deposit
