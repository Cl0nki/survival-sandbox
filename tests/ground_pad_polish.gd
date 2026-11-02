extends SceneTree

## Headless check: pads use published PBR materials, quieter UVs, and scatter.


func _init() -> void:
	var pad_root := Node3D.new()
	pad_root.name = "PadRoot"
	root.add_child(pad_root)
	ShowcasePad.add_rect(pad_root, ShowcasePad.BUILDING, ShowcasePad.BUILDING_SIZE, Color(0.3, 0.42, 0.22), "ground_meadow")
	ShowcasePad.add(pad_root, ShowcasePad.FOOD, Color(0.42, 0.36, 0.24), "ground_dirt")
	ShowcasePad.add(pad_root, ShowcasePad.BENCHES, Color(0.48, 0.46, 0.44), "ground_rock")
	var meshes: Array[MeshInstance3D] = []
	var scatters := 0
	var instances := 0
	for child in pad_root.get_children():
		if child is MeshInstance3D:
			meshes.append(child)
		elif child is MultiMeshInstance3D:
			scatters += 1
			instances += child.multimesh.visible_instance_count
	assert(meshes.size() == 3, "expected three pad meshes")
	var meadow: StandardMaterial3D = meshes[0].get_surface_override_material(0)
	assert(meadow != null and meadow.albedo_texture != null, "meadow albedo missing")
	assert(meadow.normal_enabled and meadow.normal_texture != null, "meadow normal missing")
	assert(meadow.ao_enabled and meadow.ao_texture != null, "meadow ao missing")
	assert(is_equal_approx(meadow.uv1_scale.x, ShowcasePad.BUILDING_SIZE / ShowcasePad.METERS_PER_TILE), "meadow uv wrong")
	var dirt: StandardMaterial3D = meshes[1].get_surface_override_material(0)
	assert(dirt.normal_enabled and dirt.normal_texture != null, "dirt normal missing")
	assert(is_equal_approx(dirt.uv1_scale.x, ShowcasePad.SIZE / ShowcasePad.METERS_PER_TILE), "dirt uv wrong")
	assert(scatters >= 4, "expected grass/pebble MultiMeshes on meadow and dirt")
	assert(instances >= 80, "scatter density too low: %s" % instances)
	print("GROUND_PAD_POLISH_OK meshes=%s scatters=%s instances=%s" % [meshes.size(), scatters, instances])
	quit(0)
