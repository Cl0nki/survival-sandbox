extends RefCounted
class_name CraftRules

## One craft or cook job. Input, an optional second part, fuel, and output.
## A station runs a single batch. A higher tier of the same family does every
## lower recipe, in a bigger batch, on less fuel.

const INPUT := 0
const EXTRA := 1
const FUEL := 2
const OUTPUT := 3
const SLOTS := 4

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


static func group_of(kind: String) -> String:
	return str(_spec(kind).get("group", ""))


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


static func body_height(kind: String) -> float:
	return float(_spec(kind).get("height", 0.84))


static func color_of(kind: String) -> Color:
	var spec := _spec(kind)
	if spec.is_empty():
		return Color(0.52, 0.36, 0.20)
	return spec["color"]


static func hint(kind: String) -> String:
	var spec := _spec(kind)
	if spec.is_empty():
		return ""
	return str(spec["hint"])


static func accepts_input(kind: String, item_id: String) -> bool:
	return _has_role(kind, item_id, "input")


static func accepts_extra(kind: String, item_id: String) -> bool:
	return _has_role(kind, item_id, "extra")


static func accepts_fuel(kind: String, item_id: String) -> bool:
	var spec := _spec(kind)
	if spec.is_empty():
		return false
	return (spec["fuels"] as Dictionary).has(item_id)


static func plan(
	kind: String,
	input_id: String,
	input_qty: int,
	extra_id: String,
	extra_qty: int,
	fuel_id: String,
	fuel_qty: int,
	output_id: String,
	output_qty: int
) -> Dictionary:
	var empty := {
		"ok": false,
		"reason": "",
		"input_id": input_id,
		"extra_id": extra_id,
		"fuel_id": fuel_id,
		"output_id": "",
		"jobs": 0,
		"in_count": 0,
		"extra_count": 0,
		"fuel_count": 0,
		"output_count": 0,
		"seconds": 0.0,
	}
	var spec := _spec(kind)
	if spec.is_empty():
		empty["reason"] = "No station"
		return empty
	if input_id.is_empty() or input_qty <= 0:
		empty["reason"] = "Empty"
		return empty
	var recipe := _match(spec, input_id, extra_id)
	if recipe.is_empty():
		empty["reason"] = "Cannot craft"
		return empty
	if bool(recipe.get("needs_extra", false)):
		empty["reason"] = "Needs the other part"
		return empty
	var in_n := int(recipe["in_n"])
	var extra_n := int(recipe["extra_n"])
	var out_n := int(recipe["out_n"])
	if input_qty < in_n or (extra_n > 0 and extra_qty < extra_n):
		empty["reason"] = "Not enough"
		return empty
	var produced := str(recipe["output"])
	if output_id != "" and output_qty > 0 and output_id != produced:
		empty["reason"] = "Output full"
		return empty
	var room := _stack_of(produced) - (output_qty if output_id == produced else 0)
	var jobs := int(spec["batch"])
	jobs = mini(jobs, int(input_qty / in_n))
	if extra_n > 0:
		jobs = mini(jobs, int(extra_qty / extra_n))
	jobs = mini(jobs, int(room / out_n))
	if jobs < 1:
		empty["reason"] = "Output full"
		return empty
	var fuels: Dictionary = spec["fuels"]
	var value := int(fuels.get(fuel_id, 0))
	if value <= 0:
		empty["reason"] = "Needs fuel"
		return empty
	jobs = _jobs_for_fuel(jobs, fuel_qty, int(spec["fuel_num"]), int(spec["fuel_den"]), value)
	if jobs < 1:
		empty["reason"] = "Needs fuel"
		return empty
	return {
		"ok": true,
		"reason": "",
		"input_id": input_id,
		"extra_id": extra_id if extra_n > 0 else "",
		"fuel_id": fuel_id,
		"output_id": produced,
		"jobs": jobs,
		"in_count": jobs * in_n,
		"extra_count": jobs * extra_n,
		"fuel_count": _fuel_items(jobs, int(spec["fuel_num"]), int(spec["fuel_den"]), value),
		"output_count": jobs * out_n,
		"seconds": float(spec["seconds"]) * float(jobs),
	}


static func _has_role(kind: String, item_id: String, role: String) -> bool:
	var spec := _spec(kind)
	if spec.is_empty() or item_id.is_empty():
		return false
	var family := str(spec["family"])
	var tier := int(spec["tier"])
	for recipe in _recipes:
		if str(recipe["family"]) != family or int(recipe["tier"]) > tier:
			continue
		if role == "input" and str(recipe["input"]) == item_id:
			return true
		if role == "extra" and str(recipe["extra"]) == item_id:
			return true
	return false


