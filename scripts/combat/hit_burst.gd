extends RefCounted
class_name HitBurst

## Short chip burst at a harvest contact. Presentation only.


static func color_for(kind: String) -> Color:
	match kind:
		"shovel":
			return Color(0.50, 0.36, 0.20)
		"hatchet":
			return Color(0.62, 0.40, 0.20)
		"crowbar":
			return Color(0.84, 0.86, 0.90)
		_:
			return Color(0.66, 0.64, 0.60)


static func spawn(parent: Node, point: Vector3, normal: Vector3, tint: Color) -> void:
	if parent == null:
		return
	var direction := normal
	if direction.length_squared() < 0.0001:
		direction = Vector3.UP
	direction = direction.normalized()

	var particles := CPUParticles3D.new()
	particles.name = "HitBurst"
	particles.top_level = true
	particles.one_shot = true
	particles.explosiveness = 0.96
	particles.amount = 30
	particles.lifetime = 0.5
	particles.randomness = 0.35
	particles.direction = direction
	particles.spread = 48.0
	particles.initial_velocity_min = 1.8
	particles.initial_velocity_max = 3.8
	particles.gravity = Vector3(0.0, -8.5, 0.0)
	particles.damping_min = 1.2
	particles.damping_max = 2.4
	particles.scale_amount_min = 0.35
	particles.scale_amount_max = 0.9
	particles.angular_velocity_min = -8.0
	particles.angular_velocity_max = 8.0
	particles.color = tint
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var chip := BoxMesh.new()
	chip.size = Vector3(0.055, 0.04, 0.03)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = tint
	chip.material = material
	particles.mesh = chip
	parent.add_child(particles)
	particles.global_position = point + direction * 0.32
	particles.emitting = true
	var timer := parent.get_tree().create_timer(0.85)
	timer.timeout.connect(particles.queue_free)
