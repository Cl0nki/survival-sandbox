extends SceneTree

## Grid deployables share cells with the building system.
## godot --headless --path <project> --script res://tests/deployables.gd

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
		print("DEPLOYABLES_OK")
		quit(0)
	else:
		quit(1)


func _run() -> void:
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

	var along_x: Dictionary = deployables.try_place("chest", Vector2i(0, 0), 0, 0)
	_check(bool(along_x["ok"]), "chest along x refused: %s" % along_x["reason"])
	var x_cells := deployables.cells_of(int(along_x["id"]))
	_check(_same_cells(x_cells, [Vector2i(0, 0), Vector2i(1, 0)]), "chest 2x1 along x was %s" % [str(x_cells)])
	var x_center := deployables.center_of(int(along_x["id"]))
	_check(absf(x_center.x - 1.0) < 0.01 and absf(x_center.z - 0.5) < 0.01, "chest is not centered on the 2x1: %s" % x_center)

	var along_z: Dictionary = deployables.try_place("chest", Vector2i(4, 0), 1, 0)
	_check(bool(along_z["ok"]), "rotated chest refused: %s" % along_z["reason"])
	var z_cells := deployables.cells_of(int(along_z["id"]))
	_check(_same_cells(z_cells, [Vector2i(4, 0), Vector2i(4, 1)]), "rotated chest cells %s" % [str(z_cells)])
	var z_center := deployables.center_of(int(along_z["id"]))
	_check(absf(z_center.x - 4.5) < 0.01 and absf(z_center.z - 1.0) < 0.01, "rotated chest center %s" % z_center)

	var turned: Dictionary = deployables.try_place("chest", Vector2i(8, 0), 2, 0)
	_check(bool(turned["ok"]), "chest facing the other long side refused: %s" % turned["reason"])
	var turned_center := deployables.center_of(int(turned["id"]))
	_check(absf(turned_center.x - 9.0) < 0.01 and absf(turned_center.z - 0.5) < 0.01, "flipped chest left the middle: %s" % turned_center)

	_check(bool(_place(building, "floor_1x1", Vector2i(12, 4))["ok"]), "floor for the dividing wall failed")
	_check(bool(_place(building, "floor_1x1", Vector2i(13, 4))["ok"]), "second floor for the dividing wall failed")
	_check(bool(_place(building, "wall", Vector2i(13, 4), 0, 0, BuildTypes.AXIS_Z)["ok"]), "interior wall was refused")
	var clipped: Dictionary = deployables.try_place("chest", Vector2i(12, 4), 0, 0)
	_check(not bool(clipped["ok"]) and str(clipped["reason"]).find("Wall") >= 0, "chest accepted a wall through its middle: %s" % clipped["reason"])

	_check(bool(_place(building, "floor_1x1", Vector2i(12, 8))["ok"]), "perimeter floor failed")
	_check(bool(_place(building, "floor_1x1", Vector2i(13, 8))["ok"]), "perimeter second floor failed")
	_check(bool(_place(building, "wall", Vector2i(12, 8), 0, 0, BuildTypes.AXIS_X)["ok"]), "perimeter wall was refused")
	var beside: Dictionary = deployables.try_place("chest", Vector2i(12, 8), 0, 0)
	_check(bool(beside["ok"]), "chest refused a wall on its outer edge: %s" % beside["reason"])
	var through: Dictionary = _place(building, "wall", Vector2i(13, 8), 0, 0, BuildTypes.AXIS_Z)
	_check(not bool(through["ok"]) and str(through["reason"]).find("Chest") >= 0, "wall was built through the chest: %s" % through["reason"])
	var outside: Dictionary = _place(building, "wall", Vector2i(12, 9), 0, 0, BuildTypes.AXIS_X)
	_check(bool(outside["ok"]), "wall on the far side of the chest was refused: %s" % outside["reason"])

	_check(bool(_place(building, "floor_1x1", Vector2i(2, 2))["ok"]), "opening floor failed")
	_check(bool(_place(building, "doorway", Vector2i(2, 2), 0, 0, BuildTypes.AXIS_X)["ok"]), "doorway failed")
	_check(bool(_place(building, "window", Vector2i(2, 3), 0, 0, BuildTypes.AXIS_X)["ok"]), "window failed")
	var door: Dictionary = deployables.try_place_edge("door_scrap", Vector4i(2, 2, 0, BuildTypes.AXIS_X))
	_check(bool(door["ok"]), "door did not fit the doorway: %s" % door["reason"])
	var bars_on_door: Dictionary = deployables.try_place_edge("window_scrap", Vector4i(2, 2, 0, BuildTypes.AXIS_X))
	_check(not bool(bars_on_door["ok"]), "window bars fit a doorway")
	var bars: Dictionary = deployables.try_place_edge("window_scrap", Vector4i(2, 3, 0, BuildTypes.AXIS_X))
	_check(bool(bars["ok"]), "window bars did not fit the window: %s" % bars["reason"])
	var door_on_window: Dictionary = deployables.try_place_edge("door_scrap", Vector4i(2, 3, 0, BuildTypes.AXIS_X))
	_check(not bool(door_on_window["ok"]), "door fit a window")
	var wall_in_door: Dictionary = _place(building, "wall", Vector2i(2, 2), 0, 0, BuildTypes.AXIS_X)
	_check(not bool(wall_in_door["ok"]), "wall replaced a doorway that has a door: %s" % wall_in_door["reason"])

	var doorway_id := building.state.edges.component_at(Vector4i(2, 2, 0, BuildTypes.AXIS_X))
	building.authority.apply_bullet(doorway_id, 5000, Vector3.ZERO, "door-break")
	_check(not deployables.has_piece(int(door["id"])), "door stayed after its doorway was destroyed")

	_check(bool(_place(building, "floor_1x1", Vector2i(14, 2))["ok"]), "ground floor failed")
	_check(bool(_place(building, "floor_1x1", Vector2i(15, 2))["ok"]), "ground floor second cell failed")
	_check(bool(_place(building, "floor_1x1", Vector2i(14, 2), 0, 1)["ok"]), "upper floor failed")
	_check(bool(_place(building, "floor_1x1", Vector2i(15, 2), 0, 1)["ok"]), "upper floor second cell failed")
	var upstairs: Dictionary = deployables.try_place("chest", Vector2i(14, 2), 0, 1)
	_check(bool(upstairs["ok"]), "upper chest refused: %s" % upstairs["reason"])
	var slab_id := building.state.slab_at(GridSystem.slab_key(Vector2i(14, 2), 1))
	building.authority.apply_bullet(slab_id, 5000, Vector3.ZERO, "floor-break")
	_check(not deployables.has_piece(int(upstairs["id"])), "upper chest stayed after its floor fell")

	var grounded: Dictionary = deployables.try_place("chest", Vector2i(0, 6), 0, 0)
	_check(bool(grounded["ok"]), "ground chest refused: %s" % grounded["reason"])
	_check(bool(_place(building, "floor_1x1", Vector2i(0, 5))["ok"]), "floor beside the ground chest failed")
	_check(bool(_place(building, "wall", Vector2i(0, 6), 0, 0, BuildTypes.AXIS_X)["ok"]), "wall beside the ground chest failed")
	var wall_id := building.state.edges.component_at(Vector4i(0, 6, 0, BuildTypes.AXIS_X))
	building.authority.apply_bullet(wall_id, 5000, Vector3.ZERO, "wall-break")
	_check(deployables.has_piece(int(grounded["id"])), "ground chest was destroyed when a nearby wall fell")

	_check(bool(_place(building, "floor_1x1", Vector2i(6, 6))["ok"]), "tool doorway floor failed")
	_check(bool(_place(building, "doorway", Vector2i(6, 6), 0, 0, BuildTypes.AXIS_X)["ok"]), "tool doorway failed")
	var tool := DeployTool.new()
	stage.add_child(tool)
	tool.setup(deployables, building)
	var chest_aim := Vector3(1.0, 0.0, 10.5)
	var chest_from := Vector3(1.0, 0.0, 8.0)
	var ghost: Dictionary = tool.preview_at("chest", chest_aim, chest_from, 0)
	_check(bool(ghost["ok"]), "chest ghost refused: %s" % ghost["reason"])
	_check(_same_cells(_as_cells(ghost["cells"]), [Vector2i(0, 10), Vector2i(1, 10)]), "chest ghost cells %s" % str(ghost["cells"]))
	var ghost_center: Vector3 = ghost["center"]
	_check(absf(ghost_center.x - 1.0) < 0.01 and absf(ghost_center.z - 10.5) < 0.01, "chest ghost is not centered: %s" % ghost_center)
	_check(tool.ghost_shown(), "chest ghost is hidden")
	var status := deployables.get_node("DeployPreview/Status") as Label3D
	_check(status != null and status.text.find("2x1") >= 0, "chest blueprint did not say 2x1: %s" % (status.text if status != null else "missing"))
	var far: Dictionary = tool.preview_at("chest", chest_aim, Vector3(1.0, 0.0, 0.0), 0)
	_check(not bool(far["ok"]) and str(far["reason"]) == "Too far", "far chest was %s" % far["reason"])
	var spun: Dictionary = tool.preview_at("chest", Vector3(0.5, 0.0, 15.0), Vector3(0.5, 0.0, 12.0), 1)
	_check(bool(spun["ok"]), "rotated ghost refused: %s" % spun["reason"])
	_check(_same_cells(_as_cells(spun["cells"]), [Vector2i(0, 14), Vector2i(0, 15)]), "rotated ghost cells %s" % str(spun["cells"]))
	var bag := Inventory.new(9)
	bag.ensure_item("chest")
	var placed: Dictionary = tool.place_from(bag, 0, "chest", chest_aim, chest_from, 0)
	_check(bool(placed["ok"]), "hotbar chest was not placed: %s" % placed["reason"])
	_check(bag.count_item("chest") == 0, "chest stayed in the hotbar")
	_check(deployables.has_piece(int(placed["id"])), "placed chest is missing")
	var again: Dictionary = tool.place_from(bag, 0, "chest", Vector3(4.5, 0.0, 10.5), Vector3(4.5, 0.0, 8.0), 0)
	_check(not bool(again["ok"]), "empty hotbar still placed a chest")
	var door_aim := Vector3(6.5, 0.0, 6.3)
	var door_from := Vector3(6.5, 0.0, 4.0)
	bag.ensure_item("door_scrap")
	var door_ghost: Dictionary = tool.preview_at("door_scrap", door_aim, door_from, 0)
	_check(bool(door_ghost["ok"]), "door ghost missed the doorway: %s" % door_ghost["reason"])
	_check(door_ghost["edge"] == Vector4i(6, 6, 0, BuildTypes.AXIS_X), "door ghost edge %s" % str(door_ghost["edge"]))
	var door_placed: Dictionary = tool.place_from(bag, 0, "door_scrap", door_aim, door_from, 0)
	_check(bool(door_placed["ok"]), "hotbar door was not placed: %s" % door_placed["reason"])
	_check(bag.count_item("door_scrap") == 0, "door stayed in the hotbar")
	_check(deployables.health_of(int(door_placed["id"])) == 100, "scrap door is not 100 HP")
	var fitting := deployables.piece_node(int(door_placed["id"]))
	var closed_tip: Vector3 = fitting.leaf_tip()
	_check(closed_tip.x > 0.3 and absf(closed_tip.z) < 0.05, "closed door does not fill the doorway: %s" % closed_tip)
	var door_at: Vector3 = (fitting as Node3D).global_position
	_check(deployables.toggle_door(int(door_placed["id"]), door_at + Vector3(0.0, 0.0, 1.0)), "door did not open")
	_check(bool(fitting.get("open")), "door stayed shut")
	var open_tip: Vector3 = fitting.leaf_tip()
	_check(open_tip.z > 0.4 and open_tip.x < 0.0, "door did not swing toward the player: %s" % open_tip)
	_check(deployables.toggle_door(int(door_placed["id"]), door_at + Vector3(0.0, 0.0, 1.0)), "door did not close")
	_check(not bool(fitting.get("open")), "door stayed open")
	var shut_tip: Vector3 = fitting.leaf_tip()
	_check(shut_tip.x > 0.3 and absf(shut_tip.z) < 0.05, "closed door left the doorway: %s" % shut_tip)
	_check(not deployables.toggle_door(int(bars["id"]), door_at), "window bars opened")
	_check(fitting.receive_damage(100, Vector3.ZERO), "scrap door ignored the shot")
	_check(not deployables.has_piece(int(door_placed["id"])), "scrap door stayed at 0 HP")
	var wood_door: Dictionary = deployables.try_place_edge("door_wood", Vector4i(6, 6, 0, BuildTypes.AXIS_X))
	_check(bool(wood_door["ok"]), "wood door refused the empty doorway: %s" % wood_door["reason"])
	_check(deployables.health_of(int(wood_door["id"])) == 200, "wood door is not half of wood tier HP")

	var bench: Dictionary = deployables.try_place("workbench", Vector2i(10, 10), 0, 0)
	_check(bool(bench["ok"]), "workbench refused: %s" % bench["reason"])
	_check(deployables.health_of(int(bench["id"])) == 100, "workbench is not 100 HP")
	var bench_body := deployables.piece_node(int(bench["id"]))
	_check(bench_body.receive_damage(40, Vector3.ZERO), "workbench ignored the shot")
	_check(deployables.health_of(int(bench["id"])) == 60, "workbench health did not drop to 60")
	_check(bench_body.receive_damage(60, Vector3.ZERO), "workbench ignored the killing shot")
	_check(not deployables.has_piece(int(bench["id"])), "workbench stayed at 0 HP")
	_check(DeployableCatalog.max_health("chest") == 100, "chest max health is not 100")
	for tier in range(BuildingTier.MIN, BuildingTier.MAX + 1):
		var half := BuildingTier.health_of(tier) / 2
		_check(DeployableCatalog.max_health(DeployableCatalog.door_id(tier)) == half, "door tier %d health" % tier)
		_check(DeployableCatalog.max_health(DeployableCatalog.window_id(tier)) == half, "window tier %d health" % tier)

	stage.free()


func _place(building: BuildingSystem, blueprint_id: String, anchor: Vector2i, rotation: int = 0, level: int = 0, axis: int = 0) -> Dictionary:
	return building.authority.request_place(RoomPlacer.make_request(blueprint_id, anchor, rotation, level, axis))


func _as_cells(raw: Array) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for cell in raw:
		cells.append(cell)
	return cells


func _same_cells(got: Array[Vector2i], want: Array) -> bool:
	if got.size() != want.size():
		return false
	for cell in want:
		if not got.has(cell):
			return false
	return true


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)
