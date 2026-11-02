extends RefCounted
class_name TextureCompare

## One small building per tier on the north side of the building pad.
## These are the real floor, wall, pillar, doorway, and window meshes.
## They are not part of the building system, so they are not saved.

const HOUSES := [
	[1, "Scrap", -9],
	[2, "Wood", -6],
	[3, "Brick", -3],
	[4, "Stone", 0],
	[5, "Concrete", 3],
	[6, "Composite", 6],
]

const _NORTH := -9


static func build(arena: Node3D) -> void:
	if arena.get_node_or_null("TextureCompare") != null:
		return
	var root := Node3D.new()
	root.name = "TextureCompare"
	arena.add_child(root)
	var grid := GridSystem.new()
	var geometry := BuildingGeometry.new(grid.config)
	ShowcasePad.label(root, "COMPARE", Vector3(-0.5, 5.6, -9.8), 36, Color(0.86, 0.84, 0.72))
	for house in HOUSES:
		_house(root, grid, geometry, int(house[0]), str(house[1]), int(house[2]))


static func _house(root: Node3D, grid: GridSystem, geometry: BuildingGeometry, tier: int, title: String, ox: int) -> void:
	var oz := _NORTH
	for x in [ox, ox + 1]:
		for z in [oz, oz + 1]:
			_piece(root, grid, geometry, tier, BuildTypes.Kind.SLAB, GridSystem.slab_key(Vector2i(x, z), 0))
			_piece(root, grid, geometry, tier, BuildTypes.Kind.SLAB, GridSystem.slab_key(Vector2i(x, z), 1))
	var edges: Array[Array] = [
		[BuildTypes.Kind.WALL, Vector4i(ox, oz, 0, BuildTypes.AXIS_X)],
		[BuildTypes.Kind.WALL, Vector4i(ox + 1, oz, 0, BuildTypes.AXIS_X)],
		[BuildTypes.Kind.WALL, Vector4i(ox, oz, 0, BuildTypes.AXIS_Z)],
		[BuildTypes.Kind.WALL, Vector4i(ox, oz + 1, 0, BuildTypes.AXIS_Z)],
		[BuildTypes.Kind.WINDOW, Vector4i(ox + 2, oz, 0, BuildTypes.AXIS_Z)],
		[BuildTypes.Kind.WALL, Vector4i(ox + 2, oz + 1, 0, BuildTypes.AXIS_Z)],
		[BuildTypes.Kind.WALL, Vector4i(ox, oz + 2, 0, BuildTypes.AXIS_X)],
		[BuildTypes.Kind.DOORWAY, Vector4i(ox + 1, oz + 2, 0, BuildTypes.AXIS_X)],
	]
	var posts := {}
	for edge in edges:
		var key: Vector4i = edge[1]
		_piece(root, grid, geometry, tier, int(edge[0]), key)
		for vertex in GridSystem.edge_vertices(key):
			posts[GridSystem.post_key(vertex, key.z)] = true
	for key: Vector3i in posts:
		_piece(root, grid, geometry, tier, BuildTypes.Kind.POST, key)
	ShowcasePad.label(root, title, Vector3(ox + 1.0, 4.3, oz + 1.0), 28, Color(0.9, 0.88, 0.78))


static func _piece(root: Node3D, grid: GridSystem, geometry: BuildingGeometry, tier: int, kind: int, key: Variant) -> void:
	var mesh := MeshInstance3D.new()
	mesh.mesh = geometry.mesh_for(kind, 0)
	mesh.transform = grid.transform_for(kind, key)
	var material := BuildingTier.make_material(tier, kind)
	BuildingTier.align_repeat(material, tier, kind, mesh.transform)
	mesh.set_surface_override_material(0, material)
	root.add_child(mesh)
