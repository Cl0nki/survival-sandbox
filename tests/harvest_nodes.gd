extends SceneTree

## Headless check for minable deposits, tool math, and the west mine pad.
## godot --headless --path <project> --script res://tests/harvest_nodes.gd

const EXPECTED := {
	"stone": [40, 8, "pickaxe", 1.0, 1.0],
	"iron_ore": [70, 5, "pickaxe", 1.6, 1.0],
	"copper_ore": [55, 6, "pickaxe", 1.3, 1.0],
	"coal": [45, 8, "pickaxe", 1.1, 1.0],
	"limestone": [35, 8, "pickaxe", 0.9, 1.0],
	"sulfur": [50, 5, "pickaxe", 1.2, 1.0],
	"bauxite": [65, 5, "pickaxe", 1.5, 1.0],
	"lead_ore": [60, 5, "pickaxe", 1.4, 1.0],
	"quartz": [80, 4, "pickaxe", 1.8, 1.0],
}

const EXPECTED_TREES := {
	"oak": [55, "hatchet", 1.2, [["log", 6], ["stick", 4], ["plant_resin", 1]]],
	"birch": [32, "hatchet", 0.8, [["log", 3], ["stick", 8], ["plant_resin", 2]]],
	"spruce": [48, "hatchet", 1.0, [["log", 5], ["stick", 6], ["plant_resin", 3]]],
}

const EXPECTED_SCAVENGE := {
	"broken_car": [56, "crowbar", 1.4, [["scrap_metal", 6], ["steel_scrap", 3], ["rubber", 2], ["mechanical_part", 1], ["glass", 2], ["plastic", 2]]],
	"scrap_pile": [32, "crowbar", 0.8, [["scrap_metal", 10], ["steel_scrap", 2], ["plastic", 4]]],
	"rubble_pile": [40, "crowbar", 1.1, [["stone", 6], ["limestone", 4], ["scrap_metal", 2]]],
	"tire_pile": [24, "crowbar", 0.7, [["rubber", 8]]],
}


func _init() -> void:
	physics_frame.connect(_boot, CONNECT_ONE_SHOT)


func _boot() -> void:
	var code := _run()
	if code == 0:
		print("HARVEST_NODES_OK")
	quit(code)


