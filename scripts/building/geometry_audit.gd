extends RefCounted
class_name GeometryAudit

## Inspects the committed building as it actually exists in the scene tree
## and reports anything that could jitter, Z-fight, overlap, or leave a gap:
## - slot ownership: one piece per canonical slot, registry and state agree
## - nodes: exactly one node per piece, transform equal (bit for bit) to the
##   canonical transform, mesh equal to the expected bottom-mask variant
## - collision: shapes match the module parts; no two pieces' blocking shapes
##   overlap except a vertical piece passing through the slab of its level
## - faces: no two front faces lie in the same plane with the same facing and
##   overlap by area (read from the real mesh arrays), none on the ground plane,
##   and triangle winding agrees with the stored normals
## - joints: every edge piece ends flush against a post at both ends
## - graph: every link is stored from both ends with mirrored meaning
## - preview: no physics bodies under the preview root

const EPS := 0.0005
const AREA_EPS := 0.000001


static func run(system: BuildingSystem, include_faces: bool = true) -> Dictionary:
	var issues: Array = []
	var state := system.state
	_check_slots(state, issues)
	var records := _collect(system, issues)
	_check_overlaps(records, issues, system.config)
	var face_count := 0
	if include_faces:
		face_count = _check_faces(system, records, issues)
	_check_joints(system, issues)
	_check_graph(state, issues)
	_check_floors(state, issues)
	_check_preview(system, issues)
	var shape_count := 0
	for record: Dictionary in records.values():
		shape_count += (record["shapes"] as Array).size()
	return {
		"ok": issues.is_empty(),
		"issues": issues,
		"components": state.component_count(),
		"nodes": records.size(),
		"shapes": shape_count,
		"triangles": face_count,
	}


static func describe(report: Dictionary, limit: int = 8) -> String:
	var lines := PackedStringArray()
	lines.append("audit %s: %d pieces, %d shapes, %d triangles, %d issue(s)" % [
		"OK" if bool(report["ok"]) else "FAILED",
		int(report["components"]), int(report["shapes"]), int(report["triangles"]), (report["issues"] as Array).size(),
	])
	var shown := 0
	for issue: Dictionary in report["issues"]:
		if shown >= limit:
			lines.append("  ...")
			break
		lines.append("  [%s] %s" % [issue["type"], issue["message"]])
		shown += 1
	return "\n".join(lines)


static func _issue(issues: Array, type: String, message: String, at: Vector3 = Vector3.ZERO) -> void:
	issues.append({"type": type, "message": message, "position": at})


# --- logical slots -----------------------------------------------------------

static func _check_slots(state: BuildingState, issues: Array) -> void:
	var seen := {}
	var edge_pieces := 0
	for component: BuildComponent in state.components.values():
		var family := BuildTypes.Kind.WALL if BuildTypes.is_edge_kind(component.kind) else component.kind
		var slot := "%d|%s" % [family, str(component.key)]
		if seen.has(slot):
			_issue(issues, "duplicate", "%s and #%d share slot %s" % [component.describe(), int(seen[slot]), slot])
		seen[slot] = component.id
		var owner := 0
		match component.kind:
			BuildTypes.Kind.SLAB:
				owner = state.slab_at(component.key)
			BuildTypes.Kind.POST:
				owner = state.post_at(component.key)
			BuildTypes.Kind.STAIRS:
				for cell in component.cells:
					if state.stairs_at(cell) != component.id:
						_issue(issues, "slot", "%s missing stairs cell %s" % [component.describe(), cell])
				owner = component.id
			_:
				edge_pieces += 1
				owner = state.edges.component_at(component.key)
		if owner != component.id:
			_issue(issues, "slot", "%s is not the owner of its slot (owner #%d)" % [component.describe(), owner])
	for pair: Array in [[state.slabs, BuildTypes.Kind.SLAB], [state.posts, BuildTypes.Kind.POST]]:
		var slots: Dictionary = pair[0]
		for key in slots.keys():
			var component := state.get_component(int(slots[key]))
			if component == null or component.kind != int(pair[1]) or component.key != key:
				_issue(issues, "slot", "slot %s points at a missing or mismatched piece" % str(key))
	if state.edges.size() != edge_pieces:
		_issue(issues, "duplicate", "edge registry has %d boundaries for %d edge pieces" % [state.edges.size(), edge_pieces])
	for key in state.edges.keys():
		var component := state.get_component(state.edges.component_at(key))
		if component == null or component.key != key or not BuildTypes.is_edge_kind(component.kind):
			_issue(issues, "slot", "boundary %s points at a missing or mismatched piece" % str(key))
	if state.edges.rejected_claims != 0:
		_issue(issues, "duplicate", "edge registry refused %d duplicate claims" % state.edges.rejected_claims)
	for cell in state.stairwells.keys():
		if state.slab_at(cell) != 0:
			_issue(issues, "stairwell", "slab inside the stairwell at %s" % str(cell))


