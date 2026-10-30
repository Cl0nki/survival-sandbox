extends Node3D
class_name BuildingSystem

## Composition root for local building. Owns the logical state and wires the
## authority, the committed-geometry presentation, the preview root, and the
## debug view. The Build Tool finds this node through the "building_system"
## group. Preview nodes live under PreviewRoot and never under World.

const DEFAULT_CONFIG := preload("res://resources/building/default_building_config.tres")

@export var config: BuildingConfig

var grid: GridSystem
var geometry: BuildingGeometry
var state: BuildingState
var authority: BuildingAuthority
var world: BuildingWorld
var preview_root: Node3D
var debug_view: BuildingDebugView
var debris: DebrisSystem
var impacts: ImpactMarks
## Set by the Build Tool while it is equipped; -2 lets the system decide.
var cut_override := -2


func _init() -> void:
	name = "BuildingSystem"


func _ready() -> void:
	add_to_group(&"building_system")
	if config == null:
		config = DEFAULT_CONFIG
	var problems := config.validate()
	if not problems.is_empty():
		push_error("BuildingConfig invalid: %s" % ", ".join(problems))
	grid = GridSystem.new(config)
	geometry = BuildingGeometry.new(config)
	state = BuildingState.new()
	world = BuildingWorld.new()
	world.name = "World"
	add_child(world)
	world.bind(state, grid, geometry)
	debris = DebrisSystem.new()
	debris.name = "Debris"
	debris.setup(config)
	add_child(debris)
	impacts = ImpactMarks.new()
	impacts.name = "Impacts"
	impacts.setup(config)
	add_child(impacts)
	preview_root = Node3D.new()
	preview_root.name = "PreviewRoot"
	add_child(preview_root)
	authority = BuildingAuthority.new()
	authority.name = "Authority"
	add_child(authority)
	authority.setup(state, grid, geometry, self)
	authority.impacts = impacts
	authority.debris = debris
	debug_view = BuildingDebugView.new()
	debug_view.name = "DebugView"
	add_child(debug_view)
	debug_view.bind(self)


func _process(_delta: float) -> void:
	if cut_override != -2:
		world.set_cut_level(cut_override)
		return
	world.set_cut_level(_indoor_cut_level())


## When the local player stands under a slab, hide everything above their
## level so the top-down camera can see inside. Those pieces still collide
## with the player. Aim skips them, so the cursor hits the room, not the roof.
func _indoor_cut_level() -> int:
	var player := _local_player()
	if player == null:
		return -1
	var level := grid.level_for_height(player.global_position.y)
	var cell := grid.world_to_cell(player.global_position)
	for above in range(level + 1, config.max_levels + 1):
		if state.slab_at(GridSystem.slab_key(cell, above)) != 0:
			return level
	return -1


func _local_player() -> Node3D:
	for node in get_tree().get_nodes_in_group(&"player"):
		if node.has_method("is_controlled_locally") and bool(node.call("is_controlled_locally")):
			return node as Node3D
	return null
