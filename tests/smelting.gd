extends SceneTree

## Furnace, smelter, and foundry batches.
## godot --headless --path <project> --script res://tests/smelting.gd

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
		print("SMELTING_OK")
		quit(0)
	else:
		quit(1)


func _run() -> void:
	_check(ItemCatalog.known("lead_ingot"), "lead ingots missing")
	_check(ItemCatalog.known("aluminum_ingot"), "aluminum ingots missing")
	_check(not ItemCatalog.known("composite_stock"), "composite stock should be gone")
	_rules()
	_stations()


func _rules() -> void:
	var scrap := SmeltRules.plan("furnace_scrap", "iron_ore", 1, "coal", 2, "", 0)
	_check(bool(scrap["ok"]) and int(scrap["count"]) == 1 and int(scrap["fuel_count"]) == 2, "scrap iron job %s" % str(scrap))
	_check(is_equal_approx(float(scrap["seconds"]), 8.0), "scrap iron should take 8s")
	_check(str(scrap["output_id"]) == "iron_ingot", "scrap iron output")
	var copper := SmeltRules.plan("furnace_scrap", "copper_ore", 1, "coal", 2, "", 0)
	_check(bool(copper["ok"]) and str(copper["output_id"]) == "copper_ingot", "scrap copper")
	var short_coal := SmeltRules.plan("furnace_scrap", "iron_ore", 1, "coal", 1, "", 0)
	_check(not bool(short_coal["ok"]) and str(short_coal["reason"]) == "Needs fuel", "scrap accepted 1 coal")
	var lead := SmeltRules.plan("furnace_scrap", "lead_ore", 1, "coal", 2, "", 0)
	_check(str(lead["reason"]) == "Cannot smelt", "scrap smelted lead")
	var scrap_fuel := SmeltRules.plan("furnace_scrap", "iron_ore", 1, "fuel", 2, "", 0)
	_check(str(scrap_fuel["reason"]) == "Needs fuel", "scrap burned fuel")

	var iron := SmeltRules.plan("smelter_iron", "lead_ore", 5, "coal", 5, "", 0)
	_check(bool(iron["ok"]) and int(iron["count"]) == 5 and int(iron["fuel_count"]) == 5, "iron lead job %s" % str(iron))
	_check(str(iron["output_id"]) == "lead_ingot", "lead output")
	_check(is_equal_approx(float(iron["seconds"]), 20.0), "five lead should take 20s")
	var capped := SmeltRules.plan("smelter_iron", "iron_ore", 7, "coal", 7, "", 0)
	_check(int(capped["count"]) == 5 and int(capped["fuel_count"]) == 5, "iron batch did not cap at 5")
	var partial := SmeltRules.plan("smelter_iron", "iron_ore", 5, "coal", 4, "", 0)
	_check(int(partial["count"]) == 4 and int(partial["fuel_count"]) == 4, "iron short coal was %s" % str(partial))

	var steel_ore := SmeltRules.plan("smelter_steel", "iron_ore", 10, "coal", 5, "", 0)
	_check(int(steel_ore["count"]) == 10 and int(steel_ore["fuel_count"]) == 5, "steel ore coal %s" % str(steel_ore))
	_check(is_equal_approx(float(steel_ore["seconds"]), 25.0), "ten ore should take 25s")
	var steel_short := SmeltRules.plan("smelter_steel", "iron_ore", 10, "coal", 4, "", 0)
	_check(int(steel_short["count"]) == 8 and int(steel_short["fuel_count"]) == 4, "4 coal should smelt 8 ore")
	var one := SmeltRules.plan("smelter_steel", "iron_ore", 1, "coal", 1, "", 0)
	_check(int(one["count"]) == 1 and int(one["fuel_count"]) == 1, "one ore still needs a coal")
	var alloy := SmeltRules.plan("smelter_steel", "iron_ingot", 10, "coal", 10, "", 0)
	_check(bool(alloy["ok"]) and str(alloy["output_id"]) == "steel_ingot" and int(alloy["fuel_count"]) == 10, "steel alloy %s" % str(alloy))
	var glass := SmeltRules.plan("smelter_steel", "sand", 10, "coal", 5, "", 0)
	_check(bool(glass["ok"]) and str(glass["output_id"]) == "glass" and int(glass["fuel_count"]) == 5, "sand to glass %s" % str(glass))
	var early := SmeltRules.plan("smelter_steel", "bauxite", 10, "coal", 10, "", 0)
	_check(str(early["reason"]) == "Cannot smelt", "steel smelted bauxite")

	var aluminum := SmeltRules.plan("foundry", "bauxite", 20, "coal", 10, "", 0)
	_check(bool(aluminum["ok"]) and str(aluminum["output_id"]) == "aluminum_ingot" and int(aluminum["count"]) == 20 and int(aluminum["fuel_count"]) == 10, "aluminum %s" % str(aluminum))
	_check(is_equal_approx(float(aluminum["seconds"]), 30.0), "foundry batch should take 30s")
	var quartz := SmeltRules.plan("foundry", "quartz", 20, "fuel", 5, "", 0)
	_check(str(quartz["reason"]) == "Cannot smelt", "foundry still smelted quartz")
	var foundry_steel := SmeltRules.plan("foundry", "iron_ingot", 20, "coal", 10, "", 0)
	_check(int(foundry_steel["count"]) == 20 and int(foundry_steel["fuel_count"]) == 10 and str(foundry_steel["output_id"]) == "steel_ingot", "foundry steel %s" % str(foundry_steel))
	var foundry_fuel := SmeltRules.plan("foundry", "iron_ingot", 20, "fuel", 5, "", 0)
	_check(int(foundry_fuel["count"]) == 20 and int(foundry_fuel["fuel_count"]) == 5, "foundry steel on fuel %s" % str(foundry_fuel))
	var blocked := SmeltRules.plan("foundry", "iron_ore", 20, "coal", 10, "iron_ingot", 50)
	_check(str(blocked["reason"]) == "Output full", "full output still planned")


