extends RefCounted
class_name GroundSplat

## One yard-sized plane with an RGBA splatmap plus soft deposit overlays.
## Base: R dirt, G meadow, B rock, A grass.
## Soil: R sand, G clay, B gravel.
## Stain: R water, G gas, B oil.

const _SHADER := preload("res://shaders/ground_splat.gdshader")

const LAYER_DIRT := 0
const LAYER_MEADOW := 1
const LAYER_ROCK := 2
const LAYER_GRASS := 3

const SOIL_SAND := 0
const SOIL_CLAY := 1
const SOIL_GRAVEL := 2

const STAIN_WATER := 0
const STAIN_GAS := 1
const STAIN_OIL := 2

const FOREST_OAK := 0
const FOREST_BIRCH := 1
const FOREST_SPRUCE := 2

const YARD_SIZE := 40.0
const SURVIVAL_SIZE := 80.0
const SPLAT_RES := 256
const SURVIVAL_SPLAT_RES := 384
## Soft falloff across pad seams, in meters.
const BLUR_METERS := 1.25
## Tight survival seams — biomes abut; no mushy “between” zones.
const SURVIVAL_BLUR_METERS := 1.25
const SURVIVAL_BLUR_PASSES := 1
const SURVIVAL_FEATHER_METERS := 1.0
## Tighter falloff so deposit patches stay readable on dirt.
const STAIN_BLUR_METERS := 0.7
const BLEND_SHARPNESS := 8.0
## Keep survival biome carpets distinct.
const SURVIVAL_BLEND_SHARPNESS := 6.0

## Deposit ids whose ground look lives in soil/stain splats (no overlay mesh).
const STAIN_DEPOSIT_IDS := {
	"sand": true,
	"clay": true,
	"gravel": true,
	"ground_water": true,
	"natural_gas": true,
	"crude_oil": true,
}

## Debug showcase: [center, size, layer]
## Top row + building keep their own looks; the rest is city (meadow under asphalt).
const REGIONS := [
	[ShowcasePad.WOODS, ShowcasePad.SIZE, LAYER_GRASS],
	[ShowcasePad.MINE, ShowcasePad.SIZE, LAYER_ROCK],
	[ShowcasePad.SMELTING, ShowcasePad.SIZE, LAYER_ROCK],
	[ShowcasePad.GROUND, ShowcasePad.SIZE, LAYER_DIRT],
	[ShowcasePad.SCAVENGE, ShowcasePad.SIZE, LAYER_MEADOW],
	[ShowcasePad.RANGE, ShowcasePad.SIZE, LAYER_MEADOW],
	[ShowcasePad.BUILDING, ShowcasePad.BUILDING_SIZE, LAYER_MEADOW],
	[ShowcasePad.CRAFTING, ShowcasePad.SIZE, LAYER_MEADOW],
	[ShowcasePad.FOOD, ShowcasePad.SIZE, LAYER_MEADOW],
	[ShowcasePad.DEPLOYABLES, ShowcasePad.SIZE, LAYER_MEADOW],
	[ShowcasePad.SUPPLIES, ShowcasePad.SIZE, LAYER_MEADOW],
	[ShowcasePad.BENCHES, ShowcasePad.SIZE, LAYER_MEADOW],
	[ShowcasePad.CHEM, ShowcasePad.SIZE, LAYER_MEADOW],
]

const SOIL_REGIONS := [
	[Vector3(12.0, 0.0, -18.0), 2.0, SOIL_SAND],
	[Vector3(14.0, 0.0, -18.0), 2.0, SOIL_CLAY],
	[Vector3(16.0, 0.0, -18.0), 2.0, SOIL_GRAVEL],
]

const STAIN_REGIONS := [
	[Vector3(17.5, 0.0, -18.5), 1.0, STAIN_WATER],
	[Vector3(12.5, 0.0, -15.5), 3.0, STAIN_GAS],
	[Vector3(17.0, 0.0, -16.0), 2.0, STAIN_OIL],
]

