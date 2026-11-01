extends Node3D
class_name DeployableSystem

## Grid deployables beside BuildingSystem. Cell pieces use the same anchor
## and rotation as rooms. The anchor is the minimum cell of the footprint.
## A chest is 2x1 and sits in the middle of those cells. Doors and window
## bars mount on a doorway or window. Nothing here is allowed to pass
## through a wall, and a wall cannot be raised through one of these.

const EDGE_GAP := 0.02
const PLACE_RANGE := 5.0
const _FITTING := preload("res://scripts/deployables/deployable_fitting.gd")

var _building: BuildingSystem
var _pieces: Dictionary = {}
var _cell_owner: Dictionary = {}
var _edge_owner: Dictionary = {}
var _next_id := 1


func _init() -> void:
	name = "DeployableSystem"


func _ready() -> void:
	add_to_group(&"deployable_system")
	_bind_building()


func obstruction_name(box: AABB) -> String:
	var thin := 0.12
	if _building != null and _building.grid != null:
		thin = _building.grid.config.slab_thickness + 0.02
	for piece in _pieces.values():
		var volume: AABB = piece["volume"]
		if box.size.y <= thin and _floor_fits(box, volume):
			continue
		if volume.grow(-0.001).intersects(box):
			return str(piece["display_name"])
	return ""


## A floor may be poured under a whole footprint. One slab under half of it may not.
func _floor_fits(box: AABB, volume: AABB) -> bool:
	if box.position.x >= volume.end.x or box.end.x <= volume.position.x:
		return true
	if box.position.z >= volume.end.z or box.end.z <= volume.position.z:
		return true
	return box.position.x <= volume.position.x + 0.02 and box.end.x >= volume.end.x - 0.02 and box.position.z <= volume.position.z + 0.02 and box.end.z >= volume.end.z - 0.02


func piece_count() -> int:
	return _pieces.size()


func has_piece(piece_id: int) -> bool:
	return _pieces.has(piece_id)


func cells_of(piece_id: int) -> Array[Vector2i]:
	var piece: Dictionary = _pieces.get(piece_id, {})
	var cells: Array[Vector2i] = []
	for cell in piece.get("cells", []):
		cells.append(cell)
	return cells


func center_of(piece_id: int) -> Vector3:
	var piece: Dictionary = _pieces.get(piece_id, {})
	var node := piece.get("node") as Node3D
	if node == null:
		return Vector3.ZERO
	return node.global_position


static func in_place_range(from: Vector3, point: Vector3) -> bool:
	return Vector2(from.x - point.x, from.z - point.z).length() <= PLACE_RANGE


func piece_node(piece_id: int) -> Node:
	var piece: Dictionary = _pieces.get(piece_id, {})
	return piece.get("node") as Node


func health_of(piece_id: int) -> int:
	return int(_pieces.get(piece_id, {}).get("health", 0))


static func forward_damage(node: Node, amount: int) -> bool:
	if node == null or amount <= 0 or not node.has_meta(&"deployable_id"):
		return false
	var host := node.get_parent()
	if host == null or not host.has_method(&"damage_piece"):
		return false
	return bool(host.call(&"damage_piece", int(node.get_meta(&"deployable_id")), amount))


## Subtracts hit points. The piece is removed at zero.
func damage_piece(piece_id: int, amount: int) -> bool:
	if not local_authority() or amount <= 0 or not _pieces.has(piece_id):
		return false
	var piece: Dictionary = _pieces[piece_id]
	var health := int(piece["health"])
	if health <= 0:
		return false
	health = maxi(health - amount, 0)
	piece["health"] = health
	_refresh_health(piece)
	if multiplayer.get_peers().size() > 0:
		sync_health.rpc(piece_id, health)
	if health <= 0:
		_remove(piece_id)
	return true


## Swings a door toward `from` or shuts it. Window bars stay put.
func toggle_door(piece_id: int, from: Vector3) -> bool:
	if not local_authority() or not _pieces.has(piece_id):
		return false
	var node := piece_node(piece_id)
	if node == null or not bool(node.call(&"toggle_from", from)):
		return false
	if multiplayer.get_peers().size() > 0:
		sync_door.rpc(piece_id, bool(node.get(&"open")), float(node.get(&"swing_yaw")))
	return true