# --- nodes, transforms, shapes ------------------------------------------------

static func _collect(system: BuildingSystem, issues: Array) -> Dictionary:
	var records := {}
	var state := system.state
	var world := system.world
	if not world.global_transform.is_equal_approx(Transform3D.IDENTITY):
		_issue(issues, "transform", "BuildingSystem is not at the world origin; canonical transforms assume it is")
	for child in world.get_children():
		var node := child as Node3D
		if node == null or not node.has_meta(&"component_id"):
			_issue(issues, "node", "unexpected node %s under the building world" % child.name)
			continue
		var component_id := int(node.get_meta(&"component_id"))
		var component := state.get_component(component_id)
		if component == null:
			_issue(issues, "node", "node %s has no logical piece" % node.name, node.position)
			continue
		if records.has(component_id):
			_issue(issues, "duplicate", "two nodes for %s" % component.describe(), node.position)
			continue
		var expected := system.grid.component_transform(component)
		if node.transform != expected:
			_issue(issues, "transform", "%s drifted from its canonical transform" % component.describe(), node.position)
		var mesh_node := node.get_node_or_null("Mesh") as MeshInstance3D
		var wanted_mesh := system.geometry.mesh_for(component.kind, world.bottom_mask(component))
		if mesh_node == null or mesh_node.mesh != wanted_mesh:
			_issue(issues, "mesh", "%s shows the wrong mesh variant" % component.describe(), node.position)
		var shapes := _shape_boxes(node)
		var parts := _expected_boxes(system, component, expected)
		if shapes.size() != parts.size():
			_issue(issues, "collision", "%s has %d shapes, expected %d" % [component.describe(), shapes.size(), parts.size()], node.position)
		else:
			for i in shapes.size():
				var got: AABB = shapes[i]
				if not got.is_equal_approx(parts[i]):
					_issue(issues, "collision", "%s shape %d does not match its visual part" % [component.describe(), i], node.position)
		records[component_id] = {"node": node, "component": component, "shapes": shapes, "xform": expected}
	for component_id in state.components.keys():
		if not records.has(int(component_id)):
			_issue(issues, "node", "%s has no node" % state.get_component(int(component_id)).describe())
	return records


static func _shape_boxes(node: Node3D) -> Array:
	var boxes: Array = []
	var body := node.get_node_or_null("Body") as StaticBody3D
	if body == null:
		return boxes
	for child in body.get_children():
		var shape_node := child as CollisionShape3D
		if shape_node == null or shape_node.disabled or shape_node.shape == null:
			continue
		var local := AABB()
		if shape_node.shape is BoxShape3D:
			var size := (shape_node.shape as BoxShape3D).size
			local = AABB(-size * 0.5, size)
		elif shape_node.shape is ConvexPolygonShape3D:
			var points := (shape_node.shape as ConvexPolygonShape3D).points
			local = AABB(points[0], Vector3.ZERO)
			for point in points:
				local = local.expand(point)
		boxes.append(node.transform * body.transform * shape_node.transform * local)
	return boxes