## City biome asphalt on the debug map (skip top station row + building): [center, size]
const ASPHALT_REGIONS := [
	[ShowcasePad.SCAVENGE, ShowcasePad.SIZE],
	[ShowcasePad.RANGE, ShowcasePad.SIZE],
	[ShowcasePad.CRAFTING, ShowcasePad.SIZE],
	[ShowcasePad.FOOD, ShowcasePad.SIZE],
	[ShowcasePad.DEPLOYABLES, ShowcasePad.SIZE],
	[ShowcasePad.SUPPLIES, ShowcasePad.SIZE],
	[ShowcasePad.BENCHES, ShowcasePad.SIZE],
	[ShowcasePad.CHEM, ShowcasePad.SIZE],
]

## Survival splat regions come from BiomePlacer / SurvivalField (no hard-coded twin).

const _LAYER_IDS := ["ground_dirt", "ground_meadow", "ground_rock", "ground_grass"]
const _LAYER_SUFFIX := ["r", "g", "b", "a"]
const _SOIL_IDS := ["ground_sand", "ground_clay", "ground_gravel"]
const _SOIL_SUFFIX := ["sand", "clay", "gravel"]
const _STAIN_IDS := ["ground_water", "ground_gas", "ground_oil"]
const _STAIN_SUFFIX := ["water", "gas", "oil"]
const _FOREST_IDS := ["ground_forest_oak", "ground_forest_birch", "ground_forest_spruce"]
const _FOREST_SUFFIX := ["oak", "birch", "spruce"]
const _ASPHALT_ID := "ground_asphalt"


static func uses_stain_splat(definition_id: String) -> bool:
	return STAIN_DEPOSIT_IDS.has(definition_id)


static func build(root: Node3D) -> MeshInstance3D:
	return _build(
		root,
		YARD_SIZE,
		SPLAT_RES,
		REGIONS,
		SOIL_REGIONS,
		STAIN_REGIONS,
		ASPHALT_REGIONS,
		[],
		BLUR_METERS,
		1,
		0.0,
		BLEND_SHARPNESS
	)


static func build_survival(
	root: Node3D,
	regions: Array = [],
	soil_regions: Array = [],
	stain_regions: Array = [],
	asphalt_regions: Array = [],
	forest_regions: Array = []
) -> MeshInstance3D:
	return _build(
		root,
		SURVIVAL_SIZE,
		SURVIVAL_SPLAT_RES,
		regions,
		soil_regions,
		stain_regions,
		asphalt_regions,
		forest_regions,
		SURVIVAL_BLUR_METERS,
		SURVIVAL_BLUR_PASSES,
		SURVIVAL_FEATHER_METERS,
		SURVIVAL_BLEND_SHARPNESS
	)


static func _build(
	root: Node3D,
	yard_size: float,
	res: int,
	regions: Array,
	soil_regions: Array,
	stain_regions: Array,
	asphalt_regions: Array,
	forest_regions: Array,
	blur_meters: float,
	blur_passes: int,
	feather_meters: float,
	blend_sharpness: float
) -> MeshInstance3D:
	if root.get_node_or_null("GroundSplat") != null:
		return root.get_node("GroundSplat") as MeshInstance3D
	# Footsteps read the same rectangles the shader paints.
	GroundSurface.register(
		regions,
		soil_regions,
		asphalt_regions,
		forest_regions,
		GroundSurface.GRASS if yard_size > YARD_SIZE + 0.1 else GroundSurface.DIRT
	)
	var mesh := MeshInstance3D.new()
	mesh.name = "GroundSplat"
	var plane := PlaneMesh.new()
	plane.size = Vector2(yard_size, yard_size)
	mesh.mesh = plane
	mesh.position = Vector3(0.0, ShowcasePad.PAD_CENTER_Y, 0.0)
	mesh.set_surface_override_material(
		0,
		make_material(
			yard_size,
			res,
			regions,
			soil_regions,
			stain_regions,
			asphalt_regions,
			forest_regions,
			blur_meters,
			blur_passes,
			feather_meters,
			blend_sharpness
		)
	)
	root.add_child(mesh)
	return mesh