func _stations() -> void:
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

	var scrap_place: Dictionary = deployables.try_place("furnace_scrap", Vector2i(0, 0), 0, 0)
	_check(bool(scrap_place["ok"]), "scrap furnace refused: %s" % scrap_place["reason"])
	_check(deployables.cells_of(int(scrap_place["id"])).size() == 1, "scrap furnace footprint")
	_check(deployables.health_of(int(scrap_place["id"])) == 200, "scrap furnace HP")
	var scrap := deployables.piece_node(int(scrap_place["id"])) as Smelter
	_check(scrap != null and scrap.inventory.capacity == 3, "scrap furnace slots")
	_load(scrap, "iron_ore", 2, "coal", 4)
	scrap._process(3.0)
	_check(scrap.inventory.count_item("iron_ingot") == 0, "job finished early")
	_check(scrap.inventory.count_item("coal") == 4, "fuel burned before the job finished")
	_check(scrap.slot_hint().contains("Iron Ingot"), "label did not show the job: %s" % scrap.slot_hint())
	scrap._process(5.0)
	_check(scrap.inventory.count_item("iron_ingot") == 1, "first scrap batch")
	_check(scrap.inventory.count_item("iron_ore") == 1, "scrap ate both ore in one job")
	_check(scrap.inventory.count_item("coal") == 2, "scrap burned the second batch of coal")
	scrap._process(8.0)
	_check(scrap.inventory.count_item("iron_ingot") == 2, "second scrap batch")
	_check(scrap.inventory.count_item("iron_ore") == 0 and scrap.inventory.count_item("coal") == 0, "scrap left leftovers")

	_load(scrap, "iron_ore", 1, "coal", 2)
	scrap._process(3.0)
	scrap.inventory.slots[SmeltRules.INPUT] = {"id": "", "qty": 0}
	scrap._process(8.0)
	_check(scrap.inventory.count_item("iron_ingot") == 0, "cancelled job still produced")
	_check(scrap.inventory.count_item("coal") == 2, "cancelled job burned coal")

	var bag := Inventory.new(4)
	bag.add_exact("iron_ore", 4)
	bag.add_exact("coal", 4)
	var into_fuel := Inventory.move(bag, 0, scrap.inventory, SmeltRules.FUEL, 1, true)
	_check(into_fuel == "wrong_slot", "ore went into the fuel slot (%s)" % into_fuel)
	var into_input := Inventory.move(bag, 1, scrap.inventory, SmeltRules.INPUT, 1, true)
	_check(into_input == "wrong_slot", "coal went into the input slot (%s)" % into_input)
	var into_out := Inventory.move(bag, 0, scrap.inventory, SmeltRules.OUTPUT, 1, true)
	_check(into_out == "wrong_slot", "ore went into the output (%s)" % into_out)
	var fuel_ok := Inventory.move(bag, 1, scrap.inventory, SmeltRules.FUEL, 1, true)
	_check(fuel_ok == "", "coal refused by the fuel slot (%s)" % fuel_ok)

	var iron_place: Dictionary = deployables.try_place("smelter_iron", Vector2i(4, 0), 0, 0)
	_check(bool(iron_place["ok"]), "iron smelter refused: %s" % iron_place["reason"])
	_check(deployables.cells_of(int(iron_place["id"])).size() == 4, "iron smelter is not 2x2")
	_check(deployables.health_of(int(iron_place["id"])) == 400, "iron smelter HP")
	var iron_body := deployables.piece_node(int(iron_place["id"])) as Smelter
	_load(iron_body, "lead_ore", 5, "coal", 5)
	iron_body._process(20.0)
	_check(iron_body.inventory.count_item("lead_ingot") == 5, "iron smelter lead")
	_check(iron_body.inventory.count_item("lead_ore") == 0 and iron_body.inventory.count_item("coal") == 0, "iron smelter leftovers")

	var steel_place: Dictionary = deployables.try_place("smelter_steel", Vector2i(0, 4), 0, 0)
	_check(bool(steel_place["ok"]), "steel smelter refused: %s" % steel_place["reason"])
	_check(deployables.cells_of(int(steel_place["id"])).size() == 6, "steel smelter is not 2x3")
	_check(deployables.health_of(int(steel_place["id"])) == 800, "steel smelter HP")
	var turned: Dictionary = deployables.try_place("smelter_steel", Vector2i(8, 8), 1, 0)
	_check(bool(turned["ok"]), "rotated steel smelter refused: %s" % turned["reason"])
	var turned_cells := deployables.cells_of(int(turned["id"]))
	_check(_span(turned_cells) == Vector2i(3, 2), "rotated steel span %s" % [str(turned_cells)])
	var steel := deployables.piece_node(int(steel_place["id"])) as Smelter
	_load(steel, "sand", 10, "coal", 5)
	steel._process(25.0)
	_check(steel.inventory.count_item("glass") == 10, "steel smelter glass")
	_load(steel, "iron_ingot", 10, "coal", 10)
	steel._process(25.0)
	_check(steel.inventory.count_item("steel_ingot") == 10, "steel smelter steel")

	var foundry_place: Dictionary = deployables.try_place("foundry", Vector2i(8, 0), 0, 0)
	_check(bool(foundry_place["ok"]), "foundry refused: %s" % foundry_place["reason"])
	_check(deployables.cells_of(int(foundry_place["id"])).size() == 9, "foundry is not 3x3")
	_check(deployables.health_of(int(foundry_place["id"])) == 1600, "foundry HP")
	var center := deployables.center_of(int(foundry_place["id"]))
	_check(absf(center.x - 9.5) < 0.01 and absf(center.z - 1.5) < 0.01, "foundry center %s" % str(center))
	var overlap: Dictionary = deployables.try_place("foundry", Vector2i(8, 0), 0, 0)
	_check(not bool(overlap["ok"]), "second foundry stacked on the first")
	var foundry := deployables.piece_node(int(foundry_place["id"])) as Smelter
	_load(foundry, "bauxite", 20, "coal", 10)
	foundry._process(30.0)
	_check(foundry.inventory.count_item("aluminum_ingot") == 20, "foundry aluminum")
	_load(foundry, "bauxite", 20, "fuel", 5)
	foundry._process(30.0)
	_check(foundry.inventory.count_item("aluminum_ingot") == 20, "foundry aluminum on fuel")
	_check(foundry.inventory.count_item("fuel") == 0 and foundry.inventory.count_item("bauxite") == 0, "foundry left fuel or bauxite")
	_check(foundry.receive_damage(100, Vector3.ZERO), "foundry ignored the shot")
	_check(deployables.health_of(int(foundry_place["id"])) == 1500, "foundry health")
	var furnace_box := AABB(Vector3(0, 0, 0), Vector3(2.8, 1.15, 2.8))
	_check(deployables.blocks_player(furnace_box, Vector3(1.0, 0.0, 1.0), 1.8), "a furnace can swallow a standing player")
	_check(not deployables.blocks_player(furnace_box, Vector3(6.0, 0.0, 1.0), 1.8), "a clear furnace blocked the player")
	var chest_box := AABB(Vector3(0, 0, 0), Vector3(1.8, 0.72, 0.8))
	_check(not deployables.blocks_player(chest_box, Vector3(0.4, 0.0, 0.2), 1.8), "a chest blocked a standing player")


func _load(station: Smelter, input_id: String, input_qty: int, fuel_id: String, fuel_qty: int) -> void:
	station.inventory.slots[SmeltRules.INPUT] = {"id": input_id, "qty": input_qty}
	station.inventory.slots[SmeltRules.FUEL] = {"id": fuel_id, "qty": fuel_qty}
	station.inventory.slots[SmeltRules.OUTPUT] = {"id": "", "qty": 0}
	station._job = {}
	station._job_left = 0.0


func _span(cells: Array[Vector2i]) -> Vector2i:
	var min_cell := cells[0]
	var max_cell := cells[0]
	for cell in cells:
		min_cell = Vector2i(mini(min_cell.x, cell.x), mini(min_cell.y, cell.y))
		max_cell = Vector2i(maxi(max_cell.x, cell.x), maxi(max_cell.y, cell.y))
	return Vector2i(max_cell.x - min_cell.x + 1, max_cell.y - min_cell.y + 1)


func _check(ok: bool, message: String) -> void:
	_checks += 1
	if not ok:
		_failures.append(message)