static func _expected_boxes(system: BuildingSystem, component: BuildComponent, xform: Transform3D) -> Array:
	var boxes: Array = []
	if component.kind == BuildTypes.Kind.STAIRS:
		boxes.append(xform * system.geometry.local_aabb(component.kind))
		return boxes
	for part in system.geometry.parts(component.kind):
		boxes.append(xform * part)
	return boxes


static func _check_overlaps(records: Dictionary, issues: Array, config: BuildingConfig) -> void:
	var buckets := {}
	var items: Array = []
	for record: Dictionary in records.values():
		for box: AABB in record["shapes"]:
			var index := items.size()
			items.append([record["component"], box, record["xform"]])
			for x in range(floori(box.position.x), floori(box.end.x) + 1):
				for z in range(floori(box.position.z), floori(box.end.z) + 1):
					var cell := Vector2i(x, z)
					if not buckets.has(cell):
						buckets[cell] = []
					(buckets[cell] as Array).append(index)
	var reported := {}
	for list: Array in buckets.values():
		for i in list.size():
			for j in range(i + 1, list.size()):
				var a: Array = items[list[i]]
				var b: Array = items[list[j]]
				var ca: BuildComponent = a[0]
				var cb: BuildComponent = b[0]
				if ca.id == cb.id:
					continue
				var pair := Vector2i(mini(ca.id, cb.id), maxi(ca.id, cb.id))
				if reported.has(pair):
					continue
				var box_a: AABB = a[1]
				var box_b: AABB = b[1]
				var overlap := box_a.intersection(box_b)
				if overlap.size.x <= EPS or overlap.size.y <= EPS or overlap.size.z <= EPS:
					continue
				if _allowed_overlap(ca, cb, box_a, box_b, overlap):
					continue
				if ca.kind == BuildTypes.Kind.STAIRS and _clear_of_wedge(overlap, a[2], config):
					continue
				if cb.kind == BuildTypes.Kind.STAIRS and _clear_of_wedge(overlap, b[2], config):
					continue
				reported[pair] = true
				var label := "duplicate" if box_a.is_equal_approx(box_b) else "overlap"
				_issue(issues, label, "%s and %s overlap by %s" % [ca.describe(), cb.describe(), str(overlap.size)], overlap.get_center())


## The stairs collision is a wedge, so its bounding box overstates it. The
## wedge rises linearly toward local -Z; a box inside the bounding box only
## touches the solid if its bottom is below the slope at the box's uphill end.
## Stairs transforms are exact 90-degree rotations, so the box stays exact.
static func _clear_of_wedge(overlap: AABB, stairs_xform: Transform3D, config: BuildingConfig) -> bool:
	var local := stairs_xform.affine_inverse() * overlap
	var half_run := config.cell_size * float(GridSystem.STAIRS_SIZE.y) * 0.5
	var uphill := clampf(local.position.z, -half_run, half_run)
	var surface := config.floor_height * (half_run - uphill) / (2.0 * half_run)
	return local.position.y >= surface - EPS


## Vertical pieces pass through the slab of their own level, and only within
## the slab's thickness.
static func _allowed_overlap(ca: BuildComponent, cb: BuildComponent, box_a: AABB, box_b: AABB, overlap: AABB) -> bool:
	var slab: BuildComponent = null
	var slab_box := AABB()
	var other: BuildComponent = null
	if ca.kind == BuildTypes.Kind.SLAB:
		slab = ca
		slab_box = box_a
		other = cb
	elif cb.kind == BuildTypes.Kind.SLAB:
		slab = cb
		slab_box = box_b
		other = ca
	if slab == null or not BuildTypes.is_vertical_kind(other.kind) or other.level != slab.level:
		return false
	return overlap.position.y >= slab_box.position.y - EPS and overlap.end.y <= slab_box.end.y + EPS


# --- faces ---------------------------------------------------------------------

