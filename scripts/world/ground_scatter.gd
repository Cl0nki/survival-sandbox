extends RefCounted

## Cheap visual clutter on showcase pads. Texture carries the carpet;
## these MultiMeshes fake the volume in the concept shot.


static func add(
	root: Node3D,
	center: Vector3,
	size: float,
	texture_id: String,
	y_lift := 0.0,
	profile_override: Dictionary = {},
	extent: Vector2 = Vector2.ZERO
) -> void:
	var profile := profile_override if not profile_override.is_empty() else _profile(texture_id)
	if profile.is_empty():
		return
	var rng_seed := _seed_for(center, texture_id if texture_id != "" else "biome")
	var half_x := size * 0.5 - 0.35
	var half_z := half_x
	var area := size * size
	if extent.x > 1.0 and extent.y > 1.0:
		half_x = extent.x * 0.5 - 0.35
		half_z = extent.y * 0.5 - 0.35
		area = extent.x * extent.y
	## Matches ShowcasePad.pad_top() + a hair so props sit on the pad surface.
	var y := 0.0325 + 0.01 + y_lift
	if half_x <= 0.2 or half_z <= 0.2:
		return
	var tuft_count := int(round(area * float(profile.get("tufts", 0.0))))
	var fern_count := int(round(area * float(profile.get("ferns", 0.0))))
	var pebble_count := int(round(area * float(profile.get("pebbles", 0.0))))
	if tuft_count > 0:
		_add_multimesh(root, _tuft_mesh(), tuft_count, center, half_x, half_z, y, rng_seed, 0.55, 1.15, 0.02)
	if fern_count > 0:
		_add_multimesh(root, _fern_mesh(), fern_count, center, half_x, half_z, y, rng_seed + 409, 0.7, 1.25, 0.01)
	if pebble_count > 0:
		_add_multimesh(root, _pebble_mesh(), pebble_count, center, half_x, half_z, y, rng_seed + 917, 0.7, 1.35, 0.0)


static func _profile(texture_id: String) -> Dictionary:
	match texture_id:
		"ground_meadow", "ground_grass":
			return {"tufts": 0.45, "ferns": 0.12, "pebbles": 0.18}
		"ground_forest_oak":
			return {"tufts": 0.22, "ferns": 0.42, "pebbles": 0.16}
		"ground_forest_birch":
			return {"tufts": 0.34, "ferns": 0.30, "pebbles": 0.12}
		"ground_forest_spruce":
			return {"tufts": 0.12, "ferns": 0.48, "pebbles": 0.18}
		"ground_dirt", "ground_sand", "ground_clay":
			return {"tufts": 0.08, "ferns": 0.0, "pebbles": 0.28}
		"ground_rock", "ground_gravel":
			return {"tufts": 0.0, "ferns": 0.0, "pebbles": 0.08}
		"ground_asphalt":
			return {}
		_:
			return {}


static func _add_multimesh(
	root: Node3D,
	mesh: Mesh,
	count: int,
	center: Vector3,
	half_x: float,
	half_z: float,
	y: float,
	rng_seed: int,
	scale_min: float,
	scale_max: float,
	lift: float
) -> void:
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.mesh = mesh
	multi.instance_count = count
	multi.visible_instance_count = count
	for i in count:
		var px := _rand(rng_seed, i * 3)
		var pz := _rand(rng_seed, i * 3 + 1)
		var yaw := _rand(rng_seed, i * 3 + 2) * TAU
		var amount := lerpf(scale_min, scale_max, _rand(rng_seed, i * 3 + 17))
		var pos := Vector3(
			center.x + lerpf(-half_x, half_x, px),
			y + lift,
			center.z + lerpf(-half_z, half_z, pz)
		)
		var basis := Basis.from_euler(Vector3(0.0, yaw, 0.0)).scaled(Vector3(amount, amount, amount))
		multi.set_instance_transform(i, Transform3D(basis, pos))
	var view := MultiMeshInstance3D.new()
	view.multimesh = multi
	view.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(view)


static func _tuft_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var green := Color(0.34, 0.46, 0.22)
	var tip := Color(0.48, 0.58, 0.28)
	_blade(st, Vector3(0.0, 0.0, 0.0), 0.0, 0.22, green, tip)
	_blade(st, Vector3(0.03, 0.0, 0.02), 0.45, 0.18, green, tip)
	_blade(st, Vector3(-0.03, 0.0, 0.01), -0.4, 0.16, green, tip)
	st.generate_normals()
	var mesh := st.commit()
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.roughness = 0.95
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh.surface_set_material(0, material)
	return mesh


static func _blade(st: SurfaceTool, at: Vector3, yaw: float, height: float, base: Color, tip: Color) -> void:
	var right := Vector3(cos(yaw), 0.0, sin(yaw)) * 0.035
	var top := at + Vector3(0.0, height, 0.0) + right * 0.15
	st.set_color(base)
	st.add_vertex(at - right)
	st.add_vertex(at + right)
	st.set_color(tip)
	st.add_vertex(top)


static func _fern_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var base := Color(0.24, 0.42, 0.20)
	var tip := Color(0.40, 0.58, 0.28)
	_frond(st, 0.0, 0.28, base, tip)
	_frond(st, 0.7, 0.24, base, tip)
	_frond(st, -0.65, 0.22, base, tip)
	st.generate_normals()
	var mesh := st.commit()
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.roughness = 0.94
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh.surface_set_material(0, material)
	return mesh


static func _frond(st: SurfaceTool, yaw: float, length: float, base: Color, tip: Color) -> void:
	var forward := Vector3(sin(yaw), 0.0, cos(yaw))
	var right := Vector3(cos(yaw), 0.0, -sin(yaw)) * 0.05
	var mid := forward * (length * 0.45) + Vector3(0.0, length * 0.35, 0.0)
	var end := forward * length + Vector3(0.0, length * 0.55, 0.0)
	st.set_color(base)
	st.add_vertex(Vector3.ZERO)
	st.add_vertex(mid - right)
	st.set_color(tip)
	st.add_vertex(end)
	st.set_color(base)
	st.add_vertex(Vector3.ZERO)
	st.set_color(tip)
	st.add_vertex(end)
	st.set_color(base)
	st.add_vertex(mid + right)


static func _pebble_mesh() -> Mesh:
	var box := BoxMesh.new()
	box.size = Vector3(0.12, 0.05, 0.09)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.55, 0.52, 0.48)
	material.roughness = 1.0
	box.material = material
	return box


static func _seed_for(center: Vector3, texture_id: String) -> int:
	return int(center.x * 17.0 + center.z * 31.0) * 131 + texture_id.hash()


static func _rand(rng_seed: int, index: int) -> float:
	var n := rng_seed * 1664525 + index * 1013904223
	n = (n ^ (n >> 13)) * 1274126177
	return float(n & 0x7fffffff) / float(0x7fffffff)
