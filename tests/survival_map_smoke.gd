extends SceneTree

## Boots the survival map locally and checks biome harvest zones exist without crates.
## godot --headless --path <project> --script res://tests/survival_map_smoke.gd


func _init() -> void:
	physics_frame.connect(_boot, CONNECT_ONE_SHOT)


func _boot() -> void:
	var packed := load("res://scenes/world/test_arena.tscn") as PackedScene
	if packed == null:
		return _fail("missing test_arena.tscn")
	var arena := packed.instantiate() as Node3D
	arena.force_mode = NetConfig.MODE_LOCAL
	arena.force_map = NetConfig.MAP_SURVIVAL
	root.add_child(arena)
	await process_frame
	await process_frame
	if arena.get_node_or_null("Survival") == null:
		return _fail("Survival root missing")
	if arena.get_node_or_null("Loot") == null:
		return _fail("Loot folder missing")
	for zone_name in ["Meadow", "ForestOak", "ForestBirch", "ForestSpruce", "Hills", "Wasteland", "City"]:
		if arena.get_node_or_null("Survival/%s" % zone_name) == null:
			return _fail("%s biome missing" % zone_name)
	if arena.get_node_or_null("ShootingRange") != null:
		return _fail("shooting range should stay on the debug map")
	if arena.get_node_or_null("OpenDummy") != null:
		return _fail("open dummy should be removed on survival")
	if arena.get_node_or_null("Loot/crafting_crate") != null:
		return _fail("survival should have no chests")
	if arena.get_node_or_null("Loot/military_crate") != null:
		return _fail("survival should have no military chest")
	if _resource_count(arena.get_node("Survival/ForestOak")) < 18:
		return _fail("oak forest too sparse")
	if _resource_count(arena.get_node("Survival/ForestBirch")) < 18:
		return _fail("birch forest too sparse")
	if _resource_count(arena.get_node("Survival/ForestSpruce")) < 18:
		return _fail("spruce forest too sparse")
	if _resource_count(arena.get_node("Survival/Hills")) < 12:
		return _fail("hills should have ores and stones")
	if _resource_count(arena.get_node("Survival/Wasteland")) < 14:
		return _fail("wasteland should have bushes/stones")
	if _resource_count(arena.get_node("Survival/Meadow")) < 6:
		return _fail("meadow should have stones/water")
	if not _props_inside_biome(arena, "Hills", Vector3(14.0, 0.0, -27.0), Vector2(52.0, 26.0)):
		return _fail("hills props spilled outside hills")
	if not _props_inside_biome(arena, "ForestOak", Vector3(-26.0, 0.0, -27.0), Vector2(28.0, 26.0)):
		return _fail("oak props spilled outside oak forest")
	if not _props_inside_biome(arena, "Meadow", Vector3(2.0, 0.0, 13.0), Vector2(28.0, 54.0)):
		return _fail("meadow props spilled outside meadow")
	if not FileAccess.file_exists("res://assets/textures/ground_forest_oak/albedo.png"):
		return _fail("oak forest ground texture missing")
	if not FileAccess.file_exists("res://assets/textures/ground_forest_birch/albedo.png"):
		return _fail("birch forest ground texture missing")
	if not FileAccess.file_exists("res://assets/textures/ground_forest_spruce/albedo.png"):
		return _fail("spruce forest ground texture missing")
	if _deposit_count(arena.get_node("Survival/Meadow"), "ground_water") < 1:
		return _fail("meadow missing ground water")
	if _deposit_count(arena.get_node("Survival/Wasteland"), "crude_oil") < 1:
		return _fail("wasteland missing oil")
	if _deposit_count(arena.get_node("Survival/Hills"), "natural_gas") < 1:
		return _fail("hills missing natural gas")
	if _resource_count(arena.get_node("Survival/City")) < 12:
		return _fail("city should have scrap harvestables")
	if not _props_inside_biome(arena, "City", Vector3(28.0, 0.0, 26.0), Vector2(24.0, 28.0)):
		return _fail("city props spilled outside city")
	if _deposit_count(arena.get_node("Survival/City"), "") != 0:
		return _fail("city should have no ground deposits")
	if not BiomeCatalog.known("meadow") or not BiomeCatalog.known("city"):
		return _fail("BiomeCatalog missing core biomes")
	var bag := Inventory.new(NetConfig.INVENTORY_SLOTS)
	bag.grant_loadout(NetConfig.MAP_SURVIVAL)
	if bag.count_item("debugweapon") > 0 or bag.count_item("build_tool") > 0:
		return _fail("survival loadout should not grant debug tools")
	if bag.count_item("workbench") > 0:
		return _fail("survival loadout should not grant a workbench; it is placed in the hut")
	if arena.get_node_or_null("GroundSplat") == null:
		return _fail("survival splat map missing")
	if arena.get_node_or_null("BuildingSystem") == null:
		return _fail("BuildingSystem missing")
	var building := arena.get_node("BuildingSystem") as BuildingSystem
	if building == null or building.state == null or building.state.component_count() < 8:
		return _fail("starter wood house missing")
	var deployables := arena.get_node_or_null("DeployableSystem") as DeployableSystem
	if deployables == null or deployables.piece_count() < 2:
		return _fail("starter door/workbench missing")
	## Seed is deferred; wait until the hut workbench exists.
	for _i in 8:
		await process_frame
		var ready: Dictionary = deployables.plan_cells("workbench", Vector2i(-6, 7), 0, 0)
		if not bool(ready.get("ok", false)) and str(ready.get("reason", "")).begins_with("Blocked by"):
			break
	var bench_probe: Dictionary = deployables.plan_cells("workbench", Vector2i(-6, 7), 0, 0)
	if bool(bench_probe.get("ok", false)) or not str(bench_probe.get("reason", "")).begins_with("Blocked by"):
		return _fail("starter workbench not on house floor")
	var blast := ItemCatalog.get_item("blast_gun")
	if blast == null or blast.category != "debug":
		return _fail("blast_gun should be debug category")
	print("SURVIVAL_MAP_SMOKE_OK")
	quit(0)


func _resource_count(zone: Node) -> int:
	var total := 0
	for child in zone.get_children():
		if child is ResourceNode:
			total += 1
	return total


func _deposit_count(zone: Node, definition_id: String) -> int:
	var total := 0
	for child in zone.get_children():
		var deposit := child as GroundDeposit
		if deposit == null:
			continue
		if definition_id == "" or deposit.definition_id == definition_id:
			total += 1
	return total


func _props_inside_biome(arena: Node3D, zone_name: String, center: Vector3, extent: Vector2) -> bool:
	var zone := arena.get_node_or_null("Survival/%s" % zone_name) as Node3D
	if zone == null:
		return false
	var half := extent * 0.5
	var pad := 0.05
	for child in zone.get_children():
		if not (child is ResourceNode or child is GroundDeposit):
			continue
		var node := child as Node3D
		if absf(node.position.x - center.x) > half.x + pad:
			return false
		if absf(node.position.z - center.z) > half.y + pad:
			return false
	return true


func _fail(reason: String) -> void:
	printerr("SURVIVAL_MAP_SMOKE_FAIL ", reason)
	quit(1)