func _run() -> int:
	for item_id in ["bauxite", "lead_ore", "quartz", "log", "stick", "plant_resin", "pickaxe_scrap", "shovel_scrap", "pickaxe_composite", "hatchet_scrap", "crowbar_scrap", "rubber", "mechanical_part"]:
		if not ItemCatalog.known(item_id):
			print("FAIL catalog missing %s" % item_id)
			return 1
	if ItemCatalog.known("wood"):
		print("FAIL wood should be gone")
		return 1
	var pick := ItemCatalog.get_item("pickaxe_scrap")
	var shovel := ItemCatalog.get_item("shovel_scrap")
	var composite := ItemCatalog.get_item("pickaxe_composite")
	var hatchet := ItemCatalog.get_item("hatchet_scrap")
	var crowbar := ItemCatalog.get_item("crowbar_scrap")
	var crowbar_composite := ItemCatalog.get_item("crowbar_composite")
	if pick.harvest_kind != "pickaxe" or pick.harvest_power != 8:
		print("FAIL scrap pickaxe fields")
		return 1
	if shovel.harvest_kind != "shovel" or shovel.harvest_power != 8:
		print("FAIL scrap shovel fields")
		return 1
	if composite.harvest_kind != "pickaxe" or composite.harvest_power != 36:
		print("FAIL composite pickaxe fields")
		return 1
	if hatchet.harvest_kind != "hatchet" or hatchet.harvest_power != 8:
		print("FAIL scrap hatchet fields")
		return 1
	if crowbar.harvest_kind != "crowbar" or crowbar.harvest_power != 8:
		print("FAIL scrap crowbar fields")
		return 1
	if crowbar_composite.harvest_kind != "crowbar" or crowbar_composite.harvest_power != 36:
		print("FAIL composite crowbar fields")
		return 1
	for deposit_id in EXPECTED.keys():
		var deposit := ResourceCatalog.get_deposit(deposit_id)
		if deposit == null:
			print("FAIL missing deposit %s" % deposit_id)
			return 1
		var row: Array = EXPECTED[deposit_id]
		if deposit.health != int(row[0]) or deposit.yield_amount != int(row[1]):
			print("FAIL %s health/yield %d/%d" % [deposit_id, deposit.health, deposit.yield_amount])
			return 1
		if deposit.tool_kind != str(row[2]):
			print("FAIL %s tool %s" % [deposit_id, deposit.tool_kind])
			return 1
		if not is_equal_approx(deposit.resistance, float(row[3])) or not is_equal_approx(deposit.tool_multiplier, float(row[4])):
			print("FAIL %s resist/mult" % deposit_id)
			return 1
		if not ItemCatalog.known(deposit.item_id):
			print("FAIL deposit item missing %s" % deposit.item_id)
			return 1
	var stone := ResourceCatalog.get_deposit("stone")
	var iron := ResourceCatalog.get_deposit("iron_ore")
	if HarvestSwing.damage_for(pick, stone) != 8:
		print("FAIL stone scrap pick damage %d" % HarvestSwing.damage_for(pick, stone))
		return 1
	if HarvestSwing.damage_for(pick, iron) != 5:
		print("FAIL iron scrap pick damage %d" % HarvestSwing.damage_for(pick, iron))
		return 1
	if HarvestSwing.damage_for(composite, iron) != 23:
		print("FAIL iron composite pick damage %d" % HarvestSwing.damage_for(composite, iron))
		return 1
	if HarvestSwing.damage_for(shovel, stone) != 0:
		print("FAIL shovel should not chip stone")
		return 1
	if ResourceCatalog.known("clay") or ResourceCatalog.known("sand"):
		print("FAIL clay/sand should not be mine nodes")
		return 1
	if ResourceCatalog.known("pine"):
		print("FAIL pine should be gone")
		return 1
	for tree_id in EXPECTED_TREES.keys():
		var tree := ResourceCatalog.get_deposit(tree_id)
		if tree == null:
			print("FAIL missing tree %s" % tree_id)
			return 1
		var spec: Array = EXPECTED_TREES[tree_id]
		if tree.health != int(spec[0]) or tree.tool_kind != str(spec[1]) or not is_equal_approx(tree.resistance, float(spec[2])):
			print("FAIL tree stats %s" % tree_id)
			return 1
		if tree.visual != "tree":
			print("FAIL %s is not a tree visual" % tree_id)
			return 1
		var got := tree.yield_entries()
		var want: Array = spec[3]
		if got.size() != want.size():
			print("FAIL %s yield count" % tree_id)
			return 1
		for index in want.size():
			if str(got[index][0]) != str(want[index][0]) or int(got[index][1]) != int(want[index][1]):
				print("FAIL %s yield %s" % [tree_id, got])
				return 1
	var oak := ResourceCatalog.get_deposit("oak")
	var birch := ResourceCatalog.get_deposit("birch")
	if HarvestSwing.damage_for(hatchet, oak) != 7:
		print("FAIL oak scrap hatchet damage %d" % HarvestSwing.damage_for(hatchet, oak))
		return 1
	if HarvestSwing.damage_for(hatchet, birch) != 10:
		print("FAIL birch scrap hatchet damage %d" % HarvestSwing.damage_for(hatchet, birch))
		return 1
	if HarvestSwing.damage_for(pick, oak) != 0:
		print("FAIL pickaxe should not fell oak")
		return 1
	for scavenge_id in EXPECTED_SCAVENGE.keys():
		var wreck := ResourceCatalog.get_deposit(scavenge_id)
		if wreck == null:
			print("FAIL missing scavenge %s" % scavenge_id)
			return 1
		var salvage: Array = EXPECTED_SCAVENGE[scavenge_id]
		if wreck.health != int(salvage[0]) or wreck.tool_kind != str(salvage[1]) or not is_equal_approx(wreck.resistance, float(salvage[2])):
			print("FAIL scavenge stats %s" % scavenge_id)
			return 1
		if wreck.visual != "rock":
			print("FAIL %s is not a cube" % scavenge_id)
			return 1
		var salvage_got := wreck.yield_entries()
		var salvage_want: Array = salvage[3]
		if salvage_got.size() != salvage_want.size():
			print("FAIL %s yield count" % scavenge_id)
			return 1
		for salvage_index in salvage_want.size():
			if str(salvage_got[salvage_index][0]) != str(salvage_want[salvage_index][0]) or int(salvage_got[salvage_index][1]) != int(salvage_want[salvage_index][1]):
				print("FAIL %s yield %s" % [scavenge_id, salvage_got])
				return 1
			if not ItemCatalog.known(str(salvage_want[salvage_index][0])):
				print("FAIL scavenge item missing %s" % str(salvage_want[salvage_index][0]))
				return 1
	var car := ResourceCatalog.get_deposit("broken_car")
	var heap := ResourceCatalog.get_deposit("scrap_pile")
	if HarvestSwing.damage_for(crowbar, car) != 6:
		print("FAIL car scrap crowbar damage %d" % HarvestSwing.damage_for(crowbar, car))
		return 1
	if HarvestSwing.damage_for(crowbar_composite, car) != 26:
		print("FAIL car composite crowbar damage %d" % HarvestSwing.damage_for(crowbar_composite, car))
		return 1
	if HarvestSwing.damage_for(crowbar, heap) != 10:
		print("FAIL scrap pile crowbar damage %d" % HarvestSwing.damage_for(crowbar, heap))
		return 1
	if HarvestSwing.damage_for(pick, car) != 0:
		print("FAIL pickaxe should not strip a car")
		return 1
	var bag := Inventory.new(NetConfig.INVENTORY_SLOTS)
	var node := ResourceNode.new()
	node.configure("test_stone", "stone")
	root.add_child(node)
	if node.health != 40:
		print("FAIL stone node health %d" % node.health)
		return 1
	if node.receive_damage(34, Vector3.ZERO):
		print("FAIL pistol mined stone")
		return 1
	if node.health != 40:
		print("FAIL pistol changed stone health")
		return 1
	var wrong := node.harvest("shovel_scrap", bag)
	if bool(wrong.get("changed", false)) or node.health != 40:
		print("FAIL wrong tool chipped stone")
		return 1
	if str(wrong.get("notice", "")).find("pickaxe") < 0:
		print("FAIL wrong-tool notice: %s" % str(wrong.get("notice", "")))
		return 1
	var hit := node.harvest("pickaxe_scrap", bag)
	if not bool(hit.get("ok", false)) or node.health != 32 or int(hit.get("damage", 0)) != 8:
		print("FAIL stone chip %s hp=%d" % [hit, node.health])
		return 1
	var swings := 0
	while not node.depleted and swings < 8:
		node.harvest("pickaxe_scrap", bag)
		swings += 1
	if not node.depleted or bag.count_item("stone") != 8:
		print("FAIL stone yield hp=%d stone=%d" % [node.health, bag.count_item("stone")])
		return 1
	var tree_node := ResourceNode.new()
	tree_node.configure("test_birch", "birch")
	root.add_child(tree_node)
	if tree_node.harvest("pickaxe_scrap", bag).get("changed", false):
		print("FAIL pickaxe felled birch")
		return 1
	var tree_swings := 0
	while not tree_node.depleted and tree_swings < 8:
		tree_node.harvest("hatchet_scrap", bag)
		tree_swings += 1
	if not tree_node.depleted or bag.count_item("log") != 3 or bag.count_item("stick") != 8 or bag.count_item("plant_resin") != 2:
		print(
			"FAIL birch yield log=%d stick=%d resin=%d"
			% [bag.count_item("log"), bag.count_item("stick"), bag.count_item("plant_resin")]
		)
		return 1
	var arena := Node3D.new()
	arena.name = "Arena"
	root.add_child(arena)
	LootLayout.build(arena)
	ResourceField.build(arena)
	WoodsField.build(arena)
	ScavengeField.build(arena)
	var mine := arena.get_node_or_null("Mine")
	if mine == null:
		print("FAIL mine folder missing")
		return 1
	for deposit_id in ResourceCatalog.mineral_ids():
		var placed := mine.get_node_or_null(deposit_id) as ResourceNode
		if placed == null:
			print("FAIL missing node %s" % deposit_id)
			return 1
		var deposit := ResourceCatalog.get_deposit(deposit_id)
		if placed.health != deposit.health or placed.deposit_id != deposit_id:
			print("FAIL placed %s health %d" % [deposit_id, placed.health])
			return 1
	if mine.get_node_or_null("oak") != null:
		print("FAIL tree spawned in the mine")
		return 1
	for pick_id in ["mine_pickaxe_scrap", "mine_pickaxe_iron", "mine_pickaxe_steel", "mine_pickaxe_composite"]:
		if arena.get_node_or_null("Loot/%s" % pick_id) == null:
			print("FAIL mine pickup missing %s" % pick_id)
			return 1
	if arena.get_node_or_null("Loot/mine_shovel") != null:
		print("FAIL mine shovel pickup should be gone")
		return 1
	if mine.get_node_or_null("clay") != null or mine.get_node_or_null("sand") != null:
		print("FAIL clay/sand nodes still placed")
		return 1
	var woods := arena.get_node_or_null("Woods")
	if woods == null:
		print("FAIL woods folder missing")
		return 1
	for tree_id in ResourceCatalog.tree_ids():
		var planted := woods.get_node_or_null(tree_id) as ResourceNode
		if planted == null:
			print("FAIL missing tree %s" % tree_id)
			return 1
		if planted.health != ResourceCatalog.get_deposit(tree_id).health:
			print("FAIL planted %s health %d" % [tree_id, planted.health])
			return 1
	if woods.get_node_or_null("pine") != null:
		print("FAIL pine still planted")
		return 1
	for hatchet_id in ["woods_hatchet_scrap", "woods_hatchet_iron", "woods_hatchet_steel", "woods_hatchet_composite"]:
		if arena.get_node_or_null("Loot/%s" % hatchet_id) == null:
			print("FAIL woods pickup missing %s" % hatchet_id)
			return 1
	var scavenge := arena.get_node_or_null("Scavenge")
	if scavenge == null:
		print("FAIL scavenge folder missing")
		return 1
	for scavenge_id in ResourceCatalog.scavenge_ids():
		var placed_wreck := scavenge.get_node_or_null(scavenge_id) as ResourceNode
		if placed_wreck == null:
			print("FAIL missing scavenge node %s" % scavenge_id)
			return 1
		if placed_wreck.health != ResourceCatalog.get_deposit(scavenge_id).health:
			print("FAIL placed %s health %d" % [scavenge_id, placed_wreck.health])
			return 1
	if scavenge.get_node_or_null("stone") != null:
		print("FAIL mineral spawned in scavenge")
		return 1
	for crowbar_id in ["scavenge_crowbar_scrap", "scavenge_crowbar_iron", "scavenge_crowbar_steel", "scavenge_crowbar_composite"]:
		if arena.get_node_or_null("Loot/%s" % crowbar_id) == null:
			print("FAIL scavenge pickup missing %s" % crowbar_id)
			return 1
	var scrap_node := ResourceNode.new()
	scrap_node.configure("test_scrap_pile", "scrap_pile")
	root.add_child(scrap_node)
	if scrap_node.harvest("pickaxe_scrap", bag).get("changed", false):
		print("FAIL pickaxe stripped scrap pile")
		return 1
	var scrap_swings := 0
	while not scrap_node.depleted and scrap_swings < 8:
		scrap_node.harvest("crowbar_scrap", bag)
		scrap_swings += 1
	if not scrap_node.depleted or bag.count_item("scrap_metal") != 10 or bag.count_item("steel_scrap") != 2 or bag.count_item("plastic") != 4:
		print(
			"FAIL scrap pile yield metal=%d steel=%d plastic=%d"
			% [bag.count_item("scrap_metal"), bag.count_item("steel_scrap"), bag.count_item("plastic")]
		)
		return 1
	var rubble := ResourceNode.new()
	rubble.configure("test_rubble", "rubble_pile")
	root.add_child(rubble)
	var rubble_swings := 0
	while not rubble.depleted and rubble_swings < 8:
		rubble.harvest("crowbar_scrap", bag)
		rubble_swings += 1
	if not rubble.depleted or bag.count_item("stone") != 14 or bag.count_item("limestone") != 4 or bag.count_item("scrap_metal") != 12:
		print(
			"FAIL rubble yield stone=%d limestone=%d scrap=%d"
			% [bag.count_item("stone"), bag.count_item("limestone"), bag.count_item("scrap_metal")]
		)
		return 1
	var tires := ResourceNode.new()
	tires.configure("test_tires", "tire_pile")
	root.add_child(tires)
	var tire_swings := 0
	while not tires.depleted and tire_swings < 6:
		tires.harvest("crowbar_scrap", bag)
		tire_swings += 1
	if not tires.depleted or bag.count_item("rubber") != 8:
		print("FAIL tire yield rubber=%d" % bag.count_item("rubber"))
		return 1
	print("harvest deposits %d trees %d scavenge %d" % [ResourceCatalog.mineral_ids().size(), ResourceCatalog.tree_ids().size(), ResourceCatalog.scavenge_ids().size()])
	return 0
