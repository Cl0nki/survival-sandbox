extends RefCounted
class_name SmeltRules

## One smelt job for a furnace, smelter, or foundry.
## A station runs a single batch. Higher tiers melt more, faster, on less coal.
## The foundry also burns fuel, and it is the only one that makes aluminum
## and composite stock.

const INPUT := 0
const FUEL := 1
const OUTPUT := 2
const SLOTS := 3
## One fuel item stands in for this many coal.
const FUEL_PER_COAL := 2

static var _specs: Dictionary = {}
static var _recipes: Array = []


static func known(kind: String) -> bool:
	return not _spec(kind).is_empty()


static func ids() -> PackedStringArray:
	_warm()
	var packed := PackedStringArray()
	for kind in _specs.keys():
		packed.append(str(kind))
	return packed


static func display_name(kind: String) -> String:
	var spec := _spec(kind)
	if spec.is_empty():
		return kind
	return str(spec["name"])


static func footprint(kind: String) -> Vector2i:
	var spec := _spec(kind)
	if spec.is_empty():
		return Vector2i.ZERO
	return spec["footprint"]


static func max_health(kind: String) -> int:
	return int(_spec(kind).get("hp", 0))


static func color_of(kind: String) -> Color:
	var spec := _spec(kind)
	if spec.is_empty():
		return Color(0.4, 0.32, 0.28)
	return spec["color"]


static func hint(kind: String) -> String:
	var spec := _spec(kind)
	if spec.is_empty():
		return ""
	return str(spec["hint"])


static func accepts_input(kind: String, item_id: String) -> bool:
	return not _recipe(kind, item_id).is_empty()


static func accepts_fuel(kind: String, item_id: String) -> bool:
	if _spec(kind).is_empty():
		return false
	if item_id == "coal":
		return true
	return item_id == "fuel" and bool(_spec(kind)["burns_fuel"])


## How many fuel items a batch of `count` needs. -1 when that fuel cannot be used.
static func fuel_cost(kind: String, item_id: String, fuel_id: String, count: int) -> int:
	var spec := _spec(kind)
	var recipe := _recipe(kind, item_id)
	if spec.is_empty() or recipe.is_empty() or count <= 0:
		return -1
	var num := int(spec["ore_num"])
	var den := int(spec["ore_den"])
	if bool(recipe["alloy"]):
		num = int(spec["alloy_num"])
		den = int(spec["alloy_den"])
	if num <= 0 or den <= 0:
		return -1
	var coal := ceili(float(count * num) / float(den))
	if fuel_id == "coal":
		return coal
	if fuel_id == "fuel" and bool(spec["burns_fuel"]):
		return ceili(float(coal) / float(FUEL_PER_COAL))
	return -1


## Largest job the loaded slots can run right now.
static func plan(
	kind: String,
	input_id: String,
	input_qty: int,
	fuel_id: String,
	fuel_qty: int,
	output_id: String,
	output_qty: int
) -> Dictionary:
	var empty := {
		"ok": false,
		"reason": "",
		"input_id": input_id,
		"output_id": "",
		"fuel_id": fuel_id,
		"count": 0,
		"fuel_count": 0,
		"seconds": 0.0,
	}
	var spec := _spec(kind)
	if spec.is_empty():
		empty["reason"] = "No station"
		return empty
	var recipe := _recipe(kind, input_id)
	if recipe.is_empty():
		empty["reason"] = "Cannot smelt"
		return empty
	if input_qty <= 0:
		empty["reason"] = "Empty"
		return empty
	var produced := str(recipe["output"])
	var stack := _stack_of(produced)
	var room := stack
	if output_id == produced:
		room = stack - output_qty
	elif output_id != "":
		empty["reason"] = "Output full"
		return empty
	if room <= 0:
		empty["reason"] = "Output full"
		return empty
	var cap := mini(mini(input_qty, int(spec["batch"])), room)
	var count := 0
	var cost := 0
	for amount in range(cap, 0, -1):
		var need := fuel_cost(kind, input_id, fuel_id, amount)
		if need > 0 and need <= fuel_qty:
			count = amount
			cost = need
			break
	if count <= 0:
		empty["reason"] = "Needs fuel"
		return empty
	return {
		"ok": true,
		"reason": "",
		"input_id": input_id,
		"output_id": produced,
		"fuel_id": fuel_id,
		"count": count,
		"fuel_count": cost,
		"seconds": float(spec["seconds"]) * float(count),
	}


static func _stack_of(item_id: String) -> int:
	var definition := ItemCatalog.get_item(item_id)
	if definition == null or definition.max_stack <= 0:
		return 50
	return definition.max_stack


static func _recipe(kind: String, item_id: String) -> Dictionary:
	var spec := _spec(kind)
	if spec.is_empty() or item_id.is_empty():
		return {}
	var tier := int(spec["tier"])
	for recipe in _recipes:
		if str(recipe["input"]) != item_id:
			continue
		if int(recipe["tier"]) > tier:
			continue
		return recipe
	return {}


static func _spec(kind: String) -> Dictionary:
	_warm()
	return _specs.get(kind, {})


static func _warm() -> void:
	if not _specs.is_empty():
		return
	# tier, batch, seconds per unit, ore coal num/den, alloy coal num/den, burns fuel, hp
	_put("furnace_scrap", 1, 1, 8.0, 2, 1, 0, 1, false, 200, "Scrap Furnace", Vector2i(1, 1), Color(0.55, 0.32, 0.22), "1 iron or copper ore, 2 coal.")
	_put("smelter_iron", 2, 5, 4.0, 1, 1, 0, 1, false, 400, "Iron Smelter", Vector2i(2, 2), Color(0.42, 0.42, 0.46), "5 ore, 1 coal each. Iron, copper, and lead.")
	_put("smelter_steel", 3, 10, 2.5, 1, 2, 1, 1, false, 800, "Steel Smelter", Vector2i(2, 3), Color(0.34, 0.40, 0.48), "10 at a time, half the coal. Steel and glass.")
	_put("foundry", 4, 20, 1.5, 1, 2, 1, 2, true, 1600, "Foundry", Vector2i(3, 3), Color(0.28, 0.22, 0.20), "20 at a time. Coal or fuel. Aluminum and composite stock.")
	_recipes = [
		{"input": "iron_ore", "output": "iron_ingots", "tier": 1, "alloy": false},
		{"input": "copper_ore", "output": "copper_ingots", "tier": 1, "alloy": false},
		{"input": "lead_ore", "output": "lead_ingots", "tier": 2, "alloy": false},
		{"input": "iron_ingots", "output": "steel_ingots", "tier": 3, "alloy": true},
		{"input": "sand", "output": "glass", "tier": 3, "alloy": false},
		{"input": "bauxite", "output": "aluminum_ingots", "tier": 4, "alloy": false},
		{"input": "quartz", "output": "composite_stock", "tier": 4, "alloy": false},
	]


static func _put(
	kind: String,
	tier: int,
	batch: int,
	seconds: float,
	ore_num: int,
	ore_den: int,
	alloy_num: int,
	alloy_den: int,
	burns_fuel: bool,
	hp: int,
	station_name: String,
	size: Vector2i,
	color: Color,
	blurb: String
) -> void:
	_specs[kind] = {
		"tier": tier,
		"batch": batch,
		"seconds": seconds,
		"ore_num": ore_num,
		"ore_den": ore_den,
		"alloy_num": alloy_num,
		"alloy_den": alloy_den,
		"burns_fuel": burns_fuel,
		"hp": hp,
		"name": station_name,
		"footprint": size,
		"color": color,
		"hint": blurb,
	}
