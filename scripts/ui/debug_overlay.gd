extends CanvasLayer

@onready var _label: Label = $Panel/Label

var _weight_key := ""
var _weight_cache := PackedStringArray()


func _ready() -> void:
	if has_meta(&"suppress_ready"):
		set_process(false)
		visible = false


func _process(_delta: float) -> void:
	var lines := PackedStringArray()
	var networked := _net() != null
	if networked:
		lines.append("Survival Sandbox  |  multiplayer")
	else:
		lines.append("Survival Sandbox  |  Milestone 1 local prototype")
	lines.append("FPS %d" % Engine.get_frames_per_second())
	var session := get_node_or_null("/root/NetSession")
	if session != null and int(session.get("mode")) != NetConfig.MODE_LOCAL:
		lines.append("Net       %s" % str(session.get("status_text")))
		if str(session.get("last_error")) != "":
			lines.append("Error     %s" % str(session.get("last_error")))
	var player := _controlled_player()
	if player == null:
		lines.append("Player    waiting for spawn")
	else:
		var body := player as Node3D
		var position := body.global_position
		lines.append("Position  %.2f, %.2f, %.2f" % [position.x, position.y, position.z])
		if player.has_method("get_aim_point") and player.has_method("wants_local_camera") and bool(player.call("wants_local_camera")):
			var aim: Vector3 = player.call("get_aim_point")
			lines.append("Aim       %.2f, %.2f, %.2f" % [aim.x, aim.y, aim.z])
		if player.has_method("get_lean_offset"):
			lines.append("Lean      %.2f m" % float(player.call("get_lean_offset")))
		if player.has_method("get_crouch"):
			var stance := "crouched" if float(player.call("get_crouch")) > 0.5 else "standing"
			lines.append("Stance    %s" % stance)
		if player.get("correction_count") != null:
			lines.append("Corrections %s" % str(player.get("correction_count")))
		if player.get("health") != null and networked:
			lines.append("Your HP   %s" % str(player.get("health")))
		var weapon := body.get_node_or_null("HitscanWeapon")
		if weapon != null and weapon.has_method("is_ready"):
			var ready: bool = weapon.call("is_ready")
			if networked:
				lines.append("Weapon    %s (server validates)" % ("request cooling" if not ready else "request ready"))
			else:
				lines.append("Weapon    %s" % ("ready" if ready else "cooling down"))
			lines.append("Last shot %s" % str(weapon.get("last_feedback")))
	if networked:
		var net := _net()
		lines.append("Shot event %s" % str(net.get("last_shot_text")))
		for node in _arena_nodes_in_group(&"player"):
			if node == null or not is_instance_valid(node):
				continue
			var who := "remote"
			if node.has_method("is_controlled_locally") and bool(node.call("is_controlled_locally")):
				who = "you"
			lines.append("P%s %s  %s HP" % [str(node.get("network_id")), who, str(node.get("health"))])
	for node in _arena_nodes_in_group(&"damageable"):
		lines.append("%s  %d/%d HP" % [str(node.get("display_name")), int(node.get("health")), int(node.get("max_health"))])
	for system in _arena_nodes_in_group(&"building_system"):
		for row in _weight_rows(system as BuildingSystem):
			lines.append(row)
	_label.text = "\n".join(lines)


func _unhandled_input(event: InputEvent) -> void:
	if has_meta(&"suppress_ready"):
		return
	if not event.is_action_pressed(&"debug_toggle"):
		return
	visible = not visible
	get_viewport().set_input_as_handled()


func _controlled_player() -> Node:
	var players := _arena_nodes_in_group(&"player")
	for node in players:
		if node.has_method("is_controlled_locally") and bool(node.call("is_controlled_locally")):
			return node
	if players.is_empty():
		return null
	return players[0]


func _arena_nodes_in_group(group_name: StringName) -> Array:
	var arena := get_parent()
	var found: Array = []
	if arena == null:
		return found
	for node in get_tree().get_nodes_in_group(group_name):
		if is_instance_valid(node) and (node == arena or arena.is_ancestor_of(node)):
			found.append(node)
	return found


func _weight_rows(system: BuildingSystem) -> PackedStringArray:
	var rows := PackedStringArray()
	if system == null or system.state == null:
		return rows
	var key := "%d:%d" % [system.get_instance_id(), system.state.revision]
	if key != _weight_key:
		_weight_key = key
		_weight_cache = _weight_snapshot(system)
	for row in _weight_cache:
		rows.append(row)
	var waiting := system.authority.collapse_waiting() if system.authority != null else 0
	if waiting > 0:
		rows.append("Collapse  %d waiting" % waiting)
	return rows


func _weight_snapshot(system: BuildingSystem) -> PackedStringArray:
	var rows := PackedStringArray()
	var ids: Array[int] = []
	var upper := 0
	for component: BuildComponent in system.state.components.values():
		ids.append(component.id)
		if component.kind == BuildTypes.Kind.SLAB and component.level > 0:
			upper += 1
	var bearing := system.config.wall_bearing
	if upper == 0:
		rows.append("Weight    no upper floors")
	else:
		rows.append("Weight    %d upper tiles   bearing %.0f" % [upper, bearing])
	var loads := StructuralSolver.loads(system.state, ids, system.config)
	var carriers: Array[Dictionary] = []
	for component: BuildComponent in system.state.components.values():
		if component.kind != BuildTypes.Kind.WALL and component.kind != BuildTypes.Kind.DOORWAY:
			continue
		var amount := float(loads.get(component.id, 0.0))
		if amount <= 0.001:
			continue
		carriers.append({"id": component.id, "level": component.level, "kind": component.kind, "load": amount})
	carriers.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if not is_equal_approx(float(a["load"]), float(b["load"])):
			return float(a["load"]) > float(b["load"])
		return int(a["id"]) < int(b["id"])
	)
	var shown := 0
	for entry in carriers:
		if shown >= 12:
			break
		var amount := float(entry["load"])
		var mark := "  OVER" if amount > bearing + 0.001 else ""
		rows.append("%s L%d #%d  %.2f/%.0f%s" % [BuildTypes.kind_name(int(entry["kind"])), int(entry["level"]), int(entry["id"]), amount, bearing, mark])
		shown += 1
	if carriers.size() > shown:
		rows.append("          + %d more" % (carriers.size() - shown))
	return rows


func _net() -> Node:
	var parent := get_parent()
	if parent == null:
		return null
	return parent.get_node_or_null("GameNet")
