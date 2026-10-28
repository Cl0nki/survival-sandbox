extends RefCounted
class_name BuildingGeometry

## Module geometry derived from BuildingConfig. Visual meshes, collision
## shapes, preview ghosts, outlines, and the geometry audit all read the same
## part boxes, so visuals and collision cannot drift apart.
##
## Local frames (see GridSystem for the node transforms):
## - Slab: cell centre, y from 0 to slab_thickness.
## - Wall / doorway / window: edge midpoint, runs along local X between the
##   two corner posts (length cell_size - wall_thickness), local Z is thickness,
##   y from 0 to floor_height.
## - Post: vertex, wall_thickness square, y from 0 to floor_height.
## - Stairs: footprint centre on the floor slab top, climbs toward local -Z.
##
## Connection rules:
## - Vertical pieces pass through the slab of their own level (allowed overlap).
## - Wall ends meet posts face to face; posts own the corner square, so walls
##   never overlap each other at corners.
## - Faces that touch with opposite normals are allowed: from any viewpoint one
##   of them is back-facing and culled, so they cannot fight.
## - A vertical piece's bottom face would be coplanar with the bottom of a slab
##   on its level. Those bottom faces are split per adjacent cell and omitted
##   where that cell has a slab (the "bottom mask").

const MASK_FULL := -1
## Godot treats clockwise triangles as front-facing.
const CLOCKWISE_FRONT := true

var config: BuildingConfig
var _meshes: Dictionary = {}
var _outlines: Dictionary = {}
var _shapes: Dictionary = {}
var _materials: Dictionary = {}


func _init(building_config: BuildingConfig = null) -> void:
	config = building_config if building_config != null else BuildingConfig.new()


func parts(kind: int) -> Array[AABB]:
	var s := config.cell_size
	var t := config.wall_thickness
	var h := config.floor_height
	var span := s - t
	match kind:
		BuildTypes.Kind.SLAB:
			return [AABB(Vector3(-s * 0.5, 0.0, -s * 0.5), Vector3(s, config.slab_thickness, s))]
		BuildTypes.Kind.WALL:
			return [AABB(Vector3(-span * 0.5, 0.0, -t * 0.5), Vector3(span, h, t))]
		BuildTypes.Kind.DOORWAY:
			return [AABB(Vector3(-span * 0.5, config.door_height, -t * 0.5), Vector3(span, h - config.door_height, t))]
		BuildTypes.Kind.WINDOW:
			return [
				AABB(Vector3(-span * 0.5, 0.0, -t * 0.5), Vector3(span, config.window_sill_height, t)),
				AABB(Vector3(-span * 0.5, config.window_head_height, -t * 0.5), Vector3(span, h - config.window_head_height, t)),
			]
		BuildTypes.Kind.POST:
			return [AABB(Vector3(-t * 0.5, 0.0, -t * 0.5), Vector3(t, h, t))]
	return []


## Wedge corners: bottom rectangle b0..b3, then the two top corners.
func stairs_points() -> PackedVector3Array:
	var w := (config.cell_size - config.wall_thickness) * 0.5
	var half_run := config.cell_size * float(GridSystem.STAIRS_SIZE.y) * 0.5
	var rise := config.floor_height
	return PackedVector3Array([
		Vector3(-w, 0.0, half_run),
		Vector3(w, 0.0, half_run),
		Vector3(w, 0.0, -half_run),
		Vector3(-w, 0.0, -half_run),
		Vector3(w, rise, -half_run),
		Vector3(-w, rise, -half_run),
	])


func local_aabb(kind: int) -> AABB:
	if kind == BuildTypes.Kind.STAIRS:
		var points := stairs_points()
		var box := AABB(points[0], Vector3.ZERO)
		for point in points:
			box = box.expand(point)
		return box
	var boxes := parts(kind)
	var result := boxes[0]
	for box in boxes:
		result = result.merge(box)
	return result


func world_aabb(kind: int, xform: Transform3D) -> AABB:
	return xform * local_aabb(kind)


static func full_mask(kind: int) -> int:
	if kind == BuildTypes.Kind.POST:
		return 15
	if kind == BuildTypes.Kind.WALL or kind == BuildTypes.Kind.WINDOW:
		return 3
	return 0


static func uses_bottom_mask(kind: int) -> bool:
	return full_mask(kind) != 0


