extends SceneTree

## Crafting stations, cooking stations, and campfires.
## godot --headless --path <project> --script res://tests/crafting.gd

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
		print("CRAFTING_OK")
		quit(0)
	else:
		quit(1)


func _run() -> void:
	_check(ItemCatalog.known("raw_meat") and ItemCatalog.known("cooked_fish"), "cooked food missing")
	_rules()
	_stations()


func _rules() -> void:
	var saw := CraftRules.plan("sawbench", "logs", 1, "", 0, "coal", 1, "", 0)
	_check(bool(saw["ok"]) and int(saw["output_count"]) == 4 and int(saw["fuel_count"]) == 1, "sawbench planks %s" % str(saw))
	_check(is_equal_approx(float(saw["seconds"]), 4.0), "sawbench should take 4s")
	_check(str(saw["output_id"]) == "planks", "sawbench output")
	var mill := CraftRules.plan("sawmill", "logs", 8, "", 0, "coal", 4, "", 0)
	_check(bool(mill["ok"]) and int(mill["jobs"]) == 8 and int(mill["output_count"]) == 32 and int(mill["fuel_count"]) == 4, "sawmill batch %s" % str(mill))
	var mill_one := CraftRules.plan("sawmill", "logs", 1, "", 0, "coal", 1, "", 0)
	_check(int(mill_one["jobs"]) == 1 and int(mill_one["fuel_count"]) == 1, "one log still needs a coal")

	var bricks := CraftRules.plan("kiln", "clay", 1, "", 0, "coal", 1, "", 0)
	_check(bool(bricks["ok"]) and str(bricks["output_id"]) == "bricks", "kiln bricks")
	var mortar := CraftRules.plan("kiln", "limestone", 1, "", 0, "coal", 1, "", 0)
	_check(str(mortar["output_id"]) == "mortar", "kiln mortar")
	var early_cement := CraftRules.plan("kiln", "limestone", 1, "clay", 1, "coal", 1, "", 0)
	_check(str(early_cement["reason"]) == "Cannot craft", "small kiln made cement")
	var cement := CraftRules.plan("kiln_shed", "limestone", 1, "clay", 1, "coal", 1, "", 0)
	_check(bool(cement["ok"]) and str(cement["output_id"]) == "cement", "kiln shed cement %s" % str(cement))
	var mix := CraftRules.plan("kiln_shed", "cement", 8, "sand", 8, "coal", 4, "", 0)
	_check(int(mix["jobs"]) == 8 and int(mix["fuel_count"]) == 4 and str(mix["output_id"]) == "concrete_mix", "concrete mix %s" % str(mix))

	var nails := CraftRules.plan("workbench", "iron_ingots", 1, "", 0, "coal", 1, "", 0)
	_check(bool(nails["ok"]) and int(nails["output_count"]) == 8 and str(nails["output_id"]) == "nails", "scrap nails %s" % str(nails))
	var too_soon := CraftRules.plan("workbench", "steel_ingots", 1, "", 0, "coal", 1, "", 0)
	_check(str(too_soon["reason"]) == "Cannot craft", "scrap bench made plates")
	var hatchet := CraftRules.plan("workbench", "scrap_metal", 1, "sticks", 1, "coal", 1, "", 0)
	_check(str(hatchet["output_id"]) == "hatchet_scrap", "scrap hatchet")
	var iron_hatchet := CraftRules.plan("workbench_iron", "iron_ingots", 1, "sticks", 1, "coal", 1, "", 0)
	_check(str(iron_hatchet["output_id"]) == "hatchet_iron" and int(iron_hatchet["jobs"]) == 1, "iron hatchet stacked %s" % str(iron_hatchet))
	var plates := CraftRules.plan("workbench_steel", "steel_ingots", 5, "", 0, "coal", 3, "", 0)
	_check(int(plates["jobs"]) == 5 and int(plates["fuel_count"]) == 3, "steel plates fuel %s" % str(plates))
	var motor := CraftRules.plan("machine_shop", "steel_ingots", 1, "electronics", 1, "coal", 1, "", 0)
	_check(str(motor["output_id"]) == "industrial_motors", "machine shop motor")

	var powder := CraftRules.plan("chem_bench", "sulfur", 1, "", 0, "coal", 1, "", 0)
	_check(str(powder["output_id"]) == "gunpowder", "chem gunpowder")
	var drum := CraftRules.plan("chem_bench", "oil_drum_full", 1, "", 0, "coal", 1, "", 0)
	_check(str(drum["reason"]) == "Cannot craft", "chem bench cracked a drum")
	var refined := CraftRules.plan("refinery", "oil_drum_full", 1, "", 0, "coal", 1, "", 0)
	_check(bool(refined["ok"]) and int(refined["output_count"]) == 4 and str(refined["output_id"]) == "fuel", "refinery fuel %s" % str(refined))

	var rounds := CraftRules.plan("ammo_bench", "gunpowder", 2, "lead_ingots", 2, "coal", 2, "", 0)
	_check(int(rounds["jobs"]) == 2 and int(rounds["output_count"]) == 16 and str(rounds["output_id"]) == "ammo_9mm", "9mm %s" % str(rounds))
	var need_part := CraftRules.plan("ammo_bench", "gunpowder", 1, "", 0, "coal", 1, "", 0)
	_check(str(need_part["reason"]) == "Needs the other part", "ammo without metal")
	var rifle := CraftRules.plan("ammo_bench", "gunpowder", 1, "steel_ingots", 1, "coal", 1, "", 0)
	_check(str(rifle["reason"]) == "Cannot craft", "ammo bench made 7.62")
	var armory := CraftRules.plan("armory", "gunpowder", 1, "steel_ingots", 1, "coal", 1, "", 0)
	_check(str(armory["output_id"]) == "ammo_762", "armory 7.62")
	var grenade := CraftRules.plan("armory", "explosive_compound", 1, "steel_ingots", 1, "coal", 1, "", 0)
	_check(str(grenade["output_id"]) == "grenades", "armory grenade")

	var cook := CraftRules.plan("campfire", "raw_meat", 1, "", 0, "sticks", 1, "", 0)
	_check(bool(cook["ok"]) and str(cook["output_id"]) == "cooked_meat" and int(cook["fuel_count"]) == 1, "campfire meat %s" % str(cook))
	_check(is_equal_approx(float(cook["seconds"]), 6.0), "campfire should take 6s")
	var pit := CraftRules.plan("fire_pit", "raw_fish", 4, "", 0, "logs", 1, "", 0)
	_check(int(pit["jobs"]) == 4 and int(pit["fuel_count"]) == 1 and str(pit["output_id"]) == "cooked_fish", "fire pit on one log %s" % str(pit))
	var stove := CraftRules.plan("stove", "raw_meat", 4, "", 0, "coal", 1, "", 0)
	_check(int(stove["jobs"]) == 4 and int(stove["fuel_count"]) == 1, "stove on one coal %s" % str(stove))
	var bare := CraftRules.plan("campfire", "raw_meat", 1, "", 0, "", 0, "", 0)
	_check(str(bare["reason"]) == "Needs fuel", "campfire cooked with no fuel")
	var potato := CraftRules.plan("campfire", "potato", 1, "", 0, "sticks", 1, "", 0)
	_check(bool(potato["ok"]) and str(potato["output_id"]) == "baked_potato", "campfire potato %s" % str(potato))
	var early_stew := CraftRules.plan("campfire", "raw_meat", 1, "potato", 1, "sticks", 1, "", 0)
	_check(str(early_stew["reason"]) == "Cannot craft", "campfire made stew")
	var stew := CraftRules.plan("cooking_pot", "raw_meat", 1, "potato", 1, "sticks", 1, "", 0)
	_check(bool(stew["ok"]) and str(stew["output_id"]) == "meat_stew", "pot stew %s" % str(stew))
	var fish_stew := CraftRules.plan("stove", "raw_fish", 1, "potato", 1, "coal", 1, "", 0)
	_check(str(fish_stew["output_id"]) == "fish_stew", "stove fish stew")


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

	var saw_place: Dictionary = deployables.try_place("sawbench", Vector2i(0, 0), 0, 0)
	_check(bool(saw_place["ok"]), "sawbench refused: %s" % saw_place["reason"])
	_check(deployables.health_of(int(saw_place["id"])) == 150, "sawbench HP")
	var saw := deployables.piece_node(int(saw_place["id"])) as Crafter
	_check(saw != null and saw.inventory.capacity == 4, "sawbench slots")
	_load(saw, "logs", 2, "", 0, "coal", 2)
	saw._process(4.0)
	_check(saw.inventory.count_item("planks") == 4, "first saw batch")
	_check(saw.inventory.count_item("logs") == 1 and saw.inventory.count_item("coal") == 1, "saw ate both logs in one job")
	saw._process(4.0)
	_check(saw.inventory.count_item("planks") == 8 and saw.inventory.count_item("logs") == 0, "second saw batch")

	_load(saw, "logs", 1, "", 0, "coal", 1)
	saw._process(1.0)
	saw.inventory.slots[CraftRules.INPUT] = {"id": "", "qty": 0}
	saw._process(4.0)
	_check(saw.inventory.count_item("planks") == 0, "cancelled saw still produced")
	_check(saw.inventory.count_item("coal") == 1, "cancelled saw burned coal")

	var bag := Inventory.new(4)
	bag.add_exact("logs", 1)
	bag.add_exact("coal", 1)
	var into_fuel := Inventory.move(bag, 0, saw.inventory, CraftRules.FUEL, 1, true)
	_check(into_fuel == "wrong_slot", "logs went into the fuel slot (%s)" % into_fuel)
	var into_out := Inventory.move(bag, 0, saw.inventory, CraftRules.OUTPUT, 1, true)
	_check(into_out == "wrong_slot", "logs went into the output (%s)" % into_out)

	var shop_place: Dictionary = deployables.try_place("machine_shop", Vector2i(4, 0), 0, 0)
	_check(bool(shop_place["ok"]), "machine shop refused: %s" % shop_place["reason"])
	_check(deployables.cells_of(int(shop_place["id"])).size() == 9, "machine shop is not 3x3")
	_check(deployables.health_of(int(shop_place["id"])) == 1200, "machine shop HP")

	var fire_place: Dictionary = deployables.try_place("campfire", Vector2i(2, 2), 0, 0)
	_check(bool(fire_place["ok"]), "campfire refused: %s" % fire_place["reason"])
	_check(deployables.health_of(int(fire_place["id"])) == 80, "campfire HP")
	var fire := deployables.piece_node(int(fire_place["id"])) as Crafter
	_load(fire, "raw_meat", 1, "", 0, "sticks", 1)
	fire._process(6.0)
	_check(fire.inventory.count_item("cooked_meat") == 1, "campfire cooked meat")
	_check(fire.inventory.count_item("raw_meat") == 0 and fire.inventory.count_item("sticks") == 0, "campfire leftovers")
	var fire_box := AABB(Vector3(0, 0, 0), Vector3(0.8, 0.42, 0.8))
	_check(not deployables.blocks_player(fire_box, Vector3(0.4, 0.0, 0.4), 1.8), "a campfire blocked a standing player")

	var pit_place: Dictionary = deployables.try_place("fire_pit", Vector2i(8, 4), 0, 0)
	_check(bool(pit_place["ok"]), "fire pit refused: %s" % pit_place["reason"])
	_check(deployables.cells_of(int(pit_place["id"])).size() == 2, "fire pit is not 2x1")
	var pit := deployables.piece_node(int(pit_place["id"])) as Crafter
	_load(pit, "raw_fish", 4, "", 0, "logs", 1)
	pit._process(16.0)
	_check(pit.inventory.count_item("cooked_fish") == 4, "fire pit cooked four fish")
	_check(pit.inventory.count_item("logs") == 0, "fire pit left the log")

	var bench_place: Dictionary = deployables.try_place("workbench", Vector2i(10, 10), 0, 0)
	_check(bool(bench_place["ok"]), "workbench refused: %s" % bench_place["reason"])
	_check(deployables.health_of(int(bench_place["id"])) == 100, "workbench is not 100 HP")


func _load(station: Crafter, input_id: String, input_qty: int, extra_id: String, extra_qty: int, fuel_id: String, fuel_qty: int) -> void:
	station.inventory.slots[CraftRules.INPUT] = {"id": input_id, "qty": input_qty}
	station.inventory.slots[CraftRules.EXTRA] = {"id": extra_id, "qty": extra_qty} if extra_id != "" else {"id": "", "qty": 0}
	station.inventory.slots[CraftRules.FUEL] = {"id": fuel_id, "qty": fuel_qty}
	station.inventory.slots[CraftRules.OUTPUT] = {"id": "", "qty": 0}
	station._job = {}
	station._job_left = 0.0


func _check(ok: bool, message: String) -> void:
	_checks += 1
	if not ok:
		_failures.append(message)
