extends RefCounted
class_name BiomePlacer

const _GroundScatter := preload("res://scripts/world/ground_scatter.gd")
## Reference area for density scaling (roughly a 22×22 biome).
const _REF_AREA := 484.0
## Keep props inside the biome rect (meters from the edge).
const _EDGE_INSET := 1.25

## Spawns one biome instance. Props stay inside `extent`; paint is that exact rect.


static func place(
	parent: Node3D,
	biome: BiomeDefinition,
	center: Vector3,
	extent,
	rng_seed: int,
	exclude_rects: Array = []
) -> Dictionary:
	var empty := {
		"zone": null,
		"regions": [],
		"soil": [],
		"stain": [],
		"asphalt": [],
		"forest": [],
	}
	var size := _as_extent(extent)
	if parent == null or biome == null or size.x <= 1.0 or size.y <= 1.0:
		return empty
	var zone := Node3D.new()
	zone.name = _zone_name(biome)
	zone.position = Vector3.ZERO
	parent.add_child(zone)
	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed
	var occupied: Array[Vector3] = []
	var bounds := _bounds_rect(center, size, _EDGE_INSET)
	if biome.spawn_props:
		_scatter(zone, biome, center, size)
		_spawn_harvestables(zone, biome, center, size, rng, exclude_rects, occupied, bounds)
		_spawn_deposits(zone, biome, center, size, rng, exclude_rects, occupied, bounds)
	var paint := _paint_regions(biome, center, size)
	paint["zone"] = zone
	return paint


static func splat_for(biome: BiomeDefinition, center: Vector3, extent, _rng_seed: int) -> Dictionary:
	return _paint_regions(biome, center, _as_extent(extent))


static func _as_extent(extent) -> Vector2:
	if extent is Vector2:
		return extent
	if extent is Vector2i:
		return Vector2(extent.x, extent.y)
	var side := float(extent)
	return Vector2(side, side)


static func _bounds_rect(center: Vector3, extent: Vector2, inset: float) -> Rect2:
	return Rect2(
		Vector2(center.x - extent.x * 0.5 + inset, center.z - extent.y * 0.5 + inset),
		Vector2(maxf(extent.x - inset * 2.0, 1.0), maxf(extent.y - inset * 2.0, 1.0))
	)


static func _zone_name(biome: BiomeDefinition) -> String:
	var parts := biome.id.split("_")
	var out := ""
	for part in parts:
		if part.is_empty():
			continue
		out += part.capitalize()
	return out if not out.is_empty() else "Biome"


static func _scatter(zone: Node3D, biome: BiomeDefinition, center: Vector3, extent: Vector2) -> void:
	if biome.scatter_id.is_empty() and biome.scatter_profile.is_empty():
		return
	## Shrink scatter slightly so tufts don't sit on the neighbor seam.
	var scatter_extent := Vector2(maxf(extent.x - 1.0, 2.0), maxf(extent.y - 1.0, 2.0))
	_GroundScatter.add(zone, center, maxf(scatter_extent.x, scatter_extent.y), biome.scatter_id, 0.0, biome.scatter_profile, scatter_extent)


static func _spawn_harvestables(
	zone: Node3D,
	biome: BiomeDefinition,
	center: Vector3,
	extent: Vector2,
	rng: RandomNumberGenerator,
	exclude_rects: Array,
	occupied: Array[Vector3],
	bounds: Rect2
) -> void:
	var half := Vector2(bounds.size.x * 0.5, bounds.size.y * 0.5)
	var area := extent.x * extent.y
	var index := 0
	for rule in biome.harvestables:
		var deposit_id := str(rule.get("id", ""))
		if deposit_id.is_empty() or not ResourceCatalog.known(deposit_id):
			continue
		var count := _scaled_count(rng, int(rule.get("min", 1)), int(rule.get("max", 1)), area)
		var spacing := float(rule.get("spacing", 2.5))
		var points := _sample_points(rng, center, half, count, spacing, exclude_rects, occupied, bounds)
		for at in points:
			var node := ResourceNode.new()
			node.name = "%s_%d" % [deposit_id, index]
			node.configure("%s_%s_%d" % [biome.id, deposit_id, index], deposit_id)
			node.position = at
			zone.add_child(node)
			occupied.append(at)
			index += 1


