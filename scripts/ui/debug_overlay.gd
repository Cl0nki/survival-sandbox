extends CanvasLayer

@onready var _label: Label = $Panel/Label


func _process(_delta: float) -> void:
	var lines := PackedStringArray()
	lines.append("Survival Sandbox  |  Milestone 1 local prototype")
	lines.append("FPS %d" % Engine.get_frames_per_second())
	var player := get_tree().get_first_node_in_group(&"player")
	if player == null:
		lines.append("Player missing")
	else:
		var body := player as Node3D
		var position := body.global_position
		lines.append("Position  %.2f, %.2f, %.2f" % [position.x, position.y, position.z])
		if player.has_method("get_aim_point"):
			var aim: Vector3 = player.call("get_aim_point")
			lines.append("Aim       %.2f, %.2f, %.2f" % [aim.x, aim.y, aim.z])
		if player.has_method("get_lean_offset"):
			lines.append("Lean      %.2f m" % float(player.call("get_lean_offset")))
		var weapon := body.get_node_or_null("HitscanWeapon")
		if weapon != null and weapon.has_method("is_ready"):
			var ready: bool = weapon.call("is_ready")
			lines.append("Weapon    %s" % ("ready" if ready else "cooling down"))
			lines.append("Last shot %s" % str(weapon.get("last_feedback")))
	for node in get_tree().get_nodes_in_group(&"damageable"):
		lines.append("%s  %d/%d HP" % [str(node.get("display_name")), int(node.get("health")), int(node.get("max_health"))])
	lines.append("WASD move   mouse aim   LMB fire   wheel zoom")
	lines.append("Z/C or middle-mouse orbit   Q/E lean   Esc quit")
	_label.text = "\n".join(lines)