@rpc("authority", "reliable")
func sync_door(piece_id: int, is_open: bool, yaw: float) -> void:
	if local_authority():
		return
	var node := piece_node(piece_id)
	if node != null and node.has_method(&"apply_swing"):
		node.call(&"apply_swing", is_open, yaw)


@rpc("authority", "reliable")
func sync_health(piece_id: int, health: int) -> void:
	if local_authority() or not _pieces.has(piece_id):
		return
	var piece: Dictionary = _pieces[piece_id]
	piece["health"] = maxi(health, 0)
	_refresh_health(piece)
	if int(piece["health"]) <= 0:
		_remove(piece_id)


## Read-only footprint check. The ghost uses this, and try_place commits it.
func plan_cells(kind: String, anchor: Vector2i, rotation: int = 0, level: int = 0) -> Dictionary:
	var plan := {
		"ok": false,
		"reason": "",
		"kind": kind,
		"anchor": anchor,
		"level": level,
		"steps": posmod(rotation, 4),
		"cells": [] as Array[Vector2i],
		"support_y": 0.0,
		"body": Vector3.ZERO,
		"center": Vector3.ZERO,
		"height": 0.0,
		"size": Vector2i.ZERO,
		"volume": AABB(),
	}
	if not _ensure_building():
		plan["reason"] = "No building grid"
		return plan
	if not DeployableCatalog.known(kind) or not DeployableCatalog.on_cells(kind):
		plan["reason"] = "Cannot place %s on cells" % kind
		return plan
	var steps := int(plan["steps"])
	var size := DeployableCatalog.footprint(kind)
	var cells := _footprint_cells(anchor, size, steps)
	var height := DeployableCatalog.body_height(kind)
	var cell_size := _building.grid.config.cell_size
	var body := Vector3(float(size.x) * cell_size - _clearance() * 2.0, height, float(size.y) * cell_size - _clearance() * 2.0)
	var support := _support(cells, level)
	var center := _center(cells, level)
	center.y = float(support["y"]) if bool(support["ok"]) else _building.grid.level_y(level)
	plan["cells"] = cells
	plan["support_y"] = center.y
	plan["body"] = body
	plan["center"] = center
	plan["height"] = height
	plan["size"] = size
	plan["volume"] = _cell_volume(cells, center.y, height)
	if not _inside(cells):
		plan["reason"] = "Outside the build area"
		return plan
	var taken := _cell_taken(cells, level)
	if taken != "":
		plan["reason"] = taken
		return plan
	var crossed := _shared_edge_block(cells, level)
	if crossed != "":
		plan["reason"] = "Clips a %s" % crossed
		return plan
	if not bool(support["ok"]):
		plan["reason"] = str(support["reason"])
		return plan
	var clip := _overlap_name(plan["volume"], 0)
	if clip != "":
		plan["reason"] = "Clips a %s" % clip
		return plan
	plan["ok"] = true
	return plan


## Read-only opening check. A door or window bars ghost uses the same shape it will commit.
func plan_edge(kind: String, edge: Vector4i) -> Dictionary:
	var plan := {
		"ok": false,
		"reason": "",
		"kind": kind,
		"edge": edge,
		"level": edge.z,
		"xform": Transform3D.IDENTITY,
		"local": AABB(),
		"volume": AABB(),
		"center": Vector3.ZERO,
		"host_id": 0,
	}
	if not _ensure_building():
		plan["reason"] = "No building grid"
		return plan
	var need := DeployableCatalog.slot_kind(kind)
	if need < 0:
		plan["reason"] = "%s does not fit an opening" % kind
		return plan
	var shape := _opening_shape(kind, edge)
	plan["xform"] = shape["xform"]
	plan["local"] = shape["local"]
	plan["volume"] = shape["volume"]
	plan["center"] = (shape["volume"] as AABB).get_center()
	if edge.w < 0:
		plan["reason"] = "Aim at a %s" % ("doorway" if need == BuildTypes.Kind.DOORWAY else "window")
		return plan
	if _edge_owner.has(edge):
		plan["reason"] = "Slot taken"
		return plan
	var host_id := _building.state.edges.component_at(edge)
	var host := _building.state.get_component(host_id)
	var needed := "doorway" if need == BuildTypes.Kind.DOORWAY else "window"
	if host == null or host.destroyed or host.kind != need:
		plan["reason"] = "Needs a %s" % needed
		return plan
	var clip := _overlap_name(shape["volume"], host_id)
	if clip != "":
		plan["reason"] = "Clips a %s" % clip
		return plan
	plan["host_id"] = host_id
	plan["ok"] = true
	return plan


