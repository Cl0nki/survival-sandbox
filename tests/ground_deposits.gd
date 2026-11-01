extends SceneTree

## Headless check for ground deposit types, shovel extract, and the NE pad.
## godot --headless --path <project> --script res://tests/ground_deposits.gd

const EXPECTED := {
	"sand": ["sand", "sand", 100, 500, "shovel", "shovel"],
	"clay": ["clay", "clay", 80, 500, "shovel", "shovel"],
	"gravel": ["gravel", "gravel", 180, 400, "shovel", "shovel"],
	"ground_water": ["Ground Water", "ground_water", 250, 1000, "", "well"],
	"natural_gas": ["Natural Gas", "natural_gas", 350, 600, "", "well"],
	"crude_oil": ["Crude Oil", "oil", 450, 800, "", "pump"],
}


func _init() -> void:
	physics_frame.connect(_boot, CONNECT_ONE_SHOT)


func _boot() -> void:
	var code := _run()
	if code == 0:
		print("GROUND_DEPOSITS_OK")
	quit(code)


func _run() -> int:
	for item_id in ["sand", "clay", "gravel", "ground_water", "natural_gas", "oil"]:
		if not ItemCatalog.known(item_id):
			print("FAIL catalog missing %s" % item_id)
			return 1
	if GroundDepositCatalog.all_ids().size() != 6:
		print("FAIL expected 6 ground types, got %d" % GroundDepositCatalog.all_ids().size())
		return 1
	for deposit_id in EXPECTED.keys():
		var spec := GroundDepositCatalog.get_definition(deposit_id)
		if spec == null:
			print("FAIL missing definition %s" % deposit_id)
			return 1
		var row: Array = EXPECTED[deposit_id]
		if spec.item_id != str(row[1]) or spec.resistance != int(row[2]) or spec.yield_amount != int(row[3]):
			print("FAIL %s resist/yield/item %d/%d/%s" % [deposit_id, spec.resistance, spec.yield_amount, spec.item_id])
			return 1
		if spec.harvest_kind != str(row[4]) or not spec.can_extract_with(str(row[5])):
			print("FAIL %s harvest/extractor" % deposit_id)
			return 1
		if spec.resistance == spec.yield_amount:
			print("FAIL %s resistance and yield must stay independent" % deposit_id)
			return 1
	var sand := GroundDepositCatalog.get_definition("sand")
	var clay := GroundDepositCatalog.get_definition("clay")
	var gravel := GroundDepositCatalog.get_definition("gravel")
	var oil := GroundDepositCatalog.get_definition("crude_oil")
	var shovel := ItemCatalog.get_item("shovel_scrap")
	var pick := ItemCatalog.get_item("pickaxe_scrap")
	if HarvestSwing.ground_extract(shovel, sand) != 24:
		print("FAIL sand scrap shovel extract %d" % HarvestSwing.ground_extract(shovel, sand))
		return 1
	if HarvestSwing.ground_extract(shovel, clay) != 30:
		print("FAIL clay scrap shovel extract %d" % HarvestSwing.ground_extract(shovel, clay))
		return 1
	if HarvestSwing.ground_extract(shovel, gravel) != 13:
		print("FAIL gravel scrap shovel extract %d" % HarvestSwing.ground_extract(shovel, gravel))
		return 1
	if HarvestSwing.ground_extract(pick, sand) != 0:
		print("FAIL pickaxe extracted sand")
		return 1
	if HarvestSwing.ground_extract(shovel, oil) != 0:
		print("FAIL shovel extracted oil")
		return 1
	var bag := Inventory.new(NetConfig.INVENTORY_SLOTS)
	var patch := GroundDeposit.new()
	patch.configure("test_sand", "sand")
	root.add_child(patch)
	if patch.remaining != 500 or patch.resistance != 100:
		print("FAIL sand instance remaining/resist %d/%d" % [patch.remaining, patch.resistance])
		return 1
	if not patch.covers_world_point(patch.global_position):
		print("FAIL sand center is outside its square")
		return 1
	if patch.covers_world_point(patch.global_position + Vector3(20, 0, 20)):
		print("FAIL far point counted as sand")
		return 1
	if GroundDeposit.compatible_at(patch, patch.global_position, "shovel") == null:
		print("FAIL compatible_at missed sand")
		return 1
	if GroundDeposit.compatible_at(patch, patch.global_position, "pump") != null:
		print("FAIL pump matched sand")
		return 1
	var wrong := patch.harvest("pickaxe_scrap", bag)
	if bool(wrong.get("changed", false)) or patch.remaining != 500:
		print("FAIL pickaxe changed sand")
		return 1
	var hit := patch.harvest("shovel_scrap", bag)
	if not bool(hit.get("ok", false)) or patch.remaining != 476 or bag.count_item("sand") != 24:
		print("FAIL sand shovel swing remain=%d sand=%d" % [patch.remaining, bag.count_item("sand")])
		return 1
	var taken := patch.take(476)
	if taken != 476 or not patch.depleted or patch.remaining != 0:
		print("FAIL take did not empty sand")
		return 1
	var oil_patch := GroundDeposit.new()
	oil_patch.configure("test_oil", "crude_oil")
	root.add_child(oil_patch)
	var blocked := oil_patch.harvest("shovel_scrap", bag)
	if bool(blocked.get("changed", false)) or oil_patch.remaining != 800:
		print("FAIL shovel drained oil")
		return 1
	if str(blocked.get("notice", "")).find("pump") < 0:
		print("FAIL oil notice: %s" % str(blocked.get("notice", "")))
		return 1
	if oil_patch.take(50) != 50 or oil_patch.remaining != 750:
		print("FAIL pump take remaining %d" % oil_patch.remaining)
		return 1
	var arena := Node3D.new()
	arena.name = "Arena"
	root.add_child(arena)
	LootLayout.build(arena)
	GroundDepositField.build(arena)
	var folder := arena.get_node_or_null("GroundDeposits")
	if folder == null:
		print("FAIL ground folder missing")
		return 1
	for deposit_id in GroundDepositCatalog.all_ids():
		var placed := folder.get_node_or_null(deposit_id) as GroundDeposit
		if placed == null:
			print("FAIL missing patch %s" % deposit_id)
			return 1
		var spec := GroundDepositCatalog.get_definition(deposit_id)
		if placed.remaining != spec.yield_amount or placed.resistance != spec.resistance:
			print("FAIL placed %s remaining/resist" % deposit_id)
			return 1
	for shovel_id in ["ground_shovel_scrap", "ground_shovel_iron", "ground_shovel_steel", "ground_shovel_composite"]:
		if arena.get_node_or_null("Loot/%s" % shovel_id) == null:
			print("FAIL missing %s" % shovel_id)
			return 1
	print("ground deposits %d" % GroundDepositCatalog.all_ids().size())
	return 0
