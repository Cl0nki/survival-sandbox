extends Node3D
class_name BuildingWorld

## Presentation of committed pieces: one Node3D per logical component with a
## MeshInstance3D and a StaticBody3D on the BUILDING layer. Nodes are created
## and freed only for the ids a change reports. Neighbouring walls and posts
## swap to a different shared mesh when a slab beside them appears or goes
## away (bottom mask); their transforms and collision are never touched.
## Transforms come from GridSystem and are never edited after spawn.

var state: BuildingState
var grid: GridSystem
var geometry: BuildingGeometry
## Last level shown when cutting away upper floors, or -1 for everything.
var cut_level := -1

var _nodes: Dictionary = {}
var _masks: Dictionary = {}
var spawned_total := 0
var freed_total := 0
var mask_updates := 0


func bind(building_state: BuildingState, grid_system: GridSystem, building_geometry: BuildingGeometry) -> void:
	state = building_state
	grid = grid_system
	geometry = building_geometry
	state.changed.connect(_on_changed)
	for component_id in state.components.keys():
		_spawn(int(component_id))


func node_for(component_id: int) -> Node3D:
	return _nodes.get(component_id) as Node3D


func node_count() -> int:
	return _nodes.size()


func mask_of(component_id: int) -> int:
	return int(_masks.get(component_id, -1))


## Hides pieces above `level` without touching collision. -1 shows all.
func set_cut_level(level: int) -> void:
	if level == cut_level:
		return
	cut_level = level
	for component_id in _nodes.keys():
		_apply_cut(state.get_component(int(component_id)), _nodes[component_id])


func _on_changed(change: Dictionary) -> void:
	for component_id in change["removed"]:
		_free(int(component_id))
	for component_id in change["added"]:
		_spawn(int(component_id))
	var touched := {}
	for cell_key in change["slab_cells"]:
		var key: Vector3i = cell_key
		var cell := Vector2i(key.x, key.z)
		for edge in GridSystem.cell_edges(cell, key.y):
			touched[state.edges.component_at(edge)] = true
		for vertex in GridSystem.cell_vertices(cell):
			touched[state.post_at(GridSystem.post_key(vertex, key.y))] = true
	touched.erase(0)
	for component_id in touched.keys():
		_refresh_mask(int(component_id))


func _spawn(component_id: int) -> void:
	var component := state.get_component(component_id)
	if component == null or _nodes.has(component_id):
		return
	var root := Node3D.new()
	root.name = "%s_%d" % [BuildTypes.kind_name(component.kind), component_id]
	root.transform = grid.component_transform(component)
	root.set_meta(&"component_id", component_id)
	root.add_to_group(&"building_component")
	var mesh := MeshInstance3D.new()
	mesh.name = "Mesh"
	var mask := bottom_mask(component)
	mesh.mesh = geometry.mesh_for(component.kind, mask)
	root.add_child(mesh)
	var body := StaticBody3D.new()
	body.name = "Body"
	body.collision_layer = PhysicsLayers.BUILDING
	body.collision_mask = 0
	body.set_meta(&"component_id", component_id)
	for pair in geometry.collision_shapes(component.kind):
		var shape := CollisionShape3D.new()
		shape.shape = pair[0]
		shape.transform = pair[1]
		body.add_child(shape)
	root.add_child(body)
	add_child(root)
	_nodes[component_id] = root
	_masks[component_id] = mask
	spawned_total += 1
	_apply_cut(component, root)


func _free(component_id: int) -> void:
	var node := node_for(component_id)
	_nodes.erase(component_id)
	_masks.erase(component_id)
	if node == null:
		return
	remove_child(node)
	node.free()
	freed_total += 1


func _refresh_mask(component_id: int) -> void:
	var component := state.get_component(component_id)
	var node := node_for(component_id)
	if component == null or node == null or not BuildingGeometry.uses_bottom_mask(component.kind):
		return
	var mask := bottom_mask(component)
	if mask == mask_of(component_id):
		return
	_masks[component_id] = mask
	(node.get_node("Mesh") as MeshInstance3D).mesh = geometry.mesh_for(component.kind, mask)
	mask_updates += 1


## Which bottom-face pieces stay visible: one bit per neighbouring cell that
## has no slab on the piece's level.
func bottom_mask(component: BuildComponent) -> int:
	if not BuildingGeometry.uses_bottom_mask(component.kind):
		return 0
	var mask := 0
	if component.kind == BuildTypes.Kind.POST:
		var key: Vector3i = component.key
		var cells := GridSystem.vertex_cells(Vector2i(key.x, key.z))
		for i in 4:
			if state.slab_at(GridSystem.slab_key(cells[i], key.y)) == 0:
				mask |= 1 << i
		return mask
	var edge: Vector4i = component.key
	var sides := GridSystem.edge_local_side_cells(edge)
	for i in 2:
		if state.slab_at(GridSystem.slab_key(sides[i], edge.z)) == 0:
			mask |= 1 << i
	return mask


func _apply_cut(component: BuildComponent, node: Node3D) -> void:
	if component == null or node == null:
		return
	var mesh := node.get_node("Mesh") as MeshInstance3D
	mesh.visible = cut_level < 0 or component.level <= cut_level
