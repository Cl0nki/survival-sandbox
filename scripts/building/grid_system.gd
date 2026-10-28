extends RefCounted
class_name GridSystem

## World-to-grid conversion, canonical slot keys, and canonical transforms.
##
## Conventions
## - Cell (x, z) covers world [x, x+1) * cell_size by [z, z+1) * cell_size
##   relative to grid_origin. North is -Z.
## - Level L starts at grid_origin.y + L * floor_height.
## - Slab key Vector3i(x, L, z). Post key Vector3i(vx, L, vz) on grid vertices.
##   Edge key Vector4i(x, z, L, axis). Stairs key Vector4i(ax, az, L, rotation).
## - Footprint math uses a doubled integer lattice so rotation stays exact:
##   cells are (odd, odd), vertices (even, even), AXIS_X edge midpoints
##   (odd, even), AXIS_Z edge midpoints (even, odd).
## - A rotation step maps doubled (a, b) to (-b, a). In world space that is a
##   yaw of -90 degrees. Bases are built from exact 0 / 1 / -1 entries.
## Transforms are always computed from keys; nothing accumulates offsets.

var config: BuildingConfig


func _init(building_config: BuildingConfig = null) -> void:
	config = building_config if building_config != null else BuildingConfig.new()


# --- keys -------------------------------------------------------------------

static func slab_key(cell: Vector2i, level: int) -> Vector3i:
	return Vector3i(cell.x, level, cell.y)


static func post_key(vertex: Vector2i, level: int) -> Vector3i:
	return Vector3i(vertex.x, level, vertex.y)


static func edge_key(x: int, z: int, level: int, axis: int) -> Vector4i:
	return Vector4i(x, z, level, axis)


static func key_cell(key: Vector3i) -> Vector2i:
	return Vector2i(key.x, key.z)


static func side_edge(cell: Vector2i, side: int, level: int) -> Vector4i:
	match side:
		BuildTypes.Side.NORTH:
			return Vector4i(cell.x, cell.y, level, BuildTypes.AXIS_X)
		BuildTypes.Side.SOUTH:
			return Vector4i(cell.x, cell.y + 1, level, BuildTypes.AXIS_X)
		BuildTypes.Side.WEST:
			return Vector4i(cell.x, cell.y, level, BuildTypes.AXIS_Z)
		_:
			return Vector4i(cell.x + 1, cell.y, level, BuildTypes.AXIS_Z)


static func cell_edges(cell: Vector2i, level: int) -> Array[Vector4i]:
	var result: Array[Vector4i] = []
	for side in 4:
		result.append(side_edge(cell, side, level))
	return result


static func cell_vertices(cell: Vector2i) -> Array[Vector2i]:
	return [cell, Vector2i(cell.x + 1, cell.y), Vector2i(cell.x, cell.y + 1), cell + Vector2i.ONE]


static func edge_vertices(key: Vector4i) -> Array[Vector2i]:
	match key.w:
		BuildTypes.AXIS_X:
			return [Vector2i(key.x, key.y), Vector2i(key.x + 1, key.y)]
		BuildTypes.AXIS_Z:
			return [Vector2i(key.x, key.y), Vector2i(key.x, key.y + 1)]
		BuildTypes.AXIS_DIAG_POS:
			return [Vector2i(key.x, key.y), Vector2i(key.x + 1, key.y + 1)]
		_:
			return [Vector2i(key.x + 1, key.y), Vector2i(key.x, key.y + 1)]


## The two cells a straight edge separates: north then south for AXIS_X,
## west then east for AXIS_Z.
static func edge_cells(key: Vector4i) -> Array[Vector2i]:
	if key.w == BuildTypes.AXIS_X:
		return [Vector2i(key.x, key.y - 1), Vector2i(key.x, key.y)]
	return [Vector2i(key.x - 1, key.y), Vector2i(key.x, key.y)]