## Cell deployable. rotation 0 and 2 run the long axis along X. 1 and 3 run it along Z.
func try_place(kind: String, anchor: Vector2i, rotation: int = 0, level: int = 0, piece_id: int = 0) -> Dictionary:
	var plan := plan_cells(kind, anchor, rotation, level)
	if not bool(plan["ok"]):
		return _fail(str(plan["reason"]))
	var cells: Array[Vector2i] = []
	for cell in plan["cells"]:
		cells.append(cell)
	return _commit_cells(kind, anchor, int(plan["steps"]), level, cells, plan["volume"], float(plan["support_y"]), float(plan["height"]), plan["size"], piece_id)


## Door or window bars. The edge must already be that opening.
func try_place_edge(kind: String, edge: Vector4i, piece_id: int = 0) -> Dictionary:
	var plan := plan_edge(kind, edge)
	if not bool(plan["ok"]):
		return _fail(str(plan["reason"]))
	var fitted := _opening_fit(kind, edge)
	return _commit_slot(kind, edge, int(plan["host_id"]), fitted, piece_id)


func _commit_cells(kind: String, anchor: Vector2i, steps: int, level: int, cells: Array[Vector2i], volume: AABB, support_y: float, height: float, size: Vector2i, piece_id: int = 0) -> Dictionary:
	if piece_id <= 0:
		piece_id = _next_id
	_next_id = maxi(_next_id, piece_id + 1)
	var clearance := _clearance()
	var cell := _building.grid.config.cell_size
	var body := Vector3(float(size.x) * cell - clearance * 2.0, height, float(size.y) * cell - clearance * 2.0)
	var center := _center(cells, level)
	center.y = support_y
	var node := _spawn_cell(kind, piece_id, body, steps, center)
	_remember(piece_id, kind, level, steps, anchor, cells, Vector4i(0, 0, 0, -1), 0, volume, node)
	_watch(node)
	return {"ok": true, "reason": "", "id": piece_id}


func _commit_slot(kind: String, edge: Vector4i, host_id: int, fitted: Dictionary, piece_id: int = 0) -> Dictionary:
	if piece_id <= 0:
		piece_id = _next_id
	_next_id = maxi(_next_id, piece_id + 1)
	var node: StaticBody3D = fitted["node"]
	node.name = "%s_%d" % [kind, piece_id]
	add_child(node)
	var cells: Array[Vector2i] = []
	_remember(piece_id, kind, edge.z, 0, Vector2i(edge.x, edge.y), cells, edge, host_id, fitted["volume"], node)
	return {"ok": true, "reason": "", "id": piece_id}


func _remember(piece_id: int, kind: String, level: int, steps: int, anchor: Vector2i, cells: Array[Vector2i], edge: Vector4i, host_id: int, volume: AABB, node: Node3D) -> void:
	_pieces[piece_id] = {
		"id": piece_id,
		"kind": kind,
		"display_name": DeployableCatalog.display_name(kind),
		"level": level,
		"rotation": steps,
		"anchor": anchor,
		"cells": cells,
		"edge": edge,
		"host_id": host_id,
		"volume": volume,
		"node": node,
		"health": DeployableCatalog.max_health(kind),
		"max_health": DeployableCatalog.max_health(kind),
	}
	node.set_meta(&"deployable_id", piece_id)
	_refresh_health(_pieces[piece_id])
	for cell in cells:
		_cell_owner[Vector3i(cell.x, level, cell.y)] = piece_id
	if host_id != 0:
		_edge_owner[edge] = piece_id


