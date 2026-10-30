extends RefCounted
class_name ExplosionSystem

## Picks the pieces inside a blast and decides which of them the blast can
## actually see. Collection is sorted by component id. Obstruction is resolved
## before any health changes, so destroying one piece cannot open a line of
## sight for another piece in the same blast.

const _RAY_STEPS := 8


static func falloff(distance: float, radius: float) -> float:
	if radius <= 0.0:
		return 0.0
	return clampf(1.0 - distance / radius, 0.0, 1.0)


static func closest_point(box: AABB, point: Vector3) -> Vector3:
	return Vector3(
		clampf(point.x, box.position.x, box.end.x),
		clampf(point.y, box.position.y, box.end.y),
		clampf(point.z, box.position.z, box.end.z)
	)


## Each entry is {id, distance, point}. Destroyed pieces are skipped.
## `point` is the closest point on the piece, which is also where falloff is measured.
static func collect(state: BuildingState, grid: GridSystem, geometry: BuildingGeometry, origin: Vector3, radius: float) -> Array:
	var hits: Array = []
	if radius <= 0.0:
		return hits
	for component: BuildComponent in state.components.values():
		if component.destroyed:
			continue
		var box := geometry.world_aabb(component.kind, grid.component_transform(component))
		var point := closest_point(box, origin)
		var distance := origin.distance_to(point)
		if distance > radius:
			continue
		hits.append({"id": component.id, "distance": distance, "point": point, "center": box.get_center()})
	hits.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["id"]) < int(b["id"]))
	return hits


## The ray must start just outside a piece the blast is touching. Otherwise it
## begins on that face and the corner posts hide the walls to the left and right.
## Falloff still uses the real origin.
static func los_origin(hits: Array, origin: Vector3) -> Vector3:
	var push := Vector3.ZERO
	for hit in hits:
		if float(hit["distance"]) > 0.02:
			continue
		var center: Vector3 = hit["center"]
		var outward := origin - center
		if outward.length_squared() < 0.000001:
			continue
		push += outward.normalized()
	if push.length_squared() < 0.000001:
		return origin
	return origin + push.normalized() * 0.06


## True when a solid piece or the world stands between the blast and the target.
## Windows let the ray through. Posts are only the corner blocks, so they do not
## shield the next wall along the same face. A full wall still blocks the piece behind it.
static func obstructed(state: BuildingState, space: PhysicsDirectSpaceState3D, origin: Vector3, target_point: Vector3, target_id: int) -> bool:
	if space == null or origin.distance_squared_to(target_point) < 0.000001:
		return false
	var exclude: Array[RID] = []
	for _step in _RAY_STEPS:
		var query := PhysicsRayQueryParameters3D.create(origin, target_point)
		query.collision_mask = PhysicsLayers.WORLD | PhysicsLayers.BUILDING
		query.collide_with_areas = false
		query.collide_with_bodies = true
		query.hit_from_inside = false
		query.exclude = exclude
		var hit := space.intersect_ray(query)
		if hit.is_empty():
			return false
		var collider: Object = hit.get("collider")
		var hit_id := _component_id(collider)
		if hit_id == target_id:
			return false
		if hit_id == 0:
			return true
		var blocker := state.get_component(hit_id)
		var blocks := (
			blocker != null
			and not blocker.destroyed
			and blocker.kind != BuildTypes.Kind.POST
			and DamageCatalog.for_kind(blocker.kind).obstructs_blast
		)
		if blocks:
			return true
		if not _exclude_body(exclude, collider, hit):
			return true
	return true


static func _exclude_body(exclude: Array[RID], collider: Object, hit: Dictionary) -> bool:
	var rid := RID()
	if collider is CollisionObject3D:
		rid = (collider as CollisionObject3D).get_rid()
	if not rid.is_valid():
		rid = hit.get("rid", RID())
	if not rid.is_valid():
		return false
	exclude.append(rid)
	return true


static func _component_id(collider: Object) -> int:
	if collider != null and collider.has_meta(&"component_id"):
		return int(collider.get_meta(&"component_id"))
	return 0
