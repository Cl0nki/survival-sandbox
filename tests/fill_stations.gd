extends SceneTree

## Well and pump jacks fill one empty container.
## godot --headless --path <project> --script res://tests/fill_stations.gd

var _failures := PackedStringArray()
var _checks := 0


func _init() -> void:
	physics_frame.connect(_boot, CONNECT_ONE_SHOT)


func _boot() -> void:
	_run()
	print("checks=%d failures=%d" % [_checks, _failures.size()])
	for failure in _failures:
		print("FAIL ", failure)
	if _failures.is_empty():
		print("FILL_STATIONS_OK")
		quit(0)
	else:
		quit(1)


func _run() -> void:
	for item_id in ["bucket_empty", "bucket_full", "water_bottle_empty", "water_bottle_full", "gas_bottle_empty", "gas_bottle_full", "oil_drum_empty", "oil_drum_full", "water_well", "pump_jack_gas", "pump_jack_oil"]:
		_check(ItemCatalog.known(item_id), "missing %s" % item_id)
	_check(ItemCatalog.get_item("bucket_empty").max_stack == 1, "bucket stacks")
	var stage := Node3D.new()
	root.add_child(stage)
	var building := BuildingSystem.new()
	var config := BuildingConfig.new()
	config.collapse_delay_sec = 0.0
	config.collapse_span_sec = 0.0
	building.config = config
	stage.add_child(building)
	var deployables := DeployableSystem.new()
	stage.add_child(deployables)

	var well_place: Dictionary = deployables.try_place("water_well", Vector2i(0, 0), 0, 0)
	_check(bool(well_place["ok"]), "well refused: %s" % str(well_place.get("reason", "")))
	_check(deployables.cells_of(int(well_place["id"])).size() == 1, "well footprint")
	_check(deployables.health_of(int(well_place["id"])) == 200, "well HP")
	var well := deployables.piece_node(int(well_place["id"])) as FillStation
	_check(well != null and well.inventory.capacity == 1, "well slot")
	var low := AABB(Vector3(0, 0, 0), Vector3(0.8, 0.84, 0.8))
	_check(not deployables.blocks_player(low, Vector3(0.2, 0.0, 0.2), 1.8), "well height traps a standing player")

	var bag := Inventory.new(4)
	bag.add_exact("gas_bottle_empty", 1)
	bag.add_exact("bucket_empty", 1)
	var refused := Inventory.move(bag, 0, well.inventory, FillRules.SLOT, 1, true)
	_check(refused == "wrong_slot", "well took a gas bottle (%s)" % refused)
	var accepted := Inventory.move(bag, 1, well.inventory, FillRules.SLOT, 1, true)
	_check(accepted == "", "well refused a bucket (%s)" % accepted)
	well._process(1.0)
	_check(well.inventory.count_item("bucket_empty") == 1, "bucket filled early")
	_check(well.slot_hint().begins_with("Filling"), "well label: %s" % well.slot_hint())
	well.inventory.slots[FillRules.SLOT] = {"id": "", "qty": 0}
	well._process(4.0)
	_check(well.inventory.count_item("bucket_full") == 0, "cancelled fill still finished")
	_put(well, "bucket_empty")
	well._process(4.0)
	_check(well.inventory.count_item("bucket_full") == 1, "bucket did not fill")
	_check(well.inventory.count_item("bucket_empty") == 0, "empty bucket stayed")
	_put(well, "water_bottle_empty")
	well._process(4.0)
	_check(well.inventory.count_item("water_bottle_full") == 1, "water bottle did not fill")
	var full_back := Inventory.new(2)
	full_back.add_exact("bucket_full", 1)
	var rejected := Inventory.move(full_back, 0, well.inventory, FillRules.SLOT, 1, true)
	_check(rejected == "wrong_slot", "well accepted a full bucket (%s)" % rejected)

	var gas_place: Dictionary = deployables.try_place("pump_jack_gas", Vector2i(3, 0), 0, 0)
	_check(bool(gas_place["ok"]), "gas pump refused: %s" % str(gas_place.get("reason", "")))
	_check(deployables.cells_of(int(gas_place["id"])).size() == 9, "gas pump is not 3x3")
	_check(deployables.health_of(int(gas_place["id"])) == 300, "gas pump HP")
	var gas := deployables.piece_node(int(gas_place["id"])) as FillStation
	var gas_bag := Inventory.new(2)
	gas_bag.add_exact("bucket_empty", 1)
	_check(Inventory.move(gas_bag, 0, gas.inventory, FillRules.SLOT, 1, true) == "wrong_slot", "gas pump took a bucket")
	_put(gas, "gas_bottle_empty")
	gas._process(5.0)
	_check(gas.inventory.count_item("gas_bottle_full") == 1, "gas bottle did not fill")

	var oil_place: Dictionary = deployables.try_place("pump_jack_oil", Vector2i(6, 0), 0, 0)
	_check(bool(oil_place["ok"]), "crude pump refused: %s" % str(oil_place.get("reason", "")))
	_check(deployables.cells_of(int(oil_place["id"])).size() == 4, "crude pump is not 2x2")
	_check(deployables.health_of(int(oil_place["id"])) == 400, "crude pump HP")
	var water_patch := GroundDeposit.new()
	water_patch.set_footprint(Vector2i(8, 8), Vector2i(1, 1))
	water_patch.configure("patch_water", "ground_water")
	stage.add_child(water_patch)
	var on_water: Dictionary = deployables.try_place("water_well", Vector2i(8, 8), 0, 0)
	_check(bool(on_water["ok"]), "well refused its water cell: %s" % str(on_water.get("reason", "")))
	var off_water: Dictionary = deployables.try_place("water_well", Vector2i(9, 8), 0, 0)
	_check(not bool(off_water["ok"]) and str(off_water.get("reason", "")) == "Needs the water patch", "well placed off the water patch: %s" % str(off_water.get("reason", "")))
	var gas_patch := GroundDeposit.new()
	gas_patch.set_footprint(Vector2i(8, 4), Vector2i(3, 3))
	gas_patch.configure("patch_gas", "natural_gas")
	stage.add_child(gas_patch)
	var on_gas: Dictionary = deployables.try_place("pump_jack_gas", Vector2i(8, 4), 0, 0)
	_check(bool(on_gas["ok"]), "gas pump refused its patch: %s" % str(on_gas.get("reason", "")))
	var off_gas: Dictionary = deployables.try_place("pump_jack_gas", Vector2i(9, 4), 0, 0)
	_check(not bool(off_gas["ok"]), "gas pump placed off the gas patch")
	var oil := deployables.piece_node(int(oil_place["id"])) as FillStation
	_put(oil, "gas_bottle_empty")
	oil._process(6.0)
	_check(oil.inventory.count_item("gas_bottle_full") == 0, "crude pump filled a gas bottle")
	_check(oil.inventory.count_item("gas_bottle_empty") == 1, "crude pump consumed a gas bottle")
	_put(oil, "oil_drum_empty")
	oil._process(6.0)
	_check(oil.inventory.count_item("oil_drum_full") == 1, "oil drum did not fill")
	_check(oil.receive_damage(50, Vector3.ZERO), "crude pump ignored the shot")
	_check(deployables.health_of(int(oil_place["id"])) == 350, "crude pump health")


func _put(station: FillStation, item_id: String) -> void:
	station.inventory.slots[FillRules.SLOT] = {"id": item_id, "qty": 1}
	station._job_id = ""
	station._job_left = 0.0


func _check(ok: bool, message: String) -> void:
	_checks += 1
	if not ok:
		_failures.append(message)