static func make_material(
	yard_size := YARD_SIZE,
	res := SPLAT_RES,
	regions: Array = REGIONS,
	soil_regions: Array = SOIL_REGIONS,
	stain_regions: Array = STAIN_REGIONS,
	asphalt_regions: Array = ASPHALT_REGIONS,
	forest_regions: Array = [],
	blur_meters := BLUR_METERS,
	blur_passes := 1,
	feather_meters := 0.0,
	blend_sharpness := BLEND_SHARPNESS
) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = _SHADER
	material.set_shader_parameter(
		"splat_map",
		ImageTexture.create_from_image(
			rasterize_splat(yard_size, res, regions, blur_meters, blur_passes, feather_meters)
		)
	)
	material.set_shader_parameter("soil_map", ImageTexture.create_from_image(rasterize_soil(yard_size, res, soil_regions)))
	material.set_shader_parameter("stain_map", ImageTexture.create_from_image(rasterize_stain(yard_size, res, stain_regions)))
	material.set_shader_parameter("forest_map", ImageTexture.create_from_image(rasterize_forest(yard_size, res, forest_regions)))
	## Asphalt always hard-edged; biome carpets stay soft.
	material.set_shader_parameter(
		"asphalt_map",
		ImageTexture.create_from_image(rasterize_asphalt(yard_size, res, asphalt_regions, 0.0, 1, 0.0))
	)
	material.set_shader_parameter("uv_world_size", Vector2(yard_size, yard_size))
	material.set_shader_parameter("world_origin", Vector3.ZERO)
	material.set_shader_parameter("detail_meters", ShowcasePad.METERS_PER_TILE)
	material.set_shader_parameter("blend_sharpness", blend_sharpness)
	for i in _LAYER_IDS.size():
		_bind_layer(material, _LAYER_SUFFIX[i], _LAYER_IDS[i])
	for i in _SOIL_IDS.size():
		_bind_layer(material, _SOIL_SUFFIX[i], _SOIL_IDS[i])
	for i in _STAIN_IDS.size():
		_bind_layer(material, _STAIN_SUFFIX[i], _STAIN_IDS[i])
	for i in _FOREST_IDS.size():
		_bind_layer(material, _FOREST_SUFFIX[i], _FOREST_IDS[i])
	_bind_layer(material, "asphalt", _ASPHALT_ID)
	return material


static func make_splat_texture() -> ImageTexture:
	return ImageTexture.create_from_image(rasterize_splat())


static func make_soil_texture() -> ImageTexture:
	return ImageTexture.create_from_image(rasterize_soil())


static func make_stain_texture() -> ImageTexture:
	return ImageTexture.create_from_image(rasterize_stain())


static func rasterize_splat(
	yard_size := YARD_SIZE,
	res := SPLAT_RES,
	regions: Array = REGIONS,
	blur_meters := BLUR_METERS,
	blur_passes := 1,
	feather_meters := 0.0
) -> Image:
	var weights := _empty_channels(4, res)
	for entry in regions:
		var center: Vector3 = entry[0]
		var extent := _region_extent(entry[1])
		var layer: int = int(entry[2])
		_fill_rect(weights[layer], res, yard_size, center.x, center.z, extent.x, extent.y, feather_meters)
	_blur_channels(weights, res, yard_size, blur_meters, blur_passes)
	var image := Image.create(res, res, false, Image.FORMAT_RGBA8)
	for y in res:
		for x in res:
			var i := y * res + x
			var r: float = weights[0][i]
			var g: float = weights[1][i]
			var b: float = weights[2][i]
			var a: float = weights[3][i]
			var total := r + g + b + a
			if total < 1e-5:
				## Uncovered rim: dirt on debug yard, meadow only as last resort on survival.
				if yard_size > YARD_SIZE + 0.1:
					g = 1.0
				else:
					r = 1.0
				total = 1.0
			image.set_pixel(x, y, Color(r / total, g / total, b / total, a / total))
	return image


