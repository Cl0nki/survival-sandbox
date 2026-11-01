extends Node3D
class_name BuildingWorld

## Presentation of committed pieces: one Node3D per logical component with a
## MeshInstance3D and a StaticBody3D on the BUILDING layer. Nodes are taken
## from a pool and returned when a piece leaves. Neighbouring walls and posts
## swap to a different shared mesh when a slab beside them appears or goes
## away (bottom mask); their transforms and collision are never touched.
## Transforms come from GridSystem and are never edited after spawn.

var state: BuildingState
var grid: GridSystem
var geometry: BuildingGeometry
## A comparison replica in the same physics world turns this off so it does
## not add a second collider on top of the server pieces. Real clients leave
## it on: they are the only copy in their world.
var collision_enabled := true
## Last level shown when cutting away upper floors, or -1 for everything.
var cut_level := -1
## When this is not empty, only these pieces hide above cut_level. Empty
## means every piece above the cut, which is what the Build Tool wants.
var cut_ids: Dictionary = {}

var _nodes: Dictionary = {}
var _masks: Dictionary = {}
var spawned_total := 0
var freed_total := 0
var reused_total := 0
var mask_updates := 0
## Meshes already removed from the building, still falling as rubble.
var _falls: Array[Dictionary] = []
var _pool: Array[Node3D] = []
var _dust_material: StandardMaterial3D
const POOL_CAP := 1024


func bind(building_state: BuildingState, grid_system: GridSystem, building_geometry: BuildingGeometry) -> void:
	state = building_state
	grid = grid_system
	geometry = building_geometry
	state.changed.connect(_on_changed)
	state.integrity_changed.connect(_on_integrity)
	for component_id in state.components.keys():
		_spawn(int(component_id))


func node_for(component_id: int) -> Node3D:
	return _nodes.get(component_id) as Node3D


func node_count() -> int:
	return _nodes.size()


func pool_count() -> int:
	return _pool.size()


func mask_of(component_id: int) -> int:
	return int(_masks.get(component_id, -1))


## True when this body belongs to a piece the indoor cutaway is hiding.
func collider_is_hidden(collider: Object) -> bool:
	if cut_level < 0 or collider == null or not collider.has_meta(&"component_id"):
		return false
	var component_id := int(collider.get_meta(&"component_id"))
	var component := state.get_component(component_id)
	return component != null and component.level > cut_level and _cut_allows(component_id)


## Hides pieces above `level` without touching collision. -1 shows all.
## Aim rays skip those pieces; walking into them still collides.
## `restrict` limits the cut to one building. Leave it empty to cut every roof.
func set_cut_level(level: int, restrict: Dictionary = {}) -> void:
	if level == cut_level and _same_ids(restrict, cut_ids):
		return
	cut_level = level
	cut_ids = restrict.duplicate()
	for component_id in _nodes.keys():
		_apply_cut(state.get_component(int(component_id)), _nodes[component_id])


func _cut_allows(component_id: int) -> bool:
	return cut_ids.is_empty() or cut_ids.has(component_id)


func _same_ids(left: Dictionary, right: Dictionary) -> bool:
	if left.size() != right.size():
		return false
	for key in left.keys():
		if not right.has(key):
			return false
	return true


func _on_changed(change: Dictionary) -> void:
	var falling := bool(change.get("falling", false))
	var step_sec := float(change.get("step_sec", 0.14))
	for component_id in change["removed"]:
		if falling:
			_release_falling(int(component_id), step_sec)
		else:
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
	var root := _acquire()
	_configure(root, component)
	add_child(root)
	_nodes[component_id] = root
	_masks[component_id] = bottom_mask(component)
	spawned_total += 1
	_apply_cut(component, root)


## Pulls the mesh out of the building and drops it through the storey below.
## Collision is gone immediately, so the floor is no longer there to stand on.
func _release_falling(component_id: int, step_sec: float) -> void:
	var node := node_for(component_id)
	_nodes.erase(component_id)
	_masks.erase(component_id)
	if node == null:
		return
	var body := node.get_node_or_null("Body") as StaticBody3D
	if body != null:
		body.collision_layer = 0
	var mesh := node.get_node_or_null("Mesh") as MeshInstance3D
	if mesh != null:
		if _dust_material == null:
			_dust_material = StandardMaterial3D.new()
			_dust_material.albedo_color = Color(0.62, 0.58, 0.52)
			_dust_material.roughness = 1.0
		mesh.set_surface_override_material(0, _dust_material)
		mesh.visible = true
	var host := get_parent().get_node_or_null("Debris") as Node3D
	if host == null:
		host = self
	var keep := node.global_transform
	node.reparent(host)
	node.global_transform = keep
	var angle := float(posmod(component_id * 5, 12)) / 12.0 * TAU
	var speed := grid.config.floor_height / maxf(step_sec, 0.05)
	_falls.append({
		"node": node,
		"velocity": Vector3(cos(angle) * 0.8, -speed, sin(angle) * 0.8),
		"spin": float(posmod(component_id, 5) - 2) * 1.4,
		"age": 0.0,
		"life": maxf(step_sec, 0.12) + 0.22,
	})
	freed_total += 1