static func _match(spec: Dictionary, input_id: String, extra_id: String) -> Dictionary:
	var family := str(spec["family"])
	var tier := int(spec["tier"])
	var needs_extra := false
	for recipe in _recipes:
		if str(recipe["family"]) != family or str(recipe["input"]) != input_id:
			continue
		if int(recipe["tier"]) > tier:
			continue
		if str(recipe["extra"]) == extra_id:
			return recipe
		if str(recipe["extra"]) != "" and extra_id == "":
			needs_extra = true
	if needs_extra:
		return {"needs_extra": true}
	return {}


static func _jobs_for_fuel(wanted: int, fuel_qty: int, num: int, den: int, value: int) -> int:
	var jobs := wanted
	while jobs > 0:
		if _fuel_items(jobs, num, den, value) <= fuel_qty:
			return jobs
		jobs -= 1
	return 0


static func _fuel_items(jobs: int, num: int, den: int, value: int) -> int:
	if jobs <= 0 or num <= 0 or den <= 0 or value <= 0:
		return 0
	var units := ceili(float(jobs * num) / float(den))
	return ceili(float(units) / float(value))


static func _stack_of(item_id: String) -> int:
	var definition := ItemCatalog.get_item(item_id)
	if definition == null or definition.max_stack <= 0:
		return 50
	return definition.max_stack


static func _spec(kind: String) -> Dictionary:
	_warm()
	return _specs.get(kind, {})


