extends Node3D
class_name BuildingSystem

## Composition root. Owns the logical state and wires the authority, the
## committed geometry, the preview, and replication. The Build Tool finds the
## authoritative or client copy through the "building_system" group. A replica
## used only to compare state stays out of that group. Preview nodes live
## under PreviewRoot and never under World.

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
var relay: BuildingRelay
## True in local play and on the server. Clients only apply replicated state.
var authoritative := true
## Set before the node enters the tree to keep a comparison copy from writing.
var force_replica := false
## Set by the Build Tool while it is equipped; -2 lets the system decide.
var cut_override := -2
## Cell the Build Tool is aiming at. Used when the player is not inside a building.
var cut_aim_cell := Vector2i(1 << 20, 1 << 20)
var _cut_cell := Vector2i(1 << 20, 1 << 20)
var _cut_level := -999
var _cut_revision := -1
var _cut_ids: Dictionary = {}


func _init() -> void:
	name = "BuildingSystem"


func _ready() -> void:
	authoritative = _server_owns_state()
	if not force_replica:
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
	authority.writes_enabled = authoritative
	authority.impacts = impacts
	authority.debris = debris
	relay = BuildingRelay.new()
	relay.name = "Relay"
	add_child(relay)
	relay.setup(self)
	debug_view = BuildingDebugView.new()
	debug_view.name = "DebugView"
	add_child(debug_view)
	debug_view.bind(self)


func _process(_delta: float) -> void:
	var cut := active_cut()
	world.set_cut_level(int(cut[0]), cut[1])


## Indoor walk and the Build Tool share this. Only the focused building
## opens, at the walk level or the build level.
func active_cut() -> Array:
	var player := _local_player()
	var stand_cell := Vector2i.ZERO
	var stand_level := 0
	if player != null:
		stand_cell = grid.world_to_cell(player.global_position)
		stand_level = grid.level_for_height(player.global_position.y)
	var level := cut_override if cut_override != -2 else stand_level
	var cell := stand_cell
	if player == null or not state.column_has_room(stand_cell):
		if cut_override != -2 and cut_aim_cell.x < 1 << 19:
			cell = cut_aim_cell
		elif cut_override == -2:
			return [-1, {}]
	if cut_override == -2 and not _has_cover(stand_cell, stand_level):
		return [-1, {}]
	if cell != _cut_cell or level != _cut_level or state.revision != _cut_revision:
		_cut_cell = cell
		_cut_level = level
		_cut_revision = state.revision
		_cut_ids = state.building_ids_at(cell, level)
	if _cut_ids.is_empty():
		return [-1, {}]
	return [level, _cut_ids]


func _has_cover(cell: Vector2i, level: int) -> bool:
	for above in range(level + 1, config.max_levels + 1):
		if state.slab_at(GridSystem.slab_key(cell, above)) != 0:
			return true
	return false


func _server_owns_state() -> bool:
	if force_replica:
		return false
	var peer := multiplayer.multiplayer_peer
	if peer == null:
		return true
	return multiplayer.is_server()


func _local_player() -> Node3D:
	for node in get_tree().get_nodes_in_group(&"player"):
		if node.has_method("is_controlled_locally") and bool(node.call("is_controlled_locally")):
			return node as Node3D
	return null
