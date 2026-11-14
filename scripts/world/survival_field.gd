extends RefCounted
class_name SurvivalField

## Open survival yard built from reusable BiomeCatalog entries.
## Layout is a list of placements; BiomePlacer handles random props/harvestables.

const HALF := 40.0
const WALL_THICKNESS := 0.5
const WALL_HEIGHT := 3.0
## Deterministic seed — placement looks random but stays stable across boots.
const MAP_SEED := 0x5A17F1E1

## Starter wood hut on the meadow. Door faces south.
const HOUSE_ANCHOR := Vector2i(-8, 6)
const HOUSE_SIZE := Vector2i(4, 4)
const HOUSE_WOOD_TIER := 2
## Interior floor cell (clear of walls/door) for the seeded workbench.
const HOUSE_BENCH_CELL := Vector2i(-6, 7)

## Non-overlapping tiles covering the yard (N=-Z, E=+X). No gaps, no bleed:
##   [Oak ][==== Hills ====]
##   [Birch][Meadow][Wasteland]
##   [Spruce][Meadow][City ]
## Each entry: [biome_id, center, Vector2(width_x, depth_z)]
const PLACEMENTS := [
	["forest_oak", Vector3(-26.0, 0.0, -27.0), Vector2(28.0, 26.0)],
	["forest_birch", Vector3(-26.0, 0.0, -1.0), Vector2(28.0, 26.0)],
	["forest_spruce", Vector3(-26.0, 0.0, 26.0), Vector2(28.0, 28.0)],
	["hills", Vector3(14.0, 0.0, -27.0), Vector2(52.0, 26.0)],
	["meadow", Vector3(2.0, 0.0, 13.0), Vector2(28.0, 54.0)],
	["wasteland", Vector3(28.0, 0.0, -1.0), Vector2(24.0, 26.0)],
	["city", Vector3(28.0, 0.0, 26.0), Vector2(24.0, 28.0)],
]


static func build(arena: Node3D) -> void:
	if arena.get_node_or_null("Survival") != null:
		return
	_resize_bounds(arena, HALF)
	_paint_floor(arena)
	_discard_dummy(arena, "OpenDummy")
	_discard_dummy(arena, "CoveredDummy")
	var root := Node3D.new()
	root.name = "Survival"
	arena.add_child(root)
	_ensure_loot(arena)
	var paint := _place_biomes(root)
	GroundSplat.build_survival(
		arena,
		paint.get("regions", []),
		paint.get("soil", []),
		paint.get("stain", []),
		paint.get("asphalt", []),
		paint.get("forest", [])
	)
	_starter_tools(arena)


## Wood room + doorway + door + workbench. Skips the shell if buildings already exist.
static func seed_starter_house(arena: Node3D) -> void:
	if arena == null:
		return
	var building := arena.get_node_or_null("BuildingSystem") as BuildingSystem
	var deployables := arena.get_node_or_null("DeployableSystem") as DeployableSystem
	if building == null or building.authority == null or deployables == null:
		return
	if building.state != null and building.state.component_count() == 0:
		var room: Dictionary = building.authority.request_place(RoomPlacer.make_request(
			"room", HOUSE_ANCHOR, 0, 0, 0, 0, HOUSE_SIZE, HOUSE_WOOD_TIER
		))
		if not bool(room.get("ok", false)):
			push_error("starter house refused: %s" % str(room.get("reason", "")))
			return
		var door_cell := Vector2i(HOUSE_ANCHOR.x + HOUSE_SIZE.x / 2, HOUSE_ANCHOR.y + HOUSE_SIZE.y - 1)
		var door_edge := GridSystem.side_edge(door_cell, BuildTypes.Side.SOUTH, 0)
		var opening: Dictionary = building.authority.request_place(RoomPlacer.make_request(
			"doorway",
			Vector2i(door_edge.x, door_edge.y),
			0,
			door_edge.z,
			door_edge.w,
			0,
			Vector2i.ZERO,
			HOUSE_WOOD_TIER
		))
		if not bool(opening.get("ok", false)):
			push_error("starter doorway refused: %s" % str(opening.get("reason", "")))
		else:
			var door: Dictionary = deployables.try_place_edge("door_wood", door_edge)
			if not bool(door.get("ok", false)):
				push_error("starter door refused: %s" % str(door.get("reason", "")))
	_place_hut_workbench(deployables)


static func _place_hut_workbench(deployables: DeployableSystem) -> void:
	var probe: Dictionary = deployables.plan_cells("workbench", HOUSE_BENCH_CELL, 0, 0)
	if bool(probe.get("ok", false)):
		var bench: Dictionary = deployables.try_place("workbench", HOUSE_BENCH_CELL, 0, 0)
		if bool(bench.get("ok", false)):
			return
		push_error("starter workbench refused: %s" % str(bench.get("reason", "")))
		return
	var reason := str(probe.get("reason", ""))
	## Already occupied by a prior seed is fine.
	if reason.begins_with("Blocked by"):
		return
	push_error("starter workbench refused: %s" % reason)


static func _place_biomes(root: Node3D) -> Dictionary:
	var regions: Array = []
	var soil: Array = []
	var stain: Array = []
	var asphalt: Array = []
	var forest: Array = []
	var exclude := _hut_exclude_rects()
	for index in PLACEMENTS.size():
		var entry: Array = PLACEMENTS[index]
		var biome_id := str(entry[0])
		var center: Vector3 = entry[1]
		var extent: Vector2 = entry[2]
		var biome := BiomeCatalog.get_biome(biome_id)
		if biome == null:
			push_error("survival missing biome %s" % biome_id)
			continue
		var seed := MAP_SEED ^ int(hash(biome_id)) ^ (index * 7919)
		var placed := BiomePlacer.place(root, biome, center, extent, seed, exclude)
		regions.append_array(placed.get("regions", []))
		soil.append_array(placed.get("soil", []))
		stain.append_array(placed.get("stain", []))
		asphalt.append_array(placed.get("asphalt", []))
		forest.append_array(placed.get("forest", []))
		var zone: Node3D = placed.get("zone") as Node3D
		if zone != null:
			_collect_deposit_paint(zone, soil, stain)
	return {
		"regions": regions,
		"soil": soil,
		"stain": stain,
		"asphalt": asphalt,
		"forest": forest,
	}