static func rasterize_soil(
	yard_size := YARD_SIZE,
	res := SPLAT_RES,
	regions: Array = SOIL_REGIONS
) -> Image:
	return _rasterize_rgb_regions(yard_size, res, regions)


static func rasterize_stain(
	yard_size := YARD_SIZE,
	res := SPLAT_RES,
	regions: Array = STAIN_REGIONS
) -> Image:
	return _rasterize_rgb_regions(yard_size, res, regions)


static func rasterize_forest(
	yard_size := YARD_SIZE,
	res := SPLAT_RES,
	regions: Array = []
) -> Image:
	## Match biome rects tightly — forest floors stay inside their forest.
	return _rasterize_rgb_regions(yard_size, res, regions, 0.8)


static func rasterize_asphalt(
	yard_size := YARD_SIZE,
	res := SPLAT_RES,
	regions: Array = ASPHALT_REGIONS,
	blur_meters := 0.0,
	blur_passes := 1,
	feather_meters := 0.0
) -> Image:
	var weights := _empty_channels(1, res)
	for entry in regions:
		var center: Vector3 = entry[0]
		var extent := _region_extent(entry[1])
		_fill_rect(weights[0], res, yard_size, center.x, center.z, extent.x, extent.y, feather_meters)
	_blur_channels(weights, res, yard_size, blur_meters, blur_passes)
	var image := Image.create(res, res, false, Image.FORMAT_RGBA8)
	for y in res:
		for x in res:
			var cover := clampf(weights[0][y * res + x], 0.0, 1.0)
			image.set_pixel(x, y, Color(cover, cover, cover, 1.0))
	return image


static func _rasterize_rgb_regions(
	yard_size: float,
	res: int,
	regions: Array,
	blur_meters := STAIN_BLUR_METERS
) -> Image:
	var weights := _empty_channels(3, res)
	for entry in regions:
		var center: Vector3 = entry[0]
		var extent := _region_extent(entry[1])
		var channel: int = int(entry[2])
		_fill_rect(weights[channel], res, yard_size, center.x, center.z, extent.x, extent.y, 0.0)
	_blur_channels(weights, res, yard_size, blur_meters, 1)
	var image := Image.create(res, res, false, Image.FORMAT_RGBA8)
	for y in res:
		for x in res:
			var i := y * res + x
			var r: float = clampf(weights[0][i], 0.0, 1.0)
			var g: float = clampf(weights[1][i], 0.0, 1.0)
			var b: float = clampf(weights[2][i], 0.0, 1.0)
			image.set_pixel(x, y, Color(r, g, b, 1.0))
	return image


static func _region_extent(size_value) -> Vector2:
	if size_value is Vector2:
		return size_value
	if size_value is Vector2i:
		return Vector2(size_value.x, size_value.y)
	var side := float(size_value)
	return Vector2(side, side)


static func _empty_channels(count: int, res: int) -> Array:
	var weights: Array = []
	for _channel in count:
		var buf := PackedFloat32Array()
		buf.resize(res * res)
		buf.fill(0.0)
		weights.append(buf)
	return weights