func mesh_for(kind: int, mask: int = MASK_FULL) -> ArrayMesh:
	if mask < 0 or not uses_bottom_mask(kind):
		mask = full_mask(kind)
	var cache_key := "%d:%d" % [kind, mask]
	if _meshes.has(cache_key):
		return _meshes[cache_key]
	var builder := _Builder.new()
	match kind:
		BuildTypes.Kind.STAIRS:
			_add_wedge(builder)
		BuildTypes.Kind.POST:
			var box := parts(kind)[0]
			_add_box(builder, box, _post_bottom(box, mask))
		BuildTypes.Kind.WALL, BuildTypes.Kind.WINDOW:
			var boxes := parts(kind)
			for i in boxes.size():
				var rests_on_level := is_zero_approx(boxes[i].position.y)
				_add_box(builder, boxes[i], _edge_bottom(boxes[i], mask) if rests_on_level else [])
		_:
			for box in parts(kind):
				_add_box(builder, box, [])
	var mesh := builder.commit()
	mesh.surface_set_material(0, material_for(kind))
	_meshes[cache_key] = mesh
	return mesh


func outline_mesh(kind: int) -> ArrayMesh:
	if _outlines.has(kind):
		return _outlines[kind]
	var lines := PackedVector3Array()
	if kind == BuildTypes.Kind.STAIRS:
		var p := stairs_points()
		for pair: Array in [[0, 1], [1, 2], [2, 3], [3, 0], [2, 4], [3, 5], [4, 5], [0, 5], [1, 4]]:
			lines.append(p[pair[0]])
			lines.append(p[pair[1]])
	else:
		for box in parts(kind):
			_box_lines(lines, box)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = lines
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arrays)
	_outlines[kind] = mesh
	return mesh


## [Shape3D, local Transform3D] pairs. Shape resources are shared.
func collision_shapes(kind: int) -> Array:
	var result: Array = []
	if kind == BuildTypes.Kind.STAIRS:
		if not _shapes.has("stairs"):
			var hull := ConvexPolygonShape3D.new()
			hull.points = stairs_points()
			_shapes["stairs"] = hull
		result.append([_shapes["stairs"], Transform3D.IDENTITY])
		return result
	for box in parts(kind):
		var size_key := "box:%s" % str(box.size)
		if not _shapes.has(size_key):
			var shape := BoxShape3D.new()
			shape.size = box.size
			_shapes[size_key] = shape
		result.append([_shapes[size_key], Transform3D(Basis.IDENTITY, box.get_center())])
	return result


func material_for(kind: int) -> StandardMaterial3D:
	if _materials.has(kind):
		return _materials[kind]
	var material := StandardMaterial3D.new()
	material.roughness = 0.9
	match kind:
		BuildTypes.Kind.SLAB:
			material.albedo_color = Color(0.52, 0.47, 0.41)
		BuildTypes.Kind.POST:
			material.albedo_color = Color(0.46, 0.40, 0.34)
		BuildTypes.Kind.STAIRS:
			material.albedo_color = Color(0.58, 0.48, 0.36)
		_:
			material.albedo_color = Color(0.80, 0.76, 0.68)
	_materials[kind] = material
	return material


# --- mesh construction -------------------------------------------------------

func _edge_bottom(box: AABB, mask: int) -> Array:
	var rects: Array = []
	var x0 := box.position.x
	var x1 := box.end.x
	if mask & 1:
		rects.append(Rect2(x0, box.position.z, x1 - x0, -box.position.z))
	if mask & 2:
		rects.append(Rect2(x0, 0.0, x1 - x0, box.end.z))
	return rects


func _post_bottom(box: AABB, mask: int) -> Array:
	var rects: Array = []
	var half_x := -box.position.x
	var half_z := -box.position.z
	var origins: Array[Vector2] = [Vector2(-half_x, -half_z), Vector2(0.0, -half_z), Vector2(-half_x, 0.0), Vector2(0.0, 0.0)]
	for i in 4:
		if mask & (1 << i):
			rects.append(Rect2(origins[i], Vector2(half_x, half_z)))
	return rects