static func _collect_deposit_paint(zone: Node3D, soil: Array, stain: Array) -> void:
	for child in zone.get_children():
		var deposit := child as GroundDeposit
		if deposit == null:
			continue
		var paint := BiomePlacer.deposit_splat(deposit)
		soil.append_array(paint.get("soil", []))
		stain.append_array(paint.get("stain", []))


static func _hut_exclude_rects() -> Array:
	## Keep harvestables out of the hut footprint and starter tool strip.
	var hut := Rect2(
		Vector2(float(HOUSE_ANCHOR.x) - 1.5, float(HOUSE_ANCHOR.y) - 1.5),
		Vector2(float(HOUSE_SIZE.x) + 3.0, float(HOUSE_SIZE.y) + 3.0)
	)
	var tools := Rect2(Vector2(-6.0, 10.0), Vector2(12.0, 4.0))
	return [hut, tools]


static func _ensure_loot(arena: Node3D) -> void:
	if arena.get_node_or_null("Loot") != null:
		return
	var folder := Node3D.new()
	folder.name = "Loot"
	arena.add_child(folder)


static func _starter_tools(arena: Node3D) -> void:
	var loot := arena.get_node_or_null("Loot") as Node3D
	if loot == null:
		return
	## Starter tools + supplies that harvest nodes do not already provide.
	var tools := [
		["surv_hatchet_scrap", "hatchet_scrap", Vector3(-4.0, 0.15, 12.0)],
		["surv_pickaxe_scrap", "pickaxe_scrap", Vector3(-2.5, 0.15, 12.0)],
		["surv_crowbar_scrap", "crowbar_scrap", Vector3(-1.0, 0.15, 12.0)],
		["surv_shovel_scrap", "shovel_scrap", Vector3(0.5, 0.15, 12.0)],
		["surv_cloth_pile", "cloth", Vector3(2.5, 0.15, 12.0)],
		["surv_food_pile", "canned_food", Vector3(4.0, 0.15, 12.0)],
	]
	for entry in tools:
		_pickup(loot, str(entry[0]), str(entry[1]), 1 if str(entry[1]).ends_with("_scrap") else 8, entry[2])


static func _resize_bounds(arena: Node3D, half: float) -> void:
	var span := half * 2.0
	_set_box(arena, "Geometry/Floor", Vector3(span, 1.0, span), Vector3(0.0, -0.5, 0.0))
	_set_box(arena, "Geometry/WallNorth", Vector3(span, WALL_HEIGHT, WALL_THICKNESS), Vector3(0.0, WALL_HEIGHT * 0.5, -half))
	_set_box(arena, "Geometry/WallSouth", Vector3(span, WALL_HEIGHT, WALL_THICKNESS), Vector3(0.0, WALL_HEIGHT * 0.5, half))
	_set_box(arena, "Geometry/WallEast", Vector3(WALL_THICKNESS, WALL_HEIGHT, span), Vector3(half, WALL_HEIGHT * 0.5, 0.0))
	_set_box(arena, "Geometry/WallWest", Vector3(WALL_THICKNESS, WALL_HEIGHT, span), Vector3(-half, WALL_HEIGHT * 0.5, 0.0))


static func _set_box(arena: Node3D, path: String, size: Vector3, pos: Vector3) -> void:
	var body := arena.get_node_or_null(path) as StaticBody3D
	if body == null:
		return
	body.position = pos
	var mesh_node := body.get_node_or_null("Mesh") as MeshInstance3D
	if mesh_node != null and mesh_node.mesh is BoxMesh:
		var mesh := (mesh_node.mesh as BoxMesh).duplicate() as BoxMesh
		mesh.size = size
		mesh_node.mesh = mesh
	var shape_node := body.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if shape_node != null and shape_node.shape is BoxShape3D:
		var shape := (shape_node.shape as BoxShape3D).duplicate() as BoxShape3D
		shape.size = size
		shape_node.shape = shape


static func _paint_floor(arena: Node3D) -> void:
	var mesh_node := arena.get_node_or_null("Geometry/Floor/Mesh") as MeshInstance3D
	if mesh_node == null:
		return
	var material := StandardMaterial3D.new()
	ShowcasePad.paint(material, "ground_meadow", Vector2(HALF * 2.0, HALF * 2.0), Color(0.30, 0.42, 0.22))
	mesh_node.set_surface_override_material(0, material)


static func _discard_dummy(arena: Node3D, node_name: String) -> void:
	var node := arena.get_node_or_null(node_name)
	if node == null:
		return
	node.set_physics_process(false)
	node.set_process(false)
	node.process_mode = Node.PROCESS_MODE_DISABLED
	arena.remove_child(node)
	node.free()


static func _pickup(folder: Node3D, pickup_id: String, item_id: String, quantity: int, pos: Vector3) -> void:
	if folder.get_node_or_null(pickup_id) != null:
		return
	var pickup := WorldPickup.new()
	pickup.name = pickup_id
	pickup.pickup_id = pickup_id
	pickup.item_id = item_id
	pickup.quantity = quantity
	pickup.position = pos
	folder.add_child(pickup)
