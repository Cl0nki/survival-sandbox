extends RefCounted
class_name BiomeCatalog

## Built-in biomes for survival (and any future map). Look up by id.

const ORE_IDS: PackedStringArray = [
	"iron_ore",
	"copper_ore",
	"coal",
	"limestone",
	"sulfur",
	"bauxite",
	"lead_ore",
	"quartz",
]

static var _by_id: Dictionary = {}
static var _ready := false


static func get_biome(biome_id: String) -> BiomeDefinition:
	_ensure()
	var found: BiomeDefinition = _by_id.get(biome_id) as BiomeDefinition
	if found == null:
		return null
	return found.duplicate_definition()


static func known(biome_id: String) -> bool:
	_ensure()
	return _by_id.has(biome_id)


static func all_ids() -> PackedStringArray:
	_ensure()
	var ids := PackedStringArray()
	for key in _by_id.keys():
		ids.append(str(key))
	ids.sort()
	return ids


static func _ensure() -> void:
	if _ready:
		return
	_ready = true
	_add(_meadow())
	_add(_forest("forest_oak", "Oak Forest", "oak"))
	_add(_forest("forest_birch", "Birch Forest", "birch"))
	_add(_forest("forest_spruce", "Spruce Forest", "spruce"))
	_add(_wasteland())
	_add(_hills())
	_add(_city())


static func _add(biome: BiomeDefinition) -> void:
	_by_id[biome.id] = biome


static func _meadow() -> BiomeDefinition:
	var biome := BiomeDefinition.new()
	biome.id = "meadow"
	biome.display_name = "Meadow"
	biome.ground_layer = GroundSplat.LAYER_MEADOW
	biome.scatter_id = "ground_meadow"
	biome.fill = 0.46
	biome.scatter_profile = {"tufts": 0.62, "ferns": 0.05, "pebbles": 0.14}
	biome.harvestables = [
		{"id": "stone", "min": 8, "max": 12, "spacing": 2.6},
	]
	biome.deposits = [
		{"id": "ground_water", "min": 3, "max": 5, "spacing": 4.0, "size": Vector2i(1, 1)},
	]
	return biome


static func _forest(biome_id: String, title: String, tree_id: String) -> BiomeDefinition:
	var biome := BiomeDefinition.new()
	biome.id = biome_id
	biome.display_name = title
	biome.ground_layer = GroundSplat.LAYER_GRASS
	biome.fill = 0.48
	match tree_id:
		"oak":
			biome.forest_channel = GroundSplat.FOREST_OAK
			biome.scatter_id = "ground_forest_oak"
			biome.scatter_profile = {"tufts": 0.22, "ferns": 0.42, "pebbles": 0.16}
		"birch":
			biome.forest_channel = GroundSplat.FOREST_BIRCH
			biome.scatter_id = "ground_forest_birch"
			biome.scatter_profile = {"tufts": 0.34, "ferns": 0.30, "pebbles": 0.12}
		_:
			biome.forest_channel = GroundSplat.FOREST_SPRUCE
			biome.scatter_id = "ground_forest_spruce"
			biome.scatter_profile = {"tufts": 0.12, "ferns": 0.48, "pebbles": 0.18}
	biome.harvestables = [
		{"id": tree_id, "min": 16, "max": 22, "spacing": 2.6},
		{"id": "stone", "min": 6, "max": 10, "spacing": 2.4},
	]
	return biome


static func _wasteland() -> BiomeDefinition:
	var biome := BiomeDefinition.new()
	biome.id = "wasteland"
	biome.display_name = "Wasteland"
	## Dirt carpet with rare sand pockets painted by the placer.
	biome.ground_layer = GroundSplat.LAYER_DIRT
	biome.scatter_id = "ground_dirt"
	biome.fill = 0.48
	biome.scatter_profile = {"tufts": 0.05, "ferns": 0.0, "pebbles": 0.28}
	biome.harvestables = [
		{"id": "dead_bush", "min": 10, "max": 16, "spacing": 2.2},
		{"id": "stone", "min": 7, "max": 11, "spacing": 2.4},
	]
	biome.deposits = [
		{"id": "crude_oil", "min": 2, "max": 3, "spacing": 5.0, "size": Vector2i(2, 2)},
	]
	return biome


static func _hills() -> BiomeDefinition:
	var biome := BiomeDefinition.new()
	biome.id = "hills"
	biome.display_name = "Hills"
	biome.ground_layer = GroundSplat.LAYER_ROCK
	biome.scatter_id = "ground_rock"
	biome.fill = 0.48
	biome.scatter_profile = {"tufts": 0.0, "ferns": 0.0, "pebbles": 0.14}

	## Keep density readable — area scaling used to flood this wide strip.
	biome.harvestables = [
		{"id": "stone", "min": 10, "max": 14, "spacing": 2.6},
	]
	for ore_id in ORE_IDS:
		biome.harvestables.append({"id": ore_id, "min": 1, "max": 2, "spacing": 3.4})
	biome.deposits = [
		{"id": "natural_gas", "min": 1, "max": 2, "spacing": 7.0, "size": Vector2i(3, 3)},
	]
	return biome


static func _city() -> BiomeDefinition:
	var biome := BiomeDefinition.new()
	biome.id = "city"
	biome.display_name = "City"
	biome.ground_layer = GroundSplat.LAYER_MEADOW
	biome.scatter_id = ""
	biome.asphalt = true
	biome.fill = 0.46
	biome.harvestables = [
		{"id": "scrap_pile", "min": 8, "max": 12, "spacing": 2.8},
		{"id": "rubble_pile", "min": 5, "max": 8, "spacing": 3.2},
		{"id": "tire_pile", "min": 4, "max": 6, "spacing": 3.0},
		{"id": "broken_car", "min": 2, "max": 4, "spacing": 4.5},
	]
	return biome