## Cells on the local -Z side and the local +Z side of the edge transform.
static func edge_local_side_cells(key: Vector4i) -> Array[Vector2i]:
	if key.w == BuildTypes.AXIS_X:
		return [Vector2i(key.x, key.y - 1), Vector2i(key.x, key.y)]
	return [Vector2i(key.x, key.y), Vector2i(key.x - 1, key.y)]


## Quadrant order matches post bottom masks: (-x,-z), (+x,-z), (-x,+z), (+x,+z).
static func vertex_cells(vertex: Vector2i) -> Array[Vector2i]:
	return [
		Vector2i(vertex.x - 1, vertex.y - 1),
		Vector2i(vertex.x, vertex.y - 1),
		Vector2i(vertex.x - 1, vertex.y),
		vertex,
	]


static func vertex_edges(vertex: Vector2i, level: int) -> Array[Vector4i]:
	return [
		Vector4i(vertex.x - 1, vertex.y, level, BuildTypes.AXIS_X),
		Vector4i(vertex.x, vertex.y, level, BuildTypes.AXIS_X),
		Vector4i(vertex.x, vertex.y - 1, level, BuildTypes.AXIS_Z),
		Vector4i(vertex.x, vertex.y, level, BuildTypes.AXIS_Z),
	]


# --- doubled lattice ---------------------------------------------------------

static func rotate_doubled(point: Vector2i, steps: int) -> Vector2i:
	var result := point
	for _i in posmod(steps, 4):
		result = Vector2i(-result.y, result.x)
	return result


static func rotated_size(size: Vector2i, steps: int) -> Vector2i:
	if posmod(steps, 2) == 1:
		return Vector2i(size.y, size.x)
	return size


## Doubled offset that moves a rotated footprint back so its minimum corner is
## the local origin. The anchor is always the minimum cell of the footprint.
static func footprint_offset(size: Vector2i, steps: int) -> Vector2i:
	var corners: Array[Vector2i] = [Vector2i(0, 0), Vector2i(size.x * 2, 0), Vector2i(0, size.y * 2), size * 2]
	var lowest := Vector2i(1 << 30, 1 << 30)
	for corner in corners:
		var turned := rotate_doubled(corner, steps)
		lowest = Vector2i(mini(lowest.x, turned.x), mini(lowest.y, turned.y))
	return -lowest


static func to_world_doubled(local_doubled: Vector2i, size: Vector2i, steps: int, anchor: Vector2i) -> Vector2i:
	return rotate_doubled(local_doubled, steps) + footprint_offset(size, steps) + anchor * 2


static func cell_to_doubled(cell: Vector2i) -> Vector2i:
	return Vector2i(cell.x * 2 + 1, cell.y * 2 + 1)


static func doubled_to_cell(doubled: Vector2i) -> Vector2i:
	return Vector2i((doubled.x - 1) / 2, (doubled.y - 1) / 2)


static func side_doubled(cell: Vector2i, side: int) -> Vector2i:
	var center := cell_to_doubled(cell)
	match side:
		BuildTypes.Side.NORTH:
			return center + Vector2i(0, -1)
		BuildTypes.Side.SOUTH:
			return center + Vector2i(0, 1)
		BuildTypes.Side.WEST:
			return center + Vector2i(-1, 0)
		_:
			return center + Vector2i(1, 0)


static func local_cell_to_world(cell: Vector2i, size: Vector2i, steps: int, anchor: Vector2i) -> Vector2i:
	return doubled_to_cell(to_world_doubled(cell_to_doubled(cell), size, steps, anchor))


## Returns axis -1 in w when the doubled point is not an edge midpoint.
static func doubled_to_edge(doubled: Vector2i, level: int) -> Vector4i:
	var odd_x := posmod(doubled.x, 2) == 1
	var odd_z := posmod(doubled.y, 2) == 1
	if odd_x and not odd_z:
		return Vector4i((doubled.x - 1) / 2, doubled.y / 2, level, BuildTypes.AXIS_X)
	if odd_z and not odd_x:
		return Vector4i(doubled.x / 2, (doubled.y - 1) / 2, level, BuildTypes.AXIS_Z)
	return Vector4i(0, 0, level, -1)