## bottom_rects: Rect2 list in the XZ plane. Empty array with a resting box
## means no bottom face at all.
func _add_box(builder: _Builder, box: AABB, bottom_rects: Array) -> void:
	var a := box.position
	var b := box.end
	builder.quad(Vector3(b.x, a.y, a.z), Vector3(b.x, a.y, b.z), Vector3(b.x, b.y, b.z), Vector3(b.x, b.y, a.z), Vector3.RIGHT)
	builder.quad(Vector3(a.x, a.y, a.z), Vector3(a.x, b.y, a.z), Vector3(a.x, b.y, b.z), Vector3(a.x, a.y, b.z), Vector3.LEFT)
	builder.quad(Vector3(a.x, b.y, a.z), Vector3(b.x, b.y, a.z), Vector3(b.x, b.y, b.z), Vector3(a.x, b.y, b.z), Vector3.UP)
	builder.quad(Vector3(a.x, a.y, b.z), Vector3(a.x, b.y, b.z), Vector3(b.x, b.y, b.z), Vector3(b.x, a.y, b.z), Vector3.BACK)
	builder.quad(Vector3(a.x, a.y, a.z), Vector3(b.x, a.y, a.z), Vector3(b.x, b.y, a.z), Vector3(a.x, b.y, a.z), Vector3.FORWARD)
	var rests_on_level := is_zero_approx(a.y) and uses_bottom_mask_for_box(box)
	if not rests_on_level:
		builder.quad(Vector3(a.x, a.y, a.z), Vector3(a.x, a.y, b.z), Vector3(b.x, a.y, b.z), Vector3(b.x, a.y, a.z), Vector3.DOWN)
		return
	for item in bottom_rects:
		var r: Rect2 = item
		var y := a.y
		builder.quad(
			Vector3(r.position.x, y, r.position.y),
			Vector3(r.position.x, y, r.end.y),
			Vector3(r.end.x, y, r.end.y),
			Vector3(r.end.x, y, r.position.y),
			Vector3.DOWN
		)


## Slabs always keep their full bottom; only vertical pieces use bottom masks.
func uses_bottom_mask_for_box(box: AABB) -> bool:
	return box.size.y > config.slab_thickness * 2.0


func _add_wedge(builder: _Builder) -> void:
	var p := stairs_points()
	builder.quad(p[0], p[3], p[2], p[1], Vector3.DOWN)
	builder.quad(p[2], p[3], p[5], p[4], Vector3.FORWARD)
	var slope := Vector3(0.0, p[0].z - p[3].z, p[4].y).normalized()
	builder.quad(p[0], p[1], p[4], p[5], slope)
	builder.triangle(p[1], p[2], p[4], Vector3.RIGHT)
	builder.triangle(p[0], p[5], p[3], Vector3.LEFT)


static func _box_lines(lines: PackedVector3Array, box: AABB) -> void:
	var a := box.position
	var b := box.end
	var c: Array[Vector3] = [
		Vector3(a.x, a.y, a.z), Vector3(b.x, a.y, a.z), Vector3(b.x, a.y, b.z), Vector3(a.x, a.y, b.z),
		Vector3(a.x, b.y, a.z), Vector3(b.x, b.y, a.z), Vector3(b.x, b.y, b.z), Vector3(a.x, b.y, b.z),
	]
	for pair: Array in [[0, 1], [1, 2], [2, 3], [3, 0], [4, 5], [5, 6], [6, 7], [7, 4], [0, 4], [1, 5], [2, 6], [3, 7]]:
		lines.append(c[pair[0]])
		lines.append(c[pair[1]])


class _Builder:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()

	func quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, normal: Vector3) -> void:
		var start := vertices.size()
		for point in [a, b, c, d]:
			vertices.append(point)
			normals.append(normal)
		var ccw_from_front := (b - a).cross(c - a).dot(normal) > 0.0
		if ccw_from_front == BuildingGeometry.CLOCKWISE_FRONT:
			indices.append_array([start, start + 2, start + 1, start, start + 3, start + 2])
		else:
			indices.append_array([start, start + 1, start + 2, start, start + 2, start + 3])

	func triangle(a: Vector3, b: Vector3, c: Vector3, normal: Vector3) -> void:
		var start := vertices.size()
		for point in [a, b, c]:
			vertices.append(point)
			normals.append(normal)
		var ccw_from_front := (b - a).cross(c - a).dot(normal) > 0.0
		if ccw_from_front == BuildingGeometry.CLOCKWISE_FRONT:
			indices.append_array([start, start + 2, start + 1])
		else:
			indices.append_array([start, start + 1, start + 2])

	func commit() -> ArrayMesh:
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = vertices
		arrays[Mesh.ARRAY_NORMAL] = normals
		arrays[Mesh.ARRAY_INDEX] = indices
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		return mesh