static func _spawn_deposits(
	zone: Node3D,
	biome: BiomeDefinition,
	center: Vector3,
	extent: Vector2,
	rng: RandomNumberGenerator,
	exclude_rects: Array,
	occupied: Array[Vector3],
	bounds: Rect2
) -> void:
	var half := Vector2(bounds.size.x * 0.5, bounds.size.y * 0.5)
	var area := extent.x * extent.y
	var index := 0
	var deposit_pts: Array[Vector3] = []
	for rule in biome.deposits:
		var deposit_id := str(rule.get("id", ""))
		if deposit_id.is_empty() or not GroundDepositCatalog.known(deposit_id):
			continue
		var count := _scaled_count(rng, int(rule.get("min", 1)), int(rule.get("max", 1)), area)
		var spacing := float(rule.get("spacing", 4.0))
		var patch: Vector2i = rule.get("size", Vector2i(1, 1))
		var points := _sample_points(rng, center, half, count, spacing, exclude_rects, deposit_pts, bounds)
		for at in points:
			if _too_close(at, occupied, 1.4):
				continue
			var anchor := Vector2i(floori(at.x - float(patch.x) * 0.5), floori(at.z - float(patch.y) * 0.5))
			var deposit := GroundDeposit.new()
			deposit.name = "%s_%d" % [deposit_id, index]
			deposit.set_footprint(anchor, patch)
			deposit.configure("%s_%s_%d" % [biome.id, deposit_id, index], deposit_id)
			zone.add_child(deposit)
			deposit_pts.append(deposit.position)
			index += 1
	if index == 0 and not biome.deposits.is_empty():
		_force_deposit(zone, biome, center, half, rng, exclude_rects, occupied, deposit_pts, bounds)


static func _force_deposit(
	zone: Node3D,
	biome: BiomeDefinition,
	center: Vector3,
	half: Vector2,
	rng: RandomNumberGenerator,
	exclude_rects: Array,
	occupied: Array[Vector3],
	deposit_pts: Array[Vector3],
	bounds: Rect2
) -> void:
	for rule in biome.deposits:
		var deposit_id := str(rule.get("id", ""))
		if deposit_id.is_empty() or not GroundDepositCatalog.known(deposit_id):
			continue
		var patch: Vector2i = rule.get("size", Vector2i(1, 1))
		var points := _sample_points(rng, center, half, 1, 2.0, exclude_rects, deposit_pts, bounds)
		if points.is_empty():
			var fallback := Vector3(bounds.get_center().x, 0.0, bounds.get_center().y)
			if not _excluded(fallback, exclude_rects):
				points.append(fallback)
		for at in points:
			if _too_close(at, occupied, 1.0):
				continue
			var anchor := Vector2i(floori(at.x - float(patch.x) * 0.5), floori(at.z - float(patch.y) * 0.5))
			var deposit := GroundDeposit.new()
			deposit.name = "%s_forced" % deposit_id
			deposit.set_footprint(anchor, patch)
			deposit.configure("%s_%s_forced" % [biome.id, deposit_id], deposit_id)
			zone.add_child(deposit)
			deposit_pts.append(deposit.position)
			return


static func _scaled_count(rng: RandomNumberGenerator, count_min: int, count_max: int, area: float) -> int:
	## Cap scale so wide biomes (hills) don't explode into a prop carpet.
	var scale := clampf(area / _REF_AREA, 0.6, 1.55)
	var lo := maxi(1, int(round(float(count_min) * scale)))
	var hi := maxi(lo, int(round(float(count_max) * scale)))
	return rng.randi_range(lo, hi)


static func _sample_points(
	rng: RandomNumberGenerator,
	center: Vector3,
	half: Vector2,
	count: int,
	spacing: float,
	exclude_rects: Array,
	occupied: Array[Vector3],
	bounds: Rect2
) -> Array[Vector3]:
	var points: Array[Vector3] = []
	if count <= 0 or half.x <= 0.5 or half.y <= 0.5:
		return points
	var attempts := 0
	var limit := maxi(count * 55, 50)
	while points.size() < count and attempts < limit:
		attempts += 1
		var at := Vector3(
			center.x + rng.randf_range(-half.x, half.x),
			0.0,
			center.z + rng.randf_range(-half.y, half.y)
		)
		if not bounds.has_point(Vector2(at.x, at.z)):
			continue
		if _excluded(at, exclude_rects):
			continue
		if _too_close(at, occupied, spacing) or _too_close(at, points, spacing):
			continue
		points.append(at)
	return points