func _refresh_health(piece: Dictionary) -> void:
	var node := piece.get("node") as Node
	if node == null or not node.has_method(&"set_deployable_health"):
		return
	node.call(&"set_deployable_health", int(piece["health"]), int(piece["max_health"]))


func _spawn_cell(kind: String, piece_id: int, body: Vector3, steps: int, center: Vector3) -> Node3D:
	var node: Node3D
	if kind == "chest":
		var crate := LootContainer.new()
		crate.body_size = body
		crate.prompt = "Chest"
		crate.display_name = "Chest"
		crate.container_id = "placed_chest_%d" % piece_id
		crate.slot_count = NetConfig.CONTAINER_SLOTS
		crate.box_color = Color(0.42, 0.28, 0.16)
		node = crate
	elif SmeltRules.known(kind):
		var smelter := Smelter.new()
		smelter.station_kind = kind
		smelter.body_size = body
		smelter.box_color = SmeltRules.color_of(kind)
		smelter.container_id = "smelter_%d" % piece_id
		node = smelter
	else:
		var bench := Workbench.new()
		bench.body_size = body
		node = bench
	node.name = "%s_%d" % [kind, piece_id]
	node.basis = GridSystem.rotation_basis(steps)
	node.position = center
	add_child(node)
	node.add_to_group(&"deployable")
	if kind == "chest":
		_add_front(node, body)
	return node


func _add_front(node: Node3D, body: Vector3) -> void:
	var lip := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(body.x * 0.72, body.y * 0.28, 0.04)
	lip.mesh = box
	lip.position = Vector3(0.0, body.y * 0.42, body.z * 0.5)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.28, 0.18, 0.1)
	lip.set_surface_override_material(0, material)
	node.add_child(lip)


func _opening_shape(kind: String, edge: Vector4i) -> Dictionary:
	var config := _building.grid.config
	var span := config.cell_size - config.wall_thickness
	var thick := config.wall_thickness * 0.5
	var y0 := 0.0
	var y1 := config.door_height
	if DeployableCatalog.is_window(kind):
		y0 = config.window_sill_height
		y1 = config.window_head_height
	var local := AABB(Vector3(-span * 0.5, y0, -thick * 0.5), Vector3(span, y1 - y0, thick))
	var xform := _building.grid.edge_transform(edge)
	return {"local": local, "xform": xform, "volume": xform * local, "span": span, "y0": y0, "y1": y1, "thick": thick}


func _opening_fit(kind: String, edge: Vector4i) -> Dictionary:
	var fitted := _opening_shape(kind, edge)
	var local: AABB = fitted["local"]
	var xform: Transform3D = fitted["xform"]
	var tier := DeployableCatalog.tier_of(kind)
	var color := BuildingTier.color_for(tier if tier > 0 else BuildingTier.MIN, BuildTypes.Kind.WALL)
	if DeployableCatalog.is_window(kind):
		color = color.darkened(0.35)
	var body := StaticBody3D.new()
	body.set_script(_FITTING)
	body.set(&"display_name", DeployableCatalog.display_name(kind))
	body.set(&"label_y", float(fitted["y1"]) + 0.22)
	body.collision_layer = PhysicsLayers.WORLD
	body.collision_mask = 0
	body.transform = xform
	if DeployableCatalog.is_window(kind):
		_add_bars(body, float(fitted["span"]), float(fitted["y0"]), float(fitted["y1"]), float(fitted["thick"]), color)
	else:
		body.set(&"is_door", true)
		body.set(&"swing_span", float(fitted["span"]))
		_add_box(body, local, color)
	var collision := CollisionShape3D.new()
	var hull := BoxShape3D.new()
	hull.size = local.size
	collision.shape = hull
	collision.position = local.get_center()
	body.add_child(collision)
	body.add_to_group(&"deployable")
	return {"node": body, "volume": fitted["volume"]}


func _add_box(body: Node3D, local: AABB, color: Color) -> void:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = local.size
	mesh.mesh = box
	mesh.position = local.get_center()
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.86
	mesh.set_surface_override_material(0, material)
	body.add_child(mesh)