func _process(delta: float) -> void:
	if _falls.is_empty():
		return
	var index := 0
	while index < _falls.size():
		var fall: Dictionary = _falls[index]
		var node := fall["node"] as Node3D
		if node == null or not is_instance_valid(node):
			_falls.remove_at(index)
			continue
		var age := float(fall["age"]) + delta
		fall["age"] = age
		var velocity: Vector3 = fall["velocity"]
		velocity.y -= 20.0 * delta
		fall["velocity"] = velocity
		node.global_position += velocity * delta
		node.rotate_y(float(fall["spin"]) * delta)
		var life := float(fall["life"])
		var crush := clampf(age / maxf(life * 0.7, 0.05), 0.0, 1.0)
		var flat := lerpf(1.0, 0.06, crush * crush)
		node.scale = Vector3(1.0 + crush * 0.55, flat, 1.0 + crush * 0.55)
		if age >= life or node.global_position.y < -1.5:
			_recycle(node)
			_falls.remove_at(index)
			continue
		index += 1


func _free(component_id: int) -> void:
	var node := node_for(component_id)
	_nodes.erase(component_id)
	_masks.erase(component_id)
	if node == null:
		return
	_recycle(node)
	freed_total += 1


func _acquire() -> Node3D:
	while not _pool.is_empty():
		var node := _pool.pop_back() as Node3D
		if node != null and is_instance_valid(node):
			reused_total += 1
			return node
	var root := Node3D.new()
	var mesh := MeshInstance3D.new()
	mesh.name = "Mesh"
	root.add_child(mesh)
	var body := BuildingPieceBody.new()
	body.name = "Body"
	body.collision_mask = 0
	root.add_child(body)
	return root


func _exit_tree() -> void:
	for node in _pool:
		if node != null and is_instance_valid(node):
			node.free()
	_pool.clear()
	_falls.clear()


func _configure(root: Node3D, component: BuildComponent) -> void:
	root.name = "%s_%d" % [BuildTypes.kind_name(component.kind), component.id]
	root.scale = Vector3.ONE
	root.transform = grid.component_transform(component)
	root.set_meta(&"component_id", component.id)
	root.add_to_group(&"building_component")
	var mesh := root.get_node("Mesh") as MeshInstance3D
	mesh.mesh = geometry.mesh_for(component.kind, bottom_mask(component))
	mesh.visible = true
	mesh.set_surface_override_material(0, null)
	var body := root.get_node("Body") as BuildingPieceBody
	body.display_name = BuildTypes.kind_name(component.kind)
	body.collision_layer = PhysicsLayers.BUILDING if collision_enabled else 0
	body.set_meta(&"component_id", component.id)
	for child in body.get_children():
		body.remove_child(child)
		child.free()
	for pair in geometry.collision_shapes(component.kind):
		var shape := CollisionShape3D.new()
		shape.shape = pair[0]
		shape.transform = pair[1]
		body.add_child(shape)


func _recycle(node: Node3D) -> void:
	if node == null or not is_instance_valid(node):
		return
	var mesh := node.get_node_or_null("Mesh") as MeshInstance3D
	if mesh != null:
		mesh.set_surface_override_material(0, null)
		mesh.visible = false
	var body := node.get_node_or_null("Body") as StaticBody3D
	if body != null:
		body.collision_layer = 0
	node.scale = Vector3.ONE
	if node.get_parent() != null:
		node.get_parent().remove_child(node)
	if _pool.size() >= POOL_CAP:
		node.free()
		return
	_pool.append(node)


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


func _on_integrity(component_id: int) -> void:
	var component := state.get_component(component_id)
	var node := node_for(component_id)
	if component == null or node == null:
		return
	_apply_appearance(component, node)
	_refresh_joint_posts(component)


func _apply_cut(component: BuildComponent, node: Node3D) -> void:
	_apply_appearance(component, node)


## Tint and collision for this node only. The shared mesh resource is never
## replaced, and the node transform is never written.
func _apply_appearance(component: BuildComponent, node: Node3D) -> void:
	if component == null or node == null:
		return
	var mesh := node.get_node_or_null("Mesh") as MeshInstance3D
	if mesh != null:
		var cut_hides := cut_level >= 0 and component.level > cut_level and _cut_allows(component.id)
		mesh.visible = not cut_hides and not component.destroyed
		_apply_tint(mesh, component)
	var body := node.get_node_or_null("Body") as StaticBody3D
	if body != null:
		if not collision_enabled or component.destroyed:
			body.collision_layer = 0
		else:
			body.collision_layer = PhysicsLayers.BUILDING


func _refresh_joint_posts(component: BuildComponent) -> void:
	if component == null or not BuildTypes.is_edge_kind(component.kind):
		return
	var key: Vector4i = component.key
	for vertex in GridSystem.edge_vertices(key):
		var post := state.get_component(state.post_at(GridSystem.post_key(vertex, key.z)))
		if post == null:
			continue
		var node := node_for(post.id)
		if node != null:
			_apply_appearance(post, node)


func _apply_tint(mesh: MeshInstance3D, component: BuildComponent) -> void:
	if component.destroyed:
		mesh.set_surface_override_material(0, null)
		return
	var tier := state.display_tier(component)
	var material := mesh.get_surface_override_material(0) as StandardMaterial3D
	if material == null:
		material = BuildingTier.make_material(tier, component.kind)
		mesh.set_surface_override_material(0, material)
	var ratio := 1.0
	if component.max_health > 0 and not state.is_joint_post(component):
		ratio = float(component.health) / float(component.max_health)
	BuildingTier.style_material(material, tier, ratio, component.kind)