static func _excluded(at: Vector3, exclude_rects: Array) -> bool:
	for entry in exclude_rects:
		var rect: Rect2 = entry
		if rect.has_point(Vector2(at.x, at.z)):
			return true
	return false


static func _too_close(at: Vector3, others: Array[Vector3], spacing: float) -> bool:
	var min_sq := spacing * spacing
	for other in others:
		if at.distance_squared_to(other) < min_sq:
			return true
	return false


## Exact biome rectangle only — no satellite blobs that spill into neighbors.
static func _paint_regions(biome: BiomeDefinition, center: Vector3, extent: Vector2) -> Dictionary:
	var regions: Array = []
	var asphalt: Array = []
	var forest: Array = []
	var soil: Array = []
	var stain: Array = []
	if biome.asphalt:
		asphalt.append([center, extent])
		regions.append([center, extent, biome.ground_layer])
	else:
		regions.append([center, extent, biome.ground_layer])
	if biome.forest_channel >= 0:
		forest.append([center, extent, biome.forest_channel])
	match biome.id:
		"wasteland":
			## Rare sand pockets on the dirt wasteland carpet.
			soil.append_array(_wasteland_sand_patches(center, extent))
		"hills":
			## Rock carpet with a few small gravel pockets (seeded from the biome center).
			soil.append_array(_hills_gravel_patches(center, extent))


	return {
		"regions": regions,
		"soil": soil,
		"stain": stain,
		"asphalt": asphalt,
		"forest": forest,
	}


## A couple of small sand pockets on the dirt wasteland carpet.
static func _wasteland_sand_patches(center: Vector3, extent: Vector2) -> Array:
	var patches: Array = []
	var half := extent * 0.5
	## Fractions of half-extent keep pockets inside the wasteland rect.
	var spots: Array[Vector2] = [
		Vector2(-0.36, 0.22),
		Vector2(0.40, -0.30),
	]
	var patch_meters := 2.4
	for spot in spots:
		var at := center + Vector3(spot.x * half.x, 0.0, spot.y * half.y)
		patches.append([at, patch_meters, GroundSplat.SOIL_SAND])
	return patches


## A few small gravel pockets on the rock hills carpet.
static func _hills_gravel_patches(center: Vector3, extent: Vector2) -> Array:
	var patches: Array = []
	var half := extent * 0.5
	## Fractions of half-extent keep pockets inside the hills rect.
	var spots: Array[Vector2] = [
		Vector2(-0.42, -0.28),
		Vector2(0.32, -0.38),
		Vector2(0.18, 0.34),
		Vector2(-0.28, 0.40),
		Vector2(0.46, 0.08),
		Vector2(-0.08, -0.06),
	]
	var patch_meters := 3.2
	for spot in spots:
		var at := center + Vector3(spot.x * half.x, 0.0, spot.y * half.y)
		patches.append([at, patch_meters, GroundSplat.SOIL_GRAVEL])
	return patches


## Convert a placed GroundDeposit into a soil or stain splat blob.
static func deposit_splat(deposit: GroundDeposit) -> Dictionary:
	if deposit == null:
		return {}
	var def_id := deposit.definition_id
	var center := deposit.position
	var extent := Vector2(float(deposit.footprint.x), float(deposit.footprint.y))
	match def_id:
		"sand":
			return {"soil": [[center, extent, GroundSplat.SOIL_SAND]]}
		"clay":
			return {"soil": [[center, extent, GroundSplat.SOIL_CLAY]]}
		"gravel":
			return {"soil": [[center, extent, GroundSplat.SOIL_GRAVEL]]}
		"ground_water":
			return {"stain": [[center, extent, GroundSplat.STAIN_WATER]]}
		"natural_gas":
			return {"stain": [[center, extent, GroundSplat.STAIN_GAS]]}
		"crude_oil":
			return {"stain": [[center, extent, GroundSplat.STAIN_OIL]]}
		_:
			return {}
