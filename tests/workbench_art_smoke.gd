extends SceneTree

## Placed workbench must attach the published Meshy mesh.
## godot --headless --path <project> --script res://tests/workbench_art_smoke.gd


func _init() -> void:
	physics_frame.connect(_boot, CONNECT_ONE_SHOT)


func _boot() -> void:
	var code := _run()
	quit(code)


func _run() -> int:
	if not DeployableArt.has_art("workbench"):
		push_error("workbench art missing on disk")
		return 1
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
	var placed: Dictionary = deployables.try_place("workbench", Vector2i(10, 10), 0, 0)
	if not bool(placed.get("ok", false)):
		push_error("workbench place refused: %s" % str(placed.get("reason", "")))
		return 1
	var node := deployables.piece_node(int(placed["id"])) as Node3D
	if node == null:
		push_error("workbench node missing")
		return 1
	if not node.has_meta(&"deployable_art"):
		push_error("workbench did not attach world art")
		return 1
	if node.get_node_or_null("WorldArt") == null:
		push_error("WorldArt child missing")
		return 1
	if DeployableCatalog.footprint("workbench") != Vector2i(2, 1):
		push_error("workbench footprint is not 2x1")
		return 1
	if not is_equal_approx(DeployableCatalog.body_height("workbench"), 1.428):
		push_error("workbench height is not 1.428")
		return 1
	print("WORKBENCH_ART_OK")
	return 0
