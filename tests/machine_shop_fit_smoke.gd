extends SceneTree

## Confirms the machine shop mesh keeps its proportions inside the station box.


func _init() -> void:
	physics_frame.connect(_boot, CONNECT_ONE_SHOT)


func _boot() -> void:
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
	var placed: Dictionary = deployables.try_place("machine_shop", Vector2i(4, 0), 0, 0)
	if not bool(placed.get("ok", false)):
		push_error("place failed: %s" % str(placed.get("reason", "")))
		quit(1)
		return
	var node := deployables.piece_node(int(placed["id"])) as Node3D
	var art := node.get_node_or_null("WorldArt") as Node3D
	if art == null:
		push_error("WorldArt missing")
		quit(1)
		return
	if DeployableCatalog.footprint("machine_shop") != Vector2i(2, 3):
		push_error("machine shop footprint is not 2x3")
		quit(1)
		return
	if not is_equal_approx(DeployableCatalog.body_height("machine_shop"), 1.419):
		push_error("machine shop height is not 1.419")
		quit(1)
		return
	var bounds := DeployableArt._visual_aabb(art, Transform3D.IDENTITY)
	var uniform := is_equal_approx(art.scale.x, art.scale.y) and is_equal_approx(art.scale.y, art.scale.z)
	print("SCALE ", art.scale)
	print("SIZE ", bounds.size)
	if not uniform:
		push_error("machine shop scale is not uniform: %s" % art.scale)
		quit(1)
		return
	if absf(bounds.size.z - 2.39) > 0.08 or absf(bounds.size.y - 1.419) > 0.05:
		push_error("machine shop is not the 2x3 size: %s" % bounds.size)
		quit(1)
		return
	if bounds.size.x > 1.81:
		push_error("machine shop is wider than the 2-cell side: %s" % bounds.size)
		quit(1)
		return
	var hull_size := Vector3.ZERO
	for child in node.get_children():
		if child is CollisionShape3D:
			var hull := (child as CollisionShape3D).shape as BoxShape3D
			if hull != null:
				hull_size = hull.size
	print("HULL ", hull_size)
	if hull_size.x >= bounds.size.x or hull_size.y >= bounds.size.y or hull_size.z >= bounds.size.z:
		push_error("machine shop collision is not inside the mesh: %s vs %s" % [hull_size, bounds.size])
		quit(1)
		return
	if hull_size.x > 1.0:
		push_error("machine shop collision is still the pad width: %s" % hull_size)
		quit(1)
		return
	print("MACHINE_SHOP_FIT_OK")
	quit(0)
