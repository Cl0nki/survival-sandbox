extends SceneTree

## Headless check: splat ground covers the yard; pads can skip meshes and keep scatter.

const _GroundSplat := preload("res://scripts/world/ground_splat.gd")


func _init() -> void:
	var pad_root := Node3D.new()
	pad_root.name = "PadRoot"
	root.add_child(pad_root)
	var splat := _GroundSplat.build(pad_root)
	assert(splat != null and splat.name == "GroundSplat", "splat mesh missing")
	var splat_mat := splat.get_surface_override_material(0) as ShaderMaterial
	assert(splat_mat != null and splat_mat.shader != null, "splat shader material missing")
	var splat_tex: Variant = splat_mat.get_shader_parameter("splat_map")
	assert(splat_tex is Texture2D, "splat_map texture missing")
	var stain_tex: Variant = splat_mat.get_shader_parameter("stain_map")
	assert(stain_tex is Texture2D, "stain_map texture missing")
	var soil_tex: Variant = splat_mat.get_shader_parameter("soil_map")
	assert(soil_tex is Texture2D, "soil_map texture missing")
	var detail: Variant = splat_mat.get_shader_parameter("detail_meters")
	assert(is_equal_approx(float(detail), ShowcasePad.METERS_PER_TILE), "detail_meters wrong")
	var sharpness: Variant = splat_mat.get_shader_parameter("blend_sharpness")
	assert(float(sharpness) > 0.0, "blend_sharpness missing")
	for suffix in ["r", "g", "b", "a"]:
		assert(splat_mat.get_shader_parameter("albedo_%s" % suffix) is Texture2D, "albedo_%s missing" % suffix)
		assert(splat_mat.get_shader_parameter("height_%s" % suffix) is Texture2D, "height_%s missing" % suffix)
	for suffix in ["water", "gas", "oil", "sand", "clay", "gravel"]:
		assert(splat_mat.get_shader_parameter("albedo_%s" % suffix) is Texture2D, "albedo_%s missing" % suffix)
		assert(splat_mat.get_shader_parameter("height_%s" % suffix) is Texture2D, "height_%s missing" % suffix)

	var image := _GroundSplat.rasterize_splat()
	assert(image.get_width() == _GroundSplat.SPLAT_RES, "splat resolution wrong")
	## Building center should be meadow-heavy (green channel).
	var mid := _GroundSplat.SPLAT_RES / 2
	var center := image.get_pixel(mid, mid)
	assert(center.g > center.r and center.g > center.b and center.g > center.a, "building not meadow")
	## Woods NW corner cell center ≈ (-15,-15) → grass alpha.
	var woods := _sample_world(image, -15.0, -15.0)
	assert(woods.a > woods.r and woods.a > woods.g and woods.a > woods.b, "woods not grass")
	## Mine north cell ≈ (-5,-15) → rock blue.
	var mine := _sample_world(image, -5.0, -15.0)
	assert(mine.b > mine.r and mine.b > mine.g and mine.b > mine.a, "mine not rock")

	## Sharp asphalt (no blur/feather): city pads covered, top row + building clear.
	var asphalt := _GroundSplat.rasterize_asphalt(_GroundSplat.YARD_SIZE, _GroundSplat.SPLAT_RES, _GroundSplat.ASPHALT_REGIONS, 0.0, 1, 0.0)
	assert(_sample_world(asphalt, -15.0, -5.0).r > 0.95, "scavenge missing asphalt")
	assert(_sample_world(asphalt, 15.0, 15.0).r > 0.95, "chem missing asphalt")
	## Just inside a city pad edge should still be solid (sharp, not feathered).
	assert(_sample_world(asphalt, -15.0, -9.5).r > 0.95, "asphalt edge should be sharp")
	assert(_sample_world(asphalt, 0.0, 0.0).r < 0.05, "building should not be asphalt")
	assert(_sample_world(asphalt, -15.0, -15.0).r < 0.05, "woods should not be asphalt")
	assert(_sample_world(asphalt, 15.0, -15.0).r < 0.05, "ground pad should not be asphalt")

	var soil := _GroundSplat.rasterize_soil()
	var sand := _sample_world(soil, 12.0, -18.0)
	assert(sand.r > 0.55 and sand.r > sand.g and sand.r > sand.b, "sand soil missing")
	var clay := _sample_world(soil, 14.0, -18.0)
	assert(clay.g > 0.55 and clay.g > clay.r and clay.g > clay.b, "clay soil missing")
	var gravel := _sample_world(soil, 16.0, -18.0)
	assert(gravel.b > 0.55 and gravel.b > gravel.r and gravel.b > gravel.g, "gravel soil missing")

	var stain := _GroundSplat.rasterize_stain()
	var water := _sample_world(stain, 17.5, -18.5)
	assert(water.r > 0.55 and water.r > water.g and water.r > water.b, "water stain missing")
	var gas := _sample_world(stain, 12.5, -15.5)
	assert(gas.g > 0.55 and gas.g > gas.r and gas.g > gas.b, "gas stain missing")
	var oil := _sample_world(stain, 17.0, -16.0)
	assert(oil.b > 0.55 and oil.b > oil.r and oil.b > oil.g, "oil stain missing")
	for deposit_id in ["sand", "clay", "gravel", "ground_water", "natural_gas", "crude_oil"]:
		assert(_GroundSplat.uses_stain_splat(deposit_id), "%s should use splat overlay" % deposit_id)

	ShowcasePad.add_rect(
		pad_root, ShowcasePad.BUILDING, ShowcasePad.BUILDING_SIZE, Color(0.3, 0.42, 0.22), "ground_meadow", true, 0.0, false
	)
	ShowcasePad.add(pad_root, ShowcasePad.FOOD, Color(0.42, 0.36, 0.24), "ground_dirt", true, false)
	ShowcasePad.add(pad_root, ShowcasePad.BENCHES, Color(0.48, 0.46, 0.44), "ground_rock", true, false)
	var meshes: Array[MeshInstance3D] = []
	var scatters := 0
	var instances := 0
	for child in pad_root.get_children():
		if child is MeshInstance3D:
			meshes.append(child)
		elif child is MultiMeshInstance3D:
			scatters += 1
			instances += child.multimesh.visible_instance_count
	assert(meshes.size() == 1, "expected only the splat mesh, got %s" % meshes.size())
	assert(scatters >= 4, "expected grass/pebble MultiMeshes on meadow and dirt")
	assert(instances >= 80, "scatter density too low: %s" % instances)
	print(
		"GROUND_PAD_POLISH_OK meshes=%s scatters=%s instances=%s splat=%sx%s"
		% [meshes.size(), scatters, instances, image.get_width(), image.get_height()]
	)
	quit(0)


func _sample_world(image: Image, x: float, z: float) -> Color:
	var res := float(image.get_width())
	var half := _GroundSplat.YARD_SIZE * 0.5
	var px := int(clamp((x + half) / _GroundSplat.YARD_SIZE * res, 0.0, res - 1.0))
	var pz := int(clamp((z + half) / _GroundSplat.YARD_SIZE * res, 0.0, res - 1.0))
	return image.get_pixel(px, pz)