static func _fill_rect(
	buf: PackedFloat32Array,
	res: int,
	yard_size: float,
	cx: float,
	cz: float,
	size_x: float,
	size_z: float = -1.0,
	feather_meters := 0.0
) -> void:
	## Backward compatible: old callers passed one square size.
	if size_z < 0.0:
		size_z = size_x
	var half_x := size_x * 0.5
	var half_z := size_z * 0.5
	var half_yard := yard_size * 0.5
	var feather := minf(maxf(feather_meters, 0.0), minf(half_x, half_z))
	var x0 := int(floor((cx - half_x + half_yard) / yard_size * float(res)))
	var x1 := int(ceil((cx + half_x + half_yard) / yard_size * float(res)))
	var z0 := int(floor((cz - half_z + half_yard) / yard_size * float(res)))
	var z1 := int(ceil((cz + half_z + half_yard) / yard_size * float(res)))
	x0 = clampi(x0, 0, res)
	x1 = clampi(x1, 0, res)
	z0 = clampi(z0, 0, res)
	z1 = clampi(z1, 0, res)
	var core_x := half_x - feather
	var core_z := half_z - feather
	for z in range(z0, z1):
		var row := z * res
		var wz := ((float(z) + 0.5) / float(res)) * yard_size - half_yard
		var dz := absf(wz - cz)
		var wz_w := 1.0
		if feather > 0.0 and dz > core_z:
			wz_w = 1.0 - clampf((dz - core_z) / feather, 0.0, 1.0)
		if wz_w <= 1e-5:
			continue
		for x in range(x0, x1):
			var wx := ((float(x) + 0.5) / float(res)) * yard_size - half_yard
			var dx := absf(wx - cx)
			var wx_w := 1.0
			if feather > 0.0 and dx > core_x:
				wx_w = 1.0 - clampf((dx - core_x) / feather, 0.0, 1.0)
			var w := wx_w * wz_w
			if w > 1e-5:
				buf[row + x] += w


static func _blur_channels(weights: Array, res: int, yard_size: float, meters: float, passes := 1) -> void:
	var total_radius := maxi(1, int(round(meters / yard_size * float(res))))
	var pass_count := maxi(1, passes)
	var pass_radius := maxi(1, int(round(float(total_radius) / float(pass_count))))
	for _pass in pass_count:
		for channel in weights.size():
			weights[channel] = _box_blur(weights[channel], res, pass_radius)


static func _box_blur(src: PackedFloat32Array, res: int, radius: int) -> PackedFloat32Array:
	var tmp := PackedFloat32Array()
	tmp.resize(res * res)
	var dst := PackedFloat32Array()
	dst.resize(res * res)
	var span := radius * 2 + 1
	for y in res:
		var row := y * res
		var running := 0.0
		for x in range(-radius, radius + 1):
			running += src[row + clampi(x, 0, res - 1)]
		for x in res:
			tmp[row + x] = running / float(span)
			var leave := x - radius
			var enter := x + radius + 1
			running -= src[row + clampi(leave, 0, res - 1)]
			running += src[row + clampi(enter, 0, res - 1)]
	for x in res:
		var running := 0.0
		for y in range(-radius, radius + 1):
			running += tmp[clampi(y, 0, res - 1) * res + x]
		for y in res:
			dst[y * res + x] = running / float(span)
			var leave := y - radius
			var enter := y + radius + 1
			running -= tmp[clampi(leave, 0, res - 1) * res + x]
			running += tmp[clampi(enter, 0, res - 1) * res + x]
	return dst


static func _bind_layer(material: ShaderMaterial, suffix: String, texture_id: String) -> void:
	material.set_shader_parameter("albedo_%s" % suffix, _tex("%s/albedo.png" % texture_id))
	material.set_shader_parameter("normal_%s" % suffix, _tex("%s/normal.png" % texture_id))
	material.set_shader_parameter("rough_%s" % suffix, _tex("%s/roughness.png" % texture_id))
	material.set_shader_parameter("ao_%s" % suffix, _tex("%s/ao.png" % texture_id))
	material.set_shader_parameter("height_%s" % suffix, _tex("%s/height.png" % texture_id))


static func _tex(rel: String) -> Texture2D:
	var path := "res://assets/textures/%s" % rel
	if ResourceLoader.exists(path):
		return load(path) as Texture2D
	if not FileAccess.file_exists(path):
		return null
	var image := Image.new()
	if image.load(path) != OK:
		return null
	return ImageTexture.create_from_image(image)