static func edge_to_doubled(key: Vector4i) -> Vector2i:
	if key.w == BuildTypes.AXIS_X:
		return Vector2i(key.x * 2 + 1, key.y * 2)
	return Vector2i(key.x * 2, key.y * 2 + 1)


static func rotation_basis(steps: int) -> Basis:
	var x_axis := rotate_doubled(Vector2i(1, 0), steps)
	var z_axis := rotate_doubled(Vector2i(0, 1), steps)
	return Basis(
		Vector3(x_axis.x, 0, x_axis.y),
		Vector3(0, 1, 0),
		Vector3(z_axis.x, 0, z_axis.y)
	)


# --- world conversion --------------------------------------------------------

func level_y(level: int) -> float:
	return config.grid_origin.y + float(level) * config.floor_height


## Continuous grid coordinates of a world point, in cells.
func world_to_grid(point: Vector3) -> Vector2:
	return Vector2(
		(point.x - config.grid_origin.x) / config.cell_size,
		(point.z - config.grid_origin.z) / config.cell_size
	)


func world_to_cell(point: Vector3) -> Vector2i:
	var g := world_to_grid(point)
	return Vector2i(floori(g.x), floori(g.y))


func doubled_to_world(doubled: Vector2i, level: int) -> Vector3:
	var half := config.cell_size * 0.5
	return Vector3(
		config.grid_origin.x + float(doubled.x) * half,
		level_y(level),
		config.grid_origin.z + float(doubled.y) * half
	)


func level_for_height(y: float) -> int:
	return maxi(floori((y - config.grid_origin.y) / config.floor_height + 0.05), 0)


func in_bounds(cell: Vector2i) -> bool:
	return (
		cell.x >= config.build_min_cell.x and cell.y >= config.build_min_cell.y
		and cell.x <= config.build_max_cell.x and cell.y <= config.build_max_cell.y
	)


# --- canonical transforms ----------------------------------------------------

func slab_transform(key: Vector3i) -> Transform3D:
	return Transform3D(Basis.IDENTITY, doubled_to_world(cell_to_doubled(Vector2i(key.x, key.z)), key.y))


func post_transform(key: Vector3i) -> Transform3D:
	return Transform3D(Basis.IDENTITY, doubled_to_world(Vector2i(key.x * 2, key.z * 2), key.y))


func edge_transform(key: Vector4i) -> Transform3D:
	var basis := Basis.IDENTITY if key.w == BuildTypes.AXIS_X else rotation_basis(1)
	return Transform3D(basis, doubled_to_world(edge_to_doubled(key), key.z))


const STAIRS_SIZE := Vector2i(1, 3)

## Stairs origin sits on the floor slab top at the footprint centre.
func stairs_transform(key: Vector4i) -> Transform3D:
	var centre := to_world_doubled(STAIRS_SIZE, STAIRS_SIZE, key.w, Vector2i(key.x, key.y))
	var origin := doubled_to_world(centre, key.z)
	origin.y += config.slab_thickness
	return Transform3D(rotation_basis(key.w), origin)


func component_transform(component: BuildComponent) -> Transform3D:
	match component.kind:
		BuildTypes.Kind.SLAB:
			return slab_transform(component.key)
		BuildTypes.Kind.POST:
			return post_transform(component.key)
		BuildTypes.Kind.STAIRS:
			return stairs_transform(component.key)
		_:
			return edge_transform(component.key)


func transform_for(kind: int, key: Variant) -> Transform3D:
	match kind:
		BuildTypes.Kind.SLAB:
			return slab_transform(key)
		BuildTypes.Kind.POST:
			return post_transform(key)
		BuildTypes.Kind.STAIRS:
			return stairs_transform(key)
		_:
			return edge_transform(key)
