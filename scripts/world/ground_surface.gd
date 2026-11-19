extends RefCounted
class_name GroundSurface

## What the ground is made of under a point, so footsteps can sound right.
##
## GroundSplat paints the floor from lists of rectangles. It hands the same lists to
## register(), so the sound always matches what the player sees. Later layers win where
## paint overlaps, the same order the shader uses: base ground, forest floor, soil
## patches (sand, clay, gravel), then asphalt.
##
## Each surface has its own Sounds event (footstep_grass and so on). An event with no
## files falls back to the plain "footstep" event, so a missing sound is never silent.

const GRASS := &"grass"
const FOREST := &"forest"
const DIRT := &"dirt"
const GRAVEL := &"gravel"
const SAND := &"sand"
const ROCK := &"rock"
const ASPHALT := &"asphalt"

const FALLBACK_EVENT := &"footstep"
const FOOTSTEP_EVENTS := {
	GRASS: &"footstep_grass",
	FOREST: &"footstep_forest",
	DIRT: &"footstep_dirt",
	GRAVEL: &"footstep_gravel",
	SAND: &"footstep_sand",
	ROCK: &"footstep_rock",
	ASPHALT: &"footstep_asphalt",
}

## Index matches GroundSplat.LAYER_DIRT, LAYER_MEADOW, LAYER_ROCK, LAYER_GRASS.
const BASE_LAYERS: Array[StringName] = [DIRT, GRASS, ROCK, GRASS]
## Index matches GroundSplat.SOIL_SAND, SOIL_CLAY, SOIL_GRAVEL. Clay is soft earth.
const SOIL_LAYERS: Array[StringName] = [SAND, DIRT, GRAVEL]

const PRIORITY_BASE := 0
const PRIORITY_FOREST := 1
const PRIORITY_SOIL := 2
const PRIORITY_ASPHALT := 3

## Each entry: [Rect2 in world X/Z, surface, priority]. Highest priority wins.
static var _patches: Array = []
static var _fallback: StringName = &""


## The floor of the map that is painted now. Called by GroundSplat when it builds.
## Region entries are [center: Vector3, size: float or Vector2, layer: int], the same
## shape GroundSplat rasterizes. Ground nobody painted is meadow on the big survival
## yard and dirt on the small debug yard, just like the shader.
static func register(
	base_regions: Array,
	soil_regions: Array,
	asphalt_regions: Array,
	forest_regions: Array,
	fallback: StringName
) -> void:
	_patches.clear()
	_fallback = fallback
	_add(base_regions, BASE_LAYERS, PRIORITY_BASE)
	_add(forest_regions, [FOREST, FOREST, FOREST], PRIORITY_FOREST)
	_add(soil_regions, SOIL_LAYERS, PRIORITY_SOIL)
	_add(asphalt_regions, [ASPHALT], PRIORITY_ASPHALT)


static func clear() -> void:
	_patches.clear()
	_fallback = &""


static func is_registered() -> bool:
	return _fallback != &""


## The surface under a world position, or &"" when no map has painted a floor yet.
static func at(position: Vector3) -> StringName:
	if _fallback == &"":
		return &""
	var flat := Vector2(position.x, position.z)
	var best := _fallback
	var best_priority := -1
	for patch in _patches:
		var priority: int = patch[2]
		if priority >= best_priority and (patch[0] as Rect2).has_point(flat):
			best = patch[1]
			best_priority = priority
	return best


## The Sounds event for a surface. An unknown or unpainted surface gives the plain footstep.
static func footstep_event(surface: StringName) -> StringName:
	return FOOTSTEP_EVENTS.get(surface, FALLBACK_EVENT)


static func _add(regions: Array, names: Array, priority: int) -> void:
	for entry in regions:
		# Asphalt entries are [center, size] with no layer; they use layer 0.
		var layer := int(entry[2]) if entry.size() > 2 else 0
		if layer < 0 or layer >= names.size():
			continue
		var center: Vector3 = entry[0]
		var extent := _extent(entry[1])
		var rect := Rect2(center.x - extent.x * 0.5, center.z - extent.y * 0.5, extent.x, extent.y)
		_patches.append([rect, StringName(names[layer]), priority])


static func _extent(size_value: Variant) -> Vector2:
	if size_value is Vector2:
		return size_value
	if size_value is Vector2i:
		return Vector2(size_value.x, size_value.y)
	var side := float(size_value)
	return Vector2(side, side)