static func _check_faces(system: BuildingSystem, records: Dictionary, issues: Array) -> int:
	var planes := {}
	var total := 0
	var ground_y := system.grid.config.grid_origin.y
	for record: Dictionary in records.values():
		var node: Node3D = record["node"]
		var component: BuildComponent = record["component"]
		var mesh_node := node.get_node_or_null("Mesh") as MeshInstance3D
		if mesh_node == null or mesh_node.mesh == null:
			continue
		var arrays := mesh_node.mesh.surface_get_arrays(0)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var xform := node.transform
		for t in range(0, indices.size(), 3):
			var a := xform * vertices[indices[t]]
			var b := xform * vertices[indices[t + 1]]
			var c := xform * vertices[indices[t + 2]]
			var cross := (c - a).cross(b - a)
			if not BuildingGeometry.CLOCKWISE_FRONT:
				cross = -cross
			if cross.length_squared() < 1e-12:
				continue
			var front := cross.normalized()
			var stored := (xform.basis * normals[indices[t]]).normalized()
			if front.dot(stored) < 0.99:
				_issue(issues, "winding", "%s triangle faces against its normal" % component.describe(), a)
			total += 1
			if front.is_equal_approx(Vector3.UP) and absf(a.y - ground_y) < EPS:
				_issue(issues, "zfight", "%s has an upward face on the ground plane" % component.describe(), a)
			var plane_key := "%.3f,%.3f,%.3f|%.4f" % [_q(front.x, 0.001), _q(front.y, 0.001), _q(front.z, 0.001), _q(front.dot(a), 0.0001)]
			if not planes.has(plane_key):
				planes[plane_key] = []
			(planes[plane_key] as Array).append([component, a, b, c, front])
	var reported := {}
	for list: Array in planes.values():
		for i in list.size():
			for j in range(i + 1, list.size()):
				var ta: Array = list[i]
				var tb: Array = list[j]
				var ca: BuildComponent = ta[0]
				var cb: BuildComponent = tb[0]
				if ca.id == cb.id:
					continue
				var pair := Vector2i(mini(ca.id, cb.id), maxi(ca.id, cb.id))
				if reported.has(pair):
					continue
				var area := _overlap_area(ta, tb)
				if area > AREA_EPS:
					reported[pair] = true
					_issue(issues, "zfight", "%s and %s have coplanar overlapping faces (%.5f m2)" % [ca.describe(), cb.describe(), area], ta[1])
	return total


## Snapped value with negative zero folded into zero, for stable bucket keys.
static func _q(value: float, step: float) -> float:
	return snappedf(value, step) + 0.0


static func _overlap_area(ta: Array, tb: Array) -> float:
	var normal: Vector3 = ta[4]
	var axis := 0
	if absf(normal.y) >= absf(normal.x) and absf(normal.y) >= absf(normal.z):
		axis = 1
	elif absf(normal.z) >= absf(normal.x):
		axis = 2
	var pa := PackedVector2Array([_flat(ta[1], axis), _flat(ta[2], axis), _flat(ta[3], axis)])
	var pb := PackedVector2Array([_flat(tb[1], axis), _flat(tb[2], axis), _flat(tb[3], axis)])
	if not _bounds(pa).intersects(_bounds(pb)):
		return 0.0
	var clipped := _clip(pa, pb)
	return absf(_area(clipped))


static func _flat(point: Vector3, axis: int) -> Vector2:
	if axis == 0:
		return Vector2(point.y, point.z)
	if axis == 1:
		return Vector2(point.x, point.z)
	return Vector2(point.x, point.y)


static func _bounds(points: PackedVector2Array) -> Rect2:
	var rect := Rect2(points[0], Vector2.ZERO)
	for point in points:
		rect = rect.expand(point)
	return rect


static func _area(points: PackedVector2Array) -> float:
	var total := 0.0
	for i in points.size():
		var p := points[i]
		var q := points[(i + 1) % points.size()]
		total += p.x * q.y - q.x * p.y
	return total * 0.5