func _add_bars(body: Node3D, span: float, y0: float, y1: float, thick: float, color: Color) -> void:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.7
	var gap := (y1 - y0) / 4.0
	for index in 3:
		var mesh := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(span, 0.04, thick)
		mesh.mesh = box
		mesh.position = Vector3(0.0, y0 + gap * float(index + 1), 0.0)
		mesh.set_surface_override_material(0, material)
		body.add_child(mesh)


func _on_building_changed(_change: Dictionary) -> void:
	var doomed: Array[int] = []
	for raw in _pieces.keys():
		var piece_id := int(raw)
		if _should_drop(piece_id):
			doomed.append(piece_id)
		else:
			_rest_on_ground(piece_id)
	for piece_id in doomed:
		_remove(piece_id)


## Upper floors fall with the slab under them. A fitting falls with its opening.
func _should_drop(piece_id: int) -> bool:
	var piece: Dictionary = _pieces[piece_id]
	var host_id := int(piece["host_id"])
	if host_id != 0:
		var host := _building.state.get_component(host_id)
		return host == null or host.destroyed or host.kind != DeployableCatalog.slot_kind(str(piece["kind"]))
	if int(piece["level"]) <= 0:
		return false
	for cell in piece["cells"]:
		if _building.state.slab_at(GridSystem.slab_key(cell, int(piece["level"]))) == 0:
			return true
	return false


func _rest_on_ground(piece_id: int) -> void:
	var piece: Dictionary = _pieces[piece_id]
	if int(piece["host_id"]) != 0 or int(piece["level"]) > 0:
		return
	var cells: Array = piece["cells"]
	var support := _support(cells, 0)
	if not bool(support["ok"]):
		return
	var node := piece["node"] as Node3D
	if node == null:
		return
	var y := float(support["y"])
	if absf(node.position.y - y) < 0.001:
		return
	node.position.y = y
	var volume: AABB = piece["volume"]
	volume.position.y = y
	piece["volume"] = volume


func _remove(piece_id: int) -> void:
	var piece: Dictionary = _pieces.get(piece_id, {})
	if piece.is_empty():
		return
	var level := int(piece["level"])
	for cell in piece["cells"]:
		_cell_owner.erase(Vector3i(cell.x, level, cell.y))
	if int(piece["host_id"]) != 0:
		_edge_owner.erase(piece["edge"])
	var node := piece.get("node") as Node
	_pieces.erase(piece_id)
	if node != null and is_instance_valid(node):
		node.queue_free()


func _bind_building() -> void:
	var host := get_parent()
	var system := host.get_node_or_null("BuildingSystem") if host != null else null
	_building = system as BuildingSystem
	if _building == null or _building.state == null:
		return
	if not _building.state.changed.is_connected(_on_building_changed):
		_building.state.changed.connect(_on_building_changed)


func _ensure_building() -> bool:
	if _building == null or not is_instance_valid(_building) or _building.state == null:
		_bind_building()
	return _building != null and _building.state != null


func _footprint_cells(anchor: Vector2i, size: Vector2i, steps: int) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for local in BlueprintDefinition.cells_of(size):
		cells.append(GridSystem.local_cell_to_world(local, size, steps, anchor))
	return cells


func _inside(cells: Array[Vector2i]) -> bool:
	for cell in cells:
		if not _building.grid.in_bounds(cell):
			return false
	return true


func _cell_taken(cells: Array[Vector2i], level: int) -> String:
	for cell in cells:
		var owner := int(_cell_owner.get(Vector3i(cell.x, level, cell.y), 0))
		if owner == 0:
			continue
		var piece: Dictionary = _pieces.get(owner, {})
		return "Blocked by %s" % str(piece.get("display_name", "deployable"))
	return ""


func _shared_edge_block(cells: Array[Vector2i], level: int) -> String:
	var occupied := {}
	for cell in cells:
		occupied[cell] = true
	for cell in cells:
		if occupied.has(cell + Vector2i(1, 0)):
			var east := _edge_piece_name(GridSystem.side_edge(cell, BuildTypes.Side.EAST, level))
			if east != "":
				return east
		if occupied.has(cell + Vector2i(0, 1)):
			var south := _edge_piece_name(GridSystem.side_edge(cell, BuildTypes.Side.SOUTH, level))
			if south != "":
				return south
	return ""


