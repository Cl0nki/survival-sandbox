extends RefCounted
class_name BiomeDefinition

## One reusable biome: ground look + scatter + harvest/deposit spawn tables.
## Place with BiomePlacer; paint with the splat regions it returns.

var id := ""
var display_name := ""
## GroundSplat.LAYER_* for the biome carpet.
var ground_layer := 1
## Texture id for GroundScatter profiles (empty = no clutter).
var scatter_id := ""
## Optional density override: {tufts, ferns, pebbles} per m².
var scatter_profile := {}
## City scrap yards: sharp asphalt overlay.
var asphalt := false
## When false, placer skips harvestables, deposits, and scatter.
var spawn_props := true
## GroundSplat forest overlay channel: -1 none, 0 oak, 1 birch, 2 spruce.
var forest_channel := -1
## How far props reach toward the biome edge (0.5 = full half-size).
var fill := 0.48

## Harvestable ResourceNode rules.
## Each entry: {id, min, max, spacing} — count is rolled in [min, max].
var harvestables: Array = []

## GroundDeposit rules.
## Each entry: {id, min, max, spacing, size: Vector2i}.
var deposits: Array = []


func duplicate_definition() -> BiomeDefinition:
	var copy := BiomeDefinition.new()
	copy.id = id
	copy.display_name = display_name
	copy.ground_layer = ground_layer
	copy.scatter_id = scatter_id
	copy.scatter_profile = scatter_profile.duplicate(true)
	copy.asphalt = asphalt
	copy.spawn_props = spawn_props
	copy.forest_channel = forest_channel
	copy.fill = fill
	copy.harvestables = harvestables.duplicate(true)
	copy.deposits = deposits.duplicate(true)
	return copy