## Sutherland-Hodgman: subject clipped by a convex clip polygon.
static func _clip(subject: PackedVector2Array, clip: PackedVector2Array) -> PackedVector2Array:
	var output := subject
	var orientation := signf(_area(clip))
	if orientation == 0.0:
		return PackedVector2Array()
	for i in clip.size():
		if output.is_empty():
			break
		var edge_a := clip[i]
		var edge_b := clip[(i + 1) % clip.size()]
		var input := output
		output = PackedVector2Array()
		for k in input.size():
			var current := input[k]
			var previous := input[(k + input.size() - 1) % input.size()]
			var current_in := _side(edge_a, edge_b, current) * orientation >= 0.0
			var previous_in := _side(edge_a, edge_b, previous) * orientation >= 0.0
			if current_in:
				if not previous_in:
					output.append(_cross_point(previous, current, edge_a, edge_b))
				output.append(current)
			elif previous_in:
				output.append(_cross_point(previous, current, edge_a, edge_b))
	return output


static func _side(a: Vector2, b: Vector2, p: Vector2) -> float:
	return (b - a).cross(p - a)


static func _cross_point(p: Vector2, q: Vector2, a: Vector2, b: Vector2) -> Vector2:
	var r := q - p
	var s := b - a
	var denom := r.cross(s)
	if absf(denom) < 1e-12:
		return q
	var t := (a - p).cross(s) / denom
	return p + r * t


# --- joints, graph, preview ----------------------------------------------------

static func _check_joints(system: BuildingSystem, issues: Array) -> void:
	var state := system.state
	for component: BuildComponent in state.components.values():
		if BuildTypes.is_edge_kind(component.kind):
			var key: Vector4i = component.key
			var axis := 0 if key.w == BuildTypes.AXIS_X else 2
			var box := system.geometry.world_aabb(component.kind, system.grid.edge_transform(key))
			var ends := GridSystem.edge_vertices(key)
			for i in 2:
				var post := state.get_component(state.post_at(GridSystem.post_key(ends[i], key.z)))
				if post == null:
					_issue(issues, "gap", "%s has no post at %s" % [component.describe(), ends[i]], box.get_center())
					continue
				var post_box := system.geometry.world_aabb(BuildTypes.Kind.POST, system.grid.post_transform(post.key))
				var wall_end := box.position[axis] if i == 0 else box.end[axis]
				var post_face := post_box.end[axis] if i == 0 else post_box.position[axis]
				if absf(wall_end - post_face) > EPS:
					_issue(issues, "gap", "%s does not meet its post flush (%.4f)" % [component.describe(), wall_end - post_face], box.get_center())
		elif component.kind == BuildTypes.Kind.POST and not component.pinned:
			var key: Vector3i = component.key
			if not state.vertex_has_edges(Vector2i(key.x, key.z), key.y):
				_issue(issues, "orphan", "%s carries no wall" % component.describe())


static func _check_graph(state: BuildingState, issues: Array) -> void:
	for component_id in state.components.keys():
		var links := state.graph.neighbours(int(component_id))
		for other in links.keys():
			var back := state.graph.neighbours(int(other))
			if not back.has(component_id) or int(back[component_id]) != ConstructionGraph.mirror(int(links[other])):
				_issue(issues, "graph", "link #%d -> #%d is not mirrored" % [int(component_id), int(other)])


static func _check_floors(state: BuildingState, issues: Array) -> void:
	for component: BuildComponent in state.components.values():
		if BuildTypes.is_edge_kind(component.kind) and not state.edge_has_floor(component.key):
			_issue(issues, "floor", "%s has no floor slab beside it" % component.describe())


static func _check_preview(system: BuildingSystem, issues: Array) -> void:
	var stack: Array[Node] = [system.preview_root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node is CollisionObject3D:
			_issue(issues, "preview", "preview node %s has a physics body" % node.name)
		stack.append_array(node.get_children())