func _edge_piece_name(key: Vector4i) -> String:
	var component := _building.state.get_component(_building.state.edges.component_at(key))
	if component == null or component.destroyed:
		return ""
	return BuildTypes.kind_name(component.kind)


func _support(cells: Array, level: int) -> Dictionary:
	var slabs := 0
	for cell in cells:
		if _building.state.slab_at(GridSystem.slab_key(cell, level)) != 0:
			slabs += 1
	if level > 0 and slabs != cells.size():
		return {"ok": false, "reason": "Needs a floor", "y": 0.0}
	if slabs != 0 and slabs != cells.size():
		return {"ok": false, "reason": "Needs the same floor under the whole footprint", "y": 0.0}
	var y := _building.grid.level_y(level)
	if slabs == cells.size():
		y += _building.grid.config.slab_thickness
	return {"ok": true, "reason": "", "y": y}


func _cell_volume(cells: Array[Vector2i], support_y: float, height: float) -> AABB:
	var clearance := _clearance()
	var cell_size := _building.grid.config.cell_size
	var origin := _building.grid.config.grid_origin
	var min_cell := cells[0]
	var max_cell := cells[0]
	for cell in cells:
		min_cell = Vector2i(mini(min_cell.x, cell.x), mini(min_cell.y, cell.y))
		max_cell = Vector2i(maxi(max_cell.x, cell.x), maxi(max_cell.y, cell.y))
	var min_corner := Vector3(
		origin.x + float(min_cell.x) * cell_size + clearance,
		support_y,
		origin.z + float(min_cell.y) * cell_size + clearance
	)
	var max_corner := Vector3(
		origin.x + float(max_cell.x + 1) * cell_size - clearance,
		support_y + height,
		origin.z + float(max_cell.y + 1) * cell_size - clearance
	)
	return AABB(min_corner, max_corner - min_corner)


func _center(cells: Array[Vector2i], level: int) -> Vector3:
	var cell_size := _building.grid.config.cell_size
	var origin := _building.grid.config.grid_origin
	var min_cell := cells[0]
	var max_cell := cells[0]
	for cell in cells:
		min_cell = Vector2i(mini(min_cell.x, cell.x), mini(min_cell.y, cell.y))
		max_cell = Vector2i(maxi(max_cell.x, cell.x), maxi(max_cell.y, cell.y))
	return Vector3(
		origin.x + float(min_cell.x + max_cell.x + 1) * 0.5 * cell_size,
		_building.grid.level_y(level),
		origin.z + float(min_cell.y + max_cell.y + 1) * 0.5 * cell_size
	)


func _overlap_name(volume: AABB, ignore_id: int) -> String:
	var shrunk := volume.grow(-0.001)
	for component in _building.state.components.values():
		if component == null or component.destroyed or component.id == ignore_id:
			continue
		if component.kind == BuildTypes.Kind.SLAB:
			continue
		var box := _building.geometry.world_aabb(component.kind, _building.grid.component_transform(component))
		if shrunk.intersects(box):
			return BuildTypes.kind_name(component.kind)
	return ""


func _clearance() -> float:
	return _building.grid.config.wall_thickness * 0.5 + EDGE_GAP


func _fail(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason, "id": 0}


func _watch(node: Node) -> void:
	var crate := node as LootContainer
	if crate == null:
		return
	var net := _net()
	if net != null:
		net.watch_container(crate)


func publish_smelt(piece_id: int, text: String) -> void:
	if not local_authority():
		return
	var peer := multiplayer.multiplayer_peer
	if peer == null or multiplayer.get_peers().is_empty():
		return
	sync_smelt_label.rpc(piece_id, text)


@rpc("authority", "reliable")
func sync_smelt_label(piece_id: int, text: String) -> void:
	if local_authority():
		return
	var node := piece_node(piece_id) as Smelter
	if node != null:
		node.set_smelt_status(text)