static func _warm() -> void:
	if not _specs.is_empty():
		return
	var coal := {"coal": 1}
	var flame := {"stick": 1, "log": 4, "coal": 2}
	_station("sawbench", "craft", "saw", 1, 1, 4.0, 1, 1, coal, 150, 0.84, "Sawbench", Vector2i(1, 1), Color(0.62, 0.44, 0.24), "Log into plank. One coal.")
	_station("sawmill", "craft", "saw", 2, 8, 1.5, 1, 2, coal, 400, 0.84, "Sawmill", Vector2i(2, 2), Color(0.50, 0.34, 0.18), "Eight log at a time, half the coal.")
	_station("kiln", "craft", "kiln", 1, 1, 6.0, 1, 1, coal, 200, 0.84, "Kiln", Vector2i(1, 1), Color(0.64, 0.32, 0.24), "Clay, stone, or limestone. One coal.")
	_station("kiln_shed", "craft", "kiln", 2, 8, 2.5, 1, 2, coal, 500, 0.84, "Kiln Shed", Vector2i(2, 2), Color(0.52, 0.28, 0.22), "Also cement and concrete. Eight at a time.")
	_station("workbench", "craft", "bench", 1, 1, 5.0, 1, 1, coal, 100, 0.84, "Workbench", Vector2i(1, 1), Color(0.52, 0.36, 0.20), "Nail, scrap tools, and metal part. One coal.")
	_station("workbench_iron", "craft", "bench", 2, 3, 3.5, 1, 1, coal, 200, 0.84, "Iron Workbench", Vector2i(1, 1), Color(0.58, 0.58, 0.62), "Iron tools, wiring, and metal beam.")
	_station("workbench_steel", "craft", "bench", 3, 5, 2.5, 1, 2, coal, 400, 0.84, "Steel Workbench", Vector2i(1, 1), Color(0.40, 0.44, 0.50), "Steel tools, steel plate, pipe, and screw bolt.")
	_station("workbench_composite", "craft", "bench", 4, 8, 1.5, 1, 2, coal, 800, 0.84, "Composite Workbench", Vector2i(1, 1), Color(0.42, 0.40, 0.48), "Composite tools, industrial motor, and composite panel.")
	_station("machine_shop", "craft", "bench", 4, 12, 1.2, 1, 4, coal, 1200, 0.84, "Machine Shop", Vector2i(3, 3), Color(0.36, 0.38, 0.42), "The same bench jobs, twelve at a time.")
	_station("chem_bench", "craft", "chem", 1, 1, 6.0, 1, 1, coal, 200, 0.84, "Chem Bench", Vector2i(1, 1), Color(0.42, 0.62, 0.36), "Gunpowder, plastic, rubber, and fuel.")
	_station("refinery", "craft", "chem", 2, 8, 2.0, 1, 2, coal, 800, 0.84, "Refinery", Vector2i(3, 2), Color(0.32, 0.36, 0.34), "The chem bench, plus a drum of oil into fuel.")
	_station("ammo_bench", "craft", "armory", 1, 2, 4.0, 1, 1, coal, 250, 0.84, "Ammo Bench", Vector2i(1, 1), Color(0.48, 0.42, 0.28), "Gunpowder and metal into rounds.")
	_station("armory", "craft", "armory", 2, 8, 2.0, 1, 2, coal, 600, 0.84, "Armory", Vector2i(2, 2), Color(0.32, 0.36, 0.26), "Round, grenade, mine, and demolition charge.")
	_station("campfire", "cook", "cook", 1, 1, 6.0, 1, 1, flame, 80, 0.42, "Campfire", Vector2i(1, 1), Color(0.72, 0.36, 0.16), "Cooks meat, fish, potato, mushroom, egg, or corn.")
	_station("fire_pit", "cook", "cook", 1, 4, 4.0, 1, 1, flame, 120, 0.42, "Fire Pit", Vector2i(2, 1), Color(0.46, 0.28, 0.16), "Cooks four at a time.")
	_station("cooking_pot", "cook", "cook", 2, 2, 4.0, 1, 1, flame, 100, 0.84, "Cooking Pot", Vector2i(1, 1), Color(0.40, 0.42, 0.44), "Also a stew: meat or fish, plus a potato.")
	_station("stove", "cook", "cook", 3, 4, 2.5, 1, 2, flame, 250, 0.84, "Stove", Vector2i(2, 1), Color(0.55, 0.50, 0.46), "Cooks four, on half the fuel.")
	_station("kitchen", "cook", "cook", 4, 8, 1.5, 1, 2, flame, 400, 0.84, "Kitchen", Vector2i(2, 2), Color(0.62, 0.58, 0.50), "Cooks eight at a time.")
	_recipes = [
		_out("saw", 1, "log", "", "plank", 1, 0, 4),
		_out("kiln", 1, "clay", "", "brick", 1, 0, 1),
		_out("kiln", 1, "stone", "", "cut_stone", 1, 0, 1),
		_out("kiln", 1, "limestone", "", "mortar", 1, 0, 1),
		_out("kiln", 2, "limestone", "clay", "cement", 1, 1, 1),
		_out("kiln", 2, "cement", "sand", "concrete_mix", 1, 1, 1),
		_out("bench", 1, "iron_ingot", "", "nail", 1, 0, 8),
		_out("bench", 1, "steel_scrap", "", "metal_part", 1, 0, 2),
		_out("bench", 1, "scrap_metal", "stick", "hatchet_scrap", 1, 1, 1),
		_out("bench", 1, "scrap_metal", "stone", "pickaxe_scrap", 1, 1, 1),
		_out("bench", 1, "scrap_metal", "log", "shovel_scrap", 1, 1, 1),
		_out("bench", 1, "scrap_metal", "steel_scrap", "crowbar_scrap", 1, 1, 1),
		_out("bench", 2, "copper_ingot", "", "wiring", 1, 0, 4),
		_out("bench", 2, "iron_ingot", "copper_ingot", "metal_beam", 1, 1, 1),
		_out("bench", 2, "mechanical_part", "", "mechanical_component", 1, 0, 1),
		_out("bench", 2, "iron_ingot", "stick", "hatchet_iron", 1, 1, 1),
		_out("bench", 2, "iron_ingot", "stone", "pickaxe_iron", 1, 1, 1),
		_out("bench", 2, "iron_ingot", "log", "shovel_iron", 1, 1, 1),
		_out("bench", 2, "iron_ingot", "steel_scrap", "crowbar_iron", 1, 1, 1),
		_out("bench", 3, "steel_ingot", "", "steel_plate", 1, 0, 1),
		_out("bench", 3, "steel_ingot", "iron_ingot", "screw_bolt", 1, 1, 8),
		_out("bench", 3, "steel_ingot", "copper_ingot", "pipe", 1, 1, 2),
		_out("bench", 3, "iron_ingot", "steel_ingot", "reinforcement_mesh", 1, 1, 1),
		_out("bench", 3, "electronics", "", "circuit_board", 1, 0, 1),
		_out("bench", 3, "steel_ingot", "stick", "hatchet_steel", 1, 1, 1),
		_out("bench", 3, "steel_ingot", "stone", "pickaxe_steel", 1, 1, 1),
		_out("bench", 3, "steel_ingot", "log", "shovel_steel", 1, 1, 1),
		_out("bench", 3, "steel_ingot", "steel_scrap", "crowbar_steel", 1, 1, 1),
		_out("bench", 4, "steel_ingot", "electronics", "industrial_motor", 1, 1, 1),
		_out("bench", 4, "aluminum_ingot", "refined_plastic", "composite_panel", 1, 1, 1),
		_out("bench", 4, "aluminum_ingot", "stick", "hatchet_composite", 1, 1, 1),
		_out("bench", 4, "aluminum_ingot", "stone", "pickaxe_composite", 1, 1, 1),
		_out("bench", 4, "aluminum_ingot", "log", "shovel_composite", 1, 1, 1),
		_out("bench", 4, "aluminum_ingot", "steel_ingot", "crowbar_composite", 1, 1, 1),
		_out("chem", 1, "sulfur", "", "gunpowder", 1, 0, 1),
		_out("chem", 1, "plastic", "", "refined_plastic", 1, 0, 1),
		_out("chem", 1, "rubber", "", "synthetic_rubber", 1, 0, 1),
		_out("chem", 1, "chemicals", "", "fuel", 1, 0, 1),
		_out("chem", 2, "oil_drum_full", "", "fuel", 1, 0, 4),
		_out("armory", 1, "gunpowder", "lead_ingot", "ammo_9mm", 1, 1, 8),
		_out("armory", 1, "gunpowder", "copper_ingot", "ammo_45acp", 1, 1, 8),
		_out("armory", 1, "gunpowder", "iron_ingot", "ammo_556", 1, 1, 6),
		_out("armory", 1, "gunpowder", "steel_scrap", "ammo_12gauge", 1, 1, 4),
		_out("armory", 2, "gunpowder", "steel_ingot", "ammo_762", 1, 1, 4),
		_out("armory", 2, "gunpowder", "aluminum_ingot", "explosive_round", 1, 1, 2),
		_out("armory", 2, "lead_ingot", "gunpowder", "ammo_50bmg", 1, 1, 2),
		_out("armory", 2, "chemicals", "sulfur", "explosive_compound", 1, 1, 1),
		_out("armory", 2, "explosive_compound", "steel_ingot", "grenade", 1, 1, 1),
		_out("armory", 2, "explosive_compound", "iron_ingot", "demolition_charge", 1, 1, 1),
		_out("armory", 2, "explosive_compound", "steel_scrap", "mine", 1, 1, 1),
		_out("armory", 2, "explosive_compound", "steel_plate", "rocket_warhead", 1, 1, 1),
		_out("cook", 1, "raw_meat", "", "cooked_meat", 1, 0, 1),
		_out("cook", 1, "raw_fish", "", "cooked_fish", 1, 0, 1),
		_out("cook", 1, "potato", "", "baked_potato", 1, 0, 1),
		_out("cook", 1, "mushroom", "", "cooked_mushroom", 1, 0, 1),
		_out("cook", 1, "egg", "", "fried_egg", 1, 0, 1),
		_out("cook", 1, "corn", "", "cooked_corn", 1, 0, 1),
		_out("cook", 2, "raw_meat", "potato", "meat_stew", 1, 1, 1),
		_out("cook", 2, "raw_fish", "potato", "fish_stew", 1, 1, 1),
	]


static func _station(
	kind: String,
	group: String,
	family: String,
	tier: int,
	batch: int,
	seconds: float,
	fuel_num: int,
	fuel_den: int,
	fuels: Dictionary,
	hp: int,
	height: float,
	station_name: String,
	size: Vector2i,
	color: Color,
	blurb: String
) -> void:
	_specs[kind] = {
		"group": group,
		"family": family,
		"tier": tier,
		"batch": batch,
		"seconds": seconds,
		"fuel_num": fuel_num,
		"fuel_den": fuel_den,
		"fuels": fuels,
		"hp": hp,
		"height": height,
		"name": station_name,
		"footprint": size,
		"color": color,
		"hint": blurb,
	}


static func _out(family: String, tier: int, input: String, extra: String, output: String, in_n: int, extra_n: int, out_n: int) -> Dictionary:
	return {
		"family": family,
		"tier": tier,
		"input": input,
		"extra": extra,
		"output": output,
		"in_n": in_n,
		"extra_n": extra_n,
		"out_n": out_n,
	}
