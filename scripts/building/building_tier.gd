extends RefCounted
class_name BuildingTier

## Six construction tiers. Health comes from the tier; damage factors still
## come from the piece kind. New pieces start at Scrap unless the Build Tool
## asked for a higher tier.

const MIN := 1
const MAX := 6

const NAMES := {
	1: "Scrap",
	2: "Wood",
	3: "Brick",
	4: "Stone",
	5: "Concrete",
	6: "Composite",
}

const ROMAN := {
	1: "I",
	2: "II",
	3: "III",
	4: "IV",
	5: "V",
	6: "VI",
}

const HEALTH := {
	1: 200,
	2: 400,
	3: 800,
	4: 1600,
	5: 3600,
	6: 8000,
}


static func clamp_tier(tier: int) -> int:
	return clampi(tier, MIN, MAX)


static func health_of(tier: int) -> int:
	return int(HEALTH.get(clamp_tier(tier), 200))


static func display_name(tier: int) -> String:
	return str(NAMES.get(clamp_tier(tier), "Scrap"))


static func label(tier: int) -> String:
	var id := clamp_tier(tier)
	return "%s %s" % [ROMAN[id], NAMES[id]]


static func next_of(tier: int) -> int:
	return mini(clamp_tier(tier) + 1, MAX)


static func color_of(tier: int) -> Color:
	return color_for(tier, BuildTypes.Kind.WALL)


## Each tier keeps the old split: light faces, darker floors, darkest posts.
## Concrete is the pale mass from the reference building.
static func color_for(tier: int, kind: int) -> Color:
	var id := clamp_tier(tier)
	match kind:
		BuildTypes.Kind.POST:
			match id:
				2:
					return Color(0.36, 0.22, 0.10)
				3:
					return Color(0.40, 0.16, 0.12)
				4:
					return Color(0.40, 0.38, 0.34)
				5:
					return Color(0.58, 0.54, 0.48)
				6:
					return Color(0.12, 0.28, 0.32)
				_:
					return Color(0.36, 0.26, 0.18)
		BuildTypes.Kind.SLAB:
			match id:
				2:
					return Color(0.50, 0.36, 0.20)
				3:
					return Color(0.50, 0.26, 0.20)
				4:
					return Color(0.54, 0.52, 0.46)
				5:
					return Color(0.72, 0.68, 0.62)
				6:
					return Color(0.22, 0.40, 0.44)
				_:
					return Color(0.48, 0.38, 0.28)
		BuildTypes.Kind.STAIRS:
			match id:
				2:
					return Color(0.58, 0.40, 0.22)
				3:
					return Color(0.58, 0.30, 0.22)
				4:
					return Color(0.60, 0.58, 0.52)
				5:
					return Color(0.76, 0.72, 0.66)
				6:
					return Color(0.28, 0.46, 0.50)
				_:
					return Color(0.54, 0.42, 0.30)
		_:
			match id:
				2:
					return Color(0.78, 0.60, 0.38)
				3:
					return Color(0.74, 0.42, 0.32)
				4:
					return Color(0.76, 0.74, 0.68)
				5:
					return Color(0.84, 0.80, 0.74)
				6:
					return Color(0.46, 0.64, 0.68)
				_:
					return Color(0.72, 0.58, 0.44)


static func roughness_of(tier: int) -> float:
	match clamp_tier(tier):
		1:
			return 0.97
		2:
			return 0.92
		3:
			return 0.88
		4:
			return 0.78
		5:
			return 0.88
		_:
			return 0.28


static var _textures: Dictionary = {}


static func _piece_slug(kind: int) -> String:
	match kind:
		BuildTypes.Kind.SLAB:
			return "floor"
		BuildTypes.Kind.POST:
			return "post"
		BuildTypes.Kind.STAIRS:
			return "stairs"
		_:
			return "wall"


static func _tier_slug(tier: int) -> String:
	match clamp_tier(tier):
		2:
			return "wood"
		3:
			return "brick"
		4:
			return "stone"
		5:
			return "concrete"
		6:
			return "composite"
		_:
			return "scrap"


static func _load_texture(path: String) -> Texture2D:
	if _textures.has(path):
		return _textures[path]
	if not FileAccess.file_exists(path):
		return null
	var image := Image.new()
	if image.load(path) != OK:
		return null
	var texture := ImageTexture.create_from_image(image)
	_textures[path] = texture
	return texture


static func make_material(tier: int, kind: int = BuildTypes.Kind.WALL) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	style_material(material, tier, 1.0, kind)
	return material


static func style_material(material: StandardMaterial3D, tier: int, ratio: float, kind: int = BuildTypes.Kind.WALL) -> void:
	var color := color_for(tier, kind)
	if ratio < 0.999:
		color = color.lerp(Color(0.22, 0.1, 0.07), 1.0 - clampf(ratio, 0.0, 1.0))
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	var folder := "res://assets/textures/%s_%s" % [_piece_slug(kind), _tier_slug(tier)]
	var albedo := _load_texture("%s/albedo.png" % folder)
	if albedo == null:
		material.albedo_texture = null
		material.normal_enabled = false
		material.normal_texture = null
		material.roughness_texture = null
		material.ao_enabled = false
		material.ao_texture = null
		material.metallic_texture = null
		material.albedo_color = color
		material.roughness = roughness_of(tier)
		if kind == BuildTypes.Kind.POST:
			material.roughness = minf(material.roughness + 0.06, 1.0)
		material.metallic = 0.45 if clamp_tier(tier) == MAX and kind != BuildTypes.Kind.SLAB else 0.0
		if clamp_tier(tier) == MAX and kind == BuildTypes.Kind.POST:
			material.metallic = 0.28
		return
	var tint := Color.WHITE
	if ratio < 0.999:
		tint = Color.WHITE.lerp(Color(0.22, 0.1, 0.07), 1.0 - clampf(ratio, 0.0, 1.0))
	material.albedo_texture = albedo
	material.albedo_color = tint
	var normal := _load_texture("%s/normal.png" % folder)
	material.normal_enabled = normal != null
	material.normal_texture = normal
	var rough := _load_texture("%s/roughness.png" % folder)
	material.roughness_texture = rough
	material.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	material.roughness = 1.0 if rough != null else roughness_of(tier)
	var ao := _load_texture("%s/ao.png" % folder)
	material.ao_enabled = ao != null
	material.ao_texture = ao
	material.ao_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	var metal := _load_texture("%s/metallic.png" % folder)
	material.metallic_texture = metal
	material.metallic_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	material.metallic = 1.0 if metal != null else 0.0