## The character solver stalls when a new solid contains the capsule center.
## A lid you can stand on stays legal: the center sits above that box.
func blocks_player(volume: AABB, feet: Vector3, body_height: float) -> bool:
	if volume.size.y <= 0.05:
		return false
	var solid := volume
	solid.size.y -= 0.05
	var center := feet + Vector3(0.0, body_height * 0.5, 0.0)
	return solid.has_point(center)


func local_authority() -> bool:
	var peer := multiplayer.multiplayer_peer
	if peer == null:
		return true
	return multiplayer.is_server()


## The owning client asks the server to spend the hotbar item and place it.
func request_place(kind: String, anchor: Vector2i, rotation: int, level: int, edge: Vector4i) -> void:
	if local_authority():
		return
	submit_deploy.rpc_id(1, kind, anchor.x, anchor.y, rotation, level, edge.x, edge.y, edge.z, edge.w)


@rpc("any_peer", "reliable")
func submit_deploy(kind: String, ax: int, az: int, rotation: int, level: int, ex: int, ey: int, ez: int, ew: int) -> void:
	if not local_authority():
		return
	var sender := multiplayer.get_remote_sender_id()
	var net := _net()
	if net == null or sender <= 1:
		return
	if str(net.hotbar_item(sender)) != kind or not DeployableCatalog.known(kind):
		net.deploy_notice(sender, "Not in hand")
		return
	var players: Dictionary = net.authority_players()
	var body := players.get(sender) as Node3D
	if body == null:
		return
	var from := body.global_position
	var placed := {}
	if DeployableCatalog.on_cells(kind):
		var plan := plan_cells(kind, Vector2i(ax, az), rotation, level)
		var height := 1.8
		if body.has_method(&"body_height"):
			height = float(body.call(&"body_height"))
		if bool(plan.get("ok", false)) and blocks_player(plan.get("volume", AABB()), from, height):
			plan["ok"] = false
			plan["reason"] = "Blocked by you"
		if not bool(plan["ok"]) or not in_place_range(from, plan["center"]):
			net.deploy_notice(sender, _refuse_text(kind, plan, from))
			return
		placed = try_place(kind, Vector2i(ax, az), rotation, level)
	else:
		var edge := Vector4i(ex, ey, ez, ew)
		var plan := plan_edge(kind, edge)
		if not bool(plan["ok"]) or not in_place_range(from, plan["center"]):
			net.deploy_notice(sender, _refuse_text(kind, plan, from))
			return
		placed = try_place_edge(kind, edge)
	if not bool(placed.get("ok", false)):
		net.deploy_notice(sender, "Cannot place %s: %s" % [DeployableCatalog.display_name(kind), str(placed.get("reason", ""))])
		return
	if not net.take_hotbar_item(sender, kind):
		_remove(int(placed["id"]))
		net.deploy_notice(sender, "Not in hand")
		return
	var node := piece_node(int(placed["id"]))
	if node is LootContainer:
		net.watch_container(node)
	apply_deploy.rpc(kind, ax, az, rotation, level, ex, ey, ez, ew, int(placed["id"]))
	net.deploy_notice(sender, "Placed %s" % DeployableCatalog.display_name(kind))


@rpc("authority", "reliable")
func apply_deploy(kind: String, ax: int, az: int, rotation: int, level: int, ex: int, ey: int, ez: int, ew: int, piece_id: int) -> void:
	if local_authority():
		return
	if DeployableCatalog.on_cells(kind):
		try_place(kind, Vector2i(ax, az), rotation, level, piece_id)
	else:
		try_place_edge(kind, Vector4i(ex, ey, ez, ew), piece_id)


func _refuse_text(kind: String, plan: Dictionary, from: Vector3) -> String:
	var reason := str(plan.get("reason", ""))
	if bool(plan.get("ok", false)) and not in_place_range(from, plan.get("center", Vector3.ZERO)):
		reason = "Too far"
	return "Cannot place %s: %s" % [DeployableCatalog.display_name(kind), reason]


func _net() -> GameNet:
	var host := get_parent()
	if host == null:
		return null
	return host.get_node_or_null("GameNet") as GameNet
